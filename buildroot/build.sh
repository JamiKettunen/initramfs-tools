#!/bin/bash -e
BASEDIR="$(readlink -f "$(dirname "$0")")"
INITDIR="$BASEDIR/.."

##########
# Config
##########
cd "$INITDIR"
. config.sh
cd "$BASEDIR"

#############
# Functions
#############
log() { echo ">> $1"; }
m() { make BR2_EXTERNAL="$BASEDIR/external" $@; }

##########
# Script
##########
if [ -d $HOME/.buildroot-ccache ]; then
	read -erp ">> Clean ccache located at ~/.buildroot-ccache (y/N)? " ans
	[[ "${ans^^}" = "Y"* ]] && ccache -d ~/.buildroot-ccache -C
fi

pull_ask=1
if [ ! -d buildroot-git ]; then
	pull_ask=0
	git clone https://git.buildroot.net/buildroot buildroot-git
fi
cd buildroot-git
if [ $pull_ask -eq 1 ]; then
	read -erp ">> Pull updates to buildroot tree (Y/n)? " ans
	[[ "${ans^^}" != "N"* ]] && git pull --ff-only
fi

patch_count=$(find "$BASEDIR"/patches -type f | wc -l)
log "Adding $patch_count out-of-tree patch(es)..."
cp -r "$BASEDIR"/patches/* .

if [ -d output ]; then
	read -erp ">> Clean previous build output artifacts (y/N)? " ans
	if [[ "${ans^^}" = "Y"* ]]; then
		m -j clean
		rm -r output # "$INITDIR/$BR2_TARBALL"
	fi
fi

gen_cfg=1
if [ -e .config ]; then
	read -erp ">> Regenerate Buildroot .config from \"initramfs_defconfig ${BR2_CONFIGS/,/ }\" (y/N)? " ans
	[[ "${ans^^}" != "Y"* ]] && gen_cfg=0
fi
if [ $gen_cfg -eq 1 ]; then
	header_ver="${BR2_KERNEL_HEADERS/./_}" # e.g. "5.12" -> "5_12"
	cat ../external/configs/{initramfs_defconfig,$BR2_CONFIGS} \
		| sed "s/@BR2_KERNEL_HEADERS@/BR2_KERNEL_HEADERS_$header_ver=y/" \
		> "$BASEDIR"/external/configs/final_defconfig
	m final_defconfig
fi

read -erp ">> Run Buildroot menuconfig (y/N)? " ans
[[ "${ans^^}" = "Y"* ]] && m menuconfig

bb_cfg="$(sed -n "s/^BR2_PACKAGE_BUSYBOX_CONFIG=//p" .config)" # e.g. "$(TOPDIR)/../busybox_debug.config"
bb_cfg="${bb_cfg/\$(TOPDIR)\/../$BASEDIR}" # "$(TOPDIR)/.." -> "$BASEDIR"
bb_cfg="${bb_cfg:1:-1}" # drop surrounding quotes
if [ ! -e "$bb_cfg" ]; then
	echo "ERROR: BusyBox config '$bb_cfg' doesn't exist!"
	exit 1
fi
bb_cfg_dir="$(dirname "$bb_cfg")" # e.g. "$BASEDIR"
bb_cfg_name="$(basename "$bb_cfg")" # e.g. "busybox_debug.config"
read -erp ">> Tweak local BusyBox config \"$bb_cfg_name\" (y/N)? " ans
if [[ "${ans^^}" = "Y"* ]]; then
	m busybox-menuconfig

	bb_cfg_new="$bb_cfg_dir/$bb_cfg_name.new"
	cp output/build/busybox-*/.config "$bb_cfg_new"
	diff --color "$bb_cfg" "$bb_cfg_new" || :
	read -erp ">> Update \"$bb_cfg_name\" with the above diff (Y/n)? " ans
	[[ "${ans^^}" != "N"* ]] && mv "$bb_cfg_new" "$bb_cfg" # || rm "$bb_cfg_new"
fi

log "Starting build with $BR2_BUILD_JOBS jobs..."
time m -j $BR2_BUILD_JOBS
cp output/images/rootfs.tar.gz "$INITDIR/$BR2_TARBALL"
