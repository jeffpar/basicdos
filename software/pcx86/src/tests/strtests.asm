;
; BASIC-DOS Miscellaneous String Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

        ASSUME  CS:DOS, DS:DOS, ES:DOS, SS:DOS

	org	100h

DEFPROC	main
;
; The following REALLOC is not necessary in BASIC-DOS, because it detects
; our COMHEAP signature and resizes us automatically, but if we want to run
; with the same footprint in PC DOS, then we must still resize ourselves.
;
	mov	bx,offset HEAP + MINHEAP
	and	bl,0F0h
	or	bl,0Eh		; BX adjusted to top word of top paragraph
	mov	word ptr [bx],0	; store a zero there so we can simply return
	mov	sp,bx		; lower the stack
	mov	cl,4
	add	bx,15
	shr	bx,cl
	mov	ah,DOS_MEM_REALLOC
	int	21h
;
; In BASIC-DOS, we could also use INT 20h here, but PC DOS requires that CS
; contain the PSP being terminated when calling INT 20h (BASIC-DOS does not).
;
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
	ret			; a return is not necessary, but just in case
ENDPROC	main

;
; Begin excerpt from DOSDATA.ASM
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
;
; Begin excerpt from MATH.ASM
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
; Begin excerpt from MISC.ASM
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
; Begin excerpt from UTILITY.ASM
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
;
; End excerpts
;

;
; COMHEAP 0 means we don't need a heap, but BASIC-DOS will still allocate a
; minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

DOS	ends

	end	main
