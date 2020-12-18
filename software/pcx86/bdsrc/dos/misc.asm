;
; BASIC-DOS Miscellaneous Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dev.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc
	include	version.inc

DOS	segment word public 'CODE'

	EXTNEAR	<tty_read,write_string,dos_restart,dev_request>
	EXTSTR	<STR_CTRLC>
	IF REG_CHECK
	EXTNEAR	<dos_check>
	ENDIF

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
	cmp	dl,MONTH_DAYS[bx]
	ja	msd9
;
; As in add_date, if the month index is 1 (Feb) and the year is a leap year,
; then recheck the day.  As noted in day_of_week, the leap year check is
; simplified by our limited year range (1980-2099).
;
	cmp	bl,1			; Feb?
	jne	msd1			; no
	test	cl,3			; leap year?
	jnz	msd1			; no
	cmp	dl,29			; day within the longer month?
	jbe	msd9			; yes

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
; For now, this is hard-coded to return 02h in AL, so that we can experiment
; with assorted PC DOS 2.00 binaries without hitting version-check roadblocks.
;
; However, we also set AH to our major version, BH to our minor version, BL
; to our revision, and CX to indicate internal states (eg, bit 0 is set for
; DEBUG builds).
;
; Inputs:
;	None
;
; Outputs:
;	REG_AL = major version # (BASIC-DOS: 02h)
;	REG_AH = minor version # (BASIC-DOS: major version)
;	REG_BH = OEM serial #    (BASIC-DOS: minor version)
;	REG_BL = upper 8 bits of 24-bit S/N (BASIC-DOS: revision)
;	REG_CX = lower 16 bits of 24-bit S/N (BASIC-DOS: internal states)
;
; Modifies:
;	AX
;
DEFPROC	msc_getver,DOS
	mov	[bp].REG_AX,(VERSION_MAJOR SHL 8) OR 02h
	mov	[bp].REG_BX,(VERSION_MINOR SHL 8) OR VERSION_REV
	sub	ax,ax
	IFDEF DEBUG
	inc	ax
	ENDIF
	mov	[bp].REG_CX,ax
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

	DEFLBL	msc_sigctrlc_read,near
	ASSERT	STRUCT,[bx],SCB
	cmp	[bx].SCB_CTRLC_ACT,0
	je	msg1
	call	tty_read		; remove CTRLC from the input buffer
msg0:	mov	[bx].SCB_CTRLC_ACT,0
;
; Make sure that whatever function we're interrupting has not violated
; our BP convention; some functions prefer to use BP as an extra register,
; and that's OK as long as 1) they're not an interruptable function and 2)
; they restore BP when they're done.
;
msg1:	IF REG_CHECK
	ASSERT	Z,<cmp word ptr [bp-2],offset dos_check>
	ENDIF

	mov	cx,STR_CTRLC_LEN
	mov	si,offset STR_CTRLC
	call	write_string
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
; msc_sigerr
;
; Unlike msc_sigctrlc, this signals errors from a variety of sources, so
; don't assume BP refers to a REG_FRAME.
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
DEFPROC	msc_sigerr
	ASSUME	DS:NOTHING, ES:NOTHING
	push	bx
	push	ds

	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	pushf
	call	[bx].SCB_ERROR
;
; Check the handler's return code and decide what to do.
;
	cmp	al,CRERR_ABORT		; abort program via INT 23h?
	jne	ms9			; no
	pushf
	call	[bx].SCB_CTRLC		; yes
;
; TODO: Add support for other responses.
;
ms9:	pop	ds
	pop	bx
	ret
ENDPROC	msc_sigerr

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
; Get/set the current switch character ("switchar").
;
; Inputs:
;	If REG_AL = 0, returns current switch character in REG_DL
;	If REG_AL = 1, set the current switch character from REG_DL
;	Otherwise, set REG_AL to 0FFh to indicate unsupported subfunction
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
	test	al,al
	jnz	gsw1
	mov	al,[bx].SCB_SWITCHAR
	mov	[bp].REG_DL,al		; DL = "switchar"
	jmp	short gsw9
gsw1:	dec	al
	jnz	gsw2
	mov	[bx].SCB_SWITCHAR,dl	; update "switchar"
	jmp	short gsw9
gsw2:	mov	byte ptr [bp].REG_AL,0FFh; (unsupported subfunction)
gsw9:	ret
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
