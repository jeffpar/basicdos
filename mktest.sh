#!/bin/bash
#
# Builds BASIC-DOS ON BASIC-DOS (experimental; mk.sh is still the standard build, using MS-DOS 3.20).
#
# pc.js builds a bootable BASIC-DOS hard disk (C:) directly from software/src, using the system files from
# the previous build (os/*/OBJ, so run mk.sh at least once first), software/src/CONFIG.SYS (a serial console,
# with PATH$ set to C:\ and C:\TOOLS), and the build tools in software/src/tools.  BASIC-DOS runs os/mk.bat
# (which builds BOOT, DD, DEV, DOS, CMD, and UTIL), then the TESTS and MSB makefiles, and then QUIT, after
# which pc.js writes every new or modified file back to software/src.  If a build step fails, type QUIT to
# keep what was built, or use pc.js's "abort" command to discard it.
#
# C: is a 10Mb FAT12 drive (BASIC-DOS doesn't support FAT16), which holds the sources and FINAL build outputs
# (about 8Mb) but not DEBUG listings (over 20Mb), so only FINAL builds are supported, and any old listings are
# deleted first.  As in mk.sh, all assembly sources are touched if the previous build was a DEBUG build.
#
# Use "mktest.sh clean" for a clean build: BASIC-DOS deletes the build outputs before building (using
# os/mk.bat's CLEAN option, and DEL commands for TESTS and MSB).
#
cd "$(dirname "$0")" || exit 1
case "$1" in
    "") clean= ;;
    clean|CLEAN) clean=1 ;;
    *) echo "usage: $0 [clean]" >&2; exit 1 ;;
esac
src=software/src
for f in os/boot/OBJ/BOOT.COM os/dev/OBJ/BASDEV.COM os/dos/OBJ/BASDOS.COM os/cmd/OBJ/COMMAND.COM; do
    if [ ! -f "$src/$f" ]; then echo "error: $src/$f not found (run mk.sh first)" >&2; exit 1; fi
done
if [ "$(cat tools/pc/disks/mkmode 2>/dev/null)" != FINAL ]; then
    find $src/os $src/tests $src/msb -iname "*.asm" -exec touch {} +
    mkdir -p tools/pc/disks
    echo FINAL > tools/pc/disks/mkmode
fi
find $src -iname "*.LST" -ipath "*/obj/*" -delete
make='MAKE REL=FINAL LST=NUL MAKEFILE'
mk="MK FINAL" tests= msb=
if [ -n "$clean" ]; then
    del() { for f in "$@"; do printf ';IF EXISTS("%s") THEN DEL %s' "$f" "$f"; done; }
    mk="MK FINAL CLEAN"
    tests=$(del 'OBJ\*.OBJ' 'OBJ\*.MAP' 'OBJ\*.SYM' 'BIN\*.COM' 'BIN\*.EXE')
    msb=$(del 'OBJ\*.OBJ' 'OBJ\*.EXE' 'OBJ\*.MAP' 'OBJ\*.SYM')
fi
tools/pc/pc.js ibm5160 $src "VER;CD OS;$mk;CD ..\TESTS$tests;$make;CD ..\MSB$msb;$make;QUIT" \
    --sys=bd:2 --target=10M --ram=640K --speed=8 --serial --normalize
