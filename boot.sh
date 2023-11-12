#!/bin/bash
echo This command builds and boots a BASIC-DOS boot floppy with the console connected to COM1.
pc.js ibm5160 software/pcx86/src/configs/200A --system=bd --version=2.00A --floppy --serial
