;
; BASIC-DOS Physical (COM) Serial Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	BIOSEQU equ 1
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc

DEV	group	CODE,CODE2,CODE3,CODE4,INIT,DATA

CODE	segment para public 'CODE'

	public	COM1
	DEFLEN	COM1_LEN,<COM1>
	DEFLEN	COM1_INIT,<COM1,COM2,COM3,COM4>
COM1	DDH	<COM1_LEN,,DDATTR_OPEN+DDATTR_CHAR,COM1_INIT,ddcom_int1,20202020314D4F43h>
;
; Every COM driver instance must define the next group of variables in
; the same location/order as shown below.
;
	DEFPTR	ddcom_cmdp	; ddcom_cmd pointer
	DEFPTR	ddcom_intp	; ddcom_int pointer
	DEFWORD	ct_seg,0	; active context, if any
	DEFWORD	card_num,0	; card number

	DEFPTR	wait_ptr,-1	; chain of waiting packets

	DEFLBL	CMDTBL,word
	dw	ddcom_none,   ddcom_none,   ddcom_none,   ddcom_ioctl	; 0-3
	dw	ddcom_read,   ddcom_none,   ddcom_none,   ddcom_none	; 4-7
	dw	ddcom_write,  ddcom_none,   ddcom_none,   ddcom_none	; 8-11
	dw	ddcom_none,   ddcom_open,   ddcom_close			; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFLBL	COM_PARMS,word
	dw	9600,110,19200, 8,7,8, 1,1,2, 128,0,4096

;
; Terminal types (aka "personalities"), which may be specified after the
; stop bits (eg, "COM1:9600,N,8,1,GENERIC"); the default is ANSI.  The order
; of TERM_NAMES must match the TERM_* values.
;
TERM_ANSI	equ	0	; supports ANSI (VT100) cursor and erase sequences
TERM_GENERIC	equ	1	; supports only CR, LF, BACKSPACE, and TAB

	DEFLBL	TERM_NAMES,byte
	db	"ANSI",0,"GENERIC",0,0

	DEFLBL	ANSI_RIGHT,byte
	db	CHR_ESCAPE,"[C",0	; cursor forward
	DEFLBL	ANSI_CLEAR,byte
	db	CHR_ESCAPE,"[2J",CHR_ESCAPE,"[H",0
	DEFLBL	GENERIC_CLEAR,byte
	db	CHR_RETURN,CHR_LINEFEED,0
	DEFLBL	ANSI_RESET,byte
	db	CHR_ESCAPE,"[0",0	; start of "select graphic rendition"
	DEFLBL	ANSI_COLORS,byte	; PC color # to ANSI color #
	db	0,4,2,6,1,5,3,7		; (ie, swap the red and blue bits)

TERM_COLS	equ	80	; assumed terminal dimensions (for IOCTL_GETDIM)
TERM_ROWS	equ	24

RINGBUF		struc
BUFOFF		dw	?	; 00h: offset within context of buffer
BUFHEAD		dw	?	; 02h: head of input (next offset to read)
BUFTAIL		dw	?	; 04h: tail of input (next offset to write)
BUFEND		dw	?	; 06h: offset within context of buffer end
RINGBUF		ends

;
; A serial context contains two ring buffers (CT_INPUT and CT_OUTPUT).
;
LINE_MAX	equ	128	; maximum columns saved in CT_LINE

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
CT_COL		db	?	; 0Ch: current output column (see update_col)
CT_TERM		db	?	; 0Dh: terminal type (TERM_*)
CT_LLEN		db	?	; 0Eh: # of columns in CT_LINE
CT_RSVD		db	?	; 0Fh
CT_COLOR	dw	?	; 10h: fill (LO) and border (HI) attributes
CT_LINE		db	LINE_MAX dup (?); 12h: copy of the current output line
CT_INPUT	db	size RINGBUF dup (?)
CT_OUTPUT	db	size RINGBUF dup (?)
CONTEXT		ends
SIG_CT		equ	'O'

