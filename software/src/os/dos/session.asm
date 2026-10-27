;
; BASIC-DOS Session Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

;
; Global SCB status variables:
;
; scb_locked is -1 if the current SCB is unlocked, >= 0 if it's locked;
; locked means that SCB switching is disabled.
;
; scb_stoked normally points to scb_return (ie, a RET) but if a yield
; operation notices that another SCB is ready to run BUT the current SCB is
; locked, then scb_stoked will be set to scb_stoke instead, triggering a yield
; on the next unlock.
;
; That is, thus far, the extent of our extremely simple scheduler.
;
	EXTBYTE	<scb_locked,def_drive,bpb_total>
	EXTWORD	<scb_active,scb_stoked,load_reserve>
	EXTLONG	<scb_table>
	EXTNEAR	<dos_check,dos_leave,load_command,psp_termcode>
	EXTNEAR	<sfh_add_ref,sfh_context,sfh_close,get_cdir>
	EXTNEAR	<sfb_from_sfh,sfb_read,sfb_write>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_getnum
;
; Inputs:
;	None
;
; Outputs:
;	AL = SCB # of scb_active
;
; Modifies:
;	AX
;
DEFPROC	scb_getnum,DOS
	ASSUME	ES:NOTHING
	push	bx
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	mov	al,[bx].SCB_NUM
gsn9:	pop	bx
	ret
ENDPROC	scb_getnum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_load
;
; Load a program into an available session.
;
; Inputs:
;	REG_ES:REG_BX -> SPB (Session Parameter Block)
;	REG_CH = number of programs the caller will load next (eg, the rest
;	of a pipeline; see load_program)
;
; Outputs:
;	Carry clear if successful:
;		REG_CL = session (SCB) #
;		REG_AX = program size (if SPB_ENVSEG is -1)
;		REG_ES:REG_BX -> program data (if SPB_ENVSEG is -1)
;	Carry set if error, AX = error code (eg, no SCB, no program, etc),
;		and REG_CL = session (SCB) # if an SCB was available
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	scb_load,DOS
	mov	cl,[bp].REG_CH		; CL = programs the caller will load next
	mov	ch,0
	mov	[load_reserve],cx	; (see load_program)
	mov	cl,-1
	call	scb_lock		; lock a free SCB
	jc	sl8
	push	ax			; save previous SCB
	mov	dl,[bx].SCB_NUM		; (init_scb needs AX intact)
	mov	[bp].REG_CL,dl		; REG_CL = session (SCB) #
	mov	di,[bp].REG_BX
	mov	es,[bp].REG_ES		; ES:DI -> SPB
	ASSUME	ES:NOTHING
	call	init_scb		; initialize the SCB
	push	bx			; save SCB
	mov	bx,es:[di].SPB_ENVSEG
	push	bx			; BX = ENVSEG, if any
	lds	si,es:[di].SPB_CMDLINE
	ASSUME	DS:NOTHING
	call	load_command		; DS:SI -> command line
	push	cs
	pop	ds
	ASSUME	DS:DOS
	pop	cx			; CX = ENVSEG
	pop	bx			; BX -> current SCB again
	jc	sl6			; release session references on load error
;
; If successful, load_command returns the initial program stack in DX:AX.
;
; In addition, it records cache information in the TMP registers, which most
; most callers can/will ignore, but which sysinit uses to speed up successive
; LOAD requests.
;
	mov	[bx].SCB_STACK.OFF,ax	; DX:AX == initial stack
	mov	[bx].SCB_STACK.SEG,dx
	or	[bx].SCB_STATUS,SCSTAT_LOAD
	mov	[bx].SCB_ENVSEG,cx
