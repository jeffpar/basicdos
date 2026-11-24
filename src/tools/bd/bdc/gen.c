/*
 * BDC: BASIC-DOS C Compiler
 *
 * @author Jeff Parsons
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * Code generation.
 *
 * Code is produced from one expression tree at a time, into a buffer that
 * holds one function's code, which is written to the object file at the
 * end of the function (so that jumps within it need no fixups).
 *
 * The value of an expression is in AX (or DX:AX, if it's long); a char's
 * value is extended to AX as soon as it's loaded.  BX holds an address, and
 * CX a count or a second operand; SI and DI are used (and preserved) only to
 * copy structs.  The first operand of a binary operation is pushed while the
 * second is evaluated, unless the second is simple enough (a constant, or a
 * variable with a fixed address) to be the operand of an instruction.
 */

#include "bdc.h"

#define AX      0
#define CX      1
#define DX      2
#define BX      3

#define O_IMM   1               /* constant val */
#define O_IMMA  2               /* address of sym (or segment seg) + val */
#define O_MEMG  3               /* memory at sym (or segment seg) + val */
#define O_MEML  4               /* memory at BP + val */
#define O_BX    5               /* memory at BX + val */

#define A_ADD   0               /* arithmetic instructions */
#define A_OR    1
#define A_ADC   2
#define A_SBB   3
#define A_AND   4
#define A_SUB   5
#define A_XOR   6
#define A_CMP   7

#define KIND(t)     (types[t].kind)
#define ISLONG(t)   (KIND(t) == K_TLONG || KIND(t) == K_ULONG)

struct opnd {
    int kind;
    int sym;
    int seg;
    long val;
};

int locoff;                     /* BP offset of the last local variable */
int minloc;                     /* the function's lowest locoff */

static unsigned char code[CODESZ];
static int cp;
static struct fix fixes[NFIX];
static int nfix;
static int labaddr[NLAB];       /* -1 until the label is defined */
static int nlab;
static int patchoff[NPATCH];    /* 16-bit displacements to labels */
static int patchlab[NPATCH];
static int npatch;
static int retlab;
static int lastjmp;             /* cp after a JMP to an undefined label */
static int helpers[8];

static char *helpname[] = {
    "__aNlmul", "__aNldiv", "__aNlrem", "__aNuldiv", "__aNulrem",
    "__aNlshl", "__aNlshr", "__aNulshr"
};

#define H_LMUL  0
#define H_LDIV  1
#define H_LREM  2
#define H_ULDIV 3
#define H_ULREM 4
#define H_LSHL  5
#define H_LSHR  6
#define H_ULSHR 7

static void gbool();
static void glcmp();

static void eb(b)
int b;
{
    if (cp >= CODESZ - 16) fatal("function too large", "");
    code[cp++] = b;
}

static void ew(w)
unsigned w;
{
    eb(w & 255);
    eb((w >> 8) & 255);
}

static void addfix(kind, a)
int kind;
unsigned a;
{
    if (nfix >= NFIX) fatal("function too large", "");
    fixes[nfix].off = cp;
    fixes[nfix].kind = kind;
    fixes[nfix++].a = a;
}

/*
 * Returns the kind of fixup that the address of a symbol (or, if sym is
 * zero, of an offset in a segment) needs, with the fixup's target in *pa and
 * the word to be fixed up in *pv.
 */
int symfix(sym, seg, val, pa, pv)
int sym, seg;
unsigned val;
unsigned *pa, *pv;
{
    struct sym *s;

    if (!sym) {
        *pa = seg;
        *pv = val;
        return F_SEG;
    }
    s = &syms[sym];
    if (s->ext || !(s->flags & SF_DEF)) {
        if (!s->ext) s->ext = objext(s->name, 1);
        *pa = s->ext;
        *pv = val;
        return F_EXT;
    }
    *pa = s->seg;
    *pv = s->val + val;
    return F_SEG;
}

static void eaddr(sym, seg, val)
int sym, seg;
unsigned val;
{
    unsigned a, v;
    int kind;

    kind = symfix(sym, seg, val, &a, &v);
    addfix(kind, a);
    ew(v);
}

/*
 * Labels and jumps
 */
int newlab()
{
    if (nlab >= NLAB) fatal("function too large", "");
    labaddr[nlab] = -1;
    return nlab++;
}

/*
 * Defines a label here.  A JMP to this label that was just produced is
 * removed, along with any labels defined after it.
 */
void deflab(l)
int l;
{
    int i;

    if (lastjmp == cp && npatch && patchlab[npatch - 1] == l &&
        patchoff[npatch - 1] == cp - 2) {
        npatch--;
        cp -= 3;
        for (i = 0; i < nlab; i++) {
            if (labaddr[i] == cp + 3) labaddr[i] = cp;
        }
    }
    labaddr[l] = cp;
    lastjmp = -1;
}

static void addpatch(l)
int l;
{
    if (npatch >= NPATCH) fatal("function too large", "");
    patchoff[npatch] = cp;
    patchlab[npatch++] = l;
}

void jmp(l)
int l;
{
    int d;

    if (labaddr[l] >= 0) {
        d = labaddr[l] - (cp + 2);
        if (d >= -128) {
            eb(0xEB);
            eb(d);
        }
        else {
            eb(0xE9);
            ew(d - 1);
        }
        return;
    }
    eb(0xE9);
    addpatch(l);
    ew(0);
    lastjmp = cp;
}

