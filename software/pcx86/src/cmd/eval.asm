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
; evalAdd16
;
; Inputs:
;	2 (offsets to) 16-bit values pushed on stack
;
; Outputs:
;	1 (offset to) 16-bit sum pushed back onto stack
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	evalAdd16,FAR
	pop	dx
	pop	cx			; CX:DX = return address
	pop	di
	pop	es			; ES:DI -> 1st arg
	mov	ax,es:[di]
	pop	di
	pop	es			; ES:DI -> 2nd arg
	add	ax,es:[di]
	mov	di,offset TMP16
	mov	es,cx
	mov	es:[di],ax
	push	es			; ES:DI -> new arg
	push	di
	push	cx			; ie, "JMP CX:DX"
	push	dx
	ret
ENDPROC	evalAdd16

CODE	ENDS

	end
