#!/bin/sh
# Buildroot post-image hook for the atv329q: wrap the kernel + atv329q DTB into
# an aboot boot.img (with an appended DTB) and build the vendor-board-id QCDT so
# the stock Qualcomm aboot boots it.  Runs on the host after Buildroot builds
# ${BINARIES_DIR}/{zImage, <dtb>, rootfs.ext4}.
set -e

BINARIES_DIR="${1}"
BOARD_DIR="${BR2_EXTERNAL_ATV329Q_PATH}/board/geniatech/atv329q"
KERNEL="${BINARIES_DIR}/zImage"
DTB="${BINARIES_DIR}/qcom-msm8909-geniatech-atv329q.dtb"
[ -f "${DTB}" ] || DTB="${BINARIES_DIR}/qcom/qcom-msm8909-geniatech-atv329q.dtb"

[ -f "${KERNEL}" ] || { echo "post-image: ${KERNEL} missing"; exit 1; }
[ -f "${DTB}" ]    || { echo "post-image: atv329q DTB missing"; exit 1; }

# aboot uses the appended DTB (it passes a QCDT, not ATAGs); the QCDT only has to
# match the board-id so aboot proceeds.  See mkqcdt.py / mkboot.py.
cat "${KERNEL}" "${DTB}" > "${BINARIES_DIR}/zImage-dtb"
python3 "${BOARD_DIR}/mkqcdt.py" "${DTB}" "${BINARIES_DIR}/atv329q-qcdt.img"
python3 "${BOARD_DIR}/mkboot.py" \
	--kernel  "${BINARIES_DIR}/zImage-dtb" \
	--ramdisk "${BOARD_DIR}/dummy-ramdisk.cpio.gz" \
	--dt      "${BINARIES_DIR}/atv329q-qcdt.img" \
	--cmdline "${BOARD_DIR}/cmdline.txt" \
	--out     "${BINARIES_DIR}/boot.img"

echo "post-image: ${BINARIES_DIR}/boot.img + atv329q-qcdt.img ready"
echo "post-image: flash boot.img -> boot (mmcblk0p21), rootfs.ext4 -> system (mmcblk0p22)"
