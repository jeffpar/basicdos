#!/bin/bash
# echo This command builds and boots a BASIC-DOS boot floppy with the console connected to COM1 (no 8087; see bootfpu.sh).
tools/tests/prep.sh software/pcx86/src/configs/console/serial/fpe || exit 1
tools/pc/pc.js ibm5160 software/pcx86/src/configs/console/serial/fpe --system=bd --version=2 --floppy --serial --normalize --nosync
