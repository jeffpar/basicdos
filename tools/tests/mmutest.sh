#!/bin/bash
#
# Usage: tools/tests/mmutest.sh [8088] [real] [pm] [r3] [386] [r386] [multi] [pool] [tools]
#
# Runs quick.sh's floppy tests (FPUTESTS through PRINTF), followed by CPUTESTS, R3TESTS, and V86TEST (in V86.COM's V86
# machine, which only the "386" and "r386" machines have), on these test machines:
#
#   8088    an IBM PC XT (ibm5160), where CPU$ keeps only what an 8088 needs
#   real    a 2Mb IBM PC AT (ibm5170), where CPU$ acts as it does on an 8088 by default, so BASIC-DOS runs in real mode
#   pm      a 2Mb IBM PC AT with a "CPU=80286" line, where CPU$ manages extended memory and BASIC-DOS runs in protected
#           mode, with a "RING=0" line, so that programs run at ring 0 and every test runs (including CPUTESTS and
#           HARDERR's INT 13h hook tests)
#   r3      the same machine without the "RING=0" line, so that programs (and COMMAND.COM) run at ring 3, as they do
#           by default in protected mode, where CPUTESTS and HARDERR's hook tests print that they were skipped instead
#   386     a 2Mb COMPAQ DeskPro 386 (compaq386) with "CPU=80386" and "RING=0" lines, where CPU$ uses the 80386's
#           features (CPUTESTS also tests its selectors beyond 64K)
#   r386    the same machine without the "RING=0" line
#   multi   the "r3" machine with a second console (on its video adapter), since sysinit then loads the first SHELL from
#           another session's LDT; it runs only R3TESTS, since some tests (eg, HARDERR) won't run beside another session
#   pool    the "r3" machine with 9 sessions, where MEMTESTS fills the system area's pool of PMBs and LDT descriptors
#           from 7 sessions at once, and checks that their LDTs can move, and that the system recovers
#   tools   the "r3" machine with a hard disk, where MAKE rebuilds PRIMES.EXE and SLEEP.COM with the protected-mode build
#           tools in software/src/tools/bd (see tools/misc/mkne.js), which must match the binaries of the last build, and
#           runs EXEMOD and MAPSYM, which must succeed
#
# By default, it runs all nine.  The "pm", "r3", "multi", "pool", and "tools" machines boot a copy of a configuration with a
# "CPU=80286" line (and the "386" and "r386" machines, a "CPU=80386" line), in tools/pc/disks/tmp-mmupm, which is deleted
# afterward.  The exit code is non-zero if any test failed.
#
cd "$(dirname "$0")/../.." || exit 1
fpe=software/src/configs/console/serial/fpe
tmp=tools/pc/disks/tmp-mmupm
tools/tests/prep.sh $fpe || exit 1
ok='IF ERRORLEVEL = 0 THEN PRINT "EXITOK" ELSE PRINT "EXITBAD"'
abort='IF ERRORLEVEL = 255 THEN PRINT "ABORTOK" ELSE PRINT "ABORTBAD"'
m='\TESTS\REGRESS\'
cmds="VER;MEM;${m}FPUTESTS;$ok;${m}DOSTESTS;$ok;${m}BUFTESTS;${m}STRFUN;${m}STRPOOL;${m}ARRAYS;${m}FLOW;${m}EXPRERR;${m}CMDS;${m}VARS;${m}FILEIO;${m}RUNFILE;${m}PRTUSING;${m}MOVES;${m}ATTRS;${m}FCBTESTS;$ok;${m}HARDERR;$abort;${m}IOERR.COM;$ok;${m}PRINTF;$ok;\\TESTS\\MISC\\CPUTESTS;$ok;\\TESTS\\MISC\\R3TESTS;$ok;V86 \\TESTS\\MISC\\V86TEST;SLEEP 1;QUIT"
log=$(mktemp)
failed=
for name in ${@:-8088 real pm r3 386 r386 multi pool tools}; do
    meta="HARDERR metadata passed"; seek="HARDERR seek passed"; above="BUFTESTS passed"; r3t="R3TESTS skipped"
    v86="V86 mode not available"
    case $name in
        8088)   args="ibm5160 $fpe"; cpu="CPU type 0 (hardware 0)" ;;
        real)   args="ibm5170 $fpe --ram=2M"; cpu="CPU type 0 (hardware 2)" ;;
        multi)  rm -rf $tmp
                cp -R $fpe $tmp || exit 1
                grep -v "^SKIP=" $fpe/CONFIG.SYS > $tmp/CONFIG.SYS
                printf 'CPU=80286\nSHELL=COMMAND.COM\n' >> $tmp/CONFIG.SYS
                tools/pc/pc.js ibm5170 $tmp --ram=2M "VER;MEM;\TESTS\MISC\R3TESTS;$ok;SLEEP 1;QUIT" --sys=bd:2 --floppy --serial --normalize --nosync | tee "$log"
                if ! grep -q "R3TESTS passed" "$log" || ! grep -q "EXITOK" "$log"; then
                    failed="$failed $name"
                fi
                continue ;;
        pool)   rm -rf $tmp
                cp -R $fpe $tmp || exit 1
                grep -v "^SESSIONS=" $fpe/CONFIG.SYS > $tmp/CONFIG.SYS
                printf 'CPU=80286\nSESSIONS=9\n' >> $tmp/CONFIG.SYS
                tools/pc/pc.js ibm5170 $tmp --ram=2M "VER;\TESTS\MISC\MEMTESTS;MEM;TYPE CONFIG.SYS | FIND \"CPU\";SLEEP 1;QUIT" --sys=bd:2 --floppy --serial --normalize --nosync | tee "$log"
                if ! grep -q "MEMTESTS passed" "$log" || ! grep -q "MEMTESTS pool full" "$log" || grep -q "CPU fault" "$log" ||
                   grep -q "MEMTESTS failed" "$log" || ! grep -q "^CPU=80286" "$log"; then
                    failed="$failed $name"
                fi
                continue ;;
        tools)  rm -rf $tmp
                src=software/src
                mkdir -p $tmp/MT/PRIMES $tmp/MT/OBJ $tmp/MT/BIN $tmp/OS/INC $tmp/TOOLS || exit 1
                printf 'CPU=80286\nSKIP=VKD$\nCON=COM1:9600,N,8,1\nSHELL=COMMAND.COM PATH$="C:\\;C:\\EXT;C:\\TOOLS"\n' > $tmp/CONFIG.SYS
                tools/tests/prep.sh $tmp || exit 1
                cp $src/tools/dos/*.EXE $tmp/TOOLS/ && cp $src/tools/bd/*.EXE $tmp/TOOLS/ || exit 1
                cp $src/os/inc/*.inc $tmp/OS/INC/ && cp $src/tests/primes/primes.asm $src/tests/primes/PRIMES.DEF $tmp/MT/PRIMES/ &&
                    cp $src/os/util/misc/sleep.asm $tmp/MT/ || exit 1
                cp $src/tests/bin/PRIMES.EXE $tmp/MT/REF.EXE && cp $src/os/util/misc/OBJ/SLEEP.COM $tmp/MT/REF.COM || exit 1
                #
                # These rules use the same commands and switches as the rules in the TESTS and UTIL\MISC makefiles.
                #
                sed 's/$/\r/' > $tmp/MT/MAKEFILE <<'EOF'
BIN\PRIMES.EXE: PRIMES\PRIMES.ASM PRIMES\PRIMES.DEF
	MASM /MX /R /D$(REL) /I..\OS\INC PRIMES\$*.ASM,BIN\$*.OBJ,NUL;
	LINK BIN\$*.OBJ,OBJ\$*.EXE;
	LINK4 BIN\$*.OBJ,$@/ALIGN:16,NUL,,PRIMES\$*.DEF;
	DEL BIN\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\SLEEP.COM: SLEEP.ASM
	MASM /MX /R /D$(REL) /I. /I..\OS\INC $*.ASM,OBJ\$*.OBJ,NUL;
	LINK OBJ\$*.OBJ,OBJ\$*.EXE;
	EXE2BIN OBJ\$*.EXE $@

M.SYM: OBJ\SLEEP.COM
	LINK OBJ\SLEEP.OBJ,M.EXE,M.MAP/MAP;
	EXEMOD M.EXE /MIN 400
	MAPSYM M
EOF
                tools/pc/pc.js ibm5170 $tmp --ram=2M "VER;CD MT;MAKE REL=$(cat tools/pc/disks/mkmode) MAKEFILE;$ok;COMP BIN\PRIMES.EXE REF.EXE;COMP OBJ\SLEEP.COM REF.COM;DIR M.SYM;SLEEP 1;CD \;QUIT" \
                    --sys=bd:2 --target=10M --serial --normalize --nosync --speed=8 | tee "$log"
                if ! grep -q "Assembler  Version 4.00BD" "$log" || ! grep -q "Linker  Version 3.05BD" "$log" ||
                   ! grep -q "Linker  Version 5.00.12BD" "$log" || ! grep -q "Utility  Version 4.02BD" "$log" ||
                   ! grep -q "Utility  Version 4.00BD" "$log" || ! grep -q "Generator  Version 4.00BD" "$log" ||
                   ! grep -q "EXITOK" "$log" || grep -q "EXITBAD" "$log" || grep -q "CPU fault" "$log" ||
                   [ "$(grep -c "Files compare ok" "$log")" -ne 2 ] || ! grep -q "^M  *SYM " "$log"; then
                    failed="$failed $name"
                fi
                continue ;;
        pm|r3|386|r386)
                rm -rf $tmp
                cp -R $fpe $tmp || exit 1
                case $name in
                    *386) echo CPU=80386 >> $tmp/CONFIG.SYS
                          args="compaq386 $tmp --ram=2M"; cpu="CPU type 3 (hardware 3)"; v86="V86TEST passed" ;;
                    *)    echo CPU=80286 >> $tmp/CONFIG.SYS
                          args="ibm5170 $tmp --ram=2M"; cpu="CPU type 2 (hardware 2)" ;;
                esac
                if [ $name = pm ] || [ $name = 386 ]; then
                    echo RING=0 >> $tmp/CONFIG.SYS
                    above="BUFTESTS block above 1Mb"
                else
                    cpu="CPUTESTS skipped"; meta="HARDERR hook tests skipped"; seek=$meta; r3t="R3TESTS passed"
                fi ;;
        *)      echo "usage: $0 [8088] [real] [pm] [r3] [386] [r386] [multi] [pool] [tools]" >&2; exit 1 ;;
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
       ! grep -q "BUFTESTS passed" "$log" || ! grep -q "$above" "$log" ||
       ! grep -q "MOVES passed" "$log" || ! grep -q "ATTRS passed" "$log" || ! grep -q "FILEIO passed" "$log" ||
       ! grep -q "RUNFILE passed" "$log" || ! grep -q "PRTUSING passed" "$log" || ! grep -q "FCBTESTS passed" "$log" ||
       ! grep -q "HARDERR passed" "$log" || ! grep -q "$meta" "$log" ||
       ! grep -q "$seek" "$log" || ! grep -q "IOERR passed" "$log" || ! grep -q "$r3t" "$log" ||
       ! grep -q "ABORTOK" "$log" || grep -q "ABORTBAD" "$log" || ! grep -q "1 FILE(S)" "$log" ||
       ! grep -q "Elapsed time is" "$log" || ! grep -q "Returns the square root" "$log" ||
       ! grep -q "hello world!" "$log" || ! grep -q "$v86" "$log"; then
        failed="$failed $name"
    fi
done
rm -rf $tmp
rm -f "$log"
if [ -n "$failed" ]; then
    echo "TESTS FAILED:$failed"; exit 1
fi
echo "TESTS PASSED"
