# Standalone prep
if [[ -f /constants && -z "$KERNEL_VER" ]]; then
	type eval_const >/dev/null || . /functions/core.sh
	eval_const KERNEL_VER
fi

# Kernel module support
load_module() {
	[ -d "/lib/modules/$KERNEL_VER" ] || return
	if grep -q "/$1.ko" /lib/modules/$KERNEL_VER/modules.dep; then
		lsmod | grep $1 || modprobe $@
	else
		dbg "load_module(): $1 not found in modules.dep! assuming built-in..."
	fi
}

unload_module() {
	[ -d "/lib/modules/$KERNEL_VER" ] || return
	if grep -q "/$1.ko" /lib/modules/$KERNEL_VER/modules.dep; then
		lsmod | grep $1 && modprobe -r $@
	else
		dbg "unload_module(): $1 not found in modules.dep! assuming built-in..."
	fi
}
