#!/bin/bash
#
# Usage: tools/tests/pmprobe.sh [ibm5170 or compaq386] [pc.js arguments...]
#
# Boots BASIC-DOS on a 2Mb machine (an IBM PC AT by default) from a floppy whose CONFIG.SYS has no "CPU=8088" line,
# so that a CPU$ driver built with PROBE defined (eg, by adding /DPROBE to AFLAGS in software/src/os/dev/makefile)
# runs its protected-mode probe (see pm_probe in software/src/os/dev/cpudev.asm, and docs/bdtech/mmu): code at ring 3
# calls the ROM BIOS through the IDT, and the BIOS runs at ring 0.  CPU$ prints a summary, and BASIC-DOS finishes
# booting (with its console on COM1, ie, this terminal).  The full results, PROBELOG and its events, stay in the system
# area at linear address 1039F0h.
#
# Before booting, this lists the linear addresses of the probe's entry points (from CPU$'s map file; CPU$ is the
# first driver, at 0:0970h), for breakpoints in the PCjs debugger: eg, add --halt, type "bp %XXXX" for each address
# you want, and then "g".  After the probe, "db %1039F0 l400" dumps its results.  Any other arguments are passed to
# pc.js (eg, --halt, or a list of commands, such as "VER;QUIT").  The boot floppy's folder, tools/pc/disks/pmprobe,
# is recreated every time.
#
cd "$(dirname "$0")/../.." || exit 1
machine=ibm5170
case "$1" in ibm5170|compaq386) machine=$1; shift ;; esac
cfg=tools/pc/disks/pmprobe
map=software/src/os/dev/OBJ/CPUDEV.MAP
if ! tr -d '\r' < $map | grep -qiw pm_probe; then
    echo "error: CPU$ wasn't built with PROBE defined (see $map)" >&2; exit 1
fi
rm -rf $cfg
mkdir -p $cfg || exit 1
printf 'SKIP=VKD$\r\nCON=COM1:9600,N,8,1\r\nSHELL=COMMAND.COM\r\n' > $cfg/CONFIG.SYS
for name in pm_probe probe3 sw_int irq_common exc_common probe_exit; do
    off=$(tr -d '\r' < $map | awk -v n=$name 'tolower($2) == n {split($1, a, ":"); print a[2]; exit}')
    [ -n "$off" ] && printf "%-12s bp %%%X\n" $name $((0x970 + 0x$off))
done
tools/pc/pc.js $machine $cfg --sys=bd:2 --floppy --serial --ram=2M --normalize --nosync "$@"
