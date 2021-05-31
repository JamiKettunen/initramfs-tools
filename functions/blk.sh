# Standalone prep
type dbg >/dev/null || . /functions/core.sh
type begins_with >/dev/null || . /functions/helpers.sh

# Block devices
################

bytes_base=1024 # 1000|1024
tb_threshold=$(($bytes_base*$bytes_base*$bytes_base*$bytes_base))
gb_threshold=$(($bytes_base*$bytes_base*$bytes_base))
mb_threshold=$(($bytes_base*$bytes_base))
kb_threshold=$bytes_base

bytes_to_size_helper() {
	res=$(awk -- 'BEGIN {printf "%.2f\n", ARGV[1]/ARGV[2]}' $1 $2)
	echo "${res%.00} $3"
}

# Returns a human readable size from bytes
# $1 = the bytes
bytes_to_size() {
	bytes=$1
	if [ $bytes -ge $tb_threshold ]; then
		bytes_to_size_helper $bytes $tb_threshold "TiB"
	elif [ $bytes -ge $gb_threshold ]; then
		bytes_to_size_helper $bytes $gb_threshold "GiB"
	elif [ $bytes -ge $mb_threshold ]; then
		bytes_to_size_helper $bytes $mb_threshold "MiB"
	elif [ $bytes -ge $kb_threshold ]; then
		bytes_to_size_helper $bytes $kb_threshold "KiB"
	else
		echo "$bytes B"
	fi
}

ignore_pars_under=$((150*$mb_threshold))
ignore_pars_under_str="$(bytes_to_size $ignore_pars_under)"

# List all detected partitions while taking $ignore_pars_under into account
list_pars() {
	if [ "$PARS" ]; then
		echo "$PARS"
		return
	fi

	pars="$(grep '[0-9]$' /proc/partitions | grep -Ev '(ram|boot)[0-9]+' | awk '{print $4}' | sort -V | awk '{print}' ORS=' ')" # e.g. "sda1 sda2 ... sdf7"
	blks="$(ls /sys/block/ | grep -Ev "(ram|loop|nbd|boot)[0-9]+$|rpmb$" | awk '{print}' ORS=' ')" # e.g. "sda sdb ..."
	for blk in $blks; do # e.g. "sda"
		par_names="$(fdisk -l /dev/$blk | awk '/^Number/,0{if (!/^Number/)print $5}')" # e.g. "ssd\npersist\ncache\n..."
		par_i=0
		for par in $pars; do # e.g. "sda1"
			begins_with "$blk" "$par" || continue # skip partitions for other block devices
			[ "$par" = "$blk" ] && continue # skip "partitions" matching whole block device
			par_i=$((par_i+1))
			par_size=$(blockdev --getsize64 /dev/$par) # e.g. 524288
			[ $par_size -lt $ignore_pars_under ] && continue # ignore too small partitions
			par_size_fancy="$(bytes_to_size $par_size)" # e.g. "512 KiB"
			# FIXME: This method appears to not work for mmcblk* devices!
			par_name="$(echo "$par_names" | awk "NR==$par_i {print}")"

			echo "$par (name '$par_name', size $par_size_fancy)" # e.g. "sda13 (name 'userdata', size 53.63 GiB)"
		done
	done
}

# Attempt mounting /rootfs_par; $rootfs_mount_error codes:
# 0 = None
# 1 = NBD export not found
# 2 = NBD export couldn't be mounted
# 3 = Rootfs partition mount failed
mount_rootfs_par() {
	if grep -q ' /rootfs_par ' /proc/mounts; then
		dbg "blk: mount_rootfs_par(): /rootfs_par already mounted, ignoring..."
		return
	fi
	mkdir -p /rootfs_par

	if begins_with "nbd" "$rootfs"; then
		nbd_export="rootfs"
		nbd_bs=512
		if [ "${rootfs:3:1}" = ":" ]; then # nbd:
			nbd_export="$(echo "$rootfs" | cut -d: -f2)" # e.g. "rootfs"
			nbd_bs=$(echo "$rootfs" | cut -d: -f3) # e.g. 512
			[ -z "$nbd_bs" ] && nbd_bs=512
		fi
		dbg "blk: locating NBD export $nbd_export on $HOST_IP..."
		if ! nbd-client -b $nbd_bs -N "$nbd_export" $HOST_IP /dev/nbd0; then
			rootfs_mount_error=1; return
		fi
		dbg "blk: mounting NBD export $nbd_export with bs=$nbd_bs..."
		if ! mount /dev/nbd0 /rootfs_par; then
			rootfs_mount_error=2; return
		fi
	else # block devices
		if ! mount "$rootfs_par" /rootfs_par; then
			rootfs_mount_error=3; return
		fi
	fi
	# clear potential previous logs from hang() calls
	[ -e /rootfs_par/init.log ] && rm /rootfs_par/init.log
	rootfs_location=/rootfs_par
	rootfs_mount_error=0
}

# Attempt mounting (/rootfs_par &) /rootfs; $rootfs_mount_error codes:
# 0 = None
# 1 = NBD export not found
# 2 = NBD export couldn't be mounted
# 3 = Rootfs partition mount failed
# 4 = Rootfs directory/image not found
# 5 = Rootfs image mount failed
mount_rootfs() {
	mount_rootfs_par
	if grep -q ' /rootfs ' /proc/mounts; then
		dbg "blk: mount_rootfs(): /rootfs already mounted, ignoring..."
		return
	fi
	mkdir -p /rootfs

	if [[ $slash_count -gt 2 && "$rootfs_par" != "/dev/nbd0" ]]; then # file (loopback image) or directory
		rootfs_extra="$(echo "$rootfs" | cut -d/ -f4-)" # e.g. "rootfs_dir" or "rootfs.img"
		rootfs_location="/rootfs_par/$rootfs_extra"
		if [ ! -e "$rootfs_location" ]; then
			rootfs_mount_error=4; return
		fi

		if [ -f "$rootfs_location" ]; then
			rootfs_img="$rootfs_extra" # e.g. "rootfs.img"
		else
			rootfs_dir="$rootfs_extra" # e.g. "rootfs_dir"
		fi
	fi

	# Extra mounting logic for $rootfs_img and $rootfs_dir
	if [ -z "${rootfs_dir}${rootfs_img}" ]; then
		# assume rootfs is on a partition directly
		if [ "$rootfs_par" != "/dev/nbd0" ]; then
			rootfs_type="block device (partition) on $rootfs_par"
		else
			rootfs_type="NBD (network block device) @ $nbd_export on $HOST_IP"
		fi
		[ -e "$rootfs_location/system/build.prop" ] && \
			rootfs_location="$rootfs_location/system" # Android 9+ (system-as-root)?
		mount -o bind "$rootfs_location" /rootfs
	else
		if [ "$rootfs_img" ]; then
			# assume rootfs is on a formatted image file
			rootfs_type="image (loopback) @ $rootfs_img on $rootfs_par"
			load_module loop
			if ! mount "$rootfs_location" /rootfs; then
				rootfs_mount_error=5; return
			fi
		elif [ "$rootfs_dir" ]; then
			# assume rootfs is extracted into a directory
			rootfs_type="directory @ $rootfs_dir on $rootfs_par"
			mount -o bind "$rootfs_location" /rootfs
		fi
	fi
	rootfs_location=/rootfs
	rootfs_mount_error=0
}
