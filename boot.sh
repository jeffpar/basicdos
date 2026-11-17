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
# The machine is a 2Mb IBM PC AT (ibm5170 with --ram=2M, which pc.js splits into 640K of conventional memory and 1408K
# of extended memory, unless another --ram is given), whose real-time clock sets the date and time.  No
# configuration's CONFIG.SYS has a "CPU=8088" line, so BASIC-DOS runs in protected mode, the default on an 80286 or
# later (press R at the boot message for real mode, or see tools/tests/mmutest.sh's real machine).
#
#   fpe     floppy, console on COM1, no FPU (the default)
#   fpu     floppy, console on COM1, with an 80287
#   hd      10Mb hard disk (C:), console on COM1 (see tools/tests/testhd.sh for booting BASIC-DOS from
#           a diskette with an MS-DOS-formatted hard disk instead)
#
cd "$(dirname "$0")" || exit 1
name=${1:-fpe}
[ $# -gt 0 ] && shift
machine=ibm5170
case "$name" in
    fpe)    cfg=serial/fpe; opts="--floppy --serial" ;;
    fpu)    cfg=serial/fpu; opts="--floppy --serial --fpu" ;;
    hd)     cfg=serial/hd;  opts="--target=10M --serial" ;;
    *)      echo "usage: $0 [fpe|fpu|hd] [pc.js arguments...]" >&2; exit 1 ;;
esac
cfg=software/src/configs/console/$cfg
ram=--ram=2M
case " $* " in *" --ram="*) ram= ;; esac
tools/tests/prep.sh $cfg || exit 1
tools/pc/pc.js $machine $cfg "$@" --sys=bd:2 $opts $ram --normalize --nosync