/*
 * Jumps to a label if condition cc (the low four bits of a Jcc opcode) is
 * true.  Only a jump back to a nearby label can be a short one.
 */
static void jcc(cc, l)
int cc, l;
{
    int d;

    if (labaddr[l] >= 0) {
        d = labaddr[l] - (cp + 2);
        if (d >= -128) {
            eb(0x70 | cc);
            eb(d);
            return;
        }
    }
    eb(0x70 | (cc ^ 1));
    eb(3);
    eb(0xE9);
    if (labaddr[l] >= 0) ew(labaddr[l] - (cp + 2));
    else {
        addpatch(l);
        ew(0);
    }
}

void gretlab()
{
    jmp(retlab);
}

void gcase(v, l)
long v;
int l;
{
    eb(0x3D);                           /* cmp ax,v */
    ew((unsigned)(v & 0xFFFF));
    jcc(4, l);
}

/*
 * Operands
 */
static int memop(c, o)
int c;
struct opnd *o;
{
    if (nodes[c].op == N_ADDRG) {
        o->kind = O_MEMG;
        o->sym = nodes[c].sym;
        o->seg = nodes[c].left;
        o->val = nodes[c].val;
        return 1;
    }
    if (nodes[c].op == N_ADDRL) {
        o->kind = O_MEML;
        o->val = nodes[c].val;
        return 1;
    }
    return 0;
}

/*
 * Returns nonzero if a node's value (of 16 or 32 bits) can be the operand
 * of an instruction, and describes that operand.
 */
static int getopnd(n, o)
int n;
struct opnd *o;
{
    struct node *np;

    np = &nodes[n];
    while (np->op == N_CAST && tsize(np->type) >= 2 &&
           tsize(np->type) == tsize(nodes[np->left].type)) {
        np = &nodes[np->left];
    }
    switch (np->op) {
    case N_CONST:
        o->kind = O_IMM;
        o->val = np->val;
        return 1;
    case N_ADDRG:
        o->kind = O_IMMA;
        o->sym = np->sym;
        o->seg = np->left;
        o->val = np->val;
        return 1;
    case N_DEREF:
        if (tsize(np->type) != 2 && tsize(np->type) != 4) return 0;
        return memop(np->left, o);
    }
    return 0;
}

/*
 * Returns nonzero if a node's value can be loaded without changing any
 * register but AX and DX.
 */
static int isleaf(n)
int n;
{
    int op;

    while (nodes[n].op == N_CAST) n = nodes[n].left;
    op = nodes[n].op;
    if (op == N_DEREF) op = nodes[nodes[n].left].op;
    return op == N_CONST || op == N_ADDRG || op == N_ADDRL;
}

static int fits8(v)
unsigned v;
{
    v &= 0xFFFF;
    return v < 0x80 || v >= 0xFF80;
}

static unsigned immval(o, hi)
struct opnd *o;
int hi;
{
    if (o->kind != O_IMM) return 0;
    return (unsigned)((hi ? o->val >> 16 : o->val) & 0xFFFF);
}

static void modrm(reg, o, d)
int reg;
struct opnd *o;
int d;
{
    int v;

    reg <<= 3;
    v = (int)o->val + d;
    switch (o->kind) {
    case O_MEMG:
        eb(0x06 | reg);
        eaddr(o->sym, o->seg, (unsigned)v);
        break;
    case O_MEML:
        if (v >= -128 && v <= 127) {
            eb(0x46 | reg);
            eb(v);
        }
        else {
            eb(0x86 | reg);
            ew((unsigned)v);
        }
        break;
    case O_BX:
        if (!v) eb(0x07 | reg);
        else if (v >= -128 && v <= 127) {
            eb(0x47 | reg);
            eb(v);
        }
        else {
            eb(0x87 | reg);
            ew((unsigned)v);
        }
        break;
    }
}

static void opmem(opc, reg, o, d)
int opc, reg;
struct opnd *o;
int d;
{
    eb(opc);
    modrm(reg, o, d);
}

/*
 * Loads a register with an operand (or its high word).
 */
static void ldreg(reg, o, hi)
int reg;
struct opnd *o;
int hi;
{
    unsigned v;

    if (o->kind == O_IMM || o->kind == O_IMMA && hi) {
        v = immval(o, hi);
        if (!v) {
            eb(0x33);                   /* xor reg,reg */
            eb(0xC0 | reg * 9);
        }
        else {
            eb(0xB8 | reg);
            ew(v);
        }
    }
    else if (o->kind == O_IMMA) {
        eb(0xB8 | reg);
        eaddr(o->sym, o->seg, (unsigned)o->val);
    }
    else if (reg == AX && o->kind == O_MEMG) {
        eb(0xA1);
        eaddr(o->sym, o->seg, (unsigned)o->val + (hi ? 2 : 0));
    }
    else opmem(0x8B, reg, o, hi ? 2 : 0);
}

/*
 * Arithmetic on a register with an operand (or its high word).
 */
