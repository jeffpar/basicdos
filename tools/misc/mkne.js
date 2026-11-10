#!/usr/bin/env node
/**
 * Converts the MZ tools in software/src/tools/dos to NE executables in
 * software/src/tools/bd.  BASIC-DOS loads the NE image, a restricted form of
 * NE, in protected mode, and in real mode, NESTUB.BIN (see
 * software/src/tools/nestub.asm), an NE loader that replaces the MZ image, does
 * the same, so one image runs in either mode, including under other versions of
 * DOS.  All of a program's patches must therefore be safe in real mode, using
 * only 8086 instructions, since these tools run on an 8088, too.
 *
 * Usage: node tools/misc/mkne.js
 *
 * To convert another program, add a section to PROGRAMS (see the end of this
 * file): its name, its MZ file's SHA-256 (since all its patches are specific to
 * that file), and a function that patches the NE copy of its image and returns
 * its segments, its relocations' frames, and its initial registers.
 *
 * These are the problems to look for in another program:
 *
 *   - Segment arithmetic, which is invalid with selectors.  The usual suspects
 *     are memory sizing at startup, the end of memory at PSP:0002h, and
 *     EPB_ENVSEG (see MAKE).
 *   - CLI and STI, which fault at ring 3.  They usually surround a stack switch,
 *     where they're unnecessary, because MOV SS inhibits interrupts.
 *   - Writes through CS, since code segments are read-only.
 *   - A return to PSP:0000h, which isn't code in protected mode (see LINK).
 *   - The initial SP, which BASIC-DOS uses to build the program's first register
 *     frame.  An MZ program's SP is relative to its own stack segment, so an NE
 *     program that puts its stack in DGROUP needs a new SP (see patchStartup).
 *
 * A banner ending in "BD" identifies each conversion.
 *
 * To add the NE loader to any NE program (eg, one that LINK4 built, whose stub it
 * then replaces):
 *
 *      node tools/misc/mkne.js --stub in.exe out.exe
 */

import crypto from "node:crypto";
import fs from "node:fs";

const TOOLS = new URL("../../software/src/tools/", import.meta.url);

const word = (buffer, offset) => buffer.readUInt16LE(offset);
const hex = value => value.toString(16);
const hexWord = value => {
    const buffer = Buffer.alloc(2);
    buffer.writeUInt16LE(value & 0xffff);
    return buffer.toString("hex");
};

/**
 * Converts hex text, which can contain spaces and // comments, to bytes.
 */
const bytes = text => Buffer.from(
    text.replace(/\/\/.*/g, "").replace(/\s/g, ""), "hex");

/**
 * Replaces the original bytes at offset (hex text, so a wrong offset fails here
 * rather than at run time), filling any remainder with NOPs.
 */
function patch(image, offset, original, replacement = "") {
    const before = bytes(original);
    const after = bytes(replacement);
    if (after.length > before.length) {
        throw new Error(`patch at ${hex(offset)} is too long`);
    }
    if (!image.subarray(offset, offset + before.length).equals(before)) {
        throw new Error(`unexpected bytes at ${hex(offset)}`);
    }
    image.fill(0x90, offset, offset + before.length);
    after.copy(image, offset);
}

/**
 * Returns the bytes of a near call from one image offset to another.
 */
const nearCall = (from, to) => `e8 ${hexWord(to - (from + 3))}`;

/**
 * Patches the startup code that the Microsoft C run-time uses, in the NE image.
 *
 * Its code sizes DGROUP and shrinks the MZ allocation with real-mode segment
 * arithmetic.  NE segments are separate blocks, so give DGROUP the same
 * 1000h-paragraph cap directly, and leave the PSP's allocation alone.  Replace
 * the CLI and STI around its stack switch.
 *
 * It also adds the MZ header's SP, which is relative to a separate stack segment,
 * to the offset of that segment in DGROUP.  BASIC-DOS builds the program's first
 * register frame below its initial SP, so starting at the MZ SP would overwrite
 * initialized data, which is why we start at the final SP and add nothing to it.
 *
 * start is the offset of the code's MOV SI,[2], shrink is the offset of its ADD
 * SI,DI, and sp is the MZ header's SP.  Returns the initial SP, including any
 * extra room for the caller's use at the bottom of the stack.
 */
function patchStartup(image, start, shrink, sp, extra = 0) {
    patch(image, start, "8b360200 2bf7 81fe0010 7203 be0010", "be0010");
    patch(image, start + 0x0f, "fa");
    const stack = word(image, start + 0x14);
    patch(image, start + 0x12, `81c4 ${hexWord(stack)}`, "81c4 0000");
    patch(image, start + 0x16, "fb");
    patch(image, shrink, "03f7 89360200 8cc3 2bde f7db b44a cd21");
    return sp + stack + extra;
}

