;
; BASIC-DOS Physical Clock Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	BIOSAPI equ 1
	CLKTIMER equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	CLOCK
CLOCK	DDH	<offset DEV:ddclk_end+16,,DDATTR_CLOCK+DDATTR_CHAR+DDATTR_IOCTL,offset ddclk_init,-1,2020244B434F4C43h>
	dw	offset DEV:ddclk_timer	; CLKX (see dev.inc)

	DEFLBL	CMDTBL,word
	dw	ddclk_none,   ddclk_none,  ddclk_none,  ddclk_ctlin	; 0-3
	dw	ddclk_read,   ddclk_none,  ddclk_none,  ddclk_none	; 4-7
	dw	ddclk_write,  ddclk_none,  ddclk_none,  ddclk_none	; 8-11
	dw	ddclk_ctlout, ddclk_none,  ddclk_none			; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFPTR	tmr_int,0		; timer hardware interrupt handler
	DEFPTR	wait_ptr,0FFFFh,0	; chain of waiting packets (none)
	DEFPTR	tmr_list,0FFFFh,0	; chain of running timers (none)
	DEFBYTE	dateDay,10		; 1-31 (default for PC and XT)
	DEFBYTE	dateMonth,12		; 1-12
	DEFWORD	dateYear,2020		; 1980-
	DEFBYTE	dateRTC,0		; 1 if date from a real-time clock
	DEFLONG	ticksToday,0		; ticks since midnight (from BIOS)
	DEFWORD	sndTicks,0		; ticks until the speaker is turned off

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
ddq1:	mov	ds,cs:[0].DDH_DATA
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
	mov	al,es:[di].DDP_CODE	; AL = IOCTL code
	mov	cx,es:[di].DDPRW_LENGTH	; CX = IOCTL input value
	mov	dx,es:[di].DDPRW_LBA	; DX = IOCTL input value
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD

	cmp	al,IOCTL_SOUND
	jne	dci1
;
; For SOUND requests, DX = PIT divisor and CX = # ticks; we turn off any
; current sound and then, if DX and CX are non-zero, start the new sound and
; let ddclk_interrupt turn it off after CX ticks.
;
	cli
	mov	[sndTicks],0
	in	al,61h
	and	al,0FCh
	out	61h,al			; turn the speaker off
	test	dx,dx
	jz	dci0
	jcxz	dci0
	mov	al,0B6h			; PIT channel 2, mode 3, LSB then MSB
	out	43h,al
	mov	al,dl
	out	42h,al
	mov	al,dh
	out	42h,al
	in	al,61h
	or	al,03h
	out	61h,al			; turn the speaker on
	mov	[sndTicks],cx
dci0:	sti
	jmp	dci8

dci1:	cmp	al,IOCTL_WAIT
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
	xchg	[wait_ptr]._OFF,ax
	mov	es:[di].DDP_PTR._OFF,ax
	mov	ax,es
	xchg	[wait_ptr]._SEG,ax
	mov	es:[di].DDP_PTR._SEG,ax
	sti
;
; The WAIT condition is satisfied when the packet's LENGTH:OFFSET pair (which
; should contain a standard CX:DX tick count) has been decremented to zero.
;
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	mov	ah,DOS_UTL_WAIT
	call	far ptr DDINT_UTIL	; wait on DX:DI (see int_util)
	jnc	dci1x
;
; The wait was interrupted (eg, by ABORT or CTRLC), so the packet must be
; removed from the chain; if it's no longer there, then the wait ended
; normally after all, so treat that as success.
;
	push	ax
	call	remove_packet		; carry clear if packet removed
	pop	ax
	jc	dci1x
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_GENFAIL
	ret
dci1x:	jmp	dci8

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
; for ticks: 1573040 * seconds / 86400, or 19663 * seconds / 1080; with
; hundredths, ticks = 19663 * hundredths / 108000.
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
	div	bx			; CX:AX = # ticks, DX = remainder

	IFDEF MAXDEBUG
	DPRINTF	<"initial number of ticks: %lu\r\n">,ax,cx
	DPRINTF	<"with remainder of %d after division by %u\r\n">,dx,bx
	ENDIF
;
; The remainder (DX/540 ticks) and the hundredths (plus 100 for an odd second)
; add (DX * 200 + hundredths * 19663) / 108000 ticks, which is less than 38.
;
	xchg	bx,dx			; BX = remainder
	popf				; did seconds / 2 produce a remainder?
	pop	dx			; DL = hundredths (from original DX)
	mov	dh,0
	jnc	dci3b			; no
	add	dl,100			; yes, add another 100 hundredths
