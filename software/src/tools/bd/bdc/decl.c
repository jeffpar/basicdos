/*
 * BDC: BASIC-DOS C Compiler
 *
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * Symbols, types, declarations, initializers, and statements.
 *
 * The symbol table has global symbols at the bottom, growing up, and local
 * symbols at the top, growing down, so that a global symbol declared inside
 * a function (eg, a function that's called before it's declared) outlives
 * the function's local symbols.  Types, and the names in the pool, that are
 * created inside a function are released at the end of it.
 */

#include "bdc.h"

struct sym syms[NSYM];
int nglob = 1;                  /* the next global symbol */
int nloc = NSYM;                /* the last local symbol */
int level;                      /* 0 outside functions */
struct type types[NTYPE];
int ntype;
int ptypes[NPTYPE];             /* prototypes: a count, then that many types */
int nptype = 1;
int rettype;                    /* the current function's return type */
int brklab = -1, contlab = -1;

static int shash[NHASH];
static int modk[NMOD], modv[NMOD], modtop;
static int fdepth;              /* nonzero inside a parameter list */
static int gotpars;             /* a declarator's parameters are known */
static int npar, parstyle;      /* the last function declarator's */
static char parname[NPAR][NAMELEN];
static int partype[NPAR];
static long casev[NCASE];
static int casel[NCASE], ncase, casebase, deflt, insw;
static char *gname[NGOTO];
static int glab[NGOTO], ngoto;
static char tokname[4];

static char *kwname[] = {
    "auto", "register", "static", "extern", "typedef", "const", "volatile",
    "cdecl", "near", "far", "huge", "pascal", "fortran",
    "unsigned", "signed", "short", "long", "int", "char", "void", "float",
    "double", "struct", "union", "enum", "break", "case", "continue",
    "default", "do", "else", "for", "goto", "if", "return", "sizeof",
    "switch", "while", 0
};

static int kwtok[] = {
    K_AUTO, K_REGISTER, K_STATIC, K_EXTERN, K_TYPEDEF, K_CONST, K_VOLATILE,
    K_IGNORE, K_IGNORE, K_IGNORE, K_IGNORE, K_IGNORE, K_IGNORE,
    K_UNSIGNED, K_SIGNED, K_SHORT, K_LONG, K_INT, K_CHAR, K_VOID, K_FLOAT,
    K_DOUBLE, K_STRUCT, K_UNION, K_ENUM, K_BREAK, K_CASE, K_CONTINUE,
    K_DEFAULT, K_DO, K_ELSE, K_FOR, K_GOTO, K_IF, K_RETURN, K_SIZEOF,
    K_SWITCH, K_WHILE
};

static int declspec();
static int declarator();
static void statement();
static void compound();
static void init();

void expect(t)
int t;
{
    if (tok == t) gettok();
    else {
        tokname[0] = t;
        tokname[1] = 0;
        error("'%s' expected", t < 256 ? tokname : "while");
    }
}

/*
 * Symbols
 */
int lookup(name, ns)
char *name;
int ns;
{
    int i, h;

    h = hashstr(name);
    for (i = shash[h & (NHASH - 1)]; i; i = syms[i].next) {
        if ((syms[i].hash & 255) == h && syms[i].ns == ns &&
            !strcmp(syms[i].name, name)) return i;
    }
    return 0;
}

int lookupmem(name, t)
char *name;
int t;
{
    int i, h;

    h = hashstr(name);
    for (i = shash[h & (NHASH - 1)]; i; i = syms[i].next) {
        if ((syms[i].hash & 255) == h && syms[i].ns == NS_MEM &&
            syms[i].ext == t && !strcmp(syms[i].name, name)) return i;
    }
    return 0;
}

