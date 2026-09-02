#!/bin/sh

set -eu

###############################################################################
# Install a minimal package-managed Alpine base using /sbin/apk.static.
###############################################################################

APK_STATIC="${APK_STATIC:-/sbin/apk.static}"
APK="${APK:-/sbin/apk}"
BUSYBOX="${BUSYBOX:-/bin/busybox}"
RESCUE_DIR="${RESCUE_DIR:-/rescue}"

# Optional overrides, as space-separated package lists.
# Example: BASE_PACKAGES="alpine-baselayout busybox apk-tools" sh 4_install_basic_libs.sh
BASE_PACKAGES="${BASE_PACKAGES:-}"
STANDARD_UTIL_PACKAGES="${STANDARD_UTIL_PACKAGES:-}"

require_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "Must be run as root." >&2
    exit 1
  fi
}

require_apk_static() {
  if [ ! -x "$APK_STATIC" ]; then
    echo "apk.static not found or not executable: $APK_STATIC" >&2
    echo "Run 3_prepare_system.sh first." >&2
    exit 1
  fi
}

require_repositories() {
  if [ ! -s /etc/apk/repositories ]; then
    echo "Missing /etc/apk/repositories." >&2
    echo "Run 3_prepare_system.sh first, or create repositories manually." >&2
    exit 1
  fi
}

default_base_packages() {
  # Standard Alpine filesystem layout and base config:
  # /etc/passwd, /etc/group, /etc/profile, /etc/fstab, /etc/os-release, etc.
  echo alpine-baselayout

  # Alpine-packaged BusyBox binary. Kept as rescue/fallback even after full utils.
  echo busybox

  # Ensures /bin/sh is provided correctly by BusyBox/package management.
  echo busybox-binsh

  # Normal non-static apk package manager for daily package operations.
  echo apk-tools

  # Trusted TLS CA bundle for HTTPS downloads, curl, wget, git, npm, browsers, etc.
  echo ca-certificates-bundle
}

default_standard_util_packages() {
  # GNU Bourne Again Shell.
  echo bash

  # Optional interactive completion files for Bash.
  echo bash-completion

  # GNU core tools: ls, cp, mv, rm, chmod, chown, date, cat, etc.
  echo coreutils

  # GNU find and xargs.
  echo findutils

  # Full grep implementation.
  echo grep

  # Full sed implementation.
  echo sed

  # GNU awk.
  echo gawk

  # diff, cmp, diff3, sdiff.
  echo diffutils

  # mount, umount, lsblk, fdisk, blkid, dmesg, login utilities, wipefs, etc.
  echo util-linux

  # Disk partitioning tools used by 7_deploy_to_disk.sh: parted, partprobe.
  echo parted

  # FAT filesystem tools used by 7_deploy_to_disk.sh: mkfs.vfat.
  echo dosfstools

  # ext filesystem tools used by 7_deploy_to_disk.sh: mkfs.ext4.
  echo e2fsprogs

  # ps, top, free, uptime, pgrep, pkill, etc.
  echo procps-ng

  # killall, pstree, fuser.
  echo psmisc

  # Modern ip command and networking tools.
  echo iproute2

  # ping and related IP diagnostic tools.
  echo iputils

  # Full tar implementation.
  echo tar

  # gzip/gunzip/zcat.
  echo gzip

  # zip/unzip.
  echo zip
  echo unzip

  # xz/unxz/xzcat.
  echo xz

  # bzip2/bunzip2/bzcat.
  echo bzip2

  # Pager for man pages/logs/text files.
  echo less

  # Small editor.
  echo nano

  # HTTP client/library tools.
  echo curl

  # Full wget implementation.
  echo wget

  # Source control; also needed later by provisioning clone steps.
  echo git

  # Terminal multiplexer.
  echo tmux

  # Shell history/search tool.
  echo atuin

  # Console file manager.
  echo mc

  # Fuzzy finder.
  echo fzf

  # JSON processor.
  echo jq

  # Text UI dialog utility.
  echo dialog

  # Friendly terminal editor.
  echo micro

  # OCI container runtime; useful from the base tty system.
  echo runc
}

save_rescue_busybox() {
  echo "==> Saving rescue BusyBox"

  if [ ! -x "$BUSYBOX" ]; then
    echo "BusyBox not found or not executable: $BUSYBOX" >&2
    exit 1
  fi

  mkdir -p "$RESCUE_DIR"
  "$BUSYBOX" cp "$BUSYBOX" "$RESCUE_DIR/busybox"
  "$BUSYBOX" chmod +x "$RESCUE_DIR/busybox"
}

init_apk_database_and_keys() {
  echo "==> Initializing apk database and installing Alpine keys"

  mkdir -p /lib/apk/db /var/cache/apk /etc/apk
  "$APK_STATIC" --initdb --allow-untrusted add alpine-keys
}

update_apk_indexes() {
  echo "==> Updating apk indexes"
  "$APK_STATIC" update
}

install_base_packages() {
  echo "==> Installing base packages"

  packages="${BASE_PACKAGES:-$(default_base_packages)}"
  echo "$packages"

  # 3_prepare_system.sh may create /sbin/apk -> apk.static as a temporary helper.
  # Remove it so the real apk-tools package can install /sbin/apk cleanly.
  if [ -L "$APK" ]; then
    rm -f "$APK"
  fi

  # Intentional word splitting: package names are whitespace-separated.
  # shellcheck disable=SC2086
  "$APK_STATIC" add --force-overwrite $packages
}

install_standard_utils() {
  echo "==> Installing standard utilities while keeping BusyBox"

  packages="${STANDARD_UTIL_PACKAGES:-$(default_standard_util_packages)}"
  echo "$packages"

  # Intentional word splitting: package names are whitespace-separated.
  # Use --force-overwrite so full utilities may replace BusyBox applet symlinks.
  # The /bin/busybox binary and busybox package remain installed as rescue/fallback.
  # shellcheck disable=SC2086
  "$APK_STATIC" add --force-overwrite $packages
}

refresh_busybox_applets() {
  echo "==> Refreshing BusyBox applet symlinks"

  if [ -x /bin/busybox ]; then
    /bin/busybox --install -s /bin
  fi
}

verify_install() {
  echo "==> Verifying installation"

  "$APK" --version
  "$APK" info

  echo "==> /etc/passwd"
  cat /etc/passwd
}

main() {
  require_root
  require_apk_static
  require_repositories

  save_rescue_busybox
  init_apk_database_and_keys
  update_apk_indexes
  install_base_packages
  refresh_busybox_applets
  install_standard_utils
  verify_install

  echo
  echo "Base system installed."
}

main "$@"
