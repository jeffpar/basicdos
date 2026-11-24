;
; BASIC-DOS Code Generator: Doubles
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The floating-point generators that only doubles need (see genfpu.asm, whose
; genConstDouble, genPushSlot, genFnCall, genCallFPUDst2, genCallFPUDst, and
; genCallFPU reach these through genUpper).
;
; This module is not part of COMMAND's core (see CMD.LRF and HEAP.ASM), and
; when only the core is loaded, there are no doubles either (cmdInit leaves
; PSP_FPUTBL zero), so the generators that need these report "Not enough
; memory" instead (eg, for SQR or CDBL).
;
	include	cmd.inc
	include	gen.inc
	include	8086.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<genExpr,getNextSymbol,genCallFar,genPushImm>
	EXTNEAR	<genCvtType,genBlkData>
	EXTABS	<TOK_ABS>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dblConst (genConstDouble)
;
; Generate code for a double constant: the constant is converted now (with
; FPU_ATOD) and stored in a slot in the code block, and since doubles are
; always passed by reference, the generated code pushes a pointer to the slot.
;
; Inputs:
;	DS:SI -> numeric string
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	dblConst
	call	genSlot			; DX = offset of slot
	push	bx
	push	di
	mov	di,dx			; ES:DI -> slot
	mov	cx,FPU_ATOD
	call	callFPU			; DS:SI -> numeric string
	mov	dx,di			; DX = offset of slot again
	pop	di
	pop	bx
	jc	gcc9			; conversion error
	mov	al,OP_PUSH_CS
	stosb
	jmp	genPushImm		; push offset of slot (carry clear)
gcc9:	ret
ENDPROC	dblConst

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dblPushSlot (genPushSlot)
;
; Reserve an 8-byte slot (initialized to zero) in the code block, and generate
; code to push a pointer to it (eg, for the return value of a VAR_DOUBLE
; function).
;
; Inputs:
;	ES:DI -> code block
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	dblPushSlot
	call	genSlot			; DX = offset of slot
	push	di
	mov	di,dx
	sub	ax,ax
	mov	cx,4
	rep	stosw			; zero the slot
	pop	di
	mov	ax,OP_PUSH_MEM
	call	genBlkData		; PUSH CS:[CBLK_DATA]
	jmp	genPushImm		; push offset of slot
ENDPROC	dblPushSlot

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dblFnCall (genFnCall)
;
; Generate code for a numeric function keyword (eg, "SIN(x)"), which calls
; the corresponding FPU$ function (see FN_FPUTBL); the argument is converted
; to a double if necessary, and so is the result.
;
; Inputs:
;	AL = keyword ID (TOK_ABS through TOK_TAN)
;	DS:BX -> TOKLETs (after the keyword)
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	dblFnCall
	sub	al,TOK_ABS
	cbw
	push	ax			; save the function index
	call	getNextSymbol
	jbe	gfc8
	cmp	al,'('
	jne	gfc8
	call	genExpr			; generate the argument
	jc	gfc8
	cmp	ax,(CLS_SYM SHL 8) OR ')'
	jne	gfc8			; the argument must end with ')'
	mov	al,VAR_DOUBLE
	call	genCvtType		; convert the argument to a double
	jc	gfc8
	pop	si
	mov	cl,cs:[FN_FPUTBL+si]
	mov	ch,0			; CX = FPUTBL offset of the function
	jmp	dblCallFPUDst
gfc8:	pop	ax
	stc
	ret
ENDPROC	dblFnCall

;
; FN_FPUTBL contains the FPUTBL offsets of the numeric function keywords, in
; the same order as their IDs (TOK_ABS through TOK_TAN).
;
	DEFLBL	FN_FPUTBL,byte
	db	FPU_ABS, FPU_ATN, FPU_COS, FPU_ETOX, FPU_FIX
	db	FPU_INT, FPU_LOG, FPU_SIN, FPU_SQR, FPU_TAN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dblCallFPUDst2, dblCallFPUDst, dblCallFPU (genCallFPUDst2, etc)
;
; Generates a far call to the FPU$ driver's function at the specified
; FPUTBL offset.
;
; Doubles are always passed by reference, so any FPU function that produces
; a double stores it at ES:DI and returns a pointer to it.  Use dblCallFPUDst
; for those functions; it first reserves an 8-byte result slot in the code
; block and generates code that points ES:DI at it:
;
;	JMP	SHORT $+10
;	DQ	?		; result slot
;	PUSH	CS
;	POP	ES
;	MOV	DI,offset slot
;
; Every call gets its own slot, so a result remains valid until the same code
; runs again.  This means that any double result that must outlive the code
; that produced it (eg, a function's return value) must be copied.
;
; Inputs:
;	CX = FPUTBL offset (eg, FPU_ADD)
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if there's no FPUTBL
;
; Modifies:
;	CX, DX, DI
;
DEFPROC	dblCallFPUDst2
	push	ax
	mov	al,16			; FPU_CVT2LD requires 2 slots
	jmp	short gcd1
	DEFLBL	dblCallFPUDst,near
	push	ax
	mov	al,8
gcd1:	call	genSlotAL		; DX = offset of result slot
	mov	ax,OP_MOV_ES_MEM
	call	genBlkData		; MOV ES,CS:[CBLK_DATA]
	mov	al,OP_MOV_DI
	stosb
	xchg	ax,dx
	stosw
	pop	ax
	DEFLBL	dblCallFPU,near
	push	si
	push	ds
	lds	si,ss:[PSP_FPUTBL]
	mov	dx,ds			; DX = FPUTBL segment
	test	dx,dx			; is there an FPUTBL?
	stc
	jz	gcf9			; no
	add	si,cx
	mov	cx,[si]			; DX:CX -> FPUTBL function
	call	genCallFar
gcf9:	pop	ds
	pop	si
	ret
ENDPROC	dblCallFPUDst2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genSlot
;
; Reserves an 8-byte slot (or AL bytes, if using genSlotAL) in the code block,
; preceded by a short jump around it.
;
; Inputs:
;	ES:DI -> code block
;
; Outputs:
;	DX = offset of slot
;	ES:DI -> code block (after the slot)
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	genSlot
	mov	al,8
	DEFLBL	genSlotAL,near
	mov	ah,al
	mov	al,OP_JMPS
	stosw
	mov	dx,di			; DX = offset of slot
	mov	al,ah
	mov	ah,0
	add	di,ax
	ret
ENDPROC	genSlot

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; callFPU
;
; Calls the FPU$ driver's function at the specified FPUTBL offset now (eg,
; FPU_ATOD to convert a constant while generating code).
;
; Inputs:
;	CX = FPUTBL offset (eg, FPU_ATOD)
;	Other registers as required by the function
;
; Outputs:
;	As returned by the function, or carry set if there's no FPUTBL
;
; Modifies:
;	AX, BX, plus whatever the function modifies
;
DEFPROC	callFPU
	push	ds
	lds	bx,ss:[PSP_FPUTBL]	; DS:BX -> FPUTBL
	mov	ax,ds
	add	bx,cx
	mov	bx,[bx]			; AX:BX -> FPUTBL function
	pop	ds
	test	ax,ax			; is there an FPUTBL?
	stc
	jz	cfp9			; no
	push	ax
	push	bx
	mov	bx,sp
	call	dword ptr ss:[bx]
	pop	bx			; (POPs don't modify flags)
	pop	bx
cfp9:	ret
ENDPROC	callFPU

CODE	ENDS

	end