static int addsym(i, name, ns, cls, type)
int i;
char *name;
int ns, cls, type;
{
    int h;
    struct sym *s;

    if (nglob >= nloc) fatal("too many symbols", "");
    STAT(1, NSYM - nloc + 1);
    h = hashstr(name);
    s = &syms[i];
    s->name = psave(name);
    s->type = type;
    s->cls = cls;
    s->ns = ns;
    s->hash = h;
    s->flags = 0;
    s->seg = 0;
    s->val = 0;
    s->ext = 0;
    s->next = shash[h & (NHASH - 1)];
    shash[h & (NHASH - 1)] = i;
    return i;
}

/*
 * Adds a symbol to the current scope.
 */
int newsym(name, ns, cls, type)
char *name;
int ns, cls, type;
{
    if (level) return addsym(--nloc, name, ns, cls, type);
    return addsym(nglob++, name, ns, cls, type);
}

/*
 * Adds a global symbol, even inside a function.
 */
int newglobal(name, type)
char *name;
int type;
{
    if (level) keeppool = 1;
    return addsym(nglob++, name, NS_ORD, C_GLOBAL, type);
}

/*
 * Removes the local symbols that were added after mark.
 */
static void popsyms(mark)
int mark;
{
    int b, j;

    while (nloc < mark) {
        b = syms[nloc].hash & (NHASH - 1);
        if (shash[b] == nloc) shash[b] = syms[nloc].next;
        else {
            for (j = shash[b]; syms[j].next != nloc; j = syms[j].next) ;
            syms[j].next = syms[nloc].next;
        }
        nloc++;
    }
}

/*
 * Types
 */
static int mktype(kind, base, size, aux)
int kind, base;
unsigned size;
int aux;
{
    struct type *t;

    if (ntype >= NTYPE) fatal("too many types", "");
    t = &types[ntype];
    t->kind = kind;
    t->flags = 0;
    t->base = base;
    t->size = size;
    t->aux = aux;
    t->ptr = 0;
    return ntype++;
}

int ptrto(t)
int t;
{
    if (!types[t].ptr) types[t].ptr = mktype(K_PTR, t, 2, 0);
    return types[t].ptr;
}

unsigned tsize(t)
int t;
{
    return types[t].size;
}

/*
 * Returns nonzero if a type needs no alignment.
 */
static int isbyte(t)
int t;
{
    int k;

    for (;;) {
        k = types[t].kind;
        if (k != K_ARRAY) break;
        t = types[t].base;
    }
    if (k == K_TCHAR || k == K_UCHAR) return 1;
    return k == K_STR && (types[t].flags & TF_BYTE);
}

void initdecl()
{
    int i;

    ntype = 1;
    mktype(K_TVOID, 0, 0, 0);
    mktype(K_TCHAR, 0, 1, 0);
    mktype(K_UCHAR, 0, 1, 0);
    mktype(K_TINT, 0, 2, 0);
    mktype(K_UINT, 0, 2, 0);
    mktype(K_TLONG, 0, 4, 0);
    mktype(K_ULONG, 0, 4, 0);
    mktype(K_FLT, 0, 8, 0);
    mktype(K_FUNC, T_INT, 0, 0);
    ptrto(T_CHAR);
    for (i = 0; kwname[i]; i++) {
        syms[newsym(kwname[i], NS_ORD, C_KW, 0)].val = kwtok[i];
    }
}

/*
 * Returns nonzero if the current token starts a type.
 */
int istypename()
{
    if (tok >= K_CONST && tok <= K_ENUM) return 1;
    return tok == T_ID && toksym && syms[toksym].cls == C_TYPEDEF;
}

/*
 * Returns the member of a struct that follows member m (or its first member,
 * if m is zero), in the order they were declared.
 */
static int nextmem(t, m)
int t, m;
{
    if (!m) return types[t].aux;
    if (m == types[t].base) return 0;
    for (;;) {
        if (m < nglob) m++;
        else m--;
        if (syms[m].ns == NS_MEM && syms[m].ext == t) return m;
    }
}

