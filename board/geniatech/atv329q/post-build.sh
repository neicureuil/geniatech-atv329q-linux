#!/bin/sh
# Buildroot post-build hook for the atv329q: runs on the host, on $TARGET_DIR,
# just before the rootfs image is packed.
set -e

TARGET_DIR="${1}"

# OpenSSH is pulled in for one file only: /usr/libexec/sftp-server, which
# dropbear execs for the "sftp" subsystem (dropbear ships the subsystem but not
# the server binary).  We keep dropbear as *the* SSH daemon -- it is the proven
# access channel on this board -- so drop OpenSSH's own daemon and its init
# script, which would otherwise fight dropbear for port 22 (S50sshd sorts right
# after S50dropbear and would just fail to bind at every boot).
rm -f "${TARGET_DIR}/etc/init.d/S50sshd"
rm -f "${TARGET_DIR}/usr/sbin/sshd"

# Sanity: the sftp subsystem is useless without this binary.
[ -x "${TARGET_DIR}/usr/libexec/sftp-server" ] || {
	echo "post-build: /usr/libexec/sftp-server missing (BR2_PACKAGE_OPENSSH_SERVER?)" >&2
	exit 1
}

# btmgmt is what sets this board's own Bluetooth address at boot (S35btaddr).
# bluez builds it but its `make install` does not ship it, so it has to be
# copied by hand -- Buildroot does exactly the same for gatttool, through a
# post-install hook. BUILD_DIR is exported to post-build scripts.
BTMGMT=$(echo "${BUILD_DIR}"/bluez5_utils-*/tools/btmgmt)
if [ -x "${BTMGMT}" ]; then
	install -D -m 0755 "${BTMGMT}" "${TARGET_DIR}/usr/bin/btmgmt"
	echo "post-build: btmgmt installed from $(basename "$(dirname "$(dirname "${BTMGMT}")")")"
else
	echo "post-build: btmgmt not found under ${BUILD_DIR}/bluez5_utils-*/tools" >&2
	echo "post-build: hci0 would keep whatever address the controller reports" >&2
	exit 1
fi

echo "post-build: dropbear kept as sshd, sftp-server installed"

