;
; BASIC-DOS Library Functions (for testing outside of BASIC-DOS)
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	8086.inc	; needed for FL_CARRY, etc
	include	macros.inc
	include	dos.inc
	include	dosapi.inc
	include	parser.inc	; needed for BUFLEN, etc

DOS	segment word public 'CODE'

	EXTNEAR	<sprintf>

        ASSUME  CS:DOS, DS:DOS, ES:DOS, SS:DOS

DEFPROC	bd_init
	pop	ax		; save the return address
	and	bl,0F0h
	or	bl,0Eh		; BX adjusted to top word of top paragraph
	mov	word ptr [bx],0	; store a zero there so we can simply return
	sub	bx,2
	mov	[bx],ax		; store the return address at new stack address
	mov	sp,bx		; lower the stack
	mov	cl,4
	add	bx,15
	shr	bx,cl
	mov	ah,DOS_MEM_REALLOC
	int	21h
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSUTIL
	mov	dx,offset bd_util
	int	21h
	ret
ENDPROC	bd_init

DEFPROC	bd_util
	cld
	add	ah,80h
	jmp	near ptr bd_func + 1	; avoid same entry point as bd_func
ENDPROC	bd_util

DEFPROC	bd_func
	cld				; we assume CLD everywhere
	sub	sp,size WS_TEMP
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
;
; While we assign DS and ES to the DOS segment on DOS function entry, we
; do NOT assume they will still be set that way when the FUNCTBL call returns.
;
	mov	bx,cs
	mov	ds,bx
	mov	es,bx
;
; Utility functions don't automatically re-enable interrupts, clear carry,
; or check for CTRLC, since some of them are called from interrupt handlers.
;
	cmp	ah,80h			; utility function?
	jb	dc1			; no
	sub	ah,80h
	cmp	ah,UTILTBL_SIZE		; utility function within range?
	jae	dc4			; no
	mov	bl,ah
	add	bl,FUNCTBL_SIZE		; the utility function table
	jmp	short dc2		; follows the DOS function table

dc1:	sti
	and	[bp].REG_FL,NOT FL_CARRY
	cmp	ah,FUNCTBL_SIZE
	cmc
	jb	dc3
	mov	bl,ah
dc2:	mov	bh,0			; BX = function #
	add	bx,bx			; convert function # to word offset
;
; For convenience, general-purpose registers AX, CX, DX, SI, DI, and SS
; contain their original values.
;
	call	FUNCTBL[bx]
;
; We'd just as soon IRET to the caller (which also restores their D flag),
; so we now update FL_CARRY on the stack (which we already cleared on entry).
;
dc3:	adc	[bp].REG_FL,0

dc4:	pop	bp
	pop	di
	pop	es
	pop	si
	pop	ds
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	add	sp,size WS_TEMP
	iret
ENDPROC	bd_func
;
; Begin excerpt from OS/DOS/CONIO.ASM
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_string
;
; Inputs:
;	CX = length
;	DS:SI -> string
;
; Outputs:
;	Carry clear if successful, set otherwise
;
; Modifies:
;	AX
;
DEFPROC	write_string
	jcxz	ws8
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es
ws6:	lodsb
	int	INT_FASTCON		; fallback to INT 29h
	loop	ws6
	pop	es
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
ws8:	clc
	ret
ENDPROC	write_string
;
; Begin excerpt from OS/DOS/MATH.ASM
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; div_32_16
;
; Divide DX:AX by CX, returning quotient in DX:AX and remainder in BX.
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	div_32_16
	mov	bx,ax			; save low dividend in BX
	mov	ax,dx			; divide high dividend
	sub	dx,dx			; DX:AX = new dividend
	div	cx			; AX = high quotient
	xchg	ax,bx			; move to BX, restore low dividend
	div	cx			; AX = low quotient
	xchg	dx,bx			; DX:AX = new quotient, BX = remainder
	ret
