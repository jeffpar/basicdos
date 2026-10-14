;
; BASIC-DOS 8250 UART Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

;
; Register offsets from the UART's base port, and their bits.
;
REG_DLL		equ	0	; Divisor Latch LSB (write when DLAB set)
REG_THR		equ	0	; Transmitter Holding Register (write)
REG_RBR		equ	0	; Receiver Buffer Register (read-only)

REG_IER		equ	1	; Interrupt Enable Register
IER_RBR_AVAIL	equ	01h
IER_THR_EMPTY	equ	02h
IER_DELTA	equ	04h
IER_MSR_DELTA	equ	08h
IER_UNUSED	equ	0F0h	; always zero

REG_IIR		equ	2	; Interrupt ID Register (read-only)
IIR_NO_INT	equ	01h
IIR_INT_LSR	equ	06h	; Line Status (highest priority: overrun,
				; parity, or framing error, or BREAK)
IIR_INT_RBR	equ	04h	; Receiver Data Available
IIR_INT_THR	equ	02h	; Transmitter Holding Register Empty
IIR_INT_MSR	equ	00h	; Modem Status Register (lowest priority: CTS,
				; DSR, RI, or DCD)
IIR_INT_BITS	equ	06h
IIR_UNUSED	equ	0F8h	; always zero (the ROM BIOS relies on these
				; bits "floating to 1" when there's no UART)

REG_LCR		equ	3	; Line Control Register
LCR_DATA5	equ	00h
LCR_DATA6	equ	01h
LCR_DATA7	equ	02h
LCR_DATA8	equ	03h
LCR_STOP	equ	04h	; clear: 1 stop bit; set: 1.5 stop bits for
				; LCR_DATA5, 2 stop bits for all other lengths
LCR_PARITY	equ	08h	; set: parity bit inserted/expected between the
				; last data bit and the first stop bit
LCR_PARITY_EVEN	equ	10h	; set: even parity; clear: odd parity
LCR_PARITY_INV	equ	20h	; set: parity bit is transmitted inverted
LCR_BREAK	equ	40h	; set: SOUT is forced to logical 0
LCR_DLAB	equ	80h	; Divisor Latch Access Bit

REG_MCR		equ	4	; Modem Control Register
MCR_DTR		equ	01h	; DTR high: ready to establish link
MCR_RTS		equ	02h	; RTS high: ready to exchange data
MCR_OUT1	equ	04h	; OUT1 high (looped back to RI)
MCR_OUT2	equ	08h	; OUT2 high (required to enable interrupts)

REG_LSR		equ	5	; Line Status Register
LSR_DR		equ	01h	; Data Ready (cleared when RBR read)
LSR_OE		equ	02h	; Overrun Error (cleared when LSR read)
LSR_PE		equ	04h	; Parity Error (cleared when LSR read)
LSR_FE		equ	08h	; Framing Error (cleared when LSR read)
LSR_BI		equ	10h	; Break Interrupt (cleared when LSR read)
LSR_THRE	equ	20h	; Transmitter Holding Register Empty
LSR_TSRE	equ	40h	; Transmitter Shift Register Empty
LSR_UNUSED	equ	80h	; always zero

REG_MSR		equ	6	; Modem Status Register
MSR_DCTS	equ	01h	; CTS has changed since last read
MSR_DDSR	equ	02h	; DSR has changed since last read
MSR_TERI	equ	04h	; RI has changed from 1 to 0
MSR_DRLSD	equ	08h	; RLSD has changed since last read
MSR_CTS		equ	10h	; Clear To Send
MSR_DSR		equ	20h	; Data Set Ready
MSR_RI		equ	40h	; Ring Indicator
MSR_RLSD	equ	80h	; Received Line Signal Detect
