;
; BASIC-DOS Code Generator
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTERNS	<evalAdd16>,near
	EXTERNS	<print16>,near

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genImmediate
;
; Generate code for a single line, by creating a temporary code block, and
; then calling the specified "gen" handler to generate code in the block.
;
; For example, if "PRINT 2+2" triggers a call to genPrint, it might generate
; something like (but not as inefficient as) this:
;
;	PUSH	offset C1
;	JMP	L1
;  C1:	DW	2		; constant
;  L1:	PUSH	offset C2
;	JMP	L2
;  C2:	DW	2		; constant (assuming no constant folding)
;  L2:	CALL	ADD
;	CALL	PRINT
;	RET
;
; The offsets of constants C1 and C2 will be local to the code block,
; hence < CBLKLEN, where CBLKLEN is the maximum length of a code block.
; The function call addresses will be far, as will the RET.
;
; Inputs:
;	DI -> TOKENBUF with all tokens
;	DX = TOKDEF_DATA for first token (ie, the "gen" handler)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	genImmediate
	LOCVAR	pCode,dword
	LOCVAR	pTokBufEnd,word
	ENTER
	mov	bx,CBLKLEN SHR 4
	mov	ah,DOS_MEM_ALLOC
	int	21h
	jc	gi8
	mov	es,ax
	mov	bx,di			; BX -> TOKENBUF
	mov	al,[bx].TOK_CNT
	mov	ah,0
	add	bx,offset TOK_BUF	; BX -> TOKLET array
	add	ax,ax
	add	ax,ax
	add	ax,bx
	mov	[pTokBufEnd],ax
	add	bx,size TOKLET		; skip 1st token (already parsed)
	mov	di,size CBLK_HDR	; ES:DI -> usable code block space
	mov	[pCode].OFF,di
	mov	[pCode].SEG,es
	call	dx			; generate code
	call	[pCode]			; execute code
	mov	ah,DOS_MEM_FREE
	int	21h
gi8:	jnc	gi9
	PRINTF	<"Unable to execute (%#06x)",13,10>,ax
gi9:	LEAVE
	ret
ENDPROC	genImmediate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genColor
;
; Generate code for "COLOR [fgnd],[bgnd],[border]"
;
; Inputs:
;	BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	genColor
	ret
ENDPROC	genColor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genExpr
;
; Generate code for an expression.
;
; Inputs:
;	AL = CLS of token
;	CL = length of token
;	SI = offset of token
;	BX = offset of next TOKLET
;	ES:DI -> code block
;
; Outputs:
;	ES:DI updated to next free location
;
; Modifies:
;	Any
;
DEFPROC	genExpr
	sub	dx,dx
	push	dx			; push an end marker
	jmp	short ge2

ge1:	mov	al,CLS_NUM OR CLS_SYM
	call	getNextToken
	jc	ge8

ge2:	cmp	al,CLS_SYM		; operator?
	jne	ge3			; no
	mov	al,[si]
	push	ax			; yes, push it
	jmp	ge1			; go to next token

ge3:	push	bx
	mov	bl,10			; BL = 10 (default base)
	test	al,CLS_OCT OR CLS_HEX	; octal or hex value?
	jz	ge4			; no
	inc	si			; yes, skip leading ampersand
	shl	al,1
	shl	al,1
	shl	al,1
	mov	bl,al			; BL = 8 or 16 (new base)
	cmp	byte ptr [si],'9'	; is next character a digit?
	jbe	ge4			; yes
	inc	si			; no, so skip it (must be 'O' or 'H')

ge4:	mov	al,OP_CALL
	stosb
	mov	ax,2
	stosw
	mov	ax,DOS_UTL_ATOI32	; DS:SI -> numeric string
	int	21h
	pop	bx
	stosw				; offset of constant has been "pushed"
ge7:	jmp	ge1

ge8:	pop	ax
	test	ax,ax
	jz	ge9			; all done
	cmp	al,'+'
	jne	ge9a
	mov	al,OP_CALLF
	stosb
	mov	ax,offset evalAdd16
	stosw
	mov	ax,cs
	stosw
	jmp	ge8

ge9a:	jmp	ge8

ge9:	ret
ENDPROC	genExpr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPrint
;
; Generate code to print.
;
; Inputs:
;	BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	genPrint
	mov	al,CLS_NUM
	call	getNextToken
	jc	gp9
	call	genExpr

	mov	al,OP_CALLF
	stosb
	mov	ax,offset print16
	stosw
	mov	ax,cs
	stosw
	jmp	genPrint

gp9:	mov	al,OP_RETF
	stosb
	ret
ENDPROC	genPrint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextToken
;
; Return the next token if it matches the criteria in AL;
; by default, we ignore whitespace tokens.
;
; Inputs:
;	AL = CLS bits
;	BX -> TOKLETs
;
; Outputs if successful:
;	Carry clear
;	AL = CLS of token
;	CL = length of token
;	SI = offset of token
;	BX = offset of next TOKLET
;
; Outputs if unsuccessful (next token does not match or does not exist):
;	Carry set
;	BX, CX, and SI unchanged
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	getNextToken
	mov	ah,[bx].TOKLET_CLS
	test	ah,al
	jnz	gt8
	test	ah,CLS_WHITE		; whitespace token?
	stc
	jz	gt9			; no
	add	bx,size TOKLET		; yes, ignore it
	cmp	[pTokBufEnd],bx
	jnb	getNextToken
	jmp	short gt9		; return carry set
gt8:	mov	al,ah
	mov	si,[bx].TOKLET_OFF
	mov	cl,[bx].TOKLET_LEN
	lea	bx,[bx + size TOKLET]
gt9:	ret
ENDPROC	getNextToken

CODE	ENDS

	end
