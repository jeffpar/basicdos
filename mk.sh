#!/bin/bash
#
# This command creates a drive [D:] containing the BASIC-DOS source code.
# To build the source, at the "C:\>" prompt, type "D:", then "MK", then "QUIT".
# Any modifications will be written back to the software/pcx86/src directory.
#
# NOTE: While early BASIC-DOS builds were performed in a browser using a PCjs
# PC XT with PC DOS 2.00, our command-line build environment uses PC.js with a
# COMPAQ DeskPro 386 configuration running MS-DOS 3.20, in part because that
# machine has a real-time clock that MS-DOS 3.20 knows how to use.
#
# Drive D: is 30Mb (--target=30M), since the source directory (including the
# test binaries that tools/tests/prep.sh copies into the configs folders) has
# outgrown 10Mb, and MASM's listing (.LST) files need room, too (a 20Mb drive
# ran out of space; MS-DOS 3.20 volumes can't exceed 32Mb).  The --fat option
# (16-bit FAT, 2K clusters, 512 root entries) is also required, because by
# default, pc.js gives a large volume 1024 root entries, which MS-DOS 3.20
# apparently doesn't honor (it reads the volume as if the root directory had
# 512 entries, so all files appear to be corrupted).
#
# After building, if pc.js exits normally (ie, via QUIT, which a successful
# build runs automatically), update the BASIC-DOS demo disks with the new
# binaries (which requires PCJS; see gulpfile.js).  If a build fails and you
# don't want the demo disks updated, use pc.js's "abort" command.
#
# By default, we build non-debug ("FINAL") binaries; use "mk.sh debug" to build
# the traditional DEBUG binaries.  The C: AUTOEXEC.BAT always runs MK without
# arguments, so for a FINAL build, we create an MKFINAL file in the source
# directory (D:\), which tells MK.BAT to build FINAL binaries instead, and we
# remove it when pc.js exits.  And since MAKE can't tell that the mode has
# changed, we touch all the assembly sources whenever it does, so that every
# binary is rebuilt in the new mode (the last mode is recorded in
# tools/pc/disks/mkmode, which git ignores).
#
mode=FINAL
case "$1" in
    "") ;;
    debug|DEBUG) mode=DEBUG ;;
    *) echo "usage: $0 [debug]" >&2; exit 1 ;;
esac
src=software/pcx86/src
last=$(cat tools/pc/disks/mkmode 2>/dev/null)
if [ "$last" != "$mode" ]; then
    find $src/os $src/tests -iname "*.asm" -exec touch {} +
    mkdir -p tools/pc/disks
    echo $mode > tools/pc/disks/mkmode
fi
rm -f $src/MKFINAL
if [ $mode = FINAL ]; then
    touch $src/MKFINAL
    trap 'rm -f '$src'/MKFINAL' EXIT
fi
tools/pc/pc.js --disk=software/pcx86/disks/MSDOS320-C400.json --dir=$src --normalize --speed=4 --target=30M --fat=16:2048:512
code=$?
if [ $code -eq 0 ] && [ -n "$PCJS" ]; then
    if ! npx gulp demos --silent > /dev/null; then
        echo "error: unable to update the demo disks (run \"npx gulp demos\" for details)" >&2
        exit 1
    fi
fi
exit $code