static int structspec()
{
    int isun, tag, t, bt, mt, sc, m, bytes;
    unsigned off, sz, maxsz;
    char name[NAMELEN];

    isun = tok == K_UNION;
    gettok();
    t = 0;
    if (tok == T_ID) {
        strcpy(name, tokstr);
        tag = lookup(name, NS_TAG);
        gettok();
        if (tag) t = syms[tag].type;
        if (!tag || tok == '{' && types[t].size) {
            t = mktype(K_STR, 0, 0, 0);
            newsym(name, NS_TAG, C_TAG, t);
        }
    }
    else t = mktype(K_STR, 0, 0, 0);
    if (tok != '{') return t;
    if (isun) types[t].flags = TF_UNION;
    gettok();
    off = 0;
    maxsz = 0;
    bytes = 1;
    while (tok != '}' && tok != T_EOF) {
        bt = declspec(&sc);
        if (!bt) {
            error("syntax error in struct", "");
            gettok();
            continue;
        }
        for (;;) {
            name[0] = 0;
            gotpars = 1;
            mt = declarator(bt, name);
            if (tok == ':') {
                error("bit fields aren't supported", "");
                gettok();
                constexpr();
            }
            sz = tsize(mt);
            if (!isbyte(mt)) {
                bytes = 0;
                off = (off + 1) & ~1;
            }
            m = newsym(name, NS_MEM, C_MEMBER, mt);
            syms[m].val = isun ? 0 : off;
            syms[m].ext = t;
            if (!types[t].aux) types[t].aux = m;
            types[t].base = m;
            if (isun) {
                if (sz > maxsz) maxsz = sz;
            }
            else off += sz;
            if (tok != ',') break;
            gettok();
        }
        expect(';');
    }
    gettok();
    if (isun) off = maxsz;
    if (!bytes) off = (off + 1) & ~1;
    if (!off) off = 1;
    types[t].size = off;
    if (bytes) types[t].flags |= TF_BYTE;
    return t;
}

static int enumspec()
{
    long v;
    int s;

    gettok();
    if (tok == T_ID) gettok();
    if (tok != '{') return T_INT;
    gettok();
    v = 0;
    while (tok == T_ID) {
        s = newsym(tokstr, NS_ORD, C_ENUM, T_INT);
        gettok();
        if (tok == '=') {
            gettok();
            v = constexpr();
        }
        syms[s].val = (int)v++;
        if (tok != ',') break;
        gettok();
    }
    expect('}');
    return T_INT;
}

/*
 * Parses declaration specifiers.  Returns the type, or zero if there are no
 * specifiers at all, and sets *psc to the storage class (or zero).
 */
static int declspec(psc)
int *psc;
{
    int sc, seen, uns, lng, base;

    sc = seen = uns = lng = base = 0;
    for (;;) {
        switch (tok) {
        case K_AUTO:
        case K_REGISTER:
            sc = SC_AUTO;
            break;
        case K_STATIC:
            sc = SC_STATIC;
            break;
        case K_EXTERN:
            sc = SC_EXTERN;
            break;
        case K_TYPEDEF:
            sc = SC_TYPEDEF;
            break;
        case K_CONST:
        case K_VOLATILE:
        case K_IGNORE:
            break;
        case K_UNSIGNED:
            uns = seen = 1;
            break;
        case K_LONG:
            lng = seen = 1;
            break;
        case K_SIGNED:
        case K_SHORT:
        case K_INT:
            seen = 1;
            break;
        case K_CHAR:
            base = T_CHAR;
            seen = 1;
            break;
        case K_VOID:
            base = T_VOID;
            seen = 1;
            break;
        case K_FLOAT:
        case K_DOUBLE:
            base = T_DOUBLE;
            seen = 1;
            break;
        case K_STRUCT:
        case K_UNION:
            base = structspec();
            seen = 1;
            continue;
        case K_ENUM:
            base = enumspec();
            seen = 1;
            continue;
        case T_ID:
            if (!seen && toksym && syms[toksym].cls == C_TYPEDEF) {
                base = syms[toksym].type;
                seen = 1;
                break;
            }
            goto done;
        default:
            goto done;
        }
        gettok();
    }
done:
    *psc = sc;
    if (!seen) return sc ? T_INT : 0;
    if (!base) base = lng ? (uns ? T_ULONG : T_LONG) : (uns ? T_UINT : T_INT);
    else if (base == T_CHAR && uns) base = T_UCHAR;
    return base;
}

