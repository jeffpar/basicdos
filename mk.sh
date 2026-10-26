#!/bin/bash
#
# Builds BASIC-DOS on BASIC-DOS (mkdos.sh builds it on MS-DOS 3.20 instead).
# As in mkdos.sh, if pc.js exits normally (ie, via QUIT) and PCJS is set,
# the disk images are then updated with the new binaries: while package.json's
# config.release is "debug", a DEBUG build updates every disk except the
# release diskette and the 64K demo disk, and a FINAL build updates only those
# two; once config.release is "final", a FINAL build updates them all, and a
# DEBUG build updates all but those two (see gulpfile.js).
#
# pc.js builds a bootable BASIC-DOS hard disk (C:) directly from software/src,
# using the system files from the previous build (os/*/OBJ, so run mkdos.sh at
# least once first), software/src/CONFIG.SYS (a serial console, with PATH$
# set to C:\ and C:\TOOLS), and the build tools in software/src/tools.
#
# BASIC-DOS runs os/mk.bat (which builds BOOT, DD, DEV, DOS, CMD, and UTIL),
# then the TESTS and MSB makefiles, and then QUIT, after which pc.js writes
# every new or modified file back to software/src.  If a build step fails,
# type QUIT to keep any changes or use pc.js's "abort" command to discard them.
#
# The machine (COMPAQ DeskPro 386) and C: (30Mb, FAT16, 2K clusters, 512 root
# entries) match mkdos.sh.
#
# Usage: mk.sh [FINAL or DEBUG] [CLEAN] (the same arguments as os/mk.bat, in
# either case).  DEBUG generates DEBUG binaries.  As in mkdos.sh, the default
# is package.json's config.release property, its "version" sets the BASIC-DOS
# version, and each mode keeps its own build outputs (see setMode in
# tools/release.sh), so switching modes rebuilds only what's changed.
#
# CLEAN first deletes the build outputs (using os/mk.bat's CLEAN option, and
# DEL commands for TESTS and MSB), for a clean build.
#
cd "$(dirname "$0")" || exit 1
usage() { echo "Usage: $0 [FINAL or DEBUG] [CLEAN]" >&2; exit 1; }
[ $# -le 2 ] || usage
. tools/release.sh
mode=$(echo "${1:-$release}" | tr a-z A-Z)
[ "$mode" = FINAL ] || [ "$mode" = DEBUG ] || usage
clean=
case "$(echo "$2" | tr a-z A-Z)" in
    "") ;;
    CLEAN) clean=1 ;;
    *) usage ;;
esac
src=software/src
setMode $mode
for f in os/boot/OBJ/BOOT.COM os/dev/OBJ/BASDEV.COM os/dos/OBJ/BASDOS.COM os/cmd/OBJ/COMMAND.COM; do
    if [ ! -f "$src/$f" ]; then echo "error: $src/$f not found (run mkdos.sh first)" >&2; exit 1; fi
done
make="MAKE REL=$mode MAKEFILE"
mk="MK $mode" tests= msb=
if [ -n "$clean" ]; then
    del() { for f in "$@"; do printf ';IF EXISTS("%s") THEN DEL %s' "$f" "$f"; done; }
    mk="MK $mode CLEAN"
    tests=$(del 'OBJ\*.OBJ' 'OBJ\*.MAP' 'OBJ\*.SYM' 'OBJ\*.LST' 'BIN\*.COM' 'BIN\*.EXE')
    msb=$(del 'OBJ\*.OBJ' 'OBJ\*.EXE' 'OBJ\*.MAP' 'OBJ\*.SYM' 'OBJ\*.LST')
fi
tools/pc/pc.js compaq386 $src "CD OS;$mk;CD ..\TESTS$tests;$make;CD ..\MSB$msb;$make;QUIT" \
    --sys=bd:2 --target=30M --fat=16:2048:512 --ram=640K --speed=8 --serial --normalize
code=$?
if [ $code -eq 0 ] && [ -n "$PCJS" ]; then
    if ! npx gulp demos --silent > /dev/null; then
        echo "error: unable to update the demo disks (run \"npx gulp demos\" for details)" >&2
        exit 1
    fi
fi
exit $code
