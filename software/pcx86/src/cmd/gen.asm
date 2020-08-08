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

	EXTERNS	<printArgs>,near
	EXTERNS	<allocCode,freeCode,allocVars>,near
	EXTERNS	<addVar,findVar,setVarLong>,near
	EXTERNS	<appendStr,setStr>,near

	EXTERNS	<segVars>,word
	EXTERNS	<CMD_TOKENS>,word
	EXTERNS	<OPDEFS>,byte

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genImmediate
;
; Generate code for a single line, by creating a temporary code block, and
; then calling the specified "gen" handler(s) to generate code in the block.
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
	LOCVAR	nOps,word
	LOCVAR	nValues,word
	LOCVAR	errCode,word
	LOCVAR	pCode,dword
	LOCVAR	pTokBufEnd,word
	ENTER
	mov	[errCode],0
	mov	bx,di			; BX -> TOKENBUF
	mov	al,[bx].TOK_CNT
	mov	ah,0
	add	bx,offset TOK_BUF	; BX -> TOKLET array
	add	ax,ax
	add	ax,ax
	add	ax,bx
	mov	[pTokBufEnd],ax
	add	bx,size TOKLET		; skip 1st token (already parsed)

	call	allocVars
	jc	gie
	call	allocCode
	jc	gie
	ASSUME	ES:NOTHING		; ES:DI -> usable code block space
	mov	[pCode].OFF,di
	mov	[pCode].SEG,es

gi1:	call	dx			; generate code
	jc	gi7			; error
	call	getNextToken
	jc	gi6
	push	di
	mov	ax,DOS_UTL_TOKID
	lea	di,[CMD_TOKENS]
	int	21h			; identify the token
	pop	di
	jc	gi7			; can't identify
	jmp	gi1

gie:	PRINTF	<'Not enough memory (%#06x)',13,10>,ax
	jmp	short gi9

gi6:	mov	al,OP_RETF		; terminate code
	stosb
	push	bp
	push	ds
	push	es
	mov	ax,[segVars]
	mov	ds,ax
	mov	es,ax
	ASSUME	DS:NOTHING
	call	[pCode]			; execute code
	pop	es
	pop	ds
	ASSUME	DS:CODE
	pop	bp
	clc

gi7:	pushf
	call	freeCode
	popf
gi8:	jnc	gi9

	PRINTF	<'Syntax error',13,10>

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
; genExprNum
;
; Generate code for a numeric expression.
;
; Inputs:
;	BX = offset of next TOKLET
;	ES:DI -> next unused location in code block
;
; Outputs:
;	CF clear if successful, set if error
;	ZF clear if expression existed, set if not
;	ES:DI -> next unused location in code block
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	genExprNum
	sub	dx,dx
	mov	[nOps],dx		; count operators
	mov	[nValues],dx		; and values queued
	push	dx			; push end-of-operators marker (zero)

gn1:	mov	al,CLS_NUM OR CLS_SYM OR CLS_VAR
	call	getNextToken
	jbe	gn8

	cmp	ah,CLS_SYM		; operator?
	jne	gn2			; no
	call	validateOp		; AL = operator to validate
	jc	gn8			; error
	inc	[nOps]
	mov	si,dx			; SI = current evaluator
;
; Operator is valid, so peek at the operator stack and pop if the top
; operator precedence >= current operator precedence.
;
gn1a:	pop	cx			; "peek"
	cmp	ch,ah			; top precedence >= current?
	jb	gn1b			; no
	pop	dx			; yes, pop the evaluator as well
	GENCALL	dx			; and generate call
	jmp	gn1a
gn1b:	push	cx			; "unpeek"
	push	si			; push current evaluator
	push	ax			; push current operator/precedence
	jmp	gn1			; next token

gn2:	cmp	ah,CLS_VAR		; variable?
	jne	gn4			; no
	call	findVar			; go find it
;
; We don't care if findVar succeeds or not, because even if it fails,
; it returns var type (AH) VAR_LONG with var data (DX) preset to zero.
;
; TODO: Check AH for the var type and act accordingly.
;
gn3:	call	genPushVarLong

gn3a:	inc	[nValues]		; count another queued value
	jmp	gn1