static void ari(op, reg, o, hi)
int op, reg;
struct opnd *o;
int hi;
{
    unsigned v;

    if (o->kind == O_IMM || o->kind == O_IMMA && hi) {
        v = immval(o, hi);
        if (fits8(v)) {
            eb(0x83);
            eb(0xC0 | op << 3 | reg);
            eb(v);
        }
        else {
            if (reg == AX) eb(op << 3 | 5);
            else {
                eb(0x81);
                eb(0xC0 | op << 3 | reg);
            }
            ew(v);
        }
    }
    else if (o->kind == O_IMMA) {
        if (reg == AX) eb(op << 3 | 5);
        else {
            eb(0x81);
            eb(0xC0 | op << 3 | reg);
        }
        eaddr(o->sym, o->seg, (unsigned)o->val);
    }
    else opmem(op << 3 | 3, reg, o, hi ? 2 : 0);
}

/*
 * Arithmetic on memory with a constant.
 */
static void memimm(op, o, d, v, size)
int op;
struct opnd *o;
int d;
unsigned v;
unsigned size;
{
    if (size == 1) {
        opmem(0x80, op, o, d);
        eb(v);
    }
    else if (fits8(v)) {
        opmem(0x83, op, o, d);
        eb(v);
    }
    else {
        opmem(0x81, op, o, d);
        ew(v);
    }
}

/*
 * Loads AX (or DX:AX) with the value at an operand.
 */
static void load(t, o)
int t;
struct opnd *o;
{
    unsigned sz;

    sz = tsize(t);
    if (sz == 1) {
        if (o->kind == O_MEMG) {
            eb(0xA0);
            eaddr(o->sym, o->seg, (unsigned)o->val);
        }
        else opmem(0x8A, AX, o, 0);
        if (KIND(t) == K_UCHAR) {
            eb(0x32);                   /* xor ah,ah */
            eb(0xE4);
        }
        else eb(0x98);                  /* cbw */
    }
    else if (sz == 2 || sz == 4) {
        ldreg(AX, o, 0);
        if (sz == 4) ldreg(DX, o, 1);
    }
    else error("unsupported use of a struct or array", "");
}

static void store(t, o)
int t;
struct opnd *o;
{
    unsigned sz;

    sz = tsize(t);
    if (sz == 1) {
        if (o->kind == O_MEMG) {
            eb(0xA2);
            eaddr(o->sym, o->seg, (unsigned)o->val);
        }
        else opmem(0x88, AX, o, 0);
    }
    else if (sz == 2 || sz == 4) {
        if (o->kind == O_MEMG) {
            eb(0xA3);
            eaddr(o->sym, o->seg, (unsigned)o->val);
        }
        else opmem(0x89, AX, o, 0);
        if (sz == 4) opmem(0x89, DX, o, 2);
    }
    else error("unsupported use of a struct or array", "");
}

/*
 * Stores a constant operand.
 */
static void storeimm(o, ro, sz)
struct opnd *o, *ro;
unsigned sz;
{
    if (sz == 1) {
        opmem(0xC6, 0, o, 0);
        eb(immval(ro, 0));
        return;
    }
    opmem(0xC7, 0, o, 0);
    if (ro->kind == O_IMMA) eaddr(ro->sym, ro->seg, (unsigned)ro->val);
    else ew(immval(ro, 0));
    if (sz == 4) {
        opmem(0xC7, 0, o, 2);
        ew(immval(ro, 1));
    }
}

/*
 * Splits an address into a node and a constant offset.
 */
static int addrparts(c, poff)
int c;
long *poff;
{
    *poff = 0;
    if (nodes[c].op == N_ADD && nodes[nodes[c].right].op == N_CONST) {
        *poff = nodes[nodes[c].right].val;
        c = nodes[c].left;
    }
    return c;
}

/*
 * Makes an operand for the object of an N_DEREF node, with code that puts
 * its address in BX, if it has no fixed address.
 */
static void lvaddr(n, o)
int n;
struct opnd *o;
{
    int c;
    long off;
    struct opnd t;

    c = nodes[n].left;
    if (memop(c, o)) return;
    c = addrparts(c, &off);
    if (getopnd(c, &t)) ldreg(BX, &t, 0);
    else {
        gexpr(c, 1);
        eb(0x93);                       /* xchg bx,ax */
    }
    o->kind = O_BX;
    o->val = off;
}

static void callhelp(i)
int i;
{
    if (!helpers[i]) helpers[i] = objext(helpname[i], 0);
    eb(0xE8);
    addfix(F_CALL, helpers[i]);
    ew(0);
}

static void gpush(a)
int a;
{
    struct opnd o;

    if (getopnd(a, &o)) {
        if (o.kind >= O_MEMG) {
            opmem(0xFF, 6, &o, 0);
            return;
        }
        ldreg(AX, &o, 0);
    }
    else gexpr(a, 1);
    eb(0x50);
}

static void gpushl(a)
int a;
{
    struct opnd o;

    if (getopnd(a, &o)) {
        if (o.kind >= O_MEMG) {
            opmem(0xFF, 6, &o, 2);
            opmem(0xFF, 6, &o, 0);
            return;
        }
        ldreg(AX, &o, 1);
        eb(0x50);
        ldreg(AX, &o, 0);
        eb(0x50);
        return;
    }
    gexpr(a, 1);
    eb(0x52);
    eb(0x50);
}

