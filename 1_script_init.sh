#!/bin/sh

set -eu

###############################################################################
# Build the initial II linux directory: kernel, initramfs, rootfs, and GRUB.
###############################################################################

DISTRO_NAME="${DISTRO_NAME:-ii-linux}"
HOSTNAME="${HOSTNAME:-iilinux}"
ROOTFS_LABEL="${ROOTFS_LABEL:-IILINUX}"
EFI_LABEL="${EFI_LABEL:-EFI}"
ROOTFS_ID="${ROOTFS_ID:-$(date -u +%Y%m%d%H%M%S)}"
GRUB_MENU_TITLE="${GRUB_MENU_TITLE:-II linux}"
GRUB_TIMEOUT="${GRUB_TIMEOUT:-3}"

# Do not use nomodeset by default: the provisioned X/i3 system needs KMS GPU drivers.
KERNEL_CMDLINE="${KERNEL_CMDLINE:-rdinit=/init console=tty0 loglevel=7 ignore_loglevel}"
ROOTFS_MARKER_FILE="${ROOTFS_MARKER_FILE:-$DISTRO_NAME.rootfs}"

KERNEL_IMAGE="${KERNEL_IMAGE:-/boot/vmlinuz-linux}"
BUSYBOX_URL="${BUSYBOX_URL:-https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox}"

# Keep initramfs small, but make the installed rootfs hardware-complete.
COPY_ALL_ROOTFS_MODULES="${COPY_ALL_ROOTFS_MODULES:-1}"
COPY_ALL_FIRMWARE="${COPY_ALL_FIRMWARE:-1}"

# Optional overrides, as space-separated module lists.
INITRAMFS_MODULES="${INITRAMFS_MODULES:-}"
ROOTFS_RUNTIME_MODULES="${ROOTFS_RUNTIME_MODULES:-}"
ROOTFS_X11_INPUT_MODULES="${ROOTFS_X11_INPUT_MODULES:-}"
ROOTFS_MODULES="${ROOTFS_MODULES:-}"

BUILD_DIR="${BUILD_DIR:-$DISTRO_NAME}"
DOWNLOADS_DIR="downloads"
KERNEL_DIR="kernel"
INITRAMFS_DIR="initramfs"
ROOTFS_DIR="rootfs"
BOOT_DIR="boot"

KVER="${KVER:-$(uname -r)}"
MODULE_SRC="${MODULE_SRC:-}"
FIRMWARE_SRC="${FIRMWARE_SRC:-}"

require_command() {
  command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
}

require_build_tools() {
  require_command awk
  require_command cpio
  require_command curl
  require_command depmod
  require_command find
  require_command gzip
  require_command modprobe
  require_command sed
  require_command sort
  require_command tr
}

require_kernel_image() {
  if [ ! -f "$KERNEL_IMAGE" ]; then
    echo "Kernel image not found: $KERNEL_IMAGE" >&2
    exit 1
  fi
}

