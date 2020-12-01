;
; BASIC-DOS Device Driver Interfaces
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

;
; Device Driver Header
;
; NOTE: While our drivers use traditional DOS driver headers and packets,
; our interfaces are a bit simpler: in place of a STRATEGY handler, we have
; a REQUEST handler, which performs the functions of both the STRATEGY and
; INTERRUPT handlers (we currently have no use for the INTERRUPT handler).
;
; I appreciate that the DOS driver model was designed to enable some form
; of future multitasking, but the fact virtually no driver was ever really
; written to support that made the whole exercise rather pointless.  Drivers
; rarely implemented a "request packet queue" (they typically used a global
; variable to store a single packet address), because they knew DOS would
; simply call their INTERRUPT handler immediately after calling their STRATEGY
; handler.
;
DDH		struc
DDH_NEXT_OFF	dw	?	; 00h: offset of next DDH (or FFFFh)
DDH_NEXT_SEG	dw	?	; 02h: segment of next DDH
DDH_ATTR	dw	?	; 04h: device attributes
DDH_REQUEST	dw	?	; 06h: request ("strategy") entry offset
DDH_INTERRUPT	dw	?	; 08h: unused ("interrupt") entry offset
DDH_NAME	dq	?	; 0Ah: device name (8 characters)
DDH		ends

DDATTR_STDIN	equ	0001h
DDATTR_STDOUT	equ	0002h
DDATTR_NUL	equ	0004h
DDATTR_CLOCK	equ	0008h
DDATTR_OPEN	equ	0800h	; understands open/close
DDATTR_IOCTL	equ	4000h	; set if device supports IOCTLs
DDATTR_CHAR	equ	8000h	; set if character device, clear if block
DDATTR_BLOCK	equ	0000h

;
; IOCTL operations for assorted devices
;
; Once again, our IOCTL interface is a simplification of what PC DOS
; eventually implemented.
;
IOCTL_CLOCK	equ	0C0h
IOCTL_WAIT	equ	0C1h	; CLOCK$: wait # ms in packet's LENGTH:OFFSET
IOCTL_SETDATE	equ	0C2h	; CLOCK$: set yr,mon,day from CL,DH,DL
IOCTL_SETTIME	equ	0C3h	; CLOCK$: set hr,min,sec,1/100 from CH,CL,DH,DL
IOCTL_GETDATE	equ	0C4h	; CLOCK$: get formatted date
IOCTL_GETTIME	equ	0C5h	; CLOCK$: get formatted time

IOCTL_CON	equ	0D0h
IOCTL_GETDIM	equ	0D1h	; CON: get context dimensions
IOCTL_GETPOS	equ	0D2h	; CON: get cursor position
IOCTL_GETLEN	equ	0D3h	; CON: get displayed length of data
IOCTL_MOVCUR	equ	0D4h	; CON: move cursor by DDPRW_LENGTH positions
IOCTL_SETINS	equ	0D5h	; CON: set INSERT mode ON (CL=1) or OFF (CL=0)
IOCTL_SCROLL	equ	0D6h	; CON: scroll (or clear) interior of context
IOCTL_GETCOLOR	equ	0D7h	; CON: get fill (DL) and border (DH) colors
IOCTL_SETCOLOR	equ	0D8h	; CON: set fill (CL) and border (CH) colors

;
; Character codes that we care about.
;
CHR_CTRLA	equ	01h
CHR_CTRLB	equ	02h
CHR_CTRLC	equ	03h
CHR_CTRLD	equ	04h	; alias for SCAN_RIGHT
CHR_CTRLE	equ	05h	; alias for SCAN_UP
CHR_CTRLF	equ	06h
CHR_CTRLG	equ	07h	; alias for CHR_DEL
CHR_BACKSPACE	equ	08h
CHR_TAB		equ	09h
CHR_LINEFEED	equ	0Ah
CHR_CTRLK	equ	0Bh	; alias for SCAN_F1 (aka VTAB)
CHR_CTRLL	equ	0Ch	; alias for SCAN_F3
CHR_RETURN	equ	0Dh
CHR_CTRLP	equ	10h
CHR_CTRLQ	equ	11h
CHR_CTRLR	equ	12h
CHR_CTRLS	equ	13h	; alias for SCAN_LEFT
CHR_CTRLT	equ	14h
CHR_CTRLU	equ	15h
CHR_CTRLV	equ	16h	; alias for SCAN_INS
CHR_CTRLW	equ	17h
CHR_CTRLX	equ	18h	; alias for SCAN_DOWN
CHR_CTRLY	equ	19h
CHR_CTRLZ	equ	1Ah
CHR_ESCAPE	equ	1Bh
CHR_SPACE	equ	20h
CHR_DQUOTE	equ	22h
CHR_SQUOTE	equ	27h
CHR_SLASH	equ	2Fh
CHR_LT		equ	3Ch
CHR_GT		equ	3Eh
CHR_BSLASH	equ	5Ch
CHR_DEL		equ	7Fh	; alias for SCAN_DEL