CTSTAT_XMTFULL	equ	01h	; transmitter buffer full
CTSTAT_RCVOVFL	equ	02h	; receiver buffer overflow
CTSTAT_INPUT	equ	40h	; context is waiting for input
CTSTAT_PAUSED	equ	80h	; context is paused (triggered by CTRLS hotkey)

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
; For READ requests that cannot be satisfied, we add this packet to an
; internal chain of "reading" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
	ASSERT	STRUCT,ds:[0],CT
	or	ds:[CT_STATUS],CTSTAT_INPUT

	call	add_packet
	jnc	dcr9
	and	ds:[CT_STATUS],NOT CTSTAT_INPUT
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_RDFAULT
	jmp	short dcr9a

dcr9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dcr9a:	sti
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
dcw3:	test	es:[CT_STATUS],CTSTAT_XMTFULL OR CTSTAT_PAUSED
	jz	dcw4
;
; For WRITE requests that cannot be satisfied, we add this packet to an
; internal chain of "writing" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
dcw3a:	pop	es			; ES:DI -> packet again
	mov	es:[di].DDPRW_LENGTH,cx
	mov	es:[di].DDPRW_ADDR.OFF,si
	call	add_packet
	jc	dcw8			; the wait was interrupted
	jmp	dcw2			; otherwise, try writing again

dcw8:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_WRFAULT
	pop	cx
	ret

dcw4:	mov	al,[si]
	call	write_context
	jc	dcw3a
	call	update_col		; update CT_COL for the char in AL
	inc	si
	loop	dcw4
	pop	es

dcw9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	pop	cx
	ret
ENDPROC	ddcom_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_ioctl
;
; When a serial context is serving as a console (eg, "CONSOLE=COM1:9600,N,8,1"
; in CONFIG.SYS), the DOS line editor (see read_line in conio.asm) relies on
; the same IOCTLs that the CON driver provides, in order to redisplay and
; reposition the cursor as characters are inserted, deleted, etc.  We support
; them by tracking the terminal's current column (CT_COL) as data is written,
; so that the editor sees consistent cursor positions and display lengths.
;
; We have no knowledge of the terminal's width, so line wrapping is ignored.
;
; Inputs:
;	CX = context, if any
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW packet updated (with any result in DDP_CONTEXT)
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_ioctl
	jcxz	dio8			; no context
	push	cx
	mov	ds,cx
	ASSUME	DS:NOTHING
	ASSERT	STRUCT,ds:[0],CT
	mov	al,es:[di].DDP_CODE	; AL = IOCTL code
	mov	cx,es:[di].DDPRW_LENGTH	; CX = IOCTL input value
	mov	dx,es:[di].DDPRW_LBA	; DX = IOCTL input value
	cmp	al,IOCTL_GETDIM
	je	dio0
	cmp	al,IOCTL_GETPOS
	je	dio1
	cmp	al,IOCTL_GETLEN
	je	dio2
	cmp	al,IOCTL_MOVCUR
	je	dio3
	cmp	al,IOCTL_SETINS
	je	dio4
	cmp	al,IOCTL_SCROLL
	je	dio5
	cmp	al,IOCTL_GETCOLOR
	je	dio0a
	cmp	al,IOCTL_SETCOLOR
	je	dio0b
	pop	cx
dio8:	jmp	ddcom_none		; unsupported IOCTL
;
; IOCTL_GETDIM: return the (assumed) terminal dimensions.
;
dio0:	mov	dx,(TERM_ROWS SHL 8) OR TERM_COLS
	jmp	short dio7
;
; IOCTL_GETCOLOR: return the fill (DL) and border (DH) attributes.
;
dio0a:	mov	dx,ds:[CT_COLOR]
	jmp	short dio7
;
; IOCTL_SETCOLOR: set the fill (CL) and border (CH) attributes.
;
dio0b:	call	set_color
	jc	dio9			; wait interrupted (DDP_STATUS set)
	jmp	short dio4
;
; IOCTL_GETPOS: return the current column in DL (row in DH is always zero).
;
dio1:	mov	dl,ds:[CT_COL]
	mov	dh,0
	jmp	short dio7
;
; IOCTL_GETLEN: return the display length of CL bytes at DDPRW_ADDR, starting
; at column DL, using the same display rules as the CON driver (and update_col).
;
dio2:	call	get_len
	jmp	short dio7
