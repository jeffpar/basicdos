#!/bin/bash
#
# Copies the BASIC-DOS test binaries and batch files into the specified configuration folder
# (eg, software/pcx86/src/configs/console/serial/fpe) before boot.sh or another script in tools/tests boots it.
#
# Only CONFIG.SYS and AUTOEXEC.BAT are tracked in those folders (see software/pcx86/src/configs/.gitignore);
# everything else is copied here, so build the sources first (see mk.sh) to make sure the copies are current.
#
root=$(cd "$(dirname "$0")/../.." && pwd)
src="$root/software/pcx86/src"
dir="$1"
if [ ! -f "$dir/CONFIG.SYS" ]; then
    echo "usage: $0 [configuration folder containing CONFIG.SYS]" >&2
    exit 1
fi
files=(
    "$src"/tests/bin/*.COM
    "$src"/tests/bin/*.EXE
    "$src"/tests/misc/BD*.BAT
    "$src"/tests/misc/*.BAS
    "$src"/tests/misc/SYMDEB.EXE
    "$src"/tests/primes/PRIMES.BAS
    "$src"/tests/primes/PRIMES.BAT
    "$src"/msb/OBJ/MSBASIC.EXE
)
for f in "${files[@]}"; do
    if [ -f "$f" ]; then
        cp -p "$f" "$dir/"
    else
        echo "warning: ${f#$root/} not found (has it been built?)" >&2
    fi
done
if [ ! -f "$dir/DOSTESTS.COM" ]; then
    echo "error: DOSTESTS.COM is missing from $dir" >&2
    exit 1
fi