static void pushmod(k, v)
int k, v;
{
    if (modtop >= NMOD) fatal("declarator too complex", "");
    modk[modtop] = k;
    modv[modtop++] = v;
}

/*
 * Parses a parameter list; the "(" has been read.  The parameters of the
 * first list of a declarator outside of any other list are recorded, in
 * case this is a function definition.
 */
static void funcsuffix()
{
    int base, cnt, sc, t, record, dots;
    char nm[NAMELEN];

    record = fdepth == 0 && !gotpars;
    if (record) {
        npar = parstyle = 0;
        gotpars = 1;
    }
    if (tok == ')') {
        gettok();
        pushmod(K_FUNC, 0);
        return;
    }
    if (tok == T_ID && !istypename()) {         /* an old-style list */
        for (;;) {
            if (tok != T_ID) {
                error("parameter name expected", "");
                break;
            }
            if (record && npar < NPAR) {
                strcpy(parname[npar], tokstr);
                partype[npar++] = T_INT;
            }
            gettok();
            if (tok != ',') break;
            gettok();
        }
        expect(')');
        if (record) parstyle = 1;
        pushmod(K_FUNC, 0);
        return;
    }
    fdepth++;
    if (nptype >= NPTYPE - NPAR - 2) fatal("too many prototypes", "");
    base = nptype++;
    cnt = dots = 0;
    for (;;) {
        if (tok == T_ELLIPSIS) {
            gettok();
            dots = 1;
            break;
        }
        t = declspec(&sc);
        if (!t) {
            error("parameter type expected", "");
            break;
        }
        nm[0] = 0;
        t = declarator(t, nm);
        if (t == T_VOID && !nm[0] && !cnt && tok == ')') break;
        if (types[t].kind == K_ARRAY) t = ptrto(types[t].base);
        else if (types[t].kind == K_FUNC) t = ptrto(t);
        if (cnt < NPAR) {
            ptypes[nptype++] = t;
            if (record) {
                strcpy(parname[npar], nm);
                partype[npar++] = t;
            }
            cnt++;
        }
        if (tok != ',') break;
        gettok();
    }
    fdepth--;
    expect(')');
    ptypes[base] = cnt;
    pushmod(K_FUNC, dots && !cnt ? 0 : base);
}

static void dcl(name)
char *name;
{
    int stars;
    long n;

    stars = 0;
    for (;;) {
        if (tok == '*') stars++;
        else if (tok != K_CONST && tok != K_VOLATILE && tok != K_IGNORE) break;
        gettok();
    }
    if (tok == '(') {
        gettok();
        if (tok == '*' || tok == '(' || tok == K_IGNORE ||
            tok == T_ID && name && !istypename()) {
            dcl(name);
            expect(')');
        }
        else funcsuffix();              /* a function with no name */
    }
    else if (tok == T_ID && name) {
        strcpy(name, tokstr);
        gettok();
    }
    for (;;) {
        if (tok == '[') {
            gettok();
            n = 0;
            if (tok != ']') {
                n = constexpr();
                if (n <= 0) {
                    error("bad array size", "");
                    n = 1;
                }
            }
            expect(']');
            pushmod(K_ARRAY, (int)n);
        }
        else if (tok == '(') {
            gettok();
            funcsuffix();
        }
        else break;
    }
    while (stars--) pushmod(K_PTR, 0);
}

/*
 * Parses a declarator of type t; returns its type, and its name, if it
 * has one and name isn't null.
 */
static int declarator(t, name)
int t;
char *name;
{
    int b, i;

    b = modtop;
    dcl(name);
    for (i = modtop - 1; i >= b; i--) {
        if (modk[i] == K_PTR) t = ptrto(t);
        else if (modk[i] == K_ARRAY) {
            t = mktype(K_ARRAY, t, modv[i] * tsize(t), modv[i]);
        }
        else t = mktype(K_FUNC, t, 0, modv[i]);
    }
    modtop = b;
    return t;
}

