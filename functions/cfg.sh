# Standalone prep
type dbg >/dev/null || . /functions/core.sh
type get_cmdline_opt >/dev/null || . /functions/opts.sh

# Prepare for external rd.cfg support
setup_rd_config() {
	config_par=$(get_cmdline_opt "rd.config") # e.g. /dev/sda13
	if [ "$config_par" ]; then
		dbg "setup_rd_config(): config_par=$config_par"
		mkdir /tmpmnt
		dbg_err mount $config_par /tmpmnt || return
		if [ -e /tmpmnt/rd.cfg ]; then
			cp /tmpmnt/rd.cfg /
			cat /rd.cfg >> /init.log
		fi
		umount /tmpmnt && rmdir /tmpmnt
	fi
}
