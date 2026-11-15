/*
 * BDC: BASIC-DOS C Compiler
 *
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * Definitions shared by the compiler's modules (see bdc.c for an overview).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Table sizes.  Everything is a fixed table, because the compiler is a small
 * model program whose data, stack, and heap share 64K.
 */
#define NSYM    520             /* symbols (globals up, locals down) */
#define NHASH   64              /* symbol and macro hash chains */
#define NTYPE   320             /* types */
#define NPTYPE  240             /* prototype parameter types */
#define NNODE   200             /* expression nodes (per expression) */
#define POOLSZ  9000           /* names and macro bodies */
#define NMAC    300             /* macros */
#define MBUFSZ  1200            /* macro arguments and expansions */
#define LINESZ  512             /* a source line (with continuations) */
#define TOKSZ   512             /* a string literal */
#define NAMELEN 32              /* significant characters of a name, + 1 */
#define NTEXT   16              /* nested macro expansions */
#define NFILE   6               /* nested include files */
#define NIF     24              /* nested #if directives */
#define NINC    6               /* include directories */
#define NPAR    16              /* parameters of a function definition */
#define NMOD    24              /* declarator modifiers */
#define CODESZ  6000           /* code of one function */
#define NFIX    300             /* fixups of one function */
#define NLAB    240             /* labels of one function */
#define NPATCH  300             /* jumps of one function */
#define NCASE   120             /* cases of nested switch statements */
#define NGOTO   24              /* goto labels of one function */
#define NARG    24              /* arguments of a call */
#ifdef HOST
#define PATHSZ  1024            /* a file's path */
#else
#define PATHSZ  100
#endif

/*
 * Tokens.  A single-character token is the character itself.
 */
#define T_EOF   0
#define T_ID    256
#define T_NUM   257
#define T_STR   258
#define T_EOL   259             /* end of a directive's line */
#define T_EQ    260
#define T_NE    261
#define T_LE    262
#define T_GE    263
#define T_SHL   264
#define T_SHR   265
#define T_ANDAND 266
#define T_OROR  267
#define T_INC   268
#define T_DEC   269
#define T_ARROW 270
#define T_ELLIPSIS 271
#define T_ASGOP 272             /* an operator followed by "="; see tokval */

#define K_AUTO  300             /* keywords, starting with storage classes */
#define K_REGISTER 301
#define K_STATIC 302
#define K_EXTERN 303
#define K_TYPEDEF 304
#define K_CONST 305             /* type keywords, through K_ENUM */
#define K_VOLATILE 306
#define K_IGNORE 307            /* cdecl, near, far, etc */
#define K_UNSIGNED 308
#define K_SIGNED 309
#define K_SHORT 310
#define K_LONG  311
#define K_INT   312
#define K_CHAR  313
#define K_VOID  314
#define K_FLOAT 315
#define K_DOUBLE 316
#define K_STRUCT 317
#define K_UNION 318
#define K_ENUM  319
#define K_BREAK 320
#define K_CASE  321
#define K_CONTINUE 322
#define K_DEFAULT 323
#define K_DO    324
#define K_ELSE  325
#define K_FOR   326
#define K_GOTO  327
#define K_IF    328
#define K_RETURN 329
#define K_SIZEOF 330
#define K_SWITCH 331
#define K_WHILE 332

/*
 * Types.  The first eight types are the basic types, in the same order as
 * their kinds, so a basic type's number is also its kind.
 */
#define K_TVOID 1
#define K_TCHAR 2
#define K_UCHAR 3
#define K_TINT  4
#define K_UINT  5
#define K_TLONG 6
#define K_ULONG 7
#define K_FLT   8
#define K_PTR   9
#define K_ARRAY 10
#define K_FUNC  11
#define K_STR   12              /* struct or union */

#define T_VOID  1
#define T_CHAR  2
#define T_UCHAR 3
#define T_INT   4
#define T_UINT  5
#define T_LONG  6
#define T_ULONG 7
#define T_DOUBLE 8
#define T_FUNCINT 9             /* function returning int */
#define T_PCHAR 10              /* pointer to char */

#define TF_BYTE 1               /* struct with byte alignment */
#define TF_UNION 2

struct type {
    char kind;
    char flags;
    int base;                   /* pointer, array, function: the type inside */
    unsigned size;              /* size in bytes (0 if incomplete) */
    int aux;                    /* array: elements; function: prototype */
    int ptr;                    /* the type that points to this one, or 0 */
};

/*
 * Symbols
 */
#define NS_ORD  0               /* ordinary names */
#define NS_TAG  1               /* struct, union, and enum tags */
#define NS_MEM  2               /* members (ext is the struct's type) */