/**
 * Returns an EXEPACKed MZ image's original image, relocations, and registers.
 */
function unpackExepack(source, image) {
    const base = word(source, 0x16) * 16;
    const [ip, cs, , , sp, ss, paragraphs, signature] = Array.from(
        { length: 8 }, (_, i) => word(image, base + i * 2));
    if (signature !== 0x4252) {
        throw new Error("EXEPACK signature not found");
    }
    const output = Buffer.alloc(paragraphs * 16);
    let from = base - 1, to = output.length;
    while (image[from] === 0xff) from--;
    for (let last = false; !last; ) {
        const op = image[from];
        const count = image[from - 1] * 256 + image[from - 2];
        from -= 3;
        last = !!(op & 1);
        if ((op & 0xfe) === 0xb0) {
            output.fill(image[from--], to - count, to);
            to -= count;
        } else if ((op & 0xfe) === 0xb2) {
            for (let i = 0; i < count; i++) output[--to] = image[from--];
        } else {
            throw new Error(`bad EXEPACK opcode ${hex(op)}`);
        }
    }
    image.copy(output, 0, 0, from + 1);

    /* After the stub's message: 16 lists of offsets, one per 64K frame. */
    const relocations = [];
    let table = image.indexOf("Packed file is corrupt") + 22;
    for (let frame = 0; frame < 16; frame++) {
        const count = word(image, table);
        table += 2;
        for (let i = 0; i < count; i++, table += 2) {
            relocations.push(relocationAt(output, frame * 0x1000,
                word(image, table)));
        }
    }
    return { image: output, relocations, ip, cs, sp, ss };
}

function relocationAt(image, segment, offset) {
    const linear = segment * 16 + offset;
    return { linear, target: word(image, linear) };
}

/**
 * Reads the MZ executable, which must have the given SHA-256, and returns it,
 * along with a copy of its load image (for the NE segments, so that patches
 * never touch the MZ stub) and its relocations, where linear is an image offset
 * and target is the segment value there.
 */
function loadMZ(name, sourceHash) {
    const source = fs.readFileSync(new URL(`dos/${name}.EXE`, TOOLS));
    const hash = crypto.createHash("sha256").update(source).digest("hex");
    if (hash !== sourceHash) {
        throw new Error(`unsupported ${name}.EXE (SHA-256 ${hash})`);
    }
    const image = Buffer.from(source.subarray(word(source, 0x08) * 16));
    const relocations = [];
    for (let i = 0; i < word(source, 0x06); i++) {
        const entry = word(source, 0x18) + i * 4;
        relocations.push(relocationAt(image, word(source, entry + 2),
            word(source, entry)));
    }
    return { source, image, relocations };
}

/**
 * Writes the NE executable, with the NE loader stub.  Each segment is { start, end, data, size,
 * extra }: its contents are image bytes start through end, followed by extra,
 * if any; size is its size in memory (0 means 64K; its contents' length if
 * omitted).  Every relocation applies to the segments containing it, and frames
 * maps each target value to a one-based segment number.
 */
