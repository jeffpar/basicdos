;
; BASIC-DOS Utility Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	dev.inc
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<chk_devname,dev_request>,near
	EXTERNS	<scb_load,scb_start,scb_stop,scb_end,scb_waitend>,near
	EXTERNS	<scb_yield,scb_release,scb_wait,scb_endwait>,near
	EXTERNS	<mem_query,msc_getdate,msc_gettime>,near
	EXTERNS	<psp_term_exitcode>,near
	EXTERNS	<add_date,read_line>,near

	EXTERNS	<scb_locked>,byte
	EXTERNS	<scb_active>,word
	EXTERNS	<scb_table,clk_ptr>,dword

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_getdev (AL = 0Fh)
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
;	AX, CX, DI, ES (ie, whatever chk_devname modifies)
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
; utl_ioctl (AL = 10h)
;
; Inputs:
;	REG_BX = IOCTL command (BH = DDC_IOCTLIN, BL = IOCTL command)
;	REG_ES:REG_DI -> DDH
;	Other registers will vary
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	utl_ioctl,DOS
	sti
	mov	ax,[bp].REG_BX		; AX = command codes from BH,BL
	mov	es,[bp].REG_ES		; ES:DI -> DDH
	mov	bx,dx			; BX = REG_DX, CX = REG_CX
	call	dev_request		; call the driver
	ret
ENDPROC	utl_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_load (AL = 11h)
;
; Inputs:
;	REG_ES:REG_DI -> SPB (Session Parameter Block)
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
; utl_start (AL = 12h)
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
; utl_stop (AL = 13h)
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
; utl_end (AL = 14h)
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
; utl_waitend (AL = 15h)
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
; utl_yield (AL = 16h)
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
; utl_sleep (AL = 17h)
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
; utl_wait (AL = 18h)
;
; Synchronous interface to mark current SCB as waiting for the specified ID.
;
; Inputs:
;	REG_DX:REG_DI == wait ID
;
; Outputs:
;	None
;
DEFPROC	utl_wait,DOS
	jmp	scb_wait
ENDPROC	utl_wait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_endwait (AL = 19h)
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
; utl_hotkey (AL = 1Ah)
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
hk1:	cmp	[bx].SCB_CONTEXT,cx
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
	or	[bx].SCB_STATUS,SCSTAT_KILL
hk8:	add	bx,size SCB		; advance to the next SCB
	cmp	bx,[scb_table].SEG
	jb	hk1
	cmp	dx,1			; set carry if DX is zero (no SCBs)
hk9:	ret
ENDPROC	utl_hotkey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_lock (AL = 1Bh)
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
	mov	ax,[scb_active]
	test	ax,ax
	jz	lck8
	xchg	bx,ax
	mov	ax,[bx].SCB_CONTEXT
lck8:	mov	[bp].REG_AX,ax
	ret
ENDPROC	utl_lock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_unlock (AL = 1Ch)
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
; utl_qrymem (AL = 1Dh)
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
; utl_abort (AL = 1Fh)
;
; Inputs:
;	REG_DL = exit code
;	REG_DH = exit type
;
; Outputs:
;	None
;
DEFPROC	utl_abort,DOS
	xchg	ax,dx			; AL = exit code, AH = exit type
	jmp	psp_term_exitcode
ENDPROC	utl_abort

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_getdate (AL = 20h)
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
; utl_gettime (AL = 21h)
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
; utl_incdate (AL = 22h)
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
; utl_editln (AL = 23h)
;
; Similar to DOS function tty_input (REG_AH = 0Ah) but returns editing
; notifications for selected keys (eg, UP and DOWN keys).
;
; Inputs:
;	REG_DS:REG_DX -> BUFINP with INP_MAX preset to max chars
;
; Outputs:
;	AX = last editing action
;	Characters are stored in BUFINP.INP_BUF (including the CHR_RETURN);
;	INP_CNT is set to the number of characters (excluding the CHR_RETURN)
;
DEFPROC	utl_editln,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	byte ptr [bp].TMP_AH,1	; TMP_AH = 1 for editing notifications
	call	read_line
	ret
ENDPROC	utl_editln

DOS	ends

	end
