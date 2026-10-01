#!/bin/bash
# echo This command builds and boots a BASIC-DOS boot floppy with the console connected to COM1, on a machine with an 8087.
tools/tests/prep.sh software/pcx86/src/configs/console/serial/fpu || exit 1
tools/pc/pc.js ibm5160-fpu software/pcx86/src/configs/console/serial/fpu --system=bd --version=2 --floppy --serial --normalize --nosync
