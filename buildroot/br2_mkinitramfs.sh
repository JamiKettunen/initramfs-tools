#!/bin/bash -e
ROOT="$(find "$PWD"/output/build/buildroot-fs/ -maxdepth 1 -type d | sed '1d' | head -1)/target"

# keep just fsck's & resize2fs from e2fsprogs
rm -f "$ROOT"/bin/{chattr,compile_et,lsattr,mk_cmds}
rm -f "$ROOT"/sbin/{badblocks,dumpe2fs,e2freefrag,e2label,e2mmpstatus,e2undo,e4crypt,filefrag,logsave,mke2fs,mkfs.ext*,mklost+found,tune2fs}

# TODO: Also create shadow+passwd in a post_build.sh script for build to pass?
rm -rf "$ROOT"/etc/{cron.d/,network/,e2scrub.conf,mke2fs.conf,passwd,shadow,shells}

rm -rf "$ROOT"/usr/share/{et,ss}/

if [ ! -e "$ROOT"/bin/bash ]; then
	bash_scripts="$(grep -r "$ROOT" -e '^#!/bin/bash$' || :)"
	if [ "$bash_scripts" ]; then
		echo "$bash_scripts" | cut -d':' -f1 | xargs rm
		bash_scripts_count=$(echo "$bash_scripts" | wc -l)
		echo "Purged $bash_scripts_count bash scripts as /bin/bash didn't exist!"
	fi
fi

empty_dirs_count=$(find "$ROOT" -depth -empty -print -delete | wc -l)
[ $empty_dirs_count -gt 0 ] && echo "Cleaned up $empty_dirs_count empty directories!"
