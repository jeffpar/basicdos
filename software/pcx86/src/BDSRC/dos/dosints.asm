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
; dos_term (INT 20h)
;
; TODO
;
DEFPROC	dos_term,DOSFAR
	iret
ENDPROC	dos_term

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_func (INT 21h)
;
; Inputs:
;	Varies
;
; Outputs:
;	Varies
;
DEFPROC	dos_func,DOSFAR
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
	mov	al,ah
	cmp	al,FUNCTBL_SIZE
	cmc
	jb	dc9
	cbw
	add	ax,ax
	mov	bx,ax
	call	FUNCTBL[bx]
;
; We'd just as soon IRET to the caller (which also restores their D flag),
; so we now update FL_CARRY on the stack (which we already cleared on entry).
;
dc9:	adc	[bp].REG_FL,0
	pop	bp
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
ENDPROC	dos_func

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_abort (INT 22h)
;
; TODO
;
DEFPROC	dos_abort,DOSFAR
	iret
ENDPROC	dos_abort

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_ctrlc (INT 23h)
;
; TODO
;
DEFPROC	dos_ctrlc,DOSFAR
	iret
ENDPROC	dos_ctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_error (INT 24h)
;
; TODO
;
DEFPROC	dos_error,DOSFAR
	iret
ENDPROC	dos_error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; disk_read (INT 25h)
;
; TODO
;
DEFPROC	disk_read,DOSFAR
	iret
ENDPROC	disk_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; disk_write (INT 26h)
;
; TODO
;
DEFPROC	disk_write,DOSFAR
	iret
ENDPROC	disk_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_tsr (INT 27h)
;
; TODO
;
DEFPROC	dos_tsr,DOSFAR
	iret
ENDPROC	dos_tsr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_call5
;
; TODO
;
DEFPROC	dos_call5,DOSFAR
	iret
ENDPROC	dos_call5

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; func_none (handler for unimplemented DOS functions)
;
; Inputs:
;	Varies
;
; Outputs:
;	REG_AX = ERR_INVALID, carry set
;
DEFPROC	func_none,DOS
	mov	[bp].REG_AX,ERR_INVALID
	stc
	ret
ENDPROC	func_none

DOS	ends

	end
