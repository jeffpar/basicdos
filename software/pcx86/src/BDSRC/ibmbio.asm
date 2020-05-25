	include	driver.inc

CODE    segment

        ASSUME	CS:CODE, DS:BIOS_DATA, ES:BIOS_DATA, SS:NOTHING

	jmp	init
;
; Put device drivers here
;

BIOS_CODE_END	equ	$

;
; Initialization inputs:
;
;	AX -> offset of boot.asm "find" code
;	DX == LBA of DIR_SECTOR
; 	SI -> BPB_ACTIVE
;	DS and ES == BIOS_DATA
;
; We start by switching to a safer stack (better than 30:100h anyway).
;
init	proc	far
	push	ds
	pop	ss
	mov	sp,offset BIOS_STACK
	ASSUME	SS:BIOS_DATA
;
; Call the "find" code in boot.asm now (at 0000:AX), with these inputs:
;
; 	BX -> filename
;	DX == LBA of DIR_SECTOR
;	SI -> BPB_ACTIVE
;	DI -> DIR_SECTOR
;	BP == target load address
;
	mov	bp,BIOS_DATA_END
	add	bp,offset BIOS_CODE_END
	add	bp,15			; get next para after BIOS_CODE_END
	and	bp,0FFF0h		; BIOS_DATA:BP -> memory to load
	mov	bx,bp
	mov	cl,4
	shr	bx,cl
	push	bx			; convert BP to a SEG:0 address
	sub	cx,cx			; that the "find" code will return to
	push	cx
	push	cx			; far address of "find" (BIOS_DATA:AX)
	push	ax
	mov	bx,BIOS_DATA_END
	add	bx,offset DOS_FILE	; BIOS_DATA:BX -> filename
	mov	di,offset DIR_SECTOR	; BIOS_DATA:DI -> DIR_SECTOR
	ret
init	endp

;
; Initialization strings
;
DOS_FILE	db	"IBMDOS  COM",0

CODE	ends

	end
