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
	EXTERNS	<ctrlc_all,ctrlc_active>,byte
	EXTERNS	<msc_sigctrlc>,near

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_dverr (INT 00h)
;
; If a "divide exception" occurs, we catch it here and (eventually) do
; something reasonable with it.
;
DEFPROC	dos_dverr,DOSFAR
	PRINTF	<"division error @%08lx",13,10>
	int 3
	iret
ENDPROC	dos_dverr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_sstep (INT 01h)
;
; If an INT 01h instruction is executed, we treat it as an assertion failure.
;
; We make no effort to distinguish this from the FL_TRAP bit set in flags,
; since that would presumably be done by a debugger, which would have replaced
; the INT 01h vector with its own handler.
;
DEFPROC	dos_sstep,DOSFAR
	PRINTF	<"assert @%08lx",13,10>
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
	PRINTF	<"overflow error @%08lx",13,10>
	int 3
	iret
ENDPROC	dos_oferr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_term (INT 20h)
;
; TODO
;
DEFPROC	dos_term,DOSFAR
	int 3
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
	sub	sp,size REG_WS
	push	ax			; order of pushes must match REG_FRAME
	push	bx
	push	cx
	push	dx
	push	ds
	push	si
	push	es
	push	di
	push	bp
	mov	bp,sp

	IF REG_DIAG
	call	dos_diag
	DEFLBL	dos_diag,near
	ENDIF

	and	[bp].REG_FL,NOT FL_CARRY
	cmp	ah,FUNCTBL_SIZE
	cmc
	jb	dc9

	mov	bx,cs
	mov	ds,bx
	ASSUME	DS:DOS
	mov	es,bx
	ASSUME	ES:DOS

	test	[ctrlc_active],-1	; has CTRLC been detected?
	jz	dc1			; no
	cmp	ah,DOS_UTIL		; utility functions shall be exempt
	je	dc1			; from CTRLC checking
	test	[ctrlc_all],-1		; is checking enabled for all others?
	jz	dc1			; no
	call	msc_sigctrlc		; check CTRLC
;
; While we assign DS and ES to the DOS segment on DOS function entry,
; we do NOT require or assume they will still be set that way on exit.
;
dc1:	sub	bx,bx
	mov	bl,ah
	add	bx,bx
;
; For convenience, all general-purpose registers except BX, DS, and ES still
; contain their original values.
;
	call	FUNCTBL[bx]
	ASSUME	DS:NOTHING, ES:NOTHING
;
; We'd just as soon IRET to the caller (which also restores their D flag),
; so we now update FL_CARRY on the stack (which we already cleared on entry).
;
dc9:	adc	[bp].REG_FL,0

	DEFLBL	dos_exit,near

	IF REG_DIAG
	pop	bp
	ASSERTZ	<cmp bp,offset dos_diag>
	ENDIF

	pop	bp
	pop	di
	pop	es
	pop	si
	pop	ds
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	add	sp,size REG_WS
	iret
ENDPROC	dos_func

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_abort (INT 22h handler)
;
; TODO
;
DEFPROC	dos_abort,DOSFAR
	int 3
	iret
ENDPROC	dos_abort

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_ctrlc (INT 23h handler)
;
; TODO (for now, our default behavior, unlike DOS, is to NOT terminate)
;
DEFPROC	dos_ctrlc,DOSFAR
	mov	ah,DOS_DSK_RESET
	int	21h
	; stc
	; ret	2
	iret
ENDPROC	dos_ctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_error (INT 24h handler)
;
; TODO
;
DEFPROC	dos_error,DOSFAR
	int 3
	iret
ENDPROC	dos_error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_default (currently used for INT 28h and INT 2Ah-2Fh)
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
; moving the NEAR CALL return address into the FAR CALL return address, then
; replacing the NEAR CALL return address with the current flags, and finally
; moving the DOS function # from CL to AH.
;
; Not being familiar with the CALL 0005h interface, whether that's actually
; sufficient remains to be seen.
;
DEFPROC	dos_call5,DOSFAR
	push	bp
	mov	sp,bp
	mov	ax,[bp+4]
	mov	[bp],ax
	pushf				; since we didn't arrive here via INT,
	pop	[bp+4]			; these flags should have interrupts on
	pop	bp
	mov	ah,cl
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
	mov	al,ah
	mov	ah,0
	PRINTF	<"unsupported DOS function %02xh request @%08lx",13,10>,ax,[bp].REG_IP,[bp].REG_CS
	mov	[bp].REG_AX,ERR_INVALID
	stc
	ret
ENDPROC	func_none

DOS	ends

	end
