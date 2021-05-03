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
	if [ -e /rd.cfg ]; then # attempt getting value from rd.cfg
		value="$(sed -n "s/$opt=//p" /rd.cfg)"
		if [ "$value" ]; then
			echo "$value"
			return
		fi
	fi
	get_cmdline_opt "rd.$opt" # fallback to cmdline
}

# Update temporary ramdisk configuration /rd.cfg
# $1 = opt
# $2 = value
update_opt() {
	opt="$1"
	if [ -z "$opt" ]; then
		dbg "update_opt(): no arguments given, ignoring..."
		return
	fi

	val="$2"
	if [ -e /rd.cfg ]; then
		if grep -q "^$opt=" /rd.cfg; then # existing value
			sed "s|^$opt=.*|$opt=$val|" -i /rd.cfg
		else # new value
			echo "$opt=$val" >> /rd.cfg
		fi
	else # new file + value
		echo "$opt=$val" > /rd.cfg
	fi

	sync
	dbg "update_opt($1, $2): updated /rd.cfg:"
	cat /rd.cfg >> /init.log
}
