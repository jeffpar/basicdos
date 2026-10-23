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
; in gfx.asm (and gfxc.asm, for CIRCLE):
;
;	CIRCLE				(genCircle)
;	DRAW				(genDraw)
;	GET				(genGet)
;	LINE				(genLine)
;	MOUSE				(genMouse)
;	PAINT				(genPaint)
;	PSET and PRESET			(genPset and genPreset)
;	PUT				(genPut)
;	VIEW				(genView)
;	WINDOW				(genWindow)
;
; Coordinates can be absolute or relative (STEP); see genPoint.
;
; See gencmd.asm for an overview of all the gen*.asm files.  Like gencmd.asm,
; these functions are called while generating code, with DS:BX -> TOKLETs and
; ES:DI -> code block.
;
;
; These generators are not part of COMMAND's core (see CMD.LRF and HEAP.ASM):
; when only the core is loaded, genCommands refuses their keywords with "Not
; enough memory".  GET and PUT, which are also file statements, reach
; genGetGfx and genPutGfx from genfile.asm, and LINE, which is also LINE
; INPUT, reaches genLineGfx from gencon.asm via genUpper (see gencmd.asm).
;
	include	cmd.inc
	include	gen.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<genLong,genStr,genArrayVar,getNextToken,getNextSymbol>
	EXTNEAR	<peekNextSymbol,genCallCS,genPushImmLong,genExpr,genCvtType>
	EXTNEAR	<gfxDraw,gfxGet,gfxLastPt,gfxLine,gfxPaint,gfxPset,gfxPut>
	EXTNEAR	<gfxCircle,skipToken,mouseOn,mouseOff,peekNextToken>
	EXTNEAR	<gfxPt,gfxStep,gfxPtD,gfxStepD,genCallFPUDst,compError>
	EXTNEAR	<gfxView,gfxViewOff,gfxWindow,gfxWindowOff,gfxRadD>
	EXTABS	<TOK_PSET,TOK_PRESET,TOK_ON,TOK_OFF,TOK_STEP,TOK_SCREEN>

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
	mov	al,0
	call	genPoint
	jc	gci9
	mov	ah,','
	call	genSymbol
	jc	gci9
	call	genExpr			; radius
	jbe	gci8
	push	ax
	cmp	dl,VAR_DOUBLE		; a double?
	jne	gci0			; no
	GENCALL	gfxRadD			; yes, so convert it (see getRadius)
	jmp	short gci0a
gci0:	mov	al,VAR_LONG
	call	genCvtType
gci0a:	pop	ax
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
	ret
gci8:	stc
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
; genGetGfx
;
; Generate code for "GET (x1,y1)-(x2,y2),array"; genGet (see genfile.asm)
; comes here when GET is followed by '('.
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
DEFPROC	genGetGfx
	mov	al,1			; (the 2nd point may be relative to it)
	call	genPoint
	jc	gg9
	mov	ah,'-'
	call	genSymbol
	jc	gg9
	mov	al,0
	call	genPoint
	jc	gg9
	mov	ah,','
	call	genSymbol
	jc	gg9
	call	genArrayVar
	jc	gg9
	GENCALL	gfxGet
gg9:	ret
ENDPROC	genGetGfx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLineGfx
;
; Generate code for "LINE [(x1,y1)]-(x2,y2)[,[color][,B[F]]]"; genLine (see
; gencon.asm) comes here, via genUpper, unless INPUT follows LINE.
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
DEFPROC	genLineGfx
	call	peekNextSymbol
	jbe	gln1
	cmp	al,'-'			; is the first point omitted?
	jne	gln1			; no
	GENCALL	gfxLastPt		; yes, use the last point
	jmp	short gln2
gln1:	mov	al,1			; (the 2nd point may be relative to it)
	call	genPoint
	jc	gln9
gln2:	mov	ah,'-'
	call	genSymbol
	jc	gln9
	mov	al,0
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
ENDPROC	genLineGfx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPaint
;
; Generate code for "PAINT (x,y)[,[paint][,[border][,background]]]", where
; paint is a color or a tile string, and background (a string) is allowed
; only with a tile; for a color, -1 is pushed in its place (see gfxPaint).
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
	mov	al,0
	call	genPoint
	jc	gpa9
	call	peekNextSymbol
	jbe	gpa1			; no paint argument
	cmp	al,','
	jne	gpa1
	call	skipToken		; consume the comma
	call	peekNextSymbol
	jz	gpa1			; nothing follows
	jc	gpa2			; not a symbol, so it's an expression
	cmp	al,','
	je	gpa1			; another comma
	cmp	al,':'
	je	gpa1			; end of the statement
