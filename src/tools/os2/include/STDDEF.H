/***
*stddef.h - definitions/declarations for common constants, types, variables
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This file contains definitions and declarations for some commonly
*	used constants, types, and variables.
*	[ANSI]
*
****/


/* define NULL pointer value */

#define  NULL	 0


/* declare reference to errno */

#ifdef	_MT
extern unsigned * _cdecl _errno(void);
#define errno	(*_errno())
#else
extern int _cdecl errno;
#endif


/* define the implementation dependent size types */

#ifndef _PTRDIFF_T_DEFINED
typedef int ptrdiff_t;
#define _PTRDIFF_T_DEFINED
#endif

#ifndef _SIZE_T_DEFINED
typedef unsigned int size_t;
#define _SIZE_T_DEFINED
#endif


#ifdef	_MT

/* define pointer to thread id value */
extern unsigned * _cdecl __threadid(void);
#define _threadid   (__threadid())

#endif
