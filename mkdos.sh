#!/bin/bash
#
# This command creates a drive [D:] containing the BASIC-DOS source code.  To
# build the source, at the "C:\>" prompt, type "D:", then "MKDOS", then "QUIT".
# Any modifications will be written back to the software/src directory.
#
# NOTE: While early BASIC-DOS builds were performed in a browser using a PCjs
# PC XT with PC DOS 2.00, our command-line build environment uses PC.js with a
# COMPAQ DeskPro 386 configuration running MS-DOS 3.20, in part because that
# machine has a real-time clock that MS-DOS 3.20 knows how to use.
#
# Drive D: is 30Mb (--target=30M), since the source directory (including the
# test binaries that tools/tests/prep.sh copies into the configs folders) has
# outgrown 10Mb, and MASM's listing (.LST) files need room, too (a 20Mb drive
# ran out of space; MS-DOS 3.20 volumes can't exceed 32Mb), although listings
# are currently off (each makefile sets LST=NUL).
#
# The --fat option (16-bit FAT, 2K clusters, 512 root entries) is also required
# because by default, pc.js gives a large volume 1024 root entries, which
# MS-DOS 3.20 apparently doesn't honor (it reads the volume as if the root
# directory had 512 entries, so all files appear to be corrupted).
#
# --speed=8 runs the CPU at up to 8 times the DeskPro 386's 16Mhz (pc.js
# simply runs flat out when the host can't keep up, which as of 2026-10-25
# happens at about 8x); mk.sh uses the same multiplier.
#
# After building, if pc.js exits normally (ie, via QUIT, which a successful
# build runs automatically), update the BASIC-DOS disk images with the new
# binaries (which requires PCJS; see gulpfile.js): while package.json's
# config.release is "debug", a DEBUG build updates every disk except the
# release diskette (BASICDOS-360K) and the 64K demo disks (BASICDOS-360K-M64
# and BASICDOS-360K-TERM, which have room only for FINAL binaries), and a
# FINAL build updates only those three; once config.release is "final", a
# FINAL build updates them all, and a DEBUG build updates all but those three.
# If a build fails and you don't want the disks updated, use pc.js's "abort"
# command.
#
# Usage: mkdos.sh [FINAL or DEBUG] [CLEAN] (the same arguments as mk.sh and
# os/mk.bat, in either case).  FINAL builds non-debug binaries, and DEBUG
# builds the traditional DEBUG binaries; the default is package.json's
# config.release property, and its "version" sets the BASIC-DOS version (see
# tools/release.sh, which updates version.inc).  The C: AUTOEXEC.BAT
# always runs MKDOS without arguments, so for a FINAL build, we create an
# MKFINAL file in the source directory (D:\), which tells MKDOS.BAT to build
# FINAL binaries instead, and we remove it when pc.js exits.  And since MAKE
# can't tell that the mode has changed, each mode keeps its own build outputs
# (see setMode in tools/release.sh, which records the last mode in
# tools/pc/disks/mkmode, and saves the other mode's outputs alongside it), so
# switching modes rebuilds only what's changed since that mode's last build.
#
# Use "mkdos.sh final clean" (or "mkdos.sh debug clean") for a clean build:
# we create a CLEAN file in the source directory, which tells MKDOS.BAT to run
# MKCLEAN.BAT first (which deletes CLEAN and all the build outputs).
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
rm -f $src/MKFINAL $src/CLEAN
trap 'rm -f '$src'/MKFINAL '$src'/CLEAN' EXIT
if [ $mode = FINAL ]; then
    touch $src/MKFINAL
fi
if [ -n "$clean" ]; then
    touch $src/CLEAN
fi
tools/pc/pc.js --disk=software/disks/MSDOS320-C400.json --dir=$src --normalize --speed=8 --target=30M --fat=16:2048:512
code=$?
if [ $code -eq 0 ] && [ -n "$PCJS" ]; then
    if ! npx gulp demos --silent > /dev/null; then
        echo "error: unable to update the demo disks (run \"npx gulp demos\" for details)" >&2
        exit 1
    fi
fi
exit $code
