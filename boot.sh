#!/bin/bash
#
# Usage: ./boot.sh [config] [pc.js arguments...]
#
# Builds and boots BASIC-DOS with one of the configurations in software/src/configs/console, after
# tools/tests/prep.sh copies the test binaries into it.  Any additional arguments are passed to pc.js
# (eg, --halt, or a list of commands to run, such as "VER;MEM").  Changes to the boot disk are NOT
# saved back to the config folder (--nosync).
#
#   fpe     floppy, console on COM1, no 8087 (the default)
#   fpu     floppy, console on COM1, with an 8087
#   m640    floppy, console on COM1, 640K, skipping the CON and FPU$ drivers (for evaluating memory usage)
#   hd      10Mb hard disk (C:), console on COM1 (see tools/tests/testhd.sh for booting BASIC-DOS from
#           a diskette with an MS-DOS-formatted hard disk instead)
#   bios    floppy, CON driver (see configs/console/bios/CONFIG.SYS) on a CGA
#   cga     alias for bios
#
cd "$(dirname "$0")" || exit 1
name=${1:-fpe}
[ $# -gt 0 ] && shift
machine=ibm5160
case "$name" in
    fpe)    cfg=serial/fpe;  opts="--floppy --serial" ;;
    fpu)    cfg=serial/fpu;  opts="--floppy --serial --fpu" ;;
    m640)   cfg=serial/m640; opts="--floppy --serial --ram=640K" ;;
    hd)     cfg=serial/hd;   opts="--target=10M --serial" ;;
    bios|cga) cfg=bios;      opts="--floppy" ;;
    *)      echo "usage: $0 [fpe|fpu|m640|hd|bios|cga] [pc.js arguments...]" >&2; exit 1 ;;
esac
cfg=software/src/configs/console/$cfg
tools/tests/prep.sh $cfg || exit 1
tools/pc/pc.js $machine $cfg "$@" --sys=bd:2 $opts --normalize --nosync
