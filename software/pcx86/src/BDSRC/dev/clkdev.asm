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

	DEFPTR	timer_interrupt,0	; timer interrupt handler
	DEFPTR	wait_ptr,-1		; chain of waiting packets
	DEFBYTE	dos_ready,0		; set once DOS is ready

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp
	push	ds
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
	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	ddclk_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
;	AX, DX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddclk_ctlin
	mov	al,es:[di].DDP_UNIT
	cmp	al,CLKIO_WAIT
	jne	dci9
;
; Our interrupt handler needs to know when DOS has been initialized, so
; sysinit issues a WAIT request for zero ticks (which we treat as a no-op)
; to signal that it's ready.
;
	mov	[dos_ready],al
	mov	ax,es:[di].DDPRW_OFFSET
	or	ax,es:[di].DDPRW_LENGTH
	jz	dci9
;
; For WAIT requests, we add this packet to an internal chain of "waiting"
; packets, and then tell DOS that we're waiting; DOS will suspend the current
; SCB until we notify DOS that this packet's conditions are satisified.
;
	cli
	mov	ax,di
	xchg	[wait_ptr].off,ax
	mov	es:[di].DDP_PTR.off,ax
	mov	ax,es
	xchg	[wait_ptr].seg,ax
	mov	es:[di].DDP_PTR.seg,ax
	sti
;
; The WAIT condition is satisified when the packet's LENGTH:OFFSET pair (which
; should contain a standard CX:DX tick count) has been decremented to zero.
;
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	mov	ax,DOS_UTIL_WAIT
	int	21h

dci9:	ret
ENDPROC	ddclk_ctlin

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddclk_interrupt (hardware interrupt handler)
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
	pushf
	call	[timer_interrupt]
	cmp	[dos_ready],1
	jb	ddi9
	push	ax
	push	bx
	push	dx
	push	di
	push	ds
	push	es
	mov	ax,cs
	mov	es,ax
	ASSUME	ES:CODE
	mov	bx,offset wait_ptr	; ES:BX -> ptr
	lds	di,es:[bx]		; DS:DI -> packet, if any
	ASSUME	DS:NOTHING
	sti

ddi1:	cmp	di,-1			; end of chain?
	je	ddi8			; yes

	ASSERT_STRUC [di],DDP
;
; We wait for the double-word decrement to underflow (ie, to go from 0 to -1)
; since that's the simplest to detect.  And while you might think that means we
; always wait 1 tick longer than requested -- well, sort of.  We have no idea
; how much time elapsed between the request being made and the first tick; that
; time could be almost zero, so think of the tick count as "full" ticks.
;
	sub	[di].DDPRW_OFFSET,1
	sbb	[di].DDPRW_LENGTH,0
	jae	ddi6			; keep waiting
;
; Notify DOS that the SCB associated with this packet is done waiting.
;
ddi2:	mov	dx,ds			; DX:DI -> packet (aka "wait ID")
	mov	ax,DOS_UTIL_ENDWAIT
	int	21h
	jnc	ddi3
;
; If ENDWAIT returns an error, we presume that we simply got ahead of the
; WAIT call, so rewind the count to zero and leave the packet on the list.
;
	mov	[di].DDPRW_OFFSET,0
	mov	[di].DDPRW_LENGTH,0
	jmp	short ddi6
;
; WAIT condition has been satisfied, remove packet from wait_ptr list.
;
ddi3:	mov	ax,[di].DDP_PTR.off
	mov	es:[bx].off,ax
	mov	ax,[di].DDP_PTR.seg
	mov	es:[bx].seg,ax
	jmp	short ddi7

ddi6:	lea	bx,[di].DDP_PTR		; update prev addr ptr in ES:BX
	push	ds
	pop	es

ddi7:	lds	di,[di].DDP_PTR
	jmp	ddi1

ddi8:	mov	ax,DOS_UTIL_YIELD	; allow rescheduling to occur now
	int	21h
	pop	es
	pop	ds
	pop	di
	pop	dx
	pop	bx
	pop	ax
ddi9:	iret
ENDPROC	ddclk_interrupt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	push	ax
	push	dx
	push	ds
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS

	ASSERT_STRUC es:[bx],DDP

	mov	es:[bx].DDPI_END.off,offset ddclk_init
	mov	cs:[0].DDH_REQUEST,offset DEV:ddclk_req
;
; Install an INT 08h hardware interrupt handler
;
	mov	ax,offset ddclk_interrupt
	xchg	ds:[INT_HW_TMR * 4].off,ax
	mov	[timer_interrupt].off,ax
	mov	ax,cs
	xchg	ds:[INT_HW_TMR * 4].seg,ax
	mov	[timer_interrupt].seg,ax

	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	pop	ax
	ret
ENDPROC	ddclk_init

CODE	ends

DATA	segment para public 'DATA'

ddclk_end	db	16 dup(0)

DATA	ends

	end
