;
; BASIC-DOS Code Generator: System Statements
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for these statements, whose runtime functions are in sys.asm
; (except for raiseError, which is in flow.asm):
;
;	CHAIN				(genChain)
;	DEF SEG				(genDef and genDefSeg)
;	ERROR				(genError)
;	KEY				(genKey)
;	PLAY				(genPlay)
;	POKE				(genPoke)
;	SOUND				(genSound)
;
; See gencmd.asm for an overview of all the gen*.asm files.  Like gencmd.asm,
; these functions are called while generating code, with DS:BX -> TOKLETs and
; ES:DI -> code block.
;
	include	cmd.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<genExpr,getNextToken,peekNextSymbol,genCallCS,genCvtType>
	EXTNEAR	<defSeg,defSegBasic,pokeByte,doSound,doPlay,doChain>
	EXTNEAR	<raiseError,genEnd,genDefFn,peekNextToken>
	EXTABS	<TOK_ON,TOK_SEG>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genChain
;
; Generate code for "CHAIN file[,line]", which runs the BAS file (like any
; other command) and then ends the program.  The line, if any, is evaluated
; but ignored for now, and none of CHAIN's other options are supported.
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
DEFPROC	genChain
	call	genStr
	jc	gch9
	cmp	al,','			; is there a line?
	jne	gch8			; no
	call	genLong
	jc	gch9
	mov	ax,OP_POP_DX_AX		; yes, discard it
	stosw
gch8:	GENCALL	doChain
	jmp	genEnd
gch9:	ret
ENDPROC	genChain

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDef
;
; Generate code for "DEF SEG[=segment]"; any other DEF is a user-defined
; function (see genDefFn).
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
DEFPROC	genDef
	mov	al,CLS_KEYWORD
	call	peekNextToken
	jbe	gdf9
	cmp	al,TOK_SEG
	je	gdf1
gdf9:	jmp	genDefFn
gdf1:	mov	si,ds:[PSP_HEAP]
	mov	bx,[si].TOKLET_NEXT	; consume SEG (and fall into genDefSeg)
ENDPROC	genDef

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDefSeg
;
; Generate code for "DEF SEG[=segment]" (after genDef has consumed DEF SEG).
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
DEFPROC	genDefSeg
	call	peekNextSymbol
	jbe	gds8			; no segment
	cmp	al,'='
	jne	gds8			; no segment
	mov	si,ds:[PSP_HEAP]
	mov	bx,[si].TOKLET_NEXT	; consume the '='
	mov	si,offset defSeg
	mov	cl,1
	jmp	short genLongs
gds8:	GENCALL	defSegBasic
	clc
	ret
ENDPROC	genDefSeg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genError
;
; Generate code for "ERROR n"
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
DEFPROC	genError
	mov	si,offset raiseError
	mov	cl,1
	jmp	short genLongs
ENDPROC	genError

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genKey
;
; Process "KEY ON" and "KEY OFF".  BASIC-DOS doesn't display function keys,
; so there's no code to generate.
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
DEFPROC	genKey
	mov	al,CLS_KEYWORD
	call	getNextToken
	jbe	gk9
	or	al,1			; TOK_OFF + 1 is TOK_ON
	cmp	al,TOK_ON		; KEY ON or KEY OFF?
	je	gk8			; yes (and carry is clear)
gk9:	stc
gk8:	ret
ENDPROC	genKey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPlay
;
; Generate code for "PLAY string"
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
DEFPROC	genPlay
	call	genStr
	jc	gpl9
	GENCALL	doPlay
gpl9:	ret
ENDPROC	genPlay

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPoke
;
; Generate code for "POKE offset,value"
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
DEFPROC	genPoke
	mov	si,offset pokeByte
	mov	cl,2
	jmp	short genLongs
ENDPROC	genPoke

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genSound
;
; Generate code for "SOUND frequency,duration"
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
DEFPROC	genSound
	mov	si,offset doSound
	mov	cl,2			; fall into genLongs
ENDPROC	genSound

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLongs
;
; Generate code to push CL comma-separated (long) expressions, all required,
; followed by a call to the function in SI.
;
; Inputs:
;	CL = # of expressions
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
DEFPROC	genLongs
	push	si			; save the function
gl1:	push	cx
	call	genLong
	pop	cx
	jc	gl9
	dec	cl			; any more expressions?
	jz	gl8			; no
	cmp	al,','			; yes, so was there a comma?
	je	gl1			; yes
	stc
	jmp	short gl9
gl8:	pop	cx
	GENCALL	cx
	ret
gl9:	pop	si			; discard the function
	ret
ENDPROC	genLongs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLong
;
; Generate code for a required expression, converted to a long.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;	AX = last result from getNextToken (see genExpr)
;
; Modifies:
;	Any
;
DEFPROC	genLong
	call	genExpr
	jbe	gln9			; error or no expression
	push	ax
	mov	al,VAR_LONG
	call	genCvtType
	pop	ax
	ret
gln9:	stc
	ret
ENDPROC	genLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genStr
;
; Generate code for a required string expression.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;	AX = last result from getNextToken (see genExpr)
;
; Modifies:
;	Any
;
DEFPROC	genStr
	call	genExpr
	jbe	gst9			; error or no expression
	cmp	dl,VAR_STR		; string?
	je	gst8			; yes (and carry is clear)
gst9:	stc
gst8:	ret
ENDPROC	genStr

CODE	ENDS

	end