find_module_src() {
  if [ -n "$MODULE_SRC" ]; then
    [ -d "$MODULE_SRC" ] && { cd "$MODULE_SRC" && pwd -P; return 0; }
    echo "MODULE_SRC does not exist: $MODULE_SRC" >&2
    exit 1
  fi

  for candidate in "/usr/lib/modules/$KVER" "/lib/modules/$KVER"; do
    if [ -d "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  echo "Could not find kernel modules for $KVER" >&2
  exit 1
}

find_firmware_src() {
  if [ -n "$FIRMWARE_SRC" ]; then
    [ -d "$FIRMWARE_SRC" ] && { cd "$FIRMWARE_SRC" && pwd -P; return 0; }
    echo "FIRMWARE_SRC does not exist: $FIRMWARE_SRC" >&2
    exit 1
  fi

  for candidate in /usr/lib/firmware /lib/firmware; do
    if [ -d "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

default_initramfs_modules() {
  # Filesystem and disk/controller modules needed before rootfs is mounted.
  echo ext4
  echo nvme
  echo ahci
  echo sd_mod
  echo usb_storage
  echo uas
  echo xhci_pci
  echo xhci_hcd
  echo usbhid
  echo hid_generic
  echo virtio_pci
  echo virtio_blk
}

default_rootfs_runtime_modules() {
  # Network drivers and Intel KMS graphics loaded after switch_root/provisioning.
  echo r8169
  echo e1000e
  echo virtio_net
  echo i915
}

default_rootfs_x11_input_modules() {
  # Input modules useful for Xorg/i3 on laptops and desktop hardware.
  echo psmouse
  echo i2c_hid
  echo i2c_hid_acpi
}

get_initramfs_modules() {
  if [ -n "$INITRAMFS_MODULES" ]; then
    echo "$INITRAMFS_MODULES"
  else
    default_initramfs_modules
  fi
}

get_rootfs_runtime_modules() {
  if [ -n "$ROOTFS_RUNTIME_MODULES" ]; then
    echo "$ROOTFS_RUNTIME_MODULES"
  else
    default_rootfs_runtime_modules
  fi
}

get_rootfs_x11_input_modules() {
  if [ -n "$ROOTFS_X11_INPUT_MODULES" ]; then
    echo "$ROOTFS_X11_INPUT_MODULES"
  else
    default_rootfs_x11_input_modules
  fi
}

get_rootfs_modules() {
  if [ -n "$ROOTFS_MODULES" ]; then
    echo "$ROOTFS_MODULES"
  else
    get_initramfs_modules
    get_rootfs_runtime_modules
    get_rootfs_x11_input_modules
  fi
}

one_line() {
  tr '\n' ' ' | awk '{$1=$1; print}'
}

shell_quote() {
  # Print a POSIX shell-safe single-quoted value without a trailing newline.
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

write_env_var() {
  name="$1"
  value="$2"

  printf '%s=' "$name"
  shell_quote "$value"
  printf '\n'
}

prepare_build_dir() {
  echo "==> Preparing build directory: $BUILD_DIR"

  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"
}

write_build_env() {
  echo "==> Writing build metadata"

  {
    write_env_var DISTRO_NAME "$DISTRO_NAME"
    write_env_var HOSTNAME "$HOSTNAME"
    write_env_var ROOTFS_LABEL "$ROOTFS_LABEL"
    write_env_var EFI_LABEL "$EFI_LABEL"
    write_env_var ROOTFS_ID "$ROOTFS_ID"
    write_env_var GRUB_MENU_TITLE "$GRUB_MENU_TITLE"
    write_env_var GRUB_TIMEOUT "$GRUB_TIMEOUT"
    write_env_var KERNEL_CMDLINE "$KERNEL_CMDLINE"
    write_env_var ROOTFS_MARKER_FILE "$ROOTFS_MARKER_FILE"
    write_env_var COPY_ALL_ROOTFS_MODULES "$COPY_ALL_ROOTFS_MODULES"
    write_env_var COPY_ALL_FIRMWARE "$COPY_ALL_FIRMWARE"
  } > build.env
}

download_busybox() {
  echo "==> Downloading BusyBox"

  mkdir -p "$DOWNLOADS_DIR"
  curl -L "$BUSYBOX_URL" -o "$DOWNLOADS_DIR/busybox"
  chmod +x "$DOWNLOADS_DIR/busybox"
}

copy_kernel() {
  echo "==> Copying kernel"

  mkdir -p "$KERNEL_DIR"
  cp "$KERNEL_IMAGE" "$KERNEL_DIR/vmlinuz"
}

copy_kernel_module_file() {
  source_path="$1"
  target_path="$2"

  mkdir -p "$(dirname "$target_path")"

  case "$source_path" in
    *.ko.zst) zstd -dc "$source_path" > "${target_path%.zst}" ;;
    *.ko.xz)  xz -dc "$source_path" > "${target_path%.xz}" ;;
    *.ko.gz)  gzip -dc "$source_path" > "${target_path%.gz}" ;;
    *.ko)     cp "$source_path" "$target_path" ;;
  esac
}

copy_module_metadata() {
  tree="$1"
  module_dst="$tree/lib/modules/$KVER"

  cp "$MODULE_SRC/modules.order" "$module_dst/" 2>/dev/null || true
  cp "$MODULE_SRC/modules.builtin" "$module_dst/" 2>/dev/null || true
  cp "$MODULE_SRC/modules.builtin.modinfo" "$module_dst/" 2>/dev/null || true

  depmod -b "$tree" "$KVER"
}

prepare_kernel_modules() {
  tree="$1"
  shift

  module_dst="$tree/lib/modules/$KVER"
  mkdir -p "$module_dst"

  for module in "$@"; do
    modprobe --set-version "$KVER" --show-depends "$module" 2>/dev/null || true
  done |
  awk '$1 == "insmod" { print $2 }' |
  sort -u |
  while read -r module_path; do
    [ -n "$module_path" ] || continue

    relative_path="${module_path#$MODULE_SRC/}"

    case "$module_path" in
      *.ko.zst) target="$module_dst/${relative_path%.zst}" ;;
      *.ko.xz)  target="$module_dst/${relative_path%.xz}" ;;
      *.ko.gz)  target="$module_dst/${relative_path%.gz}" ;;
      *.ko)     target="$module_dst/$relative_path" ;;
      *)        continue ;;
    esac

    copy_kernel_module_file "$module_path" "$target"
  done

  copy_module_metadata "$tree"
}

