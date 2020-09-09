;
; BASIC-DOS Physical Clock Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	CLOCK
CLOCK	DDH	<offset DEV:ddclk_end+16,,DDATTR_CLOCK+DDATTR_CHAR+DDATTR_IOCTL,offset ddclk_init,-1,2020244B434F4C43h>

	DEFLBL	CMDTBL,word
	dw	ddclk_none,   ddclk_none,  ddclk_none,  ddclk_ctlin	; 0-3
	dw	ddclk_read,   ddclk_none,  ddclk_none,  ddclk_none	; 4-7
	dw	ddclk_write,  ddclk_none,  ddclk_none,  ddclk_none	; 8-11
	dw	ddclk_ctlout, ddclk_none,  ddclk_none			; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFPTR	tmr_int,0		; timer hardware interrupt handler
	DEFPTR	wait_ptr,-1		; chain of waiting packets
	DEFBYTE	dateDay,3		; 1-31
	DEFBYTE	dateMonth,9		; 1-12
	DEFWORD	dateYear,2020		; 1980-
	DEFLONG	ticksToday,786520	; ticks since midnight (noon default)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddclk_req,far
	mov	di,bx			; ES:DI -> DDP
	mov	bl,es:[di].DDP_CMD
	cmp	bl,CMDTBL_SIZE
	jb	ddq1
	mov	bl,0
ddq1:	push	cs
	pop	ds
	ASSUME	DS:CODE
	mov	bh,0
	add	bx,bx
	call	CMDTBL[bx]
	ret
ENDPROC	ddclk_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddclk_ctlin
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;	Varies
;
; Modifies:
;	AX, CX, DX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddclk_ctlin
	mov	al,es:[di].DDP_UNIT	; AL = IOCTL command
	mov	cx,es:[di].DDPRW_LENGTH	; CX = IOCTL input value
	mov	dx,es:[di].DDPRW_LBA	; DX = IOCTL input value
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD

	cmp	al,IOCTL_WAIT
	jne	dci2
;
; For WAIT requests, convert # ms in CX:DX (1000/second to # ticks (18.2/sec).
;
; 1 tick is equivalent to approximately 55ms, so that's the granularity of
; WAIT requests as well as all clock-driven context switches; context switches
; can also be triggered by other hardware interrupts, like keyboard interrupts,
; so this is not the full measure of context-switching granularity.
;
	add	dx,27			; add 1/2 tick (as # ms) for rounding
	adc	cx,0
	mov	bx,55			; BX = divisor
	xchg	ax,cx			; AX = high dividend
	mov	cx,dx			; CX = low dividend
	sub	dx,dx
	div	bx			; AX = high quotient
	xchg	ax,cx			; AX = low dividend, CX = high quotient
	div	bx			; AX = low quotient
	mov	es:[di].DDPRW_LBA,ax	; CX:AX = # ticks
	mov	es:[di].DDPRW_LENGTH,cx
;
; Now add this packet to an internal chain of "waiting" packets, and tell
; DOS that we're waiting; DOS will suspend the current SCB until we notify
; it that this packet's conditions are satisfied.
;
	cli
	mov	ax,di
	xchg	[wait_ptr].OFF,ax
	mov	es:[di].DDP_PTR.OFF,ax
	mov	ax,es
	xchg	[wait_ptr].SEG,ax
	mov	es:[di].DDP_PTR.SEG,ax
	sti
;
; The WAIT condition is satisfied when the packet's LENGTH:OFFSET pair (which
; should contain a standard CX:DX tick count) has been decremented to zero.
;
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	mov	ax,DOS_UTL_WAIT
	int	21h
	jmp	dci8

dci2:	cmp	al,IOCTL_SETDATE
	jne	dci3
;
; For SETDATE requests, CL = year (0-127), DH = month (1-12), DL = day (1-31).
;
	cli
	mov	ch,0
	add	cx,1980
	mov	[dateYear],cx
	mov	word ptr [dateDay],dx
	sti
	jmp	dci8

dci3:	cmp	al,IOCTL_SETTIME
	je	dci3a
	jmp	dci4
