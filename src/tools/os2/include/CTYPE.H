/***
*ctype.h - character conversion macros and ctype macros
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	Defines macros for character classification/conversion.
*	[ANSI/System V]
*
****/


/*
 * This declaration allows the user access to the ctype look-up
 * array _ctype defined in ctype.obj by simply including ctype.h
 */

extern unsigned char _cdecl _ctype[];


/* set bit masks for the possible character types */

#define _UPPER		0x1	/* upper case letter */
#define _LOWER		0x2	/* lower case letter */
#define _DIGIT		0x4	/* digit[0-9] */
#define _SPACE		0x8	/* tab, carriage return, newline, */
				/* vertical tab or form feed */
#define _PUNCT		0x10	/* punctuation character */
#define _CONTROL	0x20	/* control character */
#define _BLANK		0x40	/* space char */
#define _HEX		0x80	/* hexadecimal digit */


/* character classification function prototypes */

#ifndef _CTYPE_DEFINED
int _cdecl  isalpha(int);
int _cdecl  isupper(int);
int _cdecl  islower(int);
int _cdecl  isdigit(int);
int _cdecl  isxdigit(int);
int _cdecl  isspace(int);
int _cdecl  ispunct(int);
int _cdecl  isalnum(int);
int _cdecl  isprint(int);
int _cdecl  isgraph(int);
int _cdecl  iscntrl(int);
int _cdecl  toupper(int);
int _cdecl  tolower(int);
int _cdecl  _tolower(int);
int _cdecl  _toupper(int);
int _cdecl  isascii(int);
int _cdecl  toascii(int);
int _cdecl  iscsymf(int);
int _cdecl  iscsym(int);
#define _CTYPE_DEFINED
#endif

/* the character classification macro definitions */

#define isalpha(_c)	( (_ctype+1)[_c] & (_UPPER|_LOWER) )
#define isupper(_c)	( (_ctype+1)[_c] & _UPPER )
#define islower(_c)	( (_ctype+1)[_c] & _LOWER )
#define isdigit(_c)	( (_ctype+1)[_c] & _DIGIT )
#define isxdigit(_c)	( (_ctype+1)[_c] & _HEX )
#define isspace(_c)	( (_ctype+1)[_c] & _SPACE )
#define ispunct(_c)	( (_ctype+1)[_c] & _PUNCT )
#define isalnum(_c)	( (_ctype+1)[_c] & (_UPPER|_LOWER|_DIGIT) )
#define isprint(_c)	( (_ctype+1)[_c] & (_BLANK|_PUNCT|_UPPER|_LOWER|_DIGIT) )
#define isgraph(_c)	( (_ctype+1)[_c] & (_PUNCT|_UPPER|_LOWER|_DIGIT) )
#define iscntrl(_c)	( (_ctype+1)[_c] & _CONTROL )
#ifndef NO_EXT_KEYS
#define toupper(_c)	( (islower(_c)) ? _toupper(_c) : (_c) )
#define tolower(_c)	( (isupper(_c)) ? _tolower(_c) : (_c) )
#endif
#define _tolower(_c)	( (_c)-'A'+'a' )
#define _toupper(_c)	( (_c)-'a'+'A' )
#define isascii(_c)	( (unsigned)(_c) < 0x80 )
#define toascii(_c)	( (_c) & 0x7f )

/* MS C version 2.0 extended ctype macros */

#define iscsymf(_c)	(isalpha(_c) || ((_c) == '_'))
#define iscsym(_c)	(isalnum(_c) || ((_c) == '_'))
