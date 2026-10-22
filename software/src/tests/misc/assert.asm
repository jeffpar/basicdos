;
; BASIC-DOS Assertion Test
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Run ASSERT (in TESTS\MISC) to fake an assertion failure.  This program is
; always assembled as a DEBUG binary (even in FINAL builds), so its ASSERT
; always executes an INT 3: DEBUG.COM (as a driver, or with ASSERT as its
; program) stops there, displaying "Assertion failure", and G resumes it;
; otherwise, a DEBUG BASIC-DOS prints "Assertion failure @ssss:oooo", and a
; FINAL BASIC-DOS ignores it.  Either way, it then exits with code 0.  Its
; DPRINTF message goes to the DEBUG.COM driver's port (DEBUG$), if installed.
;
	IFNDEF	DEBUG
DEBUG	equ	1
	ENDIF
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	dosapi.inc

CODE	segment
	ASSUME	CS:CODE, DS:CODE, ES:CODE, SS:CODE
	org	100h

DEFPROC	main
	DPRINTF	<"Faking an assertion failure",13,10>
;
; CMP AX,AX always sets ZF, so asserting NZ always fails.
;
	ASSERT	NZ,<cmp ax,ax>
	PRINTF	<"ASSERT done",13,10>
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
ENDPROC	main

CODE	ends
	end	main
