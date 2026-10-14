#!/bin/bash
#
# Builds BASIC-DOS on BASIC-DOS (mkdos.sh builds it on MS-DOS 3.20 instead, which also updates the demo
# disks).
#
# pc.js builds a bootable BASIC-DOS hard disk (C:) directly from software/src, using the system files from
# the previous build (os/*/OBJ, so run mkdos.sh at least once first), software/src/CONFIG.SYS (a serial console,
# with PATH$ set to C:\ and C:\TOOLS), and the build tools in software/src/tools.  BASIC-DOS runs os/mk.bat
# (which builds BOOT, DD, DEV, DOS, CMD, and UTIL), then the TESTS and MSB makefiles, and then QUIT, after
# which pc.js writes every new or modified file back to software/src.  If a build step fails, type QUIT to
# keep what was built, or use pc.js's "abort" command to discard it.
#
# The machine (COMPAQ DeskPro 386) and C: (30Mb, FAT16, 2K clusters, 512 root
# entries) match mkdos.sh.  FINAL is the default; use "mk.sh debug" to generate
# DEBUG binaries.  As in mkdos.sh, all assembly sources are touched when the
# build mode changes.
#
# Use "mk.sh clean" for a clean build: BASIC-DOS deletes the build outputs before building (using
# os/mk.bat's CLEAN option, and DEL commands for TESTS and MSB).
#
cd "$(dirname "$0")" || exit 1
mode=FINAL
clean=
for arg in "$@"; do
    case "$arg" in
        debug|DEBUG) mode=DEBUG ;;
        clean|CLEAN) clean=1 ;;
        *) echo "usage: $0 [debug] [clean]" >&2; exit 1 ;;
    esac
done
src=software/src
for f in os/boot/OBJ/BOOT.COM os/dev/OBJ/BASDEV.COM os/dos/OBJ/BASDOS.COM os/cmd/OBJ/COMMAND.COM; do
    if [ ! -f "$src/$f" ]; then echo "error: $src/$f not found (run mkdos.sh first)" >&2; exit 1; fi
done
if [ "$(cat tools/pc/disks/mkmode 2>/dev/null)" != "$mode" ]; then
    find $src/os $src/tests $src/msb -iname "*.asm" -exec touch {} +
    mkdir -p tools/pc/disks
    echo "$mode" > tools/pc/disks/mkmode
fi
make="MAKE REL=$mode MAKEFILE"
mk="MK $mode" tests= msb=
if [ -n "$clean" ]; then
    del() { for f in "$@"; do printf ';IF EXISTS("%s") THEN DEL %s' "$f" "$f"; done; }
    mk="MK $mode CLEAN"
    tests=$(del 'OBJ\*.OBJ' 'OBJ\*.MAP' 'OBJ\*.SYM' 'OBJ\*.LST' 'BIN\*.COM' 'BIN\*.EXE')
    msb=$(del 'OBJ\*.OBJ' 'OBJ\*.EXE' 'OBJ\*.MAP' 'OBJ\*.SYM' 'OBJ\*.LST')
fi
tools/pc/pc.js compaq386 $src "VER;CD OS;$mk;CD ..\TESTS$tests;$make;CD ..\MSB$msb;$make;QUIT" \
    --sys=bd:2 --target=30M --fat=16:2048:512 --ram=640K --speed=128 --serial --normalize
