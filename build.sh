#!/bin/sh
# Build the atv329q Buildroot image inside a Debian docker container.
#
# macOS can't build Buildroot natively, and Buildroot can't extract/chmod on a
# macOS bind mount, so the build output + ccache live on PERSISTENT docker
# volumes (native fs). This also makes incremental rebuilds fast: only changed
# packages (e.g. the kernel, or a newly-added package) are rebuilt.
#
# Outputs -> atv329q-buildroot/output-images/{boot.img, atv329q-qcdt.img, rootfs.ext2}
#
#   ./build.sh              # configure (if needed) + build
#   ./build.sh kernel       # force kernel re-extract+re-patch+rebuild (use after
#                           #   editing patches/linux/*.patch or linux.config)
#   ./build.sh clean        # drop the persistent volumes (next build is full)
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"     # .../atv329q-buildroot
ROOT="$(cd "$HERE/.." && pwd)"            # .../qualcomm  (holds buildroot/ + atv329q-buildroot/)
VOL_OUT=atv329q-br-out
VOL_CC=atv329q-br-ccache

if [ "$1" = "clean" ]; then
	docker volume rm -f "$VOL_OUT" "$VOL_CC" 2>/dev/null || true
	echo "cleaned persistent volumes ($VOL_OUT, $VOL_CC)"
	exit 0
fi

[ -d "$ROOT/buildroot/.git" ] || {
	echo "error: $ROOT/buildroot not found. Clone it first:"
	echo "  git clone --branch 2024.02.10 https://github.com/buildroot/buildroot.git $ROOT/buildroot"
	exit 1
}

docker volume create "$VOL_OUT"  >/dev/null
docker volume create "$VOL_CC"   >/dev/null

# Buildroot caches the extracted+patched kernel behind stamp files, so a change
# to patches/linux/*.patch or linux.config is NOT picked up by a plain rebuild.
# `./build.sh kernel` runs linux-dirclean first to force re-extract+re-patch.
KERNEL_DIRCLEAN=false
[ "$1" = "kernel" ] && KERNEL_DIRCLEAN=true

docker run --rm \
	-e KERNEL_DIRCLEAN="$KERNEL_DIRCLEAN" \
	-v "$VOL_OUT":/bro -v "$VOL_CC":/ccache \
	-v "$ROOT":/w -w /w/buildroot debian:bookworm bash -c '
		set -e
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -qq >/dev/null
		apt-get install -y -qq build-essential file wget cpio unzip rsync bc python3 \
			python3-dev libncurses-dev git bzip2 xz-utils libssl-dev flex bison \
			gawk perl mtools >/dev/null
		# (re)generate .config from the defconfig, then build
		make O=/bro BR2_DL_DIR=/w/buildroot/dl \
			BR2_EXTERNAL=/w/atv329q-buildroot atv329q_defconfig >/dev/null
		[ "$KERNEL_DIRCLEAN" = true ] && make O=/bro BR2_DL_DIR=/w/buildroot/dl linux-dirclean
		make O=/bro BR2_DL_DIR=/w/buildroot/dl
		mkdir -p /w/atv329q-buildroot/output-images
		for f in boot.img atv329q-qcdt.img rootfs.ext2 zImage \
		         qcom-msm8909-geniatech-atv329q.dtb; do
			[ -f "/bro/images/$f" ] && cp -f "/bro/images/$f" /w/atv329q-buildroot/output-images/
		done
		echo "=== output-images ==="
		ls -l /w/atv329q-buildroot/output-images/
	'
