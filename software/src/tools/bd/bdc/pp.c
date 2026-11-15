/*
 * BDC: BASIC-DOS C Compiler
 *
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * The preprocessor and tokens.
 *
 * Source is read a line at a time.  A line that starts with "#" is a
 * directive, which is processed as soon as the line is read; any other line
 * is scanned for tokens.  A macro is expanded by scanning its text before
 * the rest of the line, and it isn't expanded again while its text is being
 * scanned; a macro with parameters is expanded completely (see xexpand)
 * before its text is scanned.
 */

#include "bdc.h"

#ifdef HOST
#define DIRSEP  '/'
#else
#define DIRSEP  '\\'
#endif

#define ISID1(c) ((c) >= 'a' && (c) <= 'z' || (c) >= 'A' && (c) <= 'Z' || \
                  (c) == '_')
#define ISDIG(c) ((c) >= '0' && (c) <= '9')
#define ISID(c)  (ISID1(c) || ISDIG(c))

struct macro {
    char *name;
    char *body;                 /* a parameter is the byte 80h + its number */
    int np;                     /* parameters, or -1 if it takes no list */
    char busy;
    char hash;
    int next;
};

struct text {                   /* macro text being scanned */
    char *p;
    int mac;
    int mtop;                   /* what to release when it's done */
    int done;
    int after;                  /* a character read ahead of the macro */
    int hasafter;
    int raw;                    /* text that is already expanded */
};

struct file {
    FILE *fp;
    char *name;
    int line;
    int ifbase;                 /* #if nesting when the file was opened */
};

static struct macro macs[NMAC];
static int nmac = 1;
static int mhash[NHASH];
static struct text texts[NTEXT];
static int ntext, textbase;
static struct file files[NFILE];
static int nfile, ateof;
static char linebuf[LINESZ];
static char *lp = linebuf;
static int eolsent = 1;
static int pushc, haspush;
static char mbuf[MBUFSZ];
static int mtop;
static char ifst[NIF];          /* 0 not yet, 1 active, 2 done, 3 ignored */
static int nif, skipping;
static int incomment;
static char body[LINESZ];
static char pn[NPAR][NAMELEN];
static char dirname[NAMELEN];

static void dodefine();

int tok;                        /* the current token */
long tokval;                    /* T_NUM: its value; T_ASGOP: its operator */
int toktype;                    /* T_NUM: its type */
int toksym;                     /* T_ID: its symbol, or 0 */
int toklen;                     /* T_STR: its length */
char tokstr[TOKSZ];             /* T_ID or T_STR: its text */
int ppmode;                     /* nonzero while evaluating #if */
char *incdirs[NINC];
int ninc;

char *curfile()
{
    return nfile ? files[nfile - 1].name : "bdc";
}

int curline()
{
    return nfile ? files[nfile - 1].line : 0;
}

/*
 * Opens a source or include file.  A quoted include file is looked for in the
 * current file's directory first.
 */
int openfile(name, sys)
char *name;
int sys;
{
    char path[PATHSZ];
    FILE *fp;
    int i, n;
    char *p, *d;

    if (nfile >= NFILE) fatal("includes nested too deeply", "");
    fp = 0;
    if (!sys) {
        n = 0;
        if (nfile) {
            d = files[nfile - 1].name;
            for (p = d; *p; p++) {
                if (*p == '\\' || *p == '/' || *p == ':') n = p - d + 1;
            }
            strncpy(path, d, n);
        }
        strcpy(path + n, name);
        fp = fopen(path, "r");
    }
    for (i = 0; !fp && i < ninc; i++) {
        strcpy(path, incdirs[i]);
        n = strlen(path);
        if (n && path[n - 1] != '\\' && path[n - 1] != '/' &&
            path[n - 1] != ':') path[n++] = DIRSEP;
        strcpy(path + n, name);
        fp = fopen(path, "r");
    }
    if (!fp) return 0;
    files[nfile].fp = fp;
    files[nfile].name = psave(path);
    files[nfile].line = 0;
    files[nfile].ifbase = nif;
    nfile++;
    keeppool = 1;
    return 1;
}

