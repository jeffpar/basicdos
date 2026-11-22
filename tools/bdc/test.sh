#!/bin/bash
#
# Usage: tools/bdc/test.sh
#
# Tests BDC, the BASIC-DOS C compiler, using a copy of it built on this machine and MS-DOS 3.20 with Microsoft C 4.00
# (software/disks/historical/dos/MSDOS320-C400.json) running in pc.js:
#
#   1. Each test program is compiled here by BDC, and linked and run on MS-DOS.  Its output must match the output of
#      the same program compiled there by Microsoft C (ints, longs, misc), or the test's .exp file: ansi is a
#      self-checking test of things that Microsoft C doesn't accept, and sucks1 and sucks2 are the programs in
#      software/src/tools/dos/demos (the originals of the ones in bd/demos/sucks), changed only to end when their input (the test's .in file) does; their .exp files are the
#      output of those programs when Microsoft C compiled versions of them that it accepts.
#
#   2. BDC is built on MS-DOS twice: by Microsoft C (BDCM.EXE), and from the object files that the BDC built here
#      made from its own source (BDCS.EXE).  Each of those must then compile every test program, and BDCS must compile
#      BDC's source, to the same object files as the BDC built here.
#
# To add a test, add a .c file here (with a name of up to seven characters) and its name to "tests" below, with an
# .exp file if Microsoft C can't compile it, and an .in file if it reads input.
#
# Everything is done in tools/pc/disks/tmp-bdctest, which is removed first, and left for inspection afterward.
# BDC.EXE itself is built by mkbdc.sh.
#
root=$(cd "$(dirname "$0")/../.." && pwd)
src=$root/software/src/tools/bd/bdc
tdir=$root/tools/bdc
inc=$root/software/src/tools/dos/include
work=$root/tools/pc/disks/tmp-bdctest
dos=$work/d                             # MS-DOS drive D:
host=$work/host                         # the BDC built here, and what it compiles
tests="ints longs misc ansi sucks1 sucks2"
mods="bdc pp decl expr gen obj"
cd "$root" || exit 1
if pgrep -f "pc\.js" > /dev/null; then
    echo "pc.js is running; try again when it's done" >&2
    exit 1
