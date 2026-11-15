/*
 * BDC: BASIC-DOS C Compiler
 *
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * BDC [/Idir] [/Dname[=text]] [/FIfile] [/Fofile] file.c
 *
 * /I adds a directory to look for include files in, /D defines a macro (which
 * can have parameters, if the command line allows the characters), /FI
 * includes a file ahead of the source file, and /Fo names the object file.
 *
 * BDC is a small, fast, single-pass C compiler.  It reads one C source file
 * and writes one object file, in a single program and with no intermediate
 * files, so it compiles much faster than Microsoft C, but its code is larger
 * and slower, since it does very little optimization.
 *
 * Its object files follow Microsoft C 4.00's small model conventions (the
 * same segments, names, calling sequence, and long arithmetic routines), so
 * they link with that compiler's libraries and object files:
 *
 *      BDC /I\TOOLS\INCLUDE HELLO.C
 *      LINK4 HELLO,HELLO.NE,NUL,\TOOLS\LIB\,HELLO.DEF
 *      STUB HELLO.NE HELLO.EXE
 *
 * It accepts both old-style and prototype-style function definitions, and
 * comments that start with two slashes.  It doesn't support floating point,
 * bit fields, structures as arguments or return values, or initializers for
 * local arrays and structures, and it has only the small memory model.
 *
 * The modules are:
 *
 *      bdc.c   the command line, error messages, and the name pool
 *      pp.c    the preprocessor and tokens
 *      decl.c  declarations, initializers, and statements
 *      expr.c  expressions, which become trees
 *      gen.c   code generation, from one expression tree at a time
 *      obj.c   the object file
 *
 * It's written in the subset of C that both Microsoft C 4.00 and BDC itself
 * accept, so either can build it.  To build it, run "MAKE MAKEFILE" in this
 * folder.  It can also be built and run on another system, to work on it
 * (eg, cc -std=gnu89 -DHOST -w -o bdc *.c), which is how the repository's
 * tools/bdc/test.sh tests it; tools/bdc/mkbdc.sh rebuilds BDC.EXE.
 */

#include "bdc.h"

#ifdef HOST
#include <unistd.h>
#endif

int nerr;
char pool[POOLSZ];              /* names and macro bodies */
int pooltop;
int keeppool;                   /* set when the pool can't be released */

static char objname[PATHSZ];
#ifdef HOST
int stats[12];
#endif
static char dtext[128];

/*
 * Reports an error at the current line.
 */
void error(msg, arg)
char *msg, *arg;
{
    printf("%s(%d) : error: ", curfile(), curline());
    printf(msg, arg);
    printf("\n");
    if (++nerr >= 25) fatal("too many errors", "");
}

/*
 * Reports an error that ends the compilation.
 */
void fatal(msg, arg)
char *msg, *arg;
{
    printf("%s(%d) : fatal error: ", curfile(), curline());
    printf(msg, arg);
    printf("\n");
    objend();
    unlink(objname);
    exit(1);
}

/*
 * Saves a string in the pool.
 */
char *psave(s)
char *s;
{
    int n;
    char *p;

    n = strlen(s) + 1;
    if (pooltop + n > POOLSZ) fatal("out of name space", "");
    p = pool + pooltop;
    strcpy(p, s);
    pooltop += n;
    return p;
}

int hashstr(s)
char *s;
{
    int h;

    h = 0;
    while (*s) h = h * 3 + *s++;
    return h & 255;
}

static void syntax()
{
    printf("Syntax error\n");
    exit(1);
}

main(argc, argv)
int argc;
char **argv;
{
    int i, n;
    char *a, *p, *src, *out, *first;

    src = 0;
    out = 0;
    first = 0;
    for (i = 1; i < argc; i++) {
        a = argv[i];
#ifdef HOST
        if (*a == '-') {
#else
        if (*a == '-' || *a == '/') {
#endif
            switch (a[1]) {
            case 'I':
            case 'i':
                p = a + 2;
                if (!*p && i + 1 < argc) p = argv[++i];
                if (!*p || ninc >= NINC) syntax();
                incdirs[ninc++] = p;
                break;
            case 'D':
            case 'd':
                p = a + 2;
                n = 0;
                while (*p && *p != '=' && n < 120) dtext[n++] = *p++;
                if (!n) syntax();
                if (*p == '=') p++;
                else p = "1";
                dtext[n++] = ' ';
                while (*p && n < 126) dtext[n++] = *p++;
                dtext[n] = 0;
                define(dtext);
                break;
            case 'F':
            case 'f':
                if (!a[3]) syntax();
                if (a[2] == 'o' || a[2] == 'O') out = a + 3;
                else if (a[2] == 'I' || a[2] == 'i') first = a + 3;
                else syntax();
                break;
            case 'c':
            case 'C':
                if (a[2]) syntax();
                break;
            default:
                syntax();
            }
        } else if (!src) src = a;
        else syntax();
    }
    if (!src) syntax();

    /*
     * Without /Fo, the object file has the source file's name, and goes in
     * the current directory.
     */
    if (out) strcpy(objname, out);
    else {
        a = src;
        for (p = src; *p; p++) {
            if (*p == '\\' || *p == '/' || *p == ':') a = p + 1;
        }
        n = 0;
        while (*a && *a != '.' && n < 64) objname[n++] = *a++;
        strcpy(objname + n, ".obj");
    }

    define("MSDOS 1");
    define("M_I86 1");
    define("M_I86SM 1");
    initdecl();
    if (!openfile(src, 0)) {
        printf("Unable to find %s\n", src);
        exit(1);
    }
    if (first && !openfile(first, 0)) {
        printf("Unable to find %s\n", first);
        exit(1);
    }
    objbegin(objname, src);
    gettok();
    while (tok != T_EOF) extdecl();
    objend();
#ifdef HOST
    if (getenv("BDCSTATS")) {
        printf("globals %d locals %d types %d pool %d code %d fixups %d "
               "patches %d labels %d nodes %d ptypes %d\n", stats[0], stats[1],
               stats[2], stats[3], stats[4], stats[5], stats[6], stats[7],
               stats[8], stats[9]);
    }
#endif
    if (nerr) {
        unlink(objname);
        exit(1);
    }
    exit(0);
}