static int findmac(name)
char *name;
{
    int i, h;

    h = hashstr(name);
    for (i = mhash[h & (NHASH - 1)]; i; i = macs[i].next) {
        if ((macs[i].hash & 255) == h && !strcmp(macs[i].name, name)) return i;
    }
    return 0;
}

static void setmac(name, text, np)
char *name, *text;
int np;
{
    int m, h;

    m = findmac(name);
    if (!m) {
        if (nmac >= NMAC) fatal("too many macros", "");
        m = nmac++;
        h = hashstr(name);
        macs[m].name = psave(name);
        macs[m].hash = h;
        macs[m].next = mhash[h & (NHASH - 1)];
        mhash[h & (NHASH - 1)] = m;
    }
    macs[m].body = psave(text);
    macs[m].np = np;
    macs[m].busy = 0;
    keeppool = 1;
}

static void setskip()
{
    int i;

    skipping = 0;
    for (i = 0; i < nif; i++) {
        if (ifst[i] != 1) skipping = 1;
    }
}

static char *skipws(p)
char *p;
{
    while (*p == ' ' || *p == '\t') p++;
    return p;
}

static char *getid(p, name)
char *p, *name;
{
    int n;

    n = 0;
    p = skipws(p);
    while (ISID(*p)) {
        if (n < NAMELEN - 1) name[n++] = *p;
        p++;
    }
    name[n] = 0;
    return p;
}

/*
 * Processes #define, given the text after the directive's name.  Comments
 * are removed from the macro's text, white space is reduced to single spaces,
 * and each parameter is replaced with a byte that identifies it.
 */
static void dodefine(p)
char *p;
{
    char name[NAMELEN], id[NAMELEN];
    int np, n, i, q;
    char *s;

    p = getid(p, name);
    if (!name[0]) {
        error("#define syntax", "");
        return;
    }
    np = -1;
    if (*p == '(') {
        np = 0;
        p = skipws(p + 1);
        while (*p && *p != ')') {
            p = getid(p, id);
            if (!id[0] || np >= NPAR) {
                error("#define syntax", "");
                return;
            }
            strcpy(pn[np++], id);
            p = skipws(p);
            if (*p == ',') p++;
        }
        if (*p == ')') p++;
    }
    p = skipws(p);
    n = 0;
    while (*p) {
        if (*p == '/' && p[1] == '*') {
            p += 2;
            while (*p && !(*p == '*' && p[1] == '/')) p++;
            if (*p) p += 2;
            body[n++] = ' ';
        }
        else if (*p == '/' && p[1] == '/') break;
        else if (*p == '"' || *p == '\'') {
            q = *p;
            body[n++] = *p++;
            while (*p) {
                body[n++] = *p;
                if (*p == '\\' && p[1]) body[n++] = *++p;
                else if (*p == q) {
                    p++;
                    break;
                }
                p++;
            }
        }
        else if (ISID1(*p)) {
            s = p;
            p = getid(p, id);
            for (i = 0; i < np; i++) {
                if (!strcmp(pn[i], id)) break;
            }
            if (i < np) body[n++] = 0x80 + i;
            else while (s < p) body[n++] = *s++;
        }
        else if (ISDIG(*p)) {           /* so "0x1e" isn't taken for a name */
            while (ISID(*p)) body[n++] = *p++;
        }
        else if (*p == ' ' || *p == '\t') {
            p = skipws(p);
            body[n++] = ' ';
        }
        else body[n++] = *p++;
    }
    while (n && body[n - 1] == ' ') n--;
    body[n] = 0;
    setmac(name, body, np);
}

/*
 * Defines a macro from the text that would follow #define (eg, "N 1").
 */
void define(text)
char *text;
{
    dodefine(text);
}

static void doinclude(p)
char *p;
{
    char name[PATHSZ];
    int q, n;

    p = skipws(p);
    q = *p == '<' ? '>' : '"';
    if (*p != '<' && *p != '"') {
        error("#include syntax", "");
        return;
    }
    n = 0;
    for (p++; *p && *p != q && n < 64; p++) name[n++] = *p;
    name[n] = 0;
    if (!openfile(name, q == '>')) error("Unable to find %s", name);
}

