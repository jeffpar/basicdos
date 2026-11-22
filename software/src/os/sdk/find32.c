/*
 * BASIC-DOS SDK: FIND32, a 32-bit C program
 *
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * Build it on BASIC-DOS (on an 80386, in protected mode) with the tools in
 * TOOLS\BIN, by running MAKE in this directory:
 *
 *      MAKE MAKEFILE
 *
 * which compiles it with CL386 (the Microsoft 386 C Compiler), assembles
 * the startup code and library (CRT32.ASM) with MASM 5.10B, and links them
 * with LINK386 (see FIND32.DEF) as an LE program.
 *
 * Usage: FIND32 [/C] [/I] [/N] [/V] string [files...]
 *
 * It's FIND.COM (see SRC\UTIL\MISC\FIND.ASM) without regular expressions
 * (/R), like FIND16 (see FIND16.ASM), but in C: it displays every line of
 * input (or of the files, which may include wildcards) that contains string,
 * which is the first argument that isn't a switch (quote it if it contains
 * spaces).  /C displays only the number of lines, /I ignores case, /N adds
 * line numbers, and /V selects lines that do NOT contain string.  The exit
 * code is 0 if any lines were selected, 1 if none, and 2 if an error
 * occurred.  Switches start with the system's switch character.
 */
#include "crt32.h"

#define MAXFILES    8           /* maximum file names on the command line */
#define LINE_MAX    256         /* maximum line length (including CR/LF) */
#define INBUF_LEN   512         /* input buffer size */
#define PATH_MAX    128         /* maximum path of a file name */
#define CTRLZ       0x1A        /* end of input */

static char swlist[] = "CINV";  /* the switches */
static int sw[4];               /* and whether each was specified */
#define swC sw[0]
#define swI sw[1]
#define swN sw[2]
#define swV sw[3]

static char *str;               /* the string, and its length */
static int slen;
static char *files[MAXFILES];
static int nfiles;
static int hin = STDIN;         /* input handle */
static int errcode;             /* exit code */
static char *prefix = "";       /* prefix for a line count (": " or "") */
static int inpos, inend;        /* next byte and end of data in inbuf */
static char inbuf[INBUF_LEN];
static char line[LINE_MAX];
static char path[PATH_MAX + 13];

static int length(char *s)
{
    int n = 0;

    while (s[n])
        n++;
    return n;
}

static int upper(int c)
{
    return c >= 'a' && c <= 'z'? c - ('a' - 'A') : c;
}

/*
 * If a write fails (eg, the command reading our output through a pipe has
 * ended), there's no point in continuing, so we exit.
 */
static void put(int handle, char *s, int len)
{
    if (write(handle, s, len) < 0)
        exit(errcode);
}

static void puts(char *s)
{
    put(STDOUT, s, length(s));
}

static void puterr(char *s)
{
    put(STDERR, s, length(s));
}

static void putnum(unsigned n)
{
    char buf[11];
    char *p = buf + sizeof(buf) - 1;

    *p = 0;
    do {
        *--p = (char)('0' + n % 10);
    } while (n /= 10);
    puts(p);
}

/*
 * Returns the next byte of input, or -1 if there's no more.  CTRLZ marks
 * the end of input, so we don't advance past it.
 */
static int getc(void)
{
    if (inpos >= inend) {
        inend = read(hin, inbuf, INBUF_LEN);
        inpos = 0;
        if (inend <= 0) {
            inend = 0;
            return -1;
        }
    }
    if (inbuf[inpos] == CTRLZ)
        return -1;
    return inbuf[inpos++];
}

/*
 * Reads the next line of input and returns its length, or 0 if there's no
 * more.  A line ends with LF, and a line without one (eg, the last line of
 * a file, or a line longer than LINE_MAX) gets CR/LF appended.
 */
