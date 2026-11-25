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
 * name is an error.
 *
 * It also gives a bound program's DOS stub (BIND's real-mode loader, which
 * displays "SYS2090" when it can't load the program) the name of the output
 * file: on a DOS before 3.00, like BASIC-DOS, the stub finds its own file by
 * searching the current directory and PATH for the name that BIND recorded
 * (eg, "clb" for CL386.EXE), which is just before the stub's entry point, as
 * a length word and up to 8 characters (zero-padded to 9 bytes).  Its PATH
 * search uses the program's module name instead (eg, "CL", which would find
 * Microsoft C's CL.EXE), so if that's different, the search's 14 bytes that
 * load the module name (DS:SI and CX) are replaced with code that loads the
 * stub's name.  Older stubs (eg, CL386's, but not LINK386's) have two more
 * bugs that keep the search from finding anything, which are fixed as newer
 * stubs fix them: an LDS that makes the search read PATH from the wrong
 * segment is removed, and the name is copied with a length of 13 (up to 8
 * characters, ".EXE", and a null) instead of one that's never set.
 *
 * It exits with code 2 if the file had nothing to change.
 */
import fs from "fs";
import path from "path";

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
const hdr = d.readUInt16LE(0x08) * 16, ip = d.readUInt16LE(0x14), cs = hdr + d.readUInt16LE(0x16) * 16;
const field = cs + ip - 11;
if (d.toString("latin1", 0, ne).includes("SYS2090") && field >= hdr && d.readUInt16LE(field) <= 8) {
    const name = path.basename(output, path.extname(output)).toLowerCase();
    const old = d.toString("latin1", field + 2, field + 2 + d.readUInt16LE(field));
    if (name.length > 8) {
        console.error(output + ": name too long for the stub");
        process.exit(1);
    }
    if (name != old) {
        d.writeUInt16LE(name.length, field);
        d.fill(0, field + 2, field + 11);
        d.write(name, field + 2, "latin1");
        console.log("stub name " + old + " -> " + name);
        changed++;
    }
    //
    // The PATH search's "mov ds,cs:[seg]; mov si,[26h]; mov cl,[si]; xor ch,ch; inc si" (the module name, from the
    // NE header's resident-name table) becomes "push cs; pop ds; mov si,name; mov cx,[length]" and 5 NOPs.
    //
    if (pstr(ne + d.readUInt16LE(ne + 0x26)).toLowerCase() != name) {
        const load = Buffer.from([0x8B, 0x36, 0x26, 0x00, 0x8A, 0x0C, 0x32, 0xED, 0x46]);
        let off = -1;
        for (let i = d.indexOf(load, hdr); i >= 0 && i < ne; i = d.indexOf(load, i + 1)) {
            if (d[i - 5] == 0x2E && d[i - 4] == 0x8E && d[i - 3] == 0x1E) {
                if (off >= 0) off = -2;
                if (off == -1) off = i - 5;
            }
        }
        if (off < 0) {
            console.error(input + ": stub's PATH search not found");
            process.exit(1);
        }
        d.set([0x0E, 0x1F, 0xBE, (ip - 9) & 0xFF, (ip - 9) >> 8, 0x8B, 0x0E, (ip - 11) & 0xFF, (ip - 11) >> 8,
               0x90, 0x90, 0x90, 0x90, 0x90], off);
        console.log("stub PATH search uses " + name + " (at " + (off - cs).toString(16) + "h)");
        changed++;
    }
    //
    // An older stub's "mov cs:[x],si; lds dx,cs:[y]; mov es,cs:[z]" loses its LDS (5 NOPs), and its
    // "mov cl,cs:[len]; xor ch,ch; rep movsb" becomes "mov cl,13" and 3 NOPs.
    //
    const lds = Buffer.from([0x2E, 0xC5, 0x16]);
    for (let i = d.indexOf(lds, hdr); i >= 0 && i < ne; i = d.indexOf(lds, i + 1)) {
        if (d.readUInt16LE(i - 5) == 0x892E && d[i - 3] == 0x36 && d.readUInt16LE(i + 5) == 0x8E2E && d[i + 7] == 0x06) {
            d.fill(0x90, i, i + 5);
            console.log("stub PATH search reads PATH from the environment (at " + (i - cs).toString(16) + "h)");
            changed++;
        }
    }
    const copy = Buffer.from([0x32, 0xED, 0xF3, 0xA4]);
    for (let i = d.indexOf(copy, hdr); i >= 0 && i < ne; i = d.indexOf(copy, i + 1)) {
        if (d[i - 5] == 0x2E && d[i - 4] == 0x8A && d[i - 3] == 0x0E) {
            d.set([0xB1, 0x0D, 0x90, 0x90, 0x90], i - 5);
            console.log("stub PATH search copies 13 bytes (at " + (i - 5 - cs).toString(16) + "h)");
            changed++;
        }
    }
}
if (!changed) {
    console.log(input + ": nothing to change");
    process.exit(2);
}
fs.writeFileSync(output, d);
