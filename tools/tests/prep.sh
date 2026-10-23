#!/bin/bash
#
# Copies the BASIC-DOS test binaries and batch files into the specified configuration folder
# (eg, software/src/configs/console/serial/fpe) before boot.sh (in the repository root) or another script in tools/tests boots it.
#
# The files come from software/manifest.txt: HELP.TXT from ROOT (pc.js adds the system files, and each configuration
# has its own CONFIG.SYS and AUTOEXEC.BAT), utilities from EXT in EXT, the DEMOS and TESTS files together in TESTS,
# the TESTS/REGRESS files (the regression tests) in TESTS\REGRESS, the TESTS/MISC files (other test programs) in
# TESTS\MISC, and the TOOLS files (except MSBASIC) in TOOLS.  A test configuration's CONFIG.SYS sets PATH$ to all of
# them except the TESTS subfolders (eg, "A:\;A:\EXT;A:\TESTS;A:\TOOLS"); the tests in TESTS\REGRESS are run by
# REGRESS.BAT (in TESTS), by path, or after CD \TESTS\REGRESS.  There's no SAMPLES folder, since only the BASIC-DOS
# disks built by gulpfile.js include the PC DOS BASIC samples.
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
files_ext=($(manifest EXT))
#
# A diskette configuration (whose PATH$ is on A:) leaves out the EXT utilities that work on entire volumes (CHKDSK,
# DISKCOPY, FORMAT, LABEL, and SYS), which no test uses, to keep enough free space on a 360K test floppy for MOVES and
# FCBTESTS; use the hd configuration to test them.
#
if grep -q 'PATH\$="A:' "$dir/CONFIG.SYS"; then
    files_ext=($(printf '%s\n' "${files_ext[@]}" | grep -v -E '/(CHKDSK|DISKCOPY|FORMAT|LABEL|SYS)\.BAS$'))
fi
files_tests=($(manifest DEMOS) $(manifest TESTS))
files_regress=($(manifest TESTS/REGRESS))
files_misc=($(manifest TESTS/MISC))
#
# MSBASIC.EXE isn't needed in a test configuration (bench.sh copies its own), and leaving it out keeps enough free
# space on a 360K test floppy for FCBTESTS, which writes a 16643-byte file.
#
files_tools=($(manifest TOOLS | grep -v '/MSBASIC\.EXE$'))
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
# Older versions of this script also used BASIC, BIN (now EXT), and SAMPLES folders, so remove those copies; EXT,
# TESTS, and TOOLS are recreated, since older versions put the test programs (and the tools) in other folders, and EXT
# may hold utilities that this configuration leaves out.
#
rm -rf "${dir:?}/BASIC" "${dir:?}/BIN" "${dir:?}/SAMPLES" "${dir:?}/EXT" "${dir:?}/TESTS" "${dir:?}/TOOLS"
copy EXT "${files_ext[@]}"
copy TESTS "${files_tests[@]}"
copy TESTS/REGRESS "${files_regress[@]}"
copy TESTS/MISC "${files_misc[@]}"
copy TOOLS "${files_tools[@]}"
if [ ! -f "$dir/TESTS/REGRESS/DOSTESTS.COM" ]; then
    echo "error: DOSTESTS.COM is missing from $dir/TESTS/REGRESS" >&2
    exit 1
fi
