;
; BASIC-DOS Evaluation Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalAddLong
;
; Inputs:
;	2 32-bit values on stack (popped)
;
; Outputs:
;	1 32-bit sum on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalAddLong,FAR
	ARGLONG	addB			; second arg
	ARGLONG	addA			; first arg
	ENTER
	mov	ax,[addB].OFF
	add	[addA].OFF,ax
	mov	ax,[addB].SEG
	adc	[addA].SEG,ax
	LEAVE
	ret	4
ENDPROC	evalAddLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalSubLong
;
; Inputs:
;	2 32-bit values on stack (popped)
;
; Outputs:
;	1 32-bit difference on stack (pushed)
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	evalSubLong,FAR
	ARGLONG	subB			; second arg
	ARGLONG	subA			; first arg
	ENTER
	mov	ax,[subB].OFF
	sub	[subA].OFF,ax
	mov	ax,[subB].SEG
	sbb	[subA].SEG,ax
	LEAVE
	ret	4
ENDPROC	evalSubLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalMulLong
;
; Inputs:
;	2 32-bit values on stack (popped)
;
; Outputs:
;	1 32-bit product on stack (pushed)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	evalMulLong,FAR
	ARGLONG	mulB			; second arg
	ARGLONG	mulA			; first arg
	ENTER

	mov	ax,[mulB].OFF
	mul	[mulA].SEG
	xchg	cx,ax			; CX = mulB.OFF * mulA.SEG

	mov	ax,[mulA].OFF
	mul	[mulB].SEG
	add	cx,ax			; CX = sum of cross product

	mov	ax,[mulA].OFF
	mul	[mulB].OFF		; DX:AX = mulB.OFF * mulA.OFF
	add	dx,cx			; add cross product to upper word

	mov	[mulA].OFF,ax
	mov	[mulA].SEG,dx
	LEAVE
	ret	4
ENDPROC	evalMulLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalDivLong
;
; Inputs:
;	2 32-bit values on stack (popped)
;
; Outputs:
;	1 32-bit quotient on stack (pushed)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	evalDivLong,FAR
	int 3
	ret
ENDPROC	evalDivLong

CODE	ENDS

	end