;
; IOCTL_MOVCUR: move the cursor by CX columns (negative for left).
;
dio3:	call	move_cur
	jc	dio9			; wait interrupted (DDP_STATUS set)
	jmp	short dio7
;
; IOCTL_SETINS: there's no cursor shape to change, so just report that
; insert mode was previously off.
;
dio4:	sub	dx,dx
	jmp	short dio7
;
; IOCTL_SCROLL: CX = 0 clears the screen (eg, for CLS); scrolling by a number
; of lines is not supported, so it's ignored.
;
dio5:	jcxz	dio6
	jmp	short dio4
dio6:	call	clear_screen
	jc	dio9			; wait interrupted (DDP_STATUS set)
	jmp	short dio4

dio7:	mov	es:[di].DDP_CONTEXT,dx	; return result in packet context
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dio9:	pop	cx			; CX = context
	ret
ENDPROC	ddcom_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_len
;
; Inputs:
;	CL = number of bytes
;	DL = starting column
;	ES:DI -> DDPRW (DDPRW_ADDR -> bytes)
;
; Outputs:
;	DH = total display length, DL = length delta (of the final character)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_len
	mov	bl,dl			; BL = current column
	sub	dx,dx			; DL = current len, DH = previous len
	mov	ch,0
	jcxz	gl9
	push	ds
	lds	si,es:[di].DDPRW_ADDR
gl1:	lodsb
	mov	dh,dl			; current len -> previous len
	mov	ah,1			; AH = # display columns
	cmp	al,CHR_TAB
	jne	gl2
	mov	ah,bl			; TAB advances to the next multiple of 8
	and	ah,07h
	neg	ah
	add	ah,8
	jmp	short gl3
gl2:	cmp	al,CHR_SPACE		; CONTROL character?
	jae	gl3			; no
	inc	ah			; yes, add 1 for the presumed "^"
gl3:	add	bl,ah			; advance the column
	add	dl,ah			; advance the length
	loop	gl1
	pop	ds
	sub	dl,dh			; DL = length delta for final character
	add	dh,dl			; DH = total length
gl9:	ret
ENDPROC	get_len

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; move_cur
;
; Moving left is done with BACKSPACEs.  There's no ASCII equivalent for moving
; right, so ANSI terminals get the "cursor forward" sequence, and GENERIC
; terminals get the characters from CT_LINE (ie, what should already be there).
;
; Inputs:
;	CX = +/- columns to move
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if interrupted (DDP_STATUS updated)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	move_cur
	test	cx,cx
	jz	mc9
	jg	mc3
	neg	cx			; CX = # columns to move left
mc1:	cmp	ds:[CT_COL],0		; already at the left edge?
	je	mc9			; yes
	mov	al,CHR_BACKSPACE
	call	ioctl_out
	jc	mc8
	dec	ds:[CT_COL]
	loop	mc1
	jmp	short mc9

mc3:	cmp	ds:[CT_TERM],TERM_GENERIC
	je	mc5
	mov	si,offset ANSI_RIGHT
	call	ioctl_str
	jc	mc8
	jmp	short mc7

mc5:	mov	bl,ds:[CT_COL]
	mov	bh,0
	mov	al,CHR_SPACE		; beyond the end of the line, use SPACE
	cmp	bl,ds:[CT_LLEN]
	jae	mc6
	mov	al,ds:[CT_LINE][bx]
mc6:	call	ioctl_out
	jc	mc8
mc7:	inc	ds:[CT_COL]
	loop	mc3

mc9:	clc
	ret
mc8:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_WRFAULT
	ret
ENDPROC	move_cur

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clear_screen
;
; Inputs:
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if interrupted (DDP_STATUS updated)
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	clear_screen
	mov	si,offset ANSI_CLEAR
	cmp	ds:[CT_TERM],TERM_GENERIC
	jne	clr1
	mov	si,offset GENERIC_CLEAR
clr1:	call	ioctl_str
	jc	clr8
	mov	ds:[CT_COL],0
	mov	ds:[CT_LLEN],0
	ret
clr8:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_WRFAULT
	ret