/*
 * Evaluates the expression of #if or #elif, by scanning the rest of the
 * line for tokens; a name that isn't a macro is zero.
 */
static int ifexpr(p)
char *p;
{
    int v, savenode, savebase, savepush;

    savenode = nodetop;
    savebase = textbase;
    savepush = haspush;
    textbase = ntext;
    haspush = 0;
    lp = p;
    ppmode = 1;
    gettok();
    v = constexpr() != 0;
    if (tok != T_EOL) error("#if syntax", "");
    ppmode = 0;
    while (*lp) lp++;
    nodetop = savenode;
    textbase = savebase;
    haspush = savepush;
    return v;
}

/*
 * Returns nonzero if a comment that starts on this line doesn't end on it.
 */
static int opencomment(p)
char *p;
{
    int q;

    while (*p) {
        if (*p == '"' || *p == '\'') {
            q = *p++;
            while (*p && *p != q) {
                if (*p == '\\' && p[1]) p++;
                p++;
            }
            if (*p) p++;
        }
        else if (*p == '/' && p[1] == '/') return 0;
        else if (*p == '/' && p[1] == '*') {
            p += 2;
            while (*p && !(*p == '*' && p[1] == '/')) p++;
            if (!*p) return 1;
            p += 2;
        }
        else p++;
    }
    return 0;
}

static void directive(p)
char *p;
{
    int i, v;
    char id[NAMELEN];

    p = getid(p, dirname);
    if (!strcmp(dirname, "if") || !strcmp(dirname, "ifdef") ||
        !strcmp(dirname, "ifndef")) {
        if (nif >= NIF) fatal("#if nested too deeply", "");
        if (skipping) {
            ifst[nif++] = 3;
            return;
        }
        if (!dirname[2]) v = ifexpr(p);
        else {
            getid(p, id);
            v = findmac(id) != 0;
            if (dirname[2] == 'n') v = !v;
        }
        ifst[nif++] = v ? 1 : 0;
        setskip();
        return;
    }
    if (!strcmp(dirname, "else") || !strcmp(dirname, "elif")) {
        if (nif <= files[nfile - 1].ifbase) {
            error("#else without #if", "");
            return;
        }
        i = ifst[nif - 1];
        if (i == 1) ifst[nif - 1] = 2;
        else if (i == 0) {
            /*
             * Evaluate #elif as if this part were active, since its
             * expression is scanned like any other line.
             */
            ifst[nif - 1] = 1;
            setskip();
            v = 1;
            if (dirname[2] == 'i' && !skipping) v = ifexpr(p);
            ifst[nif - 1] = v ? 1 : 0;
        }
        setskip();
        return;
    }
    if (!strcmp(dirname, "endif")) {
        if (nif <= files[nfile - 1].ifbase) error("#endif without #if", "");
        else nif--;
        setskip();
        return;
    }
    if (skipping) return;
    if (!strcmp(dirname, "define")) dodefine(p);
    else if (!strcmp(dirname, "include")) doinclude(p);
    else if (!strcmp(dirname, "undef")) {
        getid(p, id);
        i = findmac(id);
        if (i) macs[i].name = "";       /* it stays in its chain, unfindable */
    }
    else if (!strcmp(dirname, "error")) error("#error%s", p);
    else if (dirname[0] && strcmp(dirname, "line") &&
             strcmp(dirname, "pragma")) {
        error("unknown directive: %s", dirname);
    }
}

/*
 * Reads the next line of the current file, with any continuation lines.
 */
static int readline()
{
    char *p;
    int n;
    struct file *f;

    p = linebuf;
    f = &files[nfile - 1];
    for (;;) {
        if (!fgets(p, LINESZ - (int)(p - linebuf), f->fp)) {
            if (p == linebuf) return 0;
            break;
        }
        f->line++;
        n = strlen(p);
        while (n && (p[n - 1] == '\n' || p[n - 1] == '\r' || p[n - 1] == 26))
            n--;
        p[n] = 0;
        if (!n || p[n - 1] != '\\') break;
        p += n - 1;
        *p = 0;
        if (p - linebuf > LINESZ - 100) fatal("line too long", "");
    }
    return 1;
}

