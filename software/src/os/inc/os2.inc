;
; BASIC-DOS OS/2 Interfaces
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Definitions for the OS/2 1.x functions that the libraries in EXT\DLL (eg,
; DOSCALLS.DLL) provide, for those libraries and for the programs that call
; them (eg, SRC\SDK's FIND16).  It needs macros.inc, but no other file.
;

;
; PCALL calls a function that uses the Pascal calling convention, as OS/2's
; functions do: the parameters are pushed in the order they're documented
; (left to right), each as one word, or as two for a dword (the high word
; first) or a far pointer (the selector first), and the function removes them
; and returns its result in AX (for an OS/2 function, 0 or an error code,
; with every other register preserved).
;
; List the parameters as the function's documentation does.  A two-word
; parameter is its two words (eg, 0,0 for a zero dword, or <ds,dx> for a far
; pointer in DS:DX; the brackets only show that they're one parameter), or
; for a far pointer to a variable in the automatic data segment (DGROUP,
; which DS must address), ADDR and the variable's name; for example:
;
;	PCALL	DOSWRITE,bx,<ds,dx>,cx,ADDR,written
;
; Pushing a constant requires an 80286 (ie, .286), which every program that
; can call these functions has.
;
PCALL	macro	func,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13,a14,a15,a16
	argw = 1
	IRP	arg,<a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13,a14,a15,a16>
	 IFNB <arg>
	  IFIDN <arg>,<ADDR>
	argw = 2
	  ELSE
	   IF argw EQ 2
	push	ds
	push	offset DGROUP:arg
	argw = 1
	   ELSE
	push	arg
	   ENDIF
	  ENDIF
	 ENDIF
	ENDM
	call	func
	endm

;
; Error codes that DOS doesn't have (the rest are DOS's; see ERR_* in
; dosapi.inc).
;
ERROR_NO_MORE_FILES equ	18	; DosFindFirst and DosFindNext: no files
ERROR_OPEN_FAILED equ	110	; DosOpen: the open flags rule out the file
ERROR_BUFFER_OVERFLOW equ 111	; DosFindFirst: the buffer is too small
ERROR_BAD_SIGNAL equ	209	; DosSetSigHandler: unsupported signal

;
; DosOpen's open flags say what to do if the file exists (bits 0-3) and if
; it doesn't (bit 4), and its open mode is the access (bits 0-2) and what
; other programs may do (bits 4-6), which OS/2 requires and BASIC-DOS ignores.
;
OPENF_EXISTS	equ	0001h	; open the file if it exists (else fail)
OPENF_REPLACE	equ	0002h	; replace the file if it exists
OPENF_CREATE	equ	0010h	; create the file if it doesn't exist
OPENM_READ	equ	0000h	; read-only access
OPENM_WRITE	equ	0001h	; write-only access
OPENM_RDWR	equ	0002h	; read and write access
OPENM_DENYNONE	equ	0040h	; other programs may read and write the file

;
; DosSetSigHandler's signals and actions.
;
SIG_CTRLC	equ	1	; signal for CTRL-C
SIG_CTRLBREAK	equ	4	; signal for CTRL-BREAK (CTRL-C to us)
SIGA_KILL	equ	0	; signal action: end the program
SIGA_IGNORE	equ	1	; signal action: ignore the signal
SIGA_ACCEPT	equ	2	; signal action: call the handler
SIGA_ACK	equ	4	; signal action: acknowledge the signal

;
; DosFindFirst's directory handles, and the FILEFINDBUF that it and
; DosFindNext store for each file.
;
HDIR_SYSTEM	equ	1	; the handle that's always available
HDIR_CREATE	equ	-1	; create a handle (see DosFindClose)

FILEFINDBUF	struc
FF_CDATE	dw	?	; 00h: creation date
FF_CTIME	dw	?	; 02h: creation time
FF_ADATE	dw	?	; 04h: last access date
FF_ATIME	dw	?	; 06h: last access time
FF_WDATE	dw	?	; 08h: last write date
FF_WTIME	dw	?	; 0Ah: last write time
FF_SIZE		dd	?	; 0Ch: file size
FF_ALLOC	dd	?	; 10h: allocated size
FF_ATTR		dw	?	; 14h: attributes
FF_NAMELEN	db	?	; 16h: length of the name
FF_NAME		db   13 dup (?)	; 17h: name (null-terminated)
FILEFINDBUF	ends		; 24h
