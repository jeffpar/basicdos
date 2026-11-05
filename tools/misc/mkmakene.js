#!/usr/bin/env node
/**
 * Convert the MAKE 4.02 MZ executable to the restricted NE format that
 * BASIC-DOS loads in protected mode.  The original MZ image remains the
 * real-mode stub, so the result still runs under MS-DOS and real-mode
 * BASIC-DOS.
 */

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const sourceHash =
    "04bf03c0c2521ed5c7958c4fc46c2cbcf3ee5a5a2d6c232efb7a42e3afd9c6af";
const sourceName = process.argv[2] || "software/src/tools/dos/MAKE.EXE";
const outputName = process.argv[3] || "software/src/tools/bd/MAKE.EXE";
const source = fs.readFileSync(sourceName);
const hash = crypto.createHash("sha256").update(source).digest("hex");

if (hash !== sourceHash) {
    throw new Error(`unsupported MAKE.EXE (SHA-256 ${hash})`);
}

const word = (buffer, offset) => buffer.readUInt16LE(offset);
const putWord = (buffer, offset, value) =>
    buffer.writeUInt16LE(value, offset);
const putDWord = (buffer, offset, value) =>
    buffer.writeUInt32LE(value, offset);
const align = (buffer, size = 16) => {
    const extra = (size - buffer.length % size) % size;
    return extra ? Buffer.concat([buffer, Buffer.alloc(extra)]) : buffer;
};

const headerSize = word(source, 0x08) * 16;
const image = Buffer.from(source.subarray(headerSize));
const relocationCount = word(source, 0x06);
const relocationOffset = word(source, 0x18);
const relocations = [];

for (let i = 0; i < relocationCount; i++) {
    const offset = word(source, relocationOffset + i * 4);
    const segment = word(source, relocationOffset + i * 4 + 2);
    const linear = segment * 16 + offset;
    relocations.push({ linear, source: segment, target: word(image, linear) });
}

/*
 * MAKE sizes and shrinks its single MZ allocation with real-mode segment
 * arithmetic.  Its NE segments are separate blocks, so give its data segment
 * the same 1000h-paragraph cap directly and leave the NE PSP allocation alone.
 */
image.set(Buffer.from([0xbe, 0x00, 0x10]), 0x1672);
image.fill(0x90, 0x1675, 0x1681);
image.fill(0x90, 0x16bf, 0x16c9);

/*
 * MOV SS already inhibits interrupts until after the following instruction.
 * CLI and STI would fault at ring 3, both at startup and when MAKE launches a
 * command, so replace the four pairs around MAKE's stack switches.
 */
for (const offset of [0x1681, 0x1688, 0x49bc, 0x49c1, 0x4b1e, 0x4b23]) {
    image[offset] = 0x90;
}

/*
 * The C run-time's EXEC helper saves five words in its code segment, which is
 * read-only in protected mode.  Move them to the bottom of MAKE's stack and
 * keep the original 2K stack by moving its top up by the same ten bytes.  SS
 * overrides keep the state reachable while EXEC is restoring DS and SS.
 */
putWord(image, 0x1686, 0x1478);
const execState = new Map([
    [0x3d1a, 0x1472],             // saved SS
    [0x3d1f, 0x1470],             // saved SP
    [0x3d4d, 0x1474],             // saved INT 0Bh offset
    [0x3d55, 0x1476],             // saved INT 0Bh segment
    [0x3d5a, 0x1478],             // saved DS
    [0x3d72, 0x1472],
    [0x3d77, 0x1470],
    [0x3d86, 0x1478],
    [0x3d8b, 0x1476],
    [0x3d93, 0x1474]
]);
for (const [offset, state] of execState) {
    image[offset] = 0x36;         // SS override instead of CS
    putWord(image, offset + 3, state);
}

/*
 * The same helper builds EPB_ENVSEG as DS + (offset >> 4), for a copy of the
 * environment in MAKE's data segment, but that sum isn't a selector, and the
 * child faults when it loads it.  MAKE never changes its environment, so pass
 * zero, which makes the child share MAKE's.  All the child loses is the copy's
 * ;C_FILE_INFO entry, which programs that COMMAND runs don't get either.
 */
image.set(Buffer.from([0x33, 0xc0]), 0x3ce8);   // xor ax,ax
image.fill(0x90, 0x3cea, 0x3cf3);

/*
 * Print a protected-mode banner from CS so that the original MZ data and its
 * real-mode banner remain byte-for-byte intact.  The helper replaces MAKE's
 * first fputs call; the following copyright fputs call is unchanged.
 */
const codeEnd = 0x4e10;
const banner = Buffer.from(
    "Microsoft (R) Program Maintenance Utility  Version 4.02BD\r\n",
    "ascii"
);
const bannerWriter = Buffer.from([
    0x1e,                         // push ds
    0x0e, 0x1f,                   // push cs / pop ds
    0xba, 0x00, 0x00,             // mov dx,banner
    0xb9, 0x00, 0x00,             // mov cx,banner.length
    0xbb, 0x01, 0x00,             // mov bx,stdout
    0xb4, 0x40,                   // mov ah,40h
    0xcd, 0x21,                   // int 21h
    0x1f,                         // pop ds
    0xc3                          // ret
]);
putWord(bannerWriter, 4, codeEnd + bannerWriter.length);
putWord(bannerWriter, 7, banner.length);
const codeExtension = Buffer.concat([bannerWriter, banner]);

