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
	EXTERNS	<FUNCTBL_SIZE,UTILTBL_SIZE>,abs
	EXTERNS	<scb_active,key_boot>,word
	EXTERNS	<ddint_level>,byte
	EXTERNS	<msc_sigctrlc_read,msc_sigerr>,near

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_dverr (INT 00h)
;
; If a "divide exception" occurs, this default handler reports it and then
; aborts the current program.
;
DEFPROC	dos_dverr,DOSFAR
	IFDEF MAXDEBUG
	DBGBRK
	ENDIF
	push	ax
	IFNDEF	DEBUG
	PRINTF	<"Division error",13,10>
	ELSE
;
; Print the 32-bit return address on the stack, and since it's already on
; the stack, we don't have to push it, which means PRINTF won't try to pop it
; either.  However, since we had to push AX (the only register that PRINTF
; modifies), we must include a special PRINTF formatter (%U) that skips one
; 16-bit value on the stack.
;
	PRINTF	<"Division error @%U%08lx",13,10>
	ENDIF
	call	msc_sigerr
	pop	ax
	IFDEF DEBUG
	iret
	ELSE
	mov	ah,EXTYPE_DVERR
	jmp	dos_abort
	ENDIF
ENDPROC	dos_dverr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_sstep (INT 01h)
;
; If a trace interrupt (or an explicit INT 10h) occurs, and no debugger
; is currently running, we catch it here and ignore it.
;
DEFPROC	dos_sstep,DOSFAR
	iret
ENDPROC	dos_sstep

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_brkpt (INT 03h)
;
; If a breakpoint interrupt occurs, and no debugger is currently running,
; we catch it here and ignore it.
;
DEFPROC	dos_brkpt,DOSFAR
	iret
ENDPROC	dos_brkpt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_oferr (INT 04h)
;
; If an "overflow exception" occurs, this default handler reports it and
; signals the error.
;
DEFPROC	dos_oferr,DOSFAR
	IFDEF MAXDEBUG
	DBGBRK
	ENDIF
	push	ax
	IFNDEF	DEBUG
	PRINTF	<"Overflow error",13,10>
	ELSE
;
; Print the 32-bit return address on the stack, and since it's already on
; the stack, we don't have to push it, which means PRINTF won't try to pop it
; either.  However, since we had to push AX (the only register that PRINTF
; modifies), we must include a special PRINTF formatter (%U) that skips one
; 16-bit value on the stack.
;
	PRINTF	<"Overflow error @%U%08lx",13,10>
	ENDIF
	call	msc_sigerr
	pop	ax
	IFDEF DEBUG
	iret
	ELSE
	mov	ah,EXTYPE_OVERR
	jmp	dos_abort
	ENDIF
ENDPROC	dos_oferr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_opchk (INT 06h)
;
; This interrupt is used by DEBUG builds to perform "operation checks",
; based on the byte that follows the INT 06h instruction; eg:
;
;	CCh: breakpoint
;	F9h: assertion failure
;	FBh: 32-bit multiply check
;	FCh: 32-bit division check
;
; If the 8086 emulation environment isn't set up to intercept INT 06h and
; perform these checks, this handler ensures the checks are harmless.
;
DEFPROC	dos_opchk,DOSFAR
	IFDEF	DEBUG
	push	bp
	mov	bp,sp
	push	ax
	push	si
	push	ds
	lds	si,dword ptr [bp+2]	; DS:SI = CS:IP from stack
	cld
	lodsb
	mov	[bp+2],si		; update CS:IP to skip OPCHECK byte
	cmp	al,OP_ASSERT		; OP_ASSERT?
	jnz	oc9			; no
	PRINTF	<"Assertion failure @%08lx",13,10>,si,ds
oc9:	pop	ds
	pop	si
	pop	ax
	pop	bp
	ENDIF
