#!/bin/sh
# Build the atv329q Buildroot image inside a Debian docker container.
#
# macOS can't build Buildroot natively, and Buildroot can't extract/chmod on a
# macOS bind mount, so the build output + ccache live on PERSISTENT docker
# volumes (native fs). This also makes incremental rebuilds fast: only changed
# packages (e.g. the kernel, or a newly-added package) are rebuilt.
#
# One single target: atv329q_defconfig -> output-images/  (everything is in it:
# WiFi/BT, screen, SSH/SFTP, NTP, Docker engine).
#
#   ./build.sh            # configure (if needed) + build
#   ./build.sh kernel     # + force kernel re-extract+re-patch+rebuild
#   ./build.sh nodocker   # one-off build without Docker (BR2_PACKAGE_DOCKER_BIN=n)
#   ./build.sh noscreen   # one-off headless build (BR2_PACKAGE_ATV329Q_SCREEN=n)
#   ./build.sh clean      # drop the persistent output volume
# (use `kernel` after editing patches/linux/*.patch, linux.config or linux-docker.config)
#
# Docker and the screen are packages of this BR2_EXTERNAL tree (docker-bin /
# atv329q-screen, both `default y`, each carrying its own kernel fragment). To
# turn one off permanently, put "# BR2_PACKAGE_<PKG> is not set" in
# configs/atv329q_defconfig;
# `nodocker` / `noscreen` here only override the current build, and can be
# combined. Either way the kernel changes, so add `kernel` on the first build:
#   ./build.sh nodocker noscreen kernel
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"     # .../atv329q-buildroot
ROOT="$(cd "$HERE/.." && pwd)"            # .../qualcomm  (holds buildroot/ + atv329q-buildroot/)
DEFCONFIG=atv329q_defconfig
IMGDIR=output-images
VOL_OUT=atv329q-br-out
VOL_CC=atv329q-br-ccache

# `nodocker` / `noscreen`: flip a board option off for this build only (the
# defconfig stays the source of truth). Can be combined, in any order, with
# `kernel` last.
DOCKER=y
SCREEN=y
while true; do
	case "$1" in
	nodocker) DOCKER=n; shift ;;
	noscreen) SCREEN=n; shift ;;
	*) break ;;
	esac
done

if [ "$1" = "clean" ]; then
	docker volume rm -f "$VOL_OUT" 2>/dev/null || true
	echo "cleaned output volume ($VOL_OUT).  ccache ($VOL_CC) kept."
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
# to patches/linux/*.patch, linux.config or linux-docker.config is NOT picked up
# by a plain rebuild. `kernel` runs linux-dirclean first to force re-extract.
KERNEL_DIRCLEAN=false
[ "$1" = "kernel" ] && KERNEL_DIRCLEAN=true

docker run --rm \
	-e KERNEL_DIRCLEAN="$KERNEL_DIRCLEAN" -e DEFCONFIG="$DEFCONFIG" -e IMGDIR="$IMGDIR" \
	-e DOCKER="$DOCKER" -e SCREEN="$SCREEN" \
	-v "$VOL_OUT":/bro -v "$VOL_CC":/ccache \
	-v "$ROOT":/w -w /w/buildroot debian:bookworm bash -c '
		set -e
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -qq >/dev/null
		apt-get install -y -qq build-essential file wget cpio unzip rsync bc python3 \
			python3-dev libncurses-dev git bzip2 xz-utils libssl-dev flex bison \
			gawk perl mtools >/dev/null
		# Turning a package OFF does not remove what a previous build already
		# installed into target/ (Buildroot never uninstalls). So if a board
		# switch changed since the last build in this volume, start from a clean
		# tree -- otherwise e.g. dockerd would still end up in the image.
		STATE=/bro/.atv329q-options-state
		WANT="docker=$DOCKER screen=$SCREEN"
		PREV="$(cat $STATE 2>/dev/null || true)"
		if [ -n "$PREV" ] && [ "$PREV" != "$WANT" ]; then
			echo "=== board options changed ($PREV -> $WANT): full rebuild (make clean) ==="
			make O=/bro clean >/dev/null
		fi

		# (re)generate .config from the defconfig, then build. For nodocker /
		# noscreen, feed a *copy* of the defconfig with the option turned off,
		# rather than disabling it in an already-generated .config: the symbols
		# it selects (docker-bin, iptables, i2c-tools, ...) would keep their
		# value there.
		DEFCONFIG_FILE=/w/atv329q-buildroot/configs/$DEFCONFIG
		if [ "$DOCKER" = n ] || [ "$SCREEN" = n ]; then
			cp "$DEFCONFIG_FILE" /tmp/atv329q_defconfig.local
			DEFCONFIG_FILE=/tmp/atv329q_defconfig.local
			if [ "$DOCKER" = n ]; then
				echo "=== building WITHOUT docker (BR2_PACKAGE_DOCKER_BIN=n) ==="
				sed -i "s/^BR2_PACKAGE_DOCKER_BIN=y/# BR2_PACKAGE_DOCKER_BIN is not set/" \
					"$DEFCONFIG_FILE"
			fi
			if [ "$SCREEN" = n ]; then
				echo "=== building HEADLESS (BR2_PACKAGE_ATV329Q_SCREEN=n) ==="
				sed -i "s/^BR2_PACKAGE_ATV329Q_SCREEN=y/# BR2_PACKAGE_ATV329Q_SCREEN is not set/" \
					"$DEFCONFIG_FILE"
			fi
		fi
		make O=/bro BR2_DL_DIR=/w/buildroot/dl \
			BR2_EXTERNAL=/w/atv329q-buildroot defconfig \
			BR2_DEFCONFIG="$DEFCONFIG_FILE" >/dev/null
		[ "$KERNEL_DIRCLEAN" = true ] && make O=/bro BR2_DL_DIR=/w/buildroot/dl linux-dirclean
		make O=/bro BR2_DL_DIR=/w/buildroot/dl
		echo "$WANT" > "$STATE"
		mkdir -p "/w/atv329q-buildroot/$IMGDIR"
		for f in boot.img atv329q-qcdt.img rootfs.ext2 zImage \
		         qcom-msm8909-geniatech-atv329q.dtb; do
			[ -f "/bro/images/$f" ] && cp -f "/bro/images/$f" "/w/atv329q-buildroot/$IMGDIR/"
		done
		echo "=== $IMGDIR ==="
		ls -l "/w/atv329q-buildroot/$IMGDIR/"
	'
