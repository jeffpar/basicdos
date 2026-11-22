;
; BASIC-DOS KBDCALLS Library
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; KBDCALLS.DLL is an NE library (see KBDCALLS.DEF) with the one function of
; OS/2's KBDCALLS module that LINK386 imports; see DOSCALLS.ASM for how these
; libraries are found and how their functions are called.
;
	DOSFUNC equ 1
	include	macros.inc
	include	dosapi.inc

CODE	segment word public 'CODE'

	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; KbdFlushBuffer (ordinal 13)
;
; Discards any type-ahead (see DOS_TTY_FLUSH).
;
; Inputs:
;	[SP+4] = keyboard handle (ignored: the keyboard is standard input)
;
; Outputs:
;	AX = 0
;
DEFPROC	KBDFLUSHBUFFER,FAR
	mov	ax,DOS_TTY_FLUSH SHL 8
	int	21h
	sub	ax,ax
	ret	2
ENDPROC	KBDFLUSHBUFFER

CODE	ends

	end
