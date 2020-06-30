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

	cmp	al,IOCTL_WAIT
	jne	dci9
;
; For WAIT requests, we add this packet to an internal chain of "waiting"
; packets, and then tell DOS that we're waiting; DOS will suspend the current
; SCB until we notify DOS that this packet's conditions are satisfied.
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
	mov	bx,offset wait_ptr	; DS:BX -> ptr
	les	di,[bx]			; ES:DI -> packet, if any
	ASSUME	ES:NOTHING
	sti

ddi1:	cmp	di,-1			; end of chain?
	je	ddi9			; yes

	ASSERT_STRUC es:[di],DDP
;
; We wait for the double-word decrement to underflow (ie, to go from 0 to -1)
; since that's the simplest to detect.  And while you might think that means we
; always wait 1 tick longer than requested -- well, sort of.  We have no idea
; how much time elapsed between the request's arrival and the first tick; that
; time could be almost zero, so think of the tick count as "full" ticks.
;
	sub	es:[di].DDPRW_OFFSET,1
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
	mov	es:[di].DDPRW_OFFSET,0
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

	mov	es:[bx].DDPI_END.OFF,offset ddclk_init
	mov	cs:[0].DDH_REQUEST,offset DEV:ddclk_req
;
; Install an INT 08h hardware interrupt handler, which we will use to drive
; calls to DOS_UTL_YIELD as soon as DOS tells us it's ready (which it will do
; by setting the DDATTR_CLOCK bit in our header).
;
	cli
	mov	ax,offset ddclk_interrupt
	xchg	ds:[INT_HW_TMR * 4].OFF,ax
	mov	[tmr_int].OFF,ax
	mov	ax,cs
	xchg	ds:[INT_HW_TMR * 4].SEG,ax
	mov	[tmr_int].SEG,ax
	sti

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
