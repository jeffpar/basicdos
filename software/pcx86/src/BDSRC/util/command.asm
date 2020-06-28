;
; BASIC-DOS Command Interpreter
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	mov	dx,offset ctrlc
	int	21h
m1:	PRINTF	">"
	mov	ah,DOS_TTY_INPUT
	mov	dx,offset input
	int	21h
	mov	bx,dx		; DS:BX -> input buffer
	inc	bx
	mov	al,[bx]
	test	al,al		; anything typed?
	jz	m1		; no
	cbw
	inc	bx
	mov	dx,bx		; DS:DX -> potential filename
	add	bx,ax
	mov	byte ptr [bx],0	; null-terminate it
	mov	ax,DOS_PSP_EXEC
	int	21h
	jnc	m1
	PRINTF	<"error loading %s: %d",13,10>,dx,ax
	jmp	m1
ENDPROC	main

DEFPROC	ctrlc,FAR
	PRINTF	<"CTRL-C intercepted",13,10>
	iret
ENDPROC	ctrlc

input	db	32		; the rest of input doesn't need initialization

	COMHEAP	4096		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
