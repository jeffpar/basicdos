/***
*direct.h - function declarations for directory handling/creation
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This include file contains the function declarations for the library
*	functions related to directory handling and creation.
*
****/


#ifndef _SIZE_T_DEFINED
typedef unsigned int size_t;
#define _SIZE_T_DEFINED
#endif

/* function prototypes */

int _cdecl chdir(const char *);
int _cdecl _chdrive(int);
char * _cdecl  getcwd(char *, int);
char * _cdecl  _getdcwd(int, char *, int);
int _cdecl _getdrive(void);
int _cdecl mkdir(const char *);
int _cdecl rmdir(const char *);
