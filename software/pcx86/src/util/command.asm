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
m1:	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	al,'A'		; AL = current drive letter
	PRINTF	"%c>",ax

	int 3
	mov	bx,offset workspace
	mov	[bx].INPUT.INP_MAX,size INPUT.INP_BUF
	lea	dx,[bx].INPUT
	mov	ah,DOS_TTY_INPUT
	int	21h

	mov	si,dx
	mov	[bx].TOKENS.TOK_MAX,size TOKENS.TOK_BUF
	lea	di,[bx].TOKENS
	mov	ax,DOS_UTIL_TOKENS
	int	21h

	mov	ch,0
	mov	cl,[bx].TOKENS.TOK_CNT
	jcxz	m1

	mov	dx,[bx].TOKENS.TOK_BUF
	mov	ax,DOS_PSP_EXEC
	int	21h
	jnc	m1
	PRINTF	<"error loading %s: %d",13,10>,dx,ax
	jmp	m1
ENDPROC	main

DEFPROC	ctrlc,FAR
	push	ax
	PRINTF	<"CTRL-C intercepted",13,10>
	pop	ax
	iret
ENDPROC	ctrlc

workspace equ	$

	COMHEAP	4096		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
