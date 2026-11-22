#!/usr/bin/env node
/**
 * @fileoverview Makes the BASIC-DOS version of an OS/2 1.x (NE) program
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * Usage: node tools/misc/os2bd.js in.exe out.exe
 *
 * BASIC-DOS's NE loader resolves a library's functions by ordinal only, so
 * this rewrites each relocation record that imports a function by name as
 * one that imports it by ordinal (the file's size and everything else stay
 * the same).  It knows the ordinals of the functions in NAMES; any other
 * name is an error.  It exits with code 2 if the file had nothing to change.
 */
import fs from "fs";

const NAMES = {
    "NLS.DOSGETDBCSEV": 4
};

const [input, output] = process.argv.slice(2);
if (!input || !output) {
    console.error("usage: os2bd.js in.exe out.exe");
    process.exit(1);
}
const d = fs.readFileSync(input);
const ne = d.readUInt32LE(0x3C);
if (d.toString("latin1", 0, 2) != "MZ" || d.toString("latin1", ne, ne + 2) != "NE") {
    console.error(input + ": not an NE file");
    process.exit(1);
}
const nSegs = d.readUInt16LE(ne + 0x1C), nMods = d.readUInt16LE(ne + 0x1E);
const segTab = ne + d.readUInt16LE(ne + 0x22), modTab = ne + d.readUInt16LE(ne + 0x28);
const impTab = ne + d.readUInt16LE(ne + 0x2A), shift = d.readUInt16LE(ne + 0x32);
const pstr = (off) => d.toString("latin1", off + 1, off + 1 + d[off]);
const mods = [];
for (let i = 0; i < nMods; i++) mods.push(pstr(impTab + d.readUInt16LE(modTab + i * 2)));
let changed = 0;
for (let i = 0; i < nSegs; i++) {
    const e = segTab + i * 8;
    const sector = d.readUInt16LE(e), length = d.readUInt16LE(e + 2) || 0x10000, flags = d.readUInt16LE(e + 4);
    if (!sector || !(flags & 0x0100)) continue;         // no data, or no relocations
    let p = sector * (1 << shift) + length;
    const n = d.readUInt16LE(p);
    p += 2;
    for (let j = 0; j < n; j++, p += 8) {
        if ((d[p + 1] & 0x03) != 2) continue;           // not an import by name
        const name = mods[d.readUInt16LE(p + 4) - 1] + "." + pstr(impTab + d.readUInt16LE(p + 6));
        const ordinal = NAMES[name];
        if (!ordinal) {
            console.error(input + ": unknown import " + name);
            process.exit(1);
        }
        d[p + 1] = (d[p + 1] & ~0x03) | 0x01;           // an import by ordinal
        d.writeUInt16LE(ordinal, p + 6);
        console.log(name + " -> " + ordinal + " (segment " + (i + 1) + ")");
        changed++;
    }
}
if (!changed) {
    console.log(input + ": nothing to change");
    process.exit(2);
}
fs.writeFileSync(output, d);
