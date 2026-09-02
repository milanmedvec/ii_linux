#!/bin/sh

# Main orchestration for 6_install_x11_i3_workspace.sh.

configure_timezone() {
  echo "==> Configuring timezone: $TIMEZONE"

  zoneinfo_path="/usr/share/zoneinfo/$TIMEZONE"
  if [ ! -f "$zoneinfo_path" ]; then
    echo "Timezone not found: $zoneinfo_path" >&2
    return 1
  fi

  cp "$zoneinfo_path" /etc/localtime
  echo "$TIMEZONE" > /etc/timezone
}

ensure_dbus_machine_id() {
  echo "==> Ensuring DBus machine-id"

  mkdir -p /var/lib/dbus

  if command -v dbus-uuidgen >/dev/null 2>&1; then
    dbus-uuidgen --ensure=/var/lib/dbus/machine-id 2>/dev/null || {
      if [ ! -s /var/lib/dbus/machine-id ]; then
        dbus-uuidgen > /var/lib/dbus/machine-id
      fi
    }
  elif [ ! -s /var/lib/dbus/machine-id ]; then
    echo "dbus-uuidgen not found; cannot create /var/lib/dbus/machine-id" >&2
    return 1
  fi
}

main() {
  require_root
  require_apk
  require_user
  require_workspace_src

  setup_runtime_mounts

  install_x11_i3_package_groups
  configure_timezone
  ensure_dbus_machine_id
  install_workspace_packages

  setup_workspace
  setup_runtime_services_now
  setup_xorg_permissions

  configure_getty_init

  echo
  echo "X11/i3 workspace setup complete."
  echo "User: $USER_NAME"
  echo
  echo "After reboot: login as $USER_NAME on tty1; startx runs automatically."
}
