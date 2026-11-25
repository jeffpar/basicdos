;
; BASIC-DOS V86 Utility: Interrupts and I/O Ports
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The machine has no hardware of its own, so what its programs expect of it
; is done here: its timer and keyboard interrupts (INT 08h and 09h), and a
; sound card's, which it gets when it exits after one of the system's
; interrupts (see tick), and the I/O ports in IO_TABLE, each of which has a
; handler for the machine's INs and OUTs (see do_io), including the DMA
; controller's, which SND$ does.  The only ports that the machine uses itself
; are an EGA or VGA's, while its console is in a graphics mode, and a sound
; card's, if SND$ lent it one (see snd_lend and CPU_V86).
;
	BIOSKEY equ 1
	include	v86host.inc

CODE    SEGMENT word public 'CODE'

	EXTBYTE	<VARS>
	EXTNEAR	<run,fault,seg_ptr,push_word,pop_word,pop_ret,set_keys>
	EXTNEAR	<pft_load>
	EXTWORD	<machine>

	.286c

        ASSUME  CS:CODE, DS:CODE, ES:NOTHING, SS:CODE
;
; IO_TABLE has an IOENT for each range of ports.  A handler gets the port in
; DX, which of the range's ports it is in CX, the opcode in BL (bit 1 is set
; for OUT), and for OUT, the byte in AL; it returns with carry clear, and for
; IN, the byte in AL, and it can change only AL, CX, SI, and DI.
;
IOENT		struc
IO_PORT		dw	?	; first port
IO_NUM		dw	?	; number of ports
IO_PROC		dw	?	; handler
IOENT		ends

	DEFLBL	IO_TABLE,word
	IOENT	<00h,10h,io_dma>	; DMA controller
	IOENT	<40h,4,io_pit>		; timer
	IOENT	<60h,5,io_kbd>		; keyboard (and speaker)
	IOENT	<80h,10h,io_dma>	; DMA page registers
	IOENT	<210h,60h,io_none>	; sound cards (eg, a Sound Blaster)
	IOENT	<278h,3,io_none>	; parallel ports
	IOENT	<378h,3,io_none>
	IOENT	<388h,2,io_none>	; sound card (FM synthesizer)
	IOENT	<3BCh,3,io_none>	; (and the third parallel port)
	DEFLBL	IO_END,word

