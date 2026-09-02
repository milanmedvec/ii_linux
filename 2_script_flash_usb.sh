#!/bin/sh

set -eu

###############################################################################
# Flash a prepared II linux build directory to a USB/disk device.
###############################################################################

BUILD_DIR="${1:-}"
DISK="${2:-}"
BUILD_ENV=""
SCRIPT_DIR=""
MOUNT_DIR=""
EFI=""
ROOT=""

INSTALL_SCRIPTS="${INSTALL_SCRIPTS:-3_prepare_system.sh 4_install_basic_libs.sh 5_setup_user_management.sh 6_install_x11_i3_workspace.sh 7_deploy_to_disk.sh}"
PROVISION_CONFIG_DIR="${PROVISION_CONFIG_DIR:-_provision_config}"
PROVISION_LIB_DIR="${PROVISION_LIB_DIR:-_provision_lib}"

usage() {
  echo "Usage: $0 BUILD_DIR DISK"
  echo "Example: sudo $0 ii-linux /dev/sdX"
}

require_args() {
  if [ "$#" -ne 2 ]; then
    usage >&2
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
  require_command chmod
  require_command cp
  require_command grub-install
  require_command mkdir
  require_command mkfs.ext4
  require_command mkfs.vfat
  require_command mount
  require_command mountpoint
  require_command parted
  require_command rm
  require_command sync
  require_command tar
  require_command umount
  require_command wipefs
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "Must be run as root." >&2
    exit 1
  fi
}

script_dir() {
  cd "$(dirname "$0")" && pwd -P
}

load_build_env() {
  BUILD_ENV="$BUILD_DIR/build.env"

  if [ ! -d "$BUILD_DIR" ]; then
    echo "Build directory does not exist: $BUILD_DIR" >&2
    exit 1
  fi

  if [ ! -f "$BUILD_ENV" ]; then
    echo "Build metadata not found: $BUILD_ENV" >&2
    echo "Run 1_script_init.sh first, or pass the correct build directory." >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  . "$BUILD_ENV"

  : "${DISTRO_NAME:?Missing DISTRO_NAME in $BUILD_ENV}"
  : "${HOSTNAME:?Missing HOSTNAME in $BUILD_ENV}"
  : "${ROOTFS_LABEL:?Missing ROOTFS_LABEL in $BUILD_ENV}"
  : "${EFI_LABEL:?Missing EFI_LABEL in $BUILD_ENV}"
  ROOTFS_ID="${ROOTFS_ID:-$DISTRO_NAME}"
  : "${GRUB_MENU_TITLE:?Missing GRUB_MENU_TITLE in $BUILD_ENV}"
  : "${ROOTFS_MARKER_FILE:?Missing ROOTFS_MARKER_FILE in $BUILD_ENV}"

  MOUNT_DIR="${MOUNT_DIR:-/mnt/$HOSTNAME}"
}

require_target_disk() {
  if [ ! -b "$DISK" ]; then
    echo "Not a block device: $DISK" >&2
    exit 1
  fi
}

require_build_artifacts() {
  if [ ! -f "$BUILD_DIR/boot/vmlinuz" ]; then
    echo "Missing prepared kernel: $BUILD_DIR/boot/vmlinuz" >&2
    echo "Run 1_script_init.sh again to prepare boot files." >&2
    exit 1
  fi

  if [ ! -f "$BUILD_DIR/boot/initramfs.img" ]; then
    echo "Missing prepared initramfs: $BUILD_DIR/boot/initramfs.img" >&2
    echo "Run 1_script_init.sh again to prepare boot files." >&2
    exit 1
  fi

  if [ ! -f "$BUILD_DIR/boot/grub/grub.cfg" ]; then
    echo "Missing prepared GRUB config: $BUILD_DIR/boot/grub/grub.cfg" >&2
    echo "Run 1_script_init.sh again to prepare boot files." >&2
    exit 1
  fi

  if [ ! -d "$BUILD_DIR/rootfs" ]; then
    echo "Missing rootfs directory: $BUILD_DIR/rootfs" >&2
    exit 1
  fi
}

require_install_payload() {
  SCRIPT_DIR="$(script_dir)"

  for script in $INSTALL_SCRIPTS; do
    if [ ! -f "$SCRIPT_DIR/$script" ]; then
      echo "Missing install helper script: $SCRIPT_DIR/$script" >&2
      exit 1
    fi
  done

  if [ ! -d "$SCRIPT_DIR/$PROVISION_CONFIG_DIR" ]; then
    echo "Missing provision config payload: $SCRIPT_DIR/$PROVISION_CONFIG_DIR" >&2
    exit 1
  fi

  if [ ! -d "$SCRIPT_DIR/$PROVISION_LIB_DIR" ]; then
    echo "Missing provision library payload: $SCRIPT_DIR/$PROVISION_LIB_DIR" >&2
    exit 1
  fi
}

confirm_disk_wipe() {
  echo "Build directory : $BUILD_DIR"
  echo "Distro name     : $DISTRO_NAME"
  echo "Hostname        : $HOSTNAME"
  echo "EFI label       : $EFI_LABEL"
  echo "Rootfs label    : $ROOTFS_LABEL"
  echo "Rootfs marker   : /etc/$ROOTFS_MARKER_FILE = $ROOTFS_ID"
  echo "Target disk     : $DISK"
  echo
  echo "WARNING: this will wipe and format $DISK."
  echo "Type YES to continue:"
  read -r answer

  case "$answer" in
    YES) echo "Wiping and formatting $DISK..." ;;
    *) exit 0 ;;
  esac
}

