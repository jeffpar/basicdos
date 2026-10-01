#!/bin/bash
# echo This command builds and boots a BASIC-DOS boot floppy with the console connected to COM1.
tools/pc/pc.js ibm5160 software/pcx86/src/configs/v2 --system=bd --version=2 --floppy --serial --normalize --nosync