PIT_MIN		equ	400h	; smallest timer divisor (about 1165 Hz)
TICKS_MAX	equ	64	; most ticks that the machine can be owed
VQ_TICKS	equ	16	; most ticks to give it at once (see virq)
VQ_SNDS		equ	2	; and sound card interrupts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tick
;
; The machine exited after one of the system's interrupts (V86X_TICK), so
; unless its interrupts are off, it gets any interrupts of its own that it's
; due now (see virq).  After a timer tick (VR_VEC = 08h), the tick count in
; its BIOS data becomes the system's (rather than counting its own ticks,
; which it misses while its interrupts are off, or while a DOS call waits),
; and it's owed as many ticks of its own as its timer would have made since
; the last one (one, unless a program has set the timer's divisor; see
; io_pit).
;
; A program whose INT 09h handler didn't pass the last interrupt on (see
; do_int) doesn't want its keys read, either, so the console's are discarded
; (otherwise, the system's keyboard buffer would fill).
;
DEFPROC	tick
	cmp	byte ptr [VARS+VR_VEC],INT_HW_TMR	; a timer tick?
	jne	tk3			; no
	sub	ax,ax
	mov	di,BIOS_DATA + offset TIMER_LOW
	call	seg_ptr			; ES:DI -> the machine's tick count
	DOSUTIL	GETTIME,1		; DX:AX = BIOS tick count
	stosw
	xchg	ax,dx
	stosw
	mov	ax,1			; (one tick)
	mov	cx,[pit_div]
	jcxz	tk1			; the timer's divisor is 65536
	cwd
	xchg	ax,dx
	mov	ax,[pit_acc]		; DX:AX = 65536 + what was left over
	div	cx			; AX = ticks
	mov	[pit_acc],dx
tk1:	add	al,[pit_owed]
	cmp	al,TICKS_MAX
	jbe	tk2
	mov	al,TICKS_MAX
tk2:	mov	[pit_owed],al
	cmp	[kbd_sent],0		; did a handler keep an interrupt?
	je	tk3			; no
	mov	[kbd_sent],0
	call	pft_load
	mov	cl,3
	call	set_keys		; (so that CTRL-C is only a key)
	mov	ax,DOS_TTY_FLUSH SHL 8
	int	21h
	mov	cl,2
	call	set_keys
tk3:	mov	[kbd_done],0
	mov	bl,1			; (the first interrupt)
	test	byte ptr [VARS+VR_EFL+1],FL_INTS SHR 8
	jnz	virq
	jmp	run			; its interrupts are off
ENDPROC	tick

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; virq and virq_ret
;
; Gives the machine the interrupts that it's due, as real mode would (each
; one with its FLAGS, CS, and IP pushed, and IF and TF cleared), in this
; order: an INT 09h for the next scan code in the console's queue (see
; KQ_HEAD), which port 60h then reads (see io_kbd); the interrupts from its
; sound card that SND$ counted (at SND_IRQS), up to VQ_SNDS; and an INT 08h
; for each tick that it's owed, up to VQ_TICKS (the rest wait for the next
; exit).  Interrupts whose vectors are still the defaults are discarded
; instead (the system's handlers are all they need), except for the timer's
; (its default handler is code in the machine; see STUB_TICK).  It gets only
; one scan code for each of the system's interrupts (after any prefixes), so
; that a key's release never follows its press at once, which a program that
; looks for keys that are down would miss.
;
; The machine runs the first handler, whose IRET "returns" to the next one
; (as if that interrupt had arrived as it returned), and so on, until the
; last one returns to where the machine was interrupted, so the handlers need
; no exits.  The exception is a scan code prefix with another code after it:
; its handler returns to STUB_VIRQ instead, which is a HLT, so the machine
; exits (see run), and virq_ret gives it the next code.
;
; Inputs:
;	BL = nonzero for the first interrupt, zero for virq_ret (whose
;	interrupted frame is on the machine's stack already)
;
DEFPROC	virq_ret
	mov	bl,0
	DEFLBL	virq,near
	sub	ax,ax
	sub	di,di
	call	seg_ptr			; ES:DI -> the machine's first 32K
	mov	bp,di
	mov	si,offset VARS + V_BUF	; SI -> the list of handlers to run
	mov	bh,0			; BH = 1 if it must exit after them
	cmp	[kbd_done],0		; has it had this tick's scan code?
	jne	vq2			; yes
	mov	ax,word ptr es:[bp+KQ_HEAD]	; AL = head, AH = tail
	cmp	al,ah			; any scan codes?
	je	vq2			; no
	mov	di,INT_HW_KBD * 4
	cmp	es:[bp+di]._SEG,STUB_SEG
	jne	vq1			; a program has a handler
	mov	es:[bp+KQ_HEAD],ah	; no handler, so discard them
	jmp	short vq2
vq1:	mov	di,ax
	and	di,0FFh
	mov	cl,es:[bp+di+KQ_CODES]
	mov	[kbd_data],cl
	inc	ax
	cmp	al,KQ_MAX
	jb	vq1a
	mov	al,0
vq1a:	mov	es:[bp+KQ_HEAD],al
	mov	[kbd_sent],1
	mov	di,INT_HW_KBD * 4
	push	ax
	call	vq_add
	pop	ax
	cmp	cl,0E0h			; a prefix (E0h or E1h)?
	jae	vq1b			; yes
	inc	[kbd_done]
	jmp	short vq2
vq1b:	cmp	al,ah			; does another code follow it?
	je	vq2			; no
	inc	bh			; yes, so it exits after this one
	jmp	short vq4
vq2:	mov	al,[snd_vec]
	test	al,al			; does it have a sound card?
	jz	vq3			; no
	mov	ah,0
	shl	ax,1
	shl	ax,1
	xchg	di,ax			; DI -> its vector
	mov	cx,VQ_SNDS
vq2a:	cmp	byte ptr es:[bp+SND_IRQS],0	; any interrupts from it?
	je	vq3			; no
	cmp	es:[bp+di]._SEG,STUB_SEG
	jne	vq2b			; a program has a handler
	mov	byte ptr es:[bp+SND_IRQS],0	; no handler, so discard them
	jmp	short vq3
vq2b:	dec	byte ptr es:[bp+SND_IRQS]
	call	vq_add
	loop	vq2a
vq3:	mov	cl,[pit_owed]
	cmp	cl,VQ_TICKS
	jbe	vq3a
	mov	cl,VQ_TICKS
vq3a:	sub	[pit_owed],cl
	mov	ch,0
	jcxz	vq4			; no ticks
	mov	di,INT_HW_TMR * 4
vq3b:	call	vq_add
	loop	vq3b
;
; Push the frames: the interrupted one (unless it's there already), then the
; one that returns to STUB_VIRQ (if it must exit), and then one for each
; handler after the first, from the last to the second.
;
vq4:	sub	si,offset VARS + V_BUF	; SI = the list's length
	jnz	vq5
	test	bl,bl			; nothing to give it; the first time?
	jnz	vq9			; yes, so it goes on
	call	pop_ret			; no, so it returns to where it was
	call	pop_word
	mov	word ptr [VARS+VR_EFL],ax
	jmp	short vq9
vq5:	mov	dx,word ptr [VARS+VR_EFL]	; DX = FLAGS
	test	bl,bl			; the first time?
	jz	vq6			; no
	mov	ax,dx
	call	push_word
	mov	ax,word ptr [VARS+VR_CS]
	call	push_word
	mov	ax,word ptr [VARS+VR_EIP]
	call	push_word
vq6:	and	dx,NOT (FL_INTS OR FL_TRAP)	; DX = the handlers' FLAGS
	test	bh,bh			; must it exit after them?
	jz	vq7			; no
	mov	ax,dx
	call	push_word
	mov	ax,STUB_SEG
	call	push_word
	mov	ax,STUB_VIRQ
	call	push_word
vq7:	sub	si,4			; SI -> the next handler (from the end)
	jz	vq8			; (the first one runs now)
	mov	ax,dx
	call	push_word
	mov	ax,word ptr [VARS+V_BUF+si+2]
	call	push_word
	mov	ax,word ptr [VARS+V_BUF+si]
	call	push_word
	jmp	vq7
vq8:	mov	ax,word ptr [VARS+V_BUF]
	mov	word ptr [VARS+VR_EIP],ax
	mov	ax,word ptr [VARS+V_BUF+2]
	mov	word ptr [VARS+VR_CS],ax
	mov	word ptr [VARS+VR_EFL],dx
vq9:	jmp	run
;
; vq_add adds the handler at vector ES:[BP+DI] to the list at SI.
;
vq_add:	mov	ax,es:[bp+di]._OFF
	mov	[si],ax
	mov	ax,es:[bp+di]._SEG
	mov	[si+2],ax
	add	si,4
	ret
ENDPROC	virq_ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; do_io
;
; The machine exited at an IN or OUT (V86X_IO): the port's handler does it
; (or for a word, that port's handler and then the next port's, with the
; high byte, as two byte-wide ports would), and the machine runs again.  If
; either port has no handler, it's a fault at the instruction, which is one
; byte if the port was in DX (bit 3 of the opcode), and two if not.
;
DEFPROC	do_io
	mov	dx,word ptr [VARS+VR_ERR]	; DX = port
	mov	bx,word ptr [VARS+VR_ERR+2]	; BL = opcode
	mov	ax,word ptr [VARS+VR_EAX]
	call	io_byte
	jc	io8
	test	bl,1			; a word?
	jz	io1			; no
	xchg	al,ah
	inc	dx
	call	io_byte
	xchg	al,ah
	jc	io8
io1:	test	bl,2			; OUT?
	jnz	io2			; yes
	mov	word ptr [VARS+VR_EAX],ax
io2:	jmp	run
io8:	mov	ax,1
	test	bl,08h
	jnz	io9
	inc	ax
io9:	sub	word ptr [VARS+VR_EIP],ax
	mov	ax,INT_GP
	jmp	fault
ENDPROC	do_io

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; io_byte
;
; Calls a port's handler (see IO_TABLE).
;
; Inputs:
;	DX = port, BL = opcode, AL = byte (OUT)
;
; Outputs:
;	Carry clear if the port has a handler (IN: AL = byte), set if not
;
; Modifies:
;	AL, CX, SI, DI
;
DEFPROC	io_byte
	mov	si,offset IO_TABLE
ib1:	mov	cx,dx
	sub	cx,[si].IO_PORT		; CX = which of the range's ports
	cmp	cx,[si].IO_NUM		; is it one of them?
	jb	ib2			; yes
	add	si,size IOENT
	cmp	si,offset IO_END
	jb	ib1
	stc
	ret
ib2:	jmp	[si].IO_PROC
ENDPROC	io_byte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; snd_lend
;
; Borrows a sound card for the machine, if SND$ has one (see snd.inc): our
; handle for SND$ becomes our last handle, which the machine's programs don't
; get (see pft_load and psp_build), so that DOS closes it when we end (even
; if we're killed), which gives the card back.  The card's interrupts are
; the machine's (see virq), and its DMA controller's ports go to SND$ (see
; io_dma).
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	snd_lend
	mov	dx,offset SND_NAME
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jc	sl9			; no SND$
	xchg	bx,ax			; BX = handle
	mov	dx,[machine]
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_SNDLEND
	int	21h			; DL = IRQ
	jc	sl8
	cmp	byte ptr ds:[PSP_PFT+MACH_PFT],SFH_NONE	; is our last free?
	jne	sl8			; no
	mov	al,SFH_NONE
	xchg	al,ds:[PSP_PFT][bx]
	mov	ds:[PSP_PFT+MACH_PFT],al
	add	dl,INT_HW_TMR		; DL = its vector (IRQs 0-7)
	mov	[snd_vec],dl
	ret
sl8:	mov	ah,DOS_HDL_CLOSE
	int	21h
sl9:	ret
ENDPROC	snd_lend

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; io_dma
;
; The DMA controller's ports (00h-0Fh, and its page registers, 80h-8Fh) go
; to SND$ (see IOCTL_SNDDMA), if the machine has a sound card; otherwise,
; they're ports with nothing behind them (eg, a program that writes port 80h
; as a delay).
;
DEFPROC	io_dma
	cmp	[snd_vec],0		; does it have a sound card?
	je	io_none			; no
	push	bx
	push	dx
	mov	cl,dl			; CL = port
	mov	ch,bl
	shr	ch,1
	and	ch,1			; CH = 1 for OUT
	mov	dl,al
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_SNDDMA
	mov	bx,MACH_PFT		; (our handle for SND$)
	int	21h			; DL = byte (IN)
	xchg	ax,dx
	pop	dx
	pop	bx
	clc
	ret
ENDPROC	io_dma

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; io_none
;
; A port with nothing behind it reads as FFh: a sound card's (388h and
; 389h), which is how programs know that there isn't one, and the parallel
; ports' (eg, for a program that looks for a sound device there; printing is
; INT 17h's).  OUTs do nothing.  (The interrupt controller's ports and the
; game port, which reads FFh, too, are the 80386 driver's; see CPU_V86.)
;
DEFPROC	io_none
	test	bl,2			; OUT? (and carry is clear)
	jnz	in9			; yes
	mov	al,0FFh
in9:	ret
ENDPROC	io_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; io_pit
;
; The timer's ports (40h-43h): only counter 0's divisor matters to us (it's
; how often the machine gets an INT 08h; see tick), which a program sets with
; a command (port 43h, bits 7-6 zero) and then two bytes (port 40h), low and
; high; zero means 65536, and anything smaller than PIT_MIN is PIT_MIN.  The
; other counters' OUTs (eg, the speaker's tone) do nothing, and any IN is a
; count that's always changing.
;
DEFPROC	io_pit
	test	bl,2			; OUT?
	jnz	ip1			; yes
	sub	[pit_count],25h
	mov	al,[pit_count]
	jmp	short ip9
ip1:	cmp	cl,3			; a command?
	jne	ip2			; no
	test	al,0C0h			; for counter 0?
	jnz	ip9			; no
	mov	byte ptr [pit_high],0	; yes, so its low byte is next
	jmp	short ip9
ip2:	jcxz	ip3			; counter 0's divisor
	jmp	short ip9
ip3:	xor	byte ptr [pit_high],1	; is this the low byte?
	jz	ip4			; no
	mov	[pit_low],al
	jmp	short ip9
ip4:	mov	ch,al
	mov	cl,[pit_low]		; CX = divisor
	jcxz	ip5
	cmp	cx,PIT_MIN
	jae	ip5
	mov	cx,PIT_MIN
ip5:	mov	[pit_div],cx
ip9:	clc
	ret
ENDPROC	io_pit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; io_kbd
;
; The keyboard's ports (60h-64h): port 60h reads the scan code of the last
; INT 09h that the machine got (see virq), and port 61h reads what was last
; written to it (eg, by a handler that acknowledges the scan code there, or
; by a program that turns the speaker on), except that bit 4 changes every
; time, as an AT's does, for programs that time with it.  The rest read as
; zero (eg, the keyboard controller's status, which is that it's ready), and
; OUTs do nothing.
;
DEFPROC	io_kbd
	test	bl,2			; OUT?
	jnz	ik2			; yes
	mov	al,[kbd_data]
	jcxz	ik9			; port 60h
	xor	byte ptr [port_61],10h
	mov	al,[port_61]
	dec	cx
	jz	ik9			; port 61h
	mov	al,0
	jmp	short ik9
ik2:	dec	cx
	jnz	ik9
	mov	[port_61],al
ik9:	clc
	ret
ENDPROC	io_kbd

	DEFWORD	pit_div,0		; counter 0's divisor (zero = 65536)
	DEFWORD	pit_acc,0		; what's left of 65536 after each tick
	DEFBYTE	pit_owed,0		; ticks that the machine is owed
	DEFBYTE	pit_low,0		; the divisor's low byte
	DEFBYTE	pit_high,0		; nonzero if its high byte is next
	DEFBYTE	pit_count,0		; what an IN reads
	DEFBYTE	kbd_data,0		; the scan code that port 60h reads
	DEFBYTE	kbd_sent,0		; nonzero if a handler got one
	DEFBYTE	kbd_done,0		; nonzero after a tick's scan code
	DEFBYTE	port_61,0		; what port 61h reads
	DEFBYTE	snd_vec,0		; the sound card's vector (or zero)
	DEFSTR	SND_NAME,<"SND$",0>

CODE	ENDS

	end
