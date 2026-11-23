/***
*stdio.h - definitions/declarations for standard I/O routines
*
*	Copyright (c) 1985-1990, Microsoft Corporation. All rights reserved.
*
*Purpose:
*	This file defines the structures, values, macros, and functions
*	used by the level 2 I/O ("standard I/O") routines.
*	[ANSI/System V]
*
****/


/* ensure proper alignment of struct fields */

#pragma pack(4)


#ifndef _SIZE_T_DEFINED
typedef unsigned int size_t;
#define _SIZE_T_DEFINED
#endif

#ifndef _VA_LIST_DEFINED
typedef char *va_list;
#define _VA_LIST_DEFINED
#endif


/* buffered I/O macros */

#define BUFSIZ	512
#ifdef	_MT
#define _NFILE	40
#else
#define _NFILE	20
#endif
#define EOF	(-1)

#ifndef _FILE_DEFINED
struct _iobuf {
	char *_ptr;
	int   _cnt;
	char *_base;
	int   _flag;
	int   _file;
	int   _charbuf;
	int   _bufsiz;
	int   __tmpnum;
	};
typedef struct _iobuf FILE;
#define _FILE_DEFINED
#endif

/* P_tmpnam: Directory where temporary files may be created.
 * L_tmpnam size =  size of P_tmpdir
 *	+ 1 (in case P_tmpdir does not end in "\\")
 *	+ 6 (for the temp number string)
 *	+ 1 (for the null terminator)
 */

#define P_tmpdir "\\"
#define L_tmpnam sizeof(P_tmpdir)+8

#define SEEK_CUR 1
#define SEEK_END 2
#define SEEK_SET 0

#define FILENAME_MAX 63
#define FOPEN_MAX 20
#define SYS_OPEN 20
#define TMP_MAX 32767


/* define NULL pointer value */

#define NULL	0


/* declare _iob[] array */

#ifndef _STDIO_DEFINED
extern FILE _cdecl _iob[];
#endif


/* define file position type */

#ifndef _FPOS_T_DEFINED
typedef long fpos_t;
#define _FPOS_T_DEFINED
#endif


#define stdin  (&_iob[0])
#define stdout (&_iob[1])
#define stderr (&_iob[2])


#define _IOREAD 	0x0001
#define _IOWRT		0x0002

#define _IOFBF		0x0000
#define _IOLBF		0x0040
#define _IONBF		0x0004

#define _IOMYBUF	0x0008
#define _IOEOF		0x0010
#define _IOERR		0x0020
#define _IOSTRG 	0x0040
#define _IORW		0x0080


/* function prototypes */

#ifndef _STDIO_DEFINED
int _cdecl _filbuf(FILE *);
int _cdecl _flsbuf(int, FILE *);
FILE * _cdecl _fsopen(const char *, const char *, int);
void _cdecl clearerr(FILE *);
int _cdecl fclose(FILE *);
int _cdecl fcloseall(void);
FILE * _cdecl fdopen(int, const char *);
int _cdecl feof(FILE *);
int _cdecl ferror(FILE *);
int _cdecl fflush(FILE *);
int _cdecl fgetc(FILE *);
int _cdecl fgetchar(void);
int _cdecl fgetpos(FILE *, fpos_t *);
char * _cdecl fgets(char *, int, FILE *);
int _cdecl fileno(FILE *);
int _cdecl flushall(void);
FILE * _cdecl fopen(const char *, const char *);
int _cdecl fprintf(FILE *, const char *, ...);
int _cdecl fputc(int, FILE *);
int _cdecl fputchar(int);
int _cdecl fputs(const char *, FILE *);
size_t _cdecl fread(void *, size_t, size_t, FILE *);
FILE * _cdecl freopen(const char *, const char *, FILE *);
int _cdecl fscanf(FILE *, const char *, ...);
int _cdecl fsetpos(FILE *, const fpos_t *);
int _cdecl fseek(FILE *, long, int);
long _cdecl ftell(FILE *);
size_t _cdecl fwrite(const void *, size_t, size_t, FILE *);
int _cdecl getc(FILE *);
int _cdecl getchar(void);
char * _cdecl gets(char *);
int _cdecl getw(FILE *);
void _cdecl perror(const char *);
int _cdecl _pclose(FILE *);
FILE * _cdecl _popen(const char *, const char *);
int _cdecl printf(const char *, ...);
int _cdecl putc(int, FILE *);
int _cdecl putchar(int);
int _cdecl puts(const char *);
int _cdecl putw(int, FILE *);
int _cdecl remove(const char *);
int _cdecl rename(const char *, const char *);
void _cdecl rewind(FILE *);
int _cdecl rmtmp(void);
int _cdecl scanf(const char *, ...);
void _cdecl setbuf(FILE *, char *);
int _cdecl setvbuf(FILE *, char *, int, size_t);
int _cdecl sprintf(char *, const char *, ...);
int _cdecl sscanf(const char *, const char *, ...);
char * _cdecl tempnam(char *, char *);
FILE * _cdecl tmpfile(void);
char * _cdecl tmpnam(char *);
int _cdecl ungetc(int, FILE *);
int _cdecl unlink(const char *);
int _cdecl vfprintf(FILE *, const char *, va_list);
int _cdecl vprintf(const char *, va_list);
int _cdecl vsprintf(char *, const char *, va_list);
#define _STDIO_DEFINED
#endif


/* macro definitions */

#define feof(_stream)	  ((_stream)->_flag & _IOEOF)
#define ferror(_stream)   ((_stream)->_flag & _IOERR)
#define fileno(_stream)   ((_stream)->_file)
#define getc(_stream)	  (--(_stream)->_cnt >= 0 ? 0xff & *(_stream)->_ptr++ \
	: _filbuf(_stream))
#define putc(_c,_stream)  (--(_stream)->_cnt >= 0 \
	? 0xff & (*(_stream)->_ptr++ = (char)(_c)) :  _flsbuf((_c),(_stream)))
#define getchar()	  getc(stdin)
#define putchar(_c)	  putc((_c),stdout)

#ifdef _MT
#undef	getc
#undef	putc
#undef	getchar
#undef	putchar
#endif


/* restore default alignment */

#pragma pack()