;
; Number must be a constant, and although CX contains its exact length,
; DOS_UTL_ATOI32 doesn't actually care; it simply converts characters until
; it reaches a non-digit.
;
gn4:	push	bx
	mov	bl,10			; BL = 10 (default base)
	test	ah,CLS_OCT OR CLS_HEX	; octal or hex value?
	jz	gn5			; no
	inc	si			; yes, skip leading ampersand
	shl	ah,1
	shl	ah,1
	shl	ah,1
	mov	bl,ah			; BL = 8 or 16 (new base)
	cmp	byte ptr [si],'9'	; is next character a digit?
	jbe	gn5			; yes
	inc	si			; no, skip it (must be 'O' or 'H')
gn5:	mov	ax,DOS_UTL_ATOI32	; DS:SI -> numeric string
	int	21h
	xchg	cx,ax			; save result in DX:CX
	pop	bx

gn6:	mov	al,OP_MOV_AX
	stosb
	xchg	ax,dx
	stosw
	mov	ax,OP_PUSH_AX OR (OP_MOV_AX SHL 8)
	stosw
	xchg	ax,cx
	stosw
	PUSH_AX
	jmp	gn3a			; go count another queued value
;
; Time to start popping the operator stack.
;
gn8:	pop	ax
	test	ax,ax
	jz	gn9			; all done
	pop	dx			; DX = evaluator
	GENCALL	dx
	jmp	gn8
;
; Verify the number of expected operands matches the number of values queued.
;
gn9:	mov	ax,[nValues]
	test	ax,ax
	jz	gn10			; return ZF set if no values
	mov	ax,[nOps]
	inc	ax
	cmp	ax,[nValues]
	stc
	jne	gn10
	test	ax,ax			; success (both CF and ZF clear)
gn10:	ret
ENDPROC	genExprNum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genExprStr
;
; Generate code for a string expression.  It begins by creating an empty
; string (ie, null pointer) on the stack and beginning string operations
; (ie, concatenations, if any).
;
; The common case is a string constant, which is stored in the code block.
; The generated code will call appendStr to append the string referenced in
; the code block to the string pointer on the stack.
;
; Inputs:;
;	BX = offset of next TOKLET
;	ES:DI -> next unused location in code block
;
; Outputs:
;	CF clear if successful, set if error
;	ZF clear if expression existed, set if not
;	ES:DI -> next unused location in code block
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	genExprStr
	int 3
	mov	ax,OP_ZERO_AX
	stosw
	mov	ax,OP_PUSH_AX OR (OP_PUSH_AX SHL 8)
	stosw

gs1:	mov	al,CLS_VAR OR CLS_STR
	call	getNextToken
	jbe	gs5

	cmp	ah,CLS_STR
	jne	gs2
;
; Handle string constant here.
;
	sub	cx,2			; CX = string length
	ASSERT	NC
	jcxz	gs4			; empty string, skip it
	inc	si			; DS:SI -> string contents
	PUSHSTR
	jmp	short gs3
;
; Handle string variable here.
;
gs2:	cmp	ah,VAR_STR
	ASSERT	Z
	stc
	jne	gs8
	call	findVar			; find the variable
	jc	gs8
	cmp	ah,VAR_STR		; correct type?
	stc
	jne	gs8			; no
	call	genPushVarLong
gs3:	GENCALL	appendStr
;
; Check for concatenation (the only supported string operator).
;
gs4:	mov	al,CLS_SYM
	call	getNextToken
	jbe	gs5
	cmp	al,'+'
	je	gs1
	stc

gs5:

gs8:	ret
ENDPROC	genExprStr

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
;	BX = offset of next TOKLET
;	ES:DI -> next unused location in code block
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	genLet
	mov	al,CLS_VAR
	call	getNextToken
	jbe	gl9
;
; If the variable has a specific type, then AL should be >= VAR_INT.
; Otherwise, we default to VAR_LONG.
;
	mov	al,ah
	cmp	al,VAR_INT
	jae	gl1
	mov	al,VAR_LONG

gl1:	call	addVar			; DX -> var data
	jc	gl9

	push	ax
	PUSH_DS_DX
	mov	al,CLS_SYM
	call	getNextToken
	pop	dx
	jbe	gl9

	cmp	al,'='
	stc
	jne	gl9

	cmp	dl,VAR_STR		; check the new variable's type
	jne	gl2			; presumably numeric

	call	genExprStr
	jc	gl9
	GENCALL	setStr
	jmp	short gl9

gl2:	call	genExprNum
	jc	gl9
	GENCALL	setVarLong