;
; Since we start the SCB's first program by going through dos_leave, we need
; to bump SCB_INDOS (TODO: Consider whether this is really a job for init_scb).
;
	inc	[bx].SCB_INDOS

	inc	cx			; was ENVSEG -1?
	jnz	sl7			; no, leave REG_AX, REG_ES:REG_BX alone
	mov	ax,[bp].TMP_CX
	mov	[bp].REG_AX,ax		; REG_AX = program size
	mov	ax,[bp].TMP_BX
	mov	[bp].REG_BX,ax
	mov	ax,[bp].TMP_ES
	mov	[bp].REG_ES,ax		; REG_ES:REG_BX -> program data
	jmp	short sl7
;
; Undo init_scb's handle references, preserving the original load error.
; Sysinit's handles already belonged to the session and were not incremented.
;
sl6:	push	ax
	push	bx
	inc	cx			; was ENVSEG -1 (from sysinit)?
	jz	sl6a			; yes, leave its handles alone
	mov	cl,[bx].SCB_NUM
	call	scb_close
sl6a:	pop	bx
	pop	ax
	stc

sl7:	pop	cx			; recover previous SCB
	call	scb_unlock		; unlock
sl8:	jnc	sl9
	mov	[bp].REG_AX,ax		; return error code to caller
sl9:	ret
ENDPROC	scb_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_lock
;
; Activate and lock the specified SCB
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	On success, carry clear, AX -> previous SCB, BX -> current SCB
;	On failure, carry set (if SCB invalid or not initialized for use)
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	scb_lock,DOS
	ASSUME	ES:NOTHING
	inc	[scb_locked]
	call	get_scb
	jc	sk9
	mov	ax,bx			; AX = current SCB
	xchg	bx,[scb_active]		; BX -> previous SCB, if any
	ASSERT	STRUCT,[bx],SCB
	xchg	bx,ax			; BX -> current SCB, AX -> previous SCB
	ASSERT	STRUCT,[bx],SCB
	push	ax
	push	dx
	lea	si,[bx].SCB_EXIT	; SI -> SCB vectors
	mov	al,INT_DOSEXIT
sk1:	call	far ptr DDINT_GETVEC	; DX:CX = vector
	mov	[si].OFF,cx
	mov	[si].SEG,dx
	add	si,4
	inc	ax
	cmp	al,INT_DOSERROR		; copied all 3 vectors?
	jbe	sk1			; no
	pop	dx
	pop	ax
	ret
sk9:	dec	[scb_locked]
	ret
ENDPROC	scb_lock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_unlock
;
; Restore the previous SCB and lock state.
;
; Inputs:
;	BX -> current SCB
;	CX -> previous SCB
;
; Modifies:
;	BX
;
; Preserves:
;	Flags
;
DEFPROC	scb_unlock,DOS
	ASSUME	ES:NOTHING
	pushf
	ASSERT	STRUCT,[bx],SCB
	mov	[scb_active],cx
	mov	bx,cx			; BX -> previous SCB
	ASSERT	STRUCT,[bx],SCB
	dec	[scb_locked]
	popf
	ret
ENDPROC	scb_unlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_release
;
; Handler invoked via UNLOCK_SCB_RET to unlock the SCB and check for a
; deferred yield request if we're completely unlocked.
;
; Inputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	scb_release,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	dec	[scb_locked]
	jge	scb_return
	ASSERT	Z,<cmp [scb_locked],-1>
	jmp	[scb_stoked]
ENDPROC	scb_release

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_stoke
;
; Handler invoked via UNLOCK_SCB_RET to perform a deferred yield request.
;
; Inputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	scb_stoke,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	mov	[scb_stoked],offset scb_return
	push	ax
	DOSUTIL	YIELD
	pop	ax
	DEFLBL	scb_return,near
	ret
