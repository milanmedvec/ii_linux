#!/bin/sh

set -eu

###############################################################################
# Install X11/i3 and provision the workspace for the existing daily user.
# Run 5_setup_user_management.sh first.
###############################################################################

HOSTNAME="${HOSTNAME:-iilinux}"
USER_NAME="${USER_NAME:-milan}"

CONFIGURE_GETTY_INIT="${CONFIGURE_GETTY_INIT:-1}"

# Provision payload contains only configuration plus public repo lists.
# Tools/vendor source is cloned during provisioning, not copied from the host.
WORKSPACE_SRC="${WORKSPACE_SRC:-}"
WORKSPACE_TARGET="${WORKSPACE_TARGET:-}"
CLONE_TOOLS="${CLONE_TOOLS:-1}"
CLONE_LIBS="${CLONE_LIBS:-1}"
BUILD_ALTTAB="${BUILD_ALTTAB:-1}"
BUILD_CLIPNOTIFY="${BUILD_CLIPNOTIFY:-1}"
TIMEZONE="${TIMEZONE:-Europe/Prague}"
XKB_LAYOUT="${XKB_LAYOUT:-cz}"

APK="${APK:-apk}"
BUSYBOX="${BUSYBOX:-/bin/busybox}"
GIT="${GIT:-git}"

SETUP_NETWORK="${SETUP_NETWORK:-1}"
NET_IFACE="${NET_IFACE:-}"
DHCP_TRIES="${DHCP_TRIES:-5}"
RUNTIME_MODULES="${RUNTIME_MODULES:-r8169 e1000e virtio_net i915 snd_hda_intel snd_usb_audio uvcvideo i2c-dev}"
X11_INPUT_MODULES="${X11_INPUT_MODULES:-psmouse i2c_hid i2c_hid_acpi}"

# Optional overrides, as space-separated package lists.
RUNTIME_HARDWARE_PACKAGES="${RUNTIME_HARDWARE_PACKAGES:-}"
X11_PACKAGES="${X11_PACKAGES:-}"
I3_PACKAGES="${I3_PACKAGES:-}"
FONT_PACKAGES="${FONT_PACKAGES:-}"
WORKSPACE_DESKTOP_PACKAGES="${WORKSPACE_DESKTOP_PACKAGES:-}"
ALTTAB_BUILD_PACKAGES="${ALTTAB_BUILD_PACKAGES:-}"
CLIPNOTIFY_BUILD_PACKAGES="${CLIPNOTIFY_BUILD_PACKAGES:-}"
INIT_TEMPLATE="${INIT_TEMPLATE:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROVISION_LIB_DIR="${PROVISION_LIB_DIR:-$SCRIPT_DIR/_provision_lib}"

. "$PROVISION_LIB_DIR/common.sh"
. "$PROVISION_LIB_DIR/packages.sh"
. "$PROVISION_LIB_DIR/vendor.sh"
. "$PROVISION_LIB_DIR/workspace.sh"
. "$PROVISION_LIB_DIR/runtime.sh"
. "$PROVISION_LIB_DIR/init.sh"
. "$PROVISION_LIB_DIR/main.sh"

main "$@"
