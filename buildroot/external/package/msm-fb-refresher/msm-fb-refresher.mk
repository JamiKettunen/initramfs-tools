################################################################################
#
# msm-fb-refresher
#
################################################################################

MSM_FB_REFRESHER_VERSION = 0.2
MSM_FB_REFRESHER_SITE = https://github.com/AsteroidOS/msm-fb-refresher/archive/refs/tags
MSM_FB_REFRESHER_SOURCE = v$(MSM_FB_REFRESHER_VERSION).tar.gz
MSM_FB_REFRESHER_LICENSE = GPL-3.0+
MSM_FB_REFRESHER_LICENSE_FILES = LICENSE

define MSM_FB_REFRESHER_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(@D)/refresher.c -o $(@D)/refresher
endef

define MSM_FB_REFRESHER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/refresher $(TARGET_DIR)/usr/bin/msm-fb-refresher
endef

$(eval $(generic-package))
