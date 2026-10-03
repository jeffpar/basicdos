;
; BASIC-DOS Device Driver Initialization Code
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	disk.inc
	include	dev.inc
	include	devapi.inc

DEV	segment para public 'CODE'

;
; Because this is the last module appended to DEV_FILE, we must include
; a fake device header, so that the BOOT code will stop looking for drivers.
; It must also be a DWORD, because the BOOT code assumes that our entry
; point is CS:0004.
;
	DEFWORD	EOD,-1
	db	OP_IRET,OP_NOP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Device driver initialization
;
; Entry:
;	DI = end of drivers (start is BIOS_END)
;	DS:SI -> boot BPB, followed by DEV_FILE, DOS_FILE, and CFG_FILE info
;	far return address on stack -> boot code's part3
;
; Exit:
;	DI = new end of drivers
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
        ASSUME	CS:DEV, DS:BIOS, ES:BIOS, SS:NOTHING

DEFPROC	devinit,far
;
; Runtime driver ASSERTs may trigger INT_UD interrupts that we don't want to
; crash (the original IBM PC did NOT initialize all the low interrupt vectors),
; so install a temporary INT_UD handler; sysinit will initialize it properly.
;
;	DBGBRK
	IFDEF	DEBUG
	mov	word ptr [IVT+INT_UD*4].OFF,offset devinit - 2
	mov	word ptr [IVT+INT_UD*4].SEG,cs
	ENDIF	; DEBUG
;
; Perform some preliminary BIOS data initialization; in particular,
; DDINT_ENTER and DDINT_LEAVE entry points for hardware interrupt handlers,
; and the DDINT_UTIL entry point for driver WAIT and ENDWAIT requests.
;
	mov	word ptr [DDINT_ENTER],(OP_RETF SHL 8) OR OP_STC
	mov	[DDINT_LEAVE],OP_IRET
	mov	word ptr [DDINT_UTIL],(OP_RETF SHL 8) OR OP_STC
	sub	ax,ax
	mov	[FDC_DEVICE].SEG,ax	; no FDC driver yet
	mov	[FDC_UNITS],al
	mov	[HDC_UNITS],al		; and no HDC volumes yet
;
; To honor any "SKIP=" line, we need CFG_FILE now, so we load it just beyond
; this code, using the boot code's read_file function (which is BOOT_RDFILE
; bytes past our return address); when we're done, we move it above where
; DOS_FILE will be loaded (see the end of this function), so the boot code
; doesn't have to read it again.
;
	push	di
	mov	di,offset devinit_end	; DI -> CFG_FILE buffer
	lea	bx,[si+BOOT_CFGFILE]	; BX -> CFG_FILE DIR info
	mov	cs:[cfg_info],bx
	cmp	[bx],al			; was CFG_FILE found?
	jne	d2			; no
	push	cs
	pop	es
	ASSUME	ES:NOTHING
	push	cs
	mov	ax,offset d1
	push	ax			; far return address -> d1
	mov	ax,offset DDINT_ENTER+1
	push	ax			; near return address -> RETF
	mov	bp,sp
	push	ds			; DS = segment of boot code (zero)
	mov	ax,[bp+8]		; AX = offset of part3
	add	ax,BOOT_RDFILE
	push	ax
	db	OP_RETF			; "call" read_file
d1:	mov	byte ptr cs:[di],0	; null-terminate the CFG_FILE data
	mov	ax,di
	sub	ax,offset devinit_end
	mov	cs:[cfg_size],ax
	inc	di
	mov	si,offset devinit_end	; look for "SKIP=" at the start of a line
d1a:	cmp	word ptr cs:[si],'KS'
	jne	d1b
	cmp	word ptr cs:[si+2],'PI'
	jne	d1b
	cmp	byte ptr cs:[si+4],'='
	jne	d1b
	add	si,5
	mov	cs:[skip_list],si	; CS:SI -> list of driver names
	jmp	short d2
d1b:	lods	byte ptr cs:[si]
	test	al,al			; end of CFG_FILE data?
	jz	d2			; yes
	cmp	al,CHR_LINEFEED
	jne	d1b
	jmp	d1a
d2:	mov	cs:[buf_off],di		; scratch buffer follows CFG_FILE data
	pop	di			; DI = end of drivers again
	push	ds
	pop	es
	ASSUME	ES:BIOS
;
; Initialize each device driver.
;
	mov	si,offset BIOS_END; DS:SI -> first driver
;
; Create a DDPI packet on the stack.
;
	sub	sp,DDP_MAXSIZE
	mov	bp,sp
	DBGINIT	STRUCT,[bp],DDP
	mov	word ptr [bp].DDP_LEN,size DDP
	mov	[bp].DDP_CMD,DDC_INIT
	mov	[bp].DDP_STATUS,0

