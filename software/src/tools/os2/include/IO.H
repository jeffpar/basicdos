/***
*io.h - declarations for low-level file handling and I/O functions
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This file contains the function declarations for the low-level
*	file handling and I/O functions.
*
****/


/* function prototypes */

int _cdecl access(const char *, int);
int _cdecl chmod(const char *, int);
int _cdecl chsize(int, long);
int _cdecl close(int);
int _cdecl creat(const char *, int);
int _cdecl dup(int);
int _cdecl dup2(int, int);
int _cdecl eof(int);
long _cdecl filelength(int);
int _cdecl isatty(int);
int _cdecl locking(int, int, long);
long _cdecl lseek(int, long, int);
char * _cdecl mktemp(char *);
int _cdecl open(const char *, int, ...);
int _cdecl _pipe(int *, unsigned int, int);
int _cdecl read(int, void *, unsigned int);
int _cdecl remove(const char *);
int _cdecl rename(const char *, const char *);
int _cdecl setmode(int, int);
int _cdecl sopen(const char *, int, int, ...);
long _cdecl tell(int);
int _cdecl umask(int);
int _cdecl unlink(const char *);
int _cdecl write(int, const void *, unsigned int);
