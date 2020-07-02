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

	lea	bx,[DGROUP:heap]
	mov	[bx].INPUT.INP_MAX,40
	lea	dx,[bx].INPUT
	mov	ah,DOS_TTY_INPUT
	int	21h

	mov	si,dx		; DS:SI -> input buffer
	lea	di,[bx].TOKENS
	mov	[di].TOK_MAX,40
	mov	ax,DOS_UTL_TOKIFY
	int	21h
	xchg	cx,ax		; CX = token count from AX
	jcxz	m1		; jump if no tokens
;
; Before trying to ID the token, let's copy it to the FILENAME buffer,
; upper-case it, and null-terminate it.
;
	GETTOKEN 1		; DS:SI -> token #1
	lea	di,[bx].FILENAME
	push	cx
	push	di
	rep	movsb
	pop	si		; DS:SI -> copy of token in FILENAME
	pop	cx
	mov	ax,DOS_UTL_STRUPR
	int	21h		; DS:SI -> upper-case token, CX = length
	mov	ax,DOS_UTL_TOKID
	lea	di,[DGROUP:CMD_TOKENS]
	int	21h		; identify the token
	jnc	m4		; token ID in AX, token data in DX

	mov	dx,si		; DS:DX -> FILENAME
	mov	di,si
	add	di,cx		; ES:DI -> end of name in FILENAME
	mov	si,offset COM_EXT
	mov	cx,COM_EXT_LEN
	rep	movsb
	mov	ax,DOS_PSP_EXEC
	int	21h		; exec program at DS:DX
	jnc	m3
m2:	PRINTF	<"error loading %s: %d">,dx,ax
m3:	PRINTF	<13,10>
	jmp	m1

m4:	lea	di,[bx].TOKENS
	mov	cx,DIR_DEF_LEN
	mov	si,offset DIR_DEF
	GETTOKEN 2		; DS:SI -> token #2
	lea	di,[bx].FILENAME
	push	cx
	push	di
	rep	movsb
	mov	byte ptr es:[di],0
	pop	si		; DS:SI -> copy of token in FILENAME
	pop	cx
	mov	ax,DOS_UTL_STRUPR
	int	21h		; DS:SI -> upper-case token, CX = length
	call	dx		; call token handler
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
	sub	cx,cx		; CX = attributes
	mov	dx,si		; DS:DX -> filespec
	mov	ah,DOS_DSK_FFIRST
	int	21h
	jnc	dir1
	PRINTF	<"unable to find %s: %d",13,10>,dx,ax
	jmp	short dir9
dir1:	lea	ax,ds:[80h].FFB_NAME
	mov	dx,ds:[80h].FFB_DATE
	mov	cx,ds:[80h].FFB_TIME
	PRINTF	<"%-12s %2M-%02D-%02X %2G:%02N%A",13,10>,ax,dx,dx,dx,cx,cx,cx
	mov	ah,DOS_DSK_FNEXT
	int	21h
	jnc	dir1
dir9:	ret
ENDPROC	cmdDir

DEFPROC	cmdUndefined
	ret
ENDPROC	cmdUndefined

DEFPROC	cmdTime
	ret
ENDPROC	cmdTime

COM_EXT	db	".COM",0
COM_EXT_LEN equ $ - COM_EXT

DIR_DEF	db	"*.*"
DIR_DEF_LEN equ $ - DIR_DEF

DEFTOKENS CMD_TOKENS,NUM_TOKENS
DEFTOK	TOK_DATE,  0, "DATE",	cmdDate
DEFTOK	TOK_DIR,   1, "DIR",	cmdDir
DEFTOK	TOK_PRINT, 2, "PRINT",	cmdUndefined
DEFTOK	TOK_TIME,  3, "TIME",	cmdTime
NUMTOKENS CMD_TOKENS,NUM_TOKENS

STRDATA SEGMENT
	COMHEAP	<size CMD_WS>	; COMHEAP (heap size) must be the last item
STRDATA	ENDS

CODE	ENDS

	end	main