fi
rm -rf "$work"
mkdir -p "$dos" "$host" || exit 1
cp software/disks/historical/dos/MSDOS320-C400.json "$work.json" || exit 1
cc -std=gnu89 -DHOST -w -o "$host/bdc" $src/*.c || exit 1

upper() { echo "$1" | tr a-z A-Z; }

#
# The sucks tests are the demos' original sources, after definitions that make them end at the end of their input
# (and max, which sucks1 uses).
#
cat > "$host/wsucks1.c" <<'END'
#include <stdio.h>
#include <stdlib.h>
int xscanf(f, a, b, c, d) char *f; int *a, *b, *c, *d;
{ int n; n = scanf(f, a, b, c, d); if (n <= 0) exit(0); return n; }
#define scanf xscanf
#define max(a,b) (((a) > (b)) ? (a) : (b))
END
cat > "$host/wsucks2.c" <<'END'
#include <stdio.h>
#include <string.h>
char *gets();
char *xgets(s) char *s;
{ if (!gets(s)) exit(0); return s; }
#define gets xgets
END
for t in sucks1 sucks2; do
    tr -d '\r' < $src/../../dos/demos/$t.c | grep -v '^#include <' >> "$host/w$t.c"
done

#
# Compile everything here, and write the batch file that MS-DOS runs (AUTOEXEC.BAT runs D:\MKDOS.BAT, which must end
# with QUIT, so that pc.js exits and saves D:'s files).  A test's files on D: are its name plus a letter: B for the
# object file from here, M and S for the ones from BDCM and BDCS, and none for Microsoft C's.
#
fails=0
bat=$dos/MKDOS.BAT
: > "$bat"
for t in $tests; do
    T=$(upper $t)
    s=$tdir/$t.c
    [ -f "$host/w$t.c" ] && s=$host/w$t.c
    cp "$s" "$host/$T.C"
    cp "$s" "$dos/$T.C"
    if ! (cd "$host" && ./bdc -I"$inc" -Fo${T}B.OBJ $T.C); then
        echo "FAIL $t: BDC reported errors"
        fails=$((fails + 1))
        continue
    fi
    cp "$host/${T}B.OBJ" "$dos/"
    in=""
    if [ -f $tdir/$t.in ]; then
        cp $tdir/$t.in "$dos/$T.IN"
        in="<$T.IN "
    fi
    if [ ! -f $tdir/$t.exp ]; then
        printf "CL /FPa /Gs $T.C >$T.ERR\r\n$T $in>$T.OUT\r\n" >> "$bat"
    fi
    printf "LINK ${T}B,,NUL; >${T}B.ERR\r\n${T}B $in>${T}B.OUT\r\n" >> "$bat"
done
cp $src/*.c $src/*.h "$dos/"
cp $src/bdc.h "$host/"
objs=""
sobjs=""
for m in $mods; do
    M=$(upper $m)
    cp $src/$m.c "$host/$M.C"
    (cd "$host" && ./bdc -I"$inc" -FoS$M.OBJ $M.C) || fails=$((fails + 1))
    cp "$host/S$M.OBJ" "$dos/"
    printf "CL /c /FPa /Gs $M.C >C$M.ERR\r\n" >> "$bat"
    objs="$objs+$M"
    sobjs="$sobjs+S$M"
done
printf "LINK /STACK:6144 ${objs#+},BDCM.EXE,NUL; >BDCM.ERR\r\n" >> "$bat"
printf "LINK /STACK:6144 ${sobjs#+},BDCS.EXE,NUL; >BDCS.ERR\r\n" >> "$bat"
for t in $tests; do
    T=$(upper $t)
    for v in M S; do
        printf "BDC$v /Ic:\\\\tools\\\\c4inc /Fo$T$v.OBJ $T.C >$T$v.ERR\r\n" >> "$bat"
    done
done
for m in $mods; do
    M=$(upper $m)
    printf "BDCS /Ic:\\\\tools\\\\c4inc /FoX$M.OBJ $M.C >X$M.ERR\r\n" >> "$bat"
done
printf "QUIT\r\n" >> "$bat"

#
# pc.js needs a terminal, and input that stays open until it exits (a pipe from a sleep, which is the job's first
# process, and is stopped when pc.js is done).
#
echo "running MS-DOS (this takes a few minutes)..."
sleep 1800 | script -q /dev/null tools/pc/pc.js --disk="$work.json" --dir="$dos" --normalize --speed=16 --target=30M \
    --fat=16:2048:512 > "$work/pc.log" 2>&1 &
pc=$!
hold=$(jobs -p | tail -1)
sleep 5
while pgrep -f "node [^ ]*pc\.js --disk=$work.json" > /dev/null; do sleep 2; done
kill $hold $pc 2> /dev/null
wait 2> /dev/null

check() {                               # check name, file, expected file
    if [ -f "$2" ] && cmp -s <(tr -d '\r' < "$2") <(tr -d '\r' < "$3"); then
        echo "pass $1"
    else
        echo "FAIL $1 (compare $2 with $3)"
        fails=$((fails + 1))
    fi
}
same() {                                # same name, file, expected file (binary)
    if [ -f "$2" ] && cmp -s "$2" "$3"; then
        echo "pass $1"
    else
        echo "FAIL $1 ($2 differs from $3)"
        fails=$((fails + 1))
    fi
}
for t in $tests; do
    T=$(upper $t)
    [ -f "$dos/${T}B.OBJ" ] || continue
    exp=$tdir/$t.exp
    [ -f $exp ] || exp=$dos/$T.OUT
    check "$t: output" "$dos/${T}B.OUT" "$exp"
    same "$t: object file from BDC built by Microsoft C" "$dos/${T}M.OBJ" "$host/${T}B.OBJ"
    same "$t: object file from BDC built by BDC" "$dos/${T}S.OBJ" "$host/${T}B.OBJ"
done
for m in $mods; do
    M=$(upper $m)
    same "$m.c: object file from BDC built by BDC" "$dos/X$M.OBJ" "$host/S$M.OBJ"
done
rm -f "$work.json"
if [ $fails -ne 0 ]; then
    echo "$fails failed (see $work)"
    exit 1
fi
echo "all passed"