;
; For SETTIME requests, we convert the hours (CH), minutes (CL), seconds
; (DH), and hundredths (DL) to a number of ticks.  We start by converting
; time to the total number of seconds (hundredths are dealt with later).
;
dci3a:	push	dx			; save DX
	mov	ax,3600			; AX = # seconds in 1 hour
	mov	dl,ch
	mov	dh,0
	mul	dx			; DX:AX = # seconds in CH hours
	xchg	bx,ax			; DX:BX
	mov	al,60
	mul	cl			; AX = # seconds in CL minutes
	add	bx,ax
	adc	dx,0			; DX:BX = # seconds in hours and mins
	pop	ax			; AH = seconds (from DX)
	push	ax
	mov	al,ah			; AL = seconds
	cbw				; AX = seconds
	add	bx,ax
	adc	dx,0			; DX:BX += seconds
;
; Now we'll convert total # seconds to total # ticks, by noting that
; there are 1193180/65536 ticks/sec, so 1193180/65536 * seconds = ticks.
; Seconds has an upper limit of 86400 for the day, so ticks has an upper
; limit of 1573040.  Using the ratio 1573040/86400 = ticks/seconds, solve
; for ticks: 1573040 * seconds / 86400, or 19663 * seconds / 1080.
;
	shr	dx,1			; DX:BX / 2 yields a max 43200
	rcr	bx,1			; BX = seconds / 2
	pushf				; save remainder, if any, for later

	mov	ax,19663
	mul	bx			; DX:AX = BX * 19663
	mov	bx,540			; divisor is 1080 / 2
;
; Divide DX:AX by BX in stages, so that we don't risk division overflow.
;
	xchg	cx,ax			; save low dividend
	xchg	ax,dx			; divide high dividend
	sub	dx,dx			; DX:AX is new dividend
	div	bx			; AX is high quotient
	xchg	ax,cx			; move to CX, restore low dividend
	div	bx			; AX is low quotient

	IFDEF MAXDEBUG
	DPRINTF	<"initial number of ticks: %ld",13,10>,ax,cx
	DPRINTF	<"with remainder of %d after division by %d",13,10>,dx,bx
	ENDIF
