#!/bin/sh

# User workspace, shell, X11, and i3 configuration.

link_user_file() {
  source_path="$1"
  target_path="$2"

  [ -e "$source_path" ] || return 0

  mkdir -p "$(dirname "$target_path")"
  rm -f "$target_path"
  ln -s "$source_path" "$target_path"
  chown -h "$USER_NAME:$USER_NAME" "$target_path" 2>/dev/null || true
}

install_workspace_tree() {
  source_payload="$1"
  user_home="/home/$USER_NAME"
  target_workspace="${WORKSPACE_TARGET:-$user_home/_workdir/workspace}"

  rm -rf "$target_workspace/bin" "$target_workspace/conf"

  mkdir -p \
    "$target_workspace/bin" \
    "$target_workspace/tools" \
    "$target_workspace/lib" \
    "$target_workspace/vendor/patches"

  cp -a "$source_payload/conf" "$target_workspace/conf"

  if [ -d "$source_payload/tools" ]; then
    mkdir -p "$target_workspace/tools"
    cp -a "$source_payload/tools/." "$target_workspace/tools/"
  fi

  if [ -d "$source_payload/lib" ]; then
    mkdir -p "$target_workspace/lib"
    cp -a "$source_payload/lib/." "$target_workspace/lib/"
  fi

  if [ -d "$source_payload/vendor/alttab/patches" ]; then
    rm -rf "$target_workspace/vendor/patches/alttab"
    mkdir -p "$target_workspace/vendor/patches/alttab"
    cp -a "$source_payload/vendor/alttab/patches/." "$target_workspace/vendor/patches/alttab/"
  fi

  if [ -d "$source_payload/vendor/clipnotify/patches" ]; then
    rm -rf "$target_workspace/vendor/patches/clipnotify"
    mkdir -p "$target_workspace/vendor/patches/clipnotify"
    cp -a "$source_payload/vendor/clipnotify/patches/." "$target_workspace/vendor/patches/clipnotify/"
  fi

  echo "$target_workspace"
}

clone_tool_repositories() {
  workspace="$1"
  repos_file="$workspace/tools/repos.list"
  tools_root="$workspace/tools/repos"

  [ "$CLONE_TOOLS" = "1" ] || return 0
  [ -f "$repos_file" ] || return 0

  echo "==> Cloning public workspace tools"
  mkdir -p "$tools_root"

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac

    # repos.list format: name url [ref]
    # shellcheck disable=SC2086
    set -- $line
    repo_name="$1"
    repo_url="$2"
    repo_ref="${3:-}"

    clone_or_update_repo "$repo_url" "$tools_root/$repo_name" "$repo_ref"
  done < "$repos_file"
}

clone_lib_repositories() {
  workspace="$1"
  repos_file="$workspace/lib/repos.list"

  [ "$CLONE_LIBS" = "1" ] || return 0
  [ -f "$repos_file" ] || return 0

  echo "==> Cloning public workspace support libraries"

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac

    # repos.list format: path url [ref]
    # shellcheck disable=SC2086
    set -- $line
    repo_path="$1"
    repo_url="$2"
    repo_ref="${3:-}"

    clone_or_update_repo "$repo_url" "$workspace/$repo_path" "$repo_ref"
  done < "$repos_file"
}

link_workspace_tool_commands() {
  workspace="$1"
  tools_root="$workspace/tools/repos"
  workspace_bin="$workspace/bin"

  [ -d "$tools_root" ] || return 0

  echo "==> Linking tool commands into workspace/bin"
  mkdir -p "$workspace_bin"

  find "$tools_root" -mindepth 3 -maxdepth 3 -path '*/bin/*' -type f | sort |
  while IFS= read -r repo_file; do
    [ -x "$repo_file" ] || chmod +x "$repo_file" 2>/dev/null || true
    [ -x "$repo_file" ] || continue

    repo_name="$(basename "$(dirname "$(dirname "$repo_file")")")"
    command_name="$(basename "$repo_file")"
    link_path="$workspace_bin/$command_name"
    link_target="../tools/repos/$repo_name/bin/$command_name"

    rm -f "$link_path"
    ln -s "$link_target" "$link_path"
  done
}

write_workspace_profile() {
  user_home="/home/$USER_NAME"

  cat > "$user_home/.profile" <<'EOF'
# II linux user session setup.

# Minimal non-systemd systems may not create XDG_RUNTIME_DIR for user sessions.
# Use a per-UID tmp directory until a login manager/PAM service owns /run/user/$UID.
user_id="$(id -u 2>/dev/null || echo "${USER:-user}")"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$user_id}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

# Workspace environment.
if [ -r "$HOME/_workdir/workspace/conf/.profile" ]; then
  . "$HOME/_workdir/workspace/conf/.profile"
fi
EOF

  cat >> "$user_home/.profile" <<'EOF'

# Start X/i3 automatically after tty1 login.
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ] && command -v startx >/dev/null 2>&1; then
  exec startx
