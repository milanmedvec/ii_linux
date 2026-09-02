# II Linux

Scripts for building and provisioning a small, bootable Linux system on a USB/disk. The flow creates a BusyBox-based initramfs/rootfs, installs GRUB for UEFI boot, then bootstraps Alpine `apk` and provisions an X11/i3 desktop workspace.

## Experimental status and disclaimer

This project is an experiment and a personal Linux bootstrap playground. It is shared for learning, reference, and hacking, not as a polished distro installer or production-ready operating system.

Use it only if you understand what the scripts do. Read the scripts before running them, especially the disk flashing step.

> **Danger**: `2_script_flash_usb.sh` wipes, repartitions, and formats the selected target disk. A wrong device path can destroy your data.

I am not responsible for any data loss, broken systems, hardware issues, failed boots, package problems, or any other trouble caused by using or modifying these scripts. Use at your own risk.

Known scope:

- Experimental/personal project.
- Mainly intended for x86_64 UEFI boot media.
- Defaults are tuned for my environment and may need changes on yours.
- Hardware support depends on the kernel, modules, and firmware copied from the build host.
- Not a secure hardened system by default.

## Repository layout

```text
1_script_init.sh          Build kernel/initramfs/rootfs/boot artifacts
2_script_flash_usb.sh     Partition, format, and install the build to a disk
3_prepare_system.sh       Bootstrap Alpine apk.static inside the new system
4_install_basic_libs.sh   Install Alpine base packages and common utilities
5_setup_user_management.sh    Set up hostname/login, doas, and daily user
6_install_x11_i3_workspace.sh Install X11/i3 packages and user workspace
7_deploy_to_disk.sh          Clone the running USB/system onto an internal disk
_provision_config/           Public provision payload copied to the installed disk
_provision_lib/              Shared helpers used by provisioning scripts
docs/                        Additional stack/background notes
```

## Requirements

Build host:

- Linux system with the kernel image and matching modules available.
- UEFI GRUB tooling for flashing (`grub-install`).
- Common build/disk tools: `awk`, `cpio`, `curl`, `depmod`, `modprobe`, `gzip`, `tar`, `parted`, `wipefs`, `mkfs.vfat`, `mkfs.ext4`, `mount`, `umount`.
- For compressed kernel modules, install the matching decompressors such as `zstd` or `xz`.

Defaults are oriented around Arch-style paths:

- Kernel image: `/boot/vmlinuz-linux`
- Modules: `/usr/lib/modules/$(uname -r)` or `/lib/modules/$(uname -r)`
- Firmware: `/usr/lib/firmware` or `/lib/firmware`

Override these with environment variables if needed.

## Quick start

### 1. Build artifacts

```sh
sh 1_script_init.sh
```

This creates `ii-linux/` by default, containing:

- `kernel/vmlinuz`
- `initramfs.img`
- `rootfs/`
- `boot/` with `vmlinuz`, `initramfs.img`, and `grub/grub.cfg`
- `build.env` metadata consumed by the flash script

Useful overrides:

```sh
DISTRO_NAME=ii-linux \
HOSTNAME=iilinux \
KERNEL_IMAGE=/boot/vmlinuz-linux \
KVER="$(uname -r)" \
sh 1_script_init.sh
```

### 2. Flash to USB/disk

Find the target disk with `lsblk`, then run:

```sh
sudo sh 2_script_flash_usb.sh ii-linux /dev/sdX
```

Replace `/dev/sdX` with the whole disk device, not a partition. The script creates:

1. EFI FAT32 partition, mounted at `/boot/efi` during install.
2. ext4 root partition containing the prepared rootfs and install helpers.

It also copies `3_prepare_system.sh`, `4_install_basic_libs.sh`, `5_setup_user_management.sh`, `6_install_x11_i3_workspace.sh`, `7_deploy_to_disk.sh`, `_provision_config/`, and `_provision_lib/` to `/root/install` on the new system.

### 3. Boot and bootstrap Alpine packages

Boot the target machine from the flashed disk. The initial system starts a root shell on `tty1`.

Run:

```sh
sh /root/install/3_prepare_system.sh
sh /root/install/4_install_basic_libs.sh
```

`3_prepare_system.sh` installs BusyBox applet links, configures Alpine repositories, brings up DHCP, downloads `apk-tools-static`, and installs `/sbin/apk.static`.

`4_install_basic_libs.sh` initializes the apk database, installs Alpine keys, base layout, `apk-tools`, BusyBox fallback, CA certificates, and common GNU/userland utilities.

### 4. Set up user management

Run:

```sh
sh /root/install/5_setup_user_management.sh
```

By default this sets hostname/login basics, installs `doas` and user-management helpers, and creates user `milan`.

If you want the user password set during setup:

```sh
USER_NAME=myuser USER_PASSWORD='change-me' sh /root/install/5_setup_user_management.sh
```

If no `USER_PASSWORD` is provided, set it manually after setup:

```sh
passwd milan
```

### 5. Install X11/i3 and workspace

Run:

