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

	EXTERNS	<FUNCTBL>,word
	EXTERNS	<FUNCTBL_SIZE>,abs

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

DEFPROC	dosexit,far
	iret
ENDPROC	dosexit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dosfunc (INT 21h)
;
; Inputs:
;	Varies
;
; Outputs:
;	Varies
;
	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	dosfunc,far
	sti
	cld				; we assume CLD everywhere
	push	ax
	push	bx
	push	cx
	push	dx
	push	ds
	push	si
	push	es
	push	di
	push	bp
	push	cs
	pop	ds
	ASSUME	DS:DOS
	sub	bp,bp			; not sure this is the best default
	mov	es,bp			; for ES, but I'm going to go with it
	ASSUME	ES:BIOS			; for now...
	mov	bp,sp
	and	[bp].REG_FL,NOT FL_CARRY
	cmp	ah,FUNCTBL_SIZE
	jae	dc8
	mov	bl,ah
	mov	bh,0
	add	bx,bx
	call	FUNCTBL[bx]
	jnc	dc9
;
; We'd just as soon IRET to the caller (which also restores their D flag),
; so we now update FL_CARRY on the stack (which we already cleared on entry).
;
dc8:	or	[bp].REG_FL,FL_CARRY
dc9:	pop	bp
	pop	di
	pop	es
	ASSUME	ES:NOTHING
	pop	si
	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	iret
ENDPROC	dosfunc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_none (handler for unimplemented DOS functions)
;
; Inputs:
;	Varies
;
; Outputs:
;	REG_AX = ERR_INVALID, carry set
;
	ASSUME	CS:DOS, DS:DOS, ES:NOTHING, SS:NOTHING

DEFPROC	dos_none
	mov	[bp].REG_AX,ERR_INVALID
	stc
	ret
ENDPROC	dos_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Far return used by sysinit for making calls to resident code (see dos_call).
;
DEFPROC	dos_return,far
	ret
ENDPROC	dos_return

DOS	ends

	end
