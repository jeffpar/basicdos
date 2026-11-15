#!/bin/bash
#
# Usage: tools/bdc/mkbdc.sh
#
# Builds software/src/tools/bd/BDC.EXE from the source in software/src/tools/bd/bdc, as its makefile
# does on a BASIC-DOS hard disk, but on MS-DOS 3.20 (software/disks/MSDOS320-C400.json) running in pc.js, whose
# drive D: is a folder here: Microsoft C 4.00 compiles it, LINK4 (the original, in software/src/tools/dos) links it
# with the BASIC-DOS libraries (software/src/tools/bd/lib, over software/src/tools/dos/lib), and STUB adds the NE
# loader stub.  A BASIC-DOS build produces the same file.
#
# Everything is done in tools/pc/disks/tmp-bdcbuild, which is removed first, and left for inspection afterward.
# Run test.sh before building a BDC.EXE that's going to be kept.
#
root=$(cd "$(dirname "$0")/../.." && pwd)
tools=$root/software/src/tools
src=$tools/bd/bdc
work=$root/tools/pc/disks/tmp-bdcbuild
dos=$work/d
cd "$root" || exit 1
if pgrep -f "pc\.js" > /dev/null; then
    echo "pc.js is running; try again when it's done" >&2
    exit 1
fi
rm -rf "$work"
mkdir -p "$dos/LIB" || exit 1
cp software/disks/MSDOS320-C400.json "$work.json" || exit 1
cp $src/*.c $src/*.h $src/bdc.def $tools/dos/LINK4.EXE $tools/bd/STUB.EXE "$dos/" || exit 1
cp $tools/dos/lib/* "$dos/LIB/" && cp $tools/bd/lib/* "$dos/LIB/" || exit 1
bat=$dos/MKDOS.BAT
: > "$bat"
for m in BDC PP DECL EXPR GEN OBJ; do
    printf "CL /c /FPa /Gs $m.C >C$m.ERR\r\n" >> "$bat"
done
printf 'LINK4 BDC+PP+DECL+EXPR+GEN+OBJ,BDC.NE,BDC.MAP,D:\\LIB\\,BDC.DEF >LINK4.ERR\r\n' >> "$bat"
printf 'STUB BDC.NE BDC.EXE >STUB.ERR\r\nQUIT\r\n' >> "$bat"

#
# pc.js needs a terminal, and input that stays open until it exits (a pipe from a sleep, which is the job's first
# process, and is stopped when pc.js is done).
#
echo "running MS-DOS (this takes a minute or two)..."
sleep 1800 | script -q /dev/null tools/pc/pc.js --disk="$work.json" --dir="$dos" --normalize --speed=16 --target=30M \
    --fat=16:2048:512 > "$work/pc.log" 2>&1 &
pc=$!
hold=$(jobs -p | tail -1)
sleep 5
while pgrep -f "node [^ ]*pc\.js --disk=$work.json" > /dev/null; do sleep 2; done
kill $hold $pc 2> /dev/null
wait 2> /dev/null
rm -f "$work.json"
if grep -a -i -q "error\|warning\|unresolved" "$dos"/*.ERR || [ ! -s "$dos/BDC.EXE" ]; then
    grep -a -i -h "error\|warning\|unresolved" "$dos"/*.ERR
    echo "BDC.EXE wasn't built (see $work)"
    exit 1
fi
if cmp -s "$dos/BDC.EXE" $tools/bd/BDC.EXE; then
    echo "BDC.EXE is unchanged"
else
    cp "$dos/BDC.EXE" $tools/bd/BDC.EXE && echo "BDC.EXE updated ($(wc -c < $tools/bd/BDC.EXE | tr -d ' ') bytes)"
fi
