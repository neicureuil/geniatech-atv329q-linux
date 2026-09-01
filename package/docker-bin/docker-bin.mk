################################################################################
#
# docker-bin -- official prebuilt static Docker binaries (armhf).
#
# No compilation: the tarball ships statically-linked ELF binaries, so this
# avoids the Go cross-toolchain that BR2_PACKAGE_DOCKER_ENGINE would build.
#
################################################################################

DOCKER_BIN_VERSION = 27.5.1
DOCKER_BIN_SITE = https://download.docker.com/linux/static/stable/armhf
DOCKER_BIN_SOURCE = docker-$(DOCKER_BIN_VERSION).tgz
# runtime deps are pulled in via Config.in `select` (iptables, ca-certificates,
# cgroupfs-mount); list them here too so ordering is correct.
DOCKER_BIN_DEPENDENCIES = iptables ca-certificates cgroupfs-mount

# Kernel side of the package: namespaces, cgroups (incl. the v1 memory/cpuset
# controllers, needed for `docker run --memory/--cpuset`), overlayfs,
# bridge/veth/vxlan and netfilter NAT, merged on top of linux.config.
#
# Note: the kernel is not automatically rebuilt when this fragment changes
# (external .mk files are read after linux/linux.mk, so the fragment is merged
# but not registered as a prerequisite) -- use `./build.sh kernel`, as for any
# kernel config change.
ifeq ($(BR2_PACKAGE_DOCKER_BIN),y)
LINUX_KCONFIG_FRAGMENT_FILES += \
	$(BR2_EXTERNAL_ATV329Q_PATH)/package/docker-bin/linux-docker.config
endif

# Binaries shipped in the tarball (extracted to $(@D) with --strip-components=1).
DOCKER_BIN_BINARIES = \
	dockerd docker containerd containerd-shim-runc-v2 ctr runc \
	docker-proxy docker-init

define DOCKER_BIN_INSTALL_TARGET_CMDS
	$(foreach b,$(DOCKER_BIN_BINARIES),\
		$(INSTALL) -D -m 0755 $(@D)/$(b) $(TARGET_DIR)/usr/bin/$(b)
	)
	$(INSTALL) -D -m 0644 $(DOCKER_BIN_PKGDIR)/daemon.json \
		$(TARGET_DIR)/etc/docker/daemon.json
endef

# S30cgroupfs comes from the cgroupfs-mount package; we add the dockerd service.
define DOCKER_BIN_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(DOCKER_BIN_PKGDIR)/S60dockerd \
		$(TARGET_DIR)/etc/init.d/S60dockerd
endef

$(eval $(generic-package))
