#!/bin/bash
#
# Builds a BASIC-DOS boot diskette and boots it on a PC XT (ibm5160) whose 10Mb hard disk (C:) is built
# from a directory, so that the HDC$ driver can be tested.  Usage:
#
#   ./boothd.sh [hard disk directory] [config folder]
#
# The hard disk directory defaults to tools/pc/disks/hdsrc (created with a few sample files if it doesn't
# exist), and the config folder defaults to software/pcx86/src/configs/console/bios.  The hard disk is
# formatted by MS-DOS 3.20 (so it also contains MS-DOS system files, and a DOS subdirectory).
#
# When the "Press a key to start..." prompt appears, press any key other than ESC to boot BASIC-DOS from the
# diskette (ESC boots MS-DOS from the hard disk instead).  Changes to the hard disk are NOT saved back to the
# directory.
#
cd "$(dirname "$0")" || exit 1
hdir="${1:-tools/pc/disks/hdsrc}"
cfg="${2:-software/pcx86/src/configs/console/bios}"
if [ ! -d "$cfg" ]; then
    echo "error: $cfg not found" >&2
    exit 1
fi
if [ ! -d "$hdir" ]; then
    mkdir -p "$hdir/SUBDIR" || exit 1
    printf 'Hello from the hard disk\r\n' > "$hdir/HELLO.TXT"
    printf 'This file is in a subdirectory\r\n' > "$hdir/SUBDIR/INSIDE.TXT"
    cp software/pcx86/src/configs/console/serial/fpe/PRIMES.BAS "$hdir/"
fi
tools/tests/prep.sh "$cfg" || exit 1
#
# Build the diskette from a copy of the config folder, and save it with "QUIT /S"; since pc.js appends our
# commands to AUTOEXEC.BAT, they first restore the original AUTOEXEC.BAT (from AUTOEXEC.HD).
#
fdir=tools/pc/disks/bdhd
mkdir -p $fdir || exit 1
rm -f $fdir/* tools/pc/disks/BDHD.IMG
cp "$cfg"/* $fdir/ || exit 1
cp $fdir/AUTOEXEC.BAT $fdir/AUTOEXEC.HD || exit 1
echo "Building BASIC-DOS diskette..."
tools/pc/pc.js ibm5160-test $fdir "VER;COPY AUTOEXEC.HD AUTOEXEC.BAT;DEL AUTOEXEC.HD;QUIT /S BDHD.IMG" \
    --system=bd --version=2 --floppy --normalize --nosync > /dev/null
if [ ! -f tools/pc/disks/BDHD.IMG ]; then
    echo "error: unable to build tools/pc/disks/BDHD.IMG" >&2
    exit 1
fi
tools/pc/pc.js ibm5160 --diskette=tools/pc/disks/BDHD.IMG --boot=A --dir="$hdir" --target=10M --sys=msdos:3.20 --nosync