ENDPROC	scb_stoke

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_start
;
; Start the specified session (actual starting will handled by scb_switch).
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success, BX -> SCB
;	Carry set on error (eg, invalid SCB #), AX = error code
;
DEFPROC	scb_start,DOS
 	call	get_scb
 	jc	ss9
	test	[bx].SCB_STATUS,SCSTAT_LOAD
	jz	ss8
	or	[bx].SCB_STATUS,SCSTAT_START
	ret
ss8:	mov	ax,ERR_BADSESSION
	stc
ss9:	ret
ENDPROC	scb_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_stop
;
; TODO: Stop (ie, suspend) the specified session.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	scb_stop,DOS
	DBGBRK
	ret
ENDPROC	scb_stop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_close
;
; Close the specified session.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success (AX = 0)
;	Carry set on error (eg, invalid SCB #), AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	scb_close,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	call	get_scb
 	jc	sud9
	call	scb_endio		; AX = 0
	and	[bx].SCB_STATUS,NOT (SCSTAT_LOAD OR SCSTAT_START)
;
; In case another session was waiting for this session to close, call endwait.
;
	mov	di,bx
	mov	dx,ds			; DX:DI = SCB address (the wait ID)
	call	scb_endwait
	clc
sud9:	ret
ENDPROC	scb_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_endio
;
; If the session's input is a character device, read zero bytes from it,
; which tells a pipe that its reader is done, so that the command writing to
; it fails instead of waiting forever for room (eg, in "TYPE FILE | FIND"
; when FIND can't open its file).  And if the session's output is a character
; device, write zero bytes to it, which tells a pipe that its input has ended,
; just as COMMAND does after the first command of a pipeline (otherwise, in
; "TYPE FILE | SORT | MORE", MORE would wait forever).  Other character
; devices ignore both.  Then close the session's system handles.
;
; Since this I/O can switch sessions, psp_term calls this before it frees the
; memory (and stack) of a session's last program; when scb_close calls it
; again, the handles are already closed, so it does nothing.
;
; Inputs:
;	BX -> SCB
;
; Outputs:
;	AX = 0
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	scb_endio,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	bx
	mov	dx,offset sfb_read
	mov	bl,[bx].SCB_SFHIN
	call	end_io
	pop	bx
	push	bx
	mov	dx,offset sfb_write
	mov	bl,[bx].SCB_SFHOUT
	call	end_io
	pop	bx
	mov	cx,5			; close this session's system handles
	push	bx
	lea	si,[bx].SCB_SFHIN
sei1:	mov	bl,SFH_NONE
	xchg	bl,[si]
	call	sfh_close
	inc	si
	loop	sei1
	pop	bx
	xchg	ax,cx			; make sure AX is zero
	ret
ENDPROC	scb_endio

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; end_io
;
; Issue a zero-length read or write to a character device (see scb_close).
;
; Inputs:
;	BL = SFH
;	DX -> sfb_read or sfb_write
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	end_io,DOS
	call	sfb_from_sfh		; BX -> SFB
	jc	ei9
	cmp	[bx].SFB_DRIVE,0	; character device?
	jge	ei9			; no
	sub	cx,cx
	mov	al,IO_RAW
	jmp	dx
ei9:	ret
ENDPROC	end_io

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_end
;
; End the current program in the specified session, by aborting it (see
; scb_abort); the abort takes effect the next time the session leaves DOS,
; so use scb_waitend to wait for it.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success
;	Carry set on error (eg, invalid SCB #, or no program in the session)
;
; Modifies:
;	AX, BX
;
DEFPROC	scb_end,DOS
	ASSUMES	<DS,DOS>,<ES,DOS>
	call	get_scb
	jc	sc9
	test	[bx].SCB_STATUS,SCSTAT_LOAD
	jz	sc8			; no program loaded
	call	scb_abort
	clc
	ret
sc8:	mov	ax,ERR_BADSESSION
	stc
sc9:	ret
ENDPROC	scb_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_waitend
;
; Wait for all programs in the specified session to end.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success, set on error
;
; Modifies:
;
DEFPROC	scb_waitend,DOS
	ASSUMES	<DS,DOS>,<ES,DOS>
	call	get_scb
	jc	sc9
	test	[bx].SCB_STATUS,SCSTAT_LOAD
	jz	sc9
;
; Turn this call into a standard scb_wait call, where the wait ID in DX:DI
; is the target SCB address (instead of the usual driver packet address).
;
	mov	di,bx
	mov	dx,ds
	jmp	scb_wait
ENDPROC	scb_waitend

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_query
;
; Returns info about a session (see utl_qryscb), such as its program's PSP
; and its console's name, so that commands (eg, RESTART) don't need the
; kernel's internal structures.  Unlike get_scb, this accepts any SCB in the
; table, so that unused sessions (no program, no console) can be listed, too.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	On success, carry clear:
;		REG_AX = PSP of the session's program (zero if none)
;		REG_ES:REG_DI -> name of the session's console device (zero if none)
;	On failure, carry set (ie, invalid SCB #)
;
; Modifies:
;	AX, BX
;
DEFPROC	scb_query,DOS
	ASSUMES	<DS,DOS>,<ES,DOS>
	mov	al,size SCB
	mul	cl
	add	ax,[scb_table].OFF
	xchg	bx,ax			; BX -> SCB
	mov	ax,ERR_BADSESSION
	cmp	bx,[scb_table].SEG	; is the SCB # valid?
	cmc
	jc	sq9			; no (carry set, AX = error)
	sub	ax,ax
	test	[bx].SCB_STATUS,SCSTAT_LOAD
	jz	sq1			; no program loaded
	mov	ax,[bx].SCB_PSP
sq1:	mov	[bp].REG_AX,ax
	mov	[bp].REG_ES,cs
	mov	bl,[bx].SCB_SFHOUT
	call	sfb_from_sfh		; BX -> SFB
	jnc	sq2
	sub	bx,bx			; no console
sq2:	ASSERT	<SFB_NAME>,EQ,0
	mov	[bp].REG_DI,bx		; REG_ES:REG_DI -> SFB_NAME
	clc
sq9:	ret
ENDPROC	scb_query

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_yield
;
; Asynchronous interface to decide which session should run next.
;
; There are currently two conditions to consider:
;
;	1) A DOSUTIL YIELD request
;	2) The active session can't continue (eg, psp_term closed it)
;
; In the first case, we want to return if no other SCB is ready; this is
; important when we're called from an interrupt handler.
;
; In the second case, we never return; we will simply switch to the first
; SCB we find whose wait condition is satisfied.
;
; NOTE: DOSUTIL WAIT requests used to be the second case, but scb_wait now
; loops on DOSUTIL YIELD instead, so that it can return the wait's outcome.
;
; Inputs:
;	AX = active SCB when called from DOSUTIL YIELD, zero otherwise
;
; Modifies:
;	BX, DX
;
DEFPROC	scb_yield,DOS
	mov	bx,ax
	test	ax,ax			; is this yield due to a WAIT?
	jnz	sy1			; no
	mov	bx,[scb_active]		; yes, spin until we find an SCB
;
; Interrupts are enabled between SCBs, but not from testing an SCB until we
; switch to it; otherwise, an interrupt could reschedule in between, and when
; this session resumed, it would switch to the SCB without testing it again
; (eg, after its session had ended).
;
sy1:	sti
	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	jb	sy2
	mov	bx,[scb_table].OFF
sy2:	ASSERT	STRUCT,[bx],SCB
	cmp	bx,ax			; have we returned to active SCB?
	je	scb_test		; yes (go check for ABORT)
	cli
	test	[bx].SCB_STATUS,SCSTAT_START
	jz	sy1			; ignore this SCB, hasn't started
	mov	dx,[bx].SCB_WAITID.OFF
	or	dx,[bx].SCB_WAITID.SEG
	jnz	sy1			; ignore this SCB, it's still waiting
	inc	[scb_locked]
	jz	scb_switch		; we were not already locked, so switch
	test	ax,ax			; yield?
	jz	sy8			; no
	mov	[scb_stoked],offset scb_stoke
sy8:	dec	[scb_locked]
	sti
sy9:	ASSERT	NC
	ret
ENDPROC	scb_yield

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_switch
;
; Switch to the specified session.  SCB locking is used to prevent switches
; whenever global data structures are being modified (eg, disk buffers), but
; all per-session data should be stored in the SCB, so that no global state
; needs to be copied in or out.
;
; The kinds of apps we ultimately want to support in BASIC-DOS sessions will
; determine whether we need to adopt additional measures, such as "swapping"
; global (eg, BIOS) data in or out of the SCB.
;
; Our CONSOLE driver is a good example.  It already performs some BIOS updates
; on INT 10h operations, but if that proves to be insufficient, we may need to
; provide session-switch notifications to the drivers, so that they can do
; their own "state swapping" every time we're about to switch to a new session.
;
; The incentives for avoiding that are high, because these switches will become
; very expensive, and IBM PCs are not all that fast.
;
; Inputs:
;	BX -> SCB
;
DEFPROC	scb_switch,DOS
	cli
	dec	[scb_locked]
	cmp	bx,[scb_active]		; is this SCB already active?
	je	scb_test		; yes
	mov	ax,bx
	xchg	bx,[scb_active]		; BX -> previous SCB
	ASSERT	STRUCT,[bx],SCB
	add	sp,2			; toss 1 near-call return address
	mov	[bx].SCB_STACK.SEG,ss
	mov	[bx].SCB_STACK.OFF,sp
	xchg	bx,ax			; BX -> current SCB, AX -> previous SCB
	ASSERT	STRUCT,[bx],SCB
	mov	ss,[bx].SCB_STACK.SEG
	mov	sp,[bx].SCB_STACK.OFF
	ASSERT	NC
	jmp	dos_leave		; we let dos_leave turn interrupts on

	DEFLBL	scb_test,near
	test	[bx].SCB_STATUS,SCSTAT_ABORT
	jz	sw9
sw8:	stc
sw9:	sti
	ret
ENDPROC	scb_switch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_wait
;
; Synchronous interface to mark current SCB as waiting for the specified ID.
;
; All waits are interruptible: an ABORT (CTRL-ALT-DEL) or CTRLC signal ends
; the wait early (see scb_intwait), in which case we return carry set, and the
; caller (typically a driver) must clean up whatever it was waiting on (eg,
; remove its request packet from any list that its interrupt handler uses).
;
; Rather than switching directly to another session (which would resume this
; session with the stack frame of whatever call switched it out, which isn't
; necessarily this one), we loop on DOSUTIL YIELD until the wait ID has been
; cleared, and then check whether an ABORT or CTRLC signal is pending.
;
; Since neither signal can be cleared while we're waiting (ABORT is processed
; only when SCB_INDOS returns to zero, and CTRLC only when this session calls
; msc_sigctrlc), a pending signal means the wait was either interrupted or will
; be shortly; in the latter case, the wait may also have ended normally, so a
; caller that waits on a request packet must treat a packet that's no longer
; waiting as satisfied (see remove_packet in the drivers).
;
; Inputs:
;	DX:DI == wait ID
;
; Outputs:
;	Carry clear if the wait ended normally (ie, via scb_endwait);
;	carry set if the wait failed or was interrupted (eg, ABORT or CTRLC)
;
; Modifies:
;	AX, BX
;
DEFPROC	scb_wait,DOS
	cli
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	ASSERT	Z,<cmp [bx].SCB_WAITID.SEG,0>
	test	[bx].SCB_STATUS,SCSTAT_ABORT
	jnz	swt8			; fail the wait if ABORT is set
	cmp	[bx].SCB_CTRLC_ACT,0	; or if CTRLC is pending
	jne	swt8
	mov	[bx].SCB_WAITID.OFF,di
	mov	[bx].SCB_WAITID.SEG,dx
swt1:	sti
	DOSUTIL	YIELD			; let other sessions run
	cli
	mov	ax,[bx].SCB_WAITID.OFF
	or	ax,[bx].SCB_WAITID.SEG	; has the wait ended yet?
	jnz	swt1			; no
	test	[bx].SCB_STATUS,SCSTAT_ABORT
	jnz	swt8			; the wait was interrupted by ABORT
	cmp	[bx].SCB_CTRLC_ACT,0	; or by CTRLC?
	je	swt9			; no (carry clear)
swt8:	stc
swt9:	sti
	ret
ENDPROC	scb_wait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_endwait
;
; Asynchronous interface to examine all SCBs for the specified ID and clear it.
;
; Inputs:
;	DX:DI == wait ID
;
; Outputs:
;	Carry clear if found, set if not
;
DEFPROC	scb_endwait,DOS
	cli
	mov	bx,[scb_table].OFF
se1:	ASSERT	STRUCT,[bx],SCB
	cmp	[bx].SCB_WAITID.OFF,di
	jne	se2
	cmp	[bx].SCB_WAITID.SEG,dx
	jne	se2
	mov	[bx].SCB_WAITID.OFF,0
	mov	[bx].SCB_WAITID.SEG,0
	jmp	short se9
se2:	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	cmc
	jnc	se1
se9:	sti
	ret
ENDPROC	scb_endwait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_abort
;
; Sets the SCB's ABORT bit and interrupts any WAIT condition.  Called on ABORT
; "hot key" notifications.
;
; Inputs:
;	BX -> SCB
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	scb_abort,DOS
	pushf
	cli
	or	[bx].SCB_STATUS,SCSTAT_ABORT
	mov	[bx].SCB_ABTYPE,EXTYPE_ABORT
	call	scb_intwait
	popf
	ret
ENDPROC	scb_abort

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_intwait
;
; Interrupts the SCB's WAIT condition, if any, by clearing its wait ID.  Called
; on ABORT and CTRLC "hot key" notifications, after the SCB has been marked with
; the pending signal, which is how scb_wait knows to return carry set.
;
; Inputs:
;	BX -> SCB
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	scb_intwait,DOS
;
; We may be called with interrupts enabled (eg, from utl_hotkey), so an
; interrupt could arrive between the two stores below.  We zero the SEG word
; first because no valid wait ID has a zero segment (and a zero SEG is how
; scb_wait determines that a session isn't waiting), so the intermediate ID
; (0:OFF) can never match an ENDWAIT for this or any other session's wait.
; Zeroing OFF first would leave SEG:0, which is the form of a pipe's wait ID.
;
	mov	[bx].SCB_WAITID.SEG,0
	mov	[bx].SCB_WAITID.OFF,0
	ret
ENDPROC	scb_intwait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_scb
;
; Returns the specified SCB.
;
; Inputs:
;	CL = SCB # (-1 for first free SCB)
;
; Outputs:
;	On success, carry clear, BX -> SCB
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, BX
;
DEFPROC	get_scb,DOS
	cmp	cl,-1
	je	get_free_scb
	mov	al,size SCB
	mul	cl
	add	ax,[scb_table].OFF
	cmp	ax,[scb_table].SEG
	jae	gs8
	xchg	bx,ax
	test	[bx].SCB_STATUS,SCSTAT_INIT
	jnz	gs9
gs8:	mov	ax,ERR_BADSESSION
	stc
gs9:	ret
ENDPROC	get_scb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_free_scb
;
; Returns the first free (unloaded) SCB.
;
; Inputs:
;	None
;
; Outputs:
;	On success, carry clear, BX -> SCB
;	On failure, carry set (SCB unavailable), AX = ERR_NOSESSION
;
; Modifies:
;	BX
;
DEFPROC	get_free_scb,DOS
	mov	bx,[scb_table].OFF
fs1:	test	[bx].SCB_STATUS,SCSTAT_LOAD
	jz	fs9
	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	jb	fs1
	mov	ax,ERR_NOSESSION
	stc
fs9:	ret
ENDPROC	get_free_scb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_scb
;
; Initialize the SCB in preparation for program loading.  Now that
; COMMAND.COM is using the LOAD interface to start background processes,
; more initialization is required (eg, copying the current SCB's settings,
; such as SCB_CURDRV).
;
; Inputs:
;	AX = previous SCB
;	DS:BX -> SCB (Session Control Block)
;	ES:DI -> SPB (Session Parameter Block)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	init_scb,DOS
	push	di
	ASSUME	ES:NOTHING
	ASSERT	STRUCT,[bx],SCB
;
; Before we overlay the SCB handles with those from the SPB, we start by
; copying the current SCB's handles (if any).  Ditto for the SCB's parent
; (if any), switch character, current drive, etc.
;
	mov	[bx].SCB_PARENT,ax	; TODO: What shall we do with this?
	xchg	si,ax			; DS:SI -> previous SCB
	mov	dx,es:[di].SPB_ENVSEG	; DX = SPB_ENVSEG (-1 if from sysinit)
	push	es
	push	di
	push	ds
	pop	es
	ASSUME	ES:DOS
;
; Copy the current drive, switch char, and path char, along with the current
; directory of every drive, from the previous SCB, unless SPB_ENVSEG is -1
; (ie, from sysinit), in which case we use the defaults (and every root).
;
	push	bx
	mov	al,0
	call	get_cdir
	mov	di,bx			; ES:DI -> new SCB's directories
	mov	bx,si
	mov	al,0
	call	get_cdir		; BX -> previous SCB's directories
	mov	cl,[bpb_total]
	mov	ch,0
	push	si
	lea	ax,[si].SCB_CURDRV	; AX -> previous SCB's settings
	mov	si,bx
	cmp	dx,-1			; from sysinit?
	jne	si0			; no
	sub	ax,ax
	rep	stosw			; every directory is the root
	mov	ax,offset def_drive	; AX -> default settings
si0:	rep	movsw			; (CX is zero if we just zeroed them)
	pop	si
	pop	bx
	xchg	si,ax
	lea	di,[bx].SCB_CURDRV
	ASSERT	<SCB_CURDRV+1>,EQ,<SCB_SWCHAR>
	ASSERT	<SCB_CURDRV+2>,EQ,<SCB_PATHCHAR>
	movsw
	movsb
	xchg	si,ax			; DS:SI -> previous SCB again
	pop	di
	pop	es
	ASSUME	ES:NOTHING
	inc	dx			; is SPB_ENVSEG -1?
	jz	si0a			; yes, don't copy handles
	ASSERT	<SCB_SFHIN>,EQ,2
	lodsw				; use LODSW as a quick SI += 2
	lodsw				; load SFHIN, SFHOUT
	mov	word ptr [bx].SCB_SFHIN,ax
	lodsw				; load SFHERR, SFHAUX
	mov	word ptr [bx].SCB_SFHERR,ax
	lodsb				; load SFHPRN
	mov	[bx].SCB_SFHPRN,al
si0a:	dec	dx
;
; Now copy any valid SFHs from the SPB into the SCB.
;
	mov	cx,5
	lea	si,[di].SPB_SFHIN	; ES:SI -> 1st SFH in the SPB
	lea	di,[bx].SCB_SFHIN	; DS:DI -> 1st SFH in the SCB
si1:	lods	byte ptr es:[si]
	cmp	al,SFH_NONE		; was an SFH supplied?
	je	si2			; no
	mov	[di],al			; update the SCB
si2:	inc	dx			; is SPB_ENVSEG -1 (from sysinit)?
	jz	si3			; yes, so leave SFH alone
	mov	al,[di]			; AL = SFH (no harm if SFH_NONE)
	mov	ah,1			; add 1 session ref
	call	sfh_add_ref		; (in addition to any program refs)
si3:	inc	di
	dec	dx
	loop	si1
;
; Now that we're done fiddling with SFHs, get the CONSOLE context from SFHOUT.
;
	mov	al,[bx].SCB_SFHOUT
	call	sfh_context
	mov	[bx].SCB_CONTEXT,ax

	mov	[bx].SCB_STATUS,SCSTAT_INIT
	pop	di
	ret
ENDPROC	init_scb

DOS	ends

	end