/*
 * Gets the next line to scan for tokens, processing the directives and
 * skipping the lines before it.  Returns zero at the end of the source.
 */
static int fillline()
{
    char *p;
    struct file *f;

    for (;;) {
        f = &files[nfile - 1];
        if (!readline()) {
            if (nif > f->ifbase) {
                error("missing #endif", "");
                nif = f->ifbase;
                setskip();
            }
            if (nfile == 1) return 0;
            fclose(f->fp);
            nfile--;
            continue;
        }
        p = skipws(linebuf);
        if (*p == '#' && !incomment) {
            directive(p + 1);
            if (opencomment(p)) {
                while (readline()) {
                    for (p = linebuf; *p; p++) {
                        if (*p == '*' && p[1] == '/') break;
                    }
                    if (*p) break;
                }
            }
            continue;
        }
        if (skipping) continue;
        lp = linebuf;
        return 1;
    }
}

/*
 * Returns the next character: '\n' at the end of a line, and -1 at the end
 * of the source.  The text of a macro ends with a space, so that the macro
 * is still being scanned when a name at the end of its text is looked up.
 */
static int nextc()
{
    int c;
    struct text *t;

    if (haspush) {
        haspush = 0;
        return pushc;
    }
    for (;;) {
        if (ntext > textbase) {
            t = &texts[ntext - 1];
            c = *t->p & 255;
            if (c) {
                t->p++;
                return c;
            }
            if (!t->done) {
                t->done = 1;
                return ' ';
            }
            macs[t->mac].busy = 0;
            mtop = t->mtop;
            ntext--;
            if (t->hasafter) return t->after;
            continue;
        }
        c = *lp & 255;
        if (c) {
            lp++;
            return c;
        }
        if (ppmode) return '\n';
        if (!eolsent) {
            eolsent = 1;
            return '\n';
        }
        if (ateof || !fillline()) {
            ateof = 1;
            return -1;
        }
        eolsent = 0;
    }
}

static void unget(c)
int c;
{
    pushc = c;
    haspush = 1;
}

static void pushtext(p, m, top)
char *p;
int m, top;
{
    if (ntext >= NTEXT) fatal("macros nested too deeply", "");
    texts[ntext].p = p;
    texts[ntext].mac = m;
    texts[ntext].mtop = top;
    texts[ntext].done = 0;
    texts[ntext].raw = 0;
    texts[ntext].after = pushc;
    texts[ntext].hasafter = haspush;
    haspush = 0;
    ntext++;
    macs[m].busy = 1;
}

static int xw;                  /* where expanded text goes in mbuf */

static void xput(c)
int c;
{
    if (xw > MBUFSZ - 4) fatal("macro call too long", "");
    mbuf[xw++] = c;
}

/*
 * Returns the character after the string or character constant at s, which
 * is copied to the expanded text, if copy is nonzero.
 */
static char *xquote(s, copy)
char *s;
int copy;
{
    int q;

    q = *s;
    if (copy) xput(*s);
    for (s++; *s; s++) {
        if (copy) xput(*s);
        if (*s == '\\' && s[1]) {
            s++;
            if (copy) xput(*s);
        }
        else if (*s == q) return s + 1;
    }
    return s;
}

/*
 * Expands the macros in a string, adding the result to the expanded text.
 * A macro with parameters has its arguments expanded first; then they
 * replace the parameters in a copy of its text, and that's expanded, too,
 * but with the macro itself left alone.  All of that is done above the
 * result, which then moves down to where it belongs.
 */
