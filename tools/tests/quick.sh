#!/bin/bash
# echo This command boots a BASIC-DOS test floppy (see conserial.sh), runs FPUTESTS, DOSTESTS, STRFUN, STRPOOL,
# ARRAYS, FLOW, CMDS (commands, pipes, redirection, and HELP), VARS (variable listings), FILEIO (sequential and random files), FCBTESTS (FCB
# functions), and PRINTF,
# and then quits; it then boots a test floppy
# on a machine with an 8087 (see bootfpu.sh), and runs FPUTESTS, VARS, and STRFUN.
# It's a very quick (and dirty) set of confidence tests.
# The exit code is non-zero if any test failed.
#
# NOTE: The ibm5160-test machines have no hard disk and no debugger, either of which would cause the
# (DEBUG) BASIC-DOS boot sector to display a "Press a key to start..." prompt, so the tests run unattended.
#
# The first command must be an internal command (eg, VER), because pc.js converts only the first
# command into a path (eg, "\DOSTESTS.COM"), which BASIC-DOS doesn't understand.  Also, since output
# at the end of a session may be truncated by QUIT, the last test is followed by SLEEP 1 (SLEEP.COM from os/util).
#
cd "$(dirname "$0")/../.." || exit 1
tools/tests/prep.sh software/pcx86/src/configs/console/serial/fpe || exit 1
tools/tests/prep.sh software/pcx86/src/configs/console/serial/fpu || exit 1
log=$(mktemp)
#
# Since only DEBUG builds of COMMAND.COM display "Return code" after a program ends, we check
# ERRORLEVEL after each test program instead.
#
ok='IF ERRORLEVEL = 0 THEN PRINT "EXITOK" ELSE PRINT "EXITBAD"'
tools/pc/pc.js ibm5160-test software/pcx86/src/configs/console/serial/fpe "VER,MEM,FPUTESTS,$ok,DOSTESTS,$ok,STRFUN,STRPOOL,ARRAYS,FLOW,CMDS,VARS,FILEIO,FCBTESTS,$ok,PRINTF,$ok,SLEEP 1,QUIT" --system=bd --version=2 --floppy --serial --normalize --nosync | tee "$log"
tools/pc/pc.js ibm5160-test-fpu software/pcx86/src/configs/console/serial/fpu "VER,MEM,FPUTESTS,$ok,VARS,STRFUN,SLEEP 1,QUIT" --system=bd --version=2 --floppy --serial --normalize --nosync | tee -a "$log"
if ! grep -q "bytes FPU emulation" "$log" || ! grep -q "bytes FPU library" "$log" ||
   grep -q "Floating-point .*installed" "$log" || grep -q "failed" "$log" || grep -q "EXITBAD" "$log" || [ "$(grep -c "EXITOK" "$log")" -lt 5 ] ||
   [ "$(grep -c "STRFUN done" "$log")" -lt 2 ] || ! grep -q "STRPOOL done" "$log" ||
   ! grep -q "ARRAYS done" "$log" || ! grep -q "FLOW done" "$log" || ! grep -q "CMDS done" "$log" ||
   [ "$(grep -c "VARS done" "$log")" -lt 2 ] ||
   ! grep -Fq 'I% = -2147483647' "$log" || ! grep -Fq 'I# = 1.25' "$log" ||
   ! grep -Fq 'S$ = "hello"' "$log" || ! grep -Fq 'E$ = ""' "$log" ||
   ! grep -Fq 'A%(0 TO 2, 0 TO 3)' "$log" || ! grep -Fq 'Q%(1 TO 3)' "$log" ||
   ! grep -q "FILEIO done" "$log" || ! grep -q "FCBTESTS passed" "$log" ||
   [ "$(grep -c "1 FILE(S)" "$log")" -lt 2 ] || ! grep -q "Elapsed time is" "$log" ||
   ! grep -q "Returns the square root" "$log" || ! grep -q "hello world!" "$log"; then
    echo "TESTS FAILED"; rm -f "$log"; exit 1
fi
echo "TESTS PASSED"; rm -f "$log"
