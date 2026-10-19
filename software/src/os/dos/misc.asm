;
; BASIC-DOS Miscellaneous Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSFUNC equ 1
	include	macros.inc
	include	8086.inc
	include	dev.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc
	include	version.inc

DOS	segment word public 'CODE'

	EXTNEAR	<dos_check,dos_restart,dev_request,write_handle>
	EXTNEAR	<sfb_get,flush_console,err_jump>
	EXTBYTE	<err_active>
	EXTWORD	<err_stack>
	EXTSTR	<STR_CTRLC>

	EXTWORD	<mcb_head>
	EXTLONG	<clk_ptr>
	EXTWORD	<scb_active>

	EXTBYTE	<MONTH_DAYS>
	EXTWORD	<MONTHS,DAYS>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_setvec (REG_AH = 25h)
;
; Inputs:
;	REG_AL = vector #
;	REG_DS:REG_DX = address for vector
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI, ES
;
; Notes:
; 	Too bad this function wasn't defined to also return the original vector.
;
DEFPROC	msc_setvec,DOS
	call	get_vecoff		; AX = vector offset
	jnc	msv1
	sub	di,di
	mov	es,di
	ASSUME	ES:NOTHING
msv1:	xchg	di,ax			; ES:DI -> vector to write
	cli
	mov	ax,[bp].REG_DX
	stosw
	mov	ax,[bp].REG_DS
	stosw
	sti
	clc
	ret
ENDPROC	msc_setvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_getdate (REG_AH = 2Ah)
;
; Inputs:
;	None
;
; Outputs:
;	AX = date in "packed" format
;	REG_CX = year (1980-2099)
;	REG_DH = month (1-12)
;	REG_DL = day (1-31)
;	REG_AL = day of week (0-6 for Sun-Sat)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	msc_getdate,DOS
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_GETDATE
	les	di,[clk_ptr]
	call	dev_request		; call the driver
;
; The GETDATE request returns DX with the date in "packed" format:
;
;	 Y  Y  Y  Y  Y  Y  Y  M  M  M  M  D  D  D  D  D
;	15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00
;
; where Y = year-1980 (0-119), m = month (1-12), and D = day (1-31)
;
	mov	ax,dx
	call	day_of_week		; AX = day of week (0-6)
	mov	[bp].REG_AL,al
	mov	ax,dx
	mov	cl,9
	shr	ax,cl
	add	ax,1980			; AX = year
	mov	[bp].REG_CX,ax
	mov	ax,dx
	mov	cl,5
	shr	ax,cl
	and	al,0Fh			; AL = month
	mov	[bp].REG_DH,al
	mov	ax,dx			; AX = "packed" date
	and	dl,1Fh			; DL = day
	mov	[bp].REG_DL,dl
	ret
ENDPROC	msc_getdate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_setdate (REG_AH = 2Bh)
;
; Inputs:
;	REG_CX = year (1980-2099)
;	REG_DH = month (1-12)
;	REG_DL = day (1-31)
;
; Outputs:
;	REG_AL = 0 if date valid, 0FFh if invalid
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	msc_setdate,DOS
	mov	byte ptr [bp].REG_AL,-1
	sub	cx,1980			; CL = year (0-127)
	jb	msd9
	cmp	cx,120			; original year <= 2099?
	jae	msd9			; no

	mov	bl,dh
	mov	bh,0
	dec	bx
	cmp	bl,12
	jae	msd9

	cmp	dl,1
	jb	msd9
	cmp	dl,MONTH_DAYS[bx]	; day within the ordinary month's length?
	jbe	msd1			; yes
;
; As in add_date, if the month index is 1 (Feb) and the year is a leap year,
; then recheck the extra day.  As noted in day_of_week, the leap year check
; is simplified by our limited year range (1980-2099).
;
	cmp	bl,1			; Feb?
	jne	msd9			; no
	test	cl,3			; leap year?
	jnz	msd9			; no
	cmp	dl,29			; day within the longer month?
	ja	msd9			; no

msd1:	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_SETDATE
	les	di,[clk_ptr]
	mov	bx,dx			; BX = REG_DX, CX = REG_CX
	call	dev_request		; call the driver
	mov	byte ptr [bp].REG_AL,0
msd9:	clc				; carry is not used for this call
	ret
