#!/bin/bash
#
# Copies the BASIC-DOS test binaries and batch files into the specified configuration folder
# (eg, software/src/configs/console/serial/fpe) before boot.sh (in the repository root) or another script in tools/tests boots it.
#
# The files follow the standard BASIC-DOS disk layout: HELP.TXT in the root (with CONFIG.SYS and AUTOEXEC.BAT,
# and the system files that pc.js adds), utilities in BIN, and everything else (test programs, PRIMES, MSBASIC,
# SYMDEB, etc) in TESTS.  A test configuration's CONFIG.SYS sets PATH$ to all three (eg, "A:\;A:\BIN;A:\TESTS"),
# so the tests can be run by name.  There's no SAMPLES folder, since SAMPLES is reserved for the PC DOS BASIC
# samples (see demos/basic), which don't fit on a 360K diskette with everything else.
#
# Only CONFIG.SYS and AUTOEXEC.BAT are tracked in those folders (see software/src/configs/.gitignore);
# everything else is copied here, so build the sources first (see mk.sh) to make sure the copies are current.
#
root=$(cd "$(dirname "$0")/../.." && pwd)
src="$root/software/src"
dir="$1"
if [ ! -f "$dir/CONFIG.SYS" ]; then
    echo "usage: $0 [configuration folder containing CONFIG.SYS]" >&2
    exit 1
fi
files_root=(
    "$src"/os/cmd/HELP.TXT
)
files_bin=(
    "$src"/os/util/OBJ/*.COM
)
files_tests=(
    "$src"/tests/primes/PRIMES.BAS
    "$src"/tests/primes/PRIMES.BAT
    "$src"/tests/bin/*.COM
    "$src"/tests/bin/*.EXE
    "$src"/tests/misc/BD*.BAT
    "$src"/tests/misc/HELLO.BAT
    "$src"/tests/misc/CMDS.BAT
    "$src"/tests/misc/*.BAS
    "$src"/tests/misc/SYMDEB.EXE
    "$src"/msb/OBJ/MSBASIC.EXE
)
#
# copy [subfolder] [files...]
#
# Older versions of this script copied everything into the root, so we also remove any root copy of a file
# that now belongs in a subfolder.
#
copy() {
    local sub="$1"; shift
    local target="$dir${sub:+/$sub}"
    mkdir -p "$target" || exit 1
    for f in "$@"; do
        if [ -f "$f" ]; then
            cp -p "$f" "$target/"
            [ -n "$sub" ] && rm -f "$dir/$(basename "$f")"
        else
            echo "warning: ${f#$root/} not found (has it been built?)" >&2
        fi
    done
}
copy "" "${files_root[@]}"
#
# Older versions of this script also used BASIC, TOOLS, and SAMPLES folders, so remove those copies.
#
rm -rf "${dir:?}/BASIC" "${dir:?}/TOOLS" "${dir:?}/SAMPLES"
copy BIN "${files_bin[@]}"
copy TESTS "${files_tests[@]}"
if [ ! -f "$dir/TESTS/DOSTESTS.COM" ]; then
    echo "error: DOSTESTS.COM is missing from $dir/TESTS" >&2
    exit 1
fi
