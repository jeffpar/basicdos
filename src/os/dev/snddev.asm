;
; BASIC-DOS Sound (SND$) Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; SND$ owns a Sound Blaster, which it finds at boot (at 220h or 240h, with
; the card's usual IRQ, 7, and DMA channel, 1), and lends it to one V86
; machine at a time (see snd.inc): CPU$ gives the machine the card's ports
; and the FM synthesizer's (at 388h), SND$ counts the card's interrupts for
; the machine's host to give the machine, and it keeps a virtual DMA
; controller for the machine, programming the real one for the card's
; channel only, with the machine's addresses translated to physical ones.
; When the handle that borrowed the card closes, the card is reset, its
; channel and IRQ are masked again, its FM voices are silenced, and the
; machine gives back the ports.  Without an 80386 (which V86 machines need)
; or a card, the driver isn't installed.
;
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	cpu.inc
	include	snd.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	SND
SND	DDH	<offset DEV:ddsnd_end+16,,DDATTR_OPEN+DDATTR_CHAR,offset ddsnd_init,-1,2020202024444E53h>

SB_IRQ		equ	7	; the card's usual IRQ
SB_DMA		equ	1	; and DMA channel
SB_PAGE		equ	83h	; and that channel's page register
SB_PORTS	equ	16	; the card's ports (from its base port)
FM_PORT		equ	388h	; the FM synthesizer's ports
FM_PORTS	equ	8
DMAR_MASK	equ	0Ah	; DMA controller: single mask register
DMAR_MODE	equ	0Bh	; mode register
DMAR_CLEARFF	equ	0Ch	; clear flip-flop register

	DEFWORD	sb_port,0	; the card's base port
	DEFWORD	holder,0	; context of the open that has the card
	DEFWORD	next_ctx,0	; the last context given out (see ddsnd_req)
	DEFWORD	mach_sel,0	; the machine that has the card
	DEFWORD	low_sel,0	; a selector for its 500h-5FFh
	DEFWORD	dma_addr,0	; virtual DMA controller: the channel's address
	DEFWORD	dma_count,0	; and count
	DEFWORD	dma_latch,0	; (a register whose bytes are being read)
	DEFBYTE	dma_page,0	; the channel's page
	DEFBYTE	dma_mode,0	; and mode
	DEFBYTE	dma_ff,0	; flip-flop (zero if a low byte is next)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Each open gets a context of its own (never zero), so that only the close
; of the one that borrowed the card gives it back, and only it can program
; the card's DMA channel.
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;	DDP updated
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddsnd_req,far
	mov	di,bx			; ES:DI -> DDP
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	ax,DDSTAT_DONE
	mov	bp,es:[di].DDP_CONTEXT	; BP = context
	mov	cl,es:[di].DDP_CMD
	cmp	cl,DDC_OPEN
	jne	dr1
	inc	[next_ctx]
	jnz	dr0
	inc	[next_ctx]		; (skip zero)
dr0:	mov	dx,[next_ctx]
	jmp	short dr8
dr1:	cmp	cl,DDC_CLOSE
	jne	dr2
	cmp	bp,[holder]		; the one that borrowed the card?
	jne	dr9			; no
	call	snd_return		; yes, so it comes back
	jmp	short dr9a
dr2:	cmp	cl,DDC_IOCTLIN
	jne	dr9			; no other request does anything
	mov	cx,es:[di].DDPRW_LENGTH	; CX = IOCTL input value
	mov	dx,es:[di].DDPRW_LBA	; DX = IOCTL input value
	mov	bl,es:[di].DDP_CODE
	push	es
	push	di
	cmp	bl,IOCTL_SNDLEND
	jne	dr3
	call	snd_lend
	jmp	short dr4
dr3:	cmp	bl,IOCTL_SNDDMA
	stc
	jne	dr4
	cmp	bp,[holder]		; does this open have the card?
	stc
	jne	dr4			; no
	call	dma_io
	clc
dr4:	pop	di
	pop	es
	mov	ax,DDSTAT_ERROR + DDERR_GENFAIL
	jc	dr9
	mov	ax,DDSTAT_DONE
dr8:	mov	es:[di].DDP_CONTEXT,dx	; return the context (or DX)
dr9:	mov	es:[di].DDP_STATUS,ax
	ret
dr9a:	mov	ax,DDSTAT_DONE
	jmp	dr9
ENDPROC	ddsnd_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; snd_lend (IOCTL_SNDLEND)
;
; Lends the card to a machine (unless another has it): CPU$ gives the machine
; the card's ports and the FM synthesizer's, and a selector for its 500h-5FFh
; lets ddsnd_irq count the card's interrupts there (at SND_IRQS), which the
; card's IRQ (unmasked now) delivers.
;
; Inputs:
;	DX = the machine's first selector, BP = context
;
; Outputs:
;	Carry clear if successful: DL = IRQ, DH = DMA channel
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	snd_lend
	cmp	[holder],0		; does another machine have it?
	stc
	jne	sl9			; yes
	mov	[mach_sel],dx
	mov	bx,dx
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_SEL
	call	far ptr DDINT_CPU	; DX:CX = its memory's address
	jc	sl9
	add	cx,SND_IRQS AND 0FF00h
	adc	dx,0			; DX:CX = its 500h
	sub	si,si
	mov	di,100h			; SI:DI = length
	mov	ax,CPU_MAP SHL 8	; (a GDT data selector)
	call	far ptr DDINT_CPU	; AX = selector
	jc	sl9
	mov	[low_sel],ax
	mov	[holder],bp		; (so snd_return can undo the rest)
	mov	es,ax
	mov	byte ptr es:[SND_IRQS AND 0FFh],0
	mov	[dma_ff],0
	mov	al,4			; lend
	call	snd_ports
	jc	sl8
	cli
	in	al,21h
	and	al,NOT (1 SHL SB_IRQ)
	out	21h,al			; unmask the card's IRQ
	sti
	mov	dx,(SB_DMA SHL 8) OR SB_IRQ	; (and carry is clear)
	ret
sl8:	call	snd_return
	stc
sl9:	ret
ENDPROC	snd_lend

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; snd_return
;
; The card comes back from the machine (see snd_lend): its DMA channel and
; IRQ are masked, the DSP is reset (which stops it), the FM synthesizer's
; voices are turned off, and the machine gives back the ports.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	snd_return
	cli
	mov	al,SB_DMA OR 4
	out	DMAR_MASK,al		; mask the card's DMA channel
	in	al,21h
	or	al,1 SHL SB_IRQ
	out	21h,al			; and its IRQ
	sti
	mov	dx,[sb_port]
	call	dsp_reset
	call	fm_off
	mov	al,5			; take them back
	call	snd_ports
	mov	bx,[low_sel]
	sub	cx,cx			; (one selector)
	mov	ah,CPU_UNMAP
	call	far ptr DDINT_CPU
	mov	[holder],0
	ret
ENDPROC	snd_return

;
; fm_off turns off the FM synthesizer's voices (registers B0h-B8h) and its
; rhythm instruments (BDh); fm_zero writes zero to FM synthesizer register
; BL, with the delays (reading its status port) that it needs after the
; register number and the value.
;
DEFPROC	fm_off
	mov	bl,0B0h
fo1:	call	fm_zero
	inc	bx
	cmp	bl,0B9h
	jb	fo1
	mov	bl,0BDh
ENDPROC	fm_off				; fall into fm_zero

DEFPROC	fm_zero
	mov	dx,FM_PORT
	mov	al,bl
	out	dx,al
	mov	cx,6
	call	snd_wait
	inc	dx
	mov	al,0
	out	dx,al
	dec	dx
	mov	cx,35
	jmp	snd_wait
ENDPROC	fm_zero

;
; snd_ports lends the card's ports and the FM synthesizer's to the machine
; (AL = 4), or takes them back (AL = 5), and CPU$ calls snd_note when the
; machine is suspended or resumes.  CPU$ doesn't preserve ES, so ES:DI is set
; for each call (see sp1).
;
DEFPROC	snd_ports
	push	es
	mov	bx,[mach_sel]
	mov	cx,[sb_port]
	mov	dx,SB_PORTS
	call	sp1
	jc	sp9
	mov	cx,FM_PORT
	mov	dx,FM_PORTS
	call	sp1
sp9:	pop	es
	ret
sp1:	push	cs
	pop	es
	mov	di,offset snd_note	; ES:DI -> snd_note
	push	ax
	mov	ah,CPU_V86
	call	far ptr DDINT_CPU
	pop	ax
	ret
ENDPROC	snd_ports

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; snd_note
;
; CPU$ calls this (with interrupts off) when the machine that has the card is
; suspended (AL = 0), eg, while its console is hidden, or resumes (AL = 1):
; a DMA transfer in progress is paused (DSP command D0h) and continued (D4h),
; and the FM synthesizer's voices are turned off, since its registers can't
; be read (so a held note stops until the music's next one).
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	snd_note,far
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	ah,0D4h			; continue DMA
	test	al,al			; resumes?
	jnz	sn1			; yes
	call	fm_off
	mov	ah,0D0h			; pause DMA
sn1:	mov	dx,[sb_port]
	add	dl,0Ch			; DX = the card's write port
	mov	cx,1000
sn2:	in	al,dx
	test	al,80h			; ready for a command?
	loopnz	sn2			; not yet
	mov	al,ah
	out	dx,al
	pop	ds
	ret
ENDPROC	snd_note

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsp_reset and snd_wait
;
; dsp_reset resets the DSP of a card at port DX, which answers AAh when it's
; ready again (carry clear), or carry set if it doesn't; snd_wait reads the
; port DX CX times (about a microsecond each), as a delay.
;
; Modifies:
;	AX, CX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	dsp_reset
	push	dx
	add	dx,6			; DX = the card's reset port
	mov	al,1
	out	dx,al
	mov	cx,8
	call	snd_wait		; (at least 3 microseconds)
	mov	al,0
	out	dx,al
	add	dx,8			; DX = the card's data available port
	mov	cx,1000
dsr1:	in	al,dx
	test	al,80h			; any data?
	jnz	dsr2			; yes
	loop	dsr1
	stc
	jmp	short dsr9
dsr2:	sub	dx,4			; DX = the card's read data port
	in	al,dx
	cmp	al,0AAh			; ready? (carry clear if so)
	je	dsr9
	stc
dsr9:	pop	dx
	ret
ENDPROC	dsp_reset

DEFPROC	snd_wait
	in	al,dx
	loop	snd_wait
	ret
ENDPROC	snd_wait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddsnd_irq (the card's hardware interrupt handler)
;
; While a machine has the card, each of its interrupts is counted for the
; machine (at SND_IRQS, which its host gives it; see snd.inc), and the
; machine's own handler acknowledges the card; the interrupt controller is
; told that it's done now.  An interrupt that the controller doesn't say is
; in service is a spurious one, which gets no end of interrupt.
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddsnd_irq,far
	push	ax
	mov	al,0Bh
	out	20h,al
	in	al,20h			; AL = in-service register
	test	al,1 SHL SB_IRQ		; is it in service?
	jz	irq9			; no
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	cmp	[holder],0		; does a machine have the card?
	je	irq8			; no
	mov	ds,[low_sel]
	ASSUME	DS:NOTHING
	inc	byte ptr ds:[SND_IRQS AND 0FFh]
	jnz	irq8
	dec	byte ptr ds:[SND_IRQS AND 0FFh]	; (at most FFh)
irq8:	pop	ds
	mov	al,20h
	out	20h,al			; end of interrupt
irq9:	pop	ax
	iret
ENDPROC	ddsnd_irq

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dma_io (IOCTL_SNDDMA)
;
; The machine's virtual DMA controller (the first one, with channels 0-3):
; the card's channel has an address, count, page, and mode of its own, and
; when the machine unmasks it, the real channel is programmed with them, with
; the address translated to a physical one (as long as all of the transfer is
; in the machine's memory, and doesn't cross a 64K boundary, which it can't
; on the machine either, since each 64K of its memory is a 64K of physical
; memory; see CPU_V86), or else it stays masked.  Reading the channel's
; address or count reads the real one (the low 16 bits of a physical address
; are the same as the machine's),
; and the status register has the channel's bits of the real one.  The other
; channels' registers read as zero, and writing them does nothing, but the
; flip-flop works for all of them.
;
; Inputs:
;	CL = port (00h-0Fh, or 80h-8Fh), CH = 0 for IN, 1 for OUT, DL = byte
;
; Outputs:
;	DL = byte (IN)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	dma_io
	mov	al,dl			; AL = byte (OUT)
	cmp	cl,SB_PAGE		; the channel's page register?
	jne	dm1			; no
	test	ch,ch			; OUT?
	jz	dm0			; no
	mov	[dma_page],al
	ret
dm0:	mov	dl,[dma_page]
	ret
dm1:	cmp	cl,DMAR_MASK - 2		; an address or count register?
	jae	dm5			; no
;
; An address or count register (of channel port / 2), whose bytes are read
; or written in turn, as the flip-flop says.
;
	mov	bl,cl
	shr	bl,1			; BL = channel
	mov	si,offset dma_addr
	test	cl,1			; a count register?
	jz	dm2			; no
	mov	si,offset dma_count
dm2:	mov	ah,[dma_ff]
	xor	[dma_ff],1
	cmp	bl,SB_DMA		; the card's channel?
	jne	dm8			; no
	mov	bl,ah
	mov	bh,0			; BX = which byte
	test	ch,ch			; OUT?
	jz	dm3			; no
	mov	[si+bx],al
	ret
dm3:	test	bl,bl			; the low byte?
	jnz	dm4			; no
	cli
	out	DMAR_CLEARFF,al
	mov	dl,cl
	mov	dh,0
	in	al,dx
	mov	ah,al
	in	al,dx
	sti
	xchg	al,ah			; AX = the real register
	mov	[dma_latch],ax
dm4:	mov	dl,byte ptr [dma_latch+bx]
	ret
;
; The controller's own registers (08h-0Fh, 08h and 09h being a command and
; a request, which do nothing).
;
dm5:	test	ch,ch			; OUT?
	jnz	dm6			; yes
	cmp	cl,DMAR_MASK - 2		; the status register?
	jne	dm8			; no (that's the temporary register)
	in	al,DMAR_MASK - 2
	and	al,(11h SHL SB_DMA)	; the card's channel's bits
	mov	dl,al
	ret
dm6:	sub	cl,DMAR_MASK
	jb	dm9			; a command or a request
	je	dm7			; a channel's mask bit
	dec	cl
	jz	dm6a			; a channel's mode
	dec	cl
	jz	dm6c			; clear the flip-flop
	dec	cl
	jz	dm6b			; master clear
	dec	cl
	jz	dma_on			; clear every mask bit
	test	al,1 SHL SB_DMA		; every mask bit (the card's)
	jmp	short dm7b
dm6a:	mov	ah,al
	and	ah,3
	cmp	ah,SB_DMA		; the card's channel's mode?
	jne	dm9			; no
	mov	[dma_mode],al
	ret
dm6b:	mov	al,SB_DMA OR 4		; (master clear masks every channel)
	out	DMAR_MASK,al
dm6c:	mov	[dma_ff],0
	ret
dm7:	mov	ah,al
	and	ah,3
	cmp	ah,SB_DMA		; the card's channel's mask bit?
	jne	dm9			; no
	test	al,4			; masked?
dm7b:	jz	dma_on			; no
	mov	al,SB_DMA OR 4
	out	DMAR_MASK,al
	ret
dm8:	mov	dl,0			; (zero for an IN)
dm9:	ret
;
; Unmasking the card's channel programs the real one, if the transfer is all
; in pages of the machine's memory that are there, and physically consecutive
; (whose limit CPU_SEGINFO reports, with ADDR_V86 and ADDR_PHYS), and doesn't
; cross a 64K boundary; otherwise, it stays masked.
;
dma_on:	mov	al,[dma_page]
	cmp	al,10h			; below 1Mb?
	jae	dn9			; no
	mov	bx,[dma_addr]
	mov	si,bx
	and	si,0Fh			; SI = offset in its segment
	mov	cl,4
	shr	bx,cl
	mov	ah,al
	mov	al,0
	shl	ax,cl
	or	bx,ax			; BX = segment
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_V86 OR ADDR_PHYS
	call	far ptr DDINT_CPU	; DX:CX = address, AX = limit
	jc	dn9
	mov	di,[dma_count]
	add	di,si			; DI = offset of the last byte
	jc	dn9
	cmp	di,ax			; is it in the machine's memory?
	ja	dn9			; no
	add	cx,si
	adc	dx,0			; DX:CX = physical address
	test	dh,dh			; below 16Mb?
	jnz	dn9			; no
	mov	ax,cx
	add	ax,[dma_count]		; does it cross a 64K boundary?
	jc	dn9			; yes
	cli
	mov	al,SB_DMA OR 4
	out	DMAR_MASK,al
	out	DMAR_CLEARFF,al
	mov	al,[dma_mode]
	and	al,NOT 3
	or	al,SB_DMA
	out	DMAR_MODE,al
	mov	al,cl
	out	SB_DMA * 2,al
	mov	al,ch
	out	SB_DMA * 2,al		; the address
	mov	ax,[dma_count]
	out	SB_DMA * 2 + 1,al
	mov	al,ah
	out	SB_DMA * 2 + 1,al	; the count
	mov	al,dl
	out	SB_PAGE,al		; the page
	mov	al,SB_DMA
	out	DMAR_MASK,al		; and unmask it
	sti
dn9:	ret
ENDPROC	dma_io

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; The driver is installed only on an 80386 (where CPU$ can have V86 machines)
; with a Sound Blaster at 220h or 240h, whose IRQ handler it installs (the
; IRQ stays masked until a machine borrows the card); otherwise, DDPI_END
; remains zero.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddsnd_init,far
	push	bx
	push	es
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	cmp	[CPU_TYPE],CPUTYPE_80386	; can there be V86 machines?
	jb	in9			; no
	mov	dx,220h
in1:	call	dsp_reset		; is there a card at port DX?
	jnc	in2			; yes
	add	dl,20h
	cmp	dl,40h			; (220h and 240h)
	jbe	in1
	jmp	short in9		; no card, so DDPI_END stays zero
in2:	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	[sb_port],dx
	mov	al,INT_HW_TMR + SB_IRQ	; (its vector in real mode)
	mov	cx,offset ddsnd_irq
	mov	dx,cs
	call	far ptr DDINT_SETVEC
	pop	es
	pop	bx
	mov	es:[bx].DDPI_END._OFF,offset ddsnd_init
	mov	ds:[0].DDH_REQUEST,offset DEV:ddsnd_req
	ret
in9:	pop	es
	pop	bx
	ret
ENDPROC	ddsnd_init

CODE	ends

DATA	segment para public 'DATA'

ddsnd_end	db	16 dup(0)

DATA	ends

	end
