;
; BASIC-DOS Physical (COM) Serial Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	dosapi.inc

DEV	group	CODE,CODE2,CODE3,CODE4,INIT,DATA

CODE	segment para public 'CODE'

	public	COM1
	DEFLEN	COM1_LEN,<COM1>
	DEFLEN	COM1_INIT,<COM1,COM2,COM3,COM4>
COM1	DDH	<COM1_LEN,,DDATTR_OPEN+DDATTR_CHAR,COM1_INIT,ddcom_int1,20202020314D4F43h>

	DEFPTR	ddcom_cmdp	; ddcom_cmd pointer
	DEFPTR	ddcom_intp	; ddcom_int pointer
	DEFWORD	ct_seg,0	; active context, if any
	DEFWORD	card_num,0	; card number
	DEFPTR	wait_ptr,-1	; chain of waiting packets

	DEFLBL	CMDTBL,word
	dw	ddcom_none,   ddcom_none,   ddcom_none,   ddcom_none	; 0-3
	dw	ddcom_read,   ddcom_none,   ddcom_none,   ddcom_none	; 4-7
	dw	ddcom_write,  ddcom_none,   ddcom_none,   ddcom_none	; 8-11
	dw	ddcom_none,   ddcom_open,   ddcom_close			; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFLBL	COM_PARMS,word
	dw	9600,110,19200, 8,7,8, 1,1,2, 128,0,4096

RINGBUF		struc
BUFOFF		dw	?	; 00h: offset within context of buffer
BUFHEAD		dw	?	; 02h: head of input (next offset to read)
BUFTAIL		dw	?	; 04h: tail of input (next offset to write)
BUFEND		dw	?	; 06h: offset within context of buffer end
RINGBUF		ends

;
; A serial context contains two ring buffers (CT_INPUT and CT_OUTPUT).
;
CONTEXT		struc
CT_CARD		dw	?	; 00h: RS232 "card" number (ie, BIOS index)
CT_PORT		dw	?	; 02h: base port address
CT_BAUD		dw	?	; 04h: current baud rate
CT_DATABITS	db	?	; 06h
CT_STOPBITS	db	?	; 07h
CT_PARITY	db	?	; 08h
CT_REFS		db	?	; 09h
CT_STATUS	db	?	; 0Ah: context status bits (CTSTAT_*)
CT_SIG		db	?	; 0Bh
CT_INPUT	db	size RINGBUF dup (?)	; 0Ch
CT_OUTPUT	db	size RINGBUF dup (?)	; 14h
CONTEXT		ends
SIG_CT		equ	'O'

CTSTAT_XMTFULL	equ	01h	; transmitter buffer full
CTSTAT_RCVOVFL	equ	02h	; receiver buffer overflow
CTSTAT_INPUT	equ	40h	; context is waiting for input

DEF_INLEN	equ	128
DEF_OUTLEN	equ	128

REG_DLL		equ	0	; Divisor Latch LSB (write when DLAB set)
REG_THR		equ	0	; Transmitter Holding Register (write when DLAB clear)
REG_RBR		equ	0	; Receiver Buffer Register (read-only)

REG_IER		equ	1	; Interrupt Enable Register
IER_RBR_AVAIL	equ	01h
IER_THR_EMPTY	equ	02h
IER_DELTA	equ	04h
IER_MSR_DELTA	equ	08h
IER_UNUSED	equ	0F0h	; always zero

REG_IIR		equ	2	; Interrupt ID Register (read-only)
IIR_NO_INT	equ	01h
IIR_INT_LSR	equ	06h	; Line Status (highest priority: Overrun error, Parity error, Framing error, or Break Interrupt)
IIR_INT_RBR	equ	04h	; Receiver Data Available
IIR_INT_THR	equ	02h	; Transmitter Holding Register Empty
IIR_INT_MSR	equ	00h	; Modem Status Register (lowest priority: Clear To Send, Data Set Ready, Ring Indicator, or Data Carrier Detect)
IIR_INT_BITS	equ	06h
IIR_UNUSED	equ	0F8h	; always zero (the ROM BIOS relies on these bits "floating to 1" when no SerialPort is present)

