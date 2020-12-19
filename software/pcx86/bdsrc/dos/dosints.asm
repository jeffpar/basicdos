;
; BASIC-DOS Driver/Application Interface Entry Points
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTWORD	<FUNCTBL>
	EXTABS	<FUNCTBL_SIZE,UTILTBL_SIZE>
	EXTWORD	<scb_active>
	EXTBYTE	<scb_locked,int_level>
	EXTNEAR	<msc_readctrlc,msc_sigerr>

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
	sub	si,3			; display the address of the INT 06h
	; PRINTF	<"Assertion failure @%08lx",13,10>,si,ds
	DBGBRK
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
; exit code (we use zero), whereas DOS_PSP_RETURN (4Ch) allows any exit code
; to be returned.
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
; Default CTRLC response handler; if carry is set, call DOS_PSP_RETURN with
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
	DOSUTIL	TERM
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
	push	bx
	push	cx
	push	dx
	DEFLBL	dos_enter,near
	push	ds
	push	si
	push	es
	push	di
	push	bp
	mov	bp,sp

dc0:	IF REG_CHECK			; in DEBUG builds, use CALL to push
	call	dos_check		; a marker ("dos_check") onto the stack
	DEFLBL	dos_check,near		; which REG_CHECK checks will verify
	ENDIF
;
; While we assign DS and ES to the DOS segment on DOS function entry, we
; do NOT assume they will still be set that way when the FUNCTBL call returns.
;
	mov	bx,cs
	mov	ds,bx
	ASSUME	DS:DOS
	mov	es,bx
	ASSUME	ES:DOS

	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	inc	[bx].SCB_INDOS
;
; Utility functions don't automatically re-enable interrupts, clear carry,
; or check for CTRLC, since some of them are called from interrupt handlers.
;
	cmp	ah,80h			; utility function?
	jb	dc1			; no
	sub	ah,80h
	cmp	ah,UTILTBL_SIZE		; utility function within range?
	jae	dos_leave		; no
	mov	bl,ah
	add	bl,FUNCTBL_SIZE		; the utility function table
	jmp	short dc2		; follows the DOS function table

dc1:	sti
	and	[bp].REG_FL,NOT FL_CARRY
	cmp	ah,FUNCTBL_SIZE
	cmc
	jb	dc3

	IFDEF	MAXDEBUG
	push	ax
	mov	al,ah
;
; %P is a special formatter that prints the caller's REG_CS:REG_IP-2 in hex;
; "#010" ensures it's printed with "0x" and 8 digits with leading zeroes.
;
	DPRINTF	'd',<"%#010P: DOS function %02bxh\r\n">,ax
	pop	ax
	ENDIF	; MAXDEBUG
;
; If CTRLC checking is enabled for all (non-utility) functions and a CTRLC
; was detected (two conditions that we check with a single compare), signal it.
;
	cmp	word ptr [bx].SCB_CTRLC_ALL,0101h
	je	dc4			; signal CTRLC
	mov	bl,ah
dc2:	mov	bh,0			; BX = function #
	add	bx,bx			; convert function # to word offset
;
; For convenience, general-purpose registers AX, CX, DX, SI, DI, and SS
; contain their original values.
;
	call	FUNCTBL[bx]
	ASSUME	DS:NOTHING, ES:NOTHING
;
; We'd just as soon IRET to the caller (which also restores their D flag),
; so we now update FL_CARRY on the stack (which we already cleared on entry).
;
dc3:	adc	[bp].REG_FL,0

	DEFLBL	dos_leave,near
	IF REG_CHECK			; in DEBUG builds, check the "marker"
	pop	bx			; that we pushed on entry
	ASSERT	Z,<cmp bx,offset dos_check>
	ENDIF
