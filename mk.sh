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
# Drive D: is 20Mb (--target=20M), since the source directory (including the
# test binaries that tools/tests/prep.sh copies into the configs folders) has
# outgrown 10Mb.  The --fat option (16-bit FAT, 2K clusters, 512 root entries)
# is also required, because by default, pc.js gives a 20Mb volume 1024 root
# entries, which MS-DOS 3.20 apparently doesn't honor (it reads the volume as
# if the root directory had 512 entries, so all files appear to be corrupted).
#
# Before building, regenerate os/cmd/txt.inc from HELP.TXT, since COMMAND.COM
# depends on it.  And after building, if pc.js exits normally (ie, via QUIT,
# which a successful build runs automatically), update the BASIC-DOS demo disks
# with the new binaries (which requires PCJS; see gulpfile.js).  If a build
# fails and you don't want the demo disks updated, use pc.js's "abort" command.
#
npx gulp BUILD-HELP --silent || exit 1
tools/pc/pc.js --disk=software/pcx86/disks/MSDOS320-C400.json --dir=software/pcx86/src --normalize --speed=4 --target=20M --fat=16:2048:512
code=$?
if [ $code -eq 0 ] && [ -n "$PCJS" ]; then
    npx gulp demos --silent > /dev/null || exit 1
fi
exit $code
