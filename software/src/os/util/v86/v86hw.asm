;
; BASIC-DOS V86 Utility: Timer Ticks and I/O Ports
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The machine has no hardware of its own, so what its programs expect of it
; is done here: a timer tick (an INT 08h, and the BIOS tick count) whenever
; the machine exits after one of the system's, and the I/O ports in IO_TABLE,
; each of which has a handler for the machine's INs and OUTs (see do_io); the
; machine never uses a port itself.
;
	include	v86host.inc

CODE    SEGMENT word public 'CODE'

	EXTBYTE	<VARS>
	EXTNEAR	<run,fault,seg_ptr,push_word>

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
	IOENT	<201h,1,io_game>
	DEFLBL	IO_END,word

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tick
;
; The machine exited after a timer tick (V86X_TICK): the tick count in its
; BIOS data becomes the system's (rather than counting its own ticks, which
; it misses while its interrupts are off, or while a DOS call waits), and
; unless its interrupts are off, it gets an INT 08h, as real mode would do it
; (pushing its FLAGS, CS, and IP, and clearing IF and TF).  The default
; handler is code in the machine (see STUB_TICK), so the machine runs again
; at whatever the vector points to.
;
DEFPROC	tick
	sub	ax,ax
	mov	di,BIOS_DATA + offset TIMER_LOW
	call	seg_ptr			; ES:DI -> the machine's tick count
	sub	bx,bx
	mov	si,BIOS_DATA + offset TIMER_LOW
	DOSUTIL	MAPSEG,1		; AX = TIMER_LOW
	stosw
	inc	si
	inc	si
	DOSUTIL	MAPSEG,1		; AX = TIMER_HIGH
	stosw
	test	byte ptr [VARS+VR_EFL+1],FL_INTS SHR 8
	jz	tk9			; its interrupts are off
	sub	ax,ax
	mov	di,INT_HW_TMR * 4
	call	seg_ptr			; ES:DI -> its INT 08h vector
	mov	cx,es:[di].OFF
	mov	dx,es:[di].SEG
	mov	ax,word ptr [VARS+VR_EFL]
	call	push_word
	mov	ax,word ptr [VARS+VR_CS]
	call	push_word
	mov	ax,word ptr [VARS+VR_EIP]
	call	push_word
	mov	word ptr [VARS+VR_EIP],cx
	mov	word ptr [VARS+VR_CS],dx
	and	word ptr [VARS+VR_EFL],NOT (FL_INTS OR FL_TRAP)
tk9:	jmp	run
ENDPROC	tick

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
; io_game
;
; The game port (201h) reads as it does when there's no game adapter (FFh),
; so its buttons (bits 4-7) are up, and programs that time its position bits
; (0-3), which an OUT would clear, give up at once (eg, BASIC's STICK is 0).
;
DEFPROC	io_game
	test	bl,2			; OUT? (and carry is clear)
	jnz	ig9			; yes
	mov	al,0FFh
ig9:	ret
ENDPROC	io_game

CODE	ENDS

	end
