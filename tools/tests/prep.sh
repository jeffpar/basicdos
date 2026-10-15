#!/bin/bash
#
# Copies the BASIC-DOS test binaries and batch files into the specified configuration folder
# (eg, software/src/configs/console/serial/fpe) before boot.sh (in the repository root) or another script in tools/tests boots it.
#
# The files come from software/manifest.txt: HELP.TXT from ROOT (pc.js adds the system files, and each configuration
# has its own CONFIG.SYS and AUTOEXEC.BAT), utilities from BIN in BIN, and the DEMOS and TESTS files together in TESTS.
# A test configuration's CONFIG.SYS sets PATH$ to all three (eg, "A:\;A:\BIN;A:\TESTS"), so the tests can be run by
# name.  There's no SAMPLES folder, since only the BASIC-DOS disks built by gulpfile.js include the PC DOS BASIC samples.
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
#
# manifest [section]
#
# Prints the files in a section of software/manifest.txt, with wildcards expanded.
#
manifest() {
    local f
    for f in $(awk -v s="[$1]" '/^\[/ {on = ($1 == s); next} on && NF && $1 !~ /^#/ {print $1}' "$root/software/manifest.txt"); do
        echo "$root"/$f
    done
}
files_root=($(manifest ROOT | grep -v -e '/CONFIG\.SYS$' -e '\.COM$'))
files_bin=($(manifest BIN))
files_tests=($(manifest DEMOS) $(manifest TESTS))
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
