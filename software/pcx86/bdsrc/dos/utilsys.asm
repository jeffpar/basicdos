;
; BASIC-DOS Utility Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	dev.inc
	include	devapi.inc
	include	dos.inc

DOS	segment word public 'CODE'

	EXTNEAR	<chk_devname,dev_request>
	EXTNEAR	<scb_load,scb_start,scb_stop,scb_end,scb_waitend,scb_abort>
	EXTNEAR	<scb_yield,scb_release,scb_wait,scb_endwait>
	EXTNEAR	<mem_query,msc_getdate,msc_gettime,psp_termcode>
	EXTNEAR	<add_date,read_line>

	EXTBYTE	<scb_locked>
	EXTWORD	<scb_active>
	EXTLONG	<scb_table,clk_ptr>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_getdev (AH = 0Fh)
;
; Returns the DDH (Device Driver Header) in ES:DI for device name at DS:DX.
;
; Inputs:
;	DS:DX -> device name
;
; Outputs:
;	ES:DI -> DDH if success; carry set if not found
;
; Modifies:
;	CX, DX, DI, ES (ie, whatever chk_devname modifies)
;
DEFPROC	utl_getdev,DOS
	sti
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	and	[bp].REG_FL,NOT FL_CARRY
	mov	si,dx
	call	chk_devname		; DS:SI -> device name
	jc	gd9
	mov	[bp].REG_DI,di
	mov	[bp].REG_ES,es
gd9:	ret
ENDPROC	utl_getdev

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_getcsn (AH = 10h)
;
; Inputs:
;	None
;
; Outputs:
;	REG_CL = current session #, carry clear
;
; Modifies:
;	AX, BX
;
DEFPROC	utl_getcsn,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	bx,[scb_active]
	mov	al,[bx].SCB_NUM
	mov	[bp].REG_CL,al
	ret
