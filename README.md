# initramfs-tools
Create small and adaptable Linux initramfs' mainly intended for embedded (e.g. Android) devices.

## Building
Create a `config.custom.sh`, tweak options defined in `config.sh` as you please & simply run the `build.sh` script:
```
$ ./build.sh
```
For e.g. scripting you can additionally add the `-N` flag to avoid interactive actions.

## Features
* An easily configurable Buildroot/BusyBox environment
* Kernel module support
* Shell script hook system with ordering and early/late triggers
  * Execution order is decided by the numbering of the hook filenames
  * Early triggers run as soon as the initramfs is reached
  * Late triggers run **after** a rootfs is mounted and **right before** `switch_root`
  * Optionally extra hooks can be added and triggered manually via kernel cmdline
* Produced `cpio` archives can be compressed with either `gzip` or `lz4`
* Optional PPM image splash screens ([or even boot animations with some limitations](https://github.com/JamiKettunen/initramfs-tools/blob/0e66266/config.sh#L87-L107))
* Ideally boots any OS (distro) using the Linux kernel

## Runtime configuration
A bunch of the initramfs features can be configured via kernel cmdline using the following options:
|Option|Example values|Comment|
|------|--------------|-------|
|`rd.rootfs`|`/dev/sde21`, `nbd:rootfs:512`|Rootfs location (mandatory!)|
|`rd.extra_hooks`|`late/extra-hook`, `a,b,c`|Additional hooks to run in initramfs|
|`rd.mass_storage_rw`|`0` (default) or `1`|Mount all mass storage devices as read-write|
|`rd.silent_boot`|`0` (default) or `1`|Silence logs from kernel and initramfs, implied on when splash image set|
|`rd.no_clear`|`0` (default) or `1`|Don't clear console on initramfs enter|
|`rd.no_fwdcon`|`0` (default) or `1`|Don't forward kernel messages to `tty8` while starting|

## Booting
* Block device: `rd.rootfs=/dev/sde21`
* Image on a block device: `rd.rootfs=/dev/sda13/rootfs.img`
* Directory on a block device: `rd.rootfs=/dev/sda13/rootfs_dir`
* Network Block Device (NBD): `rd.rootfs=nbd` or e.g. `rd.rootfs=nbd:rootfs:512` <sup>1</sup>
  * A default export name of `rootfs` is assumed unless specified otherwise after the first colon (`:`)
  * A default block-size of `512` is assumed (choices: `512`, `1024`, `2048` or `4096`) unless specified otherwise after the second colon (`:`)

<sup>1</sup> **WARNING:** Make sure you don't (re)configure USB ConfigFS from userspace, or the network connection will cut out!

### NBD server example
Here is an example tree of a NBD server setup I've used successfully:
```
├── allowed_clients
├── nbd_config
└── rootfs.img
```
`allowed_clients`:
```sh
# subnet of initramfs RNDIS connection
172.16.42.0/24
```
`nbd_config`:
```ini
[generic]
authfile = allowed_clients
copyonwrite = false
allowlist = true
max_threads = 16
maxconnections = 1
timeout = 5

[rootfs]
exportname = <absolute-path-to-rootfs.img-here>
```
With those files in place you can start a server with `nbd-server -C nbd_config`, confirm output of `nbd-client -l 127.0.0.1` and test network-booting a target device!

## Kernel requirements
Core
* `CONFIG_RD_GZIP=y` (if using `gzip` compression)
* `CONFIG_RD_LZ4=y` (if using `lz4` compression)
* `CONFIG_DEVTMPFS=y` (populate `/dev` automatically when `devtmpfs` is mounted)

Booting
* `CONFIG_BLK_DEV_LOOP=m` (booting from loopback images)
* `CONFIG_BLK_DEV_NBD=m` (NBD rootfs booting)

USB
* `CONFIG_USB_GADGET=y` (UDC core driver)
* `CONFIG_USB_CONFIGFS=m` (configure USB via ConfigFS)
* `CONFIG_USB_CONFIGFS_RNDIS=y` (enable RNDIS access)
* `CONFIG_USB_CONFIGFS_MASS_STORAGE=y` (enable Mass Storage access)

## Debugging
If you have a working virtual console, you should have logs visible on the display itself.

Otherwise assuming the `configfs`, `rndis` and `telnet` hooks are on the initramfs, you should be able to use `telnet 172.16.42.1` to gain an ash shell on the target device.

To view the boot console (display) from telnet, you can use `conspy`.

## Silent boot
Adding `console=tty2 vt.global_cursor_default=0` to kernel cmdline appears to have helped with Void & Arch Linux at least and allowed the boot splash to show up without issues.

Keep in mind if disabling global VT cursor you should re-enable it on a per-rootfs basis with the following:
```
# setterm -cursor on >> /etc/issue
```

Adding `audit=0` might also help especially on distros using systemd init.

## To-Do
* Fix [`list_pars()`](functions/blk.sh) to work with eMMC partitions
* Minimal BusyBox config
* Recursive hook depdendencies
* Booting from a block devices based on UUID?
* Booting from subpartitions (e.g. stock postmarketOS setup) via e.g. `rd.rootfs.subpars`
* Booting LVM/LUKS2 encrypted root?
* Mount options for root via e.g. `rd.mount_opts`
* x86 support?
