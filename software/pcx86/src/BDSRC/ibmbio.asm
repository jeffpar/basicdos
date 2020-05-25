	include	dev.inc

DEV	segment word public 'CODE'

	extrn	NUL:near

        ASSUME	CS:DEV, DS:BIOS, ES:BIOS, SS:NOTHING
;
; Driver initialization
;
; Everything after "init" is discarded.
;
; The boot sector doesn't switch stacks, so let's do that first.
;
	public	init
init	proc	far
	push	ds
	pop	ss
	mov	sp,offset BIOS_STACK
	ASSUME	SS:BIOS
;
; Save boot sector inputs we received
;
	push	ax		; save offset of boot.asm "find"
	push	dx		; save LBA of sector in DIR_SECTOR
;
; Restore boot sector inputs, so we can load IBMDOS.COM next.
;
	pop	dx
	pop	ax
;
; Prepare to call the "find" code in boot.asm now (at 0000:AX).
;
; 	BX -> filename
;	DX == LBA of DIR_SECTOR
;	SI -> BPB_ACTIVE
;	DI -> DIR_SECTOR
;	BP == target load address
;
; Start with BP first, because we also need that for the "find" return address.
;
	push	cs			; push far address of first driver
	mov	bp,offset NUL
	push	bp
	mov	bp,BIOS_END		; now calulate IBMDOS load address
	add	bp,offset init
	add	bp,15			; get next para after init
	and	bp,0FFF0h		; BIOS:BP -> memory to load
	mov	bx,bp			; calculate corresponding BX:0 address
	mov	cl,4
	shr	bx,cl
	push	bx			; push BX:0 address
	sub	cx,cx			; as the "find" return address
	push	cx
	push	cx			; push far address of "find"
	push	ax
	mov	bx,BIOS_END		; set up "find" inputs and far return
	add	bx,offset DOS_FILE
	mov	si,offset BPB_ACTIVE
	mov	di,offset DIR_SECTOR
	ret
init	endp

;
; Initialization strings
;
DOS_FILE	db	"IBMDOS  COM",0

DEV	ends

	end