ENDPROC	clear_screen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_color
;
; Records the new attributes, and for ANSI terminals, sends the corresponding
; "select graphic rendition" sequence for the fill attributes (ie, foreground
; color in bits 0-2, intensity in bit 3, and background color in bits 4-6).
; The default attributes (07h) simply reset the terminal to its own defaults.
; Blinking (bit 7) and the border attributes are ignored.
;
; Inputs:
;	CL = fill attributes
;	CH = border attributes
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if interrupted (DDP_STATUS updated)
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_color
	mov	ds:[CT_COLOR],cx
	cmp	ds:[CT_TERM],TERM_ANSI
	jne	stc9			; nothing to send (carry clear)
	mov	si,offset ANSI_RESET
	call	ioctl_str		; ESC [ 0
	jc	stc8
	cmp	cl,07h			; default attributes?
	je	stc7			; yes, so the reset is all we need
	mov	ah,'3'			; foreground color
	mov	al,cl
	call	ansi_color
	jc	stc8
	mov	ah,'4'			; background color
	mov	al,cl
	shr	al,1
	shr	al,1
	shr	al,1
	shr	al,1
	call	ansi_color
	jc	stc8
	test	cl,08h			; intensity bit set?
	jz	stc7			; no
	mov	al,';'
	call	ioctl_out
	jc	stc8
	mov	al,'1'			; bold (aka bright)
	call	ioctl_out
	jc	stc8
stc7:	mov	al,'m'
	call	ioctl_out
	jc	stc8
stc9:	clc
	ret
stc8:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_WRFAULT
	ret
ENDPROC	set_color

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ansi_color
;
; Sends ";" followed by the prefix and the ANSI color # for a PC color #.
;
; Inputs:
;	AH = prefix ('3' for foreground, '4' for background)
;	AL = PC color # (in bits 0-2)
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if the wait was interrupted
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ansi_color
	and	al,07h
	mov	bl,al
	mov	bh,0
	mov	bl,cs:ANSI_COLORS[bx]	; BL = ANSI color #
	push	bx
	push	ax
	mov	al,';'
	call	ioctl_out
	pop	ax
	jc	ac8
	mov	al,ah
	call	ioctl_out		; prefix
ac8:	pop	bx
	jc	ac9
	mov	al,bl
	add	al,'0'
	call	ioctl_out		; color #
ac9:	ret
ENDPROC	ansi_color

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ioctl_str
;
; Outputs a null-terminated string on behalf of an IOCTL request.  The string
; contents are not reflected in CT_COL or CT_LINE (the caller must do that).
;
; Inputs:
;	CS:SI -> null-terminated string
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if the wait was interrupted
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ioctl_str
ios1:	mov	al,cs:[si]
	test	al,al			; end of string?
	jz	ios9			; yes (carry clear)
	push	si
	call	ioctl_out
	pop	si
	jc	ios9
	inc	si
	jmp	ios1
ios9:	ret
ENDPROC	ioctl_str

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ioctl_out
;
; Outputs a byte on behalf of an IOCTL request, waiting for room in the
; output buffer if necessary.
;
; Inputs:
;	AL = byte
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if the wait was interrupted
;
; Modifies:
;	BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ioctl_out
iot1:	call	push_output
	jnc	iot9
	push	ax
	call	add_packet		; wait for the output buffer to drain
	pop	ax
	jnc	iot1
iot9:	ret
ENDPROC	ioctl_out

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; update_col
;
; Updates the context's current column (CT_COL) and copy of the current line
; (CT_LINE) for a byte just written, using the same display rules as get_len
; (and the CON driver).  CR resets the column, BACKSPACE (which is destructive;
; see write_context) erases the previous column, LINEFEED starts a new (empty)
; line without changing the column, and BELL changes nothing.
;
; Inputs:
;	AL = byte
;	ES = context
;
; Outputs:
;	None
;
; Modifies:
;	AH
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	update_col
	push	bx
	mov	bl,es:[CT_COL]
	mov	bh,0			; BX = current column
	cmp	al,CHR_RETURN
	jne	uc1
	mov	bl,0
	jmp	short uc8
uc1:	cmp	al,CHR_LINEFEED
	jne	uc2
	mov	es:[CT_LLEN],0		; the new line is empty
	jmp	short uc9
uc2:	cmp	al,CHR_BACKSPACE
	jne	uc3
	sub	bl,1
	adc	bl,0			; don't go below zero
	mov	ah,CHR_SPACE
	call	put_line		; the previous column is now blank
	jmp	short uc8
uc3:	cmp	al,CHR_CTRLG		; BELL?
	je	uc9
	cmp	al,CHR_TAB
	jne	uc4
	or	bl,07h			; advance to the next multiple of 8
	inc	bl
	jmp	short uc8
uc4:	mov	ah,al
	cmp	al,CHR_SPACE		; CONTROL character?
	jae	uc5			; no
	mov	ah,'^'			; yes, presumably displayed as "^" + char
	call	put_line
	inc	bl
	mov	ah,al
	add	ah,'@'
uc5:	call	put_line
	inc	bl
uc8:	mov	es:[CT_COL],bl
uc9:	pop	bx
	ret
ENDPROC	update_col

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_line
;
; Stores a character in CT_LINE at the specified column (if it's within
; LINE_MAX), filling any gap beyond the current line length with spaces.
;
; Inputs:
;	AH = character
;	BX = column
;	ES = context
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	put_line
	cmp	bx,LINE_MAX
	jae	pt9
	push	cx
	push	si
	mov	cl,es:[CT_LLEN]
	mov	ch,0			; CX = current line length
pt1:	cmp	cx,bx			; is there a gap before the column?
	jae	pt2			; no
	mov	si,cx
	mov	es:[CT_LINE][si],CHR_SPACE
	inc	cx
	jmp	pt1
pt2:	mov	es:[CT_LINE][bx],ah
	cmp	cx,bx			; did the line get longer?
	ja	pt3			; no
	mov	cx,bx
	inc	cx
	mov	es:[CT_LLEN],cl
pt3:	pop	si
	pop	cx
pt9:	ret
ENDPROC	put_line

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
	jnc	dco1b
	jmp	dco7			; invalid parameter (eg, terminal type)
dco1b:	push	ax			; save output buffer length
	push	bx			; save parity and terminal type
	push	cx			; save baud rate
	add	ax,si			; AX = output + input buffer lengths
	add	ax,size CONTEXT + 15
	mov	cl,4
	shr	ax,cl
	xchg	bx,ax			; BX = required length, in paras
	mov	ax,DOS_MEM_ALLOC SHL 8
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
	pop	ax			; restore parity (BH) and terminal (BL)
	mov	dl,al			; DL = terminal type
	mov	al,1
	xchg	al,ah
	stosw				; set CT_PARITY and CT_REFS
	sub	ax,ax
	IFDEF DEBUG
	mov	ah,SIG_CT
	ENDIF
	stosw				; set CT_STATUS and CT_SIG
	mov	al,0
	mov	ah,dl
	stosw				; set CT_COL and CT_TERM
	sub	ax,ax
	stosw				; set CT_LLEN and CT_RSVD
	mov	ax,0707h
	stosw				; set CT_COLOR (same default as CON)
	add	di,LINE_MAX		; skip CT_LINE

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
	jcxz	ddi2			; no context
;	jc	ddi2			; carry set if DOS not ready

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
	jne	ddi3			; no
	call	push_input
	jmp	short ddi4
;
; Unlike the CONSOLE and CLOCK$ drivers' hardware interrupt handlers,
; which simply piggy-back on existing BIOS hardware interrupt handlers,
; we're on our own here.  So we must make sure our handler always EOIs
; the interrupt, even if the system isn't ready to process interrupts yet.
;
ddi2:	mov	al,20h			; EOI the interrupt to ensure
	out	20h,al			; we don't block other interrupts
	jmp	short ddi10

ddi3:	cmp	al,IIR_INT_THR		; transmitter ready?
	jne	ddi4			; no
	call	pull_output

ddi4:	mov	al,20h			; EOI the interrupt now
	out	20h,al

	mov	cx,cs
	mov	es,cx
	mov	bx,offset wait_ptr	; CX:BX -> ptr
	les	di,es:[bx]		; ES:DI -> packet, if any

ddi5:	cmp	di,-1			; end of chain?
	je	ddi9			; yes

	ASSERT	STRUCT,es:[di],DDP

	cmp	es:[di].DDP_CMD,DDC_READ; READ packet?
	je	ddi6			; yes, look for buffered data
;
; For WRITE packets (which we'll assume this is for now), we need to end the
; wait if the context is no longer busy (ie, neither full nor paused).
;
	ASSERT	STRUCT,ds:[0],CT
	test	ds:[CT_STATUS],CTSTAT_XMTFULL OR CTSTAT_PAUSED
	jz	ddi7			; transmitter is no longer busy
	jmp	short ddi8		; still busy, check next packet

ddi6:	call	pull_input		; pull more input data
	jc	ddi8			; not enough data, check next packet
;
; Notify DOS that this packet is done waiting.
;
ddi7:	and	ds:[CT_STATUS],NOT CTSTAT_INPUT
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	DOSUTIL	ENDWAIT
;
; If ENDWAIT returns an error, it's because the wait was interrupted (eg, by
; ABORT or CTRLC) before we could end it; add_packet will see that the packet
; has been removed and treat the request as satisfied.  In the past, it could
; also mean that we got ahead of the WAIT call, but that race was resolved by
; making the pull_input/add_packet/wait path atomic (ie, no interrupts).
;
; TODO: Consider lighter-weight solutions to this race condition.
;
; In any case, proceed with the packet removal now.
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

ddi8:	lea	bx,[di].DDP_PTR		; update prev addr ptr in CX:BX
	mov	cx,es

	les	di,es:[di].DDP_PTR
	jmp	ddi5

ddi9:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	bx

ddi10:	pop	ax
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
;	Carry clear if the packet was satisfied, set if the wait was interrupted
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
	jnc	ap9
;
; The wait was interrupted (eg, by ABORT or CTRLC), so the packet must be
; removed from the chain.  However, if it's no longer on the chain, then our
; interrupt handler satisfied it after all, so treat that as success.
;
	call	remove_packet		; carry clear if packet removed
	cmc				; carry set if packet removed
ap9:	pop	dx
	sti
	ret
ENDPROC	add_packet

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
	push	cs
	pop	ds
	mov	bx,offset wait_ptr	; DS:BX -> first link
	mov	cx,es			; CX:DI -> packet to remove
	pushf
	cli
rp1:	mov	ax,[bx].OFF
	cmp	ax,-1			; end of chain?
	je	rp8			; yes, packet not found
	cmp	ax,di
	jne	rp2
	cmp	[bx].SEG,cx
	je	rp3
rp2:	lds	bx,dword ptr [bx]	; DS:BX -> next packet
	lea	bx,[bx].DDP_PTR		; DS:BX -> its link
	jmp	rp1
rp3:	mov	ax,es:[di].DDP_PTR.OFF	; unlink the packet
	mov	[bx].OFF,ax
	mov	ax,es:[di].DDP_PTR.SEG
	mov	[bx].SEG,ax
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
; get_parms
;
; Inputs:
;	DS:SI -> parameter string:
;	[baud],[parity],[databits],[stopbits],[terminal],[inbuflen],[outbuflen]
;
; where [terminal] is optional and must be a name from TERM_NAMES.  Parsing
; stops at the end of the string, and any missing values use their defaults.
;
; Outputs:
;	If carry clear:
;	CX = baud rate
;	BH = parity indicator (unvalidated; should be one of 'N', 'O', or 'E')
;	BL = terminal type (TERM_*)
;	DL = data bits
;	DH = stop bits
;	SI = input buffer length
;	AX = output buffer length
;	If carry set, the terminal type was not recognized
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
;
; ATOI16 advances SI past the delimiter following a number, so whenever that
; delimiter wasn't a comma, we've reached the end of the parameters.
;
	mov	ax,TERM_ANSI		; AX = default terminal type
	cmp	byte ptr [si-1],','	; any more parameters?
	jne	gp1			; no
	call	get_term		; AX = terminal type, if any
	jc	gp9			; unrecognized terminal type
gp1:	push	ax			; save terminal type
	mov	ax,es:[di]		; AX = default input buffer length
	cmp	byte ptr [si-1],','	; any more parameters?
	jne	gp2			; no
	DOSUTIL	ATOI16			; AX = input buffer length
	sub	di,6			; use the input limits for output, too
gp2:	push	ax			; save input buffer length
	mov	ax,es:[di]		; AX = default output buffer length
	cmp	byte ptr [si-1],','	; any more parameters?
	jne	gp3			; no
	DOSUTIL	ATOI16			; AX = output buffer length
gp3:	pop	si			; SI = input buffer length
	pop	di			; DI = terminal type
	xchg	ax,di			; AL = terminal type, DI = output length
	mov	bl,al			; BL = terminal type
	xchg	ax,di			; AX = output buffer length
	clc
gp9:	pop	es
	pop	di
	ret
ENDPROC	get_parms

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_term
;
; If the next parameter begins with a letter, it must be one of the terminal
; type names in TERM_NAMES (in upper or lower case).
;
; Inputs:
;	DS:SI -> next parameter
;
; Outputs:
;	If carry clear, AX = terminal type (default if no name), and if there
;	was a name, SI is advanced past it and its delimiter (like ATOI16);
;	carry set if the name was not recognized
;
; Modifies:
;	AX, SI
;
DEFPROC	get_term
	mov	ax,TERM_ANSI
	mov	ah,[si]
	and	ah,0DFh			; convert to upper-case
	cmp	ah,'A'			; does parameter begin with a letter?
	jb	gt8			; no
	cmp	ah,'Z'
	ja	gt8			; no
	push	bx
	push	di
	mov	di,offset TERM_NAMES	; CS:DI -> terminal names
	sub	bx,bx			; BX = terminal type
gt1:	push	si
gt2:	mov	al,[si]
	cmp	al,'a'
	jb	gt3
	cmp	al,'z'
	ja	gt3
	sub	al,20h			; convert to upper-case
gt3:	mov	ah,cs:[di]
	inc	di
	test	ah,ah			; end of name?
	jz	gt4			; yes
	cmp	al,ah
	jne	gt5			; mismatch
	inc	si
	jmp	gt2
gt4:	cmp	al,','			; name must be followed by a comma
	je	gt6
	cmp	al,CHR_SPACE		; or the end of the string (NUL, or any
	jae	gt5			; other CONTROL char, eg, CR or LF)
gt6:	pop	ax			; discard saved SI
	inc	si			; advance SI past the delimiter
	xchg	ax,bx			; AX = terminal type
	pop	di
	pop	bx
gt8:	clc
	ret

gt5:	pop	si			; restore SI
gt5a:	test	ah,ah			; skip remainder of the name
	jz	gt5b
	mov	ah,cs:[di]
	inc	di
	jmp	gt5a
gt5b:	inc	bx			; advance terminal type
	cmp	byte ptr cs:[di],0	; end of TERM_NAMES?
	jne	gt1			; no
	pop	di
	pop	bx
	stc
	ret
ENDPROC	get_term

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
; This is also where we check for hotkeys, similar to check_hotkey in the
; CON driver, since a serial context may be serving as a console (eg, when
; CONFIG.SYS contains "CONSOLE=COM1:9600,N,8,1").
;
; CTRLS toggles the context's PAUSED state (unless the context is waiting for
; input, in which case CTRLS is passed through, because the CONIO buffered
; input code uses it for input control), and while paused, any other byte
; (eg, CTRLQ) ends the pause and is consumed.
;
; CTRLC also ends any pause, discards any buffered input (as does the CON
; driver), and is then delivered to DOS as a HOTKEY notification rather than
; as data, since the DOS CTRLC processing only removes CTRLC from the input
; stream of DDATTR_STDIN devices.
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	push_input
	call	read_rbr		; AL = received byte
	ASSERT	STRUCT,ds:[0],CT
	cmp	al,CHR_CTRLC		; CTRLC?
	je	psi6			; yes
	test	ds:[CT_STATUS],CTSTAT_INPUT
	jnz	psi3			; waiting for input, so no PAUSE checks
	cmp	al,CHR_CTRLS		; CTRLS?
	jne	psi2			; no (anything else unpauses)
	xor	ds:[CT_STATUS],CTSTAT_PAUSED
	jmp	short psi5
