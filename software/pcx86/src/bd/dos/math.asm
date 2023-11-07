;
; BASIC-DOS Math Library
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; atoi
;
; Convert string at DS:SI to number in AX using base BL, using validation
; values at ES:DI.  It will also advance SI past the first non-digit character
; to facilitate parsing of a series of delimited, validated numbers.
;
; For validation, ES:DI must point to a triplet of (def,min,max) 16-bit values
; and like SI, DI will be advanced, making it easy to parse a series of values,
; each with their own set of (def,min,max) values.
;
; For no validation (and to leave SI pointing to the first non-digit), set
; DI to -1.
;
; Returns:
;	AX = value, DS:SI -> next character (ie, AFTER first non-digit)
;	Carry set on a validation error (AX will be set to the default value)
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	atoi,DOS
	mov	cx,-1
	DEFLBL	atoi_len,near		; CX = length
	mov	bl,[bp].REG_BL
	DEFLBL	atoi_base,near		; BL = base (eg, 10)
	mov	bh,0
	mov	[bp].TMP_BX,bx		; TMP_BX equals 16-bit base
	mov	[bp].TMP_AL,bh		; TMP_AL is sign (0 for +, -1 for -)
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	ASSUME	DS:NOTHING, ES:NOTHING
	and	[bp].REG_FL,NOT FL_CARRY

	mov	ah,-1			; cleared when digit found
	sub	bx,bx			; DX:BX = value
	sub	dx,dx			; (will be returned in DX:AX)

ai0:	jcxz	ai6
	lodsb				; skip any leading whitespace
	dec	cx
	cmp	al,CHR_SPACE
	je	ai0
	cmp	al,CHR_TAB
	je	ai0

	cmp	al,'-'			; minus sign?
	jne	ai1			; no
	cmp	byte ptr [bp].TMP_AL,0	; already negated?
	jl	ai6			; yes, not good
	dec	byte ptr [bp].TMP_AL	; make a note to negate later
	jmp	short ai4

ai1:	cmp	al,'a'			; remap lower-case
	jb	ai2			; to upper-case
	sub	al,20h
ai2:	cmp	al,'A'			; remap hex digits
	jb	ai3			; to characters above '9'
	cmp	al,'F'
	ja	ai6			; never a valid digit
	sub	al,'A'-'0'-10
ai3:	cmp	al,'0'			; convert ASCII digit to value
	jb	ai6
	sub	al,'0'
	cmp	al,[bp].TMP_BL		; outside the requested base?
	jae	ai6			; yes
	cbw				; clear AH (digit found)
;
; Multiply DX:BX by the base in TMP_BX before adding the digit value in AX.
;
	push	ax
	xchg	ax,bx
	mov	[bp].TMP_DX,dx
	mul	word ptr [bp].TMP_BX	; DX:AX = orig BX * BASE
	xchg	bx,ax			; DX:BX
	xchg	[bp].TMP_DX,dx
	xchg	ax,dx
	mul	word ptr [bp].TMP_BX	; DX:AX = orig DX * BASE
	add	ax,[bp].TMP_DX
	adc	dx,0			; DX:AX:BX = new result
	xchg	dx,ax			; AX:DX:BX = new result
	test	ax,ax
	jz	ai3a
	int	04h			; signal overflow
ai3a:	pop	ax			; DX:BX = DX:BX * TMP_BX

	add	bx,ax			; add the digit value in AX now
	adc	dx,0
	jno	ai4
;
; This COULD be an overflow situation UNLESS DX:BX is now 80000000h AND
; the result is going to be negated.  Unfortunately, any negation may happen
; later, so it's insufficient to test the sign in TMP_AL; we'll just have to
; allow it.
;
	test	bx,bx
	jz	ai4
	int	04h			; signal overflow

ai4:	jcxz	ai6
	lodsb				; fetch the next character
	dec	cx
	jmp	ai1			; and continue the evaluation

ai6:	cmp	byte ptr [bp].TMP_AL,0
	jge	ai6a
	neg	dx
	neg	bx
	sbb	dx,0
	into				; signal overflow if set

ai6a:	cmp	di,-1			; validation data provided?
	jg	ai6c			; yes
	je	ai6b			; -1 for 16-bit result only
	mov	[bp].REG_DX,dx		; -2 for 32-bit result (update REG_DX)
ai6b:	dec	si			; rewind SI to first non-digit
	add	ah,1			; (carry clear if one or more digits)
	jmp	short ai9

ai6c:	test	ah,ah			; any digits?
	jz	ai6d			; yes
	mov	bx,es:[di]		; no, get the default value
	stc
	jmp	short ai8
ai6d:	cmp	bx,es:[di+2]		; too small?
	jae	ai7			; no
	mov	bx,es:[di+2]		; yes (carry set)
	jmp	short ai8
ai7:	cmp	es:[di+4],bx		; too large?
	jae	ai8			; no
	mov	bx,es:[di+4]		; yes (carry set)
ai8:	lea	di,[di+6]		; advance DI in case there are more
	mov	[bp].REG_DI,di		; update REG_DI

ai9:	mov	[bp].REG_AX,bx		; update REG_AX
	mov	[bp].REG_SI,si		; update caller's SI, too
	ret
ENDPROC atoi

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; atof64
;
; Inputs:
;	DS:SI -> string
;
; Outputs:
;	ES:DI -> FAC with result
;
; Modifies:
;
DEFPROC	atof64,DOS
	ret
ENDPROC atof64

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; itof64
;
; Inputs:
;	DX:AX = 32-bit value
;
; Outputs:
;	ES:DI -> FAC with result
;
; Modifies:
;
DEFPROC	itof64,DOS
	ret
ENDPROC itof64

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; div_32_16
;
; Divide DX:AX by CX, returning quotient in DX:AX and remainder in BX.
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	div_32_16
	mov	bx,ax			; save low dividend in BX
	mov	ax,dx			; divide high dividend
	sub	dx,dx			; DX:AX = new dividend
	div	cx			; AX = high quotient
	xchg	ax,bx			; move to BX, restore low dividend
	div	cx			; AX = low quotient
	xchg	dx,bx			; DX:AX = new quotient, BX = remainder
	ret
ENDPROC	div_32_16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mul_32_16
;
; Multiply DX:AX by CX, returning result in DX:AX.
;
; Modifies:
;	AX, DX
;
DEFPROC	mul_32_16
	push	bx
	mov	bx,dx
	mul	cx			; DX:AX = orig AX * CX
	push	ax			;
	xchg	ax,bx			; AX = orig DX
	mov	bx,dx			; BX:[SP] = orig AX * CX
	mul	cx			; DX:AX = orig DX * CX
	add	ax,bx
	adc	dx,0
	xchg	dx,ax
	pop	ax			; DX:AX = new result
	pop	bx
	ret
ENDPROC	mul_32_16

DOS	ends

	end