fi
EOF

  cp "$user_home/.profile" "$user_home/.xprofile"
  chown "$USER_NAME:$USER_NAME" "$user_home/.profile" "$user_home/.xprofile"
}

write_workspace_bash_profile() {
  user_home="/home/$USER_NAME"

  cat > "$user_home/.bash_profile" <<'EOF'
# II linux bash login setup.
[ -r "$HOME/.profile" ] && . "$HOME/.profile"
[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"
EOF

  chown "$USER_NAME:$USER_NAME" "$user_home/.bash_profile"
}

write_workspace_xinitrc() {
  user_home="/home/$USER_NAME"

  cat > "$user_home/.xinitrc" <<'EOF'
#!/bin/sh

[ -r "$HOME/.profile" ] && . "$HOME/.profile"

# Do not inherit a stale DBus socket from login/profile state.
unset DBUS_SESSION_BUS_ADDRESS

export TERMINAL=alacritty
exec dbus-run-session -- i3
EOF

  chmod +x "$user_home/.xinitrc"
  chown "$USER_NAME:$USER_NAME" "$user_home/.xinitrc"
}

write_workspace_bashrc() {
  user_home="/home/$USER_NAME"

  cat > "$user_home/.bashrc" <<'EOF'
# II linux interactive bash setup.

case $- in
  *i*) ;;
  *) return ;;
esac

if [ -r "$HOME/_workdir/workspace/conf/.bash_aliases" ]; then
  . "$HOME/_workdir/workspace/conf/.bash_aliases"
fi
EOF

  chown "$USER_NAME:$USER_NAME" "$user_home/.bashrc"
}

write_workspace_browser_desktop() {
  workspace="$1"
  user_home="/home/$USER_NAME"
  source_desktop="$workspace/tools/repos/tool_browser_selector/share/applications/browser.desktop"
  target_desktop="$user_home/.local/share/applications/browser.desktop"

  [ -e "$source_desktop" ] || return 0

  mkdir -p "$(dirname "$target_desktop")"
  cp "$source_desktop" "$target_desktop"
  chown "$USER_NAME:$USER_NAME" "$target_desktop"
}

install_workspace_i3_config() {
  workspace="$1"
  user_home="/home/$USER_NAME"
  source_config="$workspace/conf/.config/i3/config"
  target_config="$user_home/.config/i3/config"

  [ -e "$source_config" ] || return 0

  mkdir -p "$user_home/.config/i3"

  cp "$source_config" "$target_config"

  cat >> "$target_config" <<EOF

# II linux local session defaults.
exec --no-startup-id sh -c 'if command -v pulseaudio >/dev/null 2>&1; then pulseaudio --start; fi'
exec --no-startup-id sh -c 'if command -v setxkbmap >/dev/null 2>&1; then setxkbmap $XKB_LAYOUT; fi'
EOF

  chown "$USER_NAME:$USER_NAME" "$target_config"
}

setup_workspace() {
  if ! source_workspace="$(find_workspace_src)"; then
    echo "Provision config source not found. Set WORKSPACE_SRC=/path/to/_provision_config." >&2
    exit 1
  fi

  echo "==> Workspace provisioning from $source_workspace"

  user_home="/home/$USER_NAME"
  workspace="$(install_workspace_tree "$source_workspace")"

  clone_lib_repositories "$workspace"
  clone_tool_repositories "$workspace"
  link_workspace_tool_commands "$workspace"
  setup_clipnotify_vendor "$source_workspace" "$workspace"
  setup_alttab_vendor "$source_workspace" "$workspace"

  mkdir -p \
    "$user_home/.config/atuin" \
    "$user_home/.config/alacritty" \
    "$user_home/.config/mc" \
    "$user_home/.local/share/applications" \
    "$user_home/.tmux"

  write_workspace_profile
  write_workspace_bash_profile
  write_workspace_xinitrc
  write_workspace_bashrc

  link_user_file "$workspace/conf/.gitconfig" "$user_home/.gitconfig"
  link_user_file "$workspace/conf/.nanorc" "$user_home/.nanorc"
  link_user_file "$workspace/conf/.tmux/default.conf" "$user_home/.tmux.conf"
  link_user_file "$workspace/conf/.config/atuin/config.toml" "$user_home/.config/atuin/config.toml"
  link_user_file "$workspace/conf/.config/alacritty/alacritty.toml" "$user_home/.config/alacritty/alacritty.toml"
  link_user_file "$workspace/conf/.config/mc/menu" "$user_home/.config/mc/menu"

  install_workspace_i3_config "$workspace"
  write_workspace_browser_desktop "$workspace"

  if [ -e "$workspace/conf/.config/i3status/default.conf" ]; then
    cp "$workspace/conf/.config/i3status/default.conf" /etc/i3status.conf
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$user_home/.local/share/applications" || true
  fi

  chown -R "$USER_NAME:$USER_NAME" "$user_home/_workdir" 2>/dev/null || true
  chown -R "$USER_NAME:$USER_NAME" \
    "$user_home/.config" \
    "$user_home/.local" \
    "$user_home/.tmux" 2>/dev/null || true
}
