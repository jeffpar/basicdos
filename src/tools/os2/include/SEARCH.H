/***
*search.h - declarations for searcing/sorting routines
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This file contains the declarations for the sorting and
*	searching routines.
*	[System V]
*
****/


#ifndef _SIZE_T_DEFINED
typedef unsigned int size_t;
#define _SIZE_T_DEFINED
#endif


/* function prototypes */

void * _cdecl lsearch(const void *, void  *, unsigned int *, unsigned int,
	int (_cdecl *)(const void *, const void *));
void * _cdecl lfind(const void *, const void *, unsigned int *, unsigned int,
	int (_cdecl *)(const void *, const void *));
void * _cdecl bsearch(const void *, const void *, size_t, size_t,
	int (_cdecl *)(const void *, const void *));
void _cdecl qsort(void *, size_t, size_t, int (_cdecl *)(const void *,
	const void *));
