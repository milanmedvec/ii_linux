# alttab patches

Patches for the `vendor/alttab` submodule.

## 0001-add-current-window-class-filter-shortcut.patch

Adds an alternate switcher shortcut using X11 keycode `49` with the configured
modifier mask. When triggered, the window list is filtered to windows with the
same `WM_CLASS` as the currently active window.

## 0002-use-automake-1.18-generated-config.patch

Updates only `configure` to use Automake API version 1.18, so Alpine's
available `automake-1.18`/`aclocal-1.18` tools can satisfy any maintainer
rebuild steps triggered by `make`.

Apply from the workspace root with:

```bash
for patch in ../patches/alttab/*.patch; do
  git -C vendor/alttab apply "$patch"
done
```
