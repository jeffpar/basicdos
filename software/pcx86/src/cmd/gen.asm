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

	EXTERNS	<evalAdd32>,near
	EXTERNS	<print32>,near
	EXTERNS	<allocVars,addVar,findVar,letVar32>,near

	EXTERNS	<segVars>,word
	EXTERNS	<CMD_TOKENS>,word

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genImmediate
;
; Generate code for a single line, by creating a temporary code block, and
; then calling the specified "gen" handler to generate code in the block.
;
; For example, if "PRINT 2+2" triggers a call to genPrint, it might generate
; something like (but not quite as inefficient as) this:
;
;	PUSH	CS
;	PUSH	offset C1
;	JMP	SHORT L1
;  C1:	DW	2		; 16-bit constant
;  L1:	PUSH	CS
;	PUSH	offset C2
;	JMP	SHORT L2
;  C2:	DW	2		; 16-bit constant (assumes no constant folding)
;  L2:	CALLF	ADD
;	CALLF	PRINT
;	RETF
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
	LOCVAR	errCode,word
	LOCVAR	nValues,word
	LOCVAR	pCode,dword
	LOCVAR	pTokBufEnd,word
	ENTER
	mov	[errCode],0
	mov	bx,CBLKLEN SHR 4
	mov	ah,DOS_MEM_ALLOC
	int	21h
	jc	gi8
	mov	es,ax
	ASSUME	ES:NOTHING
	mov	bx,di			; BX -> TOKENBUF
	mov	al,[bx].TOK_CNT
	mov	ah,0
	add	bx,offset TOK_BUF	; BX -> TOKLET array
	add	ax,ax
	add	ax,ax
	add	ax,bx
	mov	[pTokBufEnd],ax
	add	bx,size TOKLET		; skip 1st token (already parsed)
	mov	di,di			; ES:DI -> usable code block space
	mov	[pCode].OFF,di
	mov	[pCode].SEG,es
gi5:	call	dx			; generate code
	jc	gi7			; error
	call	getNextToken
	jc	gi6
	mov	ax,DOS_UTL_TOKID
	lea	di,[CMD_TOKENS]
	int	21h			; identify the token
	jc	gi7			; can't identify
	jmp	gi5
	
gi6:	mov	al,OP_RETF		; terminate code
	stosb
	push	bp
	push	ds
	push	es
	mov	es,[segVars]
	ASSUME	ES:NOTHING
	lea	bx,[pCode]
	sub	sp,4
	mov	bp,sp			; SS:BP is 32-bit scratch space
	call	dword ptr ss:[bx]	; execute code
	add	sp,4
	pop	es
	pop	ds
	ASSUME	DS:CODE
	pop	bp
gi7:	pushf
	mov	ah,DOS_MEM_FREE
	int	21h
	popf
gi8:	jnc	gi9
	PRINTF	<'Syntax error at "%.*ls"',13,10>,cx,si,ds
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
;	ES:DI -> next unused location in code block
;
; Outputs:
;	Carry clear if successful, set if error
;	ES:DI -> next unused location in code block
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	genExpr
	sub	dx,dx
	mov	[nValues],dx		; count values queued
	push	dx			; push operator end marker (zero)

ge1:	mov	al,CLS_NUM OR CLS_SYM OR CLS_VAR
	call	getNextToken
	jbe	ge8

	cmp	al,CLS_SYM		; operator?
	jne	ge2			; no
	mov	al,[si]			; TODO: validate operator
	push	ax			; yes, push it
	jmp	ge1			; go to next token

ge2:	cmp	al,CLS_VAR		; variable?
	jne	ge4			; no
	call	findVar			; yes, does it exist?
	jnc	ge3			; yes
	sub	cx,cx			; no, so it has a default value of 0
	jmp	short ge6

ge3:	mov	al,OP_PUSH_ES
	stosb
	mov	al,OP_MOV_DI		; "MOV DI,offset var data"
	stosb
	xchg	ax,dx
	stosw
	mov	al,OP_PUSH_DI
	stosb
ge3a:	inc	[nValues]		; count another queued value
	jmp	ge1
;
; Number must be a constant, and although CX contains its exact length,
; DOS_UTL_ATOI32 doesn't actually care; it simply converts characters until
; it reaches a non-digit.
;
ge4:	push	bx
	mov	bl,10			; BL = 10 (default base)
	test	al,CLS_OCT OR CLS_HEX	; octal or hex value?
	jz	ge5			; no
	inc	si			; yes, skip leading ampersand
	shl	al,1
	shl	al,1
	shl	al,1
	mov	bl,al			; BL = 8 or 16 (new base)
	cmp	byte ptr [si],'9'	; is next character a digit?
	jbe	ge5			; yes
	inc	si			; no, skip it (must be 'O' or 'H')
ge5:	mov	ax,DOS_UTL_ATOI32	; DS:SI -> numeric string
	int	21h
	xchg	cx,ax			; save result in DX:CX
	pop	bx