gl9:	ret
ENDPROC	genLet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPrint
;
; Generate code to print.
;
; Inputs:
;	BX = offset of next TOKLET
;	ES:DI -> next unused location in code block
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	genPrint
	MOV_AL	VAR_NONE
	PUSH_AX				; push end-of-args marker (VAR_NONE)

gp1:	mov	al,CLS_VAR or CLS_STR
	call	peekNextToken
	jc	gp8
	jz	gp3
	cmp	ah,CLS_STR
	je	gp2
	cmp	ah,VAR_STR
	jne	gp3
;
; Handle string arguments here.
;
gp2:	push	ax
	call	genExprStr
	pop	ax
	jc	gp9
	jz	gp8

	push	ax
	mov	al,OP_MOV_AL
	stosw
	jmp	short gp4a
;
; Handle numeric arguments here.
;
gp3:	call	genExprNum
	jc	gp9
	jz	gp8

gp4:	push	ax
	MOV_AL	VAR_LONG
gp4a:	PUSH_AX
	pop	ax
;
; Argument paths rejoin here to determine spacing requirements.
;
gp5:	mov	ah,VAR_SEMI
	cmp	cl,';'			; was the last symbol a semi-colon?
	je	gp6			; yes
	mov	ah,VAR_COMMA
	cmp	cl,','			; how about a comma?
	jne	gp8			; no

gp6:	mov	al,OP_MOV_AL		; "MOV AL,[VAR_SEMI or VAR_COMMA]"
	stosw
	PUSH_AX
	jmp	gp1			; contine processing arguments
;
; Arguments exhausted, generate the print call.
;
gp8:	GENCALL	printArgs
	clc

gp9:	ret
ENDPROC	genPrint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCallDX
;
; Inputs:
;	CS:DX -> function to call
;
; Outputs:
;	None
;
; Modifies:
;	DX, DI
;
DEFPROC	genCallDX
	push	ax
	mov	al,OP_CALLF
	stosb
	xchg	ax,dx
	stosw
	mov	ax,cs
	stosw
	pop	ax
	ret
ENDPROC	genCallDX

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushVarLong
;
; Generates code to push 4-byte variable data onto stack (eg, a VAR_LONG or
; a VAR_STR pointer).
;
; Inputs:
;	DS:DX -> var data
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	genPushVarLong
	mov	al,OP_MOV_SI		; "MOV SI,offset var data"
	stosb
	xchg	ax,dx
	stosw
	mov	ax,OP_LODSW OR (OP_XCHG_DX SHL 8)
	stosw
	mov	ax,OP_LODSW OR (OP_PUSH_AX SHL 8)
	stosw
	mov	al,OP_PUSH_DX
	stosb
	ret
ENDPROC	genPushVarLong

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
;	AH = CLS of token
;	AL = symbol if CLS_SYM
;	CX = length of token
;	SI = offset of token
;	BX = offset of next TOKLET
;	ZF and CF clear
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
	mov	al,[si]
	cmp	al,':'
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
	mov	ah,VAR_STR
gt8:	or	ah,0			; return both ZF and CF clear
gt9:	ret
ENDPROC	getNextToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peekNextToken
;
; Return the next token if it matches the criteria in AL; by default,
; we ignore whitespace tokens.
;
DEFPROC	peekNextToken
	call	getNextToken
	jbe	pt9
	lea	bx,[bx - size TOKLET]
pt9:	ret
ENDPROC	peekNextToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; validateOp
;
; Inputs:
;	AL = operator
;
; Outputs:
;	If carry clear, AL = op, AH = precedence, DX = evaluator
;
; Modifies:
;	AX, DX
;
DEFPROC	validateOp
	mov	ah,al			; AH = operator to validate
	push	si
	mov	si,offset OPDEFS
vo1:	lodsb
	test	al,al
	stc
	jz	vo9			; not valid
	cmp	al,ah			; match?
	je	vo8			; yes
	add	si,size OPDEF - 1
	jmp	vo1
vo8:	lodsb				; AL = precedence, AH = operator
	xchg	dx,ax
	lodsw				; AX = evaluator
	xchg	dx,ax			; DX = evaluator, AX = op/prec
vo9:	xchg	al,ah			; AL = operator, AH = precedence
	pop	si
	ret
ENDPROC	validateOp

CODE	ENDS

	end
