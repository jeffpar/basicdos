	include	dev.inc

DEV	segment word public 'CODE'

	extrn	NUL:dword
	extrn	COM1:dword,COM2:dword,COM3:dword,COM4:dword
	extrn	LPT1:dword,LPT2:dword,LPT3:dword,LPT4:dword

        ASSUME	CS:DEV, DS:BIOS, ES:BIOS, SS:NOTHING

;;;;;;;;
;
; Driver initialization
;
; Everything after "init" will be recycled.
;
	public	init
init	proc	far
;
; The boot sector didn't set up a stack, so let's do that first.
;
	push	ds
	pop	ss
	mov	sp,offset BIOS_STACK
	ASSUME	SS:BIOS
;
; Save boot sector inputs we received.
;
	push	ax		; save offset of boot.asm "find"
	push	dx		; save LBA of sector in DIR_SECTOR
;
; Initialize the segments of all the device headers.
;
	mov	si,offset NUL
	push	cs
	pop	ds		; DS:SI -> NUL
	ASSUME	DS:DEV
i1:	mov	[si].DDH_NEXT.seg,cs
	lds	si,[si].DDH_NEXT
	ASSUME	DS:NOTHING
	cmp	si,-1
	jne	i1
	push	es
	pop	ds
	ASSUME	DS:BIOS
;
; Next, let's remove drivers for any devices that don't exist.
;
; For now, all this means is removing their headers from the chain.
;
	int 3
	mov	si,offset RS232_BASE
	mov	cx,8		; covers both RS232_BASE and PRINTER_BASE
	mov	bx,offset COMS
i2:	lodsw
	test	ax,ax
	jnz	i3
	call	remove		; remove device referenced by CS:BX
i3:	inc	bx
	inc	bx
	loop	i2
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

;;;;;;;;
;
; Remove driver referenced by CS:BX.
;
; Modifies: AX
;
remove	proc	near
	push	si
	push	ds
	mov	si,offset NUL
	push	cs
	pop	ds			; DS:SI -> NUL
	ASSUME	DS:NOTHING

r1:	mov	ax,[si].DDH_NEXT.off
	cmp	ax,-1
	je	r9
	cmp	ax,cs:[bx]		; target device?
	jne	r8			; no
	mov	ax,cs
	cmp	ax,[si].DDH_NEXT.seg	; same segment?
	jne	r8			; no
;
; Get DDH_NEXT from the next header and stuff it into this header.
;
	push	di
	push	es
	les	di,[si].DDH_NEXT
	les	di,es:[di]
	ASSUME	ES:NOTHING
	mov	[si].DDH_NEXT.off,di
	mov	[si].DDH_NEXT.seg,es
	pop	es
	ASSUME	ES:BIOS
	pop	di
	jmp	short r9

r8:	lds	si,[si].DDH_NEXT
	jmp	r1

r9:	pop	ds
	pop	si
	ret
remove	endp

COMS		dw	COM1,COM2,COM3,COM4
LPTS		dw	LPT1,LPT2,LPT3,LPT4

;
; Initialization strings
;
DOS_FILE	db	"IBMDOS  COM",0

DEV	ends

	end
