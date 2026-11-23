/***
*dos.h - definitions for MS-DOS interface routines
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	Defines the structs and unions used for the direct DOS interface
*	routines; includes macros to access the segment and offset
*	values of far pointers, so that they may be used by the routines; and
*	provides function prototypes for direct DOS interface functions.
*
****/


/* ensure proper alignment of struct fields */

#pragma pack(4)


#ifndef _REGS_DEFINED

/* word registers */

struct WORDREGS {
	unsigned int eax;
	unsigned int ebx;
	unsigned int ecx;
	unsigned int edx;
	unsigned int esi;
	unsigned int edi;
	unsigned int cflag;
	};


/* byte registers */

struct BYTEREGS {
	unsigned short aw;		/* high 16-bits of eax */
	unsigned char al, ah;
	unsigned short bw;		/* high 16-bits of ebx */
	unsigned char bl, bh;
	unsigned short cw;		/* high 16-bits of ecx */
	unsigned char cl, ch;
	unsigned short dw;		/* high 16-bits of edx */
	unsigned char dl, dh;
	};


/* general purpose registers union -
 *  overlays the corresponding word and byte registers.
 */

union REGS {
	struct WORDREGS x;
	struct BYTEREGS h;
	};


/* segment registers */

struct SREGS {
	unsigned int es;
	unsigned int cs;
	unsigned int ss;
	unsigned int ds;
	};

#define _REGS_DEFINED

#endif


/* _dos_getdate/_dossetdate and _dos_gettime/_dos_settime structures */

#ifndef _DATETIME_T_DEFINED

struct dosdate_t {
	unsigned char day;		/* 1-31 */
	unsigned char month;		/* 1-12 */
	unsigned int year;		/* 1980-2099 */
	unsigned char dayofweek;	/* 0-6, 0=Sunday */
	};

struct dostime_t {
	unsigned char hour;	/* 0-23 */
	unsigned char minute;	/* 0-59 */
	unsigned char second;	/* 0-59 */
	unsigned char hsecond;	/* 0-99 */
	};

#define _DATETIME_T_DEFINED

#endif


/* manifest constants for _hardresume result parameter */

#define _HARDERR_IGNORE 	0	/* Ignore the error */
#define _HARDERR_RETRY		1	/* Retry the operation */
#define _HARDERR_ABORT		2	/* Abort program issuing Interrupt 23h */
#define _HARDERR_FAIL		3	/* Fail the system call in progress */
					/* _HARDERR_FAIL is not supported on DOS 2.x */

/* File attribute constants */

#define _A_NORMAL	0x00	/* Normal file - No read/write restrictions */
#define _A_RDONLY	0x01	/* Read only file */
#define _A_HIDDEN	0x02	/* Hidden file */
#define _A_SYSTEM	0x04	/* System file */
#define _A_VOLID	0x08	/* Volume ID file */
#define _A_SUBDIR	0x10	/* Subdirectory */
#define _A_ARCH 	0x20	/* Archive file */


/* external variable declarations */

extern unsigned int _cdecl _osversion;


/* function prototypes */

void _cdecl segread(struct SREGS *);


/* restore default alignment */

#pragma pack()