psi2:	test	ds:[CT_STATUS],CTSTAT_PAUSED
	jz	psi3
	and	ds:[CT_STATUS],NOT CTSTAT_PAUSED
	jmp	short psi5

psi3:	mov	si,offset CT_INPUT
	call	push_buffer
	jc	psi8
	mov	[bx],al
	jmp	short psi9
;
; CTRLC detected: discard buffered input, end any pause, and notify DOS.
;
psi6:	mov	si,offset CT_INPUT
	cli
	mov	bx,[si].BUFTAIL
	mov	[si].BUFHEAD,bx
	and	ds:[CT_STATUS],NOT CTSTAT_RCVOVFL
	sti
	test	ds:[CT_STATUS],CTSTAT_PAUSED
	jz	psi7
	and	ds:[CT_STATUS],NOT CTSTAT_PAUSED
	call	resume_output
psi7:	push	cx
	mov	cx,ds			; CX = context
	mov	dx,CHR_CTRLC		; DL = char code, DH = scan code (none)
	DOSUTIL	HOTKEY			; notify DOS
	pop	cx
	jmp	short psi9
;
; PAUSE state changed; if we're no longer paused, resume output.
;
psi5:	test	ds:[CT_STATUS],CTSTAT_PAUSED
	jnz	psi9
	call	resume_output
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
; If the context is paused, nothing is transmitted; resume_output restarts
; transmission when the pause ends.
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
	test	ds:[CT_STATUS],CTSTAT_PAUSED
	stc
	jnz	plo9			; paused, so transmit nothing
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
; resume_output
;
; Called when a pause ends.  Since pull_output transmits nothing while paused,
; any THR interrupt that occurred during the pause was lost, so if the
; transmitter is available, we must "prime the pump" again.
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	resume_output
	cli
	call	read_lsr
	test	al,LSR_THRE		; is the transmitter available?
	jz	rso9			; no, so a THR interrupt is still due
	call	pull_output
