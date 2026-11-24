/***
*setjmp.h - definitions/declarations for setjmp/longjmp routines
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This file defines the machine-dependent buffer used by
*	setjmp/longjmp to save and restore the program state, and
*	declarations for those routines.
*	[ANSI/System V]
*
*******************************************************************************/


/* define the buffer type for holding the state information */

#define _JBLEN	9  /* bp, di, si, sp, ret addr, ds */

#ifndef _JMP_BUF_DEFINED
typedef  int  jmp_buf[_JBLEN];
#define _JMP_BUF_DEFINED
#endif


/* function prototypes */

int _cdecl setjmp(jmp_buf);
void _cdecl longjmp(jmp_buf, int);