function writeNE(name, { image, relocations, frames, segments, autoData,
    ip, cs, sp, ss }) {
    const bySegment = segments.map(() => []);
    for (const { linear, target } of relocations) {
        if (!frames.has(target)) {
            throw new Error(`no NE segment for MZ frame ${hex(target)}`);
        }
        const inSegments = segments.filter(segment =>
            linear >= segment.start && linear + 2 <= segment.end);
        if (!inSegments.length) {
            throw new Error(`no NE segment contains ${hex(linear)}`);
        }
        for (const segment of inSegments) {
            bySegment[segments.indexOf(segment)].push({
                offset: linear - segment.start,
                target: frames.get(target)
            });
        }
    }

    /*
     * Start with an empty stub, which stubNE replaces, and the NE header at 0040h.
     */
    const align = buffer => Buffer.concat(
        [buffer, Buffer.alloc((16 - buffer.length % 16) % 16)]);
    const stub = Buffer.alloc(0x40);
    const neOffset = stub.length;
    stub.writeUInt32LE(neOffset, 0x3c);

    const neHeader = Buffer.alloc(0x40 + segments.length * 8);
    neHeader.writeUInt16LE(0x454e, 0x00);       // NE signature
    neHeader.writeUInt16LE(0x0500, 0x02);       // linker version
    neHeader.writeUInt16LE(0x0008, 0x0c);       // protected mode only
    neHeader.writeUInt16LE(autoData, 0x0e);     // automatic data segment
    neHeader.writeUInt16LE(ip, 0x14);
    neHeader.writeUInt16LE(cs, 0x16);
    neHeader.writeUInt16LE(sp, 0x18);
    neHeader.writeUInt16LE(ss, 0x1a);
    neHeader.writeUInt16LE(segments.length, 0x1c);
    neHeader.writeUInt16LE(0x40, 0x22);         // segment table offset
    neHeader.writeUInt16LE(4, 0x32);            // 16-byte segment alignment

    let output = Buffer.concat([stub, neHeader]);
    segments.forEach((segment, i) => {
        output = align(output);
        const contents = Buffer.concat([
            image.subarray(segment.start, segment.end),
            segment.extra || Buffer.alloc(0)
        ]);
        const records = bySegment[i];
        const entry = neOffset + 0x40 + i * 8;
        output.writeUInt16LE(contents.length ? output.length / 16 : 0, entry);
        output.writeUInt16LE(contents.length, entry + 2);
        output.writeUInt16LE((segment.data ? 0x0001 : 0) |
            (records.length ? 0x0100 : 0), entry + 4);
        output.writeUInt16LE(segment.size ?? contents.length, entry + 6);
        output = Buffer.concat([output, contents]);
        if (records.length) {
            const list = Buffer.alloc(2 + records.length * 8);
            list.writeUInt16LE(records.length, 0);
            records.forEach((record, j) => {
                list[j * 8 + 2] = 2;            // 16-bit selector
                list[j * 8 + 3] = 4;            // additive, so no chain
                list.writeUInt16LE(record.offset, j * 8 + 4);
                list.writeUInt16LE(record.target, j * 8 + 6);
            });
            output = Buffer.concat([output, list]);
        }
    });

    output = stubNE(output, readStub());
    fs.mkdirSync(new URL("bd/", TOOLS), { recursive: true });
    fs.writeFileSync(new URL(`bd/${name}.EXE`, TOOLS), output);
    console.log(`${name}.EXE: ${output.length} bytes`);
}

/**
 * Returns a copy of an NE file with its stub replaced by the NE loader stub.
 *
 * The new MZ header has a header size of zero, so DOS loads the entire file, and
 * a file offset is an image offset.  Its minimum allocation covers what the stub
 * will need (it must agree with the stub's first step), plus its stack.  A stub
 * of a different size moves the rest of the file, by a multiple of the file's
 * alignment, so the NE header's file offsets must be adjusted, too.
 */
function stubNE(file, stub) {
    const STUB_STACK = 0x20;                    // paragraphs
    const offsetNE = file.readUInt32LE(0x3c);
    const header = file.subarray(offsetNE);
    if (word(header, 0) !== 0x454e) {
        throw new Error("no NE header");
    }
    const shift = word(header, 0x32) || 9;
    if (shift < 4) {
        throw new Error(`unsupported alignment shift ${shift}`);
    }
    const prefix = (0x40 + stub.length + 15) & ~15;
    const delta = Math.floor((offsetNE - prefix) / (1 << shift)) * (1 << shift);
    const newNE = offsetNE - delta;
    const output = Buffer.alloc(newNE + header.length);
    header.copy(output, newNE);
    stub.copy(output, 0x40);
    const entryNE = newNE + word(header, 0x22);
    const count = word(header, 0x1c);
    const autoData = word(header, 0x0e);
    const nonresident = header.readUInt32LE(0x2c);
    if (nonresident) {
        output.writeUInt32LE(nonresident - delta, newNE + 0x2c);
    }
    output.writeUInt32LE(0, newNE + 0x08);      // the file's CRC is now wrong
    let next = (entryNE + count * 8 + 15) >> 4;
    for (let i = 0; i < count; i++) {
        const entry = entryNE + i * 8;
        const sector = word(output, entry);
        let start = next;
        if (sector) {
            const moved = sector - delta / (1 << shift);
            output.writeUInt16LE(moved, entry);
            start = Math.max(next, moved << (shift - 4));
        }
        let size = word(output, entry + 6) || 0x10000;
        if (i + 1 === autoData) {
            size += word(header, 0x10) + word(header, 0x12);
        }
        next = start + ((size + 15) >> 4);
    }
    const image = (output.length + 15) >> 4;
    const stack = Math.max(next, image);
    const mz = output.subarray(0, 0x40);
    mz.writeUInt16LE(0x5a4d, 0x00);
    mz.writeUInt16LE(output.length % 512, 0x02);
    mz.writeUInt16LE((output.length + 511) >> 9, 0x04);
    mz.writeUInt16LE(stack + STUB_STACK - image, 0x0a);     // minimum
    mz.writeUInt16LE(stack + STUB_STACK - image, 0x0c);     // maximum
    mz.writeUInt16LE(stack, 0x0e);                          // SS
    mz.writeUInt16LE(STUB_STACK << 4, 0x10);                // SP
    mz.writeUInt16LE(0x40, 0x14);                           // IP
    mz.writeUInt16LE(0x40, 0x18);                           // relocation table
    mz.writeUInt32LE(newNE, 0x3c);
    return output;
}

