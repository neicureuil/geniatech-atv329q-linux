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

echo "post-build: dropbear kept as sshd, sftp-server installed"

