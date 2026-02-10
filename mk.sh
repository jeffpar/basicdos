#!/bin/bash
#
# This command creates a drive [D:] containing the BASIC-DOS source code.
# To build the source, at the "C:\>" prompt, type "D:", then "MK", then "QUIT".
# Any modifications will be written back to the software/pcx86/src directory.
#
# NOTE: While early BASIC-DOS builds were performed in a browser using a PCjs
# PC XT with PC DOS 2.00, our command-line build environment uses PC.js with a
# COMPAQ DeskPro 386 configuration running MS-DOS 3.20, in part because that
# machine has a real-time clock that MS-DOS 3.20 knows how to use.
#
pc.js --disk=software/pcx86/disks/MSDOS320-C400.json --dir=software/pcx86/src --normalize
