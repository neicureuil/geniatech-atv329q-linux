# atv329q mainline Linux BSP (Buildroot)

Reproducible mainline Linux build for the **Geniatech atv329q** Android TV box
(Qualcomm **MSM8909** / Snapdragon 210, quad Cortex-A7, ARMv7). This is a
Buildroot `BR2_EXTERNAL` tree: it pins the community
[msm8916-mainline](https://github.com/msm8916-mainline/linux) kernel, applies the
atv329q board patch, and produces a bootable `boot.img` + a persistent ext4
rootfs on the eMMC `system` partition.

## What works

- **Display** — HDMI via the MDP3 → DSI (3 lanes) → ADV7533 bridge, using a
  first-of-its-kind mainline **MDP3 KMS driver** + ADV7533 bring-up matched to
  the vendor bootloader. `/dev/dri/card0` + fbcon; kernel logs and a **login
  shell appear on the HDMI screen** (getty on `tty0`, see `rootfs_overlay/etc/inittab`).
  The screen lights on ~1/2 of boots — the analog ADV7533 lock is
  non-deterministic and not software-fixable; `S15screen` is a best-effort,
  oracle-gated DPMS re-arm helper (no flicker on good boots).
- **USB host** — the on-board Genesys hub is released via TLMM GPIO hogs
  (hub-reset=26, sw-sel=27), giving a **USB keyboard** and the internal
  **ASIX AX88772B RJ45** (`eth0`).
- **Networking** — `eth0` (DHCP, out of the box) + **WiFi** (wcn36xx,
  auto-connects at boot via `S12wifi` + baked WCNSS firmware).
- **Bluetooth** — same WCNSS radio core, via `btqcomsmd`: `hci0` + **BlueZ 5**
  (`bluetoothd` started by `S40bluetoothd`, `bluetoothctl`, `btmon`, the `hci*`
  tools). RFCOMM / BNEP / HIDP + `uhid` are in the kernel, so Bluetooth
  keyboards, mice and gamepads work. `S10wcnss` boots the shared radio core.
- **Storage** — `/` is the ext4 `system` partition (persistent, ~1.1 GB); the
  large `userdata` partition is formatted + mounted at `/data` (~5.4 GB) on first
  boot by `S11data`. **USB mass storage** (keys, disks: BOT + UAS) with
  vfat/exFAT/NTFS3 — plug a key into the hub and `mount /dev/sda1 /mnt`
  (`devtmpfs` creates the node; there is no automounter).
- **Access** — `dropbear` SSH (`root` / `alpine`) over `eth0` or WiFi, with
  **SFTP** (dropbear's `sftp` subsystem + OpenSSH's `sftp-server`) and `scp`.

## Layout

```
configs/atv329q_defconfig                     Buildroot config
board/geniatech/atv329q/
  linux.config                                kernel .config
  patches/linux/000N-*.patch                  atv329q kernel/DT patches, split by feature:
                                                0001 MDP3 KMS driver + msm-drm wiring
                                                0002 msm DSI host + 28nm PHY
                                                0003 ADV7533 DSI->HDMI bridge
                                                0004 gcc-msm8909 MDSS AXI clock
                                                0005 device tree (+ eMMC bootargs)
  cmdline.txt                                  kernel cmdline (root=/dev/mmcblk0p22)
  mkboot.py / mkqcdt.py                        aboot boot.img + QCDT builders
  dummy-ramdisk.cpio.gz                        placeholder ramdisk (rootfs is on eMMC)
  post-image.sh                                wraps zImage+DTB into boot.img + QCDT
  post-build.sh                                rootfs cleanup (drop OpenSSH's sshd, keep sftp-server)
  wpa_supplicant.conf.example                  WiFi config template (copy into rootfs_overlay)
  rootfs_overlay/
    etc/init.d/S01loglevel                     lower console_loglevel (keep printk off tty0)
    etc/init.d/S10wcnss                        boot the WCNSS radio core (WiFi + Bluetooth)
    etc/init.d/S11data                         format + mount /data (userdata) on first boot
    etc/init.d/S45timesync                     synchronous first NTP sync (no RTC battery; needed for TLS/docker pull)
    etc/chrony.conf                            NTP config (chronyd, unlimited step: boots start at 1970)
    etc/init.d/S12wifi                          WCNSS remoteproc + wpa_supplicant + DHCP (wlan0)
    etc/wpa_supplicant.conf                     WiFi SSID/psk  (git-ignored; copy from the .example)
    lib/firmware/wcnss.*                        WCNSS WiFi/BT firmware
package/atv329q-screen/                        display package (see "Board packages")
  S15screen                                    oracle-gated DPMS screen re-arm helper
  linux-noscreen.config                        kernel fragment merged when the package is OFF
package/docker-bin/                            Docker package (official static armhf binaries)
  S60dockerd / daemon.json                     dockerd init script + data-root=/data/docker
  linux-docker.config                          kernel fragment merged when the package is ON
build.sh                                       Docker build wrapper (persistent volumes)
```

## Build (Docker; native macOS can't build Buildroot)

`build.sh` runs the build inside a Debian container, keeping the Buildroot output
and ccache on **persistent docker volumes** (so incremental rebuilds are fast).

```sh
git clone --branch 2024.02.10 https://github.com/buildroot/buildroot.git ../buildroot
./build.sh                 # configure (if needed) + build
./build.sh kernel          # + force kernel re-extract+re-patch+rebuild
./build.sh nodocker        # one-off build without Docker (see below)
./build.sh noscreen        # one-off headless build (see below)
./build.sh clean           # drop the output volume
```

There is a **single target** (`atv329q_defconfig`): one image with everything in
it — WiFi/Bluetooth, screen, SSH/SFTP, NTP and the Docker engine. Outputs land in
`output-images/` (`boot.img`, `atv329q-qcdt.img`, `rootfs.ext2`).

> ⚠️ **After editing `patches/linux/*.patch` or `linux.config`**, use
> `./build.sh kernel`. Buildroot caches the extracted+patched kernel behind stamp
> files, so a plain rebuild will **silently keep the old kernel**.
>
> ⚠️ The `patches/linux/*.patch` files are the kernel source of truth for this
> project (feature-split, self-contained). To hack on the kernel, either edit the
> patches directly, or edit the extracted tree under `output/build/linux-*/` and
> use `make linux-update-patch`. The patch set must stay **complete** — all 28
> files, including `drivers/gpu/drm/msm/{Makefile,Kconfig,msm_drv.c}` and
> `drivers/clk/qcom/gcc-msm8909.c`. If the MDP3 driver isn't compiled + registered
> it never binds (`/sys/class/drm` has only `version`, screen stays black).

## Flash

The box boot chain: PBL → SBL → aboot → `boot` partition → kernel → `system`
rootfs.

- **EDL / firehose** (always works — the "usb boot" jumper forces EDL 9008):
  ```sh
  edl w boot   output-images/boot.img
  edl w system output-images/rootfs.ext2
  ```
  Partition map (mmcblk0): `boot` = p21, `system` = p22 (rootfs), `cache` = p24,
  `userdata` = p31 (`/data`).
- **Fastboot** — the vendor aboot's fastboot is reachable only if it can be
  entered; EDL is the guaranteed path.

`system` and `userdata` are persistent — reflashing `boot` alone (kernel-only
changes) leaves the rootfs and `/data` intact. Rootfs-only changes can also be
pushed live over SSH (the eMMC rootfs persists across reboots).

**Recovery**: keep a backup of the vendor bootloader partitions
(sbl1/rpm/tz/aboot) to restore Android or unbrick via EDL.

> **There is no way into fastboot from this Linux.** `dr_mode = "host"` means the
> micro-USB is not a device port, so neither adb nor fastboot ever enumerates,
> and the vendor aboot ignores the IMEM restart-reason cookie that
> `reboot bootloader` writes (measured: the magic is still sitting at
> `0x0860065c` after the reboot; the aboot binary contains no `0x77665500`, and
> its only reboot channel is the `boot-recovery` string in `misc`). The DT node
> is kept because it describes the hardware correctly, not because it works.
> **Re-flashing this board means the EDL jumper.**

## Board packages

The two optional features of the image are **packages** of this BR2_EXTERNAL
tree, both `default y`, each carrying its userland *and* its kernel side so the
two can't drift apart:

| package | on (default) | off |
| --- | --- | --- |
| `docker-bin` (`BR2_PACKAGE_DOCKER_BIN`) | static Docker binaries + `S60dockerd` + `daemon.json`, selects `iproute2`/`iptables`/`ca-certificates`/`cgroupfs-mount`, merges `linux-docker.config` | no container userland, smaller kernel |
| `atv329q-screen` (`BR2_PACKAGE_ATV329Q_SCREEN`) | `S15screen` + a getty on tty0 (login on HDMI); the DRM/fbdev kernel side is already in `linux.config` | merges `linux-noscreen.config`, which drops DRM/FB/fbcon — headless, SSH + serial only |

- **off permanently**: replace `BR2_PACKAGE_<PKG>=y` with
  `# BR2_PACKAGE_<PKG> is not set` in `configs/atv329q_defconfig`
- **off for one build**: `./build.sh nodocker`, `./build.sh noscreen` (combinable)

> Note the asymmetry: `linux.config` already builds the display, so the screen
> package needs a fragment in its **off** state (kconfig has no "disable when
> absent" hook), while docker needs one in its **on** state. Both live in the
> package directory next to the code they belong to.
>
> Both change the kernel, and Buildroot never uninstalls what a previous build
> put in `target/`, so `build.sh` remembers the switches and runs a full
> `make clean` rebuild whenever one flips. Add `kernel` on the first flip if you
> also touched patches/config: `./build.sh noscreen kernel`.
>
> The kernel *patches* (MDP3, DSI, ADV7533, MDSS clock, device tree) are always
> applied — they are the board's source of truth. Disabling the screen package
> only stops the display from being *built*, and leaves `CONFIG_VT` in place, so
> the `console=tty0` in the cmdline stays harmless.

## Docker

With the package on, the image ships a full **Docker** engine (the box has ~2 GB
RAM, so armv7/arm32 containers run comfortably). It uses the **official prebuilt static Docker
binaries** (armhf) rather than compiling the Go engine — so the build stays
native and fast (no Go cross-toolchain, no emulation). It comes from:

- the `docker-bin` BR2_EXTERNAL package (`package/docker-bin/`): downloads the
  official `docker-<ver>.tgz` (statically-linked `dockerd`, `docker`,
  `containerd`, `runc`, ...) and installs them + `/etc/init.d/S60dockerd` +
  `/etc/docker/daemon.json`. It selects `iptables`, `ca-certificates` and
  `cgroupfs-mount` (the latter provides `/etc/init.d/S30cgroupfs`, which mounts
  the cgroup hierarchy). `iproute2` is added for `ip`.
- its `linux-docker.config` kernel fragment (namespaces, cgroups incl. the v1
  `memory`/`cpuset` controllers for `--memory`/`--cpuset`, overlayfs,
  bridge/veth/vxlan, netfilter NAT), merged on top of `linux.config` by
  `docker-bin.mk` itself.
- `daemon.json` points `data-root` at `/data/docker` (the big `userdata`
  partition, so images don't fill the rootfs).

> Only the kernel (fragment) and a little C (`iptables`, `ca-certificates`) are
> compiled; the Docker userland is prebuilt. To bump Docker, change
> `DOCKER_BIN_VERSION` in `package/docker-bin/docker-bin.mk` and update the
> `.hash`, then `./build.sh` (or `./build.sh kernel`).

On the box: `docker run --rm hello-world` (use arm/armv7 images, e.g.
`arm32v7/alpine`).

## Time / NTP

The box has **no battery-backed RTC**: every boot starts at 1970, and TLS (hence
`docker pull`, `https`) fails with "certificate is not yet valid" until the clock
is set. Two pieces:

- `S45timesync` (overlay): a **synchronous** one-shot `chronyd -q -t 15` right
  after the network comes up, so the clock is already correct when `dockerd`
  starts at S60. Falls back to `rdate` (RFC 868, NIST) if NTP is unreachable;
  non-fatal either way.
- `S49chrony` (from the `chrony` package): the daemon, which then keeps the clock
  disciplined for as long as the box is up. Config in `/etc/chrony.conf`
  (overlay): `pool pool.ntp.org iburst` and `makestep 1.0 -1` — always step,
  never slew, since slewing a 56-year offset would never converge.

Check with `chronyc tracking` / `chronyc sources` on the box.

## Headless builds

Dropping the `atv329q-screen` package (`# BR2_PACKAGE_ATV329Q_SCREEN is not set`,
or `./build.sh noscreen`) produces the same image without the display: the kernel
drops DRM/FB/fbcon/logo (`linux-noscreen.config`), and neither `S15screen` nor
the `getty -L tty0` line gets installed — the package adds the getty with a
target-finalize hook, so an image built without it simply never has one.
Everything else — eMMC rootfs, `/data`, WiFi/Bluetooth, SSH/SFTP,
NTP, Docker — is untouched, and the serial console (`ttyMSM0`) still gets a login.

Useful given the analog flakiness of the HDMI bring-up (~1 in 2 boots): a
headless image takes the screen out of the equation entirely.

## Boot model

aboot loads `boot.img` (zImage + **appended DTB** + QCDT to satisfy the board-id
check) and boots. The kernel takes its cmdline from the DTB `chosen/bootargs`
(aboot passes a QCDT, not ATAGs), which sets `root=/dev/mmcblk0p22`. No initramfs.

## WiFi setup

WiFi requires to copy the template and fill with your network credentials:

```sh
cp board/geniatech/atv329q/wpa_supplicant.conf.example \
   board/geniatech/atv329q/rootfs_overlay/etc/wpa_supplicant.conf
$EDITOR board/geniatech/atv329q/rootfs_overlay/etc/wpa_supplicant.conf   # set ssid + psk
```

The real `rootfs_overlay/etc/wpa_supplicant.conf` is git-ignored, so your
credentials never enter the repo. If it is absent the build still works and
`S12wifi` just skips WiFi (`eth0` / SSH are unaffected).

## Bluetooth

Bluetooth rides the same WCNSS core as WiFi (`btqcomsmd`), so it needs the
remoteproc booted with the firmware from the rootfs — `S10wcnss` does that at
boot, independently of whether WiFi is configured. `hci0` then appears a few
seconds in and `bluetoothd` powers it on.

```sh
hciconfig -a                 # hci0 up, address, features
bluetoothctl
  power on
  scan on
  pair    <MAC>
  connect <MAC>
  trust   <MAC>              # auto-reconnect after a reboot
btmon                        # live HCI trace when something misbehaves
```

Pairings live in `/var/lib/bluetooth`, on the persistent eMMC rootfs, so they
survive reboots. A paired keyboard/mouse shows up as a normal input device (HIDP
+ `uhid`) and drives the HDMI console. Audio (A2DP) is *not* included: it needs
a sound server (PipeWire/PulseAudio) that this image doesn't ship.

## SFTP

`dropbear` already advertises the `sftp` subsystem but doesn't ship a server
binary; the build installs OpenSSH's `sftp-server` at `/usr/libexec/sftp-server`
for it. OpenSSH's own `sshd` (and its `S50sshd` init script) is removed by
`post-build.sh` — dropbear stays the one SSH daemon on port 22.

```sh
sftp root@<box>              # or any GUI client: Filezilla, Cyberduck, Nautilus...
scp file root@<box>:/data/
```

## Security

The default root password is `alpine` (`BR2_TARGET_GENERIC_ROOT_PASSWD`). Change
it before deploying anywhere reachable.

## TODO

- Git-version this tree as a standalone repo (with `.gitignore` for `buildroot/`,
  `output-images/`) after redacting the WiFi credentials.
- Deterministic screen lock (analog wall; only visual confirmation is reliable).
- Network robustness: `eth0` enumerates late via the USB hub — add DHCP retry/wait.
