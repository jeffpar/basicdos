#!/usr/bin/env node
/**
 * Convert the LINK4 5.00.12 MZ executable to the restricted NE format that
 * BASIC-DOS loads in protected mode.  The original MZ image remains the
 * real-mode stub, so the result still runs under MS-DOS and real-mode
 * BASIC-DOS.
 */

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const sourceHash =
    "1c5d073d5b1891e87a0c4107190525b1bd156f2285a20ae11faa247313a44748";
const sourceName = process.argv[2] || "software/src/tools/dos/LINK4.EXE";
const outputName = process.argv[3] || "software/src/tools/bd/LINK4.EXE";
const source = fs.readFileSync(sourceName);
const hash = crypto.createHash("sha256").update(source).digest("hex");

if (hash !== sourceHash) {
    throw new Error(`unsupported LINK4.EXE (SHA-256 ${hash})`);
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
const relativeCall = (from, to) => {
    const instruction = Buffer.alloc(3);
    instruction[0] = 0xe8;
    instruction.writeInt16LE(to - from - instruction.length, 1);
    return instruction;
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
 * In real mode, LINK4 uses segments above DGROUP as 512-byte cache pages.
 * Selector arithmetic cannot address those pages in protected mode, so make
 * the cache report no memory pages and use its existing temporary-file path.
 */
const diskCache = Buffer.from([
    0x33, 0xc0,                   // xor ax,ax
    0xa3, 0xa2, 0x21,             // mov [21A2h],ax (memory-page count)
    0xa3, 0xa4, 0x21,             // mov [21A4h],ax (temporary-file handle)
    0x48,                         // dec ax
    0xa3, 0xa6, 0x21,             // mov [21A6h],ax
    0x8b, 0xe5,                   // mov sp,bp
    0x5d,                         // pop bp
    0xc3                          // ret
]);
image.set(diskCache, 0xb715);
image.fill(0x90, 0xb715 + diskCache.length, 0xb73c);

/*
 * Add "BD" to LINK4's buffered banner after its final version component.  The
 * helper also supplies the AX value of the MOV that its call replaces, and it
 * keeps the original MZ banner and data untouched.
 */
const codeEnd = 0xc630;
const bannerSuffix = Buffer.from("BD", "ascii");
const bannerWriter = Buffer.from([
    0xb8, 0x36, 0x22,             // mov ax,bannerSuffix
    0x50,                         // push ax
    0xb8, 0x02, 0x22,             // mov ax,stdout stream
    0x50,                         // push ax
    0xe8, 0x00, 0x00,             // call formatted-output routine
    0x83, 0xc4, 0x04,             // add sp,4
    0xb8, 0x2b, 0x20,             // mov ax,202Bh
    0xc3                          // ret
]);
bannerWriter.writeInt16LE(0xba65 - (codeEnd + 11), 9);

const codeExtension = bannerWriter;

/*
 * LINK4 sizes its MZ allocation with real-mode segment arithmetic.  Install
 * a fixed 64K NE data segment instead, and put its stack at the top.
 */
image.set(Buffer.from([
    0xbb, 0xf0, 0xff              // mov bx,fff0h
]), 0x010b);
image.fill(0x90, 0x010e, 0x0125);

/* MOV SS inhibits interrupts through MOV SP, so these would only fault. */
image[0x0125] = 0x90;
image[0x012a] = 0x90;

image.set(relativeCall(0xa7da, codeEnd), 0xa7da);

const segments = [
    {
        start: 0x0000,
        end: codeEnd,
        size: codeEnd + codeExtension.length,
        data: false,
        extra: codeExtension
    },
    {
        start: 0xc630,
        end: 0xe866,
        size: 0x0000,
        data: true,
        extra: Buffer.concat([bannerSuffix, Buffer.alloc(1)])
    }
];
const bySource = Array.from({ length: segments.length }, () => []);

for (const relocation of relocations) {
    if (relocation.source !== 0 || relocation.target !== 0x0c63) {
        throw new Error(
            `unsupported relocation ${relocation.source.toString(16)}:` +
            `${relocation.linear.toString(16)} -> ` +
            relocation.target.toString(16)
        );
    }
    bySource[0].push({ offset: relocation.linear, target: 2 });
}

/*
 * Move the MZ relocation table from 001Eh to 0040h.  BASIC-DOS uses a table
 * offset of at least 0040h to recognize the NE header pointer at 003Ch.
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
putWord(neHeader, 0x14, 0x0100);       // initial IP
putWord(neHeader, 0x16, 1);            // initial CS segment number
putWord(neHeader, 0x18, 0xfff0);       // initial SP
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
