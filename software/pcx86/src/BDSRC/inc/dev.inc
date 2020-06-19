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
; NOTE: While our drivers use traditional DOS driver headers and packets,
; our interfaces are a bit simpler: in place of the STRATEGY handler, we have
; a REQUEST handler, which performs the functions of both the STRATEGY and
; INTERRUPT handlers (we currently have no use for the INTERRUPT handler).
;
; I appreciate that the DOS driver model was apparently designed to enable some
; form of future multitasking, bit the fact virtually no driver was ever really
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

;
; Device driver packets, starting with the 13-byte packet header (DDP)
;
DDP		struc
DDP_LEN		db	?	; 00h: length of packet
DDP_UNIT	db	?	; 01h: unit # (block devices only)
DDP_CMD		db	?	; 02h: command #
DDP_STATUS	dw	?	; 03h: status
DDP_RESERVED	db	?	; 05h (holds DDPSIG in DEBUG builds)
DDP_CONTEXT	dw	?	; 06h: device context, if any
DDP_PTR		dd	?	; 08h: optional driver-specific pointer
DDP_UNUSED	db	?	; 0Ch
DDP		ends

DDPSIG		equ	'D'

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
; Device driver packet for the INIT command
;
DDPI		struc
DDPI_HDR	db	size DDP dup(?)
DDPI_UNITS	db	?	; 0Dh: # of units (ie, drives)
DDPI_END	dd	?	; 0Eh: end of driver
DDPI_BPBPTR	dd	?	; 12h: not used
DDPI_BLKDEV	db	?	; 16h: not used
DDPI		ends

;
; MEDIACHK values returned in the CONTEXT field
;
MC_UNCHANGED	equ	1
MC_UNKNOWN	equ	0
MC_CHANGED	equ	-1

;
; Device driver packet for IOCTL/READ/WRITE/MEDIACHK/BUILDBPB commands
;
DDPRW		struc
DDPRW_HDR	db	size DDP dup(?)
DDPRW_ID	db	?	; 0Dh: media ID (for block devices)
DDPRW_ADDR	dd	?	; 0Eh: transfer address
DDPRW_LBA	dw	?	; 12h: starting sector number
DDPRW_OFFSET	dw	?	; 14h: starting offset within sector
DDPRW_LENGTH	dw	?	; 16h: transfer length (in bytes)
DDPRW_BPB	dd	?	; 18h: pointer to BPB
DDPRW		ends

DDP_MAXSIZE	equ	((size DDPRW + 1) AND 0FFFEh)

;
; Public IOCTL operations for assorted devices
;
CLKIO_WAIT	equ	1	; wait # ticks in DDPRW_ADDR field

;
; Helper macro to define the overall length of a device driver;
; especially helpful when the driver includes headers for multiple devices
; that share a common INIT handler.
;
DEFLEN	macro	symbol,vars,add
symbol	=	0
	IRP	var,<vars>
symbol 	=	symbol + (((var&&_end - &&var) + 15) AND 0FFF0h)
	ENDM
	IFNB	<add>
symbol	=	symbol + add
	ENDIF
	endm
