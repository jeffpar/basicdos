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

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalAddLong
;
; Inputs:
;	2 32-bit values pushed on stack
;
; Outputs:
;	1 32-bit sum pushed back onto stack
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	evalAddLong,FAR
	pop	di
	pop	dx			; DX:DI = return address
	pop	cx
	pop	bx			; BX:CX = 1st arg
	DEFLBL	evalAddSubLong,near
	pop	ax
	add	cx,ax
	pop	ax
	adc	bx,ax			; BX:CX = 1st arg + 2nd arg
	push	bx
	push	cx
	push	dx			; ie, "JMP DX:DI"
	push	di
	ret
ENDPROC	evalAddLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalSubLong
;
; Inputs:
;	2 32-bit values pushed on stack
;
; Outputs:
;	1 32-bit difference pushed back onto stack
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	evalSubLong,FAR
	pop	di
	pop	dx			; DX:DI = return address
	pop	cx
	pop	bx			; BX:CX = 1st arg
	neg	cx
	adc	bx,0
	neg	bx			; BX:CX negated
	jmp	short evalAddSubLong
ENDPROC	evalSubLong

CODE	ENDS

	end