copy_all_kernel_modules() {
  tree="$1"
  module_dst="$tree/lib/modules/$KVER"

  echo "==> Copying all kernel modules for $KVER"
  mkdir -p "$module_dst"

  (
    cd "$MODULE_SRC"
    find . \
      \( -path './build' -o -path './source' \) -prune -o \
      -type f \
      \( -name '*.ko' -o -name '*.ko.zst' -o -name '*.ko.xz' -o -name '*.ko.gz' \) \
      -print
  ) |
  while read -r relative_path; do
    relative_path="${relative_path#./}"
    source_path="$MODULE_SRC/$relative_path"

    case "$relative_path" in
      *.ko.zst) target="$module_dst/${relative_path%.zst}" ;;
      *.ko.xz)  target="$module_dst/${relative_path%.xz}" ;;
      *.ko.gz)  target="$module_dst/${relative_path%.gz}" ;;
      *.ko)     target="$module_dst/$relative_path" ;;
      *)        continue ;;
    esac

    copy_kernel_module_file "$source_path" "$target"
  done

  copy_module_metadata "$tree"
}

copy_all_firmware() {
  tree="$1"

  [ "$COPY_ALL_FIRMWARE" = "1" ] || return 0

  if [ -z "$FIRMWARE_SRC" ]; then
    echo "No firmware directory found; skipping firmware copy."
    return 0
  fi

  echo "==> Copying firmware from $FIRMWARE_SRC"
  mkdir -p "$tree/lib/firmware"
  cp -a "$FIRMWARE_SRC/." "$tree/lib/firmware/"
}

prepare_initramfs_tree() {
  echo "==> Preparing initramfs tree"

  mkdir -p "$INITRAMFS_DIR/bin" "$INITRAMFS_DIR/dev" "$INITRAMFS_DIR/proc" "$INITRAMFS_DIR/sys"
  cp "$DOWNLOADS_DIR/busybox" "$INITRAMFS_DIR/bin/busybox"
  ln -sf busybox "$INITRAMFS_DIR/bin/sh"

  # Intentional word splitting: module names are whitespace-separated.
  # shellcheck disable=SC2046
  prepare_kernel_modules "$INITRAMFS_DIR" $(get_initramfs_modules)
}

write_initramfs_init() {
  echo "==> Writing initramfs /init"

  initramfs_module_list="$(get_initramfs_modules | one_line)"

  cat > "$INITRAMFS_DIR/init" <<EOF
#!/bin/sh

BB=/bin/busybox
INITRAMFS_MODULES="$initramfs_module_list"

\$BB mount -t proc proc /proc
\$BB mount -t sysfs sysfs /sys
\$BB mount -t devtmpfs devtmpfs /dev

for module in \$INITRAMFS_MODULES; do
  \$BB modprobe "\$module" 2>/dev/null || true
done

\$BB mkdir -p /newroot

echo "Searching for $DISTRO_NAME root filesystem..."

i=0
while [ "\$i" -lt 20 ]; do
  for dev in \
    /dev/nvme*n*p* \
    /dev/sd[a-z][0-9]* \
    /dev/vd[a-z][0-9]* \
    /dev/mmcblk*p*
  do
    [ -b "\$dev" ] || continue

    echo "Trying \$dev"

    if \$BB mount -t ext4 "\$dev" /newroot 2>/dev/null; then
      if [ "\$(\$BB cat /newroot/etc/$ROOTFS_MARKER_FILE 2>/dev/null)" = "$ROOTFS_ID" ] && [ -x /newroot/sbin/init ]; then
        echo "Found root filesystem on \$dev"

        \$BB mount --move /proc /newroot/proc
        \$BB mount --move /sys /newroot/sys
        \$BB mount --move /dev /newroot/dev

        exec \$BB switch_root /newroot /sbin/init
      fi

      \$BB umount /newroot
    fi
  done

  i=\$((i + 1))
  \$BB sleep 1
done

echo "Could not find $DISTRO_NAME root filesystem."
exec \$BB sh
EOF

  chmod +x "$INITRAMFS_DIR/init"
}

pack_initramfs() {
  echo "==> Packing initramfs"

  (
    cd "$INITRAMFS_DIR"
    find . -print0 |
      cpio --null --create --format=newc |
      gzip -9
  ) > initramfs.img
}

