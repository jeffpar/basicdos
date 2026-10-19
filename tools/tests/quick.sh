#!/bin/bash
# echo This command boots a BASIC-DOS test floppy (like ./boot.sh), runs FPUTESTS, DOSTESTS, STRFUN, STRPOOL,
# ARRAYS, FLOW, CMDS (commands, pipes, redirection, and HELP), VARS (variable listings), FILEIO (sequential and random files),
# PRTUSING (PRINTF USING), MOVES (file and directory moves), FCBTESTS (FCB
# functions), HARDERR (INT 24h hard error handling, using the empty drive B:; its ABORT test ends it with exit code 255),
# and PRINTF,
# and then quits; it then boots a test floppy
# on a machine with an 8087 (like ./boot.sh fpu), and runs FPUTESTS, VARS, and STRFUN.
# Finally, it boots a hard disk with both floppy drives empty (like ./boot.sh hd),
# and runs HARDERR from C:\TESTS\MISC to check hard disk data and metadata recovery.
# It's a very quick (and dirty) set of confidence tests.
# The exit code is non-zero if any test failed.
#
# NOTE: With --floppy, pc.js removes the machine's hard disk, which would otherwise make the BASIC-DOS
# boot sector display a "Press a key to start..." prompt, so the tests run unattended.
#
# The first command must be an internal command (eg, VER), because pc.js converts only the first
# command into a path (eg, "\DOSTESTS.COM"), which BASIC-DOS doesn't understand.  Also, since output
# at the end of a session may be truncated by QUIT, the last test is followed by SLEEP 1 (SLEEP.COM from os/util/misc).
#
cd "$(dirname "$0")/../.." || exit 1
tools/tests/prep.sh software/src/configs/console/serial/fpe || exit 1
tools/tests/prep.sh software/src/configs/console/serial/fpu || exit 1
tools/tests/prep.sh software/src/configs/console/serial/hd || exit 1
log=$(mktemp)
#
# Since only DEBUG builds of COMMAND.COM display "Return code" after a program ends, we check
# ERRORLEVEL after each test program instead.
#
ok='IF ERRORLEVEL = 0 THEN PRINT "EXITOK" ELSE PRINT "EXITBAD"'
abort='IF ERRORLEVEL = 255 THEN PRINT "ABORTOK" ELSE PRINT "ABORTBAD"'
#
# The tests in TESTS\MISC aren't on PATH$, so they're run by path (commands containing backslashes must be
# separated with semicolons).
#
m='\TESTS\MISC\'
tools/pc/pc.js ibm5160 software/src/configs/console/serial/fpe "VER;MEM;${m}FPUTESTS;$ok;${m}DOSTESTS;$ok;${m}STRFUN;${m}STRPOOL;${m}ARRAYS;${m}FLOW;${m}CMDS;${m}VARS;${m}FILEIO;${m}PRTUSING;${m}MOVES;${m}FCBTESTS;$ok;${m}HARDERR;$abort;${m}PRINTF;$ok;SLEEP 1;QUIT" --system=bd --version=2 --floppy --serial --normalize --nosync | tee "$log"
tools/pc/pc.js ibm5160 software/src/configs/console/serial/fpu "VER;MEM;${m}FPUTESTS;$ok;${m}VARS;${m}STRFUN;SLEEP 1;QUIT" --fpu --system=bd --version=2 --floppy --serial --normalize --nosync | tee -a "$log"
tools/pc/pc.js ibm5160 software/src/configs/console/serial/hd "VER;CD TESTS\MISC;HARDERR;$abort;SLEEP 1;QUIT" --system=bd --version=2 --target=10M --serial --normalize --nosync | tee -a "$log"
if grep -q "Floating-point .*installed" "$log" || grep -q "failed" "$log" || grep -q "EXITBAD" "$log" || [ "$(grep -c "EXITOK" "$log")" -lt 5 ] ||
   [ "$(grep -c "STRFUN done" "$log")" -lt 2 ] || ! grep -q "STRPOOL done" "$log" ||
   ! grep -q "ARRAYS done" "$log" || ! grep -q "FLOW done" "$log" || ! grep -q "CMDS done" "$log" ||
   [ "$(grep -c "VARS done" "$log")" -lt 2 ] ||
   ! grep -Fq 'I% = -2147483647' "$log" || ! grep -Fq 'I# = 1.25' "$log" ||
   ! grep -Fq 'S$ = "hello"' "$log" || ! grep -Fq 'E$ = ""' "$log" ||
   ! grep -Fq 'A%(0 TO 2, 0 TO 3)' "$log" || ! grep -Fq 'Q%(1 TO 3)' "$log" ||
   ! grep -q "MOVES done" "$log" || ! grep -q "FILEIO done" "$log" || ! grep -q "PRTUSING done" "$log" || ! grep -q "FCBTESTS passed" "$log" ||
   [ "$(grep -c "HARDERR passed" "$log")" -lt 2 ] || [ "$(grep -c "HARDERR metadata passed" "$log")" -lt 2 ] ||
   [ "$(grep -c "ABORTOK" "$log")" -lt 2 ] || grep -q "ABORTBAD" "$log" ||
   [ "$(grep -c "1 FILE(S)" "$log")" -lt 2 ] || ! grep -q "Elapsed time is" "$log" ||
   ! grep -q "Returns the square root" "$log" || ! grep -q "hello world!" "$log"; then
    echo "TESTS FAILED"; rm -f "$log"; exit 1
fi
echo "TESTS PASSED"; rm -f "$log"
