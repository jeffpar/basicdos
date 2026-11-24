/***
*stdlib.h - declarations/definitions for commonly used library functions
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This include file contains the function declarations for
*	commonly used library functions which either don't fit somewhere
*	else, or, like toupper/tolower, can't be declared in the normal
*	place for other reasons.
*	[ANSI]
*
****/


#ifndef _SIZE_T_DEFINED
typedef unsigned int size_t;
#define _SIZE_T_DEFINED
#endif


/* define NULL pointer value */

#define NULL	0


/* definition of the return type for the onexit() function */

#define EXIT_SUCCESS	0
#define EXIT_FAILURE	1


#ifndef _ONEXIT_T_DEFINED
typedef int (_cdecl * _cdecl onexit_t)();
#define _ONEXIT_T_DEFINED
#endif


/* Data structure definitions for div and ldiv runtimes. */

#ifndef _DIV_T_DEFINED

typedef struct _div_t {
	int quot;
	int rem;
} div_t;

typedef struct _ldiv_t {
	long quot;
	long rem;
} ldiv_t;

#define _DIV_T_DEFINED
#endif

/* Maximum value that can be returned by the rand function. */

#define RAND_MAX 0x7fff


/* min and max macros */

#define max(a,b)	(((a) > (b)) ? (a) : (b))
#define min(a,b)	(((a) < (b)) ? (a) : (b))


/* sizes for buffers used by the _makepath() and _splitpath() functions.
 * note that the sizes include space for 0-terminator
 */

#define _MAX_PATH	260	/* max. length of full pathname */
#define _MAX_DRIVE	3	/* max. length of drive component */
#define _MAX_DIR	256	/* max. length of path component */
#define _MAX_FNAME	256	/* max. length of file name component */
#define _MAX_EXT	256	/* max. length of extension component */

/* external variable declarations */

#ifdef	_MT
extern unsigned * _cdecl _errno(void);
extern unsigned * _cdecl __doserrno(void);
#define errno	    (*_errno())
#define _doserrno   (*__doserrno())
#else
extern int _cdecl errno;		/* XENIX style error number */
extern int _cdecl _doserrno;		/* MS-DOS system error value */
#endif
extern char * _cdecl sys_errlist[];	/* perror error message table */
extern int _cdecl sys_nerr;		/* # of entries in sys_errlist table */

extern char ** _cdecl environ;		/* pointer to environment table */
extern int _cdecl _fmode;		/* default file translation mode */
extern int _cdecl _fileinfo;		/* open file info mode (for spawn) */

extern unsigned int _cdecl _psp;	/* Program Segment Prefix */


/* DOS major/minor version numbers */

extern unsigned int _cdecl _osmajor;
extern unsigned int _cdecl _osminor;

#define DOS_MODE	0	/* Real Address Mode */
#define OS2_MODE	1	/* Protected Address Mode */

extern unsigned char _cdecl _osmode;


/* function prototypes */

void   _cdecl abort(void);
int    _cdecl abs(int);
int    _cdecl atexit(void (_cdecl *)(void));
double _cdecl atof(const char *);
int    _cdecl atoi(const char *);
long   _cdecl atol(const char *);
void * _cdecl bsearch(const void *, const void *, size_t, size_t,
	int (_cdecl *)(const void *, const void *));
void * _cdecl calloc(size_t, size_t);
div_t  _cdecl div(int, int);
char * _cdecl ecvt(double, int, int *, int *);
void   _cdecl exit(int);
void   _cdecl _exit(int);
char * _cdecl fcvt(double, int, int *, int *);
void   _cdecl free(void *);
char * _cdecl  _fullpath(char *, const char *, size_t);
char * _cdecl gcvt(double, int, char *);
char * _cdecl getenv(const char *);
char * _cdecl itoa(int, char *, int);
long   _cdecl labs(long);
ldiv_t _cdecl ldiv(long, long);
unsigned long _cdecl _lrotl(unsigned long, int);
unsigned long _cdecl _lrotr(unsigned long, int);
char * _cdecl ltoa(long, char *, int);
void   _cdecl _makepath(char *, const char *, const char *, const char *,
	const char *);
void * _cdecl malloc(size_t);
onexit_t _cdecl onexit(onexit_t);
void   _cdecl perror(const char *);
int    _cdecl putenv(const char *);
void   _cdecl qsort(void *, size_t, size_t, int (_cdecl *)(const void *,
	const void *));
unsigned int _cdecl _rotl(unsigned int, int);
unsigned int _cdecl _rotr(unsigned int, int);
int    _cdecl rand(void);
void * _cdecl realloc(void *, size_t);
void   _cdecl _searchenv(const char *, const char *, char *);
void   _cdecl _splitpath(const char *, char *, char *, char *, char *);
void   _cdecl srand(unsigned int);
double _cdecl strtod(const char *, char **);
long   _cdecl strtol(const char *, char **, int);
unsigned long _cdecl strtoul(const char *, char **, int);
void   _cdecl swab(char *, char *, int);
int    _cdecl system(const char *);
char * _cdecl ultoa(unsigned long, char *, int);

#ifndef tolower 	/* tolower has been undefined - use function */
int _cdecl tolower(int);
#endif	/* tolower */

#ifndef toupper 	/* toupper has been undefined - use function */
int    _cdecl toupper(int);
#endif	/* toupper */
