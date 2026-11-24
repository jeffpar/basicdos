/*
 * BASIC-DOS SDK: declarations for 32-bit C programs (see CRT32.ASM)
 *
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * CRT32.OBJ is the startup code and library of a 32-bit C program for
 * BASIC-DOS: it calls main(argc, argv), where argv[0] is an empty string
 * (BASIC-DOS doesn't give a program its name), and its functions are DOS
 * calls.  A function that fails returns -1 (or for the find functions, a
 * nonzero value) and stores the DOS error code in doserr.
 */
#define STDIN   0
#define STDOUT  1
#define STDERR  2

#define ERR_NOFILE      2       /* DOS error codes */
#define ERR_NOPATH      3
#define ERR_BADDRIVE    15
#define ERR_NOFILES     18

/*
 * What findfirst() and findnext() store for each file (a DOS find block).
 */
#pragma pack(1)
struct find {
    char            reserved[21];
    char            attr;       /* attributes */
    unsigned short  time;       /* time and date of last write */
    unsigned short  date;
    unsigned long   size;
    char            name[13];   /* null-terminated */
};
#pragma pack()

extern int doserr;              /* error code of the last call that failed */

void exit(int code);
int open(char *name, int mode); /* mode 0 to read, 1 to write, 2 for both */
int close(int handle);
int read(int handle, char *buf, unsigned len);
int write(int handle, char *buf, unsigned len);
int findfirst(char *spec, int attr, struct find *pfind);
int findnext(struct find *pfind);
int switchar(void);             /* the system's switch character */