ENDPROC	div_32_16
;
; Begin excerpt from OS/DOS/MISC.ASM
;
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
DEFPROC	day_of_week
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
;
; Begin excerpt from OS/DOS/UTILITY.ASM
;
DEFPROC	strlen			; for internal calls (no REG_FRAME)
	push	cx
	push	di
	push	es
	push	ds
	pop	es
	mov	di,si
	mov	cx,di
	not	cx		; CX = largest possible count
	repne	scasb
	je	sl8
	sub	ax,ax		; operation failed
	stc			; return carry set and zero length
	jmp	short sl9
sl8:	sub	di,si
	lea	ax,[di-1]	; don't count the terminator character
sl9:	pop	es
	pop	di
	pop	cx
	ret
ENDPROC	strlen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_printf (AH = 04h)
;
; A CDECL-style calling convention is assumed, where all parameters EXCEPT
; for the format string are pushed from right to left, so that the first
; (left-most) parameter is the last one pushed.  The format string is stored
; in the CODE segment following the INT XX, which we automatically skip, and
; the next instruction should be an "ADD SP,N*2", assuming N word parameters.
;
; Use the PRINTF macro to simplify calls to this function.
;
; Inputs:
;	format string follows the INT XX
;	all other parameters must be pushed onto the stack, right to left
;
; Outputs:
;	REG_AX = # of characters printed
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; See sprintf.asm for more information on the format string.
;
DEFPROC	utl_printf,DOS
	ASSUME	DS:NOTHING,ES:NOTHING
;	mov	bl,0
	DEFLBL	hprintf,near		; BL = SFH (or 0 for STDOUT)
	sti
	push	ss
	pop	es
	mov	cx,BUFLEN		; CX = length
	sub	sp,cx
	mov	di,sp			; ES:DI -> buffer on stack
	push	bx
	mov	bx,[bp].REG_IP
	mov	ds,[bp].REG_CS		; DS:BX -> format string
	call	sprintf
	mov	[bp].REG_AX,ax		; update REG_AX with count in AX
	add	[bp].REG_IP,bx		; update REG_IP with length in BX
	pop	bx
	mov	si,sp
	push	ss
	pop	ds			; DS:SI -> buffer on stack
	xchg	cx,ax			; CX = # of characters
;	test	bl,bl			; SFH?
;	jz	pf7			; no
;	jl	pf8			; DEBUG output not enabled
;	call	sfb_from_sfh		; BX -> SFB
;	jc	pf7
;	mov	al,IO_COOKED
;	call	sfb_write
;	jmp	short pf8
pf7:	call	write_string		; write string to STDOUT
pf8:	add	sp,BUFLEN		; carry should always be clear now
	ret
