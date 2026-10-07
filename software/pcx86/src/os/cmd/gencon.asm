;
; BASIC-DOS Code Generator: Console I/O
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for these console I/O statements:
;
;	CLS				(genCLS)
;	COLOR				(genColor)
;	ECHO				(genEcho)
;	LOCATE				(genLocate)
;	PRINT				(genPrint)
;	SCREEN				(genScreen)
;	WIDTH				(genWidth)
;
; See gencmd.asm for an overview of all the gen*.asm files.  Like gencmd.asm,
; these functions are called while generating code, with DS:BX -> TOKLETs and
; ES:DI -> code block.
;
	include	cmd.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<genExpr,getNextToken,genCallCS,genPushImm,genPushImmByte>
	EXTNEAR	<genPushImmByteAL,genPushImmByteAH,genPushImmLong,genCvtType>
	EXTNEAR	<peekNextSymbol>
	EXTNEAR	<clearScreen,printArgs,printEcho,setColor,setFlags>
	EXTNEAR	<setPos,setScreen,setWidth,redirOut,redirEnd,ensureRoom>
	EXTABS	<TOK_OFF,TOK_ON>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCLS
;
; Generate code for "CLS"
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
DEFPROC	genCLS
	GENCALL	clearScreen
	ret
ENDPROC	genCLS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genColor
;
; Generate code for "COLOR [fgnd][,[bgnd][,border]]"
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
DEFPROC	genColor
	mov	si,offset setColor
	jmp	short genArgs
ENDPROC	genColor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLocate
;
; Generate code for "LOCATE [row][,[col][,cursor]]"
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
DEFPROC	genLocate
	mov	si,offset setPos
	jmp	short genArgs
ENDPROC	genLocate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genScreen
;
; Generate code for "SCREEN [mode][,burst]"
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
DEFPROC	genScreen
	mov	si,offset setScreen
	jmp	short genArgs
ENDPROC	genScreen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genWidth
;
; Generate code for "WIDTH columns"
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
DEFPROC	genWidth
	mov	si,offset setWidth	; fall into genArgs
ENDPROC	genWidth

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genArgs
;
; Generate code to push a series of numeric arguments (as longs), followed by
; the number of arguments, and then a call to the function in SI, which must
; begin by calling getArgs.  An omitted argument (eg, the 1st argument in
; "LOCATE ,5") is pushed as -1.
;
; Inputs:
;	SI = offset of function (in our CODE segment)
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genArgs
	push	si			; save the function
	sub	cx,cx			; CX = # args
ga1:	call	peekNextSymbol
	jbe	ga2			; not a symbol
	cmp	al,','			; omitted argument?
	jne	ga2			; no
	mov	si,ds:[PSP_HEAP]
	mov	bx,[si].TOKLET_NEXT	; consume the comma
	push	cx
	GENPUSH	-1,-1
	pop	cx
	inc	cx
	jmp	ga1
ga2:	call	genExpr
	jb	ga9
	je	ga8
	push	ax
	push	cx
	mov	al,VAR_LONG
	call	genCvtType		; arguments must be longs
	pop	cx
	pop	ax
	jc	ga9
	inc	cx
	cmp	al,','			; was the last symbol a comma?
	je	ga1			; yes, go back for more
ga8:	GENPUSH	cx
	pop	cx
	GENCALL	cx
	ret
ga9:	pop	si			; discard the function
	ret
ENDPROC	genArgs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genEcho
;
; Process "ECHO".  If "ECHO ON" or "ECHO OFF", generate call to setFlags.
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
DEFPROC	genEcho
	mov	al,CLS_KEYWORD
	call	getNextToken
	jb	gec9
	jnz	gec1
	GENCALL	printEcho
	ret
gec1:	cmp	al,TOK_ON
	jne	gec2
	mov	ah,NOT CMD_NOECHO
	jmp	short gec8
gec2:	cmp	al,TOK_OFF
	stc
	jne	gec9
	mov	ah,CMD_NOECHO
gec8:	mov	al,OP_MOV_AL
	stosw				; "MOV AL,xx" where XX is value in AH
	GENCALL	setFlags
gec9:	ret
ENDPROC	genEcho

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPrint
;
; Generate code to "PRINT" a series of values.
;
; Inputs:
;	BX = offset of next TOKLET
;	ES:DI -> next unused location in code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genPrint
	GENPUSHB VAR_NONE		; push end-of-args marker
gp1:	call	genExpr
	jnc	gp2
	test	dh,dh			; if there were no tokens
	stc				; then ignore the error
	jnz	gp9			; (PRINT without args is allowed)
gp2:	jz	gp8
	push	ax
	mov	al,dl			; AL = VAR_LONG, VAR_STR, or VAR_DOUBLE
	GENPUSHB al
	pop	ax
	cmp	ah,CLS_KEYWORD		; did a keyword (eg, ELSE) end the
	je	gp8			; expression?
	cmp	ax,(CLS_SYM SHL 8) OR ':'; or a colon?
	je	gp8			; yes, so we're done
	mov	ah,VAR_COMMA		; comma (03h)
	cmp	al,','			; was the last symbol a comma?
	je	gp6			; yes
