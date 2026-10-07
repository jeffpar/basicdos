#!/bin/bash
#
# Boots BASIC-DOS 2.00 from a hard disk that pc.js builds from tools/pc/disks/hdsrc (see tools/tests/testhd.sh
# for booting BASIC-DOS from a diskette with an MS-DOS-formatted hard disk instead).  Changes to the hard disk
# are NOT saved back to the directory (--nosync).
#
cd "$(dirname "$0")" || exit 1
tools/pc/pc.js ibm5160 tools/pc/disks/hdsrc --sys=bd:2 --target=10M --serial --normalize --nosync
