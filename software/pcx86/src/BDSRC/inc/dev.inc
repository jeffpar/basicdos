;
; BASIC-DOS Device Driver Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	bios.inc
;
; Device driver header
;
DDH		struc
DDH_NEXT_OFF	dw	?	; 00h: offset of next DDH (or FFFFh)
DDH_NEXT_SEG	dw	?	; 02h: segment of next DDH
DDH_ATTR	dw	?	; 04h: device attributes
DDH_STRATEGY	dw	?	; 06h: strategy entry point
DDH_INTERRUPT	dw	?	; 08h: interrupt entry point
DDH_NAME	dq	?	; 0Ah: device name (8 characters)
DDH		ends

DDATTR_STDIN	equ	0001h
DDATTR_STDOUT	equ	0002h
DDATTR_NUL	equ	0004h
DDATTR_CLOCK	equ	0008h
DDATTR_OPEN	equ	0800h	; understands open/close
DDATTR_CHAR	equ	8000h	; set if character device, clear if block
DDATTR_BLOCK	equ	0000h

;
; Device driver packets, starting with the packet header (DDP)
;
DDP		struc
DDP_LEN		db	?	; 00h: length of packet
DDP_UNIT	db	?	; 01h: unit # (block devices only)
DDP_CMD		db	?	; 02h: command #
DDP_STATUS	dw	?	; 03h: status
DDP_RESERVED	db	?	; 05h (technically, next 8 bytes are reserved)
DDP_CONTEXT	dw	?	; 06h: device context, if any
DDP_PARMS	dd	?	; 08h (eg, OPEN parms)
DDP_UNUSED	db	?	; 0Ah
DDP		ends

DDSTAT_ERROR	equ	8000h
DDSTAT_DONE	equ	0100h
DDSTAT_BUSY	equ	0200h
DDSTAT_ERRCODE	equ	00FFh

DDERR_WP	equ	0	; Write protect violation
DDERR_UNKUNIT	equ	1	; Unknown unit
DDERR_NOTREADY	equ	2	; Drive not ready
DDERR_UNKCMD	equ	3	; Unknown command
DDERR_CRC	equ	4	; CRC error
DDERR_BADREQ	equ	5	; Bad drive request structure length
DDERR_SEEK	equ	6	; Seek error
DDERR_UNKMEDIA	equ	7	; Unknown media
DDERR_NOSECTOR	equ	8	; Sector not found
DDERR_NOPAPER	equ	9	; Printer out of paper
DDERR_WRFAULT	equ	10	; Write fault
DDERR_RDFAULT	equ	11	; Read fault
DDERR_GENFAIL	equ	12	; General failure
DDERR_INVDSKCHG	equ	15	; Invalid disk change

;
; Device driver packet for assorted READ/WRITE commands
;
DDPRW		struc
DDPRW_HDR	db	13 dup(?)
DDPRW_MEDIA_ID	db	?	; 0Dh: media ID byte
DDPRW_ADDR	dd	?	; 0Eh: transfer address
DDPRW_COUNT	dw	?	; 12h: transfer count
DDPRW_SECTOR	dw	?	; 14h: starting sector number
DDPRW_BPB	dd	?	; 16h: pointer to BPB
DDPRW		ends

;
; Device driver packet for the INIT command
;
DDPI		struc
DDPI_HDR	db	13 dup(?)
DDPI_UNITS	db	?
DDPI_END	dd	?
DDPI_BPBPTR	dd	?
DDPI_BLKDEV	db	?
DDPI		ends

DDP_MAXSIZE	equ	((size DDPI + 1) AND 0FFFEh)

;
; Device driver commands
;
DDC_INIT	equ	0	; Init
DDC_MEDIACHK	equ	1	; Media Check (Block devices only)
DDC_BUILDBPB	equ	2	; Build BPB (Block devices only)
DDC_IOCTLIN	equ	3	; IOCtl Input (Only called if device has IOCtl)
DDC_READ	equ	4	; Input (Read)
DDC_NDREAD	equ	5	; Non-destructive Read, No Wait (Character devices only)
DDC_INSTATUS	equ	6	; Input Status (Character devices only)
DDC_INFLUSH	equ	7	; Input Flush (Character devices only)
DDC_WRITE	equ	8	; Output (Write)
DDC_WRITEV	equ	9	; Output (Write) with Verify
DDC_OUTSTATUS	equ	10	; Output Status (Character devices only)
DDC_OUTFLUSH	equ	11	; Output Flush (Character devices only)
DDC_IOCTLOUT	equ	12	; IOCtl Output (Only called if device has IOCtl)
DDC_OPEN	equ	13	; Device Open (Only called if Open/Close/Removable Media bit set)
DDC_CLOSE	equ	14	; Device Close (Only called if Open/Close/Removable Media bit set)
DDC_REMOVABLE	equ	15	; Removable Media (Only called if Open/Close/Removable Media bit set and device is block)
DDC_OUTBUSY	equ	16	; Output Until Busy (Only called if bit 13 is set on character devices)
DDC_GENIOCTL	equ	19	; Generic IOCtl Request
DDC_GETLOGDEV	equ	23	; Get Logical Device
DDC_SETLOGDEV	equ	24	; Set Logical Device

DEFLEN	macro	symbol,vars,add
symbol	=	0
	IRP	var,<vars>
symbol 	=	symbol + (((var&&_end - &&var) + 15) AND 0FFF0h)
	ENDM
	IFNB	<add>
symbol	=	symbol + add
	ENDIF
	endm