;
; Even if you mistakenly run a DEBUG binary on a non-DEBUG system (which
; means all that's here is this IRET), any operation check should still be
; innocuous (but that's neither guaranteed nor recommended).
;
	iret
ENDPROC	dos_opchk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_term (INT 20h)
;
; NOTE: In PC DOS, this interrupt, as well as INT 21h AH=00h, apparently
; requires the call to be made from the segment containing the PSP (CS == PSP).
; We do not.  Also, the underlying function here (DOS_PSP_TERM) sets a default
; exit code (we use zero), whereas DOS_PSP_EXIT (4Ch) allows any exit code to
; be returned.
;
DEFPROC	dos_term,DOSFAR
	mov	ah,DOS_PSP_TERM
	int	21h
	iret
ENDPROC	dos_term

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_restart
;
; Default CTRLC response handler; if carry is set, call DOS_PSP_EXIT with
; (arbitrary) exit code -1.
;
; Inputs:
;	Carry determines whether we exit the process or restart the DOS call
;
; Outputs:
;	None
;
DEFPROC	dos_restart,DOSFAR
	jnc	dos_func
	mov	ah,EXTYPE_CTRLC
	DEFLBL	dos_abort,near
	mov	al,0FFh			; AL = exit code
	xchg	dx,ax			; DL = exit code, DH = exit type
	mov	ax,DOS_UTL_ABORT
	int	21h
	ASSERT	NEVER			; assert that we never get here
ENDPROC dos_restart

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	cld				; we assume CLD everywhere
	sub	sp,size WS_TEMP
	push	ax			; order of pushes must match REG_FRAME

	DEFLBL	dos_enter,near
	push	bx
	push	cx
	push	dx
	push	ds
	push	si
	push	es
	push	di
	push	bp
	mov	bp,sp

	IF REG_CHECK
	call	dos_check
	DEFLBL	dos_check,near
	ENDIF

	mov	bx,cs
	mov	ds,bx
	ASSUME	DS:DOS
	mov	es,bx
	ASSUME	ES:DOS
;
; Utility functions don't automatically re-enable interrupts, clear the carry,
; or check for CTRLC, since some of them are called from interrupt handlers.
;
	cmp	ah,DOS_UTL		; utility function?
	jne	dc1			; no
	cmp	al,UTILTBL_SIZE		; utility function within range?
	jae	dos_exit		; no
	mov	ah,FUNCTBL_SIZE		; the utility function table
	add	ah,al			; follows the DOS function table
	jmp	short dc2

dc1:	sti
	and	[bp].REG_FL,NOT FL_CARRY
	cmp	ah,FUNCTBL_SIZE
	cmc
	jb	dc9
;
; If SHIFT+L was pressed at boot (and this is a DEBUG build), log DOS calls.
;
	IFDEF DEBUG
	cmp	[key_boot].LOB,'L'
	jne	dc1a
	mov	bl,ah
	mov	bh,0
;
; %P is a special formatter that prints the caller's REG_CS:REG_IP-2 in hex;
; "#010" ensures it's printed with "0x" and 8 digits with leading zeroes.
;
	DPRINTF	<"%#010P: DOS function %02xh",13,10>,bx
	ENDIF
;
; If CTRLC checking is enabled for all (non-utility) functions and a CTRLC
; was detected (two conditions that we check with a single compare), signal it.
;
dc1a:	mov	bx,[scb_active]
	test	bx,bx
	jz	dc2			; TODO: always have an scb_active
	ASSERT	STRUCT,[bx],SCB
	cmp	word ptr [bx].SCB_CTRLC_ALL,0101h
	je	dc10			; signal CTRLC
;
; While we assign DS and ES to the DOS segment on DOS function entry,
; we do NOT require or assume they will still be set that way on exit.
;
dc2:	sub	bx,bx
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

	IF REG_CHECK
	pop	bp
	ASSERT	Z,<cmp bp,offset dos_check>
	ENDIF

	DEFLBL	dos_exit2,near

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
	add	sp,size WS_TEMP
	iret
dc10:	jmp	msc_sigctrlc_read
ENDPROC	dos_func

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_exret (INT 22h handler)
;
DEFPROC	dos_exret,DOSFAR
	ASSERT	NEVER			; assert that we never get here
	jmp	near ptr dos_term
ENDPROC	dos_exret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_ctrlc (INT 23h handler)
;
DEFPROC	dos_ctrlc,DOSFAR
	push	ax
	mov	ah,DOS_DSK_RESET
	int	21h
	pop	ax
	stc				; set carry to indicate termination
	ret
ENDPROC	dos_ctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_error (INT 24h handler)
;
; Outputs:
;	AL = 0:	ignore error
;	AL = 1:	retry operation
;	AL = 2:	abort program via INT 23h
;	AL = 3:	fail system call in progress
;
DEFPROC	dos_error,DOSFAR
	mov	al,CRERR_ABORT		; default to 2 (abort via INT 23h)
	iret
ENDPROC	dos_error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_default (currently used for INT 28h and INT 2Ah-2Fh)
;
DEFPROC	dos_default,DOSFAR
	iret
ENDPROC	dos_default

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; disk_read (INT 25h)
;
; TODO
;
DEFPROC	disk_read,DOSFAR
	iret
ENDPROC	disk_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; disk_write (INT 26h)
;
; TODO
;
DEFPROC	disk_write,DOSFAR
	iret
ENDPROC	disk_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_tsr (INT 27h)
;
; TODO
;
DEFPROC	dos_tsr,DOSFAR
	iret
ENDPROC	dos_tsr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	bp,sp
	mov	ax,[bp+6]
	mov	[bp+2],ax
	pushf				; since we didn't arrive here via INT,
	pop	[bp+6]			; these flags should have interrupts on
	pop	bp
	mov	ah,cl
	jmp	near ptr dos_func
ENDPROC	dos_call5

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_ddint_enter
;
; DDINT_ENTER is "revectored" here by sysinit.
;
; Inputs:
;	None
;
; Outputs:
; 	Carry clear (DOS interrupt processing enabled)
;
DEFPROC	dos_ddint_enter,DOSFAR
	inc	[ddint_level]
	clc
	ret
ENDPROC	dos_ddint_enter

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_ddint_leave
;
; DDINT_LEAVE is "revectored" here by sysinit.
;
; Inputs:
;	Carry set to reschedule, assuming ddint_level has dropped to zero
;
; Outputs:
; 	None
;
DEFPROC	dos_ddint_leave,DOSFAR
	cli
	dec	[ddint_level]
	jnz	ddl9
	jnc	ddl9
;
; If both Z and C are set, then enter DOS to perform a reschedule.
;
; TODO: Once sysinit has revectored DDINT_LEAVE, we're off and running, but
; the very first call to scb_yield will occur while scb_active is still zero,
; which scb_yield will misinterpret as a WAIT rather than a YIELD.  That's
; OK, but only so long as at least one SCB is runnable, and only so long as
; scb_active NEVER goes to zero again, lest we run the risk of blowing the
; stack, as successive timer interrupts attempt to yield and fail.
;
; There was no risk of that when scb_yield locked the SCBs first, but we
; prefer to no longer do that, because we want every yield to at least take
; a quick look at all the SCBs and "stoke" any SCB that would have started
; running earlier if another SCB hadn't been holding the lock.
;
	cld
	sub	sp,size WS_TEMP
	push	ax
	mov	ax,DOS_UTL_YIELD
	jmp	dos_enter
ddl9:	iret
ENDPROC	dos_ddint_leave

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
;
; %P is a special formatter that prints the caller's REG_CS:REG_IP-2 in hex;
; "#010" ensures it's printed with "0x" and 8 digits with leading zeroes.
;
	DPRINTF	<"%#010P: unsupported DOS function %02xh",13,10>,ax
	mov	[bp].REG_AX,ERR_INVALID
	stc
	ret
ENDPROC	func_none

DOS	ends

	end
