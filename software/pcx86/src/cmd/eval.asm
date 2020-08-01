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
;	AX, BX, DX, SI, DI, ES
;
DEFPROC	evalAdd16,FAR
	pop	dx
	pop	es			; ES:DX = return address
	pop	si
	pop	di
	mov	ax,es:[si]
	add	ax,es:[di]
	mov	bx,offset TMP16
	mov	es:[bx],ax
	push	bx
	push	es
	push	dx
	ret
ENDPROC	evalAdd16

CODE	ENDS

	end
