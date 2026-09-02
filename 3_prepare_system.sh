#!/bin/sh

set -eu

###############################################################################
# Install Alpine apk.static into the currently running minimal system.
###############################################################################

ALPINE_VERSION="${ALPINE_VERSION:-edge}"
ARCH="${ARCH:-}"
BUSYBOX="${BUSYBOX:-/bin/busybox}"
BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-/tmp/apk-bootstrap}"
APK_STATIC="${APK_STATIC:-/sbin/apk.static}"
APK_LINK="${APK_LINK:-/sbin/apk}"

require_busybox() {
  if [ ! -x "$BUSYBOX" ]; then
    echo "BusyBox not found or not executable: $BUSYBOX" >&2
    exit 1
  fi
}

require_root() {
  if [ "$($BUSYBOX id -u)" != "0" ]; then
    echo "Must be run as root." >&2
    exit 1
  fi
}

detect_arch() {
  machine="$($BUSYBOX uname -m)"

  case "$machine" in
    x86_64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    armv7l) echo "armv7" ;;
    armhf|armv6l) echo "armhf" ;;
    *)
      echo "Unsupported architecture: $machine" >&2
      echo "Set ARCH manually, for example: ARCH=x86_64 $0" >&2
      exit 1
      ;;
  esac
}

install_busybox_applets() {
  echo "==> Installing BusyBox applet symlinks"

  "$BUSYBOX" mkdir -p /bin /sbin /usr/bin /usr/sbin
  "$BUSYBOX" --install -s /bin
}

prepare_apk_dirs() {
  echo "==> Preparing apk directories"

  mkdir -p \
    /etc/apk \
    /var/cache/apk \
    /lib/apk/db \
    /sbin \
    "$BOOTSTRAP_DIR"
}

configure_repositories() {
  echo "==> Configuring Alpine repositories: $ALPINE_VERSION/$ARCH"

  REPO_BASE="http://dl-cdn.alpinelinux.org/alpine/$ALPINE_VERSION"
  REPO_MAIN="$REPO_BASE/main/$ARCH"

  {
    echo "$REPO_BASE/main"
    echo "$REPO_BASE/community"
    echo "$REPO_BASE/testing"
  } > /etc/apk/repositories
}

install_udhcpc_config() {
  echo "==> Installing BusyBox udhcpc DHCP config"

  "$BUSYBOX" mkdir -p /usr/share/udhcpc /etc/udhcpc
  "$BUSYBOX" touch /etc/resolv.conf

  cat > /usr/share/udhcpc/default.script <<'EOF'
#!/bin/sh

BB=/bin/busybox
RESOLV_CONF=/etc/resolv.conf
UDHCPC_CONF=/etc/udhcpc/udhcpc.conf

[ -f "$UDHCPC_CONF" ] && . "$UDHCPC_CONF"

case "$1" in
  deconfig)
    "$BB" ip -4 addr flush dev "$interface" 2>/dev/null || true
    ;;

  bound|renew)
    "$BB" ip -4 addr flush dev "$interface" 2>/dev/null || true

    if [ -n "${mask:-}" ]; then
      "$BB" ip -4 addr add "$ip/$mask" ${broadcast:+broadcast "$broadcast"} dev "$interface"
    else
      "$BB" ifconfig "$interface" "$ip" netmask "$subnet" ${broadcast:+broadcast "$broadcast"}
    fi

    "$BB" ip -4 link set dev "$interface" up 2>/dev/null || true

    "$BB" ip -4 route del default dev "$interface" 2>/dev/null || true
    for gateway in $router; do
      "$BB" ip -4 route add default via "$gateway" dev "$interface" 2>/dev/null || \
        "$BB" route add default gw "$gateway" dev "$interface" 2>/dev/null || true
      break
    done

    if [ "${RESOLV_CONF:-}" != "no" ] && [ -n "${dns:-}" ]; then
      : > "$RESOLV_CONF"
      for nameserver in $dns; do
        echo "nameserver $nameserver" >> "$RESOLV_CONF"
      done
    fi
    ;;

  leasefail)
    echo "udhcpc failed to get a DHCP lease" >&2
    ;;

  nak)
    echo "udhcpc received DHCP NAK" >&2
    ;;
