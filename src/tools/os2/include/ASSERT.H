/***
*assert.h - define the assert macro
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	Defines the assert(exp) macro.
*	[ANSI/System V]
*
****/


#undef	assert

#ifdef NDEBUG

#define assert(exp)

#else

void _cdecl _assert(void *, void *, unsigned);
#define assert(exp) \
	( (exp) ? (void) 0 : _assert(#exp, __FILE__, __LINE__) )

#endif /* NDEBUG */