```sh
sh /root/install/6_install_x11_i3_workspace.sh
```

This installs runtime hardware support, Xorg, i3, fonts, terminal/workspace packages, and links configuration from `_provision_config` for the user created by step 4. If you changed `USER_NAME` in step 4, pass the same `USER_NAME` here.

After reboot, log in on `tty1`; `startx` launches i3 automatically.

### 6. Optional: deploy from USB to an internal disk

After booting from the provisioned USB, you can clone the running system to the station's internal disk:

```sh
sh /root/install/7_deploy_to_disk.sh /dev/sdX
```

Replace `/dev/sdX` with the whole internal disk device, not a partition. The script wipes the target disk, creates EFI/root partitions, copies the running root filesystem, and copies the USB EFI system partition.

## Common customization

All scripts are configured with environment variables.

### Build (`1_script_init.sh`)

| Variable | Default | Description |
| --- | --- | --- |
| `DISTRO_NAME` | `ii-linux` | Build directory name. |
| `HOSTNAME` | `iilinux` | Installed hostname. |
| `ROOTFS_LABEL` | `IILINUX` | ext4 partition label. |
| `EFI_LABEL` | `EFI` | EFI partition label. |
| `ROOTFS_ID` | UTC timestamp | Unique rootfs marker value used by initramfs. |
| `KERNEL_IMAGE` | `/boot/vmlinuz-linux` | Kernel image to copy. |
| `KVER` | `$(uname -r)` | Kernel module version. |
| `MODULE_SRC` | auto-detected | Kernel module source directory. |
| `FIRMWARE_SRC` | auto-detected | Firmware source directory. |
| `COPY_ALL_ROOTFS_MODULES` | `1` | Copy all modules into rootfs. |
| `COPY_ALL_FIRMWARE` | `1` | Copy firmware into rootfs. |
| `INITRAMFS_MODULES` | built-in list | Modules loaded before mounting rootfs. |
| `ROOTFS_RUNTIME_MODULES` | built-in list | Runtime modules loaded after switch_root. |

Example minimal custom module list:

```sh
COPY_ALL_ROOTFS_MODULES=0 \
INITRAMFS_MODULES="ext4 nvme ahci sd_mod usb_storage xhci_pci" \
ROOTFS_RUNTIME_MODULES="r8169 i915" \
sh 1_script_init.sh
```

### Flash (`2_script_flash_usb.sh`)

| Variable | Default | Description |
| --- | --- | --- |
| `MOUNT_DIR` | `/mnt/$HOSTNAME` | Temporary mount point. |
| `INSTALL_SCRIPTS` | `3_prepare_system.sh 4_install_basic_libs.sh 5_setup_user_management.sh 6_install_x11_i3_workspace.sh 7_deploy_to_disk.sh` | Scripts copied to `/root/install`. |
| `PROVISION_CONFIG_DIR` | `_provision_config` | Provision payload directory. |

### Bootstrap/provision/deploy (`3`–`7`)

| Variable | Default | Description |
| --- | --- | --- |
| `ALPINE_VERSION` | `edge` | Alpine repository branch used by `3_prepare_system.sh`. |
| `NET_IFACE` | auto-detected | Network interface for DHCP. |
| `SETUP_NETWORK` | `1` | Enable DHCP setup. |
| `USER_NAME` | `milan` | User created by `5_setup_user_management.sh` and configured by `6_install_x11_i3_workspace.sh`. |
| `USER_PASSWORD` | empty | Optional password to set with `chpasswd`. |
| `CLONE_TOOLS` | `1` | Clone public tool repositories from `_provision_config/tools/repos.list`. |
| `CLONE_LIBS` | `1` | Clone support libraries from `_provision_config/lib/repos.list`. |
| `BUILD_ALTTAB` | `1` | Clone, patch, build, and install `alttab`. |
| `SRC_ROOT` | detected `/` device | Source root partition for `7_deploy_to_disk.sh`. |
| `SRC_EFI` | detected/derived | Source EFI partition for `7_deploy_to_disk.sh`. |
| `DST_DISK` | first script argument | Whole target disk for `7_deploy_to_disk.sh`. |
| `ROOT_LABEL` | `IILINUX` | Root partition label used by `7_deploy_to_disk.sh`. |
| `EFI_LABEL` | `EFI` | EFI partition label used by `7_deploy_to_disk.sh`. |

## Provision payload

`_provision_config/` contains public configuration and repository lists used by `6_install_x11_i3_workspace.sh`. It is not a full private workspace copy. See [`_provision_config/README.md`](_provision_config/README.md) for details.

## Notes

- See [`docs/`](docs/) for generic stack hints and QEMU simulation notes.
- The generated initramfs searches common block devices for an ext4 rootfs whose `/etc/$ROOTFS_MARKER_FILE` content matches this build's `ROOTFS_ID`, plus executable `/sbin/init`.
- The flash target is installed as removable UEFI boot media via `grub-install --target=x86_64-efi --removable`.
- This project currently targets x86_64 UEFI systems by default, though the Alpine bootstrap script can detect several architectures when used separately.