static void gcall(n)
int n;
{
    int args[NARG];
    int na, a, f, bytes, i;
    struct opnd o;
    struct sym *s;

    na = 0;
    for (a = nodes[n].right; a; a = nodes[a].right) {
        if (na >= NARG) fatal("too many arguments", "");
        args[na++] = nodes[a].left;
    }
    bytes = 0;
    for (i = na - 1; i >= 0; i--) {
        a = args[i];
        if (ISLONG(nodes[a].type)) {
            gpushl(a);
            bytes += 4;
        }
        else {
            gpush(a);
            bytes += 2;
        }
    }
    f = nodes[n].left;
    if (nodes[f].op == N_ADDRG && nodes[f].sym) {
        s = &syms[nodes[f].sym];
        eb(0xE8);
        if ((s->flags & SF_DEF) && !s->ext && s->seg == SEG_TEXT) {
            addfix(F_REL, s->val);
        }
        else {
            if (!s->ext) s->ext = objext(s->name, 1);
            addfix(F_CALL, s->ext);
        }
        ew(0);
    }
    else if (getopnd(f, &o) && o.kind >= O_MEMG) opmem(0xFF, 2, &o, 0);
    else {
        gexpr(f, 1);
        eb(0xFF);                       /* call ax */
        eb(0xD0);
    }
    if (bytes == 2) eb(0x5B);           /* pop bx */
    else if (bytes) {
        eb(0x83);                       /* add sp,bytes */
        eb(0xC4);
        eb(bytes);
    }
}

/*
 * Copies a struct: the address of the source is pushed while the address of
 * the destination is evaluated, and BX and DX preserve DI and SI.
 */
static void gstruct(l, r, sz)
int l, r;
unsigned sz;
{
    gexpr(nodes[r].left, 1);
    eb(0x50);
    gexpr(nodes[l].left, 1);
    eb(0x8B); eb(0xDF);                 /* mov bx,di */
    eb(0x8B); eb(0xD6);                 /* mov dx,si */
    eb(0x8B); eb(0xF8);                 /* mov di,ax */
    eb(0x5E);                           /* pop si */
    eb(0x1E);                           /* push ds */
    eb(0x07);                           /* pop es */
    eb(0xB9);                           /* mov cx,sz/2 */
    ew(sz >> 1);
    eb(0xF3); eb(0xA5);                 /* rep movsw */
    if (sz & 1) eb(0xA4);               /* movsb */
    eb(0x8B); eb(0xFB);                 /* mov di,bx */
    eb(0x8B); eb(0xF2);                 /* mov si,dx */
}

static void gassign(n, need)
int n, need;
{
    struct opnd o, ro;
    int l, r, t, c, k;
    long off;
    unsigned sz;

    l = nodes[n].left;
    r = nodes[n].right;
    t = nodes[n].type;
    sz = tsize(t);
    if (KIND(t) == K_STR) {
        gstruct(l, r, sz);
        return;
    }
    k = getopnd(r, &ro) && (ro.kind == O_IMM || ro.kind == O_IMMA && sz == 2);
    if (!memop(nodes[l].left, &o)) {
        if (isleaf(r)) lvaddr(l, &o);
        else {
            c = addrparts(nodes[l].left, &off);
            gexpr(c, 1);
            eb(0x50);
            gexpr(r, 1);
            eb(0x5B);                   /* pop bx */
            o.kind = O_BX;
            o.val = off;
            store(t, &o);
            return;
        }
    }
    if (k) {
        storeimm(&o, &ro, sz);
        if (need) gexpr(r, 1);
    }
    else {
        gexpr(r, 1);
        store(t, &o);
    }
}

static void gincdec(n, need)
int n, need;
{
    struct opnd o;
    int op, l, t, inc, post;
    unsigned sz, step;

    op = nodes[n].op;
    l = nodes[n].left;
    t = nodes[n].type;
    sz = tsize(t);
    step = (unsigned)nodes[n].val;
    inc = op == N_PREINC || op == N_POSTINC;
    post = op == N_POSTINC || op == N_POSTDEC;
    lvaddr(l, &o);
    if (post && need) load(t, &o);
    if (sz == 4) {
        memimm(inc ? A_ADD : A_SUB, &o, 0, step, 2);
        memimm(inc ? A_ADC : A_SBB, &o, 2, 0, 2);
    }
    else if (step == 1) opmem(sz == 1 ? 0xFE : 0xFF, inc ? 0 : 1, &o, 0);
    else memimm(inc ? A_ADD : A_SUB, &o, 0, step, sz);
    if (!post && need) load(t, &o);
}

static int aricode(op)
int op;
{
    switch (op) {
    case N_ADD: return A_ADD;
    case N_SUB: return A_SUB;
    case N_AND: return A_AND;
    case N_OR:  return A_OR;
    case N_XOR: return A_XOR;
    }
    return -1;
}

/*
 * An assignment with an operator.  Addition, subtraction, and the bitwise
 * operations are done in memory; anything else (and anything with a char)
 * is done in AX, with the right operand in CX.
 */
