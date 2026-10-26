#!/bin/bash
#
# Usage: ./boot.sh [config] [pc.js arguments...]
#
# Builds and boots BASIC-DOS with one of the configurations in software/src/configs/console, after
# tools/tests/prep.sh copies the test binaries into it.  Any additional arguments are passed to pc.js
# (eg, --halt, or a list of commands to run, such as "VER;MEM", which pc.js adds to CONFIG.SYS's SHELL
# line, or if they don't fit, to AUTOEXEC.BAT).  Changes to the boot disk are NOT saved back to the
# config folder (--nosync).
#
# The machine is a 640K IBM PC AT (ibm5170), whose real-time clock sets the date and time.
#
#   fpe     floppy, console on COM1, no FPU (the default)
#   fpu     floppy, console on COM1, with an 80287
#   hd      10Mb hard disk (C:), console on COM1 (see tools/tests/testhd.sh for booting BASIC-DOS from
#           a diskette with an MS-DOS-formatted hard disk instead)
#   bios    floppy, CON driver (see configs/console/bios/CONFIG.SYS) on a CGA
#   cga     alias for bios
#
cd "$(dirname "$0")" || exit 1
name=${1:-fpe}
[ $# -gt 0 ] && shift
machine=ibm5170
case "$name" in
    fpe)    cfg=serial/fpe; opts="--floppy --serial" ;;
    fpu)    cfg=serial/fpu; opts="--floppy --serial --fpu" ;;
    hd)     cfg=serial/hd;  opts="--target=10M --serial" ;;
    bios|cga) cfg=bios;     opts="--floppy" ;;
    *)      echo "usage: $0 [fpe|fpu|hd|bios|cga] [pc.js arguments...]" >&2; exit 1 ;;
esac
cfg=software/src/configs/console/$cfg
tools/tests/prep.sh $cfg || exit 1
tools/pc/pc.js $machine $cfg "$@" --sys=bd:2 $opts --normalize --nosync