static void xexpand(s)
char *s;
{
    char id[NAMELEN];
    int argoff[NPAR];
    char *t, *b, *a;
    int m, n, c, depth, base, bodyoff, resoff, save;

    while (*s) {
        c = *s & 255;
        if (c == '"' || c == '\'') {
            s = xquote(s, 1);
            continue;
        }
        if (!ISID(c)) {
            xput(c);
            s++;
            continue;
        }
        t = s;
        n = 0;
        while (ISID(*s)) {
            if (n < NAMELEN - 1) id[n++] = *s;
            s++;
        }
        id[n] = 0;
        m = ISDIG(c) ? 0 : findmac(id);
        b = s;
        if (m && macs[m].np >= 0) {
            while (*b == ' ') b++;
            if (*b != '(') m = 0;
        }
        if (!m || macs[m].busy) {
            while (t < s) xput(*t++);
            continue;
        }
        if (macs[m].np < 0) {
            macs[m].busy = 1;
            xexpand(macs[m].body);
            macs[m].busy = 0;
            continue;
        }
        base = xw;
        s = b + 1;
        n = 0;
        for (;;) {
            t = s;
            depth = 0;
            while (*s) {
                if (*s == '"' || *s == '\'') {
                    s = xquote(s, 0);
                    continue;
                }
                if (*s == '(') depth++;
                else if (*s == ')') {
                    if (!depth) break;
                    depth--;
                }
                else if (*s == ',' && !depth) break;
                s++;
            }
            save = *s;
            *s = 0;
            if (n < NPAR) argoff[n++] = xw;
            xexpand(t);
            xput(0);
            *s = save;
            if (!save) break;
            s++;
            if (save == ')') break;
        }
        bodyoff = xw;
        for (b = macs[m].body; *b; b++) {
            if (*b & 0x80) {
                if ((*b & 0x7f) < n) {
                    for (a = mbuf + argoff[*b & 0x7f]; *a; a++) xput(*a);
                }
            }
            else xput(*b);
        }
        xput(0);
        resoff = xw;
        macs[m].busy = 1;
        xexpand(mbuf + bodyoff);
        macs[m].busy = 0;
        n = xw - resoff;
        for (c = 0; c < n; c++) mbuf[base + c] = mbuf[resoff + c];
        xw = base + n;
    }
}

/*
 * Expands a macro that has parameters; the "(" has been read.  The text of
 * the call and then its expansion go in mbuf, which is released when the
 * expansion has been scanned.
 */
static void expand(m)
int m;
{
    int base, c, depth, q;
    char *p;

    base = mtop;
    xw = mtop;
    for (p = macs[m].name; *p; p++) xput(*p);
    xput('(');
    depth = 0;
    for (;;) {
        c = nextc();
        if (c < 0 || c == '\n' && ppmode) {
            error("unterminated macro call", "");
            break;
        }
        if (c == '\n') c = ' ';
        if (c == '"' || c == '\'') {
            q = c;
            xput(c);
            for (;;) {
                c = nextc();
                if (c < 0 || c == '\n') break;
                xput(c);
                if (c == '\\') xput(nextc());
                else if (c == q) break;
            }
            continue;
        }
        if (c == '/') {
            c = nextc();
            if (c == '*') {
                incomment = 1;
                c = nextc();
                while (c >= 0) {
                    if (c == '*') {
                        c = nextc();
                        if (c == '/') break;
                    }
                    else c = nextc();
                }
                incomment = 0;
                c = ' ';
            }
            else {
                unget(c);
                c = '/';
            }
        }
        xput(c);
        if (c == '(') depth++;
        else if (c == ')') {
            if (depth-- == 0) break;
        }
    }
    xput(0);
    c = xw;
    xexpand(mbuf + base);
    xput(0);
    pushtext(mbuf + c, 0, base);
    texts[ntext - 1].raw = 1;
    mtop = xw;
}

/*
 * Reads the character after a backslash in a string or character constant,
 * and returns the character that the escape sequence stands for.
 */
static int escape()
{
    int c, v, n;

    c = nextc();
    switch (c) {
    case 'n': return '\n';
    case 't': return '\t';
    case 'r': return '\r';
    case 'b': return '\b';
    case 'f': return '\f';
    case 'a': return 7;
    case 'v': return 11;
    case 'x':
        v = 0;
        for (;;) {
            c = nextc();
            if (ISDIG(c)) v = v * 16 + c - '0';
            else if (c >= 'a' && c <= 'f') v = v * 16 + c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') v = v * 16 + c - 'A' + 10;
            else break;
        }
        unget(c);
        return v & 255;
    }
    if (c >= '0' && c <= '7') {
        v = 0;
        for (n = 0; n < 3 && c >= '0' && c <= '7'; n++) {
            v = v * 8 + c - '0';
            c = nextc();
        }
        unget(c);
        return v & 255;
    }
    return c;
}