static void gasgop(n, need)
int n, need;
{
    struct opnd o, ro;
    int op, uns, l, r, t, c, code1, code2, fixed;
    long off;
    unsigned sz;

    op = nodes[n].sym;
    uns = (int)nodes[n].val;
    l = nodes[n].left;
    r = nodes[n].right;
    t = nodes[n].type;
    sz = tsize(t);
    code1 = aricode(op);
    code2 = code1 == A_ADD ? A_ADC : code1 == A_SUB ? A_SBB : code1;
    if (sz < 2) code1 = -1;
    if (sz == 4 && code1 < 0) {
        /*
         * A long operation that the C library does: the lvalue's address
         * stays on the stack, unless it's fixed, until the result is stored.
         */
        fixed = memop(nodes[l].left, &o);
        if (!fixed) {
            c = addrparts(nodes[l].left, &off);
            gexpr(c, 1);
            eb(0x50);
            o.kind = O_BX;
            o.val = off;
        }
        if (op == N_SHL || op == N_SHR) {
            gexpr(r, 1);
            eb(0x8B); eb(0xC8);         /* mov cx,ax */
            if (!fixed) {
                eb(0x5B);               /* pop bx */
                eb(0x53);               /* push bx */
            }
            load(t, &o);
            callhelp(op == N_SHL ? H_LSHL : uns ? H_ULSHR : H_LSHR);
        }
        else {
            gpushl(r);
            if (!fixed) {
                eb(0x8B); eb(0xDC);     /* mov bx,sp */
                eb(0x8B); eb(0x5F);     /* mov bx,[bx+4] */
                eb(4);
            }
            opmem(0xFF, 6, &o, 2);
            opmem(0xFF, 6, &o, 0);
            if (op == N_MUL) callhelp(H_LMUL);
            else if (op == N_DIV) callhelp(uns ? H_ULDIV : H_LDIV);
            else callhelp(uns ? H_ULREM : H_LREM);
        }
        if (!fixed) eb(0x5B);           /* pop bx */
        store(t, &o);
        return;
    }
    if (memop(nodes[l].left, &o)) {
        if (code1 >= 0 && getopnd(r, &ro) && ro.kind == O_IMM) {
            memimm(code1, &o, 0, immval(&ro, 0), 2);
            if (sz == 4) memimm(code2, &o, 2, immval(&ro, 1), 2);
            if (need) load(t, &o);
            return;
        }
        gexpr(r, 1);
    }
    else if (isleaf(r)) {
        lvaddr(l, &o);
        gexpr(r, 1);
    }
    else {
        c = addrparts(nodes[l].left, &off);
        gexpr(c, 1);
        eb(0x50);
        gexpr(r, 1);
        eb(0x5B);                       /* pop bx */
        o.kind = O_BX;
        o.val = off;
    }
    if (code1 >= 0) {
        opmem(code1 << 3 | 1, AX, &o, 0);
        if (sz == 4) opmem(code2 << 3 | 1, DX, &o, 2);
        if (need) load(t, &o);
        return;
    }
    eb(0x8B); eb(0xC8);                 /* mov cx,ax */
    load(t, &o);
    switch (op) {
    case N_MUL:
        eb(0xF7); eb(0xE9);             /* imul cx */
        break;
    case N_DIV:
    case N_MOD:
        if (uns) {
            eb(0x33); eb(0xD2);         /* xor dx,dx */
            eb(0xF7); eb(0xF1);         /* div cx */
        }
        else {
            eb(0x99);                   /* cwd */
            eb(0xF7); eb(0xF9);         /* idiv cx */
        }
        if (op == N_MOD) {
            eb(0x8B); eb(0xC2);         /* mov ax,dx */
        }
        break;
    case N_SHL:
        eb(0xD3); eb(0xE0);             /* shl ax,cl */
        break;
    case N_SHR:
        eb(0xD3);                       /* shr or sar ax,cl */
        eb(uns ? 0xE8 : 0xF8);
        break;
    default:
        eb(aricode(op) << 3 | 3);       /* op ax,cx */
        eb(0xC1);
    }
    store(t, &o);
    if (need && sz == 1) {
        if (KIND(t) == K_UCHAR) {
            eb(0x32); eb(0xE4);         /* xor ah,ah */
        }
        else eb(0x98);                  /* cbw */
    }
}

/*
 * Shifts AX left or right by a constant.
 */
static void shiftc(op, uns, n)
int op, uns, n;
{
    int b;

    b = op == N_SHL ? 0xE0 : uns ? 0xE8 : 0xF8;
    n &= 15;
    if (!n) return;
    if (n == 1) eb(0xD1);
    else {
        eb(0xB1);                       /* mov cl,n */
        eb(n);
        eb(0xD3);
    }
    eb(b);
}

static int log2of(v)
long v;
{
    int n;

    for (n = 1; n < 15; n++) {
        if (v == 1L << n) return n;
    }
    return 0;
}

/*
 * A binary operation on ints.
 */
