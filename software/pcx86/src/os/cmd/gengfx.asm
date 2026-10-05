;
; BASIC-DOS Code Generator: Graphics Statements
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for these graphics statements, whose runtime functions are
; in gfx.asm (and gfxcirc.asm, for CIRCLE):
;
;	CIRCLE				(genCircle)
;	DRAW				(genDraw)
;	GET				(genGet)
;	LINE				(genLine)
;	PAINT				(genPaint)
;	PSET and PRESET			(genPset and genPreset)
;	PUT				(genPut)
;
; Coordinates must be absolute (ie, STEP isn't supported yet).
;
; See gencmd.asm for an overview of all the gen*.asm files.  Like gencmd.asm,
; these functions are called while generating code, with DS:BX -> TOKLETs and
; ES:DI -> code block.
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<genLong,genStr,genArrayVar,getNextToken,getNextSymbol>
	EXTNEAR	<peekNextSymbol,genCallCS,genPushImmLong,genExpr,genCvtType>
	EXTNEAR	<gfxDraw,gfxGet,gfxLastPt,gfxLine,gfxPaint,gfxPset,gfxPut>
	EXTNEAR	<gfxCircle>
	EXTABS	<TOK_PSET,TOK_PRESET>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCircle
;
; Generate code for "CIRCLE (x,y),r[,[color][,[start][,[end][,aspect]]]]",
; where the angles (in radians) and aspect are doubles (see gfxCircle).
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genCircle
	call	genPoint
	jc	gci9
	mov	ah,','
	call	genSymbol
	jc	gci9
	call	genLong			; radius
	jc	gci9
	mov	cx,-1
	mov	dl,VAR_LONG
	call	genOptArg		; color
	jc	gci9
	mov	cx,3
gci1:	push	cx
	sub	cx,cx
	mov	dl,VAR_DOUBLE
	call	genOptArg		; start, end, and aspect
	pop	cx
	jc	gci9
	loop	gci1
	GENCALL	gfxCircle
gci9:	ret
ENDPROC	genCircle

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDraw
;
; Generate code for "DRAW string"
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genDraw
	call	genStr
	jc	gdr9
	GENCALL	gfxDraw
gdr9:	ret
ENDPROC	genDraw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genGet
;
; Generate code for "GET (x1,y1)-(x2,y2),array"
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genGet
	call	genPoint
	jc	gg9
	mov	ah,'-'
	call	genSymbol
	jc	gg9
	call	genPoint
	jc	gg9
	mov	ah,','
	call	genSymbol
	jc	gg9
	call	genArrayVar
	jc	gg9
	GENCALL	gfxGet
gg9:	ret
ENDPROC	genGet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLine
;
; Generate code for "LINE [(x1,y1)]-(x2,y2)[,[color][,B[F]]]"
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genLine
	call	peekNextSymbol
	jbe	gln1
	cmp	al,'-'			; is the first point omitted?
	jne	gln1			; no
	GENCALL	gfxLastPt		; yes, use the last point
	jmp	short gln2
gln1:	call	genPoint
	jc	gln9
gln2:	mov	ah,'-'
	call	genSymbol
	jc	gln9
	call	genPoint
	jc	gln9
	mov	cx,-1
	call	genOptLong		; color (AL = ',' if it consumed one)
	jc	gln9
	sub	dx,dx			; DX = 0 (no box)
	cmp	al,','
	je	gln5
	call	peekNextSymbol
	jbe	gln6
	cmp	al,','
	jne	gln6
	call	skipToken		; consume the comma
gln5:	mov	al,CLS_VAR
	call	getNextToken		; DS:SI -> name (CX = length)
	jbe	gln8
	mov	al,[si]
	or	al,20h
	cmp	al,'b'			; B?
	jne	gln8			; no
	inc	dx			; DX = 1 (box)
	dec	cx
	jz	gln6
	dec	cx
	jnz	gln8
	mov	al,[si+1]
	or	al,20h
	cmp	al,'f'			; BF?
	jne	gln8			; no
	inc	dx			; DX = 2 (filled box)
gln6:	mov	cx,dx
	sub	dx,dx
	GENPUSH	dx,cx
	GENCALL	gfxLine
	ret
gln8:	stc
gln9:	ret
ENDPROC	genLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPaint
;
; Generate code for "PAINT (x,y)[,[paint][,border]]"
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genPaint
	call	genPoint
	jc	gpa9
	mov	cx,-1
	call	genOptLong		; paint color
	jc	gpa9
	cmp	al,','			; did it consume another comma?
	jne	gpa1			; no
	call	genLong			; yes, so a border color must follow
	jmp	short gpa2
gpa1:	mov	cx,-1
	call	genOptLong		; border color
gpa2:	jc	gpa9
	GENCALL	gfxPaint
gpa9:	ret
ENDPROC	genPaint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPreset
;
; Generate code for "PRESET (x,y)[,color]", whose default color is 0
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genPreset
	sub	cx,cx
	jmp	short gps1
ENDPROC	genPreset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPset
;
; Generate code for "PSET (x,y)[,color]", whose default color is the
; foreground color
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genPset
	mov	cx,-1
gps1:	push	cx
	call	genPoint
	pop	cx
	jc	gps9
	call	genOptLong		; color
	jc	gps9
	GENCALL	gfxPset
gps9:	ret
ENDPROC	genPset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPut
;
; Generate code for "PUT (x,y),array[,action]", where action is PSET,
; PRESET, XOR (the default), OR, or AND (see PUT_* in gfx.asm).
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genPut
	call	genPoint
	jc	gpu9
	mov	ah,','
	call	genSymbol
	jc	gpu9
	call	genArrayVar
	jc	gpu9
	sub	cx,cx			; CX = 0 (XOR)
	call	peekNextSymbol
	jbe	gpu7
	cmp	al,','
	jne	gpu7
	call	skipToken		; consume the comma
	mov	al,CLS_KEYWORD
	call	getNextToken		; (XOR, OR, and AND are CLS_SYM)
	jbe	gpu8
	mov	cl,1
	cmp	ah,CLS_KEYWORD
	jne	gpu5
	cmp	al,TOK_PSET
	je	gpu7
	inc	cx
	cmp	al,TOK_PRESET
	je	gpu7
	jmp	short gpu8
gpu5:	dec	cx			; CX = 0
	cmp	al,'X'			; XOR?
	je	gpu7
	mov	cl,3
	cmp	al,'|'			; OR?
	je	gpu7
	inc	cx
	cmp	al,'A'			; AND?
	jne	gpu8
gpu7:	sub	dx,dx
	GENPUSH	dx,cx
	GENCALL	gfxPut
	ret
gpu8:	stc
gpu9:	ret
ENDPROC	genPut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genOptLong
;
; Generate code for an optional long expression that follows a comma (see
; genOptArg).
;
; Inputs:
;	CX = default value (-1 or 0)
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;	AL = ',' if the expression consumed a comma that followed it
;
; Modifies:
;	Any
;
DEFPROC	genOptLong
	mov	al,0
	mov	dl,VAR_LONG		; fall into genOptArg
ENDPROC	genOptLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genOptArg
;
; Generate code for an optional expression that follows a comma: if the next
; symbol is a comma (or AL says that it was already consumed), and unless
; another comma (or nothing) follows it, we generate the expression;
; otherwise, we generate the default value (for a double, the default must be
; 0, which is a null pointer).
;
; Inputs:
;	AL = ',' if the preceding comma was already consumed, otherwise 0
;	CX = default value (-1 or 0)
;	DL = type of the expression (VAR_LONG or VAR_DOUBLE)
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;	AL = ',' if the expression consumed a comma that followed it
;
; Modifies:
;	Any
;
DEFPROC	genOptArg
	push	dx
	push	cx
	cmp	al,','			; already consumed a comma?
	je	goa2			; yes
	call	peekNextSymbol
	jbe	goa8			; no comma
	cmp	al,','
	jne	goa8			; no comma
	call	skipToken		; consume the comma
goa2:	call	peekNextSymbol
	jz	goa8			; nothing follows
	jc	goa5			; not a symbol, so it's an expression
	cmp	al,','
	je	goa8			; another comma
	cmp	al,':'
	je	goa8			; end of the statement
goa5:	pop	cx
	call	genExpr
	pop	cx			; CL = type
	jbe	goa9
	push	ax
	mov	al,cl
	call	genCvtType
	pop	ax
	ret
goa8:	pop	cx
	pop	dx
	mov	dx,cx
	GENPUSH	dx,cx
	mov	al,0
	clc
	ret
goa9:	stc
	ret
ENDPROC	genOptArg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPoint
;
; Generate code for "(x,y)", which pushes x and y (as longs).
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genPoint
	mov	ah,'('
	call	genSymbol
	jc	gpt9
	call	genLong			; x
	jc	gpt9
	cmp	al,','
	jne	gpt8
	call	genLong			; y
	jc	gpt9
	cmp	al,')'
	je	gpt9			; (carry is clear)
gpt8:	stc
gpt9:	ret
ENDPROC	genPoint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genSymbol
;
; Inputs:
;	AH = required symbol
;	DS:BX -> TOKLETs
;
; Outputs:
;	Carry clear if the next token was the symbol (and it's consumed)
;
; Modifies:
;	AX, CX
;
DEFPROC	genSymbol
	push	ax
	call	getNextSymbol
	pop	cx
	jbe	gsy8
	cmp	al,ch
	je	gsy9			; (carry is clear)
gsy8:	stc
gsy9:	ret
ENDPROC	genSymbol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; skipToken
;
; Consumes the token that peekNextSymbol (or peekNextToken) just returned.
;
; Inputs:
;	None
;
; Outputs:
;	BX = offset of next TOKLET
;
; Modifies:
;	BX, SI
;
DEFPROC	skipToken
	mov	si,ds:[PSP_HEAP]
	mov	bx,[si].TOKLET_NEXT
	ret
ENDPROC	skipToken

CODE	ENDS

	end