esac
EOF

  "$BUSYBOX" chmod +x /usr/share/udhcpc/default.script
  "$BUSYBOX" ln -sf /usr/share/udhcpc/default.script /etc/udhcpc/default.script

  cat > /etc/udhcpc/udhcpc.conf <<'EOF'
# Set RESOLV_CONF="no" to prevent udhcpc from overwriting /etc/resolv.conf.
#RESOLV_CONF="no"
EOF
}

detect_network_interface() {
  if [ -n "${NET_IFACE:-}" ]; then
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

bring_up_network() {
  [ "${SETUP_NETWORK:-1}" = "1" ] || return 0

  echo "==> Bringing up network with DHCP"

  "$BUSYBOX" ip link set lo up 2>/dev/null || true

  if ! iface="$(detect_network_interface)"; then
    echo "No non-loopback network interface found." >&2
    echo "Set NET_IFACE manually after loading the required network driver." >&2
    exit 1
  fi

  echo "Using interface: $iface"
  "$BUSYBOX" ip link set "$iface" up 2>/dev/null || true

  if ! "$BUSYBOX" udhcpc \
    -i "$iface" \
    -s /usr/share/udhcpc/default.script \
    -q \
    -t "${DHCP_TRIES:-5}"; then
    echo "DHCP failed on $iface." >&2
    echo "Check link/cable/driver, or rerun with NET_IFACE=<iface>." >&2
    exit 1
  fi
}

find_apk_tools_static_version() {
  echo "==> Downloading APKINDEX"

  cd "$BOOTSTRAP_DIR"
  rm -f APKINDEX.tar.gz APKINDEX

  "$BUSYBOX" wget \
    -O APKINDEX.tar.gz \
    "$REPO_MAIN/APKINDEX.tar.gz"

  APK_VERSION="$($BUSYBOX tar -xOzf APKINDEX.tar.gz APKINDEX | \
    "$BUSYBOX" awk '
      /^P:apk-tools-static$/ { found=1; next }
      found && /^V:/ { sub(/^V:/, ""); print; exit }
    '
  )"

  if [ -z "$APK_VERSION" ]; then
    echo "Could not find apk-tools-static version in APKINDEX." >&2
    exit 1
  fi

  echo "apk-tools-static version: $APK_VERSION"
}

download_and_install_apk_static() {
  echo "==> Downloading apk-tools-static"

  cd "$BOOTSTRAP_DIR"
  APK_PACKAGE="apk-tools-static-$APK_VERSION.apk"

  rm -rf sbin .PKGINFO .SIGN.* "$APK_PACKAGE"

  "$BUSYBOX" wget \
    -O "$APK_PACKAGE" \
    "$REPO_MAIN/$APK_PACKAGE"

  echo "==> Extracting apk.static"
  "$BUSYBOX" tar -xzf "$APK_PACKAGE"

  if [ ! -f sbin/apk.static ]; then
    echo "Downloaded package did not contain sbin/apk.static" >&2
    exit 1
  fi

  echo "==> Installing $APK_STATIC"
  "$BUSYBOX" cp sbin/apk.static "$APK_STATIC"
  "$BUSYBOX" chmod +x "$APK_STATIC"

  # Temporary convenience symlink. Later, apk-tools package can replace it.
  "$BUSYBOX" ln -sf "$(basename "$APK_STATIC")" "$APK_LINK"
}

main() {
  require_busybox
  require_root

  if [ -z "$ARCH" ]; then
    ARCH="$(detect_arch)"
  fi

  install_busybox_applets
  prepare_apk_dirs
  configure_repositories
  install_udhcpc_config
  bring_up_network
  find_apk_tools_static_version
  download_and_install_apk_static

  echo "==> Verifying apk.static"
  "$APK_STATIC" --version

  echo
  echo "apk.static installed. Next step:"
  echo "  $APK_STATIC --initdb --allow-untrusted add alpine-keys"
  echo "  $APK_STATIC update"
}

main "$@"