ENDPROC	msc_setdate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_gettime (REG_AH = 2Ch)
;
; Inputs:
;	None
;
; Outputs:
;	AX = time in "packed" format
;	REG_CH = hours (0-23)
;	REG_CL = minutes (0-59)
;	REG_DH = seconds (0-59)
;	REG_DL = hundredths
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	msc_gettime,DOS
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_GETTIME
	les	di,[clk_ptr]
	call	dev_request		; call the driver
;
; The GETTIME request returns DX with the time in "packed" format:
;
;	 H  H  H  H  H  M  M  M  M  M  M  S  S  S  S  S
;	15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00
;
; where H = hours (0-23), m = minutes (0-59), and S = seconds / 2 (0-29);
; additionally, AL contains hundredths (< 200).
;
	mov	bx,dx
	mov	cl,11
	shr	bx,cl
	mov	[bp].REG_CH,bl		; BL = hours
	mov	bx,dx
	mov	cl,5
	shr	bx,cl
	and	bl,3Fh
	mov	[bp].REG_CL,bl		; BL = minutes
	xchg	ax,dx			; AX = "packed" time
	mov	dh,al
	and	dh,1Fh			; DH = seconds / 2
	shl	dh,1			; DH = seconds
	cmp	dl,100			; hundredths >= 100?
	jb	mgt9
	sub	dl,100
	inc	dh
mgt9:	mov	[bp].REG_DH,dh		; DH = seconds
	mov	[bp].REG_DL,dl		; DL = hundredths
	ret
ENDPROC	msc_gettime

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_settime (REG_AH = 2Dh)
;
; Inputs:
;	REG_CH = hours (0-23)
;	REG_CL = minutes (0-59)
;	REG_DH = seconds (0-59)
;	REG_DL = hundredths
;
; Outputs:
;	REG_AL = 0 if time valid, 0FFh if invalid
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	msc_settime,DOS
	mov	byte ptr [bp].REG_AL,-1
	cmp	ch,24
	jae	mst9
	cmp	cl,60
	jae	mst9
	cmp	dh,60
	jae	mst9
	cmp	dl,100
	jae	mst9
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_SETTIME
	les	di,[clk_ptr]
	mov	bx,dx			; BX = REG_DX, CX = REG_CX
	call	dev_request		; call the driver
	mov	byte ptr [bp].REG_AL,0
mst9:	ret
ENDPROC	msc_settime

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_getver (REG_AH = 30h)
;
; Inputs:
;	None
;
; Outputs:
;	REG_AL = major version #
;	REG_AH = minor version #
;	REG_BX = revision # (currently zero)
;	REG_CX = 0 (1 if DEBUG build)
;
; Modifies:
;	AX, SI, ES
;
DEFPROC	msc_getver,DOS
	mov	ax,(VERSION_MINOR SHL 8) OR VERSION_MAJOR
;
; Some programs demand one exact version; EXE2BIN 3.20, for example, follows
; its INT 21h with "XCHG AH,AL" and "CMP AX,0314h".  If the caller's code has
; such a CMP (3Dh at CS:IP+2), return the version it's comparing against,
; with the bytes swapped, since the caller will swap them back.
;
	les	si,dword ptr [bp].REG_IP
	cmp	byte ptr es:[si+2],OP_CMP_AX	; CMP AX,imm16 at CS:IP+2?
	jne	gvr1			; no
	mov	ax,es:[si+3]		; yes, AX = the version it wants
	xchg	al,ah
gvr1:	mov	[bp].REG_AX,ax
	mov	[bp].REG_BX,SIG_BASICDOS	; BX = "BD" (identifies BASIC-DOS)
	IFNDEF DEBUG
	mov	[bp].REG_CX,0
	ELSE
	mov	[bp].REG_CX,1
	ENDIF
	ret
ENDPROC	msc_getver

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_setctrlc (REG_AH = 33h)
;
; Inputs:
;	REG_AL = 0 to get current CTRLC state in REG_DL
;	REG_AL = 1 to set current CTRLC state in REG_DL
;
; Outputs:
;	REG_DL = current state if REG_AL = 1, or 0FFh if REG_AL neither 0 nor 1
;
DEFPROC	msc_setctrlc,DOS
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	sub	al,1
	jae	msc1
	mov	al,[bx].SCB_CTRLC_ALL]	; AL was 0
	mov	[bp].REG_DL,al		; so return CTRLC_ALL in REG_DL
	clc
	jmp	short msc9
msc1:	jnz	msc2			; jump if AL was neither 0 nor 1
	mov	al,[bp].REG_DL		; AL was 1
	sub	al,1			; so convert REG_DL to 0 or 1
	sbb	al,al
	inc	ax
	mov	[bx].SCB_CTRLC_ALL,al
	clc
	jmp	short msc9
