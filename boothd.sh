#!/bin/bash
#
# Boots BASIC-DOS 2.00 from a hard disk (C:) that pc.js builds from software/pcx86/src/configs/console/serial/hd,
# after tools/tests/prep.sh copies the test files into it (see tools/tests/testhd.sh for booting BASIC-DOS from a
# diskette with an MS-DOS-formatted hard disk instead).  Changes to the hard disk are NOT saved back to the
# directory (--nosync).
#
cd "$(dirname "$0")" || exit 1
tools/tests/prep.sh software/pcx86/src/configs/console/serial/hd || exit 1
tools/pc/pc.js ibm5160 software/pcx86/src/configs/console/serial/hd --sys=bd:2 --target=10M --serial --normalize --nosync