#define C_KW    1               /* keyword (val is its token) */
#define C_GLOBAL 2              /* variable or function with a fixed address */
#define C_AUTO  3               /* local or parameter (val is BP offset) */
#define C_TYPEDEF 4
#define C_ENUM  5               /* enumeration constant (val is its value) */
#define C_TAG   6
#define C_MEMBER 7              /* val is its offset */

#define SF_DEF  1               /* defined here (seg and val are valid) */
#define SF_STATIC 2

#define SC_AUTO 1
#define SC_STATIC 2
#define SC_EXTERN 3
#define SC_TYPEDEF 4

#define SEG_TEXT 1              /* the object file's segment numbers */
#define SEG_DATA 2
#define SEG_CONST 3
#define SEG_BSS 4

struct sym {
    char *name;
    int type;
    char cls;
    char ns;
    char hash;
    char flags;
    char seg;
    char pad;
    unsigned val;
    int ext;                    /* external number, if referenced as one */
    int next;                   /* next symbol in the hash chain */
};

/*
 * Expression nodes
 */
#define N_CONST 1               /* val */
#define N_ADDRG 2               /* address of sym (or of segment left) + val */
#define N_ADDRL 3               /* address of BP + val */
#define N_DEREF 4               /* the object at address left */
#define N_ASSIGN 5
#define N_ASGOP 6               /* sym is the operator */
#define N_PREINC 7              /* val is the amount */
#define N_PREDEC 8
#define N_POSTINC 9
#define N_POSTDEC 10
#define N_NEG   11
#define N_NOT   12
#define N_LNOT  13
#define N_LAND  14
#define N_LOR   15
#define N_COND  16              /* left ? right->left : right->right */
#define N_PAIR  17
#define N_COMMA 18
#define N_CALL  19              /* left: function, right: first N_ARG */
#define N_ARG   20              /* left: argument, right: next N_ARG */
#define N_CAST  21
#define N_ADD   22              /* binary operators, in this order */
#define N_SUB   23
#define N_MUL   24
#define N_DIV   25
#define N_MOD   26
#define N_AND   27
#define N_OR    28
#define N_XOR   29
#define N_SHL   30
#define N_SHR   31
#define N_EQ    32              /* comparisons: val is 1 if unsigned, */
#define N_NE    33              /* sym is 1 if long */
#define N_LT    34
#define N_GE    35
#define N_LE    36
#define N_GT    37

struct node {
    char op;
    char pad;
    int type;
    int left;
    int right;
    int sym;
    long val;
};

/*
 * Fixups (see obj.c)
 */
#define F_SEG   1               /* offset in one of this module's segments */
#define F_EXT   2               /* offset of an external */
#define F_CALL  3               /* self-relative offset of an external */
#define F_REL   4               /* self-relative offset in this code */

struct fix {
    unsigned off;
    int kind;
    unsigned a;
};

/*
 * bdc.c
 */
extern int nerr;
extern char pool[];
extern int pooltop;
extern int keeppool;
#ifdef HOST
extern int stats[];
#define STAT(i, v)  if ((v) > stats[i]) stats[i] = (v)
#else
#define STAT(i, v)
#endif
void error();
void fatal();
char *psave();
int hashstr();

/*
 * pp.c
 */
extern int tok;
extern long tokval;
extern int toktype;
extern int toksym;
extern int toklen;
extern char tokstr[];
extern int ppmode;
extern char *incdirs[];
extern int ninc;
void gettok();
void define();
int openfile();
char *curfile();
int curline();

/*
 * decl.c
 */
extern struct sym syms[];
extern int nglob, nloc, level;
extern struct type types[];
extern int ntype;
extern int ptypes[];
extern int nptype;
extern int rettype;
extern int brklab, contlab;
void initdecl();
void extdecl();
void expect();
int lookup();
int lookupmem();
int newsym();
int newglobal();
int ptrto();
int istypename();
int typename();
unsigned tsize();

/*
 * expr.c
 */
extern struct node nodes[];
extern int nodetop;
extern int havepend, pendsym;
extern char pendname[];
extern int ininit;
int expr();
int assign();
int fullexpr();
long constexpr();
int rvalue();
int cast();
int mk();
int konst();
long norm();

/*
 * gen.c
 */
extern int locoff, minloc;
void gbegin();
void gend();
void gexpr();
void gjump();
void gcase();
void gretlab();
int newlab();
void deflab();
void jmp();
int symfix();

/*
 * obj.c
 */
extern unsigned textoff, dataoff, constoff, bssoff;
void objbegin();
void objend();
int objext();
void objpub();
void objcode();
void dput();
void dfix();
void dflush();