gpa2:	call	genExpr			; paint
	jbe	gpa8
	mov	si,-1			; SI = -1 (no tile)
	cmp	dl,VAR_STR		; a tile?
	jne	gpa3			; no
	inc	si			; SI = 0 (tile)
	jmp	short gpa4
gpa3:	push	ax
	push	si
	mov	al,VAR_LONG
	call	genCvtType
	pop	si
	pop	ax
	jc	gpa9
	jmp	short gpa4
gpa1:	GENPUSH	-1,-1			; the default paint color
	mov	si,-1			; SI = -1 (no tile)
	mov	al,0
gpa4:	push	si
	mov	cx,-1
	mov	dl,VAR_LONG
	call	genOptArg		; border (AL = ',' if paint had one)
	pop	si
	jc	gpa9
	test	si,si			; a tile?
	jnz	gpa6			; no
	sub	cx,cx
	mov	dl,VAR_CHAR
	call	genOptArg		; background (the default is CHR$(0))
	jc	gpa9
	jmp	short gpa7
gpa6:	GENPUSH	-1,-1			; no background
gpa7:	GENCALL	gfxPaint
	ret
gpa8:	stc
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
	mov	al,0
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
; genPutGfx
;
; Generate code for "PUT (x,y),array[,action]", where action is PSET,
; PRESET, XOR (the default), OR, or AND (see PUT_* in gfximg.asm); genPut
; (see genfile.asm) comes here when PUT is followed by '('.
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
DEFPROC	genPutGfx
	mov	al,0
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
ENDPROC	genPutGfx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genView
;
; Generate code for "VIEW [[SCREEN] (x1,y1)-(x2,y2)[,[fill][,border]]]"
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
DEFPROC	genView
	mov	cl,VAR_LONG
	mov	si,offset gfxViewOff
	call	genVW
	jc	gvw9
	mov	cx,-1
	call	genOptLong		; fill
	jc	gvw9
	mov	cx,-1
	mov	dl,VAR_LONG
	call	genOptArg		; border (AL = ',' if fill had one)
	jc	gvw9
	GENCALL	gfxView
gvw9:	ret
ENDPROC	genView

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genWindow
;
; Generate code for "WINDOW [[SCREEN] (x1,y1)-(x2,y2)]", whose coordinates
; are doubles (so the FPU$ driver is required).
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
DEFPROC	genWindow
	mov	cl,VAR_DOUBLE
	mov	si,offset gfxWindowOff
	call	genVW
	jc	gwn9
	GENCALL	gfxWindow
gwn9:	ret
ENDPROC	genWindow

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genVW
;
; Generate code for the "[SCREEN] (x1,y1)-(x2,y2)" of VIEW and WINDOW, which
; pushes 1 if SCREEN (0 if not) and the coordinates.  If neither SCREEN nor a
; point follows, we generate a call to the function at SI instead, and return
; to our caller's caller.
;
; Inputs:
;	CL = type of the coordinates (VAR_LONG or VAR_DOUBLE)
;	SI = function to call if there are no coordinates
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genVW
	push	cx
	sub	dx,dx			; DX = 0 (no SCREEN)
	mov	al,CLS_KEYWORD
	call	peekNextToken
	jbe	gvw1
	cmp	al,TOK_SCREEN		; SCREEN?
	jne	gvw1			; no
	call	skipToken
	inc	dx			; DX = 1 (SCREEN)
	jmp	short gvw2
gvw1:	call	peekNextSymbol
	jbe	gvw0			; no symbol follows
	cmp	al,'('			; a point?
	je	gvw2			; yes
gvw0:	pop	cx
	pop	cx			; discard our return address
	mov	cx,si
	GENCALL	cx
	clc
	ret
gvw2:	xchg	cx,dx
	sub	dx,dx
	GENPUSH	dx,cx
	pop	cx
	push	cx
	call	genCoords		; (x1,y1)
	jc	gvw8
	mov	ah,'-'
	call	genSymbol
	jc	gvw8
	pop	cx
	jmp	short genCoords		; (x2,y2)