static void number(c)
int c;
{
    long v;
    int base, uns, lng;

    v = 0;
    base = 10;
    if (c == '0') {
        base = 8;
        c = nextc();
        if (c == 'x' || c == 'X') {
            base = 16;
            for (;;) {
                c = nextc();
                if (ISDIG(c)) v = v * 16 + c - '0';
                else if (c >= 'a' && c <= 'f') v = v * 16 + c - 'a' + 10;
                else if (c >= 'A' && c <= 'F') v = v * 16 + c - 'A' + 10;
                else break;
            }
        }
        else while (c >= '0' && c <= '7') {
            v = v * 8 + c - '0';
            c = nextc();
        }
    }
    else while (ISDIG(c)) {
        v = v * 10 + c - '0';
        c = nextc();
    }
    if (c == '.' || (c == 'e' || c == 'E') && base != 16) {
        error("floating point isn't supported", "");
        while (ISID(c) || c == '.') c = nextc();
    }
    uns = lng = 0;
    for (;;) {
        if (c == 'u' || c == 'U') uns = 1;
        else if (c == 'l' || c == 'L') lng = 1;
        else break;
        c = nextc();
    }
    unget(c);
    v &= 0xFFFFFFFFL;
    if ((v >> 16) & 0xFFFFL) lng = 1;
    if (base == 10 && !uns && (v & 0x8000L)) lng = 1;
    if (lng) {
        if (v & 0x80000000L) uns = 1;
        toktype = uns ? T_ULONG : T_LONG;
    }
    else {
        if (v & 0x8000L) uns = 1;
        toktype = uns ? T_UINT : T_INT;
    }
    tok = T_NUM;
    tokval = norm(v, toktype);
}

/*
 * Gets the next token.
 */