static void gbin(n)
int n;
{
    struct opnd o;
    int op, l, r, uns, code1, simple, k;
    long v;

    op = nodes[n].op;
    l = nodes[n].left;
    r = nodes[n].right;
    uns = KIND(nodes[n].type) == K_UINT || KIND(nodes[n].type) == K_PTR;
    simple = getopnd(r, &o);
    v = simple && o.kind == O_IMM ? o.val : 0;
    code1 = aricode(op);
    if (code1 >= 0) {
        if (simple) {
            gexpr(l, 1);
            if (v == 1 && op == N_ADD || v == -1 && op == N_SUB) eb(0x40);
            else if (v == 1 && op == N_SUB || v == -1 && op == N_ADD) eb(0x48);
            else ari(code1, AX, &o, 0);
        }
        else if (op != N_SUB && getopnd(l, &o)) {
            gexpr(r, 1);
            ari(code1, AX, &o, 0);
        }
        else {
            gexpr(l, 1);
            eb(0x50);
            gexpr(r, 1);
            eb(0x5B);                   /* pop bx */
            if (op == N_SUB) eb(0x93);  /* xchg bx,ax */
            eb(code1 << 3 | 3);         /* op ax,bx */
            eb(0xC3);
        }
        return;
    }
    switch (op) {
    case N_MUL:
        k = log2of(v);
        if (k) {
            gexpr(l, 1);
            shiftc(N_SHL, 0, k);
        }
        else if (simple && o.kind >= O_MEMG) {
            gexpr(l, 1);
            opmem(0xF7, 5, &o, 0);      /* imul word ptr [mem] */
        }
        else {
            if (simple) {
                gexpr(l, 1);
                ldreg(BX, &o, 0);
            }
            else {
                gexpr(l, 1);
                eb(0x50);
                gexpr(r, 1);
                eb(0x5B);
            }
            eb(0xF7); eb(0xEB);         /* imul bx */
        }
        break;
    case N_DIV:
    case N_MOD:
        k = log2of(v);
        if (k && uns) {
            gexpr(l, 1);
            if (op == N_DIV) shiftc(N_SHR, 1, k);
            else {
                o.val = v - 1;
                ari(A_AND, AX, &o, 0);
            }
            break;
        }
        if (simple) {
            gexpr(l, 1);
            if (o.kind < O_MEMG) ldreg(BX, &o, 0);
        }
        else {
            gexpr(l, 1);
            eb(0x50);
            gexpr(r, 1);
            eb(0x93);                   /* xchg bx,ax */
            eb(0x58);                   /* pop ax */
        }
        if (uns) {
            eb(0x33); eb(0xD2);         /* xor dx,dx */
        }
        else eb(0x99);                  /* cwd */
        if (simple && o.kind >= O_MEMG) opmem(0xF7, uns ? 6 : 7, &o, 0);
        else {
            eb(0xF7);                   /* div or idiv bx */
            eb(uns ? 0xF3 : 0xFB);
        }
        if (op == N_MOD) {
            eb(0x8B); eb(0xC2);         /* mov ax,dx */
        }
        break;
    case N_SHL:
    case N_SHR:
        if (simple && o.kind == O_IMM) {
            gexpr(l, 1);
            shiftc(op, uns, (int)v);
            break;
        }
        if (simple) {
            gexpr(l, 1);
            ldreg(CX, &o, 0);
        }
        else {
            gexpr(l, 1);
            eb(0x50);
            gexpr(r, 1);
            eb(0x8B); eb(0xC8);         /* mov cx,ax */
            eb(0x58);                   /* pop ax */
        }
        eb(0xD3);
        eb(op == N_SHL ? 0xE0 : uns ? 0xE8 : 0xF8);
        break;
    }
}

/*
 * A binary operation on longs.  Multiplication and division are done by
 * the C library, which takes both operands on the stack and removes them;
 * so are shifts, which take the count in CL.
 */
static void glbin(n)
int n;
{
    struct opnd o;
    int op, l, r, uns, code1, code2;

    op = nodes[n].op;
    l = nodes[n].left;
    r = nodes[n].right;
    uns = KIND(nodes[n].type) == K_ULONG;
    code1 = aricode(op);
    if (code1 >= 0) {
        code2 = code1 == A_ADD ? A_ADC : code1 == A_SUB ? A_SBB : code1;
        if (getopnd(r, &o)) {
            gexpr(l, 1);
            ari(code1, AX, &o, 0);
            ari(code2, DX, &o, 1);
            return;
        }
        gexpr(l, 1);
        eb(0x52);
        eb(0x50);
        gexpr(r, 1);
        eb(0x5B);                       /* pop bx */
        eb(0x59);                       /* pop cx */
        if (op == N_SUB) {
            eb(0x93);                   /* xchg bx,ax */
            eb(0x87); eb(0xD1);         /* xchg dx,cx */
        }
        eb(code1 << 3 | 3); eb(0xC3);   /* op ax,bx */
        eb(code2 << 3 | 3); eb(0xD1);   /* op dx,cx */
        return;
    }
    if (op == N_SHL || op == N_SHR) {
        gexpr(l, 1);
        if (getopnd(r, &o)) {
            if (o.kind == O_IMM) {
                eb(0xB1);               /* mov cl,n */
                eb((int)o.val & 255);
            }
            else ldreg(CX, &o, 0);
        }
        else {
            eb(0x52);
            eb(0x50);
            gexpr(r, 1);
            eb(0x8B); eb(0xC8);         /* mov cx,ax */
            eb(0x58);
            eb(0x5A);
        }
        callhelp(op == N_SHL ? H_LSHL : uns ? H_ULSHR : H_LSHR);
        return;
    }
    gpushl(r);
    gpushl(l);
    if (op == N_MUL) callhelp(H_LMUL);
    else if (op == N_DIV) callhelp(uns ? H_ULDIV : H_LDIV);
    else callhelp(uns ? H_ULREM : H_LREM);
}

/*
 * Compares two 16-bit operands.
 */
static void gcmp(n)
int n;
{
    struct opnd o;

    gexpr(nodes[n].left, 1);
    if (getopnd(nodes[n].right, &o)) {
        if (o.kind == O_IMM && !immval(&o, 0)) {
            eb(0x0B); eb(0xC0);         /* or ax,ax */
        }
        else ari(A_CMP, AX, &o, 0);
    }
    else {
        eb(0x50);
        gexpr(nodes[n].right, 1);
        eb(0x5B);                       /* pop bx */
        eb(0x3B); eb(0xD8);             /* cmp bx,ax */
    }
}