dci3b:	push	cx
	push	ax			; save # ticks
	mov	ax,19663
	mul	dx			; DX:AX = hundredths * 19663
	xchg	ax,bx			; AX = remainder
	mov	cx,dx			; CX:BX = hundredths * 19663
	mov	dx,200
	mul	dx			; DX:AX = remainder * 200
	add	ax,bx
	adc	dx,cx
	shr	dx,1
	rcr	ax,1
	mov	bx,54000
	div	bx			; AX = ticks to add
	pop	cx
	add	cx,ax
	pop	dx
	adc	dx,0			; DX:CX = tick count

	IFDEF	MAXDEBUG
	DPRINTF	<"new tick count: %lu\r\n">,cx,dx
	ENDIF

	cli
	mov	[ticksToday].LW,cx
	mov	[ticksToday].HW,dx
	sti
	jmp	dci8

dci4:	cmp	al,IOCTL_CLOCK
	jne	dci4a
;
; For CLOCK requests, return DX = 1 if the date came from a real-time clock
; (see ddclk_init), or 0 if it's still our default date (eg, on a PC or XT).
;
	mov	dl,[dateRTC]
	mov	dh,0
	jmp	short dci4z

dci4a:	cmp	al,IOCTL_GETDATE
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
dci4z:	jmp	dci8
dci4x:	jmp	dci9

dci5:	cmp	al,IOCTL_GETTIME
	jne	dci4x
;
; For GETTIME requests, return the time in "packed" format:
;
;	 H  H  H  H  H  M  M  M  M  M  M  S  S  S  S  S
;	15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00
;
; where H = hours (0-23), M = minutes (0-59), and S = seconds / 2 (0-29),
; along with hundredths (< 200, since the packed time has only even seconds).
;
; However, we must first convert # ticks to # seconds.  There are 1573040
; ticks per day, so # seconds = ticks * 86400 / 1573040, or ticks * 1080 /
; 19663.  The tick count is less than 1573040 (0018:00B0), so ticks * 1080
; fits in 32 bits, and the remainder of the division gives the hundredths.
;
	cli
	mov	ax,[ticksToday].LW
	mov	dx,[ticksToday].HW
	sti

	IFDEF	MAXDEBUG
	DPRINTF	<"current tick count: %lu\r\n">,ax,dx
	ENDIF

	mov	cx,1080
	xchg	bx,ax			; BX = low ticks
	xchg	ax,dx			; AX = high ticks (< 18h)
	mul	cx			; AX = high ticks * 1080
	xchg	ax,bx			; BX = high product, AX = low ticks
	mul	cx
	add	dx,bx			; DX:AX = ticks * 1080
;
; Divide DX:AX by 19663 in stages, since the quotient can exceed 16 bits.
;
	mov	bx,19663
	xchg	cx,ax			; save low dividend
	xchg	ax,dx			; divide high dividend (< 8000h)
	cwd				; DX:AX is new dividend
	div	bx			; AX is high quotient
	xchg	ax,cx			; move to CX, restore low dividend
	div	bx			; CX:AX = # seconds, DX = remainder
	push	cx
	push	ax
	xchg	ax,dx
	mov	cx,100
	mul	cx
	div	bx			; AX = hundredths (< 100)
	pop	bx
	pop	dx
	xchg	ax,bx			; DX:AX = # seconds, BX = hundredths
	mov	cx,3600
	div	cx			; AX = # hours, DX = # seconds left
	xchg	ax,dx			; DX = # hours
	mov	cl,60
	div	cl			; AL = # minutes, AH = # seconds
;
; Create the "packed" time format now.
;
	mov	cl,6			; make room for minutes (6 bits)
	shl	dx,cl
	or	dl,al			; add the minutes
	dec	cx			; make room for seconds / 2 (5 bits)
	shl	dx,cl
	shr	ah,1			; AH = seconds / 2
	jnc	dci7
	add	bl,100			; return an odd second as hundredths
dci7:	or	dl,ah
;
; dev_request returns AX = the # bytes "transferred" (the original length less
; the remaining length), so that's how we return the hundredths.
;
	sub	es:[di].DDPRW_LENGTH,bx