const relativeCall = (from, to) => {
    const instruction = Buffer.alloc(3);
    instruction[0] = 0xe8;
    instruction.writeInt16LE(to - from - instruction.length, 1);
    return instruction;
};

image.set(relativeCall(0x0018, codeEnd), 0x0018);
image.fill(0x90, 0x001b, 0x0026);

/*
 * MZ relocation frames reveal the components that LINK combined in DGROUP.
 * Its 04E4h frame starts 30h bytes after the 04E1h group base; NE has no
 * groups, so combine both frames in the automatic data segment and adjust the
 * two far-pointer offsets that were relative to the later frame.
 */
const segments = [
    {
        start: 0x0000,
        end: codeEnd,
        size: codeEnd + codeExtension.length,
        data: false,
        extra: codeExtension
    },
    { start: 0x4e10, end: 0x597a, size: 0x0000, data: true }
];
const targets = new Map([
    [0x04e1, 2],
    [0x04e4, 2]
]);
const bySource = Array.from({ length: segments.length }, () => []);

function findSource(relocation) {
    if (relocation.source === 0x0000) {
        return { segment: 1, offset: relocation.linear };
    }
    if (relocation.source === 0x04e4) {
        return { segment: 2, offset: relocation.linear - 0x4e10 };
    }
    throw new Error(
        `no NE source segment for MZ frame ${relocation.source.toString(16)}`
    );
}

for (const relocation of relocations) {
    const sourceLocation = findSource(relocation);
    const target = targets.get(relocation.target);
    if (!target) {
        throw new Error(
            `no NE target for MZ frame ${relocation.target.toString(16)}`
        );
    }
    if (relocation.target === 0x04e4) {
        putWord(image, relocation.linear - 2,
            word(image, relocation.linear - 2) + 0x30);
    }
    bySource[sourceLocation.segment - 1].push({
        offset: sourceLocation.offset,
        target
    });
}

/*
 * Move the MZ relocation table from 001Eh to 0040h.  This makes room for the
 * NE header offset at 003Ch while leaving the real-mode load image unchanged.
 */
let stub = Buffer.from(source);
source.copy(
    stub,
    0x40,
    relocationOffset,
    relocationOffset + relocationCount * 4
);
putWord(stub, 0x18, 0x40);
stub = align(stub);
const neOffset = stub.length;
putDWord(stub, 0x3c, neOffset);

/* Recompute the one's-complement checksum of the declared MZ file. */
putWord(stub, 0x12, 0);
const declaredSize = (word(stub, 0x04) - 1) * 512 +
    (word(stub, 0x02) || 512);
let sum = 0;
for (let i = 0; i < declaredSize; i += 2) {
    sum = (sum + stub[i] + ((stub[i + 1] || 0) << 8)) & 0xffff;
}
putWord(stub, 0x12, (~sum) & 0xffff);

const neHeader = Buffer.alloc(0x40 + segments.length * 8);
putWord(neHeader, 0x00, 0x454e);       // NE signature
putWord(neHeader, 0x02, 0x0500);       // linker version
putWord(neHeader, 0x0c, 0x0008);       // protected mode only
putWord(neHeader, 0x0e, 2);            // automatic data segment
putWord(neHeader, 0x14, 0x166f);       // initial IP
putWord(neHeader, 0x16, 1);            // initial CS segment number
putWord(neHeader, 0x18, 0x0800);       // initial SP
putWord(neHeader, 0x1a, 2);            // initial SS segment number
putWord(neHeader, 0x1c, segments.length);
putWord(neHeader, 0x22, 0x40);         // segment table offset
putWord(neHeader, 0x32, 4);            // 16-byte segment alignment

let output = Buffer.concat([stub, neHeader]);
for (let i = 0; i < segments.length; i++) {
    output = align(output);
    const segment = segments[i];
    const sector = output.length / 16;
    let contents = image.subarray(segment.start, segment.end);
    if (segment.extra) contents = Buffer.concat([contents, segment.extra]);
    output = Buffer.concat([output, contents]);

    const records = bySource[i];
    const flags = (segment.data ? 0x0001 : 0) |
        (records.length ? 0x0100 : 0);
    const entry = neOffset + 0x40 + i * 8;
    putWord(output, entry, sector);
    putWord(output, entry + 2, contents.length);
    putWord(output, entry + 4, flags);
    putWord(output, entry + 6, segment.size);

    if (records.length) {
        const table = Buffer.alloc(2 + records.length * 8);
        putWord(table, 0, records.length);
        for (let j = 0; j < records.length; j++) {
            const record = records[j];
            table[j * 8 + 2] = 2;      // 16-bit selector
            table[j * 8 + 3] = 4;      // additive, one source per record
            putWord(table, j * 8 + 4, record.offset);
            putWord(table, j * 8 + 6, record.target);
        }
        output = Buffer.concat([output, table]);
    }
}

fs.mkdirSync(path.dirname(outputName), { recursive: true });
fs.writeFileSync(outputName, output);
console.log(`${outputName}: ${output.length} bytes`);
