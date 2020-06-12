;
; BASIC-DOS Utility Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	DEFLBL	UTILTBL,word
	dw	util_strlen,util_atoi,util_none,util_none	; 00h-03h
	dw	util_strlen,util_atoi,util_none,util_none	; 04h-07h
	dw	util_strlen,util_atoi,util_none,util_none	; 08h-0Bh
	dw	util_strlen,util_atoi,util_none,util_none	; 0Ch-0Fh
	dw	util_strlen,util_atoi,util_none,util_none	; 10h-13h
	dw	util_strlen,util_atoi,util_none,util_none	; 14h-17h
	dw	util_strlen,util_atoi,util_none,util_none	; 18h-1Bh
	dw	util_strlen,util_atoi,util_none,util_none	; 1Ch-1Fh
	dw	util_strlen,util_atoi,util_none,util_none	; 20h-23h
	dw	util_strlen					; 24h
	DEFABS	UTILTBL_SIZE,<($ - UTILTBL) SHR 1>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_func (REG_AH = 18h)
;
; Inputs:
;	REG_AL = utility function (eg, UTIL_ATOI)
;
; Outputs:
;	Varies
;
DEFPROC	util_func,DOS
	mov	al,[bp].REG_AL		; AL = utility function #
	cmp	al,UTILTBL_SIZE
	cmc
	jb	dc9
	cbw
	mov	bx,ax
	add	bx,ax
	lds	si,dword ptr [bp].REG_SI
	les	di,dword ptr [bp].REG_DI
	ASSUME	DS:NOTHING,ES:NOTHING
	call	UTILTBL[bx]
	mov	[bp].REG_SI,si
	mov	[bp].REG_DI,di
	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
dc9:	ret
ENDPROC	util_func

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_strlen (AL = 00h or 24h)
;
; Returns the length of the DS:SI string in AX, using the terminator in AL.
;
; Modifies:
;	AX, CX
;
DEFPROC	util_strlen
	push	di
	push	es
	mov	di,si
	push	ds
	pop	es
	mov	cx,di
	not	cx			; CX = largest possible count
	repne	scasb
	je	usl9
	stc				; error if we didn't end on a match
usl9:	sub	di,si
	lea	ax,[di-1]		; don't count the terminator character
	pop	es
	pop	di
	ret
ENDPROC	util_strlen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_atoi
;
; Convert string at DS:SI to decimal, then validate using values at ES:DI.
;
; Returns:
;	AX = value, DS:SI -> next character (after non-decimal digit)
;	Carry will be set if there was an error, but AX will ALWAYS be valid
;
; Modifies:
;	AX, SI, DI
;
DEFPROC	util_atoi
	push	cx
	push	dx
	sub	ax,ax
	cwd
	mov	cx,10
ud1:	mov	dl,[si]
	cmp	dl,'0'
	jb	ud6
	sub	dl,'0'
	cmp	dl,cl
	jae	ud7
	inc	si
	push	dx
	mul	cx
	pop	dx
	add	ax,dx
	jmp	ud1
ud6:	test	dl,dl
	jz	ud7
	inc	si
ud7:	test	di,di			; validation data provided?
	jz	ud9a			; no
	cmp	ax,es:[di]		; too small?
	jae	ud8			; no
	mov	ax,es:[di]
	jmp	short ud9
ud8:	cmp	es:[di+2],ax		; too large?
	jae	ud9			; no
	mov	ax,es:[di+2]
ud9:	lea	di,[di+4]		; advance DI in case there are more
ud9a:	pop	dx
	pop	cx
	ret
ENDPROC util_atoi

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_none
;
; Modifies:
;	None
;
DEFPROC	util_none
	ret
ENDPROC	util_none

DOS	ends

	end