rso9:	sti
	ret
ENDPROC	resume_output

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
	cmp	al,CHR_BACKSPACE	; BACKSPACE?
	je	wct2			; yes
	call	push_output
wct1:	pop	ds
	pop	si
	pop	dx
	pop	bx
	ret
;
; Like the CON driver, we treat a BACKSPACE written as data as "destructive"
; (the DOS line editor relies on that to erase characters; see con_erase), so
; it's sent as BACKSPACE, SPACE, BACKSPACE.  To avoid sending a partial sequence
; (which would be repeated when the write is retried), we don't start unless
; there's room for all of it.  Note that IOCTL_MOVCUR sends BACKSPACEs directly
; (see move_cur), since those are only supposed to move the cursor.
;
wct2:	push	ax
	call	output_room		; AX = free bytes in output buffer
	cmp	ax,3
	pop	ax
	jae	wct3
	or	ds:[CT_STATUS],CTSTAT_XMTFULL
	stc
	jmp	wct1
wct3:	call	push_output		; BACKSPACE
	mov	al,CHR_SPACE
	call	push_output		; SPACE
	mov	al,CHR_BACKSPACE
	call	push_output		; BACKSPACE
	jmp	wct1
ENDPROC	write_context

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; output_room
;
; Inputs:
;	DS = context
;
; Outputs:
;	AX = number of free bytes in CT_OUTPUT
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	output_room
	mov	ax,ds:[CT_OUTPUT].BUFHEAD
	sub	ax,ds:[CT_OUTPUT].BUFTAIL
	dec	ax			; AX = HEAD - TAIL - 1
	jge	or9			; no wrap
	add	ax,ds:[CT_OUTPUT].BUFEND
	sub	ax,ds:[CT_OUTPUT].BUFOFF
or9:	ret
ENDPROC	output_room

	DEFLBL	COM1_END

CODE	ends

CODE2	segment para public 'CODE'

	public	COM2
	DEFLEN	COM2_LEN,<COM2>
	DEFLEN	COM2_INIT,<COM2,COM3,COM4>
COM2	DDH	<COM2_LEN,,DDATTR_CHAR,COM2_INIT,ddcom_int2,20202020324D4F43h>
;
; Every COM driver instance must define the next group of variables in
; the same location/order as shown below.
;
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
;
; Every COM driver instance must define the next group of variables in
; the same location/order as shown below.
;
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
;
; Every COM driver instance must define the next group of variables in
; the same location/order as shown below.
;
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
