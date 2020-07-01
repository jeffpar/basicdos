;
; BASIC-DOS Command Interpreter
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

DGROUP	group	CODE,TOKDATA,STRDATA

CODE    SEGMENT word public 'CODE'
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

	mov	bx,offset workspace
	mov	[bx].INPUT.INP_MAX,40
	lea	dx,[bx].INPUT
	mov	ah,DOS_TTY_INPUT
	int	21h

	int 3
	mov	si,dx		; DS:SI -> input buffer
	mov	[bx].TOKENS.TOK_MAX,40
	lea	di,[bx].TOKENS
	mov	ax,DOS_UTL_TOKIFY
	int	21h
	xchg	cx,ax		; CX = token count from AX
	jcxz	m1		; jump if no tokens

	add	si,2
	lea	di,[di].TOKENS.TOK_BUF
	mov	bx,[di]		; BX = offset of next token
	mov	cx,[di+2]	; CX = length of next token
	lea	si,[si+bx]	; SI -> token
	mov	ax,DOS_UTL_STRUPR
	int	21h		; make DS:SI string upper-case

	mov	ax,DOS_UTL_TOKID
	mov	di,offset DEF_TOKENS
	int	21h		; return token ID in AX
	jc	m2		; no match, so we'll assume it's a .COM file



m2:	lea	dx,[workspace].FILENAME
	mov	di,dx		; DI -> FILENAME
	rep	movsb
	mov	si,offset COM_EXT
	mov	cx,COM_EXT_LEN
	rep	movsb

	mov	ax,DOS_PSP_EXEC
	int	21h		; exec program at DS:DX
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

DEFPROC	cmdDate
	ret
ENDPROC	cmdDate

DEFPROC	cmdDir
	ret
ENDPROC	cmdDir

DEFPROC	cmdPrint
	ret
ENDPROC	cmdPrint

DEFPROC	cmdTime
	ret
ENDPROC	cmdTime

COM_EXT	db	".COM",0
COM_EXT_LEN equ $ - COM_EXT

DEF_TOKENS label word
	dw	NUM_TOKENS
	DEFTOK	TOK_DATE,  0, "DATE",	cmdDate
	DEFTOK	TOK_DIR,   1, "DIR",	cmdDir
	DEFTOK	TOK_PRINT, 2, "PRINT",	cmdPrint
	DEFTOK	TOK_TIME,  3, "TIME",	cmdTime
NUM_TOKENS	equ	($ - DEF_TOKENS) SHR 2

workspace 	equ	$

	COMHEAP	<size CMD_WS>	; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
