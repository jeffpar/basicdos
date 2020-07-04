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
	lea	bx,[DGROUP:heap]
	mov	[bx].ORIG_SP.SEG,ss
	mov	[bx].ORIG_SP.OFF,sp
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	mov	dx,offset ctrlc
	int	21h
;
; Since all the command handlers loop back to this point, we should not
; assume that any registers (including BX) will still be set to anything.
;
m1:	lea	bx,[DGROUP:heap]
	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	al,'A'		; AL = current drive letter
	PRINTF	"%c>",ax

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
	; push	ax
	; PRINTF	<"CTRL-C intercepted",13,10>
	; pop	ax
	; iret
	lea	bx,[DGROUP:heap]
	cli
	mov	ss,[bx].ORIG_SP.SEG
	mov	sp,[bx].ORIG_SP.OFF
	sti
	jmp	m1
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
dir1:	lea	si,ds:[PSP_DTA].FFB_NAME
	mov	ax,DOS_UTL_STPLEN
	int	21h		; AX = length of base name
	mov	di,si
	add	di,ax
	inc	di		; DI -> extension
	mov	dx,ds:[PSP_DTA].FFB_DATE
	mov	cx,ds:[PSP_DTA].FFB_TIME
	ASSERT	Z,<cmp ds:[PSP_DTA].FFB_SIZE.SEG,0>
	PRINTF	<"%-8.*s %-3s %7ld %2M-%02D-%02X %2G:%02N%A",13,10>,ax,si,di,ds:[PSP_DTA].FFB_SIZE.OFF,ds:[PSP_DTA].FFB_SIZE.SEG,dx,dx,dx,cx,cx,cx
	mov	ah,DOS_DSK_FNEXT
	int	21h
	jnc	dir1
dir9:	ret
ENDPROC	cmdDir

DEFPROC	cmdLoop
	push	si
	call	cmdDir
	pop	si
	jmp	cmdLoop
ENDPROC	cmdLoop

DEFPROC	cmdExit
	mov	ax,ds:[PSP_PARENT]
	test	ax,ax		; do we have a parent?
	jz	ex9		; no, can't exit
	PRINTF	<"Returning to process %#04x",13,10>,ax
	int	20h		; terminate ourselves
ex9:	ret
ENDPROC	cmdExit

DEFPROC	cmdUndefined
	ret
ENDPROC	cmdUndefined

DEFPROC	cmdTime
	ret
ENDPROC	cmdTime

DEFPROC	cmdType
	mov	dx,si		; DS:DX -> filename
	mov	ax,DOS_HDL_OPEN SHL 8
	int	21h
	jnc	ty1		; AX = file handle if successful, else error
	PRINTF	<"unable to open %s: %d",13,10>,dx,ax
	jmp	short ty9
ty1:	xchg	bx,ax		; BX = file handle
	mov	dx,PSP_DTA	; DS:DX -> DTA (as good a place as any)
ty2:	mov	cx,size PSP_DTA	; CX = number of bytes to read
	mov	ah,DOS_HDL_READ
	int	21h
	jc	ty8		; silently fail (for now)
	test	ax,ax		; anything read?
	jz	ty8		; no
	push	bx
	mov	bx,STDOUT
	xchg	cx,ax		; CX = number of bytes to write
	mov	ah,DOS_HDL_WRITE
	int	21h
	pop	bx
	jmp	ty2
ty8:	mov	ah,DOS_HDL_CLOSE
	int	21h
ty9:	ret
ENDPROC	cmdType

	DEFSTR	COM_EXT,<".COM",0>
	DEFSTR	DIR_DEF,<"*.*">

	DEFTOKENS CMD_TOKENS,NUM_TOKENS
	DEFTOK	TOK_DATE,  0, "DATE",	cmdDate
	DEFTOK	TOK_DIR,   1, "DIR",	cmdDir
	DEFTOK	TOK_EXIT,  2, "EXIT",	cmdExit
	DEFTOK	TOK_LOOP,  3, "LOOP",	cmdLoop
	DEFTOK	TOK_PRINT, 4, "PRINT",	cmdUndefined
	DEFTOK	TOK_TIME,  5, "TIME",	cmdTime
	DEFTOK	TOK_TYPE,  6, "TYPE",	cmdType
	NUMTOKENS CMD_TOKENS,NUM_TOKENS

STRDATA SEGMENT
	COMHEAP	<size CMD_WS>	; COMHEAP (heap size) must be the last item
STRDATA	ENDS

CODE	ENDS

	end	main
