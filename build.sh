#!/bin/bash
echo This command creates a drive [D:] containing the BASIC-DOS source code.
echo To build the source, at the "C:\>" prompt, type "D:", then "MK", then "QUIT".
echo Any modifications will be written back to the software/pcx86/src directory.
pc.js --disk=https://harddisks.pcjs.org/pcx86/10mb/MSDOS330-C400.json --dir=software/pcx86/src --normalize