REG_LCR		equ	3	; Line Control Register
LCR_DATA5	equ	00h
LCR_DATA6	equ	01h
LCR_DATA7	equ	02h
LCR_DATA8	equ	03h
LCR_STOP	equ	04h	; clear: 1 stop bit; set: 1.5 stop bits for LCR_DATA_5BITS, 2 stop bits for all other data lengths
LCR_PARITY	equ	08h	; if set, a parity bit is inserted/expected between the last data bit and the first stop bit; no parity bit if clear
LCR_PARITY_EVEN	equ	10h	; if set, even parity is selected (ie, the parity bit insures an even number of set bits); if clear, odd parity
LCR_PARITY_INV	equ	20h	; if set, parity bit is transmitted inverted; if clear, parity bit is transmitted normally
LCR_BREAK	equ	40h	; if set, serial output (SOUT) signal is forced to logical 0 for the duration
LCR_DLAB	equ	80h	; Divisor Latch Access Bit; if set, DLL.REG and DLM.REG can be read or written

REG_MCR		equ	4	; Modem Control Register
MCR_DTR		equ	01h	; when set, DTR goes high, indicating ready to establish link (looped back to DSR in loop-back mode)
MCR_RTS		equ	02h	; when set, RTS goes high, indicating ready to exchange data (looped back to CTS in loop-back mode)
MCR_OUT1	equ	04h	; when set, OUT1 goes high (looped back to RI in loop-back mode)
MCR_OUT2	equ	08h	; when set, OUT2 goes high (looped back to RLSD in loop-back mode); must also be set for most UARTs to enable interrupts

REG_LSR		equ	5	; Line Status Register
LSR_DR		equ	01h	; Data Ready (set when new data in RBR; cleared when RBR read)
LSR_OE		equ	02h	; Overrun Error (set when new data arrives in RBR before previous data read; cleared when LSR read)
LSR_PE		equ	04h	; Parity Error (set when new data has incorrect parity; cleared when LSR read)
LSR_FE		equ	08h	; Framing Error (set when new data has invalid stop bit; cleared when LSR read)
LSR_BI		equ	10h	; Break Interrupt (set when new data exceeded normal transmission time; cleared LSR when read)
LSR_THRE	equ	20h	; Transmitter Holding Register Empty (set when UART ready to accept new data; cleared when THR written)
LSR_TSRE	equ	40h	; Transmitter Shift Register Empty (set when the TSR is empty; cleared when the THR is transferred to the TSR)
LSR_UNUSED	equ	80h	; always zero

REG_MSR		equ	6	; Modem Status Register
MSR_DCTS	equ	01h	; when set, CTS (Clear To Send) has changed since last read
MSR_DDSR	equ	02h	; when set, DSR (Data Set Ready) has changed since last read
MSR_TERI	equ	04h	; when set, TERI (Trailing Edge Ring Indicator) indicates RI has changed from 1 to 0
MSR_DRLSD	equ	08h	; when set, RLSD (Received Line Signal Detector) has changed
MSR_CTS		equ	10h	; when set, the modem or data set is ready to exchange data (complement of the Clear To Send input signal)
MSR_DSR		equ	20h	; when set, the modem or data set is ready to establish link (complement of the Data Set Ready input signal)
MSR_RI		equ	40h	; complement of the RI (Ring Indicator) input
MSR_RLSD	equ	80h	; complement of the RLSD (Received Line Signal Detect) input

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
DEFPROC	ddcom_req,far
	mov	cx,[ct_seg]
	mov	dx,[card_num]
	call	[ddcom_cmdp]
	mov	[ct_seg],cx
	ret
ENDPROC	ddcom_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver command handler
;
; Inputs:
;	CX = context, if any
;	DX = card #
;	ES:BX -> DDP
;
; Outputs:
;
DEFPROC	ddcom_cmd,far
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
ENDPROC	ddcom_cmd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_read
;
; Inputs:
;	CX = context, if any
;	DX = card #
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW packet updated
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_read
	push	cx
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	dcr9

	mov	ax,es:[di].DDP_CONTEXT
	test	ax,ax
	jnz	dcr1a

	lds	si,es:[di].DDPRW_ADDR
	ASSUME	DS:NOTHING

dcr1:	mov	ah,2			; AH = READ, DX = card #
	int	14h			; call the BIOS to read a char
	; test	ah,ah
	; jnz	err
	mov	[si],al
	inc	si
	loop	dcr1
	jmp	short dcr9

dcr1a:	mov	ds,ax
	ASSUME	DS:NOTHING

	cli
	call	pull_input
	jnc	dcr9
;
; For READ requests that cannot be satisifed, we add this packet to an
; internal chain of "reading" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
	ASSERT	STRUCT,ds:[0],CT
	or	ds:[CT_STATUS],CTSTAT_INPUT

	call	add_packet
