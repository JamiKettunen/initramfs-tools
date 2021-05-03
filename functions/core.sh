# Logging
##########

# Log a message into the boot console & /init.log
log() { echo "$1" | tee -a /init.log; }

# Log a message into the kernel message ring buffer, boot console & /init.log
# $1 = message
# $2 = optional kmsg loglevel (default: 6)
log_kmsg() {
	log "$1"
	echo "<${2:-6}>initrd: $1" > /dev/kmsg
}

# Append a debug message into /init.log
dbg() { echo "$1" >> /init.log; }

# Log a debug message into the kernel message ring bufferm & /init.log
# $1 = message
# $2 = optional kmsg loglevel (default: 6)
dbg_kmsg() {
	dbg "$1"
	echo "<${2:-6}>initrd: $1" > /dev/kmsg
}

# Hooks
########

# Get a hook path by name
# $1 = hook name, e.g. rndis
hook_get() {
	hook_name="$1"
	hook_matches="$(find /hooks -type f 2>/dev/null | grep "$hook_name")"
	[ -z "$hook_matches" ] && return # none found

	hooks_count=$(echo "$hook_matches" | wc -l)
	if [ $hooks_count -eq 1 ]; then
		echo "$hook_matches"
	else
		dbg "WARNING: More than one match for hook '$hook_name' found, returning first of:"
		dbg "$hook_matches"
		echo "$hook_matches" | head -1
	fi
}

# Run a hook by name manually
# $1 = hook name, e.g. rndis
hook_exec() {
	hook_name="$1"
	found_hook="$(hook_get "$hook_name")"
	[ "$found_hook" ] && . "$found_hook" || dbg "hook_exec(): hook '$hook_name' not found, ignoring..."
}

# Eval and add a new constant into /constants
# $1 = name
# $2 = value
add_const() {
	eval "$1=\"$2\""
	echo "$1=$2" >> /constants
}

# Evaluate constant value(s) stored in /constants
eval_const() {
	for const; do # loop $@
		found_const="$(grep "^$1=" /constants)"
		[ "$found_const" ] \
			&& eval "$1=\"$(sed -n "s/$1=//p" /constants)\"" \
			|| dbg "eval_const(): couldn't find '$1', not evaluating..."
		shift
	done
}

# Print the usual telnet header and get an ash shell (on the boot console)
shell() {
	cat /etc/issue.net
	setsid cttyhack ash
}