i1:	cmp	si,di		; reached the end of drivers?
	jb	i2		; no
	jmp	i9		; yes
i2:	mov	dx,[si]		; DX = original size of this driver
	mov	ax,si
	mov	cl,4
	shr	ax,cl
	mov	[bp].DDPI_END.OFF,0
	mov	[bp].DDPI_END.SEG,ax
;
; Memory beyond the end of this code (and our copy of CFG_FILE) is free until
; we return, so it serves as a scratch buffer for any driver that needs one
; (eg, to read a hard disk's MBR).  Note that the end of all the drivers (DI)
; is where this code begins.
;
	mov	cx,cs:[buf_off]
	mov	[bp].DDPI_BUFPTR.OFF,cx
	mov	[bp].DDPI_BUFPTR.SEG,cs
	push	ss
	pop	es
	ASSUME	ES:NOTHING
	push	ax		; AX = segment of driver
	call	chk_skip	; is this driver on the SKIP list?
	jc	i2a		; yes (and DDPI_END is zero)
	mov	bx,bp		; ES:BX -> packet
	push	[si].DDH_REQUEST
;
; Just as in dev_request, we no longer force drivers to preserve all registers.
;
	push	dx
	push	si
	push	di
	push	bp
	push	ds

	call	dword ptr [bp-4]; far call to DDH_REQUEST

	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	ax		; toss DDH_REQUEST address

i2a:	sub	bx,bx
	mov	es,bx
	ASSUME	ES:BIOS
	mov	bx,[bp].DDPI_END.OFF
	add	bx,15
	and	bx,0FFF0h
;
; Whereas SI was the original (paragraph-aligned) address of the driver,
; and SI+DX was the end of the driver, SI+BX is the new end of driver. So,
; if DX == BX, there's nothing to move; otherwise, we need to move everything
; from SI+DX through DI to SI+BX, and update DX and DI (new end of drivers).
;
	cmp	dx,bx
	je	i4

	push	si
	mov	cx,di
	lea	di,[si+bx]	; DI = dest address
	add	si,dx		; SI = source address
	sub	cx,si
;
; If the driver *increased* its footprint, then we need to flip this move
; around (start at the high address and move down to low address); otherwise,
; we'll end up trashing some of the memory we're moving.
;
	sub	ax,ax
	cmp	di,si
	jb	i3
	mov	ax,cx
	add	ax,2		; AX = adjustment for DI after reverse move
	add	si,cx
	sub	si,2
	add	di,cx
	sub	di,2
	std
i3:	shr	cx,1
	rep	movsw
	add	di,ax		; DI = new end of drivers
	cld
	pop	si
	mov	dx,bx

i4:	pop	ax		; recover the driver segment
	test	dx,dx
	jz	i8		; jump if driver not required
	sub	cx,cx		; AX:CX -> driver header
;
; If this is the FDC driver (ie, the first block device), then we need to
; extract DDPI_UNITS from the request packet and update FDC_UNITS and
; FDC_DEVICE in the BIOS segment.  Similarly, the HDC driver (ie, the next
; block device) updates HDC_UNITS and HDC_SEG.
;
	test	[si].DDH_ATTR,DDATTR_CHAR
	jnz	i7
	push	ax
	cmp	[FDC_DEVICE].SEG,0	; FDC driver already found?
	jne	i5			; yes
	mov	[FDC_DEVICE].OFF,cx
	mov	[FDC_DEVICE].SEG,ax
	mov	al,[bp].DDPI_UNITS
	mov	[FDC_UNITS],al
	jmp	short i6
i5:	mov	[HDC_SEG],ax
	mov	al,[bp].DDPI_UNITS
	mov	[HDC_UNITS],al
i6:	pop	ax
;
; Link the driver into the chain.  I originally chained them in reverse:
;
;	xchg	[DD_LIST].OFF,cx
;	mov	[si].DDH_NEXT_OFF,cx
;	xchg	[DD_LIST].SEG,ax
;	mov	[si].DDH_NEXT_SEG,ax
;
; because it's simpler, but later decided to keep the list in memory order.
;
; In addition, I now store the next available segment in the SEG portion of
; the final driver pointer (-1 in the OFF portion still means end of list).
;
i7:	push	di
	lea	di,[DD_LIST]
i7a:	cmp	es:[di].DDH_NEXT_OFF,-1
	je	i7b
	les	di,es:[di]
	jmp	i7a
i7b:	mov	es:[di].DDH_NEXT_OFF,cx
	mov	es:[di].DDH_NEXT_SEG,ax
	mov	cl,4
	shr	bx,cl
	add	bx,ax
	mov	[si].DDH_NEXT_SEG,bx
	mov	[si].DDH_NEXT_OFF,-1
	pop	di

i8:	add	si,dx		; SI -> next driver, after adding original size
	jmp	i1

i9:	add	sp,DDP_MAXSIZE
;
; DOS_FILE will be loaded at the next paragraph (AX), so CFG_FILE belongs
; at the end of DOS_FILE (BX), rounded up to a whole cluster (since the boot
; code reads whole clusters), unless our copy is already above that.  Either
; way, we only move CFG_FILE up, so neither this code nor CFG_FILE can be
; overwritten, and then we record its offset (relative to DOS_FILE) and size
; in its DIR info, for the boot code to pass along.
;
	push	di
	push	ds
	pop	es			; ES = DS = BIOS (zero)
	mov	si,cs:[cfg_info]	; SI -> CFG_FILE DIR info
	mov	al,[si-BOOT_CFGFILE].BPB_CLUSSECS
	mov	ah,0
	mul	[si-BOOT_CFGFILE].BPB_SECBYTES
	dec	ax			; AX = bytes per cluster - 1
	mov	bx,[si-(size DIR_NAME)+4]
	add	bx,ax
	not	ax
	and	bx,ax			; BX = DOS_FILE size, in whole clusters
	lea	ax,[di+15]
	and	al,0F0h			; AX = DOS_FILE address
	add	bx,ax			; BX = end of DOS_FILE clusters
	mov	dx,cs
	mov	cl,4
	shl	dx,cl
	add	dx,offset devinit_end	; DX = address of our CFG_FILE copy
	mov	cx,cs:[cfg_size]	; CX = size of CFG_FILE
	mov	[si+4],cx
	cmp	bx,dx			; is the end of DOS_FILE above it?
	ja	i9a			; yes
	mov	bx,dx			; no, so leave CFG_FILE where it is
	jmp	short i9b
i9a:	push	si
	push	ds
	push	cs
	pop	ds
	ASSUME	DS:NOTHING
	mov	si,offset devinit_end - 1
	add	si,cx			; DS:SI -> last byte of CFG_FILE copy
	lea	di,[bx-1]
	add	di,cx			; ES:DI -> last byte of new location
	std
	rep	movsb			; move it up
	cld
	pop	ds
	ASSUME	DS:BIOS
	pop	si
i9b:	sub	bx,ax			; BX = CFG_FILE offset relative to DOS_FILE
	mov	[si+2],bx
	pop	di
	ret
ENDPROC	devinit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_skip
;
; Checks the driver's name against the "SKIP=" list (eg, "SKIP=CON,FPU$"),
; which is a list of driver names separated by commas.
;
; Inputs:
;	DS:SI -> driver header
;
; Outputs:
;	Carry set if the driver should be skipped, clear if not
;
; Modifies:
;	AX, BX, CX
;
DEFPROC	chk_skip
	push	di
	mov	di,cs:[skip_list]	; CS:DI -> list of names (zero if none)
	test	di,di
	jz	ck9			; no list (and carry is clear)
ck1:	push	si
	add	si,DDH_NAME		; DS:SI -> driver name
	mov	cx,size DDH_NAME
	mov	bl,0			; BL is zero as long as the names match
ck2:	mov	al,cs:[di]
	cmp	al,','
	je	ck4			; end of name
	cmp	al,' '
	jbe	ck4			; end of list (eg, space, CR, or null)
	inc	di
	jcxz	ck3			; listed name is too long
	dec	cx
	cmp	al,[si]
	je	ck2a
ck3:	mov	bl,1			; names don't match
ck2a:	inc	si
	jmp	ck2
ck4:	jcxz	ck5
ck4a:	cmp	byte ptr [si],' '	; rest of driver name must be blank
	je	ck4b
	mov	bl,1
ck4b:	inc	si
	loop	ck4a
ck5:	pop	si
	cmp	bl,1			; carry set if BL is zero (a match)
	jb	ck9
	inc	di			; skip the delimiter
	cmp	al,','			; more names?
	je	ck1			; yes
	clc
ck9:	pop	di
	ret
ENDPROC	chk_skip

	DEFWORD	skip_list,0		; offset of "SKIP=" list, if any
	DEFWORD	buf_off,0		; offset of scratch buffer
	DEFWORD	cfg_info,0		; offset of CFG_FILE DIR info
	DEFWORD	cfg_size,0		; size of CFG_FILE (zero if none)

devinit_end	label	byte

DEV	ends

	end