ENDPROC	utl_getcsn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_load (AH = 12h)
;
; Inputs:
;	REG_ES:REG_BX -> SPB (Session Parameter Block)
;
; Outputs:
;	Carry clear if successful
;	Carry set if error, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, DI, DS, ES
;
DEFPROC	utl_load,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_load
ENDPROC	utl_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_start (AH = 13h)
;
; "Start" the specified session.  Currently, all this does is mark the session
; startable; actual starting will handled by scb_switch.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear if successful, BX -> SCB
;	Carry set if error (eg, invalid SCB #)
;
DEFPROC	utl_start,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
 	jmp	scb_start
ENDPROC	utl_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_stop (AH = 14h)
;
; "Stop" the specified session.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear if successful
;	Carry set if error (eg, invalid SCB #)
;
DEFPROC	utl_stop,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_stop
ENDPROC	utl_stop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_end (AH = 15h)
;
; End the current program in the specified session.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear if successful
;	Carry set if error (eg, invalid SCB #)
;
DEFPROC	utl_end,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_end
ENDPROC	utl_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_waitend (AH = 16h)
;
; Wait for all programs in the specified session to end.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear if successful
;	Carry set if error (eg, invalid SCB #)
;
DEFPROC	utl_waitend,DOS
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_waitend
ENDPROC	utl_waitend

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_yield (AH = 17h)
;
; Asynchronous interface to decide which SCB should run next.
;
; Inputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	utl_yield,DOS
	sti
	mov	ax,[scb_active]
	jmp	scb_yield
ENDPROC	utl_yield

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_sleep (AH = 18h)
;
; Inputs:
;	REG_CX:REG_DX = # of milliseconds to sleep
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	utl_sleep,DOS
	sti				; CX:DX = # ms
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_WAIT
	les	di,[clk_ptr]
	mov	bx,dx			; BX = REG_DX, CX = REG_CX
	call	dev_request		; call the driver
	ret
ENDPROC	utl_sleep

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_wait (AH = 19h)
;
; Synchronous interface to mark current SCB as waiting for the specified ID.
;
; Inputs:
;	REG_DX:REG_DI == wait ID
;
; Outputs:
;	Carry clear UNLESS the wait has been ABORT'ed
;
DEFPROC	utl_wait,DOS
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_wait
ENDPROC	utl_wait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_endwait (AH = 1Ah)
;
; Asynchronous interface to examine all SCBs for the specified ID and clear it.
;
; Inputs:
;	REG_DX:REG_DI == wait ID
;
; Outputs:
;	Carry clear if found, set if not
;
DEFPROC	utl_endwait,DOS
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_endwait
ENDPROC	utl_endwait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_hotkey (AH = 1Bh)
;
; Inputs:
;	REG_CX = CONSOLE context
;	REG_DL = char code, REG_DH = scan code
;
; Outputs:
;	Carry clear if successful, set if unprocessed
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	utl_hotkey,DOS
	sti
	xchg	ax,dx			; AL = char, AH = scan code
	and	[bp].REG_FL,NOT FL_CARRY
;
; Find all SCBs with a matching context; all matching SCBs are presumed
; running inside the console that currently has focus.
;
; TODO: Decide if we need to deliver hotkey signals with greater precision
; (ie, to exactly one SCB), and if so, which SCB that should be.
;
	sub	dx,dx			; DX = matching SCB count
	mov	bx,[scb_table].OFF
hk1:	test	[bx].SCB_STATUS,SCSTAT_START
	jz	hk8			; unstarted sessions are ignored
	cmp	[bx].SCB_CONTEXT,cx
	jne	hk8
	inc	dx			; match
hk2:	cmp	al,CHR_CTRLC
	jne	hk3
	or	[bx].SCB_CTRLC_ACT,1
hk3:	cmp	al,CHR_CTRLP
	jne	hk4
	xor	[bx].SCB_CTRLP_ACT,1
hk4:	cmp	al,CHR_CTRLD
	jne	hk9
	call	scb_abort
hk8:	add	bx,size SCB		; advance to the next SCB
	cmp	bx,[scb_table].SEG
	jb	hk1
	cmp	dx,1			; set carry if DX is zero (no SCBs)
hk9:	ret
ENDPROC	utl_hotkey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_lock (AH = 1Ch)
;
; Asynchronous interface to lock the current SCB
;
; Inputs:
;	None
;
; Outputs:
;	REG_AX = CONSOLE context for the active SCB, zero if none (yet)
;
; Modifies:
;	AX, BX
;
DEFPROC	utl_lock,DOS
	LOCK_SCB
	mov	bx,[scb_active]
	mov	ax,[bx].SCB_CONTEXT
	mov	[bp].REG_AX,ax
	ret
ENDPROC	utl_lock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_unlock (AH = 1Dh)
;
; Asynchronous interface to unlock the current SCB
;
; Inputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	utl_unlock,DOS
	UNLOCK_SCB
	ret
ENDPROC	utl_unlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_qrymem (AH = 1Eh)
;
; Query info about memory blocks.
;
; Inputs:
;	REG_CX = memory block # (0-based)
;	REG_DL = memory block type (0 for any, 1 for free, 2 for used)
;
; Outputs:
;	On success, carry clear:
;		REG_ES:0 -> MCB
;		REG_AX = owner ID (eg, PSP)
;		REG_DX = size (in paragraphs)
;		REG_DS:REG_BX -> owner name, if any
;	On failure, carry set (ie, no more blocks of the requested type)
;
; Modifies:
;	AX, BX, CX, DS, ES
;
DEFPROC	utl_qrymem,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	mem_query
ENDPROC	utl_qrymem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_term (AH = 1Fh)
;
; Inputs:
;	REG_DL = exit code
;	REG_DH = exit type
;
; Outputs:
;	None
;
DEFPROC	utl_term,DOS
	xchg	ax,dx			; AL = exit code, AH = exit type
	jmp	psp_termcode
ENDPROC	utl_term

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_getdate (AH = 20h)
;
; Identical to msc_getdate, but also returns the "packed" date in AX
; and does not modify carry.
;
; Inputs:
;	None
;
; Outputs:
; 	REG_AX = date in "packed" format:
;
;	 Y  Y  Y  Y  Y  Y  Y  M  M  M  M  D  D  D  D  D
;	15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00
;
;	where Y = year-1980 (0-119), M = month (1-12), and D = day (1-31)
;
;	REG_CX = year (1980-2099)
;	REG_DH = month (1-12)
;	REG_DL = day (1-31)
;	REG_AL = day of week (0-6 for Sun-Sat)
;
DEFPROC	utl_getdate,DOS
	sti
	call	msc_getdate
	mov	[bp].REG_AX,ax
	clc
	ret
ENDPROC	utl_getdate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_gettime (AH = 21h)
;
; Identical to msc_gettime, but also returns the "packed" date in AX
; and does not modify carry.

; Inputs:
;	None
;
; Outputs:
;	REG_AX = time in "packed" format:
;
;	 H  H  H  H  H  M  M  M  M  M  M  S  S  S  S  S
;	15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00
;
;	where H = hours, M = minutes, and S = seconds / 2 (0-29)
;
;	REG_CH = hours (0-23)
;	REG_CL = minutes (0-59)
;	REG_DH = seconds (0-59)
;	REG_DL = hundredths
;
DEFPROC	utl_gettime,DOS
	sti
	call	msc_gettime
	mov	[bp].REG_AX,ax
	clc
	ret
ENDPROC	utl_gettime

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_incdate (AH = 22h)
;
; Inputs:
;	REG_CX = year (1980-2099)
;	REG_DH = month
;	REG_DL = day
;
; Outputs:
;	Date value(s) advanced by 1 day.
;
DEFPROC	utl_incdate,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ax,1			; add 1 day to the date values
	call	add_date
	mov	[bp].REG_CX,cx		; update all the inputs
	mov	[bp].REG_DX,dx		; since any or all may have changed
	ret
ENDPROC	utl_incdate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_editln (AH = 23h)
;
; Similar to DOS function tty_input (REG_AH = 0Ah) but returns editing
; notifications for selected keys (eg, UP and DOWN keys).
;
; Inputs:
;	REG_DS:REG_DX -> INPBUF with INP_MAX preset to max chars
;
; Outputs:
;	AX = last editing action
;	Characters are stored in INPBUF.INP_DATA (including the CHR_RETURN);
;	INP_CNT is set to the number of characters (excluding the CHR_RETURN)
;
DEFPROC	utl_editln,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	byte ptr [bp].TMP_AH,1	; TMP_AH = 1 for editing notifications
	call	read_line
	ret
ENDPROC	utl_editln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_restart (AH = 25h)
;
; TODO: Ensure any disk modifications (once we support disk modifications)
; have been written.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	utl_restart,DOS
	cli
	db	OP_JMPF
	dw	00000h,0FFFFh
ENDPROC	utl_restart

DOS	ends

	end