;
; Whenever the session's INDOS count returns to zero, check for a pending
; SCSTAT_ABORT; if set AND we're not in the middle of a hardware interrupt,
; clear the ABORT condition and simulate a DOSUTIL TERM session abort.
;
	mov	bx,[scb_active]
	ASSERT	STRUCT,cs:[bx],SCB
	dec	cs:[bx].SCB_INDOS
	ASSERT	GE
	jnz	dos_leave2
	test	cs:[bx].SCB_STATUS,SCSTAT_ABORT
	jz	dos_leave2
	cmp	word ptr [scb_locked],-1; do NOT abort if session or driver
	jne	dos_leave2		; lock levels are >= 0
	and	cs:[bx].SCB_STATUS,NOT SCSTAT_ABORT
;
; WARNING: This simulation of DOSUTIL TERM takes a shortcut by not updating
; REG_AH or REG_DX in REG_FRAME, but neither utl_term nor psp_termcode rely
; on REG_FRAME for their inputs, so while this is not completely kosher, we'll
; be fine.  The same is true for the termination code in int_leave.
;
	mov	dx,(EXTYPE_ABORT SHL 8) OR 0FFh
	mov	ah,DOS_UTL_TERM + 80h
	jmp	dc0

dc4:	jmp	msc_readctrlc

	DEFLBL	dos_leave2,near
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
ENDPROC	dos_func

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_exit (INT 22h handler)
;
DEFPROC	dos_exit,DOSFAR
	ASSERT	NEVER			; assert that we never get here
	jmp	near ptr dos_term
ENDPROC	dos_exit

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
; dos_util (INT 32h)
;
; We could jump straight to dos_func after adjusting the function number,
; but if a breakpoint has been set on dos_func, we'd rather not have dos_util
; calls triggering it as well; hence the redundant CLD and jmp + 1.
;
DEFPROC	dos_util,DOSFAR
	cld
	add	ah,80h
	jmp	near ptr dos_func + 1	; avoid the same entry point as INT 21h
ENDPROC	dos_util

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; int_enter
;
; DDINT_ENTER is "revectored" here by sysinit.
;
; Inputs:
;	None
;
; Outputs:
; 	Carry clear (DOS interrupt processing enabled)
;
DEFPROC	int_enter,DOSFAR
	inc	[int_level]
	clc
	ret
ENDPROC	int_enter

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; int_leave
;
; DDINT_LEAVE is "revectored" here by sysinit.
;
; Inputs:
;	Carry set to reschedule, assuming int_level has dropped below zero
;
; Outputs:
; 	None
;
DEFPROC	int_leave,DOSFAR
	cli
	dec	[int_level]
	jge	ddl9
	jnc	ddl9
;
; Enter DOS to perform a reschedule.
;
; However, we first take a peek at the current SCB's INDOS count and
; ABORT flag; if the count is zero and the flag is set, force termination.
;
	cld
	sub	sp,size WS_TEMP
	push	ax
	push	bx
	push	cx
	push	dx
	mov	ah,DOS_UTL_YIELD + 80h
	mov	bx,cs:[scb_active]
	cmp	cs:[bx].SCB_INDOS,0
	jne	ddl8
	test	cs:[bx].SCB_STATUS,SCSTAT_ABORT
	jz	ddl8
	and	cs:[bx].SCB_STATUS,NOT SCSTAT_ABORT
	mov	dx,(EXTYPE_ABORT SHL 8) OR 0FFh
	mov	ah,DOS_UTL_TERM + 80h
ddl8:	jmp	dos_enter
ddl9:	iret
ENDPROC	int_leave

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
	IFDEF	DEBUG
	mov	al,ah
;
; %P is a special formatter that prints the caller's REG_CS:REG_IP-2 in hex;
; "#010" ensures it's printed with "0x" and 8 digits with leading zeroes.
;
	DPRINTF	'd',<"%#010P: unsupported DOS function %02bxh\r\n">,ax
	ENDIF	; DEBUG

	mov	[bp].REG_AX,ERR_INVALID
	stc
	ret
ENDPROC	func_none

DOS	ends

	end
