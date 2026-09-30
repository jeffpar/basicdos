#!/bin/bash
# echo This command builds and boots a BASIC-DOS boot floppy with the console connected to COM1.
tools/pc/pc.js ibm5160 software/pcx86/src/configs/200B --system=bd --version=2.00B --floppy --serial --normalize