/*
 * Parses a type name (in a cast or sizeof).
 */
int typename()
{
    int sc, t;

    t = declspec(&sc);
    gotpars = 1;
    return declarator(t, (char *)0);
}

/*
 * Initializers
 */
static void demit(v, size)
long v;
unsigned size;
{
    while (size--) {
        dput(SEG_DATA, (int)(v & 255));
        v >>= 8;
    }
}

static void dzero(n)
unsigned n;
{
    while (n--) dput(SEG_DATA, 0);
}

static void initscalar(t)
int t;
{
    int n, braces, kind;
    unsigned a, v;

    braces = 0;
    if (tok == '{') {
        braces = 1;
        gettok();
    }
    nodetop = 1;
    ininit = 1;
    n = cast(rvalue(assign()), t);
    ininit = 0;
    while (nodes[n].op == N_CAST && tsize(nodes[n].type) == 2 &&
           tsize(nodes[nodes[n].left].type) == 2) n = nodes[n].left;
    if (nodes[n].op == N_CONST) demit(nodes[n].val, tsize(t));
    else if (nodes[n].op == N_ADDRG && tsize(t) == 2) {
        kind = symfix(nodes[n].sym, nodes[n].left, (unsigned)nodes[n].val,
                      &a, &v);
        dfix(SEG_DATA, kind, a, v);
    }
    else {
        error("constant expected", "");
        dzero(tsize(t));
    }
    if (braces) {
        if (tok == ',') gettok();
        expect('}');
    }
}

static void init(t)
int t;
{
    int k, et, braced, m, i;
    unsigned n, cnt, esz, cur;

    k = types[t].kind;
    if (k != K_ARRAY && k != K_STR) {
        initscalar(t);
        return;
    }
    braced = 0;
    if (tok == '{') {
        braced = 1;
        gettok();
    }
    if (k == K_ARRAY) {
        et = types[t].base;
        esz = tsize(et);
        n = types[t].aux;
        cnt = 0;
        if (tok == T_STR && (et == T_CHAR || et == T_UCHAR)) {
            cnt = toklen + 1;
            if (n && cnt > n) cnt = n;
            for (i = 0; i < cnt; i++) dput(SEG_DATA, tokstr[i] & 255);
            gettok();
        }
        else while (tok != '}' && tok != T_EOF) {
            init(et);
            cnt++;
            if (cnt == n || tok != ',') break;
            gettok();
        }
        if (!n) {
            n = cnt;
            types[t].aux = n;
            types[t].size = n * esz;
        }
        dzero((n - cnt) * esz);
    }
    else {
        cur = 0;
        m = nextmem(t, 0);
        while (m && tok != '}' && tok != T_EOF) {
            dzero(syms[m].val - cur);
            init(syms[m].type);
            cur = syms[m].val + tsize(syms[m].type);
            m = (types[t].flags & TF_UNION) ? 0 : nextmem(t, m);
            if (!m || tok != ',') break;
            gettok();
        }
        dzero(tsize(t) - cur);
    }
    if (braced) {
        if (tok == ',') gettok();
        expect('}');
    }
}

/*
 * Defines a variable in the data or BSS segment.
 */
static void defvar(s)
int s;
{
    int t;
    unsigned size;

    t = syms[s].type;
    if (syms[s].flags & SF_DEF) {
        if (tok == '=') error("%s is already defined", syms[s].name);
        else return;
    }
    syms[s].flags |= SF_DEF;
    if (tok == '=') {
        gettok();
        if (!isbyte(t) && (dataoff & 1)) dput(SEG_DATA, 0);
        syms[s].seg = SEG_DATA;
        syms[s].val = dataoff;
        init(t);
        dflush(SEG_DATA);
    }
    else {
        size = tsize(t);
        if (!size) error("%s has no size", syms[s].name);
        if (!isbyte(t) && (bssoff & 1)) bssoff++;
        syms[s].seg = SEG_BSS;
        syms[s].val = bssoff;
        bssoff += size;
    }
    if (!(syms[s].flags & SF_STATIC) || syms[s].ext) {
        objpub(syms[s].name, syms[s].seg, syms[s].val);
    }
}

