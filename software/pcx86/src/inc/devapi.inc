;
; BASIC-DOS Device Driver Interfaces
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
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
; variable to store a single packet address), largely because they knew DOS
; would simply call their INTERRUPT handler immediately after calling their
; STRATEGY handler.
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

IOCTL_CON	equ	0D0h
IOCTL_GETDIM	equ	0D1h	; CON: get context dimensions
IOCTL_GETPOS	equ	0D2h	; CON: get cursor position
IOCTL_GETLEN	equ	0D3h	; CON: get displayed length of data
IOCTL_MOVCUR	equ	0D4h	; CON: move cursor by DDPRW_LENGTH positions
IOCTL_SETINS	equ	0D5h	; CON: set INSERT mode ON (CL=1) or OFF (CL=0)
IOCTL_SCROLL	equ	0D6h	; CON: scroll (or clear) interior of context
IOCTL_GETCOLOR	equ	0D7h	; CON: get fill (DL) and border (DH) colors
IOCTL_SETCOLOR	equ	0D8h	; CON: set fill (CL) and border (CH) colors
