#!/bin/bash -e
BASEDIR="$(readlink -f "$(dirname "$0")")"
cd "$BASEDIR"

##########
# Config
##########
. config.sh

#############
# Functions
#############
log() { echo ">> $1"; }
warn() { echo "WARN: $1"; }
err() {
	echo "ERROR: $1"
	rm -rf initramfs/
	exit 1
}
setup_br2() {
	if [[ -e "$BR2_TARBALL" && -z "$BR2_SKIP_BUILD" ]]; then
		read -rp ">> Update Buildroot tarball (y/N)? " update_br
		[[ "${update_br^^}" = "Y"* ]] && BR2_SKIP_BUILD=0 || BR2_SKIP_BUILD=1
	elif [ ! -e "$BR2_TARBALL" ]; then
		BR2_SKIP_BUILD=0
	fi

	[ $BR2_SKIP_BUILD -eq 0 ] \
		&& bash -c "$BASEDIR/buildroot/build.sh" \
		|| log "Skipping Buildroot tarball rebuild..."

	[ -e "$BR2_TARBALL" ] || err "Buildroot tarball '$BR2_TARBALL' doesn't exist!"
}
item_in_array() {
	local item match="$1"
	shift
	for item; do [ "$item" = "$match" ] && return 0; done
	return 1
}
setup_kmodules() {
	if [ -z "$KERNEL_MODULES_DIR" ]; then
		warn "Skipping kernel modules due to KERNEL_MODULES_DIR being empty!"
		return
	fi
	if [ ! -e "$KERNEL_MODULES_DIR" ]; then
		warn "Skipping kernel modules due to '$KERNEL_MODULES_DIR' not existing!"
		return
	fi
	modules_dep="$(find "$KERNEL_MODULES_DIR" -type f -name modules.dep 2>/dev/null || :)"
	if [ -z "$modules_dep" ]; then
		warn "Skipping kernel modules as no modules.dep was found under '$KERNEL_MODULES_DIR'!"
		return
	fi

	modules="$(dirname "$modules_dep")" # e.g. ".../lib/modules/5.12.0-msm8998"
	modules_len=${#modules} # e.g. 105
	kver="$(basename "$modules")" # e.g. "5.12.0-msm8998"
	log "Adding configured kernel modules for v$kver..."
	all_modules="$(find "$modules" -type f -name "*.ko*")"
	builtins_file="$modules/modules.builtin"
	builtins="$(<"$builtins_file")"
	rd_modules="initramfs/lib/modules/$kver"
	probe_modules=()
	skip_modules=()

	[[ "$builtins" = *"/udc-core.ko"* ]] || \
		warn "Couldn't find udc-core (USB_GADGET) as a built-in (=y); USB gadget likely won't work!"

	for mod in "${KERNEL_MODULES_COPY[@]}" "${KERNEL_MODULES_PROBE[@]}"; do
		item_in_array "$mod" "${skip_modules[@]}" && continue # skip over already processed items
		mod_path="$(echo -e "$all_modules" | grep "/$mod.ko" || :)" # ".../kernel/.../mod.ko"
		mod_path="${mod_path:$((modules_len+1))}" # drop absolute path prefix
		if [ -z "$mod_path" ]; then
			[[ "$builtins" = *"/$mod.ko"* ]] || \
				warn "Skipping non-existant kernel module '$mod' (which also isn't a built-in)!"
			skip_modules+=($mod)
			continue # skip modules that are built-ins (or don't exist)
		fi

		dep_paths="$(sed -n "s|^$mod_path: ||p" "$modules_dep")"
		for mod_file in $mod_path $dep_paths; do # e.g. "kernel/.../mod.ko"
			[ -e "$rd_modules/$mod_file" ] && continue # skip copying existing modules
			mod_dir="$(dirname "$mod_file")" # e.g. "kernel/drivers/usb/gadget"
			dst_dir="$rd_modules/$mod_dir"
			[ -e "$dst_dir" ] || mkdir -p "$dst_dir"
			cp "$modules/$mod_file" "$dst_dir"/
			skip_modules+=($mod)
		done

		if item_in_array "$mod" "${KERNEL_MODULES_PROBE[@]}" \
			&& ! item_in_array "$mod" "${probe_modules[@]}"; then
			probe_modules+=($mod)
		fi
	done

	log "Copying over modules.builtin to avoid failures when probing built-ins..."
	mkdir -p "$rd_modules" # in case there's just built-ins
	cp "$builtins_file" "$rd_modules" # {,*.bin}
	log "Running depmod to (re)generate modules.dep and such files..."
	# avoid warnings about unneeded modules.order file
	depmod -b initramfs $kver 2>&1 | grep -v "modules.order" || :

	mod_count=$(find $rd_modules -type f -name "*.ko*" | wc -l)
	mod_size=$(du -sh "$rd_modules" | awk '{print $1}')
	log "Copied $mod_count modules ($mod_size) under /lib/modules!"

	if [[ $mod_count -gt 0 && ${#probe_modules[@]} -gt 0 ]]; then
		if ! item_in_array "load-modules" "${HOOKS_ENABLE[@]}"; then
			log "Including 'load-modules' hook to probe ${#probe_modules[@]} modules on boot"
			HOOKS_ENABLE+=(load-modules)
		fi
		# replace user-defined list with modules *actually* found in the list
		KERNEL_MODULES_PROBE=(${probe_modules[@]})
	fi
}
hook_present() { item_in_array "$1" "${HOOKS_ENABLE[@]}" "${HOOKS_EXTRA[@]}"; }
setup_hooks() {
	cp -r {hooks,functions} initramfs/
	enabled_hooks="${HOOKS_ENABLE[@]}"
	extra_hooks="${HOOKS_EXTRA[@]}"
	log "Enabled hooks: ${enabled_hooks:-<none>}"
	log "Extra hooks: ${extra_hooks:-<none>}"
	for hook_file in $(find initramfs/hooks -type f | sort -V); do
		hook="${hook_file:16}" # drop "initramfs/hooks/" prefix
		hook_dir="$(dirname "$hook")" # e.g. "late" / "."
		full_hook_name="$(basename "$hook")" # e.g. "late/00-hang" -> "00-hang"
		[[ "$full_hook_name" != [0-9]* ]] && \
			err "Using unordered hooks (such as $full_hook_name) creates an unpredictable
       loading order & isn't supported; please rename your hooks so they begin with numbers!"
		hook_name="$(echo "$full_hook_name" | cut -d'-' -f2-)" # e.g. "00-hang" -> "hang"
		hook="$hook_dir/$hook_name" # e.g. "late/hang"
		[[ "$hook" = "./"* ]] && hook="${hook:2}" # drop "./" prefix

		if ! hook_present "$hook"; then
			#log "Dropping unused '$hook' hook from initramfs..."
			rm "$hook_file"
			continue # avoid extra hook move in this case
		fi

		if [ -e "extras/$hook" ]; then
			extra_files=$(find "extras/$hook/" \( ! -name "deploy" ! -type d \) | wc -l)
			if [ $extra_files -gt 0 ]; then
				log "Copying extra deployment files for '$hook' hook..."
				cp -r "extras/$hook"/* initramfs/
			fi

			if [ -e "extras/$hook/deploy" ]; then
				log "Running extra deployment script for '$hook' hook..."
				. "extras/$hook/deploy"
			fi
		fi

		if ! item_in_array "$hook" "${HOOKS_ENABLE[@]}"; then
			#log "Moving extra hook '$hook' into /hooks/extra/..."
			extra_hook="${hook_file:0:15}/extra/${hook_file:16}" # e.g. "initramfs/hooks/extra/late/50-umtprd"
			extra_dir="$(dirname "$extra_hook")" # e.g. "initramfs/hooks/extra/late"
			[ -e "$extra_dir" ] || mkdir -p "$extra_dir"
			mv "$hook_file" "$extra_dir"
		fi
	done
	if hook_present "load-modules"; then
		modules_to_probe="${KERNEL_MODULES_PROBE[@]}"
		sed "s/@KERNEL_MODULES_PROBE@/$modules_to_probe/" -i initramfs/hooks/*load-modules
	fi
	if hook_present "msm-fb-refresher"; then
		if [ $BOOT_FB_REFRESHER_TIMEOUT -gt 0 ]; then
			sed "s/@FB_REFRESHER_TIMEOUT@/$BOOT_FB_REFRESHER_TIMEOUT/" -i initramfs/hooks/*msm-fb-refresher
		else
			sed "s/^timeout @FB_REFRESHER_TIMEOUT@ //" -i initramfs/hooks/*msm-fb-refresher
		fi
	else
		rm initramfs/usr/bin/msm-fb-refresher
	fi
	rmdir initramfs/hooks/late 2>/dev/null && rmdir initramfs/hooks 2>/dev/null || :
	rm -f initramfs/deploy # in case any extras/*/deploy scripts were run
}
setup_overlay() {
	overlay_items=$(ls -1 overlay | wc -l)
	[ $overlay_items -eq 0 ] && return
	overlay_size="$(du -sh overlay | awk '{print $1}')"
	log "Applying overlay of $overlay_size..."
	cp -r overlay/* initramfs/
}
setup_misc() {
	if [ $BOOT_DROP_TO_SHELL -eq 1 ]; then
		sed -e 's/@HANG_MSG@/Dropping to shell (ash)...\n/' \
			-e 's/@HANG_CMD@/shell/' \
			-i initramfs/init_functions
	else
		sed -e 's/@HANG_MSG@/Hanging here forever, please reboot your device!/' \
			-e 's/@HANG_CMD@/sleep infinity/' \
			-i initramfs/init_functions
	fi
	sed -e "s/@USB_IFACE@/$BOOT_RNDIS_IFACE/" -i initramfs/init
	# remove placeholder files for previously empty directories
	find initramfs/ -type f -name ".keep" -delete
}
setup_splash() {
	[ -z "$BOOT_SPLASH" ] && return
	if [ ! -e "$BOOT_SPLASH" ]; then
		warn "The splash image file '$BOOT_SPLASH' doesn't exist, skipping..."
		return
	fi

	log "Setting boot splash image to '$BOOT_SPLASH'..."
	splash_file="$(readlink -f "$BOOT_SPLASH")"
	type="$(file "$BOOT_SPLASH")"
	if [[ "$type" != *"gzip compressed data"* ]]; then
		if [[ "$type" != *"Netpbm image data"* ]]; then
			warn "The splash image file isn't a valid Netpbm image, skipping..."
			return
		fi
		gzip -nc "$splash_file" > initramfs/splash.ppm.gz
	else
		cp "$splash_file" initramfs/splash.ppm.gz
	fi
}
create_cpio() {
	cpio_name="initramfs${CPIO_EXTRA_NAME}.cpio"
	if [ $CPIO_RM_EXISTING -eq 1 ]; then
		log "Removing potentially existing '$cpio_name'* files..."
		rm -f "$cpio_name"*
	fi

	if [[ "$CPIO_COMPRESS" = "gz"* ]]; then
		compress_cmd="gzip --best"
		[ $CPIO_COMPRESS_KEEP_SRC -eq 1 ] && compress_cmd+=" --keep"
		compress_ext=".gz"
	elif [[ "$CPIO_COMPRESS" = "lz4"* ]]; then
		compress_cmd="lz4 -l --best --favor-decSpeed --quiet -m"
		# FIXME: "lz4 --rm" doesn't appear to delete the source file?
		[ $CPIO_COMPRESS_KEEP_SRC -ne 1 ] && compress_cmd+=" --rm"
		compress_ext=".lz4"
	fi
	cpio_final="${cpio_name}${compress_ext}"

	log "Creating '$cpio_final'..."
	cd initramfs
	chmod +x init
	find ./* -print0 | cpio --quiet --null --create --format=newc > "$BASEDIR/$cpio_name"
	[ "$compress_cmd" ] && $compress_cmd "$BASEDIR/$cpio_name"
	cd ..
}

##########
# Script
##########
setup_br2

[ -d initramfs ] && rm -rf initramfs
mkdir -p extras functions hooks initramfs overlay

log "Extracting Buildroot tarball..."
tar -xf "$BR2_TARBALL" -C initramfs
log "Copying over init scripts & extra directories..."
cp init{,_functions} initramfs/

[[ ${#KERNEL_MODULES_COPY[@]} -gt 0 || ${#KERNEL_MODULES_PROBE[@]} -gt 0 ]] \
	&& setup_kmodules
setup_hooks
setup_overlay
setup_misc
setup_splash
create_cpio

rm -rf initramfs
log "Done, size is $(du "$BASEDIR/$cpio_final" | awk '{print $1}')K"
