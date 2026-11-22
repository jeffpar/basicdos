;
; BASIC-DOS NLS Library
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; NLS.DLL is an NE library (see NLS.DEF) with the one function of OS/2's NLS
; module that LINK386 imports; see DOSCALLS.ASM for how these libraries are
; found and how their functions are called.
;
	include	macros.inc

CODE	segment word public 'CODE'

	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosGetDBCSEv (ordinal 4)
;
; Returns the lead byte ranges of a double-byte character set: pairs of bytes
; (the first and last of each range), ending with a pair of zeros.  BASIC-DOS
; has no double-byte character sets, so there are no ranges, and the buffer
; is filled with zeros.
;
; Inputs:
;	[BP+14] = size of the buffer
;	[BP+10] -> country code and code page (far pointer; ignored)
;	[BP+6] -> buffer (far pointer)
;
; Outputs:
;	AX = 0
;
DEFPROC	DOSGETDBCSEV,FAR
	push	bp
	mov	bp,sp
	push	cx
	push	di
	push	es
	les	di,[bp+6]
	mov	cx,[bp+14]
	sub	ax,ax
	rep	stosb
	pop	es
	pop	di
	pop	cx
	pop	bp
	ret	10
ENDPROC	DOSGETDBCSEV

CODE	ends

	end
