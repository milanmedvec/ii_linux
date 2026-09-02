#!/bin/sh

set -eu

###############################################################################
# Set up hostname/login basics, privilege escalation, and the daily user.
# Assumes apk/apk.static and standard utilities were installed by previous steps.
###############################################################################

HOSTNAME="${HOSTNAME:-iilinux}"
USER_NAME="${USER_NAME:-milan}"
USER_SHELL="${USER_SHELL:-/bin/bash}"
USER_PASSWORD="${USER_PASSWORD:-}"
ALLOW_EMPTY_PASSWORD="${ALLOW_EMPTY_PASSWORD:-0}"

APK="${APK:-apk}"

# Optional override, as a space-separated package list.
USER_MANAGEMENT_PACKAGES="${USER_MANAGEMENT_PACKAGES:-}"

require_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "Run as root" >&2
    exit 1
  fi
}

require_apk() {
  if ! command -v "$APK" >/dev/null 2>&1; then
    echo "apk was not found. Run 3_prepare_system.sh and 4_install_basic_libs.sh first." >&2
    exit 1
  fi
}

apk_install() {
  title="$1"
  packages="$2"

  echo "==> Installing $title"
  echo "$packages"

  # Intentional word splitting: package names are whitespace-separated.
  # shellcheck disable=SC2086
  "$APK" add $packages
}

default_user_management_packages() {
  # doas: small privilege escalation tool, similar purpose to sudo.
  echo doas

  # shadow: usermod, groupmod, chsh, chpasswd, passwd helpers.
  echo shadow
}

mount_if_needed() {
  target="$1"
  type="$2"
  source="$3"
  opts="${4:-}"

  mkdir -p "$target"
  if ! mountpoint -q "$target" 2>/dev/null; then
    if [ -n "$opts" ]; then
      mount -t "$type" -o "$opts" "$source" "$target" || true
    else
      mount -t "$type" "$source" "$target" || true
    fi
  fi
}

setup_runtime_mounts() {
  echo "==> Runtime mounts"

  mkdir -p /dev/pts /dev/shm /tmp/.X11-unix /run
  mount_if_needed /dev/pts devpts devpts
  mount_if_needed /dev/shm tmpfs tmpfs
  mount_if_needed /run tmpfs tmpfs
  chmod 1777 /tmp /dev/shm /tmp/.X11-unix
}

setup_hostname_hosts() {
  echo "==> Hostname and /etc/hosts"

  hostname "$HOSTNAME" || true
  echo "$HOSTNAME" > /etc/hostname

  cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME
::1 localhost ip6-localhost ip6-loopback
EOF
}

remove_alpine_login_banners() {
  echo "==> Removing Alpine login banners"

  : > /etc/issue
  : > /etc/motd
  : > /etc/issue.net 2>/dev/null || true
}

setup_doas() {
  echo "==> doas config"

  mkdir -p /etc/doas.d
  cat > /etc/doas.d/doas.conf <<EOF
permit persist :wheel
EOF
  chmod 0400 /etc/doas.d/doas.conf
}

ensure_group() {
  group="$1"

  if grep -q "^$group:" /etc/group; then
    return 0
  fi

  if command -v groupadd >/dev/null 2>&1; then
    groupadd -r "$group" || true
  else
    addgroup -S "$group" 2>/dev/null || addgroup "$group" 2>/dev/null || true
  fi
}

setup_user() {
  echo "==> User: $USER_NAME"

  if [ ! -x "$USER_SHELL" ]; then
    USER_SHELL=/bin/sh
  fi

  if ! id "$USER_NAME" >/dev/null 2>&1; then
    adduser -D -s "$USER_SHELL" "$USER_NAME"
  elif command -v usermod >/dev/null 2>&1; then
    usermod -s "$USER_SHELL" "$USER_NAME" || true
  fi

  for group in wheel video input audio users render i2c; do
    ensure_group "$group"
    addgroup "$USER_NAME" "$group" 2>/dev/null || true
  done

  if [ -n "$USER_PASSWORD" ]; then
    echo "$USER_NAME:$USER_PASSWORD" | chpasswd
  elif [ "$ALLOW_EMPTY_PASSWORD" = "1" ]; then
    passwd -d "$USER_NAME" || true
  else
    echo "Password not changed. Set it manually with: passwd $USER_NAME"
  fi
}

install_user_management_packages() {
  "$APK" update

  apk_install "user management packages" \
    "${USER_MANAGEMENT_PACKAGES:-$(default_user_management_packages)}"
}

main() {
  require_root
  require_apk

  setup_runtime_mounts
  setup_hostname_hosts

  install_user_management_packages
  remove_alpine_login_banners

  setup_doas
  setup_user

  echo
  echo "User management setup complete."
  echo "User: $USER_NAME"
  echo "Shell: $USER_SHELL"
  echo
  echo "Recommended next step if you did not pass USER_PASSWORD:"
  echo "  passwd $USER_NAME"
}

main "$@"
