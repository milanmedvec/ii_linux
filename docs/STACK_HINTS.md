# Linux stack hints

A small Linux system can be understood as a few explicit layers:

```text
firmware/bootloader
  -> kernel
  -> initramfs
  -> real root filesystem
  -> /sbin/init as PID 1
  -> login/session/desktop tools
```

## Kernel

The kernel owns hardware, memory, processes, filesystems, networking, and device drivers. A bootloader or emulator loads the kernel image and passes a command line such as:

```text
console=ttyS0 rdinit=/init root=...
```

Useful command-line fields:

- `console=...` chooses where kernel/init messages appear.
- `rdinit=/init` tells the kernel what to run inside the initramfs.
- `root=...` is commonly used when the kernel or initramfs should mount a real root filesystem.

## Initramfs

An initramfs is a tiny temporary userspace loaded with the kernel. It usually contains:

```text
/init
/bin/busybox
/bin/sh
/proc
/sys
/dev
/lib/modules/<kernel-version>/...
```

Typical responsibilities:

1. mount `proc`, `sysfs`, and `devtmpfs`
2. load storage/filesystem/device modules
3. find the real root filesystem
4. mount it somewhere such as `/newroot`
5. hand over with `switch_root`

A simple archive can be built with:

```sh
(
  cd initramfs
  find . -print0 |
    cpio --null --create --format=newc |
    gzip -9
) > initramfs.img
```

## Root filesystem

The real root filesystem is the writable system users normally interact with. It contains the package-managed userspace:

```text
/etc
/bin
/sbin
/usr
/var
/home
```

A small system may start with BusyBox and then bootstrap a package manager. For Alpine-style systems, the usual base pieces are:

```text
alpine-baselayout
busybox
busybox-binsh
apk-tools
ca-certificates-bundle
```

## PID 1

After the initramfs switches into the real root, the kernel runs `/sbin/init` as PID 1. PID 1 may be a full init system or a small script.

Common minimal PID 1 jobs:

- mount runtime filesystems: `/proc`, `/sys`, `/dev`, `/run`, `/tmp`
- start device management such as `udev`
- bring up networking
- start `getty` for login
- handle shutdown/reboot cleanly

## Runtime filesystems

Common mounts on minimal systems:

```text
proc        /proc
sysfs       /sys
devtmpfs    /dev
devpts      /dev/pts
tmpfs       /run
tmpfs       /tmp
cgroup2     /sys/fs/cgroup
```

`/tmp` is commonly tmpfs with mode `1777`. Cgroup v2 at `/sys/fs/cgroup` is useful for container runtimes and modern process tooling.

## User and graphical session

A direct tty login does not necessarily create all session state that desktop software expects. Useful concepts:

- `~/.profile` for login/session environment
- `~/.bash_profile` to bridge Bash login shells to `.profile` and `.bashrc`
- `~/.bashrc` for interactive shell aliases/helpers
- `~/.xinitrc` for `startx`/X11 startup
- `XDG_RUNTIME_DIR` for per-user runtime sockets/state
- `dbus-run-session -- <wm>` to scope DBus to a graphical session

For X11/i3-style sessions the rough flow is:

```text
tty login
  -> shell profile
  -> startx
  -> ~/.xinitrc
  -> dbus-run-session
  -> window manager
```