part_path() {
  partition_number="$1"

  case "$DISK" in
    *[0-9]) echo "${DISK}p$partition_number" ;;
    *) echo "${DISK}$partition_number" ;;
  esac
}

cleanup() {
  set +e
  sync

  if [ -n "$MOUNT_DIR" ] && mountpoint -q "$MOUNT_DIR/boot/efi" 2>/dev/null; then
    umount "$MOUNT_DIR/boot/efi"
  fi

  if [ -n "$MOUNT_DIR" ] && mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
    umount "$MOUNT_DIR"
  fi

  sync
}

set_partition_paths() {
  EFI="$(part_path 1)"
  ROOT="$(part_path 2)"
}

unmount_target_disk() {
  echo "==> Unmounting target disk partitions"

  # Intentional globbing: unmount any auto-mounted partition from the target disk.
  umount "${DISK}"* 2>/dev/null || true
}

partition_disk() {
  echo "==> Partitioning $DISK"

  wipefs -a "$DISK"

  parted -s "$DISK" mklabel gpt
  parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
  parted -s "$DISK" set 1 esp on
  parted -s "$DISK" mkpart root ext4 513MiB 100%

  partprobe "$DISK" 2>/dev/null || true
  udevadm settle 2>/dev/null || true
  sleep 1
}

wait_for_partitions() {
  echo "==> Waiting for partition devices"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -b "$EFI" ] && [ -b "$ROOT" ] && return 0
    sleep 1
  done

  echo "Partition devices did not appear: $EFI $ROOT" >&2
  exit 1
}

format_partitions() {
  echo "==> Formatting partitions"

  mkfs.vfat -F32 -n "$EFI_LABEL" "$EFI"
  mkfs.ext4 -F -L "$ROOTFS_LABEL" "$ROOT"
}

mount_rootfs() {
  echo "==> Mounting rootfs"

  mkdir -p "$MOUNT_DIR"
  mount "$ROOT" "$MOUNT_DIR"
}

copy_rootfs() {
  echo "==> Copying rootfs"

  (
    cd "$BUILD_DIR/rootfs"
    tar --exclude='./rootfs.tar' -cpf - .
  ) | tar -xpf - -C "$MOUNT_DIR"
}

prepare_runtime_dirs() {
  echo "==> Preparing rootfs directories"

  mkdir -p \
    "$MOUNT_DIR/proc" \
    "$MOUNT_DIR/sys" \
    "$MOUNT_DIR/dev" \
    "$MOUNT_DIR/dev/pts" \
    "$MOUNT_DIR/dev/shm" \
    "$MOUNT_DIR/run" \
    "$MOUNT_DIR/tmp/.X11-unix" \
    "$MOUNT_DIR/boot" \
    "$MOUNT_DIR/etc"

  chmod 1777 "$MOUNT_DIR/tmp"
  echo "$ROOTFS_ID" > "$MOUNT_DIR/etc/$ROOTFS_MARKER_FILE"
}

copy_boot_files() {
  echo "==> Copying boot files"

  cp -a "$BUILD_DIR/boot/." "$MOUNT_DIR/boot/"
}

install_helper_scripts() {
  echo "==> Installing helper scripts"

  mkdir -p "$MOUNT_DIR/root/install"

  for script in $INSTALL_SCRIPTS; do
    cp "$SCRIPT_DIR/$script" "$MOUNT_DIR/root/install/$script"
    chmod +x "$MOUNT_DIR/root/install/$script"
  done

  rm -rf "$MOUNT_DIR/root/install/$PROVISION_CONFIG_DIR"
  cp -a "$SCRIPT_DIR/$PROVISION_CONFIG_DIR" "$MOUNT_DIR/root/install/$PROVISION_CONFIG_DIR"

  rm -rf "$MOUNT_DIR/root/install/$PROVISION_LIB_DIR"
  cp -a "$SCRIPT_DIR/$PROVISION_LIB_DIR" "$MOUNT_DIR/root/install/$PROVISION_LIB_DIR"
}

install_grub() {
  echo "==> Installing GRUB"

  mkdir -p "$MOUNT_DIR/boot/efi"
  mount "$EFI" "$MOUNT_DIR/boot/efi"

  grub-install \
    --target=x86_64-efi \
    --efi-directory="$MOUNT_DIR/boot/efi" \
    --boot-directory="$MOUNT_DIR/boot" \
    --removable \
    --recheck
}

main() {
  require_args "$@"
  require_tools
  require_root
  load_build_env
  require_target_disk
  require_build_artifacts
  require_install_payload
  confirm_disk_wipe

  set_partition_paths
  trap cleanup EXIT

  unmount_target_disk
  partition_disk
  wait_for_partitions
  format_partitions

  mount_rootfs
  copy_rootfs
  prepare_runtime_dirs
  copy_boot_files
  install_helper_scripts
  install_grub

  cleanup
  trap - EXIT

  echo
  echo "Installed $DISTRO_NAME to $DISK"
}

main "$@"
