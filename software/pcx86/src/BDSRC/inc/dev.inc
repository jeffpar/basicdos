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
DDH_NAME	dq	?	; 0Ah: device name
DDH		ends

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
DDP_RESERVED	db	8 dup(?); 04h: reserved
DDP		ends

;
; Device driver INIT packet
;
DDPI		struc
DDPI_HDR	db	13 dup(?)
DDPI_UNITS	db	?
DDPI_END	dd	?
DDPI_BPBPTR	dd	?
DDPI_BLKDEV	db	?
DDPI		ends

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
