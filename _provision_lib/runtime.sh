#!/bin/sh

# Runtime mounts, modules, udev, networking, and Xorg permissions.

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

  mkdir -p /dev/pts /dev/shm /tmp /run /sys/fs/cgroup
  mount_if_needed /dev/pts devpts devpts
  mount_if_needed /tmp tmpfs tmpfs "mode=1777,nosuid,nodev"
  mount_if_needed /dev/shm tmpfs tmpfs
  mount_if_needed /run tmpfs tmpfs
  mount_if_needed /sys/fs/cgroup cgroup2 none
  mkdir -p /tmp/.X11-unix
  chmod 1777 /tmp /dev/shm /tmp/.X11-unix
}

load_runtime_modules() {
  echo "==> Loading runtime kernel modules"

  for module in $RUNTIME_MODULES; do
    modprobe "$module" 2>/dev/null || "$BUSYBOX" modprobe "$module" 2>/dev/null || true
  done
}

load_x11_input_modules() {
  [ -n "$X11_INPUT_MODULES" ] || return 0

  echo "==> Loading X11 input kernel modules"

  for module in $X11_INPUT_MODULES; do
    modprobe "$module" 2>/dev/null || "$BUSYBOX" modprobe "$module" 2>/dev/null || true
  done
}

detect_network_interface() {
  if [ -n "$NET_IFACE" ]; then
    echo "$NET_IFACE"
    return 0
  fi

  for path in /sys/class/net/*; do
    [ -e "$path" ] || continue
    iface="${path##*/}"
    [ "$iface" != "lo" ] || continue
    echo "$iface"
    return 0
  done

  return 1
}

bring_up_dhcp() {
  [ "$SETUP_NETWORK" = "1" ] || return 0

  echo "==> Bringing up network with DHCP"

  ip link set lo up 2>/dev/null || "$BUSYBOX" ip link set lo up 2>/dev/null || true

  if ! iface="$(detect_network_interface)"; then
    echo "No non-loopback network interface found; skipping DHCP." >&2
    return 0
  fi

  echo "Using interface: $iface"
  ip link set "$iface" up 2>/dev/null || "$BUSYBOX" ip link set "$iface" up 2>/dev/null || true

  if [ -x /usr/share/udhcpc/default.script ]; then
    "$BUSYBOX" udhcpc -i "$iface" -s /usr/share/udhcpc/default.script -q -t "$DHCP_TRIES" || true
  else
    "$BUSYBOX" udhcpc -i "$iface" -q -t "$DHCP_TRIES" || true
  fi
}

find_xorg_bin() {
  for path in /usr/lib/Xorg /usr/libexec/Xorg /usr/bin/Xorg /usr/lib/xorg/Xorg /usr/lib/X11/Xorg; do
    [ -x "$path" ] && { echo "$path"; return 0; }
  done
  return 1
}

find_xorg_wrap() {
  for path in /usr/lib/xorg/Xorg.wrap /usr/libexec/Xorg.wrap /usr/bin/Xorg.wrap; do
    [ -x "$path" ] && { echo "$path"; return 0; }
  done
  return 1
}

apply_xorg_device_permissions() {
  [ -e /dev/dri/card0 ] && chgrp video /dev/dri/card0 && chmod 660 /dev/dri/card0 || true
  [ -e /dev/dri/renderD128 ] && chgrp render /dev/dri/renderD128 && chmod 660 /dev/dri/renderD128 || true

  for snd_device in /dev/snd/*; do
    [ -e "$snd_device" ] || continue
    chgrp audio "$snd_device" && chmod 660 "$snd_device" || true
  done

  for video_device in /dev/video* /dev/media*; do
    [ -e "$video_device" ] || continue
    chgrp video "$video_device" && chmod 660 "$video_device" || true
  done

  for i2c_device in /dev/i2c-*; do
    [ -e "$i2c_device" ] || continue
    chgrp i2c "$i2c_device" && chmod 660 "$i2c_device" || true
  done

  for event_device in /dev/input/event*; do
    [ -e "$event_device" ] || continue
    chgrp input "$event_device" && chmod 660 "$event_device" || true
  done

  for tty_device in /dev/tty /dev/tty0 /dev/tty1 /dev/tty2 /dev/tty3 /dev/tty4 /dev/tty5 /dev/tty6; do
    [ -e "$tty_device" ] || continue
    chgrp tty "$tty_device" 2>/dev/null || true
  done
}

configure_i2c_permissions() {
  echo "==> DDC/CI i2c permissions"

  mkdir -p /etc/udev/rules.d
  cat > /etc/udev/rules.d/45-ddcutil-i2c.rules <<'EOF'
SUBSYSTEM=="i2c-dev", KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
EOF

  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=i2c-dev 2>/dev/null || true
    udevadm settle 2>/dev/null || true
  fi
}

setup_xorg_permissions() {
  echo "==> Xorg user permissions"

  mkdir -p /etc/X11
  cat > /etc/X11/Xwrapper.config <<'EOF'
allowed_users=console
needs_root_rights=yes
EOF

  xorg_wrap="$(find_xorg_wrap || true)"
  xorg_bin="$(find_xorg_bin || true)"

  if [ -n "$xorg_wrap" ]; then
    chmod u+s "$xorg_wrap" || true
  elif [ -n "$xorg_bin" ]; then
    chmod u+s "$xorg_bin" || true
  else
    echo "Warning: could not find Xorg binary/wrapper to chmod u+s" >&2
  fi

  configure_i2c_permissions
  apply_xorg_device_permissions
}

setup_runtime_services_now() {
  echo "==> Starting runtime helpers now"

  mkdir -p /run/udev

  load_runtime_modules
  load_x11_input_modules

  if command -v udevd >/dev/null 2>&1; then
    udevd --daemon || true
  fi

  if command -v udevadm >/dev/null 2>&1; then
    udevadm trigger || true
    udevadm settle || true
  fi

  bring_up_dhcp
}