dci8:	mov	es:[di].DDP_CONTEXT,dx	; return value goes in context field
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
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
; remove_packet
;
; Removes a packet from the chain of waiting packets, if it's still there.
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	Carry clear if the packet was removed, set if it wasn't found
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	remove_packet
	push	bx
	push	cx
	push	ds
	mov	ds,cs:[0].DDH_DATA
	mov	bx,offset wait_ptr	; DS:BX -> first link
	mov	cx,es			; CX:DI -> packet to remove
	pushf
	cli
rp1:	mov	ax,[bx]._OFF
	cmp	ax,-1			; end of chain?
	je	rp8			; yes, packet not found
	cmp	ax,di
	jne	rp2
	cmp	[bx]._SEG,cx
	je	rp3
rp2:	lds	bx,dword ptr [bx]	; DS:BX -> next packet
	lea	bx,[bx].DDP_PTR		; DS:BX -> its link
	jmp	rp1
rp3:	mov	ax,es:[di].DDP_PTR._OFF	; unlink the packet
	mov	[bx]._OFF,ax
	mov	ax,es:[di].DDP_PTR._SEG
	mov	[bx]._SEG,ax
	popf
	clc
	jmp	short rp9
rp8:	popf
	stc
rp9:	pop	ds
	pop	cx
	pop	bx
	ret
ENDPROC	remove_packet

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
; ddclk_timer (CLKX_TIMER)
;
; Starts (or cancels) a timer for another driver: after CX milliseconds
; (rounded up to whole clock ticks, where the first tick may be partial), the
; timer's TMR_FUNC is called from our timer interrupt handler, with ES:DI
; pointing to the timer and interrupts disabled; it may modify any registers
; except SS:SP and BP.  Starting a timer that's already running restarts it.
; This is a far entry (see CLKX) that may be called from interrupt handlers.
;
; Inputs:
;	ES:DI -> TMR (with TMR_FUNC set)
;	CX = milliseconds (0 to cancel)
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddclk_timer,far
	push	ax
	push	dx
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	pushf
	cli
	call	tmr_remove
	jcxz	dt9
	mov	ax,cx
	add	ax,54
	jnc	dt1
	mov	ax,-1
dt1:	sub	dx,dx
	push	cx
	mov	cx,55
	div	cx			; AX = ticks
	pop	cx
	mov	es:[di].TMR_TICKS,ax
	mov	ax,di
	xchg	[tmr_list]._OFF,ax
	mov	es:[di].TMR_NEXT._OFF,ax
	mov	ax,es
	xchg	[tmr_list]._SEG,ax
	mov	es:[di].TMR_NEXT._SEG,ax
dt9:	popf
	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	pop	ax
	ret
ENDPROC	ddclk_timer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tmr_remove
;
; Removes a timer from the chain of running timers, if it's there.
;
; Inputs:
;	ES:DI -> TMR
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	tmr_remove
	push	bx
	push	ds
	mov	ds,cs:[0].DDH_DATA
	mov	bx,offset tmr_list	; DS:BX -> first link
tr1:	mov	ax,[bx]._OFF
	cmp	ax,-1			; end of chain?
	je	tr9			; yes
	cmp	ax,di
	jne	tr2
	mov	ax,es
	cmp	[bx]._SEG,ax
	je	tr3
tr2:	lds	bx,dword ptr [bx]	; DS:BX -> next timer (and its link)
	jmp	tr1
tr3:	mov	ax,es:[di].TMR_NEXT._OFF; unlink the timer
	mov	[bx]._OFF,ax
	mov	ax,es:[di].TMR_NEXT._SEG
	mov	[bx]._SEG,ax
tr9:	pop	ds
	pop	bx
	ret
ENDPROC	tmr_remove

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; run_timers
;
; Counts down every running timer, and calls (and removes) any that expire.
;
; Inputs:
;	DS = CODE
;
; Modifies:
;	AX, BX, DX, DI, ES
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	run_timers
	mov	bx,offset tmr_list	; DS:BX -> link
rt1:	les	di,[bx]			; ES:DI -> timer, if any
	cmp	di,-1			; end of chain?
	je	rt9			; yes
	dec	es:[di].TMR_TICKS	; has it expired?
	jnz	rt2			; no
	mov	ax,es:[di].TMR_NEXT._OFF; yes, unlink it
	mov	[bx]._OFF,ax
	mov	ax,es:[di].TMR_NEXT._SEG
	mov	[bx]._SEG,ax
	push	bx
	push	cx
	push	si
	push	ds
	call	dword ptr es:[di].TMR_FUNC
	pop	ds
	pop	si
	pop	cx
	pop	bx
	jmp	rt1			; the same link is next
