;
; BASIC-DOS Code Generator Function Calls
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for calls to predefined and user-defined functions in
; expressions (see genExpr in genexp.asm).
;
	include	cmd.inc
	include	gen.inc

CODE    SEGMENT

	EXTNEAR	<genExpr,genCvtType,genPushSlot,getVar,holdStr,swapArgs>
	EXTNEAR	<genCallCS,genCallFar,genPushImmLong,genPushBPOffset>
	EXTNEAR	<genPushLong,genPushZeroLong>
	EXTNEAR	<getNextSymbol,peekNextSymbol>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genFuncExpr
;
; Generate code for "func(parm1,parm2,...)".  The func variable has already
; been parsed and DX:SI has been set to the corresponding function data.
;
; NOTE: Function data for predefined functions is actually at CS:SI, but
; since we must also support user-defined functions, we can't assume that.
; This is why we must use the loadFuncData helper function, instead of simple
; LODSW CS: instructions.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;	DX:SI -> function data
;
; Outputs:
;	Carry clear if successful, AH = return type
;
; Modifies:
;	Any
;
DEFPROC	genFuncExpr
	LOCVAR	nFuncParms,byte
	LOCVAR	nFuncType,byte
	LOCVAR	pFuncData,dword
	ENTER
	sub	cx,cx			; CX = 0 if no parms supplied
	mov	[pFuncData].OFF,si
	mov	[pFuncData].SEG,dx
	call	loadFuncData
	mov	word ptr [nFuncType],ax	; nFuncType = AL, nFuncParms = AH
;
; NOTE: peekNextSymbol can "fail" for any number of reasons, including
; the fact that not all operators that may follow an unparenthesized function
; reference are symbols (eg, "MOD").  So we must be very forgiving here.
;
	call	peekNextSymbol		; check for parenthesis
	jbe	gfe0
	cmp	al,'('
	jne	gfe0
	inc	cx			; CX = 1 if one or more parms supplied
	call	getNextSymbol		; consume the parenthesis
;
; For VAR_LONG functions, the generated stack frame needs to begin with room
; for a VAR_LONG return value; we use genPushLong instead of genPushZeroLong
; because it generates less code AND it doesn't matter what value gets pushed.
; For VAR_DOUBLE functions, the return value is a pointer to a slot in our
; code block, where the function will store its result.
;
gfe0:	cmp	[nFuncType],VAR_DOUBLE
	jne	gfe0a
	push	cx
	call	genPushSlot
	pop	cx
	jmp	short gfe1
gfe0a:	call	genPushLong

gfe1:	dec	[nFuncParms]		; more parameters?
	jl	gfe6			; no
	jcxz	gfe3			; yes, but no (more) have been supplied

	call	genExpr			; process parameter expression
	jbe	gfe3			; no value supplied

	push	ax			; save last symbol from genExpr
	call	loadFuncData		; AL = parameter type
	cmp	al,VAR_LSKIP		; optional VAR_LONG we can skip?
	jne	gfe1b			; no
	mov	al,VAR_LONG
	cmp	dl,VAR_STR		; was a string supplied instead?
	jne	gfe1b			; no
	push	cx
	push	dx
	mov	al,ah
	cbw
	cwd
	xchg	cx,ax			; DX:CX = default value
	call	genPushImmLong		; push the default value
	GENCALL	swapArgs		; and move it below the string
	pop	dx
	pop	cx
	dec	[nFuncParms]		; the string is the next parameter
	call	loadFuncData		; AL = its type
;
; A string passed to a user-defined function must be held (see holdStr),
; since the function may use its parameter more than once.
;
gfe1b:	cmp	al,VAR_STR		; string parameter?
	jne	gfe1c			; no
	mov	si,cs
	cmp	[pFuncData].SEG,si	; for a user-defined function?
	je	gfe1c			; no
	push	cx
	push	dx
	GENCALL	holdStr
	pop	dx
	pop	cx
gfe1c:	push	cx
	call	genCvtType		; convert to the parameter type
	pop	cx
	pop	ax			; restore last symbol
	jc	gfe9			; error

	cmp	ah,CLS_SYM		; was last token a symbol?
	jne	gfe9			; no, error
	cmp	al,')'			; yes, closing parenthesis?
	jne	gfe2			; no
	sub	cx,cx			; zero number of remaining parms
	jmp	gfe1

gfe2:	cmp	al,','			; comma?
	jne	gfe9			; no, error
	test	cl,cl			; are more parameters allowed?
	jz	gfe9			; no
	jmp	gfe1
;
; No parameter value was supplied, so if the parameter isn't optional,
; that's an error.
;
gfe3:	call	loadFuncData
	and	al,0FCh			; VAR_CHAR, VAR_LSKIP -> VAR_LONG
	cmp	al,VAR_LONG		; TODO: currently supports default
	stc				; parameter values for VAR_LONG only
	jne	gfe9
	mov	al,ah			; AL = default value
	cmp	al,PARM_REQUIRED	; is the parameter optional?
	stc
	je	gfe9			; no
	cbw
	cwd				; DX:AX = default value
	xchg	cx,ax			; DX:CX
	call	genPushImmLong		; push it
	sub	cx,cx
	jmp	gfe1			; continue processing parameters

gfe6:	jcxz	gfe7
	cmp	al,')'
	jne	gfe9			; something is malformed
gfe7:	call	loadFuncData		; AX = function address offset
	xchg	cx,ax
	call	loadFuncData		; AX = function address segment
	xchg	dx,ax
	test	dx,dx
	jnz	gfe8
	mov	dx,cs
gfe8:	GENCALL	dx,cx			; generate call to function DX:CX
	mov	ah,[nFuncType]		; AH = return type
	jmp	short gfe10		; GENCALL should have cleared carry
gfe9:	stc
gfe10:	LEAVE
	ret

	DEFLBL	loadFuncData,near
	push	ds
	lds	si,[pFuncData]
	lodsw
	mov	[pFuncData].OFF,si
	pop	ds
	ret
ENDPROC	genFuncExpr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genFuncParm
;
; Generate code for accessing parameter N (of CL parameters).
;
; For example, if CL is 3 and the parameter # is 2, calculate the
; parameter offset ((count - parm #) * 4 + 6) and generate the code:
;
;	push	[bp+(offset+2)]
;	push	[bp+(offset+0)]
;
; Inputs:
;	CL = parm count
;	DX:SI -> parm data
;	ES:DI -> code block
;
; Outputs:
;	If carry clear, AH = parm type (from parm data)
;
; Modifies:
;	AX, DI
;
DEFPROC	genFuncParm
	call	getVar			; AL = parm type, AH = parm #
	sub	cl,ah
	jc	gfp9			; parm # inconsistency
	mov	ah,al
	push	ax
	mov	ch,0
	add	cx,cx
	add	cx,cx
	add	cx,8			; adjust CX for high word first
	call	genPushBPOffset
	dec	cx
	dec	cx			; then back down to the low word
	call	genPushBPOffset
	pop	ax
	clc
gfp9:	ret
ENDPROC	genFuncParm

CODE	ENDS

	end
