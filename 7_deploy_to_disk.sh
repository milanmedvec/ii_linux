#!/bin/sh

set -eu

###############################################################################
# Deploy the currently running II Linux USB/system to another disk.
# Intended use: boot from USB, finish setup, then run this against the internal
# target disk, for example: sh /root/install/7_deploy_to_disk.sh /dev/sda
###############################################################################

DST_DISK="${1:-${DST_DISK:-}}"
SRC_ROOT="${SRC_ROOT:-}"
SRC_EFI="${SRC_EFI:-}"

EFI_LABEL="${EFI_LABEL:-EFI}"
ROOT_LABEL="${ROOT_LABEL:-IILINUX}"

MOUNT_ROOT="${MOUNT_ROOT:-/mnt/ii-deploy-root}"
MOUNT_SRC_EFI="${MOUNT_SRC_EFI:-/mnt/ii-deploy-src-efi}"

DST_EFI=""
DST_ROOT=""
SRC_DISK=""
SRC_EFI_MOUNT=""
MOUNTED_SRC_EFI="0"
MOUNTED_DST_EFI="0"
MOUNTED_DST_ROOT="0"

usage() {
  echo "Usage: $0 DST_DISK"
  echo "Example: sh $0 /dev/sda"
  echo
  echo "Optional overrides:"
  echo "  SRC_ROOT=/dev/sdX2 SRC_EFI=/dev/sdX1 DST_DISK=/dev/nvme0n1 sh $0"
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "Run as root" >&2
    exit 1
  fi
}

require_command() {
  command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
}

require_tools() {
  require_command awk
  require_command chmod
  require_command mkdir
  require_command mkfs.ext4
  require_command mkfs.vfat
  require_command mount
  require_command parted
  require_command rm
  require_command sync
  require_command tar
  require_command umount
  require_command wipefs
}

part_path() {
  disk="$1"
  partition_number="$2"

  case "$disk" in
    *[0-9]) echo "${disk}p$partition_number" ;;
    *) echo "${disk}$partition_number" ;;
  esac
}

parent_disk() {
  partition="$1"

  if command -v lsblk >/dev/null 2>&1; then
    parent="$(lsblk -no PKNAME "$partition" 2>/dev/null | awk 'NF { print "/dev/" $1; exit }')"
    if [ -n "$parent" ]; then
      echo "$parent"
      return 0
    fi
  fi

  echo "$partition" | awk '{ sub(/p?[0-9]+$/, ""); print }'
}

find_mount_source() {
  mount_point="$1"

  if command -v findmnt >/dev/null 2>&1; then
    findmnt -n -o SOURCE "$mount_point" 2>/dev/null | awk 'NF { print; exit }'
    return 0
  fi

  awk -v mount_point="$mount_point" '$2 == mount_point { print $1; exit }' /proc/mounts
}

detect_source_root() {
  if [ -z "$SRC_ROOT" ]; then
    SRC_ROOT="$(find_mount_source /)"
  fi

  if [ ! -b "$SRC_ROOT" ]; then
    echo "Could not detect source root block device. Set SRC_ROOT=/dev/..." >&2
    echo "Detected: ${SRC_ROOT:-<empty>}" >&2
    exit 1
  fi

  SRC_DISK="$(parent_disk "$SRC_ROOT")"
}

detect_source_efi() {
  mounted_efi="$(find_mount_source /boot/efi || true)"

  if [ -z "$SRC_EFI" ] && [ -n "$mounted_efi" ] && [ -b "$mounted_efi" ]; then
    SRC_EFI="$mounted_efi"
    SRC_EFI_MOUNT="/boot/efi"
    return 0
  fi

  if [ -z "$SRC_EFI" ]; then
    SRC_EFI="$(part_path "$SRC_DISK" 1)"
  fi

  if [ ! -b "$SRC_EFI" ]; then
    echo "Could not detect source EFI block device. Set SRC_EFI=/dev/..." >&2
    echo "Detected: ${SRC_EFI:-<empty>}" >&2
    exit 1
  fi
}

require_target_disk() {
  if [ -z "$DST_DISK" ]; then
    usage >&2
    exit 1
  fi

  if [ ! -b "$DST_DISK" ]; then
    echo "Not a block device: $DST_DISK" >&2
    exit 1
  fi

  DST_EFI="$(part_path "$DST_DISK" 1)"
  DST_ROOT="$(part_path "$DST_DISK" 2)"
}

require_safe_source_target() {
  if [ "$DST_DISK" = "$SRC_DISK" ]; then
    echo "Refusing to deploy source disk onto itself: $DST_DISK" >&2
    exit 1
  fi

  if [ "$DST_EFI" = "$SRC_EFI" ] || [ "$DST_ROOT" = "$SRC_ROOT" ]; then
    echo "Refusing to overwrite a source partition." >&2
    exit 1
  fi
}

