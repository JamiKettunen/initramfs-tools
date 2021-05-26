#!/bin/bash -e

# Runtime vars
###############
BASEDIR="$(readlink -f "$(dirname "$0")")"
INITDIR="$BASEDIR/.."
NON_INTERACTIVE=0

# Functions
############
log() { echo ">> $1"; }
die() { echo "$1" >&2; exit 1; }
err() { die "ERROR: $1"; }
usage() { die "usage: $0 [-N]"; }
parse_args() {
	while getopts ":N" OPT; do
		case "$OPT" in
			N) NON_INTERACTIVE=1 ;;
			*) usage ;;
		esac
	done
}
get_ans() {
	local msg=""
	case $1 in
		"ccache") [ $NON_INTERACTIVE -ne 1 ] && msg="Clean ccache located at ~/.buildroot-ccache (y/N)" || ans="N" ;;
		"updates") [ $NON_INTERACTIVE -ne 1 ] && msg="Pull updates to buildroot tree (Y/n)" || ans="Y" ;;
		"clean") [ $NON_INTERACTIVE -ne 1 ] && msg="Clean previous build output artifacts (y/N)" || ans="N" ;;
		"br_config") [ $NON_INTERACTIVE -ne 1 ] && msg="Regenerate Buildroot .config from \"initramfs_defconfig ${BR2_CONFIGS/,/ }\" (y/N)" || ans="Y" ;;
		"br_menuconfig") [ $NON_INTERACTIVE -ne 1 ] && msg="Run Buildroot menuconfig (y/N)" || ans="N" ;;
		"bb_config") [ $NON_INTERACTIVE -ne 1 ] && msg="Tweak local BusyBox config \"$bb_cfg_name\" (y/N)" || ans="N" ;;
		"bb_config_update") msg="Update \"$bb_cfg_name\" with the above diff (Y/n)" ;;
	esac
	[ $NON_INTERACTIVE -eq 1 ] && return
	read -erp ">> $msg? " ans
}
m() { make BR2_EXTERNAL="$BASEDIR/external" $@; }

# Script
#########
cd "$INITDIR"
. config.sh
cd "$BASEDIR"
parse_args $@

if [ -d $HOME/.buildroot-ccache ]; then
	get_ans ccache
	[[ "${ans^^}" = "Y"* ]] && ccache -d ~/.buildroot-ccache -C
fi

pull_ask=1
if [ ! -d buildroot-git ]; then
	pull_ask=0
	git clone https://git.buildroot.net/buildroot buildroot-git
fi
cd buildroot-git
if [ $pull_ask -eq 1 ]; then
	get_ans updates
	[[ "${ans^^}" != "N"* ]] && git pull --ff-only
fi

patch_count=$(find "$BASEDIR"/patches -type f | wc -l)
log "Adding $patch_count out-of-tree patch(es)..."
cp -r "$BASEDIR"/patches/* .

if [ -d output ]; then
	get_ans clean
	if [[ "${ans^^}" = "Y"* ]]; then
		m -j clean
		rm -r output # "$INITDIR/$BR2_TARBALL"
	fi
fi

gen_cfg=1
if [ -e .config ]; then
	get_ans br_config
	[[ "${ans^^}" != "Y"* ]] && gen_cfg=0
fi
if [ $gen_cfg -eq 1 ]; then
	header_ver="${BR2_KERNEL_HEADERS/./_}" # e.g. "5.12" -> "5_12"
	cat ../external/configs/{initramfs_defconfig,$BR2_CONFIGS} \
		| sed "s/@BR2_KERNEL_HEADERS@/BR2_KERNEL_HEADERS_$header_ver=y/" \
		> "$BASEDIR"/external/configs/final_defconfig
	m final_defconfig
fi

get_ans br_menuconfig
[[ "${ans^^}" = "Y"* ]] && m menuconfig

bb_cfg="$(sed -n "s/^BR2_PACKAGE_BUSYBOX_CONFIG=//p" .config)" # e.g. "$(TOPDIR)/../busybox_debug.config"
bb_cfg="${bb_cfg/\$(TOPDIR)\/../$BASEDIR}" # "$(TOPDIR)/.." -> "$BASEDIR"
bb_cfg="${bb_cfg:1:-1}" # drop surrounding quotes
[ -e "$bb_cfg" ] || err "BusyBox config '$bb_cfg' doesn't exist!"
bb_cfg_dir="$(dirname "$bb_cfg")" # e.g. "$BASEDIR"
bb_cfg_name="$(basename "$bb_cfg")" # e.g. "busybox_debug.config"
get_ans bb_config
if [[ "${ans^^}" = "Y"* ]]; then
	m busybox-menuconfig

	bb_cfg_new="$bb_cfg_dir/$bb_cfg_name.new"
	cp output/build/busybox-*/.config "$bb_cfg_new"
	diff --color "$bb_cfg" "$bb_cfg_new" || :
	get_ans bb_config_update
	[[ "${ans^^}" != "N"* ]] && mv "$bb_cfg_new" "$bb_cfg" # || rm "$bb_cfg_new"
fi

log "Starting build with $BR2_BUILD_JOBS jobs..."
time m -j $BR2_BUILD_JOBS
cp output/images/rootfs.tar.gz "$INITDIR/$BR2_TARBALL"
