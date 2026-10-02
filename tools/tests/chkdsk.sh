#!/bin/bash
#
# Runs MS-DOS 3.20 CHKDSK on a diskette image (eg, one saved by "QUIT /S BDTEST.IMG" at the end of a test session),
# to make sure that BASIC-DOS left the diskette in a valid state.  The exit code is non-zero if CHKDSK found any problems.
#
# A bare filename (eg, BDTEST.IMG) refers to tools/pc/disks, which is where "QUIT /S" saves it, and as with "QUIT /S",
# a filename without an extension gets ".img".  Any other path is relative to the current directory.
#
# How it works: the C: AUTOEXEC.BAT inside MSDOS320-C400.json runs "D:" and "MK", so we build D: from
# tools/pc/disks/chkdsk, which contains an MK.BAT that runs CHKDSK on drive A: (the diskette) and then QUIT.
#
cwd=$(pwd)
cd "$(dirname "$0")/../.." || exit 1
disk="$1"
if [ -z "$disk" ]; then
    echo "usage: $0 [diskette image]" >&2
    exit 1
fi
if [[ "$disk" != *.* ]]; then
    disk="$disk.img"
fi
if [[ "$disk" != */* ]]; then
    disk="tools/pc/disks/$disk"
elif [[ "$disk" != /* ]]; then
    disk="$cwd/$disk"
fi
if [ ! -f "$disk" ]; then
    echo "error: $disk not found" >&2
    exit 1
fi
# pc.js treats paths that begin with "/" as relative to the site root, so pass it a relative path
disk=$(node -e 'console.log(require("path").relative(process.argv[1], process.argv[2]))' "$(pwd)" "$disk")
mkdir -p tools/pc/disks/chkdsk || exit 1
printf 'ECHO N| C:\\DOS\\CHKDSK A:\r\nQUIT\r\n' > tools/pc/disks/chkdsk/MK.BAT
log=$(mktemp)
tools/pc/pc.js --disk=software/pcx86/disks/MSDOS320-C400.json --dir=tools/pc/disks/chkdsk --diskette="$disk" --normalize --speed=4 --target=20M --fat=16:2048:512 --nosync | tee "$log"
if ! grep -q "bytes total disk space" "$log" || grep -qiE "error|lost|cross-linked|invalid|allocation|probable|convert" "$log"; then
    echo "CHKDSK FAILED: $disk"; rm -f "$log"; exit 1
fi
echo "CHKDSK PASSED: $disk"; rm -f "$log"
