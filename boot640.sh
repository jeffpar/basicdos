#!/bin/bash
# echo This command builds and boots a 640K BASIC-DOS boot floppy with the console connected to COM1, skipping the CON and FPU$ drivers (for evaluating memory usage).
tools/tests/prep.sh software/src/configs/console/serial/m640 || exit 1
tools/pc/pc.js ibm5160-640k software/src/configs/console/serial/m640 --system=bd --version=2 --floppy --serial --normalize --nosync
