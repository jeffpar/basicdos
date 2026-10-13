;
; BASIC-DOS Device Driver Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

;
; Device driver commands (see DDP_CMD)
;
DDC_INIT	equ	0	; Init
DDC_MEDIACHK	equ	1	; Media Check (block devices only)
DDC_BUILDBPB	equ	2	; Build BPB (block devices only)
DDC_IOCTLIN	equ	3	; IOCTL Input (only called if device has IOCTL)
DDC_READ	equ	4	; Input (Read)
DDC_NDREAD	equ	5	; Non-destructive Read, No Wait (char devices only)
DDC_INSTATUS	equ	6	; Input Status (char devices only)
DDC_INFLUSH	equ	7	; Input Flush (char devices only)
DDC_WRITE	equ	8	; Output (Write)
DDC_WRITEV	equ	9	; Output (Write) with Verify
DDC_OUTSTATUS	equ	10	; Output Status (char devices only)
DDC_OUTFLUSH	equ	11	; Output Flush (char devices only)
DDC_IOCTLOUT	equ	12	; IOCTL Output (only called if device has IOCTL)
DDC_OPEN	equ	13	; Device Open (only called if Open/Close/Removable Media bit set)
DDC_CLOSE	equ	14	; Device Close (only called if Open/Close/Removable Media bit set)
DDC_REMOVABLE	equ	15	; Removable Media (only called if Open/Close/Removable Media bit set and device is block)
DDC_OUTBUSY	equ	16	; Output Until Busy (only called if bit 13 is set on character devices)
DDC_GENIOCTL	equ	19	; Generic IOCTL Request
DDC_GETLOGDEV	equ	23	; Get Logical Device
DDC_SETLOGDEV	equ	24	; Set Logical Device

;
; Device driver packets, starting with the 13-byte packet header (DDP).
;
; Strangely, PC DOS defined only the first 5 bytes (through DDP_STATUS),
; leaving one to wonder what the other 8 bytes were used for.  BASIC-DOS
; puts them to good use, however.  For example, the DDP_CONTEXT field
; provides critical context (ie, session) information to our CONSOLE driver.
;
DDP		struc
DDP_LEN		db	?	; 00h: length of packet
DDP_UNIT	db	?	; 01h: unit # (block devices only)
DDP_CMD		db	?	; 02h: command # (see DDC_*)
DDP_STATUS	dw	?	; 03h: status
DDP_CODE	db	?	; 05h: sub-function code, if IOCTL
DDP_CONTEXT	dw	?	; 06h: device context, if any
DDP_PTR		dd	?	; 08h: optional driver-specific pointer
DDP_SIG		db	?	; 0Ch (holds SIG_DDP in DEBUG builds)
DDP		ends
SIG_DDP		equ	'D'

DDSTAT_ERROR	equ	8000h
DDSTAT_DONE	equ	0100h
DDSTAT_BUSY	equ	0200h
DDSTAT_ERRCODE	equ	00FFh

;
; Disk error codes are the BIOS (INT 13h) error codes, so that disk drivers
; can pass them through as-is; the remaining codes use values that the BIOS
; does not.
;
DDERR_BADCMD	equ	01h	; Bad (BIOS) command
DDERR_BADMARK	equ	02h	; Bad address mark
DDERR_WP	equ	03h	; Write protect violation
DDERR_NOSECTOR	equ	04h	; Sector not found
DDERR_UNKUNIT	equ	05h	; Unknown unit
DDERR_UNKCMD	equ	06h	; Unknown command
DDERR_BADREQ	equ	07h	; Bad drive request structure length
DDERR_DMAOVR	equ	08h	; DMA overrun
DDERR_DMA64K	equ	09h	; DMA (64K) boundary error
DDERR_UNKMEDIA	equ	0Ah	; Unknown media
DDERR_NOPAPER	equ	0Bh	; Printer out of paper
DDERR_GENFAIL	equ	0Ch	; General failure
DDERR_WRFAULT	equ	0Dh	; Write fault
DDERR_RDFAULT	equ	0Eh	; Read fault
DDERR_INVDSKCHG	equ	0Fh	; Invalid disk change
DDERR_CRC	equ	10h	; CRC error
DDERR_CTRL	equ	20h	; Controller failure
DDERR_SEEK	equ	40h	; Seek error
DDERR_NOTREADY	equ	80h	; Drive not ready (aka timeout)

;
; Device driver packet for the INIT command
;
DDPI		struc
DDPI_HDR	db	size DDP dup(?)
DDPI_UNITS	db	?	; 0Dh: # of units (ie, drives)
DDPI_END	dd	?	; 0Eh: end of driver
DDPI_BUFPTR	dd	?	; 12h: 512-byte scratch buffer (from devinit)
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
;
; The FDC driver's exports, which immediately follow its DDH, so that the HDC
; driver (which finds the FDC driver with FDC_DEVICE) can share its INT 13h
; code and sector buffer (see fdcdev.asm).  Each is the offset of a far entry.
;
FDCX		struc
FDCX_RW		dw	?	; read/write request at ES:DI (AL = BIOS drive)
FDCX_RDBUF	dw	?	; read LBA DX into FDC buffer (see fdc_rdbuf)
FDCX		ends
