;
; BASIC-DOS Driver/Application Interface Entry Points
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	extrn	CALLTBL:word, CALLTBL_SIZE:abs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dosexit (INT 20h)
;
; Inputs:
;	Varies
;
; Outputs:
;	Varies
;
	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	dosexit
dosexit	proc	far
	iret
dosexit	endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doscall (INT 21h)
;
; Inputs:
;	Varies
;
; Outputs:
;	Varies
;
	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	doscall
doscall	proc	far
	sti
	cld				; we assume CLD everywhere
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp
	push	ds
	push	es
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	bp,sp
	and	[bp].REG_FL,NOT FL_CARRY
	cmp	ah,CALLTBL_SIZE
	jae	dc8
	mov	bl,ah
	mov	bh,0
	add	bx,bx
	call	CALLTBL[bx]
	jnc	dc9
;
; We'd just as soon IRET to the caller (which restores their D flag),
; so we now update FL_CARRY on the stack (which we already cleared on entry).
;
dc8:	or	[bp].REG_FL,FL_CARRY
dc9:	pop	es
	pop	ds
	ASSUME	DS:NOTHING
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	iret
doscall	endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_nop (handler for unimplemented DOS functions)
;
; Inputs:
;	Varies
;
; Outputs:
;	REG_AX = ERR_INVALID, carry set
;
	ASSUME	CS:DOS, DS:DOS, ES:NOTHING, SS:NOTHING

	public	dos_nop
dos_nop	proc	near
	mov	[bp].REG_AX,ERR_INVALID
	stc
	ret
dos_nop	endp

DOS	ends

	end