rt2:	mov	bx,di			; DS:BX -> this timer's link
	push	es
	pop	ds
	jmp	rt1
rt9:	mov	ds,cs:[0].DDH_DATA
	ret
ENDPROC	run_timers

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
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE

	add	[ticksToday].LW,1
	adc	[ticksToday].HW,0
;
; The maximum ticks per day (1573040) is 0018:00B0.
;
	cmp	[ticksToday].HW,18h
	jb	ddi0a			; no overflow yet
	ASSERT	Z
	ja	ddi0			; large overflow (how'd that happen?)
	cmp	[ticksToday].LW,00B0h
	jb	ddi0a
ddi0:	mov	[ticksToday].LW,0
	mov	[ticksToday].HW,0
;
; We use a DOS utility function to increment the date, since DOS already
; contains the required calendar data to properly increment a date (ie, it
; is not a device-specific operation).
;
	mov	cx,[dateYear]
	mov	dx,word ptr [dateDay]
	DOSUTIL	INCDATE
	mov	[dateYear],cx
	mov	word ptr [dateDay],dx

ddi0a:	cmp	[sndTicks],0		; is a sound playing?
	je	ddi0b			; no
	dec	[sndTicks]		; yes, has it ended?
	jnz	ddi0b			; no
	in	al,61h
	and	al,0FCh
	out	61h,al			; yes, turn the speaker off
ddi0b:	call	run_timers
	mov	bx,offset wait_ptr	; DS:BX -> ptr
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
	mov	ah,DOS_UTL_ENDWAIT
	call	far ptr DDINT_UTIL	; end the wait on DX:DI (see int_util)
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
	mov	ax,es:[di].DDP_PTR._OFF
	mov	[bx]._OFF,ax
	mov	ax,es:[di].DDP_PTR._SEG
	mov	[bx]._SEG,ax
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
	ASSERT	STRUCT,es:[bx],DDP

	mov	es:[bx].DDPI_END._OFF,offset ddclk_init
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	ds:[0].DDH_REQUEST,offset DEV:ddclk_req
;
; Start with the BIOS time of day (which an AT-class BIOS sets from its
; real-time clock) and the real-time clock's date, if any.  A PC or XT BIOS
; doesn't support TIME_GETDATE, so CX remains zero and our default date stands.
;
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is current tick count
	mov	[ticksToday].LW,dx
	mov	[ticksToday].HW,cx
	mov	ah,TIME_GETDATE
	sub	cx,cx
	int	INT_TIME		; CX = century/year, DX = month/day
	jcxz	ci1			; no real-time clock date
	mov	al,cl
	call	bcd_bin			; AX = year within century
	xchg	ax,cx			; CX = that year, AH = century (BCD)
	mov	al,ah
	call	bcd_bin			; AX = century
	mov	ah,100
	mul	ah
	add	cx,ax
	mov	[dateYear],cx
	mov	al,dh
	call	bcd_bin
	mov	[dateMonth],al
	mov	al,dl
	call	bcd_bin
	mov	[dateDay],al
	inc	[dateRTC]		; (see IOCTL_CLOCK)
ci1:
;
; Install an INT 08h hardware interrupt handler, which we will use to service
; WAIT requests, and which will also drive the DOS scheduler as soon as DOS has
; initialized and revectored DDINT_ENTER/DDINT_LEAVE.
;
	mov	al,INT_HW_TMR
	mov	cx,offset ddclk_interrupt
	mov	dx,cs
	cli
	call	far ptr DDINT_SETVEC	; DX:CX = previous vector
	mov	[tmr_int]._OFF,cx
	mov	[tmr_int]._SEG,dx
	sti

	ret
ENDPROC	ddclk_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; bcd_bin
;
; Inputs:
;	AL = BCD value (0-99)
;
; Outputs:
;	AX = binary value
;
DEFPROC	bcd_bin
	push	cx
	mov	cl,4
	mov	ah,al
	shr	ah,cl			; AH = tens digit
	and	al,0Fh			; AL = ones digit
	aad				; AX = AH * 10 + AL
	pop	cx
	ret
ENDPROC	bcd_bin

CODE	ends

DATA	segment para public 'DATA'

ddclk_end	db	16 dup(0)

DATA	ends

	end