dcr9:	sti

	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	pop	cx
	ret
ENDPROC	ddcom_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_write
;
; Inputs:
;	CX = context, if any
;	DX = card #
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW packet updated
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_write
	push	cx
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	dcw9

	lds	si,es:[di].DDPRW_ADDR
	ASSUME	DS:NOTHING
	mov	ax,es:[di].DDP_CONTEXT
	test	ax,ax
	jnz	dcw1a

dcw1:	lodsb
	mov	ah,1			; AH = WRITE, DX = card #
	int	14h			; call the BIOS to write the char
	loop	dcw1
	jmp	short dcw9

dcw1a:	xchg	dx,ax

dcw2:	push	es
	mov	es,dx
dcw3:	test	es:[CT_STATUS],CTSTAT_XMTFULL
	jz	dcw4
;
; For WRITE requests that cannot be satisifed, we add this packet to an
; internal chain of "writing" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
dcw3a:	pop	es			; ES:DI -> packet again
	mov	es:[di].DDPRW_LENGTH,cx
	mov	es:[di].DDPRW_ADDR.OFF,si
	call	add_packet
	jmp	dcw2			; when this returns, try writing again

dcw4:	mov	al,[si]
	call	write_context
	jc	dcw3a
	inc	si
	loop	dcw4
	pop	es

dcw9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	pop	cx
	ret
