#!/bin/bash
#
# Usage: tools/tests/pmboot.sh [ibm5170 or compaq386] [pc.js arguments...]
#
# Boots BASIC-DOS on a 2Mb machine (an IBM PC AT by default) from a floppy whose CONFIG.SYS has no "CPU=8088" line,
# so that DEVINIT switches to protected mode after CPU$ initializes (see CPU_PMODE in software/src/os/dev/cpudev.asm,
# and docs/bdtech/mmu), initializes the rest of the drivers in protected mode, and jumps to sysinit in protected mode,
# with BASIC-DOS's console on COM1 (ie, this terminal).  An exception that CPU$ can't handle prints "CPU$ fault" and
# stops the machine.
#
# Before booting, this lists the linear addresses of some protected-mode entry points (CPU$ is the first driver, at
# 0:0970h, and DEVINIT follows the drivers), for breakpoints in the PCjs debugger: eg, add --halt, type "bp %XXXX"
# for each address you want, and then "g".  dv_init precedes each driver's initialization (trace into it with "t"),
# and dv_jump precedes sysinit.  Any other arguments are passed to pc.js (eg, --halt, or a list of commands, such as
# "VER;QUIT").  The boot floppy's folder, tools/pc/disks/pmboot, is recreated every time.
#
cd "$(dirname "$0")/../.." || exit 1
machine=ibm5170
case "$1" in ibm5170|compaq386) machine=$1; shift ;; esac
cfg=tools/pc/disks/pmboot
obj=software/src/os/dev/OBJ
rm -rf $cfg
mkdir -p $cfg || exit 1
printf 'CON=COM1:9600,N,8,1\r\nSHELL=COMMAND.COM\r\n' > $cfg/CONFIG.SYS
size() { wc -c < "$1" | tr -d ' '; }
devinit=$((0x970 + $(size $obj/BASDEV.COM) - $(size software/src/os/boot/OBJ/BOOT2.COM) - $(size $obj/DEVINIT.COM)))
show() {
    for name in $3; do
        off=$(tr -d '\r' < $1 | awk -v n=$name 'tolower($2) == n {split($1, a, ":"); print a[2]; exit}')
        [ -n "$off" ] && printf "%-12s bp %%%X\n" $name $(($2 + 0x$off))
    done
}
show $obj/CPUDEV.MAP 0x970 "ddcpu_pmode sw_int irq_common exc_common cpu_fatal pm_setvec"
show $obj/DEVINIT.MAP $devinit "chk_pm dv_init dv_jump"
exec tools/pc/pc.js $machine $cfg --sys=bd:2 --floppy --serial --ram=2M --normalize --nosync "$@"