static int readline(void)
{
    int c, len = 0;

    while (len < LINE_MAX - 2) {
        if ((c = getc()) < 0) {
            if (!len)
                return 0;
            break;
        }
        line[len++] = (char)c;
        if (c == '\n')
            return len;
    }
    line[len++] = '\r';
    line[len++] = '\n';
    return len;
}

static int match(int len)
{
    int i, j;

    for (i = 0; i <= len - slen; i++) {
        for (j = 0; j < slen; j++) {
            if (swI? upper(line[i + j]) != upper(str[j]) :
                     line[i + j] != str[j])
                break;
        }
        if (j == slen)
            return 1;
    }
    return 0;
}

/*
 * Displays the lines of the input that contain the string (or with /V,
 * those that don't), or with /C, their number.
 */
static void findlines(void)
{
    int len;
    unsigned lineno = 0, nsel = 0;

    while (len = readline()) {
        lineno++;
        if (match(len) == swV)
            continue;
        nsel++;
        errcode &= 2;           /* exit code 1 becomes 0 */
        if (swC)
            continue;
        if (swN) {
            puts("[");
            putnum(lineno);
            puts("]");
        }
        put(STDOUT, line, len);
    }
    if (swC) {
        puts(prefix);
        putnum(nsel);
        puts("\r\n");
    }
}

static void openerr(char *name)
{
    if (doserr == ERR_BADDRIVE)
        puterr("Invalid drive");
    else {
        puterr(doserr == ERR_NOFILE || doserr == ERR_NOPATH ||
               doserr == ERR_NOFILES? "Unable to find " : "Unable to open ");
        puterr(name);
    }
    puterr("\r\n");
    errcode = 2;
}

/*
 * Opens a file, displays its name and its matching lines, and closes it.
 */
static void dofile(char *name)
{
    if ((hin = open(name, 0)) < 0) {
        openerr(name);
        return;
    }
    inpos = inend = 0;
    puts("\r\n---------- ");
    puts(name);
    if (!swC)
        puts("\r\n");
    findlines();
    close(hin);
}

/*
 * Displays the matching lines of a file, or for a name with wildcards
 * (? and *), of every file that findfirst() and findnext() find; each of
 * those files' names replaces the name in a copy of the path.
 */
static void eachfile(char *name)
{
    int i, wild = 0, start = 0;
    struct find f;

    for (i = 0; name[i]; i++) {
        if (name[i] == '*' || name[i] == '?')
            wild = 1;
        if (name[i] == '\\' || name[i] == '/' || name[i] == ':')
            start = i + 1;
    }
    if (!wild) {
        dofile(name);
        return;
    }
    if (start > PATH_MAX || findfirst(name, 0, &f)) {
        openerr(name);
        return;
    }
    for (i = 0; i < start; i++)
        path[i] = name[i];
    do {
        for (i = 0; path[start + i] = f.name[i]; i++)
            ;
        dofile(path);
    } while (!findnext(&f));
}

int main(int argc, char **argv)
{
    int i, j, k;
    int swc = switchar();

    for (i = 1; i < argc; i++) {
        char *arg = argv[i];
        if (arg[0] == (char)swc) {
            /*
             * Every character after the switch char must be a switch.
             */
            for (j = 1; j == 1 || arg[j]; j++) {
                for (k = 0; swlist[k] && swlist[k] != upper(arg[j]); k++)
                    ;
                if (!swlist[k])
                    goto syntax;
                sw[k] = 1;
            }
        }
        else if (!str) {
            str = arg;
            slen = length(arg);
        }
        else if (nfiles < MAXFILES)
            files[nfiles++] = arg;
        else
            goto syntax;
    }
    if (!str) {
syntax: puterr("Syntax error\r\n");
        return 2;
    }
    errcode = 1;                /* assume no lines will be selected */
    if (!nfiles)
        findlines();            /* read STDIN */
    else {
        prefix = ": ";
        for (i = 0; i < nfiles; i++)
            eachfile(files[i]);
    }
    return errcode;
}
