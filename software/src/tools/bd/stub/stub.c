/*
 * BASIC-DOS NE Loader Stub Utility
 *
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * STUB input output
 *
 * Copies an NE program (eg, one that LINK4 built), replacing its MZ stub with
 * the BASIC-DOS NE loader stub (see nestub.asm), so that the program
 * also runs in real mode.  It does what "node tools/misc/mkne.js --stub" does
 * (see stubNE in mkne.js), and produces the same file.
 *
 * The new MZ header has a header size of zero, so DOS loads the entire file,
 * and a file offset is an image offset.  Its minimum allocation covers what
 * the stub will need (it must agree with the stub's first step), plus its
 * stack.  A stub of a different size moves the rest of the file, by a multiple
 * of the file's alignment, so the NE header's file offsets are adjusted, too.
 *
 * The stub's code comes from nestub.asm itself, assembled as a far data
 * segment of this program.  To build it, run "MAKE MAKEFILE" in this folder
 * (see the makefile, and ..\hello for a simpler example).
 */

#include <fcntl.h>
#include <io.h>
#include <string.h>

#define STUB_STACK  0x20        /* the stub's stack, in paragraphs */
#define MAXSEGS     254         /* the most segments we can handle */

#define WORD(p,o)   (*(unsigned *)((p) + (o)))
#define LONG(p,o)   (*(long *)((p) + (o)))

extern char far nestub[];       /* the stub's code */
extern char far nestubend[];    /* and the end of it */

static unsigned char mz[0x40], ne[0x40], segs[MAXSEGS * 8], buf[4096];
static char *outName;
static int out;

static fail(msg, name)
char *msg, *name;
{
    write(2, msg, strlen(msg));
    if (name) write(2, name, strlen(name));
    write(2, "\r\n", 2);
    exit(1);
}

static put(p, n)
char *p;
unsigned n;
{
    if (write(out, p, n) != n) fail("Unable to write ", outName);
}

main(argc, argv)
int argc;
char **argv;
{
    int in;
    unsigned i, n, count, shift, sector, stubLen;
    long offNE, newNE, delta, align, length, next, start, size, image;
    unsigned char *p;
    char far *stub = nestub, far *stubEnd = nestubend;

    /*
     * There are no switches, and the output replaces any existing file, so
     * it can't be the input.
     */
    if (argc != 3 || !stricmp(argv[1], argv[2])) fail("Syntax error", 0);

    in = open(argv[1], O_RDONLY | O_BINARY);
    if (in < 0) fail("Unable to find ", argv[1]);
    offNE = 0;
    if (read(in, mz, 0x40) == 0x40 && WORD(mz, 0) == 0x5a4d) {
        offNE = LONG(mz, 0x3c);
    }
    shift = count = 0;
    if (offNE >= 0x40 && lseek(in, offNE, 0) == offNE &&
        read(in, ne, 0x40) == 0x40 && WORD(ne, 0) == 0x454e) {
        shift = WORD(ne, 0x32);
        if (!shift) shift = 9;
        count = WORD(ne, 0x1c);
    }
    /*
     * The stub converts alignment units to paragraphs, so the shift must be
     * at least 4, and every segment needs an entry in our copy of the table.
     */
    if (shift < 4 || shift > 15 || !count || count > MAXSEGS ||
        lseek(in, offNE + WORD(ne, 0x22), 0) < 0 ||
        read(in, segs, count * 8) != count * 8) {
        fail("Invalid program ", argv[1]);
    }
    length = lseek(in, 0L, 2) - offNE;      /* from the NE header to the end */

    stubLen = (unsigned)(long)stubEnd - (unsigned)(long)stub;
    align = 1L << shift;
    delta = offNE - ((0x40 + stubLen + 15) & ~15);
    if (delta < 0) {
        delta = -((-delta + align - 1) & ~(align - 1));
    } else {
        delta &= ~(align - 1);
    }
    newNE = offNE - delta;

    if (LONG(ne, 0x2c)) LONG(ne, 0x2c) -= delta;    /* nonresident names */
    LONG(ne, 0x08) = 0;                     /* the file's CRC is now wrong */

    /*
     * Do what the stub's first step does: find the paragraph where each
     * segment ends up, to learn how much memory the program needs.
     */
    next = (newNE + WORD(ne, 0x22) + count * 8L + 15) >> 4;
    for (i = 0, p = segs; i < count; i++, p += 8) {
        start = next;
        sector = WORD(p, 0);
        if (sector) {
            sector -= (int)(delta / align);
            WORD(p, 0) = sector;
            start = (long)sector << (shift - 4);
            if (start < next) start = next;
        }
        size = WORD(p, 6);
        if (!size) size = 0x10000L;
        if (i + 1 == WORD(ne, 0x0e)) {      /* DGROUP gets the heap and stack */
            size += (long)WORD(ne, 0x10) + WORD(ne, 0x12);
        }
        next = start + ((size + 15) >> 4);
    }
    length += newNE;                        /* the new file's length */
    image = (length + 15) >> 4;
    if (next < image) next = image;

    memset(mz, 0, 0x40);
    WORD(mz, 0x00) = 0x5a4d;
    WORD(mz, 0x02) = (unsigned)length & 511;
    WORD(mz, 0x04) = (unsigned)((length + 511) >> 9);
    WORD(mz, 0x0a) = (unsigned)(next + STUB_STACK - image);     /* minimum */
    WORD(mz, 0x0c) = WORD(mz, 0x0a);                            /* maximum */
    WORD(mz, 0x0e) = (unsigned)next;                            /* SS */
    WORD(mz, 0x10) = STUB_STACK << 4;                           /* SP */
    WORD(mz, 0x14) = 0x40;                                      /* IP */
    WORD(mz, 0x18) = 0x40;                  /* relocation table (empty) */
    LONG(mz, 0x3c) = newNE;

    outName = argv[2];
    out = open(outName, O_WRONLY | O_CREAT | O_TRUNC | O_BINARY, 0x180);
    if (out < 0) fail("Unable to create ", outName);
    put(mz, 0x40);
    memset(buf, 0, sizeof(buf));
    for (i = 0; i < stubLen; i++) buf[i] = stub[i];
    for (size = newNE - 0x40; size; size -= n) {
        n = size > sizeof(buf) ? sizeof(buf) : (unsigned)size;
        put(buf, n);
        memset(buf, 0, stubLen);            /* the rest is padding */
    }
    /*
     * Copy the rest of the file, and then go back to replace the NE header
     * and the segment table with ours.
     */
    lseek(in, offNE, 0);
    while (n = read(in, buf, sizeof(buf))) {
        if (n == -1) fail("Unable to read ", argv[1]);
        put(buf, n);
    }
    lseek(out, newNE, 0);
    put(ne, 0x40);
    lseek(out, newNE + WORD(ne, 0x22), 0);
    put(segs, count * 8);
    if (close(out)) fail("Unable to write ", outName);
    return 0;
}
