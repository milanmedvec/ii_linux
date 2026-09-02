# QEMU simulation notes

QEMU is useful for testing one layer at a time. The shortest loop is direct kernel boot:

```text
QEMU -> kernel -> initramfs -> /init
```

This avoids UEFI/GRUB while debugging the kernel command line or initramfs logic.

## Direct kernel + initramfs boot

From a build directory containing `kernel/vmlinuz` and `initramfs.img`:

```sh
qemu-system-x86_64 \
  -enable-kvm \
  -m 512M \
  -kernel kernel/vmlinuz \
  -initrd initramfs.img \
  -append "console=ttyS0 rdinit=/init" \
  -nographic
```

Exit a `-nographic` session with:

```text
Ctrl+a x
```

For pure initramfs experiments, `/init` can simply mount basics and start a shell:

```sh
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
exec sh
```

## Direct boot with a disk image

To test handoff to a real root filesystem, attach a disk image and let `/init` discover/mount it:

```sh
qemu-system-x86_64 \
  -enable-kvm \
  -m 1G \
  -kernel kernel/vmlinuz \
  -initrd initramfs.img \
  -append "console=ttyS0 rdinit=/init" \
  -drive file=disk.img,format=raw,if=virtio \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0 \
  -nographic
```

Useful storage/network modules for this style include virtio block/network drivers, filesystem drivers, and any modules needed by the chosen root device.

## UEFI/GRUB style boot

To test the full firmware/bootloader path, boot the disk as a machine disk instead of using `-kernel`/`-initrd`:

```sh
qemu-system-x86_64 \
  -enable-kvm \
  -machine q35 \
  -m 1G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
  -drive file=disk.img,format=raw,if=virtio \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0
```

OVMF firmware paths vary by distribution.

## Historical 9p rootfs development trick

During early development it can be convenient to expose a host directory as a writable rootfs:

```sh
qemu-system-x86_64 \
  -enable-kvm \
  -machine q35 \
  -m 512M \
  -kernel kernel/vmlinuz \
  -initrd initramfs.img \
  -append "console=ttyS0 rdinit=/init" \
  -virtfs local,path="$PWD/rootfs",mount_tag=rootfs,security_model=mapped-xattr \
  -nographic
```

The initramfs then needs 9p/virtio support and mounts the share before `switch_root`:

```text
mount -t 9p -o trans=virtio rootfs /newroot
switch_root /newroot /sbin/init
```

`security_model=mapped-xattr` is preferable to `security_model=none` for writable Linux rootfs testing because package managers need ownership changes such as `chown`.

## QEMU user networking

Typical user-mode networking flags:

```sh
-netdev user,id=net0 \
-device virtio-net-pci,netdev=net0
```

Inside the guest, DHCP is easiest if available:

```sh
ip link set lo up
ip link set eth0 up
udhcpc -i eth0
```

Without DHCP, QEMU user networking usually provides:

```sh
ip addr add 10.0.2.15/24 dev eth0
ip route add default via 10.0.2.2
echo "nameserver 10.0.2.3" > /etc/resolv.conf
```

Those addresses are QEMU-specific and should not be copied to real hardware setup.
