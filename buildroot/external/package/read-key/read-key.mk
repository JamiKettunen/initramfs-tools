################################################################################
#
# read-key
#
################################################################################

define READ_KEY_EXTRACT_CMDS
	cp $(BR2_EXTERNAL_initramfs_extras_PATH)/package/read-key/read-key.c $(@D)/
endef

define READ_KEY_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(@D)/read-key.c \
		-o $(@D)/read-key -lpthread
endef

define READ_KEY_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/read-key $(TARGET_DIR)/usr/bin/read-key
endef

$(eval $(generic-package))
