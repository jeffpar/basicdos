/***
*varargs.h - XENIX style macros for variable argument functions
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This file defines XENIX style macros for accessing arguments of a
*	function which takes a variable number of arguments.
*	[System V]
*
****/


#ifndef _VA_LIST_DEFINED
typedef char _FAR_ *va_list;
#define _VA_LIST_DEFINED
#endif

/* define NULL pointer value */

#define  NULL	 0

#define va_dcl va_list va_alist;
#define va_start(ap) ap = (va_list)&va_alist
#define va_arg(ap,t) ((t _FAR_ *)(ap += sizeof(t)))[-1]
#define va_end(ap) ap = NULL
