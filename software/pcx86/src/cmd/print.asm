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
;	1 (offset to) 16-bit value pushed on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	print16,FAR
	pop	dx
	pop	cx			; CX:DX = return address
	pop	di
	pop	es			; ES:DI -> value
	PRINTF	<"%d",13,10>,es:[di]
	push	cx			; ie, "JMP CX:DX"
	push	dx
	ret
ENDPROC	print16

CODE	ENDS

	end