;
; CX:AX = quotient (# ticks).  DX/540 is a fractional tick, which we convert
; to hundredths and add to the hundredths adjustment below.
;
	push	ax
	xchg	ax,dx
	mov	dl,100
	div	dl
	xchg	bx,ax			; BL = additional hundredths
	mov	dx,cx
	pop	cx			; DX:CX = tick count

	IFDEF MAXDEBUG
	mov	bh,0
	DPRINTF	<"hundredths for fractional tick: %d",13,10>,bx
	ENDIF

	popf				; did seconds / 2 produce a remainder?
	jnc	dci3b			; no
	add	bl,100			; yes, add another 100 hundredths

	IFDEF MAXDEBUG
	DPRINTF	<"hundredths for additional second: %d",13,10>,bx
	ENDIF

dci3b:	pop	ax			; AL = hundredths (from original DX)
	add	al,bl			; add any hundredths from above

	IFDEF MAXDEBUG
	mov	ah,0
	DPRINTF	<"total hundredths: %d",13,10>,ax
	ENDIF

	mov	ah,18
	mul	ah			; AX = hundredths * 18
	mov	bl,100
	div	bl			; AL = (hundredths * 18) / 100
	cbw				; AX = # ticks for hundredths
	add	cx,ax
	adc	dx,0			; DX:CX += ticks for hundredths

	IFDEF MAXDEBUG
	DPRINTF	<"%04C:%04I: new tick count: %ld",13,10>,cx,dx
	ENDIF

	cli
	mov	[ticksToday].LOW,cx
	mov	[ticksToday].HIW,dx
	sti
	jmp	dci8

dci4:	cmp	al,IOCTL_GETDATE
	jne	dci5
;
; For GETDATE requests, return the date in "packed" format:
;
;	 Y  Y  Y  Y  Y  Y  Y  M  M  M  M  D  D  D  D  D
;	15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00
;
; where Y = year-1980 (0-127), M = month (1-12), and D = day (1-31).
;
	cli
	mov	dx,[dateYear]
	sub	dx,1980
	mov	cl,4			; make room for month (4 bits)
	shl	dx,cl
	or	dl,[dateMonth]
	inc	cx
	shl	dx,cl			; make room for day (5 bits)
	or	dl,[dateDay]
	sti
	jmp	dci8
dci4x:	jmp	dci9

dci5:	cmp	al,IOCTL_GETTIME
	jne	dci4x
;
; For GETTIME requests, return the time in "packed" format:
;
;	 H  H  H  H  H  M  M  M  M  M  M  S  S  S  S  S
;	15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00
;
; where H = hours (1-12), M = minutes (0-59), and S = seconds / 2 (0-29)
;
; However, we must first convert # ticks to hours/minutes/seconds.  There
; are approximately 32771 ticks per half-hour, 1092 ticks per minute, and 18
; ticks per sec.
;
	cli
	mov	ax,[ticksToday].LOW
	mov	dx,[ticksToday].HIW
	sti

	IFDEF MAXDEBUG
	DPRINTF	<"%04C:%04I: current tick count: %ld",13,10>,ax,dx
	ENDIF
;
; TODO: the true divisor is 32771.66748046875, so the remainder may be too
; large; this appears to be good enough for now, but deal with it eventually.
;
	mov	bx,32772
	div	bx			; AX = # half-hours
	shr	ax,1			; AX = # hours
	xchg	cx,ax			; CL = # hours
	xchg	ax,dx			; AX = # half-hour ticks remaining
	mov	dx,0			; DX:AX
	jnc	dci5a
	add	ax,32772		; DX:AX = # ticks remaining
	adc	dx,0

dci5a:	mov	bx,1092
	div	bx			; AX = # minutes
;
; The true divisor is 1092.388916015625, so the remainder may be too large;
; multiply AX (# of minutes) by 3889 and divide by 10000 to yield the number
; of ticks to reduce the remainder (DX) by.
;
	push	ax
	push	dx
	mov	bx,3889
	mul	bx
	mov	bx,10000
	div	bx
	pop	dx
	sub	dx,ax
	jae	dci5b
	sub	dx,dx
dci5b:	pop	ax

	mov	ch,al			; CH = # minutes
	xchg	ax,dx			; AX = # ticks remaining
	mov	bx,10
	mul	bx			; DX:AX = # ticks * 10
	mov	bx,182
	div	bx			; AX = # seconds
	push	dx			; DX = # ticks * 10 remaining (< 182)
;
; Sanitize the time values now, ensuring we never return values out of bounds.
;
	cmp	al,60			; AL = # seconds
	jb	dci6
	mov	al,0
	inc	ch
dci6:	cmp	ch,60			; CH = # minutes
	jb	dci6b
	mov	ch,0
	inc	cx
dci6b:	cmp	cl,24			; CL = # hours
	jb	dci7
	mov	cl,0
;
; Create the "packed" time format now.
;
dci7:	mov	dl,cl			; start with hours (5 bits)
	mov	cl,6			; make room for minutes (6 bits)
	shl	dx,cl
	or	dl,ch			; add the minutes
	dec	cx			; make room for seconds / 2 (5 bits)
	shl	dx,cl
	pop	cx			; CX = # ticks remaining (from above)
	shr	al,1			; AL = seconds / 2
	jnc	dci7a
	add	cx,182
dci7a:	or	dl,al
	xchg	ax,cx			; AL = # ticks remaining (< 364)
;
; At this point, the packed result is ready, but we'd also like to convert
; the remaining ticks in AX to hundredths (< 200).  AX/364 = N/200.  We return
; up to 200 hundredths to compensate for the "packed" time containing only
; the nearest EVEN second.
;
	push	dx
	mov	cx,200
	mul	cx			; DX:AX = AX * 200
	mov	cx,364
	div	cx			; AX = (AX * 200) / 364
	pop	dx

dci8:	mov	es:[di].DDP_CONTEXT,dx	; return value goes in context field
	mov	ah,DDSTAT_DONE SHR 8
	mov	es:[di].DDP_STATUS,ax	; return AL in DDP_STATUS, too
dci9:	ret
ENDPROC	ddclk_ctlin

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddclk_ctlout
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddclk_ctlout
	ret
ENDPROC	ddclk_ctlout

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddclk_read
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddclk_read
	ret
ENDPROC	ddclk_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddclk_write
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddclk_write
	ret
ENDPROC	ddclk_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddclk_none (handler for unimplemented functions)
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddclk_none
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	stc
	ret
ENDPROC	ddclk_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddclk_interrupt (timer hardware interrupt handler)
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddclk_interrupt,far
	call	far ptr DDINT_ENTER
	pushf
	call	[tmr_int]
	push	ax
	push	bx
	push	dx
	push	di
	push	ds
	push	es
	mov	ax,cs
	mov	ds,ax
	ASSUME	DS:CODE

	add	[ticksToday].LOW,1
	adc	[ticksToday].HIW,0
;
; The maximum ticks per day (1573040) is 0018:00B0.
;
	cmp	[ticksToday].HIW,18h
	jb	ddi0a			; no overflow yet
	ASSERT	Z
	ja	ddi0			; large overflow (how'd that happen?)
	cmp	[ticksToday].LOW,00B0h
	jb	ddi0a
ddi0:	mov	[ticksToday].LOW,0
	mov	[ticksToday].HIW,0
;
; We use a DOS utility function to increment the date, since DOS already
; contains the required calendar data to properly increment a date (ie, it
; is not a device-specific operation).
;
	mov	cx,[dateYear]
	mov	dx,word ptr [dateDay]
	mov	ax,DOS_UTL_INCDATE
	int	21h
	mov	[dateYear],cx
	mov	word ptr [dateDay],dx

ddi0a:	mov	bx,offset wait_ptr	; DS:BX -> ptr
	les	di,[bx]			; ES:DI -> packet, if any
	ASSUME	ES:NOTHING
	sti

ddi1:	cmp	di,-1			; end of chain?
	je	ddi9			; yes

	ASSERT	STRUCT,es:[di],DDP
;
; We wait for the double-word decrement to underflow (ie, to go from 0 to -1)
; since that's the simplest to detect.  And while you might think that means we
; always wait 1 tick longer than requested -- well, sort of.  We have no idea
; how much time elapsed between the request's arrival and the first tick; that
; time could be almost zero, so think of the tick count as "full" ticks.
;
	sub	es:[di].DDPRW_LBA,1
	sbb	es:[di].DDPRW_LENGTH,0
	jae	ddi6			; keep waiting
;
; Notify DOS that the SCB associated with this packet is done waiting.
;
ddi2:	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	mov	ax,DOS_UTL_ENDWAIT
	int	21h
	jnc	ddi3
;
; If ENDWAIT returns an error, we presume that we simply got ahead of the
; WAIT call, so rewind the count to zero and leave the packet on the list.
;
	mov	es:[di].DDPRW_LBA,0
	mov	es:[di].DDPRW_LENGTH,0
	jmp	short ddi6
;
; WAIT condition has been satisfied, remove packet from wait_ptr list.
;
ddi3:	cli
	mov	ax,es:[di].DDP_PTR.OFF
	mov	[bx].OFF,ax
	mov	ax,es:[di].DDP_PTR.SEG
	mov	[bx].SEG,ax
	sti
	jmp	short ddi7

ddi6:	lea	bx,[di].DDP_PTR		; update prev addr ptr in DS:BX
	push	es
	pop	ds

ddi7:	les	di,es:[di].DDP_PTR
	jmp	ddi1

ddi9:	pop	es
	pop	ds
	pop	di
	pop	dx
	pop	bx
	pop	ax
	stc				; set carry to indicate yield
	jmp	far ptr DDINT_LEAVE
ENDPROC	ddclk_interrupt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddclk_init,far
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS

	ASSERT	STRUCT,es:[bx],DDP

	mov	es:[bx].DDPI_END.OFF,offset ddclk_init
	mov	cs:[0].DDH_REQUEST,offset DEV:ddclk_req
;
; Install an INT 08h hardware interrupt handler, which we will use to service
; WAIT requests, and which will also drive the DOS scheduler as soon as DOS has
; initialized and revectored DDINT_ENTER/DDINT_LEAVE.
;
	cli
	mov	ax,offset ddclk_interrupt
	xchg	ds:[INT_HW_TMR * 4].OFF,ax
	mov	[tmr_int].OFF,ax
	mov	ax,cs
	xchg	ds:[INT_HW_TMR * 4].SEG,ax
	mov	[tmr_int].SEG,ax
	sti

	ret
ENDPROC	ddclk_init

CODE	ends

DATA	segment para public 'DATA'

ddclk_end	db	16 dup(0)

DATA	ends

	end