void gettok()
{
    int c, c2, n, m;

again:
    do c = nextc();
    while (c == ' ' || c == '\t' || c == '\r' || c == '\f' ||
           c == '\n' && !ppmode);
    if (c < 0) {
        tok = T_EOF;
        return;
    }
    if (c == '\n') {
        tok = T_EOL;
        return;
    }
    if (ISID1(c)) {
        n = 0;
        do {
            if (n < NAMELEN - 1) tokstr[n++] = c;
            c = nextc();
        } while (ISID(c));
        tokstr[n] = 0;
        unget(c);
        if (ppmode && !strcmp(tokstr, "defined")) {
            do c = nextc(); while (c == ' ' || c == '\t');
            c2 = c;
            if (c == '(') do c = nextc(); while (c == ' ' || c == '\t');
            n = 0;
            while (ISID(c)) {
                if (n < NAMELEN - 1) tokstr[n++] = c;
                c = nextc();
            }
            tokstr[n] = 0;
            while (c == ' ' || c == '\t') c = nextc();
            if (c2 != '(' || c != ')') unget(c);
            tok = T_NUM;
            tokval = findmac(tokstr) != 0;
            toktype = T_INT;
            return;
        }
        m = findmac(tokstr);
        if (m && !macs[m].busy &&
            !(ntext > textbase && texts[ntext - 1].raw)) {
            if (macs[m].np < 0) {
                pushtext(macs[m].body, m, mtop);
                goto again;
            }
            do c = nextc();
            while (c == ' ' || c == '\t' || c == '\n' && !ppmode);
            if (c == '(') {
                expand(m);
                goto again;
            }
            unget(c);
        }
        if (ppmode) {
            tok = T_NUM;
            tokval = 0;
            toktype = T_INT;
            return;
        }
        toksym = lookup(tokstr, NS_ORD);
        tok = T_ID;
        if (toksym && syms[toksym].cls == C_KW) tok = syms[toksym].val;
        return;
    }
    if (ISDIG(c)) {
        number(c);
        return;
    }
    switch (c) {
    case '"':
        n = 0;
        for (;;) {
            c = nextc();
            if (c < 0 || c == '\n') {
                error("unterminated string", "");
                break;
            }
            if (c == '"') {
                /*
                 * Another string that follows this one is part of it.
                 */
                do c = nextc();
                while (c == ' ' || c == '\t' || c == '\n' && !ppmode);
                if (c == '"') continue;
                unget(c);
                break;
            }
            if (c == '\\') c = escape();
            if (n < TOKSZ - 1) tokstr[n++] = c;
            else if (n == TOKSZ - 1) {
                error("string too long", "");
                n++;
            }
        }
        if (n > TOKSZ - 1) n = TOKSZ - 1;
        tokstr[n] = 0;
        toklen = n;
        tok = T_STR;
        return;
    case '\'':
        c = nextc();
        if (c == '\\') c = escape();
        if (nextc() != '\'') error("bad character constant", "");
        tok = T_NUM;
        tokval = norm((long)c, T_CHAR);
        toktype = T_INT;
        return;
    case '/':
        c = nextc();
        if (c == '*') {
            incomment = 1;
            c = nextc();
            for (;;) {
                if (c < 0 || c == '\n' && ppmode) break;
                if (c == '*') {
                    c = nextc();
                    if (c == '/') break;
                }
                else c = nextc();
            }
            incomment = 0;
            if (c < 0) error("unterminated comment", "");
            goto again;
        }
        if (c == '/') {
            do c = nextc(); while (c >= 0 && c != '\n');
            if (c == '\n' && ppmode) {
                tok = T_EOL;
                return;
            }
            goto again;
        }
        tok = '/';
        tokval = N_DIV;
        break;
    case '+':
        c = nextc();
        if (c == '+') {
            tok = T_INC;
            return;
        }
        tok = '+';
        tokval = N_ADD;
        break;
    case '-':
        c = nextc();
        if (c == '-') {
            tok = T_DEC;
            return;
        }
        if (c == '>') {
            tok = T_ARROW;
            return;
        }
        tok = '-';
        tokval = N_SUB;
        break;
    case '*':
        c = nextc();
        tok = '*';
        tokval = N_MUL;
        break;
    case '%':
        c = nextc();
        tok = '%';
        tokval = N_MOD;
        break;
    case '^':
        c = nextc();
        tok = '^';
        tokval = N_XOR;
        break;
    case '&':
        c = nextc();
        if (c == '&') {
            tok = T_ANDAND;
            return;
        }
        tok = '&';
        tokval = N_AND;
        break;
    case '|':
        c = nextc();
        if (c == '|') {
            tok = T_OROR;
            return;
        }
        tok = '|';
        tokval = N_OR;
        break;
    case '<':
        c = nextc();
        if (c == '=') {
            tok = T_LE;
            return;
        }
        if (c != '<') {
            unget(c);
            tok = '<';
            return;
        }
        c = nextc();
        tok = T_SHL;
        tokval = N_SHL;
        break;
    case '>':
        c = nextc();
        if (c == '=') {
            tok = T_GE;
            return;
        }
        if (c != '>') {
            unget(c);
            tok = '>';
            return;
        }
        c = nextc();
        tok = T_SHR;
        tokval = N_SHR;
        break;
    case '=':
        c = nextc();
        if (c == '=') tok = T_EQ;
        else {
            unget(c);
            tok = '=';
        }
        return;
    case '!':
        c = nextc();
        if (c == '=') tok = T_NE;
        else {
            unget(c);
            tok = '!';
        }
        return;
    case '.':
        c = nextc();
        if (c == '.') {
            if (nextc() != '.') error("syntax error", "");
            tok = T_ELLIPSIS;
            return;
        }
        if (ISDIG(c)) {
            unget(c);
            number('.');
            return;
        }
        unget(c);
        tok = '.';
        return;
    default:
        tok = c;
        return;
    }

    /*
     * An operator that "=" can follow; c is the character after it, and
     * tokval is its operator.
     */
    if (c == '=') tok = T_ASGOP;
    else unget(c);
}
