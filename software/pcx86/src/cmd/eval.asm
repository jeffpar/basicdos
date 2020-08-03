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
; evalAdd32
;
; Inputs:
;	2 (pointers to) 32-bit values pushed on stack
;
; Outputs:
;	1 (pointer to) 32-bit sum pushed back onto stack
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	evalAdd32,FAR
	pop	di
	pop	dx			; DX:DI = return address
	pop	si
	pop	ds			; DS:SI -> 1st arg
	lodsw
	xchg	bx,ax
	lodsw
	xchg	cx,ax			; CX:BX = 1st arg
	pop	si
	pop	ds			; DS:SI -> 2nd arg
	lodsw
	add	bx,ax
	lodsw
	adc	cx,ax			; CX:BX = 1st arg + 2nd arg
	mov	[bp],bx
	mov	[bp+2],cx
	push	ss			; SS:BP -> new arg
	push	bp
	push	dx			; ie, "JMP DX:DI"
	push	di
	ret
ENDPROC	evalAdd32

CODE	ENDS

	end
