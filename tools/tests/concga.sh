#!/bin/bash
# echo This command builds and boots a BASIC-DOS boot floppy that uses the CON driver on a CGA machine (see configs/console/bios/CONFIG.SYS).
cd "$(dirname "$0")/../.." || exit 1
tools/tests/prep.sh software/pcx86/src/configs/console/bios || exit 1
tools/pc/pc.js ibm5160-cga software/pcx86/src/configs/console/bios --system=bd --version=2 --floppy --normalize --nosync
