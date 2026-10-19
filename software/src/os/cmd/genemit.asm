;
; BASIC-DOS Code Generator Emitting Helpers
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The helpers that all the gen*.asm files use to emit code: calls (genCallCS
; and genCallFar, used by GENCALL) and pushes of immediate values (eg,
; genPushImmLong, used by GENPUSH, and genPushImmByte, used by GENPUSHB).
;
	DOSFUNC equ 1
	include	cmd.inc
	include	8086.inc

CODE    SEGMENT

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCallCS
;
; Inputs:
;	CS:CX -> function to call (or DX:CX if using genCallFar)
;
; Outputs:
;	Carry clear
;
; Modifies:
;	CX, DX, DI
;
DEFPROC	genCallCS
	mov	dx,cs
	DEFLBL	genCallFar,near
	push	ax
	mov	al,OP_CALLF
	stosb
	xchg	ax,cx
	stosw
	xchg	ax,dx
	stosw
	pop	ax
	clc
	ret
ENDPROC	genCallCS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPopBPOffset
;
; Inputs:
;	CX = offset
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI
;
DEFPROC	genPopBPOffset
	cmp	cx,7Fh
	ja	gpo1
	mov	ax,OP_POP_BP8
	stosw
	mov	al,cl
	stosb
	ret
gpo1:	mov	ax,OP_POP_BP16
	stosw
	mov	ax,cx
	stosw
	ret
ENDPROC	genPopBPOffset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushBPOffset
;
; Inputs:
;	CX = offset
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI
;
DEFPROC	genPushBPOffset
	cmp	cx,7Fh
	ja	gpu1
	mov	ax,OP_PUSH_BP8
	stosw
	mov	al,cl
	stosb
	ret
gpu1:	mov	ax,OP_PUSH_BP16
	stosw
	mov	ax,cx
	stosw
	ret
ENDPROC	genPushBPOffset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushImmByte
;
; Inputs:
;	AL = OP_MOV_AL
;	AH = value to push
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI
;
DEFPROC	genPushImmByteAL
	mov	ah,al
	DEFLBL	genPushImmByteAH,near
	mov	al,OP_MOV_AL
	DEFLBL	genPushImmByte,near
	stosw
	mov	al,OP_PUSH_AX
	stosb
	ret
ENDPROC	genPushImmByteAL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushImmLong
;
; While the general case looks like this 8-byte sequence:
;
;	MOV	AX,yyyy
;	PUSH	AX
;	MOV	AX,xxxx
;	PUSH	AX
;
; if we determine that DX (yyyy) is a sign-extension of CX (xxxx),
; we can generate this 6-byte sequence instead:
;
;	MOV	AX,xxxx
;	CWD
;	PUSH	DX
;	PUSH	AX
;
; and if CX (xxxx) is zero, it can be simplified to a 4-byte sequence
; (ie, genPushZeroLong):
;
;	XOR	AX,AX
;	PUSH	AX
;	PUSH	AX
;
; Inputs:
;	DX:CX = value to push
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	genPushImmLong
	IFDEF MAXDEBUG
	DPRINTF	'o',<"num %ld\r\n">,cx,dx
	ENDIF
	xchg	ax,dx			; AX has original DX
	xchg	ax,cx			; AX contains CX, CX has original DX
	cwd				; DX is 0 or FFFFh
	cmp	dx,cx			; same as original DX?
	xchg	cx,ax			; AX contains original DX, CX restored
	xchg	dx,ax			; DX restored
	jne	gpi7			; no, DX is not the same
	jcxz	genPushZeroLong		; jump if we can zero AX as well
	mov	al,OP_MOV_AX
	stosb
	xchg	ax,cx
	stosw
	mov	ax,OP_CWD OR (OP_PUSH_DX SHL 8)
	stosw
	jmp	short gpi8
gpi7:	mov	al,OP_MOV_AX
	stosb
	xchg	ax,dx
	stosw
	mov	ax,OP_PUSH_AX OR (OP_MOV_AX SHL 8)
	stosw
	xchg	ax,cx
	stosw
gpi8:	mov	al,OP_PUSH_AX
	stosb
	ret
ENDPROC	genPushImmLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushStr
;
; Copies the string at DS:SI with length CX into the code segment,
; pushing the far address of that string and then "leaping" over the string.
;
; Inputs:
;	DS:SI -> string (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX DI
;
DEFPROC	genPushStr
	mov	ax,OP_PUSH_CS OR (OP_CALL SHL 8)
	stosw
	mov	ax,cx
	inc	ax			; +1 for length byte
	stosw
	mov	al,cl
	stosb				; store the length byte
	rep	movsb			; followed by all the characters
	ret
ENDPROC	genPushStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushZeroLong
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI
;
DEFPROC	genPushZeroLong
	mov	ax,OP_ZERO_AX
	stosw
	DEFLBL	genPushLong,near
	mov	ax,OP_PUSH_AX OR (OP_PUSH_AX SHL 8)
	stosw
	ret
ENDPROC	genPushZeroLong

CODE	ENDS

	end
