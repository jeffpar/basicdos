#!/bin/bash
#
# Builds BASIC-DOS on BASIC-DOS (mkdos.sh builds it on MS-DOS 3.20 instead).
# As in mkdos.sh, if pc.js exits normally (ie, via QUIT) and PCJS is set,
# the disk images of the build's mode are then updated with the new binaries
# (disks/current for FINAL, disks/debug for DEBUG; see gulpfile.js), by "gulp
# watch" instead, if it's running, a couple of seconds later.
#
# pc.js builds a bootable BASIC-DOS hard disk (C:) directly from src,
# using the system files from the previous build (os/*/OBJ, so run mkdos.sh at
# least once first), and src/configs/mk/CONFIG.SYS (--config; a serial
# console, with PATH$ set to C:\, C:\TOOLS\BD, and C:\TOOLS\DOS, so a tool in
# src/tools/bd overrides its counterpart in src/tools/dos, as on a BASIC-DOS
# disk).
#
# BASIC-DOS runs os/mk.bat (which builds BOOT, DD, DEV, DOS, CMD, UTIL, and DLL),
# then the TESTS and MSB makefiles, and then QUIT, after which pc.js writes
# every new or modified file back to src.  If a build step fails,
# the build stops at the prompt; type QUIT to keep any changes or use pc.js's
# "abort" command to discard them.
#
# The machine (COMPAQ DeskPro 386) and C: (30Mb, FAT16, 2K clusters, 512 root
# entries) match mkdos.sh.
#
# Usage: mk.sh [FINAL, DEBUG, or ALL] [CLEAN] (in either case).  FINAL builds
# the non-debug binaries that the disk images in disks/current use, DEBUG
# builds DEBUG binaries (for disks/debug), and ALL (the default) builds DEBUG
# and then FINAL, so FINAL is the current mode afterward.  As in mkdos.sh,
# package.json's "version" sets the BASIC-DOS version, and each mode keeps its
# own build outputs (see setMode in tools/release.sh), so switching modes
# rebuilds only what's changed.
#
# CLEAN first deletes the build outputs (using os/mk.bat's CLEAN option, and
# DEL commands for TESTS and MSB), for a clean build (of each mode, with ALL).
#
cd "$(dirname "$0")" || exit 1
usage() { echo "Usage: $0 [FINAL, DEBUG, or ALL] [CLEAN]" >&2; exit 1; }
[ $# -le 2 ] || usage
. tools/release.sh
getModes "$1" || usage
clean=
case "$(echo "$2" | tr a-z A-Z)" in
    "") ;;
    CLEAN) clean=1 ;;
    *) usage ;;
esac
src=src
#
# build mode
#
# Builds the binaries of the given mode (FINAL or DEBUG), returning pc.js's exit code.
#
build() {
    local mode=$1 f make mk tests= msb= chk
    setMode $mode
    for f in os/boot/OBJ/BOOT.COM os/dev/OBJ/BASDEV.COM os/dos/OBJ/BASDOS.COM os/cmd/OBJ/COMMAND.COM; do
        if [ ! -f "$src/$f" ]; then echo "error: $src/$f not found (run mkdos.sh first)" >&2; return 1; fi
    done
    make="MAKE REL=$mode MAKEFILE"
    mk="MK $mode"
    if [ -n "$clean" ]; then
        del() { for f in "$@"; do printf ';IF EXISTS("%s") THEN DEL %s' "$f" "$f"; done; }
        mk="MK $mode CLEAN"
        tests=$(del 'OBJ\*.OBJ' 'OBJ\*.MAP' 'OBJ\*.SYM' 'OBJ\*.LST' \
            'REGRESS\OBJ\*.OBJ' 'REGRESS\OBJ\*.MAP' 'REGRESS\OBJ\*.SYM' 'REGRESS\OBJ\*.COM' 'MISC\OBJ\*.COM' 'MISC\OBJ\*.EXE' \
            'TOOLS\OBJ\*.COM')
        msb=$(del 'OBJ\*.OBJ' 'OBJ\*.EXE' 'OBJ\*.MAP' 'OBJ\*.SYM' 'OBJ\*.LST')
    fi
    #
    # Each step that fails sets ERRORLEVEL (see os/mk.bat), and since a failed
    # command doesn't stop a BAT file, chk ends AUTOEXEC.BAT then, leaving the
    # error on the screen, at the prompt, instead of running the later steps.
    #
    chk=";IF ERRORLEVEL THEN END 1"
    tools/pc/pc.js compaq386 $src "CD OS;$mk$chk;CD ..\TESTS$tests;$make$chk;CD ..\MSB$msb;$make$chk;QUIT" \
        --sys=bd:2 --config=$src/configs/mk/CONFIG.SYS --target=30M --fat=16:2048:512 --ram=640K --speed=16 --serial --normalize
}
for mode in $modes; do
    build $mode || exit
    updateDisks || exit 1
done