/*
 * Declares a global variable or function, or finds its earlier declaration.
 */
static int declglobal(name, t, sc)
char *name;
int t, sc;
{
    int s;

    s = lookup(name, NS_ORD);
    if (s && s < nglob && syms[s].cls == C_GLOBAL) {
        /*
         * A later declaration can complete an array's type, or add a
         * function's prototype.
         */
        if (!(syms[s].flags & SF_DEF) && !level) syms[s].type = t;
        return s;
    }
    s = newglobal(name, t);
    if (sc == SC_STATIC) syms[s].flags |= SF_STATIC;
    return s;
}

/*
 * Statements
 */
static int findlabel(name)
char *name;
{
    int i;

    for (i = 0; i < ngoto; i++) {
        if (!strcmp(gname[i], name)) return glab[i];
    }
    if (ngoto >= NGOTO) fatal("too many labels", "");
    gname[ngoto] = psave(name);
    glab[ngoto] = newlab();
    return glab[ngoto++];
}

static void localdecl()
{
    int sc, bt, t, s, n, a;
    unsigned sz;
    char name[NAMELEN];

    nodetop = 1;
    bt = declspec(&sc);
    if (tok == ';') {
        gettok();
        return;
    }
    for (;;) {
        name[0] = 0;
        gotpars = 1;
        t = declarator(bt, name);
        if (!name[0]) {
            error("name expected", "");
            break;
        }
        if (sc == SC_TYPEDEF) newsym(name, NS_ORD, C_TYPEDEF, t);
        else if (sc == SC_EXTERN || types[t].kind == K_FUNC) {
            declglobal(name, t, 0);
        }
        else if (sc == SC_STATIC) {
            s = newsym(name, NS_ORD, C_GLOBAL, t);
            syms[s].flags = SF_STATIC;
            defvar(s);
        }
        else {
            sz = tsize(t);
            if (!sz) error("%s has no size", name);
            locoff -= sz;
            if (!isbyte(t) && (locoff & 1)) locoff--;
            if (locoff < minloc) minloc = locoff;
            s = newsym(name, NS_ORD, C_AUTO, t);
            syms[s].val = locoff;
            if (tok == '=') {
                gettok();
                if (types[t].kind == K_ARRAY || types[t].kind == K_STR) {
                    error("%s can't be initialized", name);
                }
                nodetop = 1;
                a = mk(N_ADDRL, T_INT, 0, 0);
                nodes[a].val = locoff;
                n = cast(rvalue(assign()), t);
                gexpr(mk(N_ASSIGN, t, mk(N_DEREF, t, a, 0), n), 0);
            }
        }
        if (tok != ',') break;
        gettok();
    }
    expect(';');
}

static void compound()
{
    int smark, sloc;

    gettok();
    level++;
    smark = nloc;
    sloc = locoff;
    while (tok != '}' && tok != T_EOF) {
        if (tok >= K_AUTO && tok <= K_ENUM || istypename()) localdecl();
        else statement();
    }
    gettok();
    popsyms(smark);
    locoff = sloc;
    level--;
}

