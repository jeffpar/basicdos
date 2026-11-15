/*
 * BDC: BASIC-DOS C Compiler
 *
 * @author Jeff Parsons
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * The object file, which has the same segments, group, and comment records
 * as a small model object file from Microsoft C 4.00:
 *
 *      1  _TEXT   BYTE PUBLIC 'CODE'
 *      2  _DATA   WORD PUBLIC 'DATA'     initialized variables
 *      3  CONST   WORD PUBLIC 'CONST'    strings
 *      4  _BSS    WORD PUBLIC 'BSS'      other variables
 *      DGROUP = CONST, _BSS, _DATA
 *
 * The file is written in order, as code and data are produced: an external
 * is defined when it's first referenced, each function's code is written at
 * the end of the function, and data is written as buffers fill.  Only the
 * segments' sizes aren't known in time, so their records are rewritten at
 * the end.
 */

#include "bdc.h"

#define DBUFSZ  240
#define NDFIX   32

struct dstream {                /* the data of a segment being collected */
    int n;
    int nfx;
    unsigned char buf[DBUFSZ];
    struct fix fx[NDFIX];
};

unsigned textoff, dataoff, constoff, bssoff;

static FILE *of;
static unsigned char rec[1100];
static int rlen, rtype;
static long segpos;             /* where the segment records are */
static int nextext = 1;
static struct dstream ds[2];    /* SEG_DATA and SEG_CONST */

static void rbeg(t)
int t;
{
    rtype = t;
    rlen = 0;
}

static void rb(b)
int b;
{
    rec[rlen++] = b;
}

static void rw(w)
unsigned w;
{
    rec[rlen++] = w & 255;
    rec[rlen++] = (w >> 8) & 255;
}

static void rname(s, under)
char *s;
int under;
{
    int n;

    n = strlen(s);
    rb(n + under);
    if (under) rb('_');
    while (*s) rb(*s++);
}

static void ridx(i)
unsigned i;
{
    if (i > 127) rb(0x80 | i >> 8);
    rb(i & 255);
}

static void rend()
{
    int i, sum, len;

    len = rlen + 1;
    sum = rtype + (len & 255) + (len >> 8);
    for (i = 0; i < rlen; i++) sum += rec[i];
    putc(rtype, of);
    putc(len & 255, of);
    putc(len >> 8, of);
    fwrite((char *)rec, 1, rlen, of);
    putc(-sum & 255, of);
}

static void coment(cls, s)
int cls;
char *s;
{
    rbeg(0x88);
    rb(0);
    rb(cls);
    while (*s) rb(*s++);
    rend();
}

static void segdef(attr, len, name, cls)
int attr;
unsigned len;
int name, cls;
{
    rbeg(0x98);
    rb(attr);
    rw(len);
    rb(name);
    rb(cls);
    rb(1);
    rend();
}

static void segdefs()
{
    segdef(0x28, textoff, 3, 4);
    segdef(0x48, dataoff, 5, 6);
    segdef(0x48, constoff, 7, 7);
    segdef(0x48, bssoff, 8, 9);
}

void objbegin(name, src)
char *name, *src;
{
    static char *lnames[] = {
        "", "DGROUP", "_TEXT", "CODE", "_DATA", "DATA", "CONST", "_BSS",
        "BSS", 0
    };
    int i;

    of = fopen(name, "wb");
    if (!of) {
        printf("Unable to create %s\n", name);
        exit(1);
    }
    rbeg(0x80);
    rname(src, 0);
    rend();
    coment(0, "BDC");
    coment(0x9F, "SLIBFA");
    coment(0x9F, "SLIBC");
    coment(0x9F, "LIBH");
    coment(0x9D, "0s");
    rbeg(0x96);
    for (i = 0; lnames[i]; i++) rname(lnames[i], 0);
    rend();
    segpos = ftell(of);
    segdefs();
    rbeg(0x9A);                         /* DGROUP = CONST, _BSS, _DATA */
    rb(2);
    rb(0xFF); rb(3);
    rb(0xFF); rb(4);
    rb(0xFF); rb(2);
    rend();
    objext("_acrtused", 1);             /* brings in the C startup code */
}

