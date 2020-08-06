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

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; print32
;
; Since expressions are evaluated left-to-right, their results are pushed
; left-to-right as well.  Since the number of parameters is variable, we must
; walk the stacked parameters back to the beginning, pushing the offset of
; each as we go, and then popping and printing our way back to the end again.
;
; Inputs:
;	N pairs of variable types/values pushed on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	print32,FAR
	mov	bp,sp
	add	bp,4
	sub	bx,bx
	push	bx			; push end-of-args marker
	mov	bx,bp
p1:	mov	al,[bp]			; AL = arg type
	test	al,al
	jz	p2
	push	bp
	add	bp,6			; 6 bytes (2 for type, 4 for value)
	cmp	al,VAR_DOUBLE
	jb	p1
	add	bp,4
	jmp	p1
p2:	add	bp,2
	sub	bp,bx
	mov	cs:[p32retn],bp		; modify the RETF N with proper N 
p3:	pop	bp
	test	bp,bp			; end-of-args marker?
	jz	p8			; yes
	mov	al,[bp]
	cmp	al,VAR_LONG		; AL = arg type
	jne	p3
	mov	ax,[bp+2]
	mov	dx,[bp+4]
	PRINTF	<"%#ld ">,ax,dx		; DX:AX = 32-bit value
	jmp	p3
p8:	PRINTF	<13,10>
	db	OP_RETF_N
	DEFLBL	p32retn,word
	dw	0
ENDPROC	print32

CODE	ENDS

	end
