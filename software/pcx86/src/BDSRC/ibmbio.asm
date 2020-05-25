	include	driver.inc

CODE    segment

	org	0000h

        ASSUME	CS:CODE, DS:BIOS_DATA, ES:BIOS_DATA, SS:NOTHING

	jmp	init
;
; Put device drivers here
;

BIOS_CODE_END	equ	$

;
; Initialization inputs:
;
; 	SI -> BPB_ACTIVE
;	DX -> offset of boot.asm "find" code
;	DS and ES == BIOS_DATA
;
; We start by switching to a safer stack (better than 30:100h anyway).
;
init	proc	far
	push	ds
	pop	ss
	mov	sp,offset BIOS_STACK
	ASSUME	SS:BIOS_DATA
	mov	bx,BIOS_DATA_END
	add	bx,offset DOS_FILE	; BIOS_DATA:BX -> filename
	mov	di,offset DIR_SECTOR	; BIOS_DATA:DI -> DIR_SECTOR
	mov	ax,BIOS_DATA_END
	add	ax,offset BIOS_CODE_END
	add	ax,15			; get the next para after BIOS_CODE_END
	and	ax,0FFF0h		; truncate to para boundary
	mov	bp,ax			; BIOS_DATA:BP -> memory to load
	mov	cl,4
	shr	ax,cl
	push	ax			; convert BP to a seg:0 address
	sub	ax,ax			; that the "find" code will return to
	push	ax
;
; Call the "find" code in boot.asm now (at 0000:DX), with SI -> BPB_ACTIVE,
; BX -> filename to find (DOS_FILE), DI -> DIR_SECTOR, and BP -> memory to load.
;
	push	ax
	push	dx
	ret
init	endp

;
; Initialization strings
;
DOS_FILE	db	"IBMDOS  COM",0

CODE	ends

	end
