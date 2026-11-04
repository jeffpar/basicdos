#!/bin/bash
#
# Usage: tools/tests/mmutest.sh [8088] [real] [pm] [r3]
#
# Runs quick.sh's floppy tests (FPUTESTS through PRINTF), followed by CPUTESTS, on these test machines:
#
#   8088    an IBM PC XT (ibm5160), where CPU$ keeps only what an 8088 needs
#   real    a 2Mb IBM PC AT (ibm5170), where the fpe configuration's "CPU=8088" line makes CPU$ act as it does on an
#           8088, so BASIC-DOS runs in real mode
#   pm      a 2Mb IBM PC AT without that line, where CPU$ manages extended memory and BASIC-DOS runs in protected
#           mode, with a "RING=0" line, so that programs run at ring 0 and every test runs (including CPUTESTS and
#           HARDERR's INT 13h hook tests)
#   r3      the same machine without the "RING=0" line, so that programs (and COMMAND.COM) run at ring 3, as they do
#           by default, where CPUTESTS and HARDERR's hook tests print that they were skipped instead
#
# By default, it runs all four.  The "pm" and "r3" machines boot a copy of the fpe configuration without the
# "CPU=8088" line, in tools/pc/disks/tmp-mmupm, which is deleted afterward.  The exit code is non-zero if any test
# failed.
#
cd "$(dirname "$0")/../.." || exit 1
fpe=software/src/configs/console/serial/fpe
tmp=tools/pc/disks/tmp-mmupm
tools/tests/prep.sh $fpe || exit 1
ok='IF ERRORLEVEL = 0 THEN PRINT "EXITOK" ELSE PRINT "EXITBAD"'
abort='IF ERRORLEVEL = 255 THEN PRINT "ABORTOK" ELSE PRINT "ABORTBAD"'
m='\TESTS\REGRESS\'
cmds="VER;MEM;${m}FPUTESTS;$ok;${m}DOSTESTS;$ok;${m}STRFUN;${m}STRPOOL;${m}ARRAYS;${m}FLOW;${m}EXPRERR;${m}CMDS;${m}VARS;${m}FILEIO;${m}RUNFILE;${m}PRTUSING;${m}MOVES;${m}ATTRS;${m}FCBTESTS;$ok;${m}HARDERR;$abort;${m}IOERR.COM;$ok;${m}PRINTF;$ok;\\TESTS\\MISC\\CPUTESTS;$ok;SLEEP 1;QUIT"
log=$(mktemp)
failed=
for name in ${@:-8088 real pm r3}; do
    meta="HARDERR metadata passed"; seek="HARDERR seek passed"
    case $name in
        8088)   args="ibm5160 $fpe"; cpu="CPU type 0 (hardware 0)" ;;
        real)   args="ibm5170 $fpe --ram=2M"; cpu="CPU type 0 (hardware 2)" ;;
        pm|r3)  rm -rf $tmp
                cp -R $fpe $tmp || exit 1
                grep -v "^CPU=" $fpe/CONFIG.SYS > $tmp/CONFIG.SYS
                args="ibm5170 $tmp --ram=2M"; cpu="CPU type 2 (hardware 2)"
                if [ $name = pm ]; then
                    echo RING=0 >> $tmp/CONFIG.SYS
                else
                    cpu="CPUTESTS skipped"; meta="HARDERR hook tests skipped"; seek=$meta
                fi ;;
        *)      echo "usage: $0 [8088] [real] [pm] [r3]" >&2; exit 1 ;;
    esac
    tools/pc/pc.js $args "$cmds" --sys=bd:2 --floppy --serial --normalize --nosync | tee "$log"
    if grep -q "Floating-point .*installed" "$log" || grep -q "failed" "$log" || grep -q "EXITBAD" "$log" ||
       [ "$(grep -c "EXITOK" "$log")" -lt 6 ] || ! grep -q "$cpu" "$log" ||
       ! grep -q "STRFUN passed" "$log" || ! grep -q "STRPOOL passed" "$log" ||
       ! grep -q "ARRAYS passed" "$log" || ! grep -q "FLOW passed" "$log" || ! grep -q "EXPRERR passed" "$log" ||
       ! grep -q "CMDS passed" "$log" || ! grep -q "VARS passed" "$log" ||
       ! grep -Fq 'I% = -2147483647' "$log" || ! grep -Fq 'I# = 1.25' "$log" ||
       ! grep -Fq 'S$ = "hello"' "$log" || ! grep -Fq 'E$ = ""' "$log" ||
       ! grep -Fq 'A%(0 TO 2, 0 TO 3)' "$log" || ! grep -Fq 'Q%(1 TO 3)' "$log" ||
       ! grep -q "MOVES passed" "$log" || ! grep -q "ATTRS passed" "$log" || ! grep -q "FILEIO passed" "$log" ||
       ! grep -q "RUNFILE passed" "$log" || ! grep -q "PRTUSING passed" "$log" || ! grep -q "FCBTESTS passed" "$log" ||
       ! grep -q "HARDERR passed" "$log" || ! grep -q "$meta" "$log" ||
       ! grep -q "$seek" "$log" || ! grep -q "IOERR passed" "$log" ||
       ! grep -q "ABORTOK" "$log" || grep -q "ABORTBAD" "$log" || ! grep -q "1 FILE(S)" "$log" ||
       ! grep -q "Elapsed time is" "$log" || ! grep -q "Returns the square root" "$log" ||
       ! grep -q "hello world!" "$log"; then
        failed="$failed $name"
    fi
done
rm -rf $tmp
rm -f "$log"
if [ -n "$failed" ]; then
    echo "TESTS FAILED:$failed"; exit 1
fi
echo "TESTS PASSED"
