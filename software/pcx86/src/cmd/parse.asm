;
; BASIC-DOS Command Interpreter
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
; parseColor
;
; Parse "COLOR [fgnd],[bgnd],[border]"
;
; Inputs:
;	BX -> heap
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	parseColor
	ret
ENDPROC	parseColor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parseExpr
;
; Parse an expression.
;
; Inputs:
;	BX -> heap
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	parseExpr
	GETTOKEN 2		; DS:SI -> token #2, CX = length
	push	si
	mov	bl,10		; default to base 10
	cmp	word ptr [si],"x0"
	jne	pe1
	mov	bl,16		; "0x" prefix is present, so switch to base 16
	add	si,2		; and skip the prefix
pe1:	mov	ax,DOS_UTL_ATOI32
	int	21h
	pop	si
	jc	pe8		; apparently not a number
	PRINTF	<"Value is %ld (%#lx)",13,10>,ax,dx,ax,dx
	jmp	short pe9
pe8:	PRINTF	<"Invalid number: %.*s",13,10>,cx,si
pe9:	ret
ENDPROC	parseExpr

CODE	ENDS

	end
