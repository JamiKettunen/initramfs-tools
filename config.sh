##########
# Config
##########

# NOTE: This should be considered a default config; please prefer to override
#       options in a new config.custom.sh file which this sources at the end!

# Kernel header version to target Buildroot binaries against; this should match the lowest
# kernel version you plan to boot the initramfs with
# choices: see https://www.kernel.org/ for currently supported upstream series'
# e.g. "4.4", "5.11" or "5.12"
BR2_KERNEL_HEADERS="5.11"

# Additional Buildroot defconfig(s) to append after initramfs_defconfig; multiple ones
# can be separated with commas (,), e.g. "extra1_defconfig,extra2_defconfig"
# choices: see buildroot/external/configs/*
BR2_CONFIGS="aarch64_a53_a73_defconfig"

# Should we skip rebuilding Buildroot tarball IF an existing one was found?
# choices: 1 / 0 / empty to prompt user (default)
BR2_SKIP_BUILD=

# Amount of build jobs (threads) to run while running Buildroot build script
# e.g. $((`nproc`-1))
BR2_BUILD_JOBS=$(nproc)

# Buildroot install tarball location
# default: buildroot/rootfs.tar.gz
BR2_TARBALL="buildroot/rootfs.tar.gz"

# Shell script hooks to always run inside initramfs
# choices: see hooks/* & hooks/late/*
HOOKS_ENABLE=()

# Shell script hooks to run inside initramfs provided they are enabled via kernel cmdline
# using rd.extra_hooks
# choices: see hooks/* & hooks/late/*
HOOKS_EXTRA=(
	configfs rndis mass-storage # USB gadget
	telnetd hang late/hang # Debugging
)

# Kernel modules to copy over
# choices: see e.g. https://cateee.net/lkddb/web-lkddb/
KERNEL_MODULES_COPY=(
	ext4 f2fs loop nbd # Booting from various media
	configfs libcomposite usb_f_rndis usb_f_mass_storage # USB ConfigFS gadget support
)

# Kernel modules to (copy over &) modprobe in order after reaching initramfs;
# appending to KERNEL_MODULES_COPY is implied
# choices: see e.g. https://cateee.net/lkddb/web-lkddb/
KERNEL_MODULES_PROBE=(
	phy-qcom-qmp ufs_qcom phy-qcom-qusb2 qcom-pon # Qualcomm MSM8998/SDM845
)

# Kernel module (or build output) directory which should contain a modules.dep for example
# e.g. "/path/to/linux-src/out" or "/lib/modules/$(uname -r)"
KERNEL_MODULES_DIR=""

# Extra string to append to initramfs cpio archive name
# e.g. "-postmarketOS"
CPIO_EXTRA_NAME=""

# Remove previously created initramfs cpio archives by the same name?
# choices: 1 (default) / 0
CPIO_RM_EXISTING=1

# Optional initramfs cpio compression;
# NOTE: Enable CONFIG_RD_(GZIP|LZ4) in kernel respectively as needed
# choices: gz / lz4 (default) / none
CPIO_COMPRESS="lz4"

# Optionally define custom args for the gzip/lz4 compressor;
# gzip default: "--best --no-name"
# lz4 default: "-l -9 --favor-decSpeed --quiet"
# empty = use defaults
CPIO_COMPRESS_ARGS=""

# Should the uncompressed source initramfs cpio be kept?
# choices: 1 / 0 (default)
CPIO_COMPRESS_KEEP_SRC=0

# Path to a (optionally pre-gzipped) PPM image file to show on the framebuffer when booting;
# if this is a directory (or pre-gzipped tar archive) look for PPM animation frames to cycle
# through during boot
BOOT_SPLASH=""

# Specifications on how to render the splash image(s); animated splashes are split to static
# (first frame) and animation frames (the rest), only static specs apply to singlular splash images
# format: "static_center,static_offset_top,static_offset_left|anim_center,anim_offset_top,anim_offset_left"
# e.g. "|1,280" = "0,0,0|1,280,0" / "1" = "1,0,0|0,0,0"
BOOT_SPLASH_SPECS=""

# How many milliseconds to wait after drawing before advancing to the next frame?
# only applicable if BOOT_SPLASH is a directory or .tar.gz containing PPM images.
# e.g. for 3 FPS one can say 333, and for 30 FPS about 33
# values <1 = run update loop without any extra pauses
BOOT_ANIMATION_INTERVAL=333

# Drop to shell (ash) instead of hanging forever when e.g. errors occur?
# choices: 1 / 0 (default)
BOOT_DROP_TO_SHELL=0

# USB RNDIS network interface on the device;
# common choices include: "usb0", "rndis0" or "eth0"
BOOT_RNDIS_IFACE="usb0"

# How many seconds to wait until terminating the msm-fb-refresher & splash (animation) hooks?
# if fb-refresher is kept running it can severely affect rendering performance after booting!
# values <1 = keep running forever
BOOT_FB_UPDATE_TIMEOUT=5

# Run the build scripts without any interactive prompts; great for e.g. scripting
# Can also be enabled via -N arg for the build scripts
# choices: 1 / 0 (default)
NON_INTERACTIVE=0

# Potential local config overrides
[ -e config.custom.sh ] && . config.custom.sh || :