void objend()
{
    if (!of) return;
    dflush(SEG_DATA);
    dflush(SEG_CONST);
    rbeg(0x8A);
    rb(0);
    rend();
    fseek(of, segpos, 0);
    segdefs();
    if (ferror(of)) {
        printf("Unable to write the object file\n");
        nerr++;
    }
    fclose(of);
    of = 0;
}

/*
 * Defines an external, and returns its number.
 */
int objext(name, under)
char *name;
int under;
{
    rbeg(0x8C);
    rname(name, under);
    rb(0);
    rend();
    return nextext++;
}

void objpub(name, seg, off)
char *name;
int seg;
unsigned off;
{
    rbeg(0x90);
    rb(seg == SEG_TEXT ? 0 : 1);
    rb(seg);
    rname(name, 1);
    rw(off);
    rb(0);
    rend();
}

/*
 * Adds a fixup to a FIXUPP record, for the word at an offset in the data
 * record that precedes it.
 */
static void rfix(f, off)
struct fix *f;
unsigned off;
{
    int self;

    self = f->kind == F_CALL;
    rb(0x84 | (self ? 0 : 0x40) | off >> 8);
    rb(off & 255);
    if (f->kind == F_SEG) {
        if (f->a == SEG_TEXT) rb(0x54);         /* frame of the target */
        else {
            rb(0x14);                           /* frame of DGROUP */
            rb(1);
        }
        rb(f->a);
    }
    else {
        rb(0x56);                               /* frame of the target */
        ridx(f->a);
    }
}

/*
 * Writes a function's code and its fixups.
 */
void objcode(code, n, fixes, nfix)
unsigned char *code;
int n;
struct fix *fixes;
int nfix;
{
    int i, j, chunk, fi, any;

    fi = 0;
    for (i = 0; i < n; i += chunk) {
        chunk = n - i;
        if (chunk > 1000) chunk = 1000;
        /*
         * A record can't end in the middle of a word that has a fixup.
         */
        for (j = fi; j < nfix && fixes[j].off < i + chunk - 1; j++) ;
        if (j < nfix && fixes[j].off == i + chunk - 1) chunk--;
        rbeg(0xA0);
        rb(SEG_TEXT);
        rw(textoff + i);
        for (j = 0; j < chunk; j++) rb(code[i + j]);
        rend();
        any = 0;
        for (; fi < nfix && fixes[fi].off < i + chunk; fi++) {
            if (fixes[fi].kind == F_REL) continue;
            if (any && rlen > 1000) {
                rend();
                any = 0;
            }
            if (!any) rbeg(0x9C);
            any = 1;
            rfix(&fixes[fi], fixes[fi].off - i);
        }
        if (any) rend();
    }
}

/*
 * Writes the data collected for a segment.
 */
void dflush(seg)
int seg;
{
    struct dstream *d;
    unsigned off;
    int i;

    d = &ds[seg - SEG_DATA];
    if (!d->n) return;
    off = (seg == SEG_DATA ? dataoff : constoff) - d->n;
    rbeg(0xA0);
    rb(seg);
    rw(off);
    for (i = 0; i < d->n; i++) rb(d->buf[i]);
    rend();
    if (d->nfx) {
        rbeg(0x9C);
        for (i = 0; i < d->nfx; i++) rfix(&d->fx[i], d->fx[i].off);
        rend();
    }
    d->n = d->nfx = 0;
}

/*
 * Adds a byte to the data or CONST segment.
 */
void dput(seg, b)
int seg, b;
{
    struct dstream *d;

    d = &ds[seg - SEG_DATA];
    if (d->n >= DBUFSZ) dflush(seg);
    d->buf[d->n++] = b;
    if (seg == SEG_DATA) dataoff++;
    else constoff++;
}

/*
 * Adds a word that needs a fixup to the data segment.
 */
void dfix(seg, kind, a, v)
int seg, kind;
unsigned a, v;
{
    struct dstream *d;

    d = &ds[seg - SEG_DATA];
    if (d->n >= DBUFSZ - 2 || d->nfx >= NDFIX) dflush(seg);
    d->fx[d->nfx].off = d->n;
    d->fx[d->nfx].kind = kind;
    d->fx[d->nfx++].a = a;
    dput(seg, (int)(v & 255));
    dput(seg, (int)(v >> 8));
}
