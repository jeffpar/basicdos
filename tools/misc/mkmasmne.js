#!/usr/bin/env node
/**
 * Convert the MASM 4.00 MZ executable to the restricted NE format that
 * BASIC-DOS loads in protected mode.  The original MZ image remains the
 * real-mode stub, so the result still runs under MS-DOS and real-mode
 * BASIC-DOS.
 */

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const sourceHash =
    "6a32bdafb3a79ad9bfa8bfc92762bd7f450baaca242ef0e1c87951ae83df4c52";
const sourceName = process.argv[2] || "software/src/tools/dos/MASM.EXE";
const outputName = process.argv[3] || "software/src/tools/bd/MASM.EXE";
const source = fs.readFileSync(sourceName);
const hash = crypto.createHash("sha256").update(source).digest("hex");

if (hash !== sourceHash) {
    throw new Error(`unsupported MASM.EXE (SHA-256 ${hash})`);
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
    relocations.push({ linear, target: word(image, linear) });
}

/*
 * MASM sizes and shrinks its single MZ allocation with real-mode segment
 * arithmetic.  Its NE segments are separate blocks, so give its data segment
 * the same 1000h-paragraph cap directly and leave the NE PSP allocation alone.
 */
image.set(Buffer.from([0xbe, 0x00, 0x10]), 0xdd6d);
image.fill(0x90, 0xdd70, 0xdd7c);
image.fill(0x90, 0xddda, 0xdde4);

/*
 * MOV SS already inhibits interrupts until after the following instruction.
 * CLI and STI are therefore unnecessary here, and would fault at ring 3.
 */
image[0xdd7c] = 0x90;
image[0xdd83] = 0x90;

/* Mark the protected-mode image without changing the original MZ banner. */
const bannerOffset = 0x12e80 + 0x0900;
const banner = "Microsoft (R) Macro Assembler  Version 4.00BD\0";
image.write(banner, bannerOffset, "ascii");
putWord(image, 0x08823, 0x0900);

/*
 * MASM's predefined-register table is no longer intact after it sets up its
 * heaps in the segmented NE image.  Restore it before MASM creates the symbols.
 * The helper and its private copy of the table fit in the unused tail of the
 * first 64K code segment.
 */
const codeTail = 0x0fb30;
const registerTable = 0x12e80 + 0x07f0;
const registerTableSize = 0x00b0;
const restoreRegisters = codeTail;
const restoreCodeSize = 26;
const savedRegisterTable = image.subarray(
    registerTable,
    registerTable + registerTableSize
);

const relativeCall = (from, to) => {
    const instruction = Buffer.alloc(3);
    instruction[0] = 0xe8;
    instruction.writeInt16LE(to - from - instruction.length, 1);
    return instruction;
};

image.set(relativeCall(0x08ea2, restoreRegisters), 0x08ea2);
image.fill(0x90, 0x08ea5, 0x08ea7);
const restoreCode = Buffer.from([
    0x06,                         // push es
    0x1e, 0x07,                   // push ds / pop es
    0x0e, 0x1f,                   // push cs / pop ds
    0xbe, 0x00, 0x00,             // mov si,registerTableCopy
    0xbf, 0xf0, 0x07,             // mov di,07F0h
    0xb9, 0x58, 0x00,             // mov cx,0058h
    0xfc, 0xf3, 0xa5,             // cld / rep movsw
    0x06, 0x1f,                   // push es / pop ds
    0x07,                         // pop es
    0xc7, 0x46, 0xf6, 0xf0, 0x07, // mov word [bp-0Ah],07F0h
    0xc3                          // ret
]);
if (restoreCode.length !== restoreCodeSize) throw new Error("bad helper size");
putWord(restoreCode, 6, restoreRegisters + restoreCodeSize);
const codeExtension = Buffer.concat([restoreCode, savedRegisterTable]);

/*
 * MZ relocation frames reveal MASM's logical segments.  Its two code
 * segments overlap by design, as do the end of the second code segment and
 * the beginning of the first data segment.
 */
const segments = [
    {
        start: 0x00000,
        end: 0x0fb30,
        size: codeTail + codeExtension.length,
        data: false,
        extra: codeExtension
    },
    { start: 0x0fb30, end: 0x10543, size: 0x00a13, data: false },
    { start: 0x10540, end: 0x11190, size: 0x00c50, data: true },
    { start: 0x11190, end: 0x12a20, size: 0x01890, data: true },
    { start: 0x12a20, end: 0x12e80, size: 0x00460, data: true },
    { start: 0x12e80, end: 0x1463e, size: 0x00000, data: true }
];
const targets = new Map([
    [0x0fb3, 2],
    [0x1054, 3],
    [0x1119, 4],
    [0x12a2, 5],
    [0x12e8, 6]
]);
const bySource = Array.from({ length: segments.length }, () => []);

function findSource(linear) {
    if (linear < 0x10000) return { segment: 1, offset: linear };
    if (linear >= 0x10540 && linear < 0x11190) {
        return { segment: 3, offset: linear - 0x10540 };
    }
    if (linear >= 0x11190 && linear < 0x12a20) {
        return { segment: 4, offset: linear - 0x11190 };
    }
    if (linear >= 0x12e80 && linear < 0x1463e) {
        return { segment: 6, offset: linear - 0x12e80 };
    }
    throw new Error(`no NE source segment for relocation ${linear.toString(16)}`);
}

for (const relocation of relocations) {
    const sourceLocation = findSource(relocation.linear);
    const target = targets.get(relocation.target);
    if (!target) {
        throw new Error(
            `no NE target for MZ frame ${relocation.target.toString(16)}`
        );
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
putWord(neHeader, 0x0e, 6);            // automatic data segment
putWord(neHeader, 0x14, 0xdd6a);       // initial IP
putWord(neHeader, 0x16, 1);            // initial CS segment number
putWord(neHeader, 0x18, 0x0800);       // initial SP
putWord(neHeader, 0x1a, 6);            // initial SS segment number
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
