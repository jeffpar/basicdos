#!/bin/bash
# echo This command boots a BASIC-DOS test floppy (see conserial.sh), runs DOSTESTS, and then quits.
# It's a very quick (and dirty) set of confidence tests.
# The exit code is non-zero if any test failed.
#
# NOTE: The ibm5160-test machine has no hard disk and no debugger, either of which would cause the
# (DEBUG) BASIC-DOS boot sector to display a "Press a key to start..." prompt, so the tests run unattended.
#
# The first command must be an internal command (eg, VER), because pc.js converts only the first
# command into a path (eg, "\DOSTESTS.COM"), which BASIC-DOS doesn't understand.
#
cd "$(dirname "$0")/../.." || exit 1
tools/tests/prep.sh software/pcx86/src/configs/console/serial || exit 1
log=$(mktemp)
tools/pc/pc.js ibm5160-test software/pcx86/src/configs/console/serial "VER,DOSTESTS,QUIT" --system=bd --version=2 --floppy --serial --normalize --nosync | tee "$log"
if grep -q "failed" "$log" || ! grep -q "Return code 0" "$log"; then
    echo "TESTS FAILED"; rm -f "$log"; exit 1
fi
echo "TESTS PASSED"; rm -f "$log"
