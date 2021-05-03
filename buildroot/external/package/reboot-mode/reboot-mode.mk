################################################################################
#
# reboot-mode
#
################################################################################

REBOOT_MODE_VERSION = 1.0.0
REBOOT_MODE_SITE = https://gitlab.com/postmarketOS/reboot-mode/-/archive/$(REBOOT_MODE_VERSION)
REBOOT_MODE_SOURCE = reboot-mode-$(REBOOT_MODE_VERSION).tar.gz
REBOOT_MODE_LICENSE = GPL-3.0+
REBOOT_MODE_LICENSE_FILES = LICENSE

define REBOOT_MODE_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(@D)/reboot-mode.c -o $(@D)/reboot-mode
endef

define REBOOT_MODE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/reboot-mode $(TARGET_DIR)/usr/bin/reboot-mode
endef

$(eval $(generic-package))