prepare_rootfs_tree() {
  echo "==> Preparing rootfs tree"

  mkdir -p \
    "$ROOTFS_DIR/bin" \
    "$ROOTFS_DIR/sbin" \
    "$ROOTFS_DIR/etc" \
    "$ROOTFS_DIR/proc" \
    "$ROOTFS_DIR/sys" \
    "$ROOTFS_DIR/dev" \
    "$ROOTFS_DIR/dev/pts" \
    "$ROOTFS_DIR/dev/shm" \
    "$ROOTFS_DIR/run" \
    "$ROOTFS_DIR/tmp/.X11-unix" \
    "$ROOTFS_DIR/root" \
    "$ROOTFS_DIR/lib"

  chmod 1777 "$ROOTFS_DIR/tmp"
  echo "$ROOTFS_ID" > "$ROOTFS_DIR/etc/$ROOTFS_MARKER_FILE"

  cp "$DOWNLOADS_DIR/busybox" "$ROOTFS_DIR/bin/busybox"
  ln -sf busybox "$ROOTFS_DIR/bin/sh"
}

write_rootfs_init() {
  echo "==> Writing rootfs /sbin/init"

  rootfs_runtime_module_list="$(get_rootfs_runtime_modules | one_line)"

  cat > "$ROOTFS_DIR/sbin/init" <<EOF
#!/bin/sh

BB=/bin/busybox
HOSTNAME="$HOSTNAME"
DISTRO_NAME="$DISTRO_NAME"
ROOTFS_RUNTIME_MODULES="$rootfs_runtime_module_list"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export TERM=linux

mount_if_needed() {
  target="\$1"
  type="\$2"
  source="\$3"

  \$BB mkdir -p "\$target"
  if ! \$BB grep -qs " \$target " /proc/mounts 2>/dev/null; then
    \$BB mount -t "\$type" "\$source" "\$target" 2>/dev/null || true
  fi
}

setup_runtime_mounts() {
  \$BB mkdir -p /dev/pts /dev/shm /tmp/.X11-unix /run
  mount_if_needed /dev/pts devpts devpts
  mount_if_needed /dev/shm tmpfs tmpfs
  mount_if_needed /run tmpfs tmpfs
  \$BB chmod 1777 /tmp /dev/shm /tmp/.X11-unix 2>/dev/null || true
}

\$BB mount -t proc proc /proc 2>/dev/null || true
\$BB mount -t sysfs sysfs /sys 2>/dev/null || true
\$BB mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
\$BB mount -t tmpfs tmpfs /tmp 2>/dev/null || true
setup_runtime_mounts

\$BB hostname "\$HOSTNAME"

for module in \$ROOTFS_RUNTIME_MODULES; do
  \$BB modprobe "\$module" 2>/dev/null || true
done

\$BB echo "\$DISTRO_NAME rootfs booted." >/dev/tty1 2>/dev/null || true
\$BB echo "Starting shell on tty1." >/dev/tty1 2>/dev/null || true

cd "\$HOME" 2>/dev/null || true

while true; do
  \$BB setsid sh -c 'exec /bin/sh </dev/tty1 >/dev/tty1 2>&1'
  \$BB sleep 1
done
EOF

  chmod +x "$ROOTFS_DIR/sbin/init"
}

prepare_rootfs_modules() {
  if [ "$COPY_ALL_ROOTFS_MODULES" = "1" ]; then
    copy_all_kernel_modules "$ROOTFS_DIR"
  else
    # Intentional word splitting: module names are whitespace-separated.
    # shellcheck disable=SC2046
    prepare_kernel_modules "$ROOTFS_DIR" $(get_rootfs_modules)
  fi
}

prepare_boot_files() {
  echo "==> Preparing boot files"

  mkdir -p "$BOOT_DIR/grub"
  cp "$KERNEL_DIR/vmlinuz" "$BOOT_DIR/vmlinuz"
  cp initramfs.img "$BOOT_DIR/initramfs.img"

  cat > "$BOOT_DIR/grub/grub.cfg" <<EOF
set timeout=$GRUB_TIMEOUT
set default=0

menuentry "$GRUB_MENU_TITLE" {
  linux /boot/vmlinuz $KERNEL_CMDLINE
  initrd /boot/initramfs.img
}
EOF
}

main() {
  require_build_tools
  require_kernel_image

  MODULE_SRC="$(find_module_src)"
  FIRMWARE_SRC="$(find_firmware_src || true)"

  prepare_build_dir
  write_build_env
  download_busybox
  copy_kernel

  prepare_initramfs_tree
  write_initramfs_init
  pack_initramfs

  prepare_rootfs_tree
  write_rootfs_init
  prepare_rootfs_modules
  copy_all_firmware "$ROOTFS_DIR"

  prepare_boot_files

  echo
  echo "Build complete."
}

main "$@"
