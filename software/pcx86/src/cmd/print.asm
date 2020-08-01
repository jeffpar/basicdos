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
; print16
;
; Inputs:
;	1 16-bit value on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX, SI, DI
;
DEFPROC	print16,FAR
	pop	dx
	pop	es			; ES:DX = return address
	pop	si			; ES:SI -> value
	PRINTF	<"%d",13,10>,es:[si]
	push	es
	push	dx
	ret
ENDPROC	print16

CODE	ENDS

	end