ENDPROC	utl_printf
;
; Begin excerpt from OS/DOS/DOSDATA.ASM
;
	DEFBYTE	JAN,<"January",0>
	DEFBYTE	FEB,<"February",0>
	DEFBYTE	MAR,<"March",0>
	DEFBYTE	APR,<"April",0>
	DEFBYTE	MAY,<"May",0>
	DEFBYTE	JUN,<"June",0>
	DEFBYTE	JUL,<"July",0>
	DEFBYTE	AUG,<"August",0>
	DEFBYTE	SEP,<"September",0>
	DEFBYTE	OCT,<"October",0>
	DEFBYTE	NOV,<"November",0>
	DEFBYTE	DEC,<"December",0>
	DEFWORD	MONTHS,<JAN,FEB,MAR,APR,MAY,JUN,JUL,AUG,SEP,OCT,NOV,DEC>
	DEFBYTE	SUN,<"Sunday",0>
	DEFBYTE	MON,<"Monday",0>
	DEFBYTE	TUE,<"Tuesday",0>
	DEFBYTE	WED,<"Wednesday",0>
	DEFBYTE	THU,<"Thursday",0>
	DEFBYTE	FRI,<"Friday",0>
	DEFBYTE	SAT,<"Saturday",0>
	DEFWORD	DAYS,<SUN,MON,TUE,WED,THU,FRI,SAT>
	DEFBYTE	MONTH_DAYS,<31,28,31,30,31,30,31,31,30,31,30,31>

	DEFLBL	FUNCTBL,word
	DEFWORD ,<psp_term,    tty_echo,    tty_write,   aux_read>	;00-03
	DEFWORD	,<aux_write,   prn_write,   tty_io,      tty_in>	;04-07
	DEFWORD	,<tty_read,    tty_print,   tty_input,   tty_status>	;08-0B
	DEFWORD	,<tty_flush,   dsk_flush,   dsk_setdrv,  fcb_open>	;0C-0F
	DEFWORD	,<fcb_close,   func_none,   func_none,   func_none>	;10-13
	DEFWORD	,<fcb_sread,   func_none,   func_none,   func_none>	;14-17
	DEFWORD	,<func_none,   dsk_getdrv,  dsk_setdta,  func_none>	;18-1B
	DEFWORD	,<func_none,   func_none,   func_none,   func_none>	;1C-1F
	DEFWORD	,<func_none,   fcb_rread,   func_none,   func_none>	;20-23
	DEFWORD	,<fcb_setrel,  msc_setvec,  psp_copy,    fcb_rbread>	;24-27
	DEFWORD	,<func_none,   fcb_parse,   msc_getdate, msc_setdate>	;28-2B
	DEFWORD	,<msc_gettime, msc_settime, func_none,   dsk_getdta>	;2C-2F
	DEFWORD	,<msc_getver,  func_none,   func_none,   msc_setctrlc>	;30-33
	DEFWORD	,<func_none,   msc_getvec,  dsk_getinfo, msc_getswc>	;34-37
	DEFWORD	,<func_none,   func_none,   func_none,   func_none>	;38-3B
	DEFWORD	,<func_none,   hdl_open,    hdl_close,   hdl_read>	;3C-3F
	DEFWORD	,<hdl_write,   func_none,   hdl_seek,    func_none>	;40-43
	DEFWORD	,<hdl_ioctl,   func_none,   func_none,   func_none>	;44-47
	DEFWORD	,<mem_alloc,   mem_free,    mem_realloc, psp_exec>	;48-4B
	DEFWORD	,<psp_return,  psp_retcode, dsk_ffirst,  dsk_fnext>	;4C-4F
	DEFWORD	,<psp_set,     psp_get,     msc_getvars, func_none>	;50-53
	DEFWORD	,<func_none,   psp_create>				;54-55
	DEFABS	FUNCTBL_SIZE,<($ - FUNCTBL) SHR 1>

	DEFLBL	UTILTBL,word
	DEFWORD	,<utl_strlen,  utl_strstr,  func_none,   utl_strupr>	;00-03
	DEFWORD	,<utl_printf,  utl_dprintf, utl_sprintf, utl_itoa>	;04-07
	DEFWORD	,<utl_atoi16,  utl_atoi32,  utl_atoi32d, func_none>	;08-0B
	DEFWORD	,<utl_atof64,  utl_i32f64,  utl_opf64,   func_none>	;0C-0F
	DEFWORD	,<func_none,   utl_tokify,  utl_tokify,  utl_tokid>	;10-13
	DEFWORD	,<utl_parsesw, utl_getdev,  utl_getcsn,  func_none>	;14-17
	DEFWORD	,<utl_load,    utl_start,   utl_stop,    utl_end>	;18-1B
	DEFWORD	,<utl_waitend, utl_yield,   utl_sleep,   utl_wait>	;1C-1F
	DEFWORD	,<utl_endwait, utl_hotkey,  utl_lock,    utl_unlock>	;20-23
	DEFWORD	,<utl_strlen,  utl_qrymem,  utl_term,    utl_getdate>	;24-27
	DEFWORD	,<utl_gettime, utl_incdate, utl_editln,  utl_restart>	;28-2B
	DEFABS	UTILTBL_SIZE,<($ - UTILTBL) SHR 1>

DOS	ends

	end
