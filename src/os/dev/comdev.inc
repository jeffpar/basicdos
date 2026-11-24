;
; BASIC-DOS Physical (COM) Serial Device Driver Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The terminal and context definitions that the COM driver's modules
; (comdev.asm and comcon.asm) share.
;
TERM_ANSI	equ	0	; supports ANSI (VT100) cursor and erase sequences
TERM_GENERIC	equ	1	; supports only CR, LF, BACKSPACE, and TAB
TERM_VT100	equ	2	; ANSI, DELETE/BACKSPACE swapped, XON, wrap
TERM_COUNT	equ	3	; number of terminal types

VT100_SO	equ	0Eh		; "shift out" (selects G1)
VT100_SI	equ	0Fh		; "shift in" (selects G0)

TERM_COLS	equ	80	; assumed terminal dimensions (see CT_COLS)
TERM_ROWS	equ	24
WIDE_COLS	equ	132	; a VT100's columns in MODE_WIDE (see set_mode)
WIDE_ROWS	equ	14	; its rows there without the AVO (see rb6)

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
CT_ESC		db	?	; 0Fh: escape state (see raw_input)
CT_COLOR	dw	?	; 10h: fill (LO) and border (HI) attributes
CT_LINE		db	LINE_MAX dup (?); 12h: copy of the current output line
CT_INPUT	db	size RINGBUF dup (?)
CT_OUTPUT	db	size RINGBUF dup (?)
CT_SHADOW	dw	?	; shadow characters (a segment), if any
CT_ATTRS	dw	?	; shadow attributes (a segment), if any
CT_PARENT	dw	?	; console that it took the focus from
CT_PEND		dw	?	; console waiting for our focus, if any
CT_BACK		db	?	; non-zero if it doesn't have the focus
CT_BUSY		db	?	; # of IOCTLs in progress (see switch_to)
CT_NEXT		dw	?	; next console on the port (a ring)
CT_DRV		dw	?	; the port's data segment (for ct_seg)
CT_PAINT	db	4 dup (?) ; repaint state (see paint)
CT_TIMER	db	size TMR dup (?); timer for a held ESC (raw keys)
CT_ESCPARM	db	?	; escape sequence parameter (raw keys)
CT_ROW		db	?	; current output row (see update_col)
CT_TOP		db	?	; first scrolling row (see set_rows)
CT_BOT		db	?	; last scrolling row
CT_GFX		db	?	; VT100 character set (VT100_SO or VT100_SI)
CT_COLS		db	?	; current columns (TERM_COLS, half, or wide)
CT_ROWS		db	?	; current rows (TERM_ROWS, or CT_WROWS)
CT_WROWS	db	?	; rows in MODE_WIDE (TERM_ROWS or WIDE_ROWS)
CT_WIDE		db	TERM_ROWS+1 dup (?) ; zero if a row needs VT100_WIDE
CONTEXT		ends
SIG_CT		equ	'O'

CTSTAT_XMTFULL	equ	01h	; transmitter buffer full
CTSTAT_PAINT	equ	02h	; screen is being repainted (see paint)
CTSTAT_XON	equ	04h	; XON/XOFF flow control enabled (XON option)
CTSTAT_RTS	equ	08h	; RTS/CTS flow control enabled (RTS option)
CTSTAT_CTSOFF	equ	10h	; output held because CTS is low (RTS option)
CTSTAT_RAWKEYS	equ	20h	; hotkeys are just keys (see IOCTL_SETKEYS)
CTSTAT_INPUT	equ	40h	; context is waiting for input
CTSTAT_PAUSED	equ	80h	; context is paused (triggered by CTRLS hotkey)
;
; What makes a write wait (see ddcom_write and wake_packet), and what a
; context keeps when it loses the focus (see switch_to).
;
CTSTAT_BUSY	equ	CTSTAT_XMTFULL OR CTSTAT_PAUSED OR CTSTAT_PAINT
CTSTAT_KEEP	equ	NOT (CTSTAT_BUSY OR CTSTAT_CTSOFF)

