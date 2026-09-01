################################################################################
#
# atv329q-screen -- display support for the Geniatech atv329q
#
# The display chain is MDP3 (display-controller@1a00000) -> MSM DSI + 28nm PHY
# -> ADV7533 DSI-to-HDMI bridge. The drivers come from the kernel patches (which
# are always applied); this package carries what the *image* needs on top:
# the S15screen helper, a getty on the HDMI console, and -- when the package is
# disabled -- the kernel fragment that takes the whole DRM/FB stack back out.
#
# No source to download: everything ships in this directory.
#
################################################################################

ATV329Q_SCREEN_VERSION = 1.0
ATV329Q_SCREEN_SOURCE =
ATV329Q_SCREEN_LICENSE = GPL-2.0


ifeq ($(BR2_PACKAGE_ATV329Q_SCREEN),y)

# S15screen re-arms the panel (DPMS off/on) only when the ADV7533 oracle says
# the link is up, so it must run after the console is up but before the login
# prompts settle.
define ATV329Q_SCREEN_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(ATV329Q_SCREEN_PKGDIR)/S15screen \
		$(TARGET_DIR)/etc/init.d/S15screen
endef

# The stock inittab only spawns a getty on `console` (= the serial port here),
# so the HDMI screen would show the kernel log but never a login prompt. Append
# a tty0 getty. This has to be a target-finalize hook rather than an install
# command: /etc/inittab comes from busybox, which is installed after us.
define ATV329Q_SCREEN_INITTAB_TTY0
	$(Q)grep -q "getty -L tty0" $(TARGET_DIR)/etc/inittab || \
		printf '%s\n%s\n' \
			'# Login on the HDMI framebuffer console (MDP3/DSI/ADV7533 -> tty0).' \
			'tty0::respawn:/sbin/getty -L tty0 0 linux' \
			>> $(TARGET_DIR)/etc/inittab
endef
ATV329Q_SCREEN_TARGET_FINALIZE_HOOKS += ATV329Q_SCREEN_INITTAB_TTY0

else # BR2_PACKAGE_ATV329Q_SCREEN != y

# Headless: linux.config builds the display, so it is the OFF state that needs
# a kernel fragment. Buildroot re-runs olddefconfig after merging it, so every
# DRM_*/FB_* dependent symbol follows.
#
# Note: the kernel is not automatically rebuilt when this fragment changes
# (external .mk files are read after linux/linux.mk, so the fragment is merged
# but not registered as a prerequisite) -- use `./build.sh kernel`, as for any
# kernel config change.
LINUX_KCONFIG_FRAGMENT_FILES += $(ATV329Q_SCREEN_PKGDIR)/linux-noscreen.config

endif

$(eval $(generic-package))