const readStub = () => fs.readFileSync(new URL("NESTUB.BIN", TOOLS));

const PROGRAMS = [

    /*
     * MASM 4.00
     */
    {
        name: "MASM",
        hash: "6a32bdafb3a79ad9bfa8bfc92762bd7f450baaca242ef0e1c87951ae83df4c52",
        convert({ source, image }) {
            const sp = patchStartup(image, 0xdd6d, 0xddd4, word(source, 0x10));

            /*
             * Use a copy of the banner with room for "BD", in unused zeros.
             */
            image.write("Microsoft (R) Macro Assembler  Version 4.00BD\0",
                0x12e80 + 0x0900, "ascii");
            patch(image, 0x8822, "b81406", "b80009");

            /*
             * MZ relocation frames reveal MASM's logical segments.  Its two code
             * segments overlap by design, as do the end of the second code
             * segment and the beginning of the first data segment.
             */
            return {
                frames: new Map([
                    [0x0fb3, 2], [0x1054, 3], [0x1119, 4], [0x12a2, 5],
                    [0x12e8, 6]
                ]),
                segments: [
                    { start: 0x00000, end: 0x0fb30 },
                    { start: 0x0fb30, end: 0x10543, size: 0x00a13 },
                    { start: 0x10540, end: 0x11190, data: true },
                    { start: 0x11190, end: 0x12a20, data: true },
                    { start: 0x12a20, end: 0x12e80, data: true },
                    { start: 0x12e80, end: 0x1463e, size: 0, data: true }
                ],
                autoData: 6,
                ip: 0xdd6a,
                cs: 1,
                sp,
                ss: 6
            };
        }
    },

    /*
     * MAKE 4.02
     */
    {
        name: "MAKE",
        hash: "04bf03c0c2521ed5c7958c4fc46c2cbcf3ee5a5a2d6c232efb7a42e3afd9c6af",
        convert({ source, image, relocations }) {

            /*
             * The C run-time's EXEC helper saves five words in its code segment,
             * which is read-only in protected mode.  Move them to the bottom of
             * MAKE's stack (see stackState) and keep the original 2K stack by
             * moving its top up by the same ten bytes.  SS overrides keep the
             * state reachable while EXEC is restoring DS and SS.
             */
            const stackState = 0x1470;
            const sp = patchStartup(image, 0x1672, 0x16b9, word(source, 0x10),
                10);
            const execState = new Map([
                [0x3d1a, 2],            // saved SS
                [0x3d1f, 0],            // saved SP
                [0x3d4d, 4],            // saved INT 0Bh offset
                [0x3d55, 6],            // saved INT 0Bh segment
                [0x3d5a, 8],            // saved DS
                [0x3d72, 2],
                [0x3d77, 0],
                [0x3d86, 8],
                [0x3d8b, 6],
                [0x3d93, 4]
            ]);
            for (const [offset, state] of execState) {
                patch(image, offset, "2e", "36");
                image.writeUInt16LE(stackState + state, offset + 3);
            }

            /* Replace the CLI and STI around the stack switches for a command. */
            for (const offset of [0x49bc, 0x4b1e]) {
                patch(image, offset, "fa");
                patch(image, offset + 5, "fb");
            }

            /*
             * The same helper builds EPB_ENVSEG as DS + (offset >> 4), for a copy
             * of the environment in MAKE's data segment, but that sum isn't a
             * selector, and the child faults when it loads it.  MAKE never changes
             * its environment, so pass zero, which makes the child share MAKE's.
             * All the child loses is the copy's ;C_FILE_INFO entry, which programs
             * that COMMAND runs don't get either.
             */
            patch(image, 0x3ce8, "8cd8 8b5e0a b104 d3eb 03c3", "33c0");

            /*
             * Print a protected-mode banner from CS, in a helper that replaces
             * MAKE's first fputs call; the copyright fputs call is unchanged.
             */
            const codeEnd = 0x4e10;
            const banner = Buffer.from(
                "Microsoft (R) Program Maintenance Utility  Version 4.02BD\r\n",
                "ascii");
            const writer = bytes(`
                1e                      // push ds
                0e 1f                   // push cs / pop ds
                ba ${hexWord(codeEnd + 18)}     // mov dx,banner
                b9 ${hexWord(banner.length)}    // mov cx,banner.length
                bb 0100                 // mov bx,stdout
                b4 40                   // mov ah,40h
                cd 21                   // int 21h
                1f                      // pop ds
                c3                      // ret
            `);
            patch(image, 0x0018, "b8ba04 50 b84800 50 e8231a 83c404",
                nearCall(0x0018, codeEnd));

            /*
             * MZ relocation frames reveal the components that LINK combined in
             * DGROUP.  Its 04E4h frame starts 30h bytes after the 04E1h group base;
             * NE has no groups, so combine both frames in the automatic data
             * segment and adjust the two far-pointer offsets that were relative to
             * the later frame.
             */
            for (const { linear, target } of relocations) {
                if (target === 0x04e4) {
                    image.writeUInt16LE(word(image, linear - 2) + 0x30,
                        linear - 2);
                }
            }
            return {
                frames: new Map([[0x04e1, 2], [0x04e4, 2]]),
                segments: [
                    { start: 0, end: codeEnd,
                      extra: Buffer.concat([writer, banner]) },
                    { start: codeEnd, end: 0x597a, size: 0, data: true }
                ],
                autoData: 2,
                ip: 0x166f,
                cs: 1,
                sp,
                ss: 2
            };
        }
    },

    /*
     * LINK4 5.00.12
     */
    {
        name: "LINK4",
        hash: "1c5d073d5b1891e87a0c4107190525b1bd156f2285a20ae11faa247313a44748",
        convert({ image }) {

            /*
             * In real mode, LINK4 uses segments above DGROUP as 512-byte cache
             * pages.  Selector arithmetic cannot address those pages in protected
             * mode, so make the cache report no memory pages and use its existing
             * temporary-file path.
             */
            patch(image, 0xb715, `
                8b1e9600 1e 58 050010 a3a021 2bd8 7702 33db b90500 d3eb 891ea221
                33c0 a3a421 f7d0 a3a621 5d c3
            `, `
                33c0                    // xor ax,ax
                a3a221                  // mov [21A2h],ax (memory-page count)
                a3a421                  // mov [21A4h],ax (temporary-file handle)
                48                      // dec ax
                a3a621                  // mov [21A6h],ax
                8be5                    // mov sp,bp
                5d                      // pop bp
                c3                      // ret
            `);

            /*
             * LINK4 sizes its MZ allocation with real-mode segment arithmetic.
             * Install a fixed 64K NE data segment instead, and put its stack at
             * the top.  MOV SS inhibits interrupts through MOV SP, so the CLI and
             * STI would only fault.
             */
            patch(image, 0x010b,
                "268b1e0200 891e9600 2bd8 f7c300f0 7506 b104 d3e3 eb03 bbf0ff",
                "bbf0ff");
            patch(image, 0x0125, "fa");
            patch(image, 0x012a, "fb");

            /*
             * Add "BD" to LINK4's buffered banner after its final version
             * component.  The helper also supplies the AX value of the MOV that
             * its call replaces.
             */
            const codeEnd = 0xc630;
            const dataEnd = 0xe866;
            const writer = bytes(`
                b8 3622                 // mov ax,suffix
                50                      // push ax
                b8 0222                 // mov ax,stdout stream
                50                      // push ax
                e8 ${hexWord(0xba65 - (codeEnd + 11))}  // formatted output
                83c404                  // add sp,4
                b8 2b20                 // mov ax,202Bh
                c3                      // ret
            `);
            patch(image, 0xa7da, "b82b20", nearCall(0xa7da, codeEnd));
            return {
                frames: new Map([[0x0c63, 2]]),
                segments: [
                    { start: 0, end: codeEnd, extra: writer },
                    { start: codeEnd, end: dataEnd, size: 0, data: true,
                      extra: Buffer.from("BD\0", "ascii") }
                ],
                autoData: 2,
                ip: 0x0100,
                cs: 1,
                sp: 0xfff0,
                ss: 2
            };
        }
    },

    /*
     * LINK 3.05
     */
    {
        name: "LINK",
        hash: "8bd6d1144ee8acf4dc13a48e46070c642e962bb3822edacbe5a76a95e7a692b1",
        convert({ image }) {

            /*
             * LINK sizes its MZ allocation with real-mode segment arithmetic.
             * Install a fixed 64K NE data segment instead, and put its stack at
             * the top.  MOV SS inhibits interrupts through MOV SP, so the CLI and
             * STI would only fault.
             *
             * LINK also reads the word at 5ECEh, the last map file segment, before
             * setting it, and NE segments start zeroed.  Every real-mode run has
             * found a nonzero value there, which adds a blank line before a
             * warning in the map file, so start with a value that isn't a segment,
             * to produce the same map file.
             *
             * LINK's early exits return to PSP:0000h, but the PSP's selector isn't
             * code in protected mode, so instead of PUSH ES, XOR AX,AX, and PUSH
             * AX, it pushes the address of an INT 21h exit at the end of the code
             * segment.
             */
            const codeEnd = 0x9670;
            const dataEnd = 0xa9d4;
            patch(image, 0x012b, `
                268b1e0200 891e7601 2bd8 f7c300f0 7506 b104 d3e3 eb03 bbf0ff
                fa 8ed2 8be3 fb 891e7001 06 33c0 50
            `, `
                bbf0ff                  // mov bx,0fff0h
                c706ce5effff            // mov word ptr [5ECEh],-1
                8ed2                    // mov ss,dx
                8be3                    // mov sp,bx
                891e7001                // mov [170h],bx
                0e                      // push cs
                b8 ${hexWord(codeEnd)}  // mov ax,exit
                50                      // push ax
            `);

            /*
             * LINK's virtual memory keeps 512-byte pages in memory above DGROUP,
             * and in VM.TMP after that, addressing each page as base + page * 20h.
             * Selector arithmetic can't do that, so put the first 128 pages in one
             * 64K block, which the page read and write routines address as
             * selector:(page * 200h).  If the block isn't available, the page count
             * is zero, so VM.TMP gets all the pages.
             */
            patch(image, 0x8a40,
                "8b1e7601 1e 58 050010 a31013 2bd8 7702 33db b90500 d3eb 891e1213",
                `
                bb0010                  // mov bx,1000h
                b448 cd21               // DOS_MEM_ALLOC
                a31013                  // mov [1310h],ax
                bb8000                  // mov bx,128
                7302                    // jnc $+4
                33db                    // xor bx,bx
                891e1213                // mov [1312h],bx
            `);
            patch(image, 0x8930, "b90500 d3e0 03061013 8cd9 8ec1 8ed8 33f6", `
                b109                    // mov cl,9
                d3e0                    // shl ax,cl
                96                      // xchg si,ax
                8cd9 8ec1               // mov cx,ds / mov es,cx
                8e1e1013                // mov ds,[1310h]
            `);
            patch(image, 0x89b7, "b90500 d3e0 03061013 8ec0 33ff", `
                b109                    // mov cl,9
                d3e0                    // shl ax,cl
                97                      // xchg di,ax
                8e061013                // mov es,[1310h]
            `);

            /*
             * Add "BD" to the NE segment's copy of the banner, which is one string
             * that's followed by unused zeros.
             */
            const banner = image.indexOf("Version 3.05", codeEnd) + 12;
            const bannerEnd = image.indexOf("reserved.\r\n\0", banner) + 12;
            image.copy(image, banner + 2, banner, bannerEnd);
            image.write("BD", banner, "ascii");

            return {
                frames: new Map([[0x0967, 2]]),
                segments: [
                    { start: 0, end: codeEnd, extra: bytes("b8004c cd21") },
                    { start: codeEnd, end: dataEnd, size: 0, data: true }
                ],
                autoData: 2,
                ip: 0x0120,
                cs: 1,
                sp: 0xfff0,
                ss: 2
            };
        }
    },

    /*
     * EXEMOD 4.00
     */
    {
        name: "EXEMOD",
        hash: "8c82a085b20b5faef9947438697d26f1201b8aae44460e733bb506732b1ed20f",
        convert({ source, image }) {
            const sp = patchStartup(image, 0x079a, 0x0805, word(source, 0x10));

            /*
             * An unused SCCS string precedes the NE segment's copy of the banner,
             * so move the banner down over the end of that string, which makes room
             * for "BD", and adjust the one reference to it.
             */
            const codeEnd = 0x20a0;
            const banner = image.indexOf("Microsoft (R) EXE", codeEnd);
            if (banner - codeEnd !== 0x5b) {
                throw new Error("unexpected banner offset");
            }
            image.write("Microsoft (R) EXE File Header Utility  Version 4.00BD",
                banner - 2, "ascii");
            patch(image, 0x001c, "b85b00", "b85900");

            return {
                frames: new Map([[0x020a, 2]]),
                segments: [
                    { start: 0, end: codeEnd },
                    { start: codeEnd, end: 0x291a, size: 0, data: true }
                ],
                autoData: 2,
                ip: 0x0797,
                cs: 1,
                sp,
                ss: 2
            };
        }
    },

    /*
     * MAPSYM 4.00
     *
     * The MZ image is EXEPACKed, so the NE segments come from its unpacked image.
     */
    {
        name: "MAPSYM",
        hash: "fbc2a5f04b944de86011fd3161ef28e88c4b1462d3358d75eeef56f98b9694e6",
        convert({ source, image: packed }) {
            const unpacked = unpackExepack(source, packed);
            const { image, relocations } = unpacked;

            /* Its C run-time is in the code segment at frame 01A0h. */
            const sp = patchStartup(image, 0x1a38, 0x1a9f, unpacked.sp);

            /*
             * This is a large-model program, whose code is in many segments, and
             * the near jumps and tables in each are relative to its frame, so each
             * frame that a relocation names stays a separate NE segment, with the
             * same offsets.  A frame's code can extend into the next frame's first
             * paragraph (a frame is its segment's start rounded down), hence the
             * extra 16 bytes in each.
             *
             * Two frames aren't code: 03BAh is a zero-filled far data segment, and
             * 12A0h is DGROUP.
             */
            const farData = 0x03ba, dgroup = 0x12a0;
            const codeFrames = [...new Set(relocations.map(r => r.target))]
                .filter(frame => frame < farData)
                .sort((a, b) => a - b);
            const segments = codeFrames.map((frame, i) => ({
                start: frame * 16,
                end: Math.min((codeFrames[i + 1] ?? farData) * 16 + 16,
                    farData * 16)
            }));

            /*
             * Put the banner in the first code segment, instead of DGROUP, which
             * has no room for "BD".  PRINTF takes a far pointer, so PUSH CS comes
             * first, and it's the MOV that gets the banner's new offset.
             */
            segments[0].extra = Buffer.from(
                "Microsoft (R) Symbol File Generator  Version 4.00BD\n\0",
                "ascii");
            patch(image, 0x153a, "b87915 1e 50",
                `0e b8 ${hexWord(segments[0].end)} 50`);

            segments.push(
                { start: farData * 16, end: farData * 16,
                  size: (dgroup - farData) * 16, data: true },
                { start: dgroup * 16, end: image.length, size: 0, data: true }
            );
            const frames = new Map(codeFrames.map((frame, i) => [frame, i + 1]));
            frames.set(farData, codeFrames.length + 1);
            frames.set(dgroup, codeFrames.length + 2);

            return {
                image,
                relocations,
                frames,
                segments,
                autoData: frames.get(dgroup),
                ip: unpacked.ip,
                cs: frames.get(unpacked.cs),
                sp,
                ss: frames.get(dgroup)
            };
        }
    },

    /*
     * MASM 5.10B (Windows 3.1 DDK)
     *
     * The MZ image is EXEPACKed, and it's a large-model C program with the same
     * C run-time as MAPSYM.
     */
    {
        name: "MASM5",
        hash: "e8a09ca1b6f5c42162ac44f6278e715490e257720f5f8a3849f999d8cc2ffc3d",
        convert({ source, image: packed }) {
            const unpacked = unpackExepack(source, packed);
            const { image, relocations } = unpacked;
            const sp = patchStartup(image, 0x12319, 0x1235e, unpacked.sp);

            /*
             * The banner (in the listing header, too) is the SCCS string less its
             * last 20 characters (the date), so "BD" replaces the space before it.
             */
            patch(image, 0x1b15f, "422041", "424441");

            /*
             * Each frame that a relocation names stays a separate NE segment,
             * with the same offsets, extended by the next frame's first paragraph
             * (see MAPSYM).  Frames 1640h through 19BDh are far data, and 1A2Eh
             * is DGROUP.
             */
            const dgroup = 0x1a2e;
            const frames = [...new Set(relocations.map(r => r.target))]
                .sort((a, b) => a - b);
            const segments = frames.map((frame, i) => ({
                start: frame * 16,
                end: frame === dgroup ? image.length :
                    Math.min(frames[i + 1] * 16 + 16, dgroup * 16),
                data: frame >= 0x1640
            }));
            segments[segments.length - 1].size = 0;
            return {
                image,
                relocations,
                frames: new Map(frames.map((frame, i) => [frame, i + 1])),
                segments,
                autoData: frames.length,
                ip: unpacked.ip,
                cs: frames.indexOf(unpacked.cs) + 1,
                sp,
                ss: frames.length
            };
        }
    },

    /*
     * EXE2BIN (MS-DOS 3.20)
     */
    {
        name: "EXE2BIN",
        hash: "3bce593d0d4f015677515c9a0adcc9ab9a66cfbb89641cff7e97843228adf77a",
        convert({ image }) {

            /*
             * EXE2BIN insists on DOS 3.20 exactly, which BASIC-DOS accommodates by
             * recognizing its version check (see DOS_MSC_GETVER).  That's
             * unnecessary here, so always take the branch for the right version.
             */
            patch(image, 0x000d, "7411", "eb11");

            /*
             * The program's file buffer becomes its own 64K NE segment, so there's
             * no need to compare the end of the program (a selector plus a size)
             * with the end of memory.  The buffer can't overflow, because EXE2BIN
             * rejects a larger program.
             */
            patch(image, 0x021e, "03d5 3bd3 7783");

            /*
             * A fixup's segment is relative to the buffer, which is one selector,
             * so add it to the offset, in a helper at the end of the code segment.
             * CX is still 4, from reading the fixup.
             */
            const codeEnd = 0x03a0;
            const fixup = bytes(`
                8b3e4201                // mov di,[142h]
                a14401                  // mov ax,[144h]
                d3e0                    // shl ax,cl
                03f8                    // add di,ax
                8ec3                    // mov es,bx
                c3                      // ret
            `);
            patch(image, 0x030b, "8b3e4201 a14401 03c3 8ec0",
                nearCall(0x030b, codeEnd));

            /*
             * EXE2BIN ends by returning to PSP:0000h, but the PSP's selector isn't
             * code in protected mode, so it starts in a helper instead of with its
             * PUSH DS, XOR AX,AX, and PUSH AX, to return to an INT 21h exit.
             */
            const exit = codeEnd + fixup.length;
            const start = exit + 5;

            /*
             * The print routines keep their state in their code segment (offsets
             * 0Ah through 47h), which is read-only in protected mode.  Put a copy
             * at the same offsets of the stack segment, below the stack, and make
             * them use SS instead of CS.
             */
            const printStart = 0x0770;
            const printData = 0x48;
            for (const offset of [
                0x07ed, 0x07f2, 0x07f8, 0x07fd, 0x0829, 0x0831, 0x083b, 0x0840,
                0x0849, 0x0850, 0x0857, 0x0882, 0x0888, 0x0892, 0x089c, 0x08ab,
                0x08bd, 0x08c6, 0x08df, 0x08e7, 0x0916, 0x092c, 0x0931, 0x0960,
                0x0971, 0x0979, 0x0990, 0x09a8, 0x09cf, 0x09d3, 0x09d7, 0x09db,
                0x09df, 0x09e5
            ]) {
                patch(image, offset, "2e", "36");
            }
            for (const offset of [0x07c2, 0x0982, 0x09ae]) {
                patch(image, offset, "0e", "16");
            }

            const stack = 0x016a;
            return {
                frames: new Map([[0x0039, 2], [0x0077, 4], [0x009f, 5]]),
                segments: [
                    { start: 0, end: codeEnd,
                      extra: Buffer.concat([fixup, bytes(`
                        b8004c cd21             // exit: mov ax,4C00h; int 21h
                        0e                      // start: push cs
                        b8 ${hexWord(exit)}     // mov ax,exit
                        50                      // push ax
                        33c0                    // xor ax,ax
                        e9 ${hexWord(4 - (start + 10))}
                      `)]) },
                    { start: 0x0390, end: 0x0610, data: true },
                    { start: printStart, end: printStart + printData,
                      size: printData + stack, data: true },
                    { start: printStart, end: image.length },
                    { start: 0, end: 0, size: 0, data: true }
                ],
                autoData: 2,
                ip: start,
                cs: 1,
                sp: printData + stack,
                ss: 3
            };
        }
    }
];

if (process.argv[2] === "--stub") {
    const [input, output] = process.argv.slice(3);
    const result = stubNE(fs.readFileSync(input), readStub());
    fs.writeFileSync(output, result);
    console.log(`${output}: ${result.length} bytes`);
} else {
    for (const { name, hash, convert } of PROGRAMS) {
        const mz = loadMZ(name, hash);
        writeNE(name, { ...mz, ...convert(mz) });
    }
}