static void statement()
{
    int n, l1, l2, l3, l4, sb, sc, scb, sd, sin, i;
    long v;

    switch (tok) {
    case '{':
        compound();
        return;
    case ';':
        gettok();
        return;
    case K_IF:
        gettok();
        expect('(');
        n = fullexpr();
        expect(')');
        l1 = newlab();
        gjump(n, 0, l1);
        statement();
        if (tok == K_ELSE) {
            gettok();
            l2 = newlab();
            jmp(l2);
            deflab(l1);
            statement();
            deflab(l2);
        }
        else deflab(l1);
        return;
    case K_WHILE:
        gettok();
        l1 = newlab();
        l2 = newlab();
        deflab(l1);
        expect('(');
        n = fullexpr();
        expect(')');
        gjump(n, 0, l2);
        sb = brklab;
        sc = contlab;
        brklab = l2;
        contlab = l1;
        statement();
        jmp(l1);
        deflab(l2);
        brklab = sb;
        contlab = sc;
        return;
    case K_DO:
        gettok();
        l1 = newlab();
        l2 = newlab();
        l3 = newlab();
        deflab(l1);
        sb = brklab;
        sc = contlab;
        brklab = l3;
        contlab = l2;
        statement();
        deflab(l2);
        if (tok != K_WHILE) error("'while' expected", "");
        else gettok();
        expect('(');
        n = fullexpr();
        expect(')');
        gjump(n, 1, l1);
        deflab(l3);
        brklab = sb;
        contlab = sc;
        expect(';');
        return;
    case K_FOR:
        gettok();
        expect('(');
        if (tok != ';') gexpr(fullexpr(), 0);
        expect(';');
        l1 = newlab();
        l2 = newlab();
        l3 = l1;
        deflab(l1);
        if (tok != ';') gjump(fullexpr(), 0, l2);
        expect(';');
        if (tok != ')') {
            /*
             * The third expression's code comes before the body's, so the
             * body jumps back to it, and it jumps back to the test.
             */
            l3 = newlab();
            l4 = newlab();
            jmp(l4);
            deflab(l3);
            gexpr(fullexpr(), 0);
            jmp(l1);
            deflab(l4);
        }
        expect(')');
        sb = brklab;
        sc = contlab;
        brklab = l2;
        contlab = l3;
        statement();
        jmp(l3);
        deflab(l2);
        brklab = sb;
        contlab = sc;
        return;
    case K_SWITCH:
        /*
         * The value stays in AX while the code jumps to the comparisons,
         * which follow the body, since that's when the cases are known.
         */
        gettok();
        expect('(');
        n = cast(rvalue(fullexpr()), T_INT);
        expect(')');
        gexpr(n, 1);
        l1 = newlab();
        l2 = newlab();
        jmp(l1);
        sb = brklab;
        scb = casebase;
        sd = deflt;
        sin = insw;
        brklab = l2;
        casebase = ncase;
        deflt = -1;
        insw = 1;
        statement();
        jmp(l2);
        deflab(l1);
        for (i = casebase; i < ncase; i++) gcase(casev[i], casel[i]);
        if (deflt >= 0) jmp(deflt);
        deflab(l2);
        ncase = casebase;
        brklab = sb;
        casebase = scb;
        deflt = sd;
        insw = sin;
        return;
    case K_CASE:
        gettok();
        nodetop = 1;
        v = constexpr();
        expect(':');
        if (!insw) error("case outside of switch", "");
        else {
            if (ncase >= NCASE) fatal("too many cases", "");
            casev[ncase] = v;
            casel[ncase] = newlab();
            deflab(casel[ncase++]);
        }
        return;
    case K_DEFAULT:
        gettok();
        expect(':');
        if (!insw) error("default outside of switch", "");
        else {
            deflt = newlab();
            deflab(deflt);
        }
        return;
    case K_BREAK:
        gettok();
        if (brklab < 0) error("break outside of loop or switch", "");
        else jmp(brklab);
        expect(';');
        return;
    case K_CONTINUE:
        gettok();
        if (contlab < 0) error("continue outside of loop", "");
        else jmp(contlab);
        expect(';');
        return;
    case K_RETURN:
        gettok();
        if (tok != ';') {
            n = rvalue(fullexpr());
            if (rettype == T_VOID) gexpr(n, 0);
            else gexpr(cast(n, rettype), 1);
        }
        gretlab();
        expect(';');
        return;
    case K_GOTO:
        gettok();
        if (tok != T_ID) error("label expected", "");
        else {
            jmp(findlabel(tokstr));
            gettok();
        }
        expect(';');
        return;
    case T_ID:
        /*
         * This is a label if a colon follows it; otherwise, it's the first
         * token of an expression, which then starts with a token that has
         * already been read.
         */
        strcpy(pendname, tokstr);
        pendsym = toksym;
        gettok();
        if (tok == ':') {
            gettok();
            deflab(findlabel(pendname));
            return;
        }
        havepend = 1;
        break;
    }
    gexpr(fullexpr(), 0);
    expect(';');
}

