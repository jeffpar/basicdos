;
; BASIC-DOS Printing Functions
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
; print32
;
; Inputs:
;	1 (pointer to) 32-bit value pushed on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	print32,FAR
	pop	di
	pop	dx			; DX:DI = return address
	pop	si
	pop	ds			; DS:SI -> value
	lodsw
	xchg	bx,ax
	lodsw
	PRINTF	<"%ld",13,10>,bx,ax	; AX:BX = 32-bit value
	push	dx			; ie, "JMP DX:DI"
	push	di
	ret
ENDPROC	print32

CODE	ENDS

	end
