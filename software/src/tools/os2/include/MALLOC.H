/***
*malloc.h - declarations and definitions for memory allocation functions
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	Contains the function declarations for memory allocation functions;
*	also defines manifest constants and types used by the heap routines.
*	[System V]
*
****/


#define _HEAPEMPTY	(-1)
#define _HEAPOK 	(-2)
#define _HEAPBADBEGIN	(-3)
#define _HEAPBADNODE	(-4)
#define _HEAPEND	(-5)
#define _HEAPBADPTR	(-6)
#define _FREEENTRY	0
#define _USEDENTRY	1

/* Define _HEAP_MAXREQ to be equal to (unsigned)( -sizeof(_heap_seg_desc)
 * - 2*sizeof(int) ) */

#define _HEAP_MAXREQ	0xFFFFFFD8


#ifndef _SIZE_T_DEFINED
typedef unsigned int size_t;
#define _SIZE_T_DEFINED
#endif


#ifndef _HEAPINFO_DEFINED
typedef struct _heapinfo {
	int * _pentry;
	size_t _size;
	int _useflag;
	} _HEAPINFO;
#define _HEAPINFO_DEFINED
#endif


/* external variable declarations */

extern unsigned int _cdecl _amblksiz;


/* function prototypes */

void * _cdecl alloca(size_t);
void * _cdecl calloc(size_t, size_t);
void * _cdecl _expand(void *, size_t);
void _cdecl free(void *);
int _cdecl _heapadd(void *, size_t);
int _cdecl _heapchk(void);
int _cdecl _heapmin(void);
int _cdecl _heapset(unsigned int);
int _cdecl _heapwalk(_HEAPINFO *);
void * _cdecl malloc(size_t);
size_t _cdecl _msize(void *);
void * _cdecl realloc(void *, size_t);
size_t _cdecl stackavail(void);