msc2:	mov	al,0FFh
	stc
msc9:	ret
ENDPROC	msc_setctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_sigctrlc
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	Any; this function does not return directly to the caller
;
DEFPROC	msc_sigctrlc,DOSFAR
	ASSUME	DS:NOTHING, ES:NOTHING
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	jmp	short msg0
;
; psp_retcode signals a child's CTRLC to its parent here, without echoing it
; or flushing the console again.
;
	DEFLBL	msc_retctrlc,near
	push	cs
	pop	ds
	mov	di,-1			; DI = -1 (don't echo the CTRLC)
	jmp	short msg1

	DEFLBL	msc_readctrlc,near
	ASSERT	STRUCT,[bx],SCB
	sub	di,di			; DI = 0 (echo the CTRLC)
	cmp	[bx].SCB_CTRLC_ACT,0
	je	msg1
msg0:	mov	[bx].SCB_CTRLC_ACT,0
;
; Have the session's console discard its type-ahead (including the CTRLC,
; which console drivers leave in the input) and end any pause (see
; flush_console), rather than reading the CTRLC from STDIN, which may be
; redirected (eg, the second command in "DIR | CASE").  Every session using
; the console receives the CTRLC (eg, every command in a pipeline), but only
; a session whose input is the console flushes the console and echoes it.
;
	call	flush_console		; carry set if input isn't the console
	sbb	di,di			; DI = -1 if so (don't echo the CTRLC)
;
; Make sure that whatever function we're interrupting has not violated
; our BP convention; some functions prefer to use BP as an extra register,
; and that's OK as long as 1) they're not an interruptable function and 2)
; they restore BP when they're done.
;
msg1:	cmp	[err_active],0		; inside a hard error handler?
	je	msg1a			; no
;
; A CTRLC inside the session's ERROR handler ends the handler with an ABORT
; response: discard everything on the hard error stack above dev_error's
; frame and resume there (see err_jump).
;
	push	cs
	pop	ss
	mov	sp,[err_stack]
	sub	sp,ERR_FRAME
	mov	al,CRERR_ABORT
	jmp	err_jump

msg1a:	IF REG_CHECK
	ASSERT	Z,<cmp word ptr [bp-2],offset dos_check>
	ENDIF