static int ccode(op, uns)
int op, uns;
{
    switch (op) {
    case N_NE: return 5;
    case N_LT: return uns ? 2 : 0xC;
    case N_GE: return uns ? 3 : 0xD;
    case N_LE: return uns ? 6 : 0xE;
    case N_GT: return uns ? 7 : 0xF;
    }
    return 4;
}

/*
 * Compares the high or low words of two longs: the left one is in DX:AX
 * and the right one is an operand, or they're in CX:BX and DX:AX.
 */
static void lcmp(o, hi)
struct opnd *o;
int hi;
{
    if (o) ari(A_CMP, hi ? DX : AX, o, hi);
    else {
        eb(0x3B);
        eb(hi ? 0xCA : 0xD8);           /* cmp cx,dx or cmp bx,ax */
    }
}

static void glcmp(n, sense, lab)
int n, sense, lab;
{
    struct opnd o;
    struct opnd *po;
    int op, uns, l, r, ls, less, more;

    op = nodes[n].op;
    uns = (int)nodes[n].val;
    l = nodes[n].left;
    r = nodes[n].right;
    if ((op == N_EQ || op == N_NE) && nodes[r].op == N_CONST &&
        !nodes[r].val) {
        gexpr(l, 1);
        eb(0x0B); eb(0xC2);             /* or ax,dx */
        jcc((op == N_EQ) == sense ? 4 : 5, lab);
        return;
    }
    gexpr(l, 1);
    po = &o;
    if (!getopnd(r, &o)) {
        po = 0;
        eb(0x52);
        eb(0x50);
        gexpr(r, 1);
        eb(0x5B);                       /* pop bx */
        eb(0x59);                       /* pop cx */
    }
    if (op == N_EQ || op == N_NE) {
        if ((op == N_EQ) == sense) {
            ls = newlab();
            lcmp(po, 1);
            jcc(5, ls);
            lcmp(po, 0);
            jcc(4, lab);
            deflab(ls);
        }
        else {
            lcmp(po, 1);
            jcc(5, lab);
            lcmp(po, 0);
            jcc(5, lab);
        }
        return;
    }
    if (!sense) op ^= 1;                /* the opposite comparison */
    less = uns ? 2 : 0xC;
    more = uns ? 7 : 0xF;
    ls = newlab();
    lcmp(po, 1);
    if (op == N_LT || op == N_LE) {
        jcc(less, lab);
        jcc(more, ls);
        lcmp(po, 0);
        jcc(op == N_LT ? 2 : 6, lab);
    }
    else {
        jcc(more, lab);
        jcc(less, ls);
        lcmp(po, 0);
        jcc(op == N_GT ? 7 : 3, lab);
    }
    deflab(ls);
}

/*
 * Jumps to a label if an expression is true (sense is 1) or false (0).
 */
void gjump(n, sense, lab)
int n, sense, lab;
{
    struct node *np;
    int l1, cc;

    np = &nodes[n];
    switch (np->op) {
    case N_LNOT:
        gjump(np->left, !sense, lab);
        return;
    case N_LAND:
        if (!sense) {
            gjump(np->left, 0, lab);
            gjump(np->right, 0, lab);
        }
        else {
            l1 = newlab();
            gjump(np->left, 0, l1);
            gjump(np->right, 1, lab);
            deflab(l1);
        }
        return;
    case N_LOR:
        if (sense) {
            gjump(np->left, 1, lab);
            gjump(np->right, 1, lab);
        }
        else {
            l1 = newlab();
            gjump(np->left, 1, l1);
            gjump(np->right, 0, lab);
            deflab(l1);
        }
        return;
    case N_CONST:
        if ((np->val != 0) == sense) jmp(lab);
        return;
    case N_EQ:
    case N_NE:
    case N_LT:
    case N_GE:
    case N_LE:
    case N_GT:
        if (np->sym) {
            glcmp(n, sense, lab);
            return;
        }
        gcmp(n);
        cc = ccode(np->op, (int)np->val);
        if (!sense) cc ^= 1;
        jcc(cc, lab);
        return;
    }
    gexpr(n, 1);
    eb(0x0B);                           /* or ax,ax or or ax,dx */
    eb(ISLONG(np->type) ? 0xC2 : 0xC0);
    jcc(sense ? 5 : 4, lab);
}

/*
 * Leaves 1 or 0 in AX.
 */
static void gbool(n)
int n;
{
    int l1, l2;

    l1 = newlab();
    l2 = newlab();
    gjump(n, 0, l1);
    eb(0xB8);                           /* mov ax,1 */
    ew(1);
    jmp(l2);
    deflab(l1);
    eb(0x33); eb(0xC0);                 /* xor ax,ax */
    deflab(l2);
}

/*
 * Produces the code for an expression.  If need is zero, its value isn't
 * used, so only its side effects are produced.
 */
