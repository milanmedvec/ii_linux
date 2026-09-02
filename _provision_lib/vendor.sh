#!/bin/sh

# Third-party source builds used by the workspace.

setup_clipnotify_vendor() {
  source_payload="$1"
  workspace="$2"

  [ "$BUILD_CLIPNOTIFY" = "1" ] || return 0

  repo_env="$source_payload/vendor/clipnotify/repo.env"
  if [ ! -f "$repo_env" ]; then
    echo "Missing clipnotify vendor metadata: $repo_env" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  . "$repo_env"
  : "${CLIPNOTIFY_REPO_URL:?Missing CLIPNOTIFY_REPO_URL in $repo_env}"
  clipnotify_ref="${CLIPNOTIFY_REPO_REF:-}"

  clipnotify_dir="$workspace/vendor/clipnotify"
  patch_dir="$workspace/vendor/patches/clipnotify"

  echo "==> Cloning/building clipnotify"
  if [ -d "$clipnotify_dir/.git" ]; then
    echo "Using existing clipnotify repository: $clipnotify_dir"
  else
    clone_or_update_repo "$CLIPNOTIFY_REPO_URL" "$clipnotify_dir" "$clipnotify_ref"
  fi

  if [ -d "$patch_dir" ]; then
    for patch_file in "$patch_dir"/*.patch; do
      [ -f "$patch_file" ] || continue
      apply_patch_if_needed "$clipnotify_dir" "$patch_file"
    done
  fi

  (
    cd "$clipnotify_dir"
    make
    make install
  )
}

setup_alttab_vendor() {
  source_payload="$1"
  workspace="$2"

  [ "$BUILD_ALTTAB" = "1" ] || return 0

  repo_env="$source_payload/vendor/alttab/repo.env"
  if [ ! -f "$repo_env" ]; then
    echo "Missing alttab vendor metadata: $repo_env" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  . "$repo_env"
  : "${ALTTAB_REPO_URL:?Missing ALTTAB_REPO_URL in $repo_env}"
  alttab_ref="${ALTTAB_REPO_REF:-}"

  alttab_dir="$workspace/vendor/alttab"
  patch_dir="$workspace/vendor/patches/alttab"

  echo "==> Cloning/building patched alttab"
  if [ -d "$alttab_dir/.git" ]; then
    echo "Using existing patched alttab repository: $alttab_dir"
  else
    clone_or_update_repo "$ALTTAB_REPO_URL" "$alttab_dir" "$alttab_ref"
  fi

  if [ -d "$patch_dir" ]; then
    for patch_file in "$patch_dir"/*.patch; do
      [ -f "$patch_file" ] || continue
      apply_patch_if_needed "$alttab_dir" "$patch_file"
    done
  fi

  (
    cd "$alttab_dir"
    if [ ! -x ./configure ]; then
      if [ -x ./bootstrap.sh ]; then
        ./bootstrap.sh
      else
        autoreconf -fvi
      fi
    fi
    ./configure --prefix=/usr/local
    make
    make install
  )
}
