#!/bin/sh

# Package lists and package installation groups for X11/i3 provisioning.

default_runtime_hardware_packages() {
  # udev: device manager for /dev/input, /dev/dri, hotplug devices, etc.
  echo udev

  # dbus: common desktop/session message bus dependency.
  echo dbus

  # dbus-x11: dbus-launch/dbus-run-session integration for X11 sessions.
  echo dbus-x11

  # tzdata: zoneinfo database used to configure /etc/localtime.
  echo tzdata
}

default_x11_packages() {
  # Xorg server.
  echo xorg-server

  # startx/xinit for starting X from tty login.
  echo xinit

  # libinput driver for keyboard/mouse/touchpad.
  echo xf86-input-libinput

  # Mesa DRI drivers for common GPUs and software rendering fallback.
  echo mesa-dri-gallium

  # xrandr display configuration tool.
  echo xrandr

  # Clipboard helper for X11 selections.
  echo xclip

  # X11 automation tool for windows, mouse, and keyboard.
  echo xdotool

  # X11 window control helper.
  echo wmctrl

  # xinput input device inspection/configuration tool.
  echo xinput

  # Keyboard layout helper for X11.
  echo setxkbmap
}

default_i3_packages() {
  # i3 window manager.
  echo i3wm

  # i3 status bar helper.
  echo i3status

  # dmenu launcher.
  echo dmenu

  # X11 screen locker.
  echo i3lock

  # TODO it does not exit on alpine
  # Lock on X idle/suspend events when available.
  #echo xss-lock
}

default_font_packages() {
  # Basic bitmap fonts used by old/simple X clients.
  echo font-misc-misc

  # General-purpose TrueType fonts.
  echo font-dejavu
}

default_workspace_desktop_packages() {
  # Packages used by the workspace i3 config and helper scripts.
  # Some are community/desktop packages; unavailable packages will fail provisioning.
  echo alacritty
  echo tk
  echo brightnessctl
  echo dunst
  echo libnotify
  echo lm-sensors
  echo pamixer
  echo pulseaudio
  echo pulseaudio-utils
  echo yad
  echo ffmpeg
  echo slop
  echo acl
  echo ddcutil
  echo sox
}

default_alttab_build_packages() {
  echo build-base
  echo autoconf
  echo automake
  echo pkgconf
  echo libx11-dev
  echo libxmu-dev
  echo libxft-dev
  echo libxrender-dev
  echo libxrandr-dev
  echo libpng-dev
  echo libxpm-dev
  echo musl-fts-dev
  echo uthash-dev
}

default_clipnotify_build_packages() {
  echo build-base
  echo libxcb-dev
  echo libxfixes-dev
}

install_workspace_packages() {
  apk_install_workspace_packages "workspace desktop packages" \
    "${WORKSPACE_DESKTOP_PACKAGES:-$(default_workspace_desktop_packages)}"

  if [ "$BUILD_ALTTAB" = "1" ]; then
    apk_install_workspace_packages "alttab build packages" \
      "${ALTTAB_BUILD_PACKAGES:-$(default_alttab_build_packages)}"
  fi

  if [ "$BUILD_CLIPNOTIFY" = "1" ]; then
    apk_install_workspace_packages "clipnotify build packages" \
      "${CLIPNOTIFY_BUILD_PACKAGES:-$(default_clipnotify_build_packages)}"
  fi
}

install_x11_i3_package_groups() {
  "$APK" update

  apk_install "runtime/hardware packages" \
    "${RUNTIME_HARDWARE_PACKAGES:-$(default_runtime_hardware_packages)}"

  apk_install "X11 packages" \
    "${X11_PACKAGES:-$(default_x11_packages)}"

  apk_install "i3 packages" \
    "${I3_PACKAGES:-$(default_i3_packages)}"

  apk_install "font packages" \
    "${FONT_PACKAGES:-$(default_font_packages)}"
}
