#!/bin/bash
#
# Runs BENCH.BAS (software/pcx86/src/tests/misc) with BASIC-DOS, BASICA, and GW-BASIC (MSBASIC.EXE), each on
# an IBM PC XT with a CGA (ibm5160-cga), both without and with an 8087 (ibm5160-cga-fpu), all six at once, and
# then prints each test's time in seconds (BIOS ticks / 18.2), as shown on the preview/part6 page.
#
# Build first (see mk.sh), so that COMMAND.COM and MSBASIC.EXE are current.  The BASICA runs use BASICA.COM from
# the PC DOS 2.00 diskette (extracted with diskimage.js from the PCJS repository, which defaults to ../pcjs) and
# the machine's ROM BASIC.
#
# Each machine is given SECS seconds (the first argument, default 420) to finish, after which its debugger dumps
# the text screen.  Keystrokes are typed into the debugger one at a time, because pc.js ignores longer input chunks
# in debug mode.  The BASIC-DOS boot sector waits for a key when there's a debugger, so those runs press one.
#
# NOTE: When a command list is passed to pc.js, it converts the first command into a path, so every list
# starts with VER (eg, "VER,MSBASIC BENCH"); otherwise, PC DOS never runs the program.
#
cd "$(dirname "$0")/../.." || exit 1
secs=${1:-420}
src=software/pcx86/src
out=tools/pc/disks/bench
for f in $src/tests/misc/BENCH.BAS $src/msb/OBJ/MSBASIC.EXE; do
    if [ ! -f "$f" ]; then echo "error: $f not found (has it been built?)" >&2; exit 1; fi
done
rm -rf "$out/bd"
mkdir -p "$out/bd/TESTS" "$out/pc"
cp demos/s80/CONFIG.SYS "$out/bd/"
cp $src/tests/misc/BENCH.BAS "$out/bd/TESTS/"
cp $src/tests/misc/BENCH.BAS $src/msb/OBJ/MSBASIC.EXE "$out/pc/"
if [ ! -f "$out/pc/BASICA.COM" ]; then
    root=$(pwd)
    pcjs=$(cd "${PCJS:-../pcjs}" 2>/dev/null && pwd)
    (cd "$out/pc" && node "$pcjs/tools/diskimage/diskimage.js" "$root/software/pcx86/disks/PCDOS200-DISK1.json" \
        --extract=BASICA.COM > /dev/null 2>&1)
    if [ ! -f "$out/pc/BASICA.COM" ]; then echo "error: unable to extract BASICA.COM (set PCJS)" >&2; exit 1; fi
fi
rm -f "${out:?}"/*.out
for key in 0 1; do
    cat > "$out/drive$key.sh" <<EOF
dbg() { local s="\$1"; for ((i=0;i<\${#s};i++)); do printf '%s' "\${s:\$i:1}"; sleep 0.05; done; printf '\r'; sleep 1; }
[ $key = 1 ] && { sleep 12; printf " "; }
sleep $secs; printf '\004'; sleep 1
dbg "db b800:0 lfa0"; sleep 3; dbg "abort"; sleep 2
EOF
done
run() {
    local name=$1 key=$2 machine=$3 dir=$4 cmds=$5; shift 5
    (bash "$out/drive$key.sh" | timeout $((secs + 120)) script -q /dev/null tools/pc/pc.js $machine "$dir" "$cmds" "$@" \
        --floppy --normalize --nosync > "$out/$name.out" 2>&1) &
    sleep 15
}
echo "running 6 configurations (about $((secs / 60 + 3)) minutes)..."
run bd 1 ibm5160-cga "$out/bd" "VER,TESTS/BENCH" --system=bd --version=2
run bdf 1 ibm5160-cga-fpu "$out/bd" "VER,TESTS/BENCH" --system=bd --version=2
run ba 0 ibm5160-cga "$out/pc" "VER,BASICA BENCH" --system=pcdos --version=2.00
run baf 0 ibm5160-cga-fpu "$out/pc" "VER,BASICA BENCH" --system=pcdos --version=2.00
run gw 0 ibm5160-cga "$out/pc" "VER,MSBASIC BENCH" --system=pcdos --version=2.00
run gwf 0 ibm5160-cga-fpu "$out/pc" "VER,MSBASIC BENCH" --system=pcdos --version=2.00
wait
python3 - "$out" <<'EOF'
import re, sys
out = sys.argv[1]
cols = [("ba", "BASICA"), ("baf", "w/8087"), ("gw", "GW-BASIC"), ("gwf", "w/8087"), ("bd", "BASIC-DOS"), ("bdf", "w/8087")]
ticks = {}
for name, _ in cols:
    text = open(f"{out}/{name}.out", errors="ignore").read()
    mem = bytearray()
    for m in re.finditer(r'b800:[0-9a-f]{4}\s+((?:[0-9a-f]{2}[ -]){16})', text, re.I):
        mem += bytes(int(x, 16) for x in re.findall(r'[0-9a-f]{2}', m.group(1), re.I))
    screen = mem[0::2].decode("latin1")
    ticks[name] = {int(t): int(n) for t, n in re.findall(r'TEST\s+(\d+)\s+TICKS\s+(\d+)', screen)}
    if len(ticks[name]) < 10:
        print(f"warning: {name} has only {len(ticks[name])} results (increase SECS?)", file=sys.stderr)
print("Test " + "".join(f"{label:>10}" for _, label in cols))
for t in range(1, 11):
    row = f"{t:4} "
    for name, _ in cols:
        n = ticks[name].get(t)
        row += f"{n / 18.2:10.1f}" if n is not None else f"{'-':>10}"
    print(row)
EOF