gvw8:	pop	cx
	ret
ENDPROC	genVW

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCoords
;
; Generate code for "(x,y)", where x and y are converted to the type in CL.
;
; Inputs:
;	CL = type of the coordinates (VAR_LONG or VAR_DOUBLE)
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genCoords
	push	cx
	mov	ah,'('
	call	genSymbol
	pop	cx
	jc	gco9
	mov	ch,','
gco1:	push	cx
	call	genExpr
	pop	cx
	jbe	gco8
	cmp	al,ch			; followed by the expected symbol?
	jne	gco8			; no
	push	cx
	mov	al,cl
	call	genCvtType
	pop	cx
	jc	gco9
	cmp	ch,')'			; was it y?
	mov	ch,')'
	jne	gco1			; no
	ret
gco8:	stc
gco9:	ret
ENDPROC	genCoords

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
; Generate code for "[STEP] (x,y)", which pushes x and y as longs, or if
; either is a double, as doubles (converting the other).  As in MSBASIC, a
; STEP point is relative to the last point referenced, and every point becomes
; the last point referenced.  gfxPt (or gfxStep, gfxPtD, or gfxStepD) does
; that for a STEP point, a double point, or any point if AL is 1 (eg, LINE's
; 1st point, which a STEP 2nd point is relative to), and replaces x and y with
; screen coordinates; for any other point, the runtime function does it (see
; getPoint).
;
; Inputs:
;	AL = 1 to convert the point (as described above), 0 if not
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
	push	ax			; AL bit 0 = convert
	mov	al,CLS_KEYWORD
	call	peekNextToken
	jbe	gpt1
	cmp	al,TOK_STEP		; STEP?
	jne	gpt1			; no
	call	skipToken
	pop	ax
	or	al,2			; AL bit 1 = STEP
	push	ax
gpt1:	mov	ah,'('
	call	genSymbol
	jc	gpt8
	call	genExpr			; x
	jbe	gpt8
	cmp	al,','
	jne	gpt8
	push	dx			; DL = type of x
	call	genExpr			; y
	pop	cx			; CL = type of x
	jbe	gpt8
	cmp	al,')'
	jne	gpt8
	mov	al,VAR_DOUBLE
	cmp	cl,al			; is x a double?
	je	gpt3			; yes, so y must be one, too
	cmp	cl,VAR_LONG		; is x a long?
	jne	gpt7			; no, so it's a type mismatch
	cmp	dl,al			; is y a double?
	je	gpt2			; yes, so convert x
	mov	al,VAR_LONG		; no, so y must be a long
	call	genCvtType		; (which generates no code)
	pop	ax			; AL = flags
	jc	gpt9
	jmp	short gpt4
gpt2:	mov	cx,FPU_CVTL2D
	call	genCallFPUDst		; convert x to a double
	jmp	short gpt3a
gpt3:	call	genCvtType		; convert y to a double
	jc	gpt8
gpt3a:	pop	ax
	or	al,4			; AL bit 2 = doubles
;
; Use AL bits 1 and 2 (STEP and doubles) to select gfxPt, gfxStep, gfxPtD,
; or gfxStepD, if a call is required (ie, if any bit is set).
;
gpt4:	test	al,al			; is a call required?
	jz	gpt9			; no (carry is clear)
	shr	al,1
	cbw
	xchg	si,ax
	add	si,si
	mov	cx,cs:GFX_CVT[si]
	GENCALL	cx
	ret
gpt7:	mov	al,13			; "Type mismatch"
	call	compError
gpt8:	pop	ax
	stc
gpt9:	ret
ENDPROC	genPoint

GFX_CVT	dw	gfxPt, gfxStep, gfxPtD, gfxStepD

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
; genMouse
;
; Generate code for "MOUSE ON" and "MOUSE OFF" (see the MOUSE function, too).
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
DEFPROC	genMouse
	mov	al,CLS_KEYWORD
	call	getNextToken
	jbe	gmo9
	cmp	al,TOK_ON
	mov	cx,offset mouseOn
	je	gmo8
	cmp	al,TOK_OFF
	mov	cx,offset mouseOff
	jne	gmo9
gmo8:	GENCALL	cx
	clc
	ret
gmo9:	stc
	ret
ENDPROC	genMouse

CODE	ENDS

	end