ENDPROC	ddcom_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_open
;
; The format of the optional context descriptor is:
;
;	[device]:[baud],[parity],[databits],[stopbits],[inbuflen],[outbuflen]
;
; where [device] is "COMn" (otherwise you wouldn't be here).
;
; Inputs:
;	CX = context, if any
;	DX = card #
;	ES:DI -> DDP
;	[DDP].DDP_PTR -> context descriptor (eg, "COM1:9600,N,8,1")
;
; Outputs:
;	CX = context (zero if none)
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_open
;
; If there's already a context for this device, increment the refs.
;
	jcxz	dco1
	mov	ds,cx
	ASSUME	DS:NOTHING
	inc	ds:[CT_REFS]
dco0:	jmp	dco8

dco1:	lds	si,es:[di].DDP_PTR
	ASSUME	DS:NOTHING
;
; We know that DDP_PTR must point to a string containing "COMn" at the
; very least, so we skip those 4 bytes.
;
	add	si,4			; DS:SI -> parms
	cmp	[si],cl			; any parms?
	je	dco0			; no
	inc	si			; skip the colon separator

	push	di
	push	es
	mov	di,dx			; DI = card #
	call	get_parms
	push	ax			; save output buffer length
	push	bx			; save parity
	push	cx			; save baud rate
	add	ax,si			; AX = output + input buffer lengths
	add	ax,size CONTEXT + 15
	mov	cl,4
	shr	ax,cl
	xchg	bx,ax			; BX = required length, in paras
	mov	ah,DOS_MEM_ALLOC
	int	INT_DOSFUNC
	jnc	dco1a
	jmp	dco7

dco1a:	mov	es,ax
	xchg	ax,di			; AX = card #
	sub	di,di			; ES:DI -> CONTEXT
	push	ds
	mov	ds,di
	ASSUME	DS:BIOS
	stosw				; set CT_CARD
	xchg	bx,ax
	add	bx,bx			; BX = card # * 2
	mov	ax,[RS232_BASE][bx]
	pop	ds
	ASSUME	DS:NOTHING
	stosw				; set CT_PORT
	pop	ax			; restore baud rate (originally in CX)
	stosw				; set CT_BAUD
	xchg	ax,dx
	stosw				; set CT_DATABITS and CT_STOPBITS
	pop	ax			; restore parity (originally in BH)
	mov	al,1
	xchg	al,ah
	stosw				; set CT_PARITY and CT_REFS
	sub	ax,ax
	IFDEF DEBUG
	mov	ah,SIG_CT
	ENDIF
	stosw				; set CT_STATUS and CT_SIG

	mov	ax,size CONTEXT
	stosw				; set CT_INPUT.BUFOFF
	stosw				; set CT_INPUT.BUFHEAD
	stosw				; set CT_INPUT.BUFTAIL
	add	ax,si
	stosw				; set CT_INPUT.BUFEND

	stosw				; set CT_OUTPUT.BUFOFF
	stosw				; set CT_OUTPUT.BUFHEAD
	stosw				; set CT_OUTPUT.BUFTAIL
	pop	bx			; restore output buffer length
	add	ax,bx
	stosw				; set CT_OUTPUT.BUFEND

	push	es
	pop	ds			; DS is now the context
	mov	ax,ds:[CT_BAUD]
	mov	cl,150
	div	cl
;
; AL is now 64, 32, 16, 8, 4, 2, or 1 for baud rates 9600, 4800, 2400, 1200,
; 600, 300, or 150.
;
	mov	ah,0
dco2:	test	al,al
	jz	dco3
	shr	al,1
	add	ah,20h
	jnc	dco2
;
; AH should now contain the correct baud rate selection in bits 7-5.  Next,
; add the appropriate parity, stop length, and data length bits.
;
dco3:	mov	al,ds:[CT_PARITY]
	cmp	al,'O'
	jne	dco3a
	or	ah,08h
dco3a:	cmp	al,'E'
	jne	dco3b
	or	ah,18h
dco3b:	cmp	ds:[CT_STOPBITS],2
	jne	dco3c
	or	ah,04h
dco3c:	or	ah,02h
	cmp	ds:[CT_DATABITS],8
	jne	dco4
	or	ah,03h
;
; Now we can use the BIOS to initialize the card.
;
dco4:	mov	dx,ds:[CT_CARD]
	mov	al,ah
	mov	ah,0
	int	INT_COM

	test	si,si			; verify we have an input buffer
	jnz	dco5			; we do
	mov	ah,DOS_MEM_FREE		; no, apparently the caller just
	int	INT_DOSFUNC		; used us to initialize the COM port
	sub	cx,cx
	jmp	short dco6
;
; There are 3 required steps to enabling COM interrupts.
;
; Step 1: Set the desired bits in the Interrupt Enable Register.
;
dco5:	call	write_ier		; enable THR and RBR interrupts
;
; Step 2: Set the OUT2 bit in the Modem Control Register.
;
	call	write_mcr		; set DTR and OUT2
;
; Step 3: Unmask the IRQ.  We choose which IRQ based on port #.
;
	mov	al,0
	call	write_irq
;
; All done.  Be sure to return with the context segment in CX.
;
	mov	cx,ds
dco6:	pop	es
	pop	di
	jmp	short dco8
;
; At the moment, the only possible error is a failure to allocate memory.
;
dco7:	pop	es
	pop	di
	sub	cx,cx
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_GENFAIL
	jmp	short dco9

dco8:	mov	es:[di].DDP_CONTEXT,cx
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dco9:	ret
ENDPROC	ddcom_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_close
;
; Inputs:
;	CX = context, if any
;	ES:DI -> DDP
;
; Outputs:
;	CX = context (zero if freed)
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_close
	mov	cx,es:[di].DDP_CONTEXT
	jcxz	dcc8			; no context

	push	es
	mov	es,cx
	ASSERT	STRUCT,es:[0],CT
	dec	es:[CT_REFS]
	jg	dcc8
;
; Before freeing the context, mask the IRQ.
;
	mov	al,1
	call	write_irq
;
; We are now free to free the context segment in ES.
;
	mov	ah,DOS_MEM_FREE
	int	INT_DOSFUNC
	pop	es
	sub	cx,cx

dcc8:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcom_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_none (handler for unimplemented functions)
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	DDPRW packet updated
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_none
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	stc
	ret
ENDPROC	ddcom_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_int
;
; COM hardware interrupt handler.
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
DEFPROC	ddcom_int,far
	call	far ptr DDINT_ENTER
	push	ax
	jcxz	ddi0			; no context
	jnc	ddi1			; carry clear if DOS ready
;
; Unlike the CONSOLE and CLOCK$ drivers' hardware interrupt handlers,
; which simply piggy-back on existing BIOS hardware interrupt handlers,
; we're on our own here.  So we must make sure our handler always EOIs
; the interrupt, even if the system isn't ready to process interrupts yet.
;
ddi0:	mov	al,20h			; EOI the interrupt to ensure
	out	20h,al			; we don't block other interrupts
	jmp	ddix

ddi1:	push	bx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	mov	ds,cx
	sti
;
; Check the IIR to see what's changed.
;
	call	read_iir
	cmp	al,IIR_INT_RBR		; data received?
	jne	ddi1a			; no
	call	push_input
	jmp	short ddi1b

ddi1a:	cmp	al,IIR_INT_THR		; transmitter ready?
	jne	ddi1b			; no
	call	pull_output

ddi1b:	mov	al,20h			; EOI the interrupt now
	out	20h,al

	mov	cx,cs
	mov	es,cx
	mov	bx,offset wait_ptr	; CX:BX -> ptr
	les	di,es:[bx]		; ES:DI -> packet, if any

ddi2:	cmp	di,-1			; end of chain?
	je	ddi9			; yes

	ASSERT	STRUCT,es:[di],DDP

	cmp	es:[di].DDP_CMD,DDC_READ; READ packet?
	je	ddi3			; yes, look for buffered data
;
; For WRITE packets (which we'll assume this is for now), we need to end the
; wait if the context is no longer busy.
;
	ASSERT	STRUCT,ds:[0],CT
	test	ds:[CT_STATUS],CTSTAT_XMTFULL
	jz	ddi4			; transmitter buffer is no longer full
	jmp	short ddi6		; still full, check next packet

ddi3:	call	pull_input		; pull more input data
	jc	ddi6			; not enough data, check next packet
;
; Notify DOS that this packet is done waiting.
;
ddi4:	and	ds:[CT_STATUS],NOT CTSTAT_INPUT
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	DOSUTIL	ENDWAIT
	ASSERT	NC
;
; If ENDWAIT returns an error, that could be a problem.  In the past, it
; was because we got ahead of the WAIT call.  One thought was to make the
; driver's WAIT code more resilient, and double-check that the request had
; really been satisfied, but I eventually resolved the race by making the
; pull_input/add_packet/utl_wait path atomic (ie, no interrupts).
;
; TODO: Consider lighter-weight solutions to this race condition.
;
; Anyway, assuming no race conditions, proceed with the packet removal now.
;
	cli
	mov	ax,es:[di].DDP_PTR.OFF
	mov	dx,es:[di].DDP_PTR.SEG
	mov	es,cx
	mov	es:[bx].OFF,ax
	mov	es:[bx].SEG,dx
	sti
	stc				; set carry to indicate yield
	jmp	short ddi9

ddi6:	lea	bx,[di].DDP_PTR		; update prev addr ptr in CX:BX
	mov	cx,es

	les	di,es:[di].DDP_PTR
	jmp	ddi2

ddi9:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	bx

ddix:	pop	ax
	pop	cx
	jmp	far ptr DDINT_LEAVE
ENDPROC	ddcom_int

DEFPROC	ddcom_int1,far
	push	cx
	mov	cx,[ct_seg]
	jmp	[ddcom_intp]
ENDPROC	ddcom_int1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_packet
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	add_packet
	cli
	mov	ax,di
	xchg	[wait_ptr].OFF,ax
	mov	es:[di].DDP_PTR.OFF,ax
	mov	ax,es
	xchg	[wait_ptr].SEG,ax
	mov	es:[di].DDP_PTR.SEG,ax
;
; The WAIT condition will be satisfied when enough data is received
; (for a READ packet) or when the context is ready (for a WRITE packet).
;
	push	dx
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	DOSUTIL	WAIT
	pop	dx
	sti
	ret
ENDPROC	add_packet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_parms
;
; Inputs:
;	DS:SI -> parameter string:
;	[device]:[baud],[parity],[databits],[stopbits],[inbuflen],[outbuflen]
;
; Outputs:
;	CX = baud rate
;	BH = parity indicator (unvalidated; should be one of 'N', 'O', or 'E')
;	DL = data bits
;	DH = stop bits
;	SI = input buffer length
;	AX = output buffer length
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	get_parms
	push	di
	push	es
	push	cs
	pop	es
	mov	bl,10			; use base 10
	mov	di,offset COM_PARMS	; ES:DI -> parm defaults/limits
	DOSUTIL	ATOI16			; updates SI, DI, and AX
	xchg	cx,ax			; CX = baud rate
	lodsb
	mov	bh,al			; BH = parity indicator ('N', 'O', 'E')
	lodsb
	DOSUTIL	ATOI16
	mov	dl,al			; DL = data bits
	DOSUTIL	ATOI16
	mov	dh,al			; DH = stop bits
	DOSUTIL	ATOI16
	push	ax			; AX = input buffer length
	sub	di,6			; use the input limits for output, too
	DOSUTIL	ATOI16			; AX = output buffer length
	pop	si			; SI = input buffer length
	pop	es
	pop	di
	ret
ENDPROC	get_parms

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peek_buffer
;
; Inputs:
;	SI -> RINGBUF in context
;	DS = context
;
; Outputs:
;	ZF clear if data available, ZF set if empty
;
; Modifies:
;	BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	peek_buffer
	ASSERT	STRUCT,ds:[0],CT
	mov	bx,[si].BUFHEAD
	cmp	bx,[si].BUFTAIL
	ret
ENDPROC	peek_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pull_buffer
;
; Call with interrupts off when calling from non-interrupt code (eg, when
; pulling bytes for a read request).
;
; Inputs:
;	SI -> RINGBUF in context
;	DS = context
;
; Outputs:
;	CF clear if data available in AL, CF set if empty
;
; Modifies:
;	AX, BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pull_buffer
	ASSERT	STRUCT,ds:[0],CT
	mov	bx,[si].BUFHEAD
	cmp	bx,[si].BUFTAIL
	stc
	je	pl9			; buffer empty
	mov	al,[bx]
	inc	bx
	cmp	bx,[si].BUFEND
	jb	pl2
	mov	bx,[si].BUFOFF
pl2:	mov	[si].BUFHEAD,bx
	clc
pl9:	ret
ENDPROC	pull_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; push_buffer
;
; Call with interrupts off when calling from non-interrupt code (eg, when
; pushing bytes from a write request).
;
; Inputs:
;	SI -> RINGBUF in context
;	DS = context
;
; Outputs:
;	CF clear if room (BX -> available space), CF set if full
;
; Modifies:
;	BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	push_buffer
	ASSERT	STRUCT,ds:[0],CT
	push	ax
	mov	bx,[si].BUFTAIL
	mov	ax,bx			; AX -> potential free space
	inc	bx
	cmp	bx,[si].BUFEND
	jb	ps1
	mov	bx,[si].BUFOFF
ps1:	cmp	bx,[si].BUFHEAD
	stc
	je	ps9
	mov	[si].BUFTAIL,bx
	xchg	bx,ax
	clc
ps9:	pop	ax
	ret
ENDPROC	push_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pull_input
;
; Remove bytes from CT_INPUT and transfer them to the request buffer.
;
; Inputs:
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	If carry clear, AL = byte; otherwise carry set
;
; Modifies:
;	AX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pull_input
	push	bx
	mov	si,offset CT_INPUT
pli1:	call	pull_buffer
	jc	pli9
	push	ds
	lds	bx,es:[di].DDPRW_ADDR	; DS:BX -> next read/write address
	mov	[bx],al
	inc	bx
	mov	es:[di].DDPRW_ADDR.OFF,bx
	pop	ds
	dec	es:[di].DDPRW_LENGTH	; have we satisfied the request yet?
	jnz	pli1
	clc
pli9:	pop	bx
	ret
ENDPROC	pull_input

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; push_input
;
; Add a byte from the receiver to CT_INPUT.  If there's no more room,
; then set CTSTAT_RCVOVFL.
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	push_input
	mov	si,offset CT_INPUT
	call	push_buffer
	jc	psi8
	call	read_rbr
	mov	[bx],al
	jmp	short psi9
psi8:	or	ds:[CT_STATUS],CTSTAT_RCVOVFL
psi9:	ret
ENDPROC	push_input

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pull_output
;
; Remove a byte from CT_OUTPUT and transmit it.  If there are no more bytes,
; then clear CTSTAT_XMTFULL.
;
; Inputs:
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	If carry clear, AL = byte; otherwise carry set
;
; Modifies:
;	AX, BX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pull_output
	mov	si,offset CT_OUTPUT
	call	pull_buffer
	jc	plo8
	call	write_thr
	jmp	short plo9
;
; TODO: Think about the best time to clear CTSTAT_XMTFULL.  In theory, I can
; clear it every time we remove a single byte, instead of waiting for the buffer
; to become completely empty, but that could create increased context-switching
; overhead with minimal benefit.
;
plo8:	and	ds:[CT_STATUS],NOT CTSTAT_XMTFULL
plo9:	ret
ENDPROC	pull_output

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; push_output
;
; Add a byte to CT_OUTPUT.
;
; Inputs:
;	AL = byte
;	DS = context
;
; Outputs:
;	CF clear if successful, CF set if buffer full
;
; Modifies:
;	BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	push_output
	cli
	mov	si,offset CT_OUTPUT
	call	peek_buffer		; anything in the output buffer?
	jnz	pso7			; yes, so continue to buffer
	push	ax
	call	read_lsr
	test	al,LSR_THRE		; is the transmitter is available?
	pop	ax
	jz	pso7			; no, so once again, we must buffer
	call	write_thr		; prime the pump
	jmp	short pso9
pso7:	call	push_buffer		; is there room in the buffer?
	jc	pso8			; no, mark it full
	mov	[bx],al			; yes, save the data
	jmp	short pso9
pso8:	or	ds:[CT_STATUS],CTSTAT_XMTFULL
	stc
pso9:	sti
	ret
ENDPROC	push_output

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_iir
;
; Inputs:
;	DS = context
;
; Outputs:
;	AL = Interrupt ID Register (IIR)
;
; Modifies:
;	AX, DX
;
DEFPROC	read_iir
	mov	dx,ds:[CT_PORT]
	add	dx,REG_IIR		; DX -> IIR
	in	al,dx
	ret
ENDPROC	read_iir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_lsr
;
; Inputs:
;	DS = context
;
; Outputs:
;	AL = Line Status Register (LSR)
;
; Modifies:
;	AX, DX
;
DEFPROC	read_lsr
	mov	dx,ds:[CT_PORT]
	add	dx,REG_LSR		; DX -> LSR
	in	al,dx
	ret
ENDPROC	read_lsr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_rbr
;
; Inputs:
;	DS = context
;
; Outputs:
;	AL = Receiver Buffer Register (RBR)
;
; Modifies:
;	AX, DX
;
DEFPROC	read_rbr
	mov	dx,ds:[CT_PORT]
	in	al,dx
	ret
ENDPROC	read_rbr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_mcr
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX
;
DEFPROC	write_mcr
	mov	dx,ds:[CT_PORT]
	add	dx,REG_MCR		; DX -> MCR
	in	al,dx
	jmp	$+2
	or	al,MCR_DTR OR MCR_OUT2	; OUT2 enables interrupts
	out	dx,al
	ret
ENDPROC	write_mcr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_ier
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX
;
DEFPROC	write_ier
	mov	dx,ds:[CT_PORT]
	add	dx,REG_LCR		; DX -> LCR
	in	al,dx
	jmp	$+2
	and	al,not LCR_DLAB		; make sure the DLAB is not set
	out	dx,al			; so that we can set IER
	dec	dx
	dec	dx			; DX -> IER
	jmp	$+2
	mov	al,IER_THR_EMPTY OR IER_RBR_AVAIL
	out	dx,al
	ret
ENDPROC	write_ier

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_irq
;
; This unmasks (on device open) or masks (on device close) the IRQ associated
; with the device.  We simplistically decide that it's IRQ4 if the port address
; is 3F8h and IRQ3 if the port address is 2F8h.
;
; Inputs:
;	AL = 0 to unmask IRQ, non-zero to mask
;	ES = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	write_irq
	mov	dx,es:[CT_PORT]
	mov	cl,dh			; DH should be either 2 or 3
	inc	cx
	mov	ah,1
	shl	ah,cl			; shift AL (01h) left 3 or 4 bits
	test	al,al
	in	al,21h			; read the PIC's IMR
	jnz	si8			; jump if masking
	not	ah
	and	al,ah			; unmask it
	jmp	short si9
si8:	or	al,ah			; mask it
si9:	out	21h,al			; update the PIC's IMR
	ret
ENDPROC	write_irq

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_thr
;
; Inputs:
;	AL = data for Transmitter Holding Register (THR)
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	DX
;
DEFPROC	write_thr
	mov	dx,ds:[CT_PORT]
	out	dx,al
	ret
ENDPROC	write_thr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_context
;
; Inputs:
;	AL = character
;	ES = context
;
; Outputs:
;	Carry clear if successful, set unable to buffer
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	write_context
	push	bx
	push	dx
	push	si
	push	ds
	push	es
	pop	ds			; DS is now the context
	call	push_output
	pop	ds
	pop	si
	pop	dx
	pop	bx
	ret
ENDPROC	write_context

	DEFLBL	COM1_END

CODE	ends

CODE2	segment para public 'CODE'

	public	COM2
	DEFLEN	COM2_LEN,<COM2>
	DEFLEN	COM2_INIT,<COM2,COM3,COM4>
COM2	DDH	<COM2_LEN,,DDATTR_CHAR,COM2_INIT,ddcom_int2,20202020324D4F43h>

	DEFPTR	ddcom_cmdp2
	DEFPTR	ddcom_intp2
	DEFWORD	ct_seg2,0
	DEFWORD	card_num2,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE2, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_req2,far
	mov	cx,[ct_seg2]
	mov	dx,[card_num2]
	call	[ddcom_cmdp2]
	mov	[ct_seg2],cx
	ret
ENDPROC	ddcom_req2

DEFPROC	ddcom_int2,far
	push	cx
	mov	cx,[ct_seg2]
	jmp	[ddcom_intp2]
ENDPROC	ddcom_int2

	DEFLBL	COM2_END

CODE2	ends

CODE3	segment para public 'CODE'

	public	COM3
	DEFLEN	COM3_LEN,<COM3>
	DEFLEN	COM3_INIT,<COM3,COM4>
COM3	DDH	<COM3_LEN,,DDATTR_CHAR,COM3_INIT,ddcom_int3,20202020334D4F43h>

	DEFPTR	ddcom_cmdp3
	DEFPTR	ddcom_intp3
	DEFWORD	ct_seg3,0
	DEFWORD	card_num3,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE3, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_req3,far
	mov	cx,[ct_seg3]
	mov	dx,[card_num3]
	call	[ddcom_cmdp3]
	mov	[ct_seg3],cx
	ret
ENDPROC	ddcom_req3

DEFPROC	ddcom_int3,far
	push	cx
	mov	cx,[ct_seg3]
	jmp	[ddcom_intp3]
ENDPROC	ddcom_int3

	DEFLBL	COM3_END

CODE3	ends

CODE4	segment para public 'CODE'

	public	COM4
	DEFLEN	COM4_LEN,<COM4,ddcom_init>,16
	DEFLEN	COM4_INIT,<COM4>
COM4	DDH	<COM4_LEN,,DDATTR_CHAR,COM4_INIT,ddcom_int4,20202020344D4F43h>

	DEFPTR	ddcom_cmdp4
	DEFPTR	ddcom_intp4
	DEFWORD	ct_seg4,0
	DEFWORD	card_num4,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE4, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_req4,far
	mov	cx,[ct_seg4]
	mov	dx,[card_num4]
	call	[ddcom_cmdp4]
	mov	[ct_seg4],cx
	ret
ENDPROC	ddcom_req4

DEFPROC	ddcom_int4,far
	push	cx
	mov	cx,[ct_seg4]
	jmp	[ddcom_intp4]
ENDPROC	ddcom_int4

	DEFLBL	COM4_END

CODE4	ends

INIT	segment para public 'CODE'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; If there are no COM ports, then the offset portion of DDPI_END will be zero.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_init,far
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	si,offset RS232_BASE
	mov	di,bx			; ES:DI -> DDPI
	mov	bl,byte ptr cs:[DDH_NAME+3]
	dec	bx
	and	bx,0003h
	add	si,bx
	mov	dx,[si+bx]		; DX = BIOS RS232 port address
	test	dx,dx			; exists?
	jz	in9			; no
	mov	[card_num],bx
	mov	ax,cs:[DDH_NEXT_OFF]	; yes, copy over the driver length
	cmp	bl,3			; COM4?
	jne	in1			; no
	mov	ax,cs:[DDH_REQUEST]	; use the temporary ddcom_req offset

in1:	mov	es:[di].DDPI_END.OFF,ax
	mov	cs:[DDH_REQUEST],offset DEV:ddcom_req

	mov	[ddcom_cmdp].OFF,offset DEV:ddcom_cmd
	mov	[ddcom_intp].OFF,offset DEV:ddcom_int
in2:	mov	ax,0			; this MOV will be modified
	test	ax,ax			; on the first call to contain the CS
	jnz	in3			; of the first driver (this is the
	mov	ax,cs			; easiest way to communicate between
	mov	word ptr cs:[in2+1],ax	; the otherwise fully insulated drivers)
in3:	mov	[ddcom_cmdp].SEG,ax
	mov	[ddcom_intp].SEG,ax
;
; Determine the hardware interrupt vector for port DX
;
	mov	di,INT_HW_COM1
	cmp	dh,03h
	je	in4
	dec	di
in4:	add	di,di
	add	di,di
	cli
	mov	ax,cs:[DDH_INTERRUPT]
	mov	[di].OFF,ax
	mov	[di].SEG,cs
	sti

in9:	ret
ENDPROC	ddcom_init

	DEFLBL	ddcom_init_end

INIT	ends

DATA	segment para public 'DATA'

ddcom_end	db	16 dup(0)

DATA	ends

	end
