;
; BASIC-DOS Code Generator: Floating-Point
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for these floating-point operations:
;
;	Numeric functions		(genFnCall: ABS, ATN, COS, EXP, FIX,
;					INT, LOG, SIN, SQR, TAN; see FN_FPUTBL)
;	Double constants		(genConstDouble, eg, "3.14" or "1E-5")
;	Type conversions		(genCvtType: between longs and doubles,
;					as LET, DEF, function parameters, and
;					COLOR require)
;	Double conditions		(genTestDouble: eg, "IF A THEN" when A
;					is a double, which is true if A <> 0)
;	Calls to FPU$ functions		(genCallFPUDst2, genCallFPUDst, and
;					genCallFPU, which genExpr uses for
;					operators and type conversions)
;
; Doubles are always passed by reference, so any generated code that produces
; a double needs a place for it; genSlot reserves an 8-byte slot inline in the
; code block for that purpose.  callFPU calls an FPU$ function immediately
; (eg, FPU_ATOD to convert a constant while generating code).
;
; Only genCvtType and genTestDouble are here, in COMMAND's core, since the
; core calls them for every type; the rest (including genSlot, callFPU, and
; genBlkData) are in gendbl.asm, which the stubs here reach through genUpper.
;
; See gencmd.asm for an overview of all the gen*.asm files.  Like gencmd.asm,
; these functions are called while generating code, with DS:BX -> TOKLETs and
; ES:DI -> code block.
;
	include	cmd.inc
	include	gen.inc
	include	8086.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<genCallCS,strToChar,compError,genUpper>
	EXTNEAR	<dblConst,dblPushSlot,dblFnCall,dblCallFPUDst2>
	EXTNEAR	<dblCallFPUDst,dblCallFPU>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genConstDouble, genPushSlot, genFnCall, genCallFPUDst2, genCallFPUDst,
; genCallFPU
;
; These generators are needed only for doubles, so they're outside COMMAND's
; core, in gendbl.asm (eg, dblConst for genConstDouble; see there for their
; inputs and outputs), and we reach them through genUpper, which reports
; "Not enough memory" if only the core was loaded.
;
; Modifies:
;	DX, and whatever the generator modifies
;
DEFPROC	genConstDouble
	mov	dx,offset dblConst
	jmp	short gfu
	DEFLBL	genPushSlot,near
	mov	dx,offset dblPushSlot
	jmp	short gfu
	DEFLBL	genFnCall,near
	mov	dx,offset dblFnCall
	jmp	short gfu
	DEFLBL	genCallFPUDst2,near
	mov	dx,offset dblCallFPUDst2
	jmp	short gfu
	DEFLBL	genCallFPUDst,near
	mov	dx,offset dblCallFPUDst
	jmp	short gfu
	DEFLBL	genCallFPU,near
	mov	dx,offset dblCallFPU
gfu:	jmp	genUpper
ENDPROC	genConstDouble

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCvtType
;
; Generate code to convert the value on the stack from one type to another
; (like MSBASIC, converting a long to a double or a double to a long, with
; rounding); any other mismatch is a "Type mismatch" error.
;
; VAR_CHAR (used only for parameters) requires a VAR_LONG, but it also
; accepts a VAR_STR, which is converted to the code of its first character.
;
; Inputs:
;	DL = type of the value (VAR_*)
;	AL = type required (VAR_*)
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if the types are incompatible
;
; Modifies:
;	CX, DX, DI (and AX and SI if the types are incompatible)
;
DEFPROC	genCvtType
	cmp	al,VAR_CHAR		; character code required?
	jne	gct0			; no
	mov	al,VAR_LONG
	cmp	dl,VAR_STR		; string value?
	jne	gct0			; no
	GENCALL	strToChar		; yes, convert it to a character code
	ret
gct0:	cmp	dl,al			; do the types already match?
	je	gct8			; yes
	mov	cx,FPU_CVT1LD
	cmp	al,VAR_DOUBLE		; double required?
	jne	gct1			; no
	cmp	dl,VAR_LONG		; long value?
	jne	gct9			; no
	jmp	genCallFPUDst
gct1:	mov	cx,FPU_CVT1DL
	cmp	al,VAR_LONG		; long required?
	jne	gct9			; no
	cmp	dl,VAR_DOUBLE		; double value?
	jne	gct9			; no
	jmp	genCallFPU
gct8:	clc
	ret
gct9:	mov	al,BERR_TYPE		; "Type mismatch"
	jmp	compError
ENDPROC	genCvtType

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genTestDouble
;
; If the value on the stack is a double, generate code to replace it with a
; long that's -1 if the double is non-zero and 0 if not (eg, for IF).
;
; Inputs:
;	DL = type of the value (VAR_*)
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	genTestDouble
	cmp	dl,VAR_DOUBLE
	clc
	jne	gtd9
	call	genPushSlot		; push a pointer to a zero
	mov	cx,FPU_NE
	jmp	genCallFPU		; and compare the double to it
gtd9:	ret
ENDPROC	genTestDouble

CODE	ENDS

	end
