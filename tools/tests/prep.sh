#!/bin/bash
#
# Copies the BASIC-DOS test binaries and batch files into the specified configuration folder
# (eg, src/configs/console/serial/fpe) before boot.sh (in the repository root) or another script in tools/tests boots it.
#
# The files come from manifest.txt (nothing from ROOT, since pc.js adds the system files, and each configuration
# has its own CONFIG.SYS and, if needed, AUTOEXEC.BAT): programs (and HELP.TXT) from EXT/CMD in EXT\CMD, BASIC utilities from EXT/BAS in EXT\BAS, the libraries from EXT/DLL in EXT\DLL, the DEMOS and TESTS
# files together in TESTS (only TESTS on a diskette; see below),
# the TESTS/REGRESS files (the regression tests) in TESTS\REGRESS, the TESTS/MISC files (other test programs) in
# TESTS\MISC, and the TOOLS files (except MSBASIC, and SYMDEB on a diskette) in TOOLS.  A test configuration's CONFIG.SYS sets PATH$ to all of
# them except TESTS and its subfolders (eg, "A:\;A:\EXT\CMD;A:\EXT\BAS;A:\TOOLS"); the tests are run by path or after CD \TESTS
# (or CD \TESTS\REGRESS), and those in TESTS\REGRESS by REGRESS.BAT (in TESTS), too.  There's no TESTS\SAMPLES folder, since only the BASIC-DOS
# hard disk built by gulpfile.js includes the PC DOS BASIC samples (other than DONKEY.BAS, which is in DEMOS).
#
# Only CONFIG.SYS and AUTOEXEC.BAT are tracked in those folders (see src/configs/.gitignore);
# everything else is copied here, so build the sources first (see mk.sh) to make sure the copies are current.
#
root=$(cd "$(dirname "$0")/../.." && pwd)
src="$root/src"
dir="$1"
if [ ! -f "$dir/CONFIG.SYS" ]; then
    echo "usage: $0 [configuration folder containing CONFIG.SYS]" >&2
    exit 1
fi
#
# manifest [section]
#
# Prints the files in a section of manifest.txt, with wildcards expanded.
#
manifest() {
    local f
    for f in $(awk -v s="[$1]" '/^\[/ {on = ($1 == s); next} on && NF && $1 !~ /^#/ {print $1}' "$root/manifest.txt"); do
        echo "$root"/$f
    done
}
files_cmd=($(manifest EXT/CMD))
files_bas=($(manifest EXT/BAS))
files_dll=($(manifest EXT/DLL))
files_tests=($(manifest DEMOS) $(manifest TESTS))
files_regress=($(manifest TESTS/REGRESS))
files_misc=($(manifest TESTS/MISC))
#
# A diskette configuration (whose PATH$ is on A:) leaves out the EXT/BAS utilities that work on entire volumes (CHKDSK,
# DISKCOPY, FORMAT, LABEL, and SYS) or that no diskette test runs (ATTRIB, CLAUDE, COMP, and MODE), and EXT/CMD's DEBUG.COM (the largest EXT program, which no diskette test uses), the DEMOS files (eg, DIR.BAS and PAINT.BAS), and the TESTS files that only run by
# hand (BENCH.BAS, STRESS.BAT, GFXTESTS.BAS, and MICRO.BAS; bench.sh copies its own BENCH.BAS), which no diskette test
# uses, to keep enough free space on a 360K test floppy for MOVES, FCBTESTS, and HARDERR; use the hd configuration for
# them.  It also has only one of the EXT\DLL libraries, DOSCALLS.DLL (which DLLTESTS needs), since only LINK386 uses the others.
#
if grep -q 'PATH\$="A:' "$dir/CONFIG.SYS"; then
    files_bas=($(printf '%s\n' "${files_bas[@]}" | grep -v -E '/(ATTRIB|CHKDSK|CLAUDE|COMP|DISKCOPY|FORMAT|LABEL|MODE|SYS)\.BAS$'))
    files_cmd=($(printf '%s\n' "${files_cmd[@]}" | grep -v '/DEBUG\.COM$'))
    files_dll=($(printf '%s\n' "${files_dll[@]}" | grep -E '/DOSCALLS\.DLL$'))
    files_tests=($(manifest TESTS | grep -v -E '/(BENCH\.BAS|STRESS\.BAT)$'))
    files_misc=($(printf '%s\n' "${files_misc[@]}" | grep -v -E '/(GFXTESTS|MICRO)\.BAS$'))
fi
#
# MSBASIC.EXE isn't needed in a test configuration (bench.sh copies its own), and leaving it out keeps enough free
# space on a 360K test floppy for FCBTESTS, which writes a 16643-byte file.  No test uses SYMDEB.EXE either, so a
# diskette configuration leaves it out too, to keep enough free space for HARDERR, which extends a file to 12288 bytes.
#
files_tools=($(manifest TOOLS | grep -v '/MSBASIC\.EXE$'))
if grep -q 'PATH\$="A:' "$dir/CONFIG.SYS"; then
    files_tools=($(printf '%s\n' "${files_tools[@]}" | grep -v '/SYMDEB\.EXE$'))
fi
#
# copy [subfolder] [files...]
#
# Older versions of this script copied everything into the root (including HELP.TXT, which is now in EXT), so we
# also remove any root copy of a file that now belongs in a subfolder.
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
#
# Older versions of this script also used BASIC, BIN (now EXT), and SAMPLES folders, so remove those copies; EXT,
# TESTS, and TOOLS are recreated, since older versions put the test programs (and the tools) in other folders, and EXT
# may hold utilities that this configuration leaves out.
#
rm -rf "${dir:?}/BASIC" "${dir:?}/BIN" "${dir:?}/SAMPLES" "${dir:?}/EXT" "${dir:?}/TESTS" "${dir:?}/TOOLS"
copy EXT/CMD "${files_cmd[@]}"
copy EXT/BAS "${files_bas[@]}"
copy EXT/DLL "${files_dll[@]}"
copy TESTS "${files_tests[@]}"
copy TESTS/REGRESS "${files_regress[@]}"
copy TESTS/MISC "${files_misc[@]}"
copy TOOLS "${files_tools[@]}"
if [ ! -f "$dir/TESTS/REGRESS/DOSTESTS.COM" ]; then
    echo "error: DOSTESTS.COM is missing from $dir/TESTS/REGRESS" >&2
    exit 1
fi
