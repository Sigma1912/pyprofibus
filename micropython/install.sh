#!/bin/sh
#
# Install pyprofibus on a Micropython board.
#

basedir="$(dirname "$0")"
[ "$(echo "$basedir" | cut -c1)" = '/' ] || basedir="$PWD/$basedir"

rootdir="$(realpath -m "$basedir/..")"

die()
{
	echo "ERROR: $*" >&2
	exit 1
}

echos()
{
	printf '%s' "$*"
}

rootpath()
{
	realpath --relative-base="$rootdir" "$@"
}

pyboard()
{
	"$pyboard" -d "$dev" "$@" || die "pyboard: $pyboard failed."
}

build()
{
	echo "=== build ==="

	cd "$rootdir" || die "Failed to switch to root dir."

	local gsds="$(rootpath -e misc/*.gsd *.gsd)"
	local pys="$(find pyprofibus/ -name '*.py') $(find stublibs/ -name '*.py') $(rootpath -e example_*.py)"
	local confs="$(rootpath -e *.conf)"

	local gsdparser_opts="--dump-strip --dump-notext --dump-noextuserprmdata \
		--dump-module '6ES7 138-4CA01-0AA0 PM-E DC24V' \
		--dump-module '6ES7 132-4BB30-0AA0  2DO DC24V' \
		--dump-module '6ES7 132-4BB30-0AA0  2DO DC24V' \
		--dump-module '6ES7 131-4BD01-0AA0  4DI DC24V' \
		--dump-module 'Master_O Slave_I  1 by unit' \
		--dump-module 'Master_I Slave_O  1 by unit' \
		--dump-module 'dummy output module' \
		--dump-module 'dummy input module' \
		$modules"

	local targets=
	[ -n "$clean" ] && local targets="$targets clean"
	local targets="$targets all"
	for target in $targets; do
		echo "--- $target ---"
		make -j4 -f "$rootdir/micropython/Makefile" \
			SRCDIR="$(rootpath -m "$rootdir")" \
			MARCH="$march" \
			GSDPARSER_OPTS="$gsdparser_opts" \
			PYS="$pys" \
			GSDS="$gsds" \
			CONFS="$confs" \
			$target || die "make failed."
	done
}

transfer()
{
	local from="$1"
	local to="$2"

	if [ -d "$from" ]; then
		pyboard -f mkdir "$to"
		for f in "$from"/*; do
			transfer "$f" "$to/$(basename "$f")"
		done
		return
	fi
	pyboard -f cp "$from" "$to"
}

transfer_to_device()
{
	echo "=== transfer to device $dev ==="

	pyboard -c 'import flashbdev, uos; uos.umount("/"); uos.VfsLfs2.mkfs(flashbdev.bdev); uos.mount(uos.VfsLfs2(flashbdev.bdev), "/")'
	for f in $builddir/*; do
		transfer "$f" :/"$(basename $f)"
	done
	pyboard --no-follow -c 'import machine; machine.reset()'
}

builddir="$rootdir/build/micropython"
dev="/dev/ttyUSB0"
march="xtensa"
pyboard="pyboard.py"
modules=
clean=

while [ $# -ge 1 ]; do
	[ "$(echos "$1" | cut -c1)" != "-" ] && break

	case "$1" in
	-h|--help)
		echo "install.sh [OPTIONS] [TARGET-UART-DEVICE]"
		echo
		echo "TARGET-UART-DEVICE:"
		echo " Target serial device. Default: /dev/ttyUSB0"
		echo
		echo "Options:"
		echo " -c|--clean          Clean before build."
		echo " -a|--march ARCH     Target architecture for cross compile. Default: xtensa"
		echo " -m|--module NAME    Include GSD module."
		echo " -p|--pyboard PATH   Path to pyboard executable. Default: pyboard.py"
		echo " -h|--help           Show this help."
		exit 0
		;;
	-a|--march)
		shift
		march="$1"
		;;
	-p|--pyboard)
		shift
		pyboard="$1"
		;;
	-m|--module)
		shift
		modules="$modules --dump-module '$1'"
		;;
	-c|--clean)
		clean=1
		;;
	*)
		die "Unknown option: $1"
		;;
	esac
	shift
done
if [ $# -ge 1 ]; then
	dev="$1"
	shift
fi
if [ $# -ge 1 ]; then
	die "Too many arguments."
fi

build
transfer_to_device