;
; Semi-colon is the other valid separator, but we no longer explicitly
; check for it, because historically PRINT presumes a semi-colon whenever
; a pair of values are separated only by whitespace (eg, if A = 2 and B = 3,
; "PRINT A B" behaves exactly like "PRINT A;B", displaying " 2  3").
;
; Unfortunately, in MSBASIC, that's only true for variables, not constants
; (eg, "PRINT 2 3" will print the number "23").  This is a parsing difference
; which we neither approve of nor emulate.
;
	mov	ah,VAR_SEMI		; presume semi-colon (02h) then
	test	al,al
	jz	gp8

gp6:	GENPUSHB ah			; "MOV AL,[VAR_SEMI or VAR_COMMA]"
	jmp	gp1			; continue processing arguments
gp8:	GENCALL	printArgs		; all done
gp9:	ret
ENDPROC	genPrint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genRedir
;
; Check a line for ":>" (or ":>>"), which redirects the output of the entire
; line to a file (eg, PRINT "hello" :> TEST).  If found, the line's commands
; end before the ":>" (we trim both TOKLET_END and LINE_LEN, the latter for
; genDOS), and we generate a call to redirOut, along with a word in the code
; for redirOut to record the redirection; genRedirEnd ends it.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	If carry set, error (eg, no filename)
;	Otherwise, AX = 0 if no redirection; otherwise, AX = original LINE_LEN
;	(which the caller must restore), and DX:CX -> redirection word
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	genRedir
	push	bx
	mov	si,ds:[PSP_HEAP]
	sub	bx,size TOKLET
	jmp	short gr1
gr0:	pop	bx			; no redirection (AX = 0, carry clear)
	ret
gr1:	add	bx,size TOKLET
	sub	ax,ax
	cmp	bx,[si].TOKLET_END	; any tokens left?
	jae	gr0			; no (and carry is clear)
	cmp	[bx].TOKLET_CLS,CLS_SYM
	jne	gr1
	mov	cx,[bx].TOKLET_OFF	; CX -> symbol in LINEBUF
	xchg	bx,cx
	cmp	word ptr [bx],'>:'	; ":>"?
	xchg	bx,cx
	jne	gr1
;
; The line's commands end at the ":>" (at CX).
;
	mov	[si].TOKLET_END,bx
	lea	bx,[si].LINEBUF		; BX -> LINEBUF
	sub	cx,bx			; CX = length of line before ":>"
	xchg	cx,[si].LINE_LEN	; CX = original length
	push	cx			; save it for the caller
	add	cx,bx			; CX -> end of line
	add	bx,[si].LINE_LEN	; BX -> ":>"
	lea	si,[bx+2]		; SI -> after ":>"
	mov	ax,1			; AX = 1 (create)
	cmp	byte ptr [si],'>'	; ":>>"?
	jne	gr2			; no
	inc	ax			; AX = 2 (append)
	inc	si
gr2:	cmp	si,cx			; skip leading whitespace
	jae	gr3
	cmp	byte ptr [si],' '
	ja	gr3
	inc	si
	jmp	gr2
gr3:	mov	bx,cx			; BX -> end of line
gr4:	cmp	bx,si			; trim trailing whitespace
	jbe	gr5
	cmp	byte ptr [bx-1],' '
	ja	gr5
	dec	bx
	jmp	gr4
gr5:	sub	bx,si			; BX = length of filename
	jz	gr8			; there's no filename
	push	ax			; save mode
	mov	ax,(2 SHL 8) OR OP_JMPS	; JMP over the redirection word
	stosw
	mov	cx,di			; CX = offset of redirection word
	sub	ax,ax
	stosw
	push	cx
	GENPUSH	es,cx			; push pointer to redirection word
	pop	cx
	pop	dx			; DX = mode
	push	cx
	GENPUSH	dx			; push mode
	GENPUSH	bx			; push length of filename
	mov	bx,ds:[PSP_HEAP]
	lea	cx,[bx].LINEBUF
	sub	si,cx			; SI = offset of filename in the line
	mov	cx,[bx].LINE_PTR.OFF
	add	cx,si
	mov	dx,[bx].LINE_PTR.SEG
	GENPUSH	dx,cx			; push pointer to filename
	GENCALL	redirOut
	pop	cx
	mov	dx,es			; DX:CX -> redirection word
	pop	ax			; AX = original length (carry clear)
	jmp	short gr9
gr8:	pop	ax			; discard original length
	stc
gr9:	pop	bx
	ret
ENDPROC	genRedir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genRedirEnd
;
; Generate a call to redirEnd at the end of a line redirected by genRedir.
;
; Inputs:
;	DX:CX -> redirection word
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	genRedirEnd
	mov	ax,16
	call	ensureRoom
	jc	gre9
	GENPUSH	dx,cx			; push pointer to redirection word
	GENCALL	redirEnd
gre9:	ret
ENDPROC	genRedirEnd

CODE	ENDS

	end
