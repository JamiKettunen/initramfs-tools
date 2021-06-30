################################################################################
#
# parse-android-dynparts
#
################################################################################

PARSE_ANDROID_DYNPARTS_VERSION = 0.1
PARSE_ANDROID_DYNPARTS_COMMIT = c8837c1cd0c4fbc29641980b71079fc4f3cabcc0
PARSE_ANDROID_DYNPARTS_SITE = https://github.com/tchebb/parse-android-dynparts/archive
PARSE_ANDROID_DYNPARTS_SOURCE = $(PARSE_ANDROID_DYNPARTS_COMMIT).tar.gz
PARSE_ANDROID_DYNPARTS_LICENSE = Apache-2.0
PARSE_ANDROID_DYNPARTS_LICENSE_FILES = LICENSE
PARSE_ANDROID_DYNPARTS_DEPENDENCIES = openssl

$(eval $(cmake-package))
