/***
*string.h - declarations for string manipulation functions
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This file contains the function declarations for the string
*	manipulation functions.
*	[ANSI/System V]
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
int _cdecl memicmp(const void *, const void *, unsigned int);
void * _cdecl memcpy(void *, const void *, size_t);
void * _cdecl memmove(void *, const void *, size_t);
void * _cdecl memset(void *, int, size_t);
void _cdecl movedata(unsigned int, unsigned int, unsigned int, unsigned int, unsigned int);

char * _cdecl strcat(char *, const char *);
char * _cdecl strchr(const char *, int);
int _cdecl strcmp(const char *, const char *);
int _cdecl strcmpi(const char *, const char *);
int _cdecl strcoll(const char *, const char *);
int _cdecl stricmp(const char *, const char *);
char * _cdecl strcpy(char *, const char *);
size_t _cdecl strcspn(const char *, const char *);
char * _cdecl strdup(const char *);
char * _cdecl _strerror(const char *);
char * _cdecl strerror(int);
size_t _cdecl strlen(const char *);
char * _cdecl strlwr(char *);
char * _cdecl strncat(char *, const char *, size_t);
int _cdecl strncmp(const char *, const char *, size_t);
int _cdecl strnicmp(const char *, const char *, size_t);
char * _cdecl strncpy(char *, const char *, size_t);
char * _cdecl strnset(char *, int, size_t);
char * _cdecl strpbrk(const char *, const char *);
char * _cdecl strrchr(const char *, int);
char * _cdecl strrev(char *);
char * _cdecl strset(char *, int);
size_t _cdecl strspn(const char *, const char *);
char * _cdecl strstr(const char *, const char *);
char * _cdecl strtok(char *, const char *);
char * _cdecl strupr(char *);
size_t _cdecl strxfrm (char *, const char *, size_t);
