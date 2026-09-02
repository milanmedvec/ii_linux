# Provision config payload

Portable configuration payload for `6_install_x11_i3_workspace.sh`.

This directory is intentionally not a full copy of `workspace/`. It contains
only public/non-private configuration and repository lists used to recreate the
runtime workspace on II linux.

Installed target layout:

```text
/home/$USER_NAME/_workdir/workspace/
├── conf/                 # copied from this payload
├── bin/                  # symlinks to cloned tool commands
├── tools/repos/tool_*    # public tool repositories cloned during provisioning
├── lib/bash-preexec      # public shell hook dependency
└── vendor/alttab         # public alttab source, patched and built locally
```

Included:

- `conf/` copied from `workspace/conf/`, with the old terminal alias removed.
- `tools/repos.list` listing public `tool_*` repositories and pinned refs to clone.
- `lib/repos.list` listing public support repositories such as `bash-preexec`.
- `vendor/alttab/repo.env` and `vendor/alttab/patches/` for the pinned custom alttab build.

Not included:

- `workspace/bin/` generated/linked command tree.
- `workspace/modules/` private modules.
- full `workspace/vendor/` checkouts.
- git metadata or private/secrets files.
