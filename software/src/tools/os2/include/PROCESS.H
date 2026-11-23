/***
*process.h - definition and declarations for process control functions
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This file defines the modeflag values for spawnxx calls.
*	Only P_WAIT and P_OVERLAY are currently implemented on MS-DOS.
*	Also contains the function argument declarations for all
*	process control related routines.
*
****/


/* modeflag values for spawnxx routines */

#ifndef _MT
extern int _cdecl _p_overlay;
#endif

#define P_WAIT		0
#define P_NOWAIT	1
#ifdef	_MT
#define P_OVERLAY	2
#else
#define P_OVERLAY	_p_overlay
#endif
#define OLD_P_OVERLAY	2
#define P_NOWAITO	3
#define P_DETACH	4


/* Action Codes used with Cwait() */

#define WAIT_CHILD 0
#define WAIT_GRANDCHILD 1


/* function prototypes */

#ifdef _MT
int _cdecl _beginthread (void (_cdecl *) (void *), unsigned, void *);
void _cdecl _endthread(void);
#endif
void _cdecl abort(void);
void _cdecl _cexit(void);
void _cdecl _c_exit(void);
int _cdecl cwait(int *, int, int);
int _cdecl execl(const char *, const char *, ...);
int _cdecl execle(const char *, const char *, ...);
int _cdecl execlp(const char *, const char *, ...);
int _cdecl execlpe(const char *, const char *, ...);
int _cdecl execv(const char *, const char * const *);
int _cdecl execve(const char *, const char * const *, const char * const *);
int _cdecl execvp(const char *, const char * const *);
int _cdecl execvpe(const char *, const char * const *, const char * const *);
void _cdecl exit(int);
void _cdecl _exit(int);
int _cdecl getpid(void);
int _cdecl spawnl(int, const char *, const char *, ...);
int _cdecl spawnle(int, const char *, const char *, ...);
int _cdecl spawnlp(int, const char *, const char *, ...);
int _cdecl spawnlpe(int, const char *, const char *, ...);
int _cdecl spawnv(int, const char *, const char * const *);
int _cdecl spawnve(int, const char *, const char * const *,
	const char * const *);
int _cdecl spawnvp(int, const char *, const char * const *);
int _cdecl spawnvpe(int, const char *, const char * const *,
	const char * const *);
int _cdecl system(const char *);
int _cdecl wait(int *);