/*
 * Compiles a function's definition; its declarator has been parsed, so
 * its parameters are in parname and partype.
 */
static void funcdef(s)
int s;
{
    int smark, pmark, tmark, ptmark, sc, bt, t, i, p;
    unsigned off;
    char name[NAMELEN];

    if (syms[s].flags & SF_DEF) error("%s is already defined", syms[s].name);
    syms[s].flags |= SF_DEF;
    syms[s].seg = SEG_TEXT;
    syms[s].val = textoff;
    if (!(syms[s].flags & SF_STATIC) || syms[s].ext) {
        objpub(syms[s].name, SEG_TEXT, textoff);
    }
    rettype = types[syms[s].type].base;
    smark = nloc;
    pmark = pooltop;
    tmark = ntype;
    ptmark = nptype;
    keeppool = 0;
    level = 1;

    /*
     * The declarations of an old-style definition's parameters
     */
    if (parstyle) {
        while (tok != '{' && tok != T_EOF) {
            bt = declspec(&sc);
            if (!bt) {
                error("syntax error in parameters", "");
                break;
            }
            for (;;) {
                name[0] = 0;
                gotpars = 1;
                t = declarator(bt, name);
                if (types[t].kind == K_ARRAY) t = ptrto(types[t].base);
                else if (types[t].kind == K_FUNC) t = ptrto(t);
                for (i = 0; i < npar; i++) {
                    if (!strcmp(parname[i], name)) break;
                }
                if (i < npar) partype[i] = t;
                else error("%s isn't a parameter", name);
                if (tok != ',') break;
                gettok();
            }
            expect(';');
        }
    }
    off = 4;
    for (i = 0; i < npar; i++) {
        if (parname[i][0]) {
            p = newsym(parname[i], NS_ORD, C_AUTO, partype[i]);
            syms[p].val = off;
        }
        off += (tsize(partype[i]) + 1) & ~1;
    }
    ngoto = 0;
    ncase = 0;
    insw = 0;
    brklab = contlab = -1;
    gbegin();
    if (tok != '{') error("'{' expected", "");
    else compound();
    gend();
    STAT(0, nglob);
    STAT(1, NSYM - nloc);
    STAT(2, ntype);
    STAT(3, pooltop);
    STAT(9, nptype);
    popsyms(smark);
    level = 0;
    if (!keeppool) {
        pooltop = pmark;
        ntype = tmark;
        nptype = ptmark;
        for (i = 1; i < ntype; i++) {
            if (types[i].ptr >= ntype) types[i].ptr = 0;
        }
    }
}

/*
 * Compiles a declaration outside of a function.
 */
void extdecl()
{
    int sc, bt, t, s;
    char name[NAMELEN];

    if (tok == ';') {
        gettok();
        return;
    }
    nodetop = 1;
    bt = declspec(&sc);
    if (!bt) {
        if (tok != T_ID && tok != '*' && tok != '(') {
            error("syntax error", "");
            gettok();
            return;
        }
        bt = T_INT;
    }
    if (tok == ';') {
        gettok();
        return;
    }
    for (;;) {
        name[0] = 0;
        gotpars = 0;
        t = declarator(bt, name);
        if (!name[0]) {
            error("name expected", "");
            gettok();
            return;
        }
        if (sc == SC_TYPEDEF) newsym(name, NS_ORD, C_TYPEDEF, t);
        else {
            s = declglobal(name, t, sc);
            if (types[t].kind == K_FUNC) {
                if (tok != ',' && tok != ';') {
                    funcdef(s);
                    return;
                }
            }
            else if (sc != SC_EXTERN || tok == '=') defvar(s);
        }
        if (tok != ',') break;
        gettok();
    }
    expect(';');
}
