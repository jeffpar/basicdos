/***
*memory.h - declarations for buffer (memory) manipulation routines
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This include file contains the function declarations for the
*	buffer (memory) manipulation routines.
*	[System V]
*
****/


#ifndef _SIZE_T_DEFINED
typedef unsigned int size_t;
#define _SIZE_T_DEFINED
#endif


/* function prototypes */

void * _cdecl memccpy(void *, const void *, int, unsigned int);
void * _cdecl memchr(const void *, int, size_t);
int _cdecl memcmp(const void *, const void *, size_t);
void * _cdecl memcpy(void *, const void *, size_t);
int _cdecl memicmp(const void *, const void *, unsigned int);
void * _cdecl memset(void *, int, size_t);
void _cdecl movedata(unsigned int, unsigned int, unsigned int, unsigned int,
	unsigned int);