ge6:	mov	al,OP_PUSH_CS
	stosb
	mov	al,OP_CALL
	stosb
	mov	ax,4			; size of 32-bit constant
	stosw
	xchg	ax,cx			; store 32-bit constant in DX:CX
	stosw
	xchg	ax,dx
	stosw
	jmp	ge3a			; go count another queued value
;
; Time to start popping the operator stack.
;
ge8:	pop	ax
	test	ax,ax
	jz	ge9			; all done
	cmp	al,'+'
	jne	ge9a
	mov	al,OP_CALLF
	stosb
	mov	ax,offset evalAdd32
	stosw
	mov	ax,cs
	stosw
	jmp	ge8

ge9a:	jmp	ge8

;
; TODO: Count the number of values that the operator stack expects, compare
; to the number of values actually queued (nValues), and bail on any mismatch.
;
ge9:	clc
	ret
ENDPROC	genExpr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLet
;
; Generate code to "let" a variable equal some expression.  We start with
; 32-bit integer ("long") variables.  We'll also start with the assumption
; that it's OK to alloc the variable at "gen" time, so that the only code we
; have to generate (and execute later) is code that sets the variable,
; using its preallocated location.
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
DEFPROC	genLet
	call	allocVars
	jc	gl9

	mov	al,CLS_VAR
	call	getNextToken
	jbe	gl9
;
; If the variable has a specific type, then AL should be >= VAR_INT.
; Otherwise, we default to VAR_LONG.
;
	cmp	al,VAR_INT
	jae	gl1
	mov	al,VAR_LONG

gl1:	call	addVar			; DX -> var data
	jc	gl9

	mov	al,CLS_SYM
	call	getNextToken
	jc	gl9
	cmp	byte ptr [si],'='
	stc
	jne	gl9

	mov	al,OP_MOV_DI		; "MOV DI,offset var data"
	stosb
	xchg	ax,dx
	stosw

	call	genExpr

	mov	al,OP_CALLF
	stosb
	mov	ax,offset letVar32
	stosw
	mov	ax,cs
	stosw

gl9:	ret
ENDPROC	genLet

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
	mov	al,CLS_NUM OR CLS_VAR
	call	getNextToken
	jbe	gp8

	sub	bx,size TOKLET
	call	genExpr
	jc	gp9

	mov	al,OP_CALLF
	stosb
	mov	ax,offset print32
	stosw
	mov	ax,cs
	stosw

	jmp	genPrint

gp8:	clc
gp9:	ret
ENDPROC	genPrint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextToken
;
; Return the next token if it matches the criteria in AL; by default,
; we ignore whitespace tokens.
;
; Inputs:
;	AL = CLS bits
;	BX -> TOKLETs
;
; Outputs if next token matches:
;	AL = CLS of token
;	CX = length of token
;	SI = offset of token
;	BX = offset of next TOKLET
;	ZF and CF clear (use JA opcode)
;
; Outputs if NO matching next token:
;	ZF set if no matching token, CF set if no more tokens
;	BX, CX, and SI unchanged
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	getNextToken
	cmp	bx,[pTokBufEnd]
	cmc
	jb	gt9			; no more tokens
	mov	ah,[bx].TOKLET_CLS
	test	al,ah
	jnz	gt1
	test	ah,CLS_WHITE		; whitespace token?
	jz	gt9			; no (return ZF set)
	add	bx,size TOKLET		; yes, ignore it
	jmp	getNextToken

gt1:	mov	si,[bx].TOKLET_OFF
	mov	cl,[bx].TOKLET_LEN
	mov	ch,0
	lea	bx,[bx + size TOKLET]
;
; If we're about to return a CLS_SYM that happens to be a colon, then
; return ZF set (but not carry) to end the caller's token scan.
;
	cmp	ah,CLS_SYM
	jne	gt2
	cmp	byte ptr [si],':'
	jne	gt8
	jmp	short gt9
;
; If we're about to return a CLS_VAR, then we also peek at the next token,
; and if it's CLS_SYM, then check for '%', '!', '#', and '$', and if one of
; those is present, skip it and update this token's type appropriately.
;
gt2:	cmp	ah,CLS_VAR		; returning CLS_VAR?
	jne	gt8			; no
	cmp	bx,[pTokBufEnd]		; more tokens?
	jnb	gt8			; no
	cmp	[bx].TOKLET_CLS,CLS_SYM	; next token a symbol?
	jne	gt8			; no
	mov	al,[si]			; get symbol character
	cmp	al,'%'
	jne	gt3
	mov	ah,VAR_LONG		; default to VAR_LONG for integers
gt3:	cmp	al,'!'
	jne	gt4
	mov	ah,VAR_SINGLE
gt4:	cmp	al,'#'
	jne	gt5
	mov	ah,VAR_DOUBLE
gt5:	cmp	al,'$'
	jne	gt8
	mov	ah,VAR_STRING

gt8:	mov	al,0
	or	al,ah			; return both ZF clear and CF clear

gt9:	ret
ENDPROC	getNextToken

CODE	ENDS

	end