confirm_disk_wipe() {
  echo "Source disk     : $SRC_DISK"
  echo "Source EFI      : $SRC_EFI"
  echo "Source root     : $SRC_ROOT"
  echo "Target disk     : $DST_DISK"
  echo "Target EFI      : $DST_EFI"
  echo "Target root     : $DST_ROOT"
  echo "EFI label       : $EFI_LABEL"
  echo "Root label      : $ROOT_LABEL"
  echo
  echo "WARNING: this will wipe and format $DST_DISK."
  echo "Type YES to continue:"
  read -r answer

  case "$answer" in
    YES) echo "Deploying to $DST_DISK..." ;;
    *) exit 0 ;;
  esac
}

cleanup() {
  set +e
  sync

  if [ "$MOUNTED_DST_EFI" = "1" ]; then
    umount "$MOUNT_ROOT/boot/efi"
  fi

  if [ "$MOUNTED_SRC_EFI" = "1" ]; then
    umount "$MOUNT_SRC_EFI"
  fi

  if [ "$MOUNTED_DST_ROOT" = "1" ]; then
    umount "$MOUNT_ROOT"
  fi

  sync
}

unmount_target_disk() {
  echo "==> Unmounting target disk partitions"

  # Intentional globbing: unmount any auto-mounted partition from the target disk.
  umount "${DST_DISK}"* 2>/dev/null || true
}

partition_disk() {
  echo "==> Partitioning $DST_DISK"

  wipefs -a "$DST_DISK"

  parted -s "$DST_DISK" mklabel gpt
  parted -s "$DST_DISK" mkpart ESP fat32 1MiB 513MiB
  parted -s "$DST_DISK" set 1 esp on
  parted -s "$DST_DISK" mkpart root ext4 513MiB 100%

  partprobe "$DST_DISK" 2>/dev/null || true
  udevadm settle 2>/dev/null || true
  sleep 1
}

wait_for_partitions() {
  echo "==> Waiting for target partition devices"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -b "$DST_EFI" ] && [ -b "$DST_ROOT" ] && return 0
    sleep 1
  done

  echo "Partition devices did not appear: $DST_EFI $DST_ROOT" >&2
  exit 1
}

format_partitions() {
  echo "==> Formatting target partitions"

  mkfs.vfat -F32 -n "$EFI_LABEL" "$DST_EFI"
  mkfs.ext4 -F -L "$ROOT_LABEL" "$DST_ROOT"
}

mount_target_root() {
  echo "==> Mounting target root"

  mkdir -p "$MOUNT_ROOT"
  mount "$DST_ROOT" "$MOUNT_ROOT"
  MOUNTED_DST_ROOT="1"
}

copy_rootfs() {
  echo "==> Copying running root filesystem"

  (
    cd /
    tar --one-file-system \
      --exclude='./dev' \
      --exclude='./proc' \
      --exclude='./sys' \
      --exclude='./run' \
      --exclude='./tmp' \
      --exclude='./mnt' \
      --exclude='./media' \
      --exclude='./lost+found' \
      -cpf - .
  ) | tar -xpf - -C "$MOUNT_ROOT"
}

mount_source_efi_if_needed() {
  if [ -n "$SRC_EFI_MOUNT" ]; then
    return 0
  fi

  echo "==> Mounting source EFI"

  mkdir -p "$MOUNT_SRC_EFI"
  mount "$SRC_EFI" "$MOUNT_SRC_EFI"
  SRC_EFI_MOUNT="$MOUNT_SRC_EFI"
  MOUNTED_SRC_EFI="1"
}

copy_efi() {
  echo "==> Copying EFI system partition"

  mount_source_efi_if_needed

  mkdir -p "$MOUNT_ROOT/boot/efi"
  mount "$DST_EFI" "$MOUNT_ROOT/boot/efi"
  MOUNTED_DST_EFI="1"

  tar -C "$SRC_EFI_MOUNT" -cpf - . | tar -xpf - -C "$MOUNT_ROOT/boot/efi"
}

prepare_runtime_dirs() {
  echo "==> Preparing runtime directories on target"

  mkdir -p \
    "$MOUNT_ROOT/proc" \
    "$MOUNT_ROOT/sys" \
    "$MOUNT_ROOT/dev" \
    "$MOUNT_ROOT/dev/pts" \
    "$MOUNT_ROOT/dev/shm" \
    "$MOUNT_ROOT/run" \
    "$MOUNT_ROOT/tmp" \
    "$MOUNT_ROOT/tmp/.X11-unix" \
    "$MOUNT_ROOT/boot/efi"

  chmod 1777 "$MOUNT_ROOT/tmp" "$MOUNT_ROOT/dev/shm" "$MOUNT_ROOT/tmp/.X11-unix"
}

main() {
  require_root
  require_tools
  require_target_disk
  detect_source_root
  detect_source_efi
  require_safe_source_target
  confirm_disk_wipe

  trap cleanup EXIT

  unmount_target_disk
  partition_disk
  wait_for_partitions
  format_partitions
  mount_target_root
  copy_rootfs
  copy_efi
  prepare_runtime_dirs

  cleanup
  trap - EXIT

  echo
  echo "Deployment complete: $DST_DISK"
  echo "Remove the USB, then boot from the target disk."
}

main "$@"
