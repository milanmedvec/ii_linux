#!/bin/sh

# Common helpers for II Linux provisioning scripts.

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

script_dir() {
  if [ -n "${SCRIPT_DIR:-}" ]; then
    echo "$SCRIPT_DIR"
    return 0
  fi

  cd "$(dirname "$0")" && pwd -P
}

find_workspace_src() {
  if [ -n "$WORKSPACE_SRC" ]; then
    [ -d "$WORKSPACE_SRC/conf" ] && { echo "$WORKSPACE_SRC"; return 0; }
    return 1
  fi

  dir="$(script_dir)"
  for candidate in \
    "$dir/_provision_config" \
    "$PWD/_provision_config"
  do
    if [ -d "$candidate/conf" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

require_workspace_src() {
  if ! find_workspace_src >/dev/null 2>&1; then
    echo "Provision config source not found. Put _provision_config next to this script or set WORKSPACE_SRC=/path/to/_provision_config." >&2
    exit 1
  fi
}

require_user() {
  if ! id "$USER_NAME" >/dev/null 2>&1; then
    echo "User does not exist: $USER_NAME. Run 5_setup_user_management.sh first." >&2
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

apk_install_workspace_packages() {
  title="$1"
  packages="$2"

  [ -n "$packages" ] || return 0
  apk_install "$title" "$packages"
}

clone_or_update_repo() {
  repo_url="$1"
  repo_dir="$2"
  repo_ref="${3:-}"

  if [ -d "$repo_dir/.git" ]; then
    echo "Updating repository: $repo_dir"
    "$GIT" -C "$repo_dir" fetch --all --prune
    if [ -n "$repo_ref" ]; then
      "$GIT" -C "$repo_dir" checkout "$repo_ref"
    else
      "$GIT" -C "$repo_dir" pull --ff-only
    fi
    return 0
  fi

  if [ -e "$repo_dir" ]; then
    backup_dir="$repo_dir.before-provision.$(date +%Y%m%d-%H%M%S)"
    echo "Backing up non-git repository target: $repo_dir -> $backup_dir"
    mv "$repo_dir" "$backup_dir"
  fi

  echo "Cloning repository: $repo_url -> $repo_dir"
  mkdir -p "$(dirname "$repo_dir")"
  "$GIT" clone "$repo_url" "$repo_dir"

  if [ -n "$repo_ref" ]; then
    "$GIT" -C "$repo_dir" checkout "$repo_ref"
  fi
}

apply_patch_if_needed() {
  repo_dir="$1"
  patch_file="$2"

  if "$GIT" -C "$repo_dir" apply --check "$patch_file" >/dev/null 2>&1; then
    echo "Applying patch: $patch_file"
    "$GIT" -C "$repo_dir" apply "$patch_file"
    return 0
  fi

  if "$GIT" -C "$repo_dir" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "Patch already applied: $patch_file"
    return 0
  fi

  echo "Patch cannot be applied cleanly: $patch_file" >&2
  exit 1
}
