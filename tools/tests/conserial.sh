#!/bin/bash
# echo This command builds and boots a BASIC-DOS boot floppy with the console connected to COM1 (same as boot.sh).
cd "$(dirname "$0")/../.." || exit 1
tools/tests/prep.sh software/pcx86/src/configs/console/serial || exit 1
tools/pc/pc.js ibm5160 software/pcx86/src/configs/console/serial --system=bd --version=2 --floppy --serial --normalize --nosync