void gexpr(n, need)
int n, need;
{
    struct node *np;
    struct opnd o;
    int t, l, r, f, l1, l2;

    np = &nodes[n];
    t = np->type;
    l = np->left;
    r = np->right;
    switch (np->op) {
    case N_CONST:
        if (need) {
            o.kind = O_IMM;
            o.val = np->val;
            ldreg(AX, &o, 0);
            if (ISLONG(t)) ldreg(DX, &o, 1);
        }
        break;
    case N_ADDRG:
        if (need) {
            eb(0xB8);
            eaddr(np->sym, np->left, (unsigned)np->val);
        }
        break;
    case N_ADDRL:
        if (need) {
            o.kind = O_MEML;
            o.val = np->val;
            opmem(0x8D, AX, &o, 0);     /* lea ax,[bp+n] */
        }
        break;
    case N_DEREF:
        if (need) {
            lvaddr(n, &o);
            load(t, &o);
        }
        else if (!memop(l, &o)) gexpr(l, 0);
        break;
    case N_ASSIGN:
        gassign(n, need);
        break;
    case N_ASGOP:
        gasgop(n, need);
        break;
    case N_PREINC:
    case N_PREDEC:
    case N_POSTINC:
    case N_POSTDEC:
        gincdec(n, need);
        break;
    case N_NEG:
        gexpr(l, need);
        if (!need) break;
        if (ISLONG(t)) {
            eb(0xF7); eb(0xDA);         /* neg dx */
            eb(0xF7); eb(0xD8);         /* neg ax */
            eb(0x83); eb(0xDA); eb(0);  /* sbb dx,0 */
        }
        else {
            eb(0xF7); eb(0xD8);
        }
        break;
    case N_NOT:
        gexpr(l, need);
        if (!need) break;
        eb(0xF7); eb(0xD0);             /* not ax */
        if (ISLONG(t)) {
            eb(0xF7); eb(0xD2);         /* not dx */
        }
        break;
    case N_LNOT:
    case N_LAND:
    case N_LOR:
        gbool(n);
        break;
    case N_EQ:
    case N_NE:
    case N_LT:
    case N_GE:
    case N_LE:
    case N_GT:
        if (!need) {
            gexpr(l, 0);
            gexpr(r, 0);
        }
        else if (np->sym) gbool(n);
        else {
            gcmp(n);
            eb(0xB8);                   /* mov ax,1 */
            ew(1);
            eb(0x70 | ccode(np->op, (int)np->val));
            eb(1);                      /* jcc $+3 */
            eb(0x48);                   /* dec ax */
        }
        break;
    case N_COND:
        l1 = newlab();
        l2 = newlab();
        gjump(l, 0, l1);
        gexpr(nodes[r].left, need);
        jmp(l2);
        deflab(l1);
        gexpr(nodes[r].right, need);
        deflab(l2);
        break;
    case N_COMMA:
        gexpr(l, 0);
        gexpr(r, need);
        break;
    case N_CALL:
        gcall(n);
        break;
    case N_CAST:
        f = nodes[l].type;
        if (KIND(t) == K_TVOID) need = 0;
        gexpr(l, need);
        if (!need) break;
        if (tsize(t) == 1) {
            if (KIND(t) != KIND(f)) {
                if (KIND(t) == K_UCHAR) {
                    eb(0x32); eb(0xE4); /* xor ah,ah */
                }
                else eb(0x98);          /* cbw */
            }
        }
        else if (tsize(t) == 4 && tsize(f) < 4) {
            if (KIND(f) >= K_TCHAR && KIND(f) <= K_TINT) eb(0x99);
            else {
                eb(0x33); eb(0xD2);     /* xor dx,dx */
            }
        }
        break;
    default:
        if (!need) {
            gexpr(l, 0);
            gexpr(r, 0);
        }
        else if (ISLONG(t)) glbin(n);
        else gbin(n);
    }
}

/*
 * Starts a function: PUSH BP, MOV BP,SP, and SUB SP,n, where n isn't known
 * until the end of the function.
 */
void gbegin()
{
    cp = 0;
    nfix = npatch = nlab = 0;
    locoff = minloc = 0;
    lastjmp = -1;
    retlab = newlab();
    eb(0x55);
    eb(0x8B); eb(0xEC);
    eb(0x81); eb(0xEC);
    ew(0);
}

/*
 * Ends a function, and writes its code to the object file.
 */
void gend()
{
    int i, n;
    unsigned w;

    deflab(retlab);
    n = -minloc;
    if (n & 1) n++;
    if (n) {
        code[5] = n;
        code[6] = n >> 8;
        eb(0x8B); eb(0xE5);             /* mov sp,bp */
    }
    eb(0x5D);                           /* pop bp */
    eb(0xC3);                           /* ret */
    if (!n) {
        /*
         * There are no local variables, so remove the SUB SP.
         */
        for (i = 7; i < cp; i++) code[i - 4] = code[i];
        cp -= 4;
        for (i = 0; i < nlab; i++) {
            if (labaddr[i] >= 0) labaddr[i] -= 4;
        }
        for (i = 0; i < npatch; i++) patchoff[i] -= 4;
        for (i = 0; i < nfix; i++) fixes[i].off -= 4;
    }
    for (i = 0; i < npatch; i++) {
        if (labaddr[patchlab[i]] < 0) {
            error("undefined label", "");
            continue;
        }
        w = labaddr[patchlab[i]] - (patchoff[i] + 2);
        code[patchoff[i]] = w;
        code[patchoff[i] + 1] = w >> 8;
    }
    for (i = 0; i < nfix; i++) {
        if (fixes[i].kind == F_REL) {
            w = fixes[i].a - (textoff + fixes[i].off + 2);
            code[fixes[i].off] = w;
            code[fixes[i].off + 1] = w >> 8;
        }
    }
    STAT(4, cp);
    STAT(5, nfix);
    STAT(6, npatch);
    STAT(7, nlab);
    if ((long)textoff + cp > 0xFFF0L) fatal("too much code", "");
    objcode(code, cp, fixes, nfix);
    textoff += cp;
}