;
; Echo CTRLC to STDERR rather than STDOUT, since STDOUT may be redirected
; (eg, to a pipe that's full, in which case the write would never complete).
;
	test	di,di			; echo the CTRLC?
	jnz	msg2			; no
	mov	cx,STR_CTRLC_LEN
	mov	si,offset STR_CTRLC
	mov	bx,STDERR
	call	write_handle
msg2:
;
; Use the REG_WS workspace on the stack to create two "call frames",
; allowing us to RETF to the CTRLC handler, and allowing the CTRLC handler
; to IRET back to us.
;
	mov	ax,[bp].REG_FL		; FL_CARRY is clear in REG_FL
	mov	[bp].REG_WS.RET_FL,ax
	mov	[bp].REG_WS.RET_CS,cs
	mov	[bp].REG_WS.RET_IP,offset dos_restart
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	dec	[bx].SCB_INDOS
	; ASSERT	GE
;
; At this point, we're effectively issuing an INT 23h (INT_DOSCTRLC), but it
; has to be simulated, because we're using the SCB CTRLC address rather than
; the IVT CTRLC address; they should be the same thing, as long as everyone
; uses DOS_MSC_SETVEC to set vector addresses.
;
; As explained in the SCB definition, we do this only because we'd rather not
; swap IVT vectors on every SCB switch, hence the use of "shadow" vectors
; inside the SCB.
;
	mov	ax,[bx].SCB_CTRLC.SEG
	mov	[bp].REG_WS.JMP_CS,ax
	mov	ax,[bx].SCB_CTRLC.OFF
	mov	[bp].REG_WS.JMP_IP,ax

	mov	sp,bp
	pop	bp
	pop	di
	pop	es
	pop	si
	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	msc_sigctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; flush_stdin
;
; Discards any type-ahead, by sending DDC_INFLUSH to STDIN, if it's a
; character device (see tty_flush).
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	BX, ES (all other registers preserved)
;
DEFPROC	flush_stdin,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	ax
	push	cx
	push	dx
	push	di
	mov	bx,STDIN
	call	sfb_get			; BX -> SFB
	jc	fs9
	les	di,[bx].SFB_DEVICE
	test	es:[di].DDH_ATTR,DDATTR_CHAR
	jz	fs9			; not a character device
	mov	dx,[bx].SFB_CONTEXT
	mov	ah,DDC_INFLUSH
	sub	cx,cx			; no data
	call	dev_request
fs9:	pop	di
	pop	dx
	pop	cx
	pop	ax
	ret
ENDPROC	flush_stdin

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_getvec (REG_AH = 35h)
;
; Inputs:
;	REG_AL = vector #
;
; Outputs:
;	REG_ES:REG_BX = address from vector
;
; Modifies:
;	AX, SI, DS
;
DEFPROC	msc_getvec,DOS
	call	get_vecoff		; AX = vector offset
	jnc	mgv1
	sub	si,si
	mov	ds,si
	ASSUME	DS:NOTHING
mgv1:	xchg	si,ax			; DS:SI -> vector to read
	cli
	lodsw
	mov	[bp].REG_BX,ax
	lodsw
	mov	[bp].REG_ES,ax
	sti
	clc
	ret
ENDPROC	msc_getvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_getswc (REG_AH = 37h)
;
; Get the switch character or the path character.  Both are chosen at boot
; (by CONFIG.SYS's PATHCHAR setting, which also determines the switch char;
; see sysinit) and can't be changed, so programs need to get them only once.
;
; Inputs:
;	If REG_AL = 0, returns the switch character in REG_DL
;	If REG_AL = 4, returns the path character in REG_DL
;	Otherwise, set REG_AL to 0FFh to indicate unsupported subfunction
;	(PC DOS uses 1 to set the switch character, and 2 and 3 for the
;	obsolete "AVAILDEV" setting)
;
; Outputs:
;	See above
;
; Modifies:
;	AX
;
DEFPROC	msc_getswc,DOS
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	cmp	al,4			; get path char subfunction?
	jne	gsw0			; no
	mov	al,0			; yes, so treat it like get switch char
	ASSERT	<SCB_SWCHAR + 1>,EQ,<SCB_PATHCHAR>
	inc	bx			; (but for SCB_PATHCHAR)
gsw0:	test	al,al
	jnz	gsw2
	mov	al,[bx].SCB_SWCHAR
	mov	[bp].REG_DL,al		; DL = switch char
	ret
gsw2:	mov	byte ptr [bp].REG_AL,0FFh; (unsupported subfunction)
	ret
ENDPROC	msc_getswc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_getvars (REG_AH = 52h)
;
; Get address of BASIC-DOS variables in REG_ES:REG_BX.
;
; NOTE: The only variable located at the same offset as PC DOS is mcb_head
; (REG_BX-2).  Attempting to support most other variables would be pointless,
; because we don't have a Drive Parameter Table (just BPBs), the SFBs in our
; System File Table are completely different, etc.
;
; Inputs:
;	None
;
; Outputs:
;	REG_ES:REG_BX-2 -> mcb_head
;
; Modifies:
;	None
;
DEFPROC	msc_getvars,DOS
	mov	[bp].REG_ES,ds
	mov	[bp].REG_BX,offset mcb_head + 2
	ret
ENDPROC	msc_getvars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_vecoff
;
; Inputs:
;	AL = vector #
;
; Outputs:
;	AX = vector offset (carry set if IVT, clear if SCB)
;
; Modifies:
;	AX
;
DEFPROC	get_vecoff,DOS
	mov	ah,0			; AX = vector #
	add	ax,ax
	add	ax,ax			; AX = vector # * 4
	cmp	ax,INT_DOSEXIT * 4
	jb	gv9			; use IVT (carry set)
	cmp	ax,INT_DOSERROR * 4 + 4
	cmc
	jb	gv9			; use IVT (carry set)
	sub	ax,(INT_DOSEXIT * 4) - offset SCB_EXIT
	add	ax,[scb_active]		; AX = vector offset in current SCB
	ASSERT	NC
gv9:	ret
ENDPROC	get_vecoff

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_date
;
; TODO: While it would be nice to make this a general-purpose function,
; we only need to increment a date by 1 day, so that's all we do.  In the
; future, consider factoring day_of_week into multiple functions:
;
;	date_to_days (convert a date to a day count)
;	day_of_week (call date_to_days and calculate mod 7)
;	days_to_date (convert a day count back to a date)
;
; Support for 32-bit day counts would be nice too, so that despite the 128
; year limitation of DOS file dates, a wider range of dates could be supported.
;
; Inputs:
;	AX = +/- days
;	CX = year (1980-2099)
;	DH = month
;	DL = day
;
; Outputs:
;	Date value(s) updated
;
; Modifies:
;	CX, DX
;
DEFPROC	add_date,DOS
	ASSERT	Z,<cmp ax,1>
	mov	bl,dh
	mov	bh,0
	dec	bx			; BX = month index
	add	dl,al			; advance day
	cmp	dl,MONTH_DAYS[bx]	; exceeded the month's days?
	jbe	ad9			; no
;
; If the month index is 1 (Feb) and the year is a leap year, then recheck
; the day.  As noted in day_of_week, the leap year check is simplified by our
; limited year range (1980-2099).
;
	cmp	bl,1			; Feb?
	jne	ad1			; no
	test	cl,3			; leap year?
	jnz	ad1			; no
	cmp	dl,29			; day within the longer month?
	jbe	ad9			; yes

ad1:	mov	dl,1
	inc	dh
	cmp	dh,12
	jbe	ad9
	mov	dh,1
	inc	cx
ad9:	ret
ENDPROC	add_date

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; day_of_week
;
; For the given DATE, calculate the day of the week.  Given that Jan 1 1980
; (DATE "one") was a TUESDAY (day-of-week 2, since SUNDAY is day-of-week 0),
; we calculate how many days have elapsed, add 1, and compute days mod 7.
;
; Since 2000 was an every-400-years leap year, the number of elapsed leap
; days is a simple calculation as well.
;
; Note that since a DATE's year cannot be larger than 127, the number of days
; for all elapsed years cannot exceed 128 * 365 + (128 / 4) or 46752, which is
; happily a 16-bit quantity.
;
; TODO: This will need to special-case the year 2100 (which will NOT be a leap
; year -- unless, of course, someone changes the rules before then), but only
; if years > 2099 are actually allowed.  Years through 2107 can be encoded, but
; PC DOS constrained user input such that only years <= 2099 were allowed.
;
; Inputs:
;	AX = DATE in "packed" format:
;
;	 Y  Y  Y  Y  Y  Y  Y  m  m  m  m  D  D  D  D  D
;	15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00
;
; 	where Y = year-1980 (0-127), m = month (1-12), and D = day (1-31)
;
; Outputs:
;	CS:SI -> DAY string
;	AX = day of week (0-6)
;
; Modifies:
;	AX, SI
;
DEFPROC	day_of_week,DOS
	ASSUME	ES:NOTHING
	push	bx
	push	cx
	push	dx
	push	di
	sub	di,di			; DI = day accumulator
	mov	bx,ax			; save the original date in BX
	mov	cl,9
	shr	ax,cl			; AX = # of full years elapsed
	push	ax
	shr	ax,1			; divide full years by 4
	shr	ax,1			; to get number of leap days
	add	di,ax			; add to DI
	pop	ax
	mov	si,ax			; save full years in SI

	mov	dx,365
	mul	dx			; AX = total days for full years
	add	di,ax			; add to DI
	mov	ax,bx			; AX = original date again
	mov	cl,5
	shr	ax,cl
	and	ax,0Fh
	dec	ax			; AX = # of full months elapsed
	xchg	si,ax			; SI = # of full months
;
; The leap days calculation above did not account for the leap day in the
; first year, which must be added ONLY if the number of months spans February.
;
	test	ax,ax			; year zero?
	jnz	dow0			; no
	cmp	si,2			; yes, does the date span Feb?
	jb	dow1			; no
dow0:	inc	di			; yes, so add one more leap day

dow1:	dec	si
	jl	dow2
	mov	dl,[MONTH_DAYS][si]
	mov	dh,0
	add	di,dx			; add # of days in month to DI
	jmp	dow1
dow2:	mov	ax,bx			; AX = original date again
	and	ax,1Fh			; AX = day of the current month
	add	di,ax
	xchg	ax,di
	inc	ax			; add 1 day (1st date was a Tues)
	sub	dx,dx			; DX:AX = total days
	mov	cx,7			; divide by length of week
	div	cx
	mov	si,dx			; SI = remainder from DX (0-6)
	add	si,si			; convert day-of-week index to offset
	mov	ax,[DAYS][si]		; AX -> day-of-week string
	xchg	ax,si			; SI -> string
	shr	ax,1			; AX = day of week (0-6)
	pop	di
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	day_of_week

DOS	ends

	end
