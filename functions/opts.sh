# Standalone prep
type get_value >/dev/null || . /functions/helpers.sh

# Opts
#######

# Get options from kernel command line
# e.g. get_cmdline_opt rd.rootfs -> "/dev/sda13/rootfs.img"
get_cmdline_opt() {
	# shellcheck disable=SC2013
	grep -q "$1=" /proc/cmdline || return
	for opt in $(cat /proc/cmdline); do
		case "$opt" in
			"$1="*) echo "${opt#*=}" ;;
		esac
	done
}

# A nice wrapper around get_cmdline_opt() and reading values from /rd.cfg
# e.g. get_opt rootfs -> "/dev/sda13/rootfs.img"
get_opt() {
	opt="$1"
	local value="$(get_value "$opt" /rd.cfg)" # attempt getting value from rd.cfg
	if [ "$value" ]; then
		echo "$value"
		return
	fi
	get_cmdline_opt "rd.$opt" # fallback to cmdline
}

# Update ramdisk configuration on the specified config partition or temporary /rd.cfg
# $1 = opt
# $2 = value
# $3 = save? (1|0, optional)
update_opt() {
	save="$3"
	config_par="" # e.g. /dev/sda13
	[ "$save" != "0" ] && config_par=$(get_cmdline_opt "rd.config")
	opt_root=""
	if [ "$config_par" ]; then
		mkdir /tmpmnt
		dbg_err mount $config_par /tmpmnt || return
		opt_root="/tmpmnt"
	fi

	opt="$1"
	if [ -z "$opt" ]; then
		dbg "update_opt(): no arguments given, ignoring..."
		return
	fi

	val="$2"
	if [ -e $opt_root/rd.cfg ]; then
		if grep -q "^$opt=" $opt_root/rd.cfg; then # existing value
			sed "s|^$opt=.*|$opt=$val|" -i $opt_root/rd.cfg
		else # new value
			echo "$opt=$val" >> $opt_root/rd.cfg
		fi
	else # new file + value
		echo "$opt=$val" > $opt_root/rd.cfg
	fi

	sync
	dbg "update_opt($1, $2): updated $config_par/rd.cfg:"
	cat $opt_root/rd.cfg >> /init.log
	if [ "$config_par" ]; then
		umount /tmpmnt && rmdir /tmpmnt
	fi
}
