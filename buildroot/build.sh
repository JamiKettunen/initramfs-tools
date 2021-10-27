#!/bin/bash -e

# Runtime vars
###############
BASEDIR="$(readlink -f "$(dirname "$0")")"
INITDIR="$BASEDIR/.."
CONFIG="config.custom.sh"
NON_INTERACTIVE=0

# Functions
############
log() { echo ">> $1"; }
die() { echo "$1" >&2; exit 1; }
err() { die "ERROR: $1"; }
usage() { die "usage: $0 [-c alternate_config.sh] [-N]"; }
parse_args() {
	while [ $# -gt 0 ]; do
		case $1 in
			-c|--config) CONFIG="$2"; shift ;;
			-N|--non-interactive) NON_INTERACTIVE=1 ;;
			*) usage ;;
		esac
		shift
	done
}
get_ans() {
	local msg=""
	case $1 in
		"ccache") [ $NON_INTERACTIVE -ne 1 ] && msg="Clean ccache located at ~/.buildroot-ccache (y/N)" || ans="N" ;;
		"updates") [ $NON_INTERACTIVE -ne 1 ] && msg="Pull updates to buildroot tree (Y/n)" || ans="Y" ;;
		"clean") [ $NON_INTERACTIVE -ne 1 ] && msg="Clean previous build output artifacts (y/N)" || ans="N" ;;
		"br_config") [ $NON_INTERACTIVE -ne 1 ] && msg="Regenerate Buildroot .config from \"${BR2_CONFIGS[@]}\" (y/N)" || ans="Y" ;;
		"br_menuconfig") [ $NON_INTERACTIVE -ne 1 ] && msg="Run Buildroot menuconfig (y/N)" || ans="N" ;;
		"bb_config") [ $NON_INTERACTIVE -ne 1 ] && msg="Tweak local BusyBox config \"$bb_cfg_name\" (y/N)" || ans="N" ;;
		"bb_config_update") msg="Update \"$bb_cfg_name\" with the above diff (Y/n)" ;;
	esac
	[ $NON_INTERACTIVE -eq 1 ] && return
	read -erp ">> $msg? " ans
}
join_arr() { local IFS="$1"; shift; echo "$*"; }
m() { make BR2_EXTERNAL="$BASEDIR/external" $@; }

# Script
#########
cd "$INITDIR"
. config.sh
parse_args "$@"
[ -r "$CONFIG" ] && . "$CONFIG" || CONFIG="config.sh"
cd "$BASEDIR"

if [ -d $HOME/.buildroot-ccache ]; then
	get_ans ccache
	[[ "${ans^^}" = "Y"* ]] && ccache -d ~/.buildroot-ccache -C
fi

if [[ "$BR2_SOURCE" = *"git"* && "$BR2_SOURCE" != *".tar"* ]]; then
	buildroot_git=1
	buildroot_dir="buildroot-git"
else
	buildroot_git=0
	buildroot_dir="buildroot-src"
fi
pull_ask=$buildroot_git
if [ ! -d "$buildroot_dir" ]; then
	if [ $buildroot_git -eq 1 ]; then
		git clone "$BR2_SOURCE" "$buildroot_dir"
		pull_ask=0
	else
		mkdir "$buildroot_dir"
		src_tarball="$(basename "$BR2_SOURCE")"
		wget "$BR2_SOURCE" -O "$src_tarball"
		tar -xf "$src_tarball" -C "$buildroot_dir"
		if [[ "$(ls "$buildroot_dir")" = "buildroot-"* ]]; then
			shopt -s dotglob
			mv "$buildroot_dir"/buildroot-*/* "$buildroot_dir"/
			rmdir "$buildroot_dir"/buildroot-*
		fi
	fi
fi
cd "$buildroot_dir"
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

BR2_CONFIGS=(initramfs_defconfig ${BR2_CONFIGS[@]})
gen_cfg=1
if [ -e .config ]; then
	get_ans br_config
	[[ "${ans^^}" != "Y"* ]] && gen_cfg=0
fi
if [ $gen_cfg -eq 1 ]; then
	header_ver="${BR2_KERNEL_HEADERS/./_}" # e.g. "5.12" -> "5_12"
	$BR2_CCACHE && BR2_CCACHE=y || BR2_CCACHE=n # e.g. true -> y

	cfg_files="$(join_arr , "${BR2_CONFIGS[@]}")"
	[ ${#BR2_CONFIGS[@]} -gt 1 ] && cfg_files="{$cfg_files}"
	eval "sed '\$s/$/\n/' -s ../external/configs/$cfg_files" \
		| sed -e "s/@BR2_KERNEL_HEADERS@/BR2_KERNEL_HEADERS_$header_ver=y/" \
		      -e "s/@BR2_CCACHE@/BR2_CCACHE=$BR2_CCACHE/" \
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
