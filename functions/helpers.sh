# Helpers
##########

# Check if a string begins with another string
# $1 = the comparison string
# $2 = the base string
begins_with() { case $2 in "$1"*) true;; *) false;; esac; }

# Count how many times a certain character appears in a string
# $1 = the character
# $2 = the string
count_chars() { echo "$2" | awk -F"$1" '{print NF-1}'; }

# Some quirky distros such as Droidian have a os-release symlink path cycle
# such as the following, which a simple "readlink -f" can't resolve:
# /rootfs/etc/os-release -> ../usr/lib/os-release -> /usr/share/droidian-branding/os-release
# in this case we return /rootfs/usr/share/droidian-branding/os-release here
# $1 = (symlink) file path
# $2 = rootfs location
readlink_hack() {
	path_prefix="$2"
	old_path="$1" # /rootfs/etc/os-release
	new_path="$(readlink "$old_path")" # ../usr/lib/os-release
	if [ -z "$new_path" ]; then
		begins_with "$path_prefix/" "$old_path" \
			&& echo "$old_path" \
			|| echo "$path_prefix$old_path"
		return
	fi
	begins_with "." "$new_path" \
		&& readlink_hack "$(dirname "$old_path")/$new_path" "$path_prefix" \
		|| readlink_hack "$new_path" "$path_prefix"
}

# Get a variable's value from a file
# $1 = variable name
# $2 = file
get_value() {
	[ -e "$2" ] || return # no file
	local match="$(grep "^$1=" "$2")" # e.g. PRETTY_NAME="Distro Name"
	[ "$match" ] || return # no match (or value)
	local value="$(echo "$match" | sed -n "s/^$1=//p")" # e.g. "Distro Name"
	if [[ "${value:0:1}" == '"' || "${value:0:1}" == "'" ]]; then
		echo "${value:1:-1}" # assume quoted string
	else
		echo "$value" # non-quoted strings
	fi
}

# Returns PRETTY_NAME from /etc/os-release
# $1 = rootfs location
get_os_name() {
	os_release="$1/etc/os-release"
	build_prop="$1/build.prop"
	if [[ -e "$os_release" || -L "$os_release" ]]; then # most (if not all) Linux distros
		[[ ! -e "$os_release" && -L "$os_release" ]] \
			&& os_release="$(readlink_hack "$os_release" "$1")"
		local os_name="$(get_value PRETTY_NAME "$os_release")"
		[ "$os_name" ] || return # no PRETTY_NAME :(
		[ "$os_name" = "void" ] && os_name="Void Linux"
		echo "$os_name"
	elif [ -e "$build_prop" ]; then # Android
		# Here we're assuming that system-as-root has only been available since Pie
		# https://source.android.com/setup/start/build-numbers
		local api_level=$(get_value ro.build.version.sdk "$build_prop") # e.g. 28
		[ -z "$api_level" ] && return # invalid Android rootfs build.prop
		droid_ver=$(( api_level - 19 )) # e.g. 9
		echo "Android $droid_ver"
	fi
}
