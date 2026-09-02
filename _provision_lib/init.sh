#!/bin/sh

# Install the generated PID 1 script from a readable template.

sed_replacement_escape() {
  printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

find_init_template() {
  if [ -n "${INIT_TEMPLATE:-}" ]; then
    [ -f "$INIT_TEMPLATE" ] && { echo "$INIT_TEMPLATE"; return 0; }
    return 1
  fi

  dir="$(script_dir)"
  for candidate in \
    "$dir/_provision_config/init/sbin-init.sh.in" \
    "$PWD/_provision_config/init/sbin-init.sh.in" \
    "/root/install/_provision_config/init/sbin-init.sh.in"; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

render_init_template() {
  template="$1"

  sed \
    -e "s|@HOSTNAME@|$(sed_replacement_escape "$HOSTNAME")|g" \
    -e "s|@SETUP_NETWORK@|$(sed_replacement_escape "$SETUP_NETWORK")|g" \
    -e "s|@NET_IFACE@|$(sed_replacement_escape "$NET_IFACE")|g" \
    -e "s|@DHCP_TRIES@|$(sed_replacement_escape "$DHCP_TRIES")|g" \
    -e "s|@RUNTIME_MODULES@|$(sed_replacement_escape "$RUNTIME_MODULES")|g" \
    -e "s|@X11_INPUT_MODULES@|$(sed_replacement_escape "$X11_INPUT_MODULES")|g" \
    "$template"
}

configure_getty_init() {
  [ "$CONFIGURE_GETTY_INIT" = "1" ] || return 0

  echo "==> Installing simple tty-login /sbin/init"

  if ! template="$(find_init_template)"; then
    echo "Init template not found. Expected _provision_config/init/sbin-init.sh.in next to this script or set INIT_TEMPLATE=/path/to/template." >&2
    exit 1
  fi

  cp /sbin/init /sbin/init.before-provision 2>/dev/null || true

  tmp_init="/sbin/init.provision.$$"
  render_init_template "$template" > "$tmp_init"
  chmod +x "$tmp_init"
  mv "$tmp_init" /sbin/init
}
