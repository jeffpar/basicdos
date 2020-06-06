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
; dos_dverr (INT 00h)
;
; If a "divide exception" occurs, we catch it here and (eventually) do
; something reasonable with it.
;
DEFPROC	dos_dverr,DOSFAR
	iret
ENDPROC	dos_dverr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_sstep (INT 01h)
;
; If an INT 01h instruction is executed (or the TRAP flag was enabled), and
; no debugger is currently running, we catch it here and ignore it.
;
DEFPROC	dos_sstep,DOSFAR
	int 3
	iret
ENDPROC	dos_sstep

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_brkpt (INT 03h)
;
; If a breakpoint instruction is executed, and no debugger is currently running,
; we catch it here and ignore it.
;
DEFPROC	dos_brkpt,DOSFAR
	iret
ENDPROC	dos_brkpt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_oferr (INT 04h)
;
; If an "overflow exception" occurs, we catch it here and (eventually) do
; something reasonable with it.
;
DEFPROC	dos_oferr,DOSFAR
	iret
ENDPROC	dos_oferr

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
; dos_default (eg, INT 22h, INT 23h, INT 24h, INT 28h)
;
; For those software interrupts used by DOS for notification purposes,
; this provides a default handler.
;
DEFPROC	dos_default,DOSFAR
	iret
ENDPROC	dos_default

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
; dos_call5 (INT 30h)
;
; We typically arrive here via NEAR CALL 0005h to FAR CALL to FAR JMP in
; vector 30h.  We should be able to transform that into an INT 21h by "simply"
; replacing the NEAR CALL return address with current flags.
;
; Not being familiar with the CALL 0005h interface, whether that is actually
; sufficient remains to be seen.
;
DEFPROC	dos_call5,DOSFAR
	push	bp
	mov	sp,bp
	pushf
	pop	[bp+4]
	pop	bp
	jmp	dos_func
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
