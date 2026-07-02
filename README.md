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
  auto-connects at boot via `S12wifi` + baked WCNSS firmware) + Bluetooth
  (btqcomsmd).
- **Storage** — `/` is the ext4 `system` partition (persistent, ~1.1 GB); the
  large `userdata` partition is formatted + mounted at `/data` (~5.4 GB) on first
  boot by `S11data`.
- **Access** — `dropbear` SSH (`root` / `alpine`) over `eth0` or WiFi.

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
  wpa_supplicant.conf.example                  WiFi config template (copy into rootfs_overlay)
  rootfs_overlay/
    etc/inittab                                + getty on tty0 (HDMI login shell)
    etc/init.d/S01loglevel                     lower console_loglevel (keep printk off tty0)
    etc/init.d/S11data                         format + mount /data (userdata) on first boot
    etc/init.d/S12wifi                          WCNSS remoteproc + wpa_supplicant + DHCP (wlan0)
    etc/init.d/S15screen                        oracle-gated DPMS screen re-arm (i2cget -f)
    etc/wpa_supplicant.conf                     WiFi SSID/psk  (git-ignored; copy from the .example)
    lib/firmware/wcnss.*                        WCNSS WiFi/BT firmware
build.sh                                       Docker build wrapper (persistent volumes)
```

## Build (Docker; native macOS can't build Buildroot)

`build.sh` runs the build inside a Debian container, keeping the Buildroot output
and ccache on **persistent docker volumes** (so incremental rebuilds are fast).

```sh
git clone --branch 2024.02.10 https://github.com/buildroot/buildroot.git ../buildroot
./build.sh              # configure (if needed) + build
./build.sh kernel       # force kernel re-extract+re-patch+rebuild  (see below)
./build.sh clean        # drop the persistent volumes (next build is full)
```

Outputs land in `output-images/`: `boot.img`, `atv329q-qcdt.img`, `rootfs.ext2`.

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

## Security

The default root password is `alpine` (`BR2_TARGET_GENERIC_ROOT_PASSWD`). Change
it before deploying anywhere reachable.

## TODO

- Git-version this tree as a standalone repo (with `.gitignore` for `buildroot/`,
  `output-images/`) after redacting the WiFi credentials.
- Deterministic screen lock (analog wall; only visual confirmation is reliable).
- Network robustness: `eth0` enumerates late via the USB hub — add DHCP retry/wait.
- Decide whether to keep the (inert, vendor-aboot-ignored) IMEM reboot-mode DT node.
