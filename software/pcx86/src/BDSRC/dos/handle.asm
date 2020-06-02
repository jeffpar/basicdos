;
; BASIC-DOS Handle Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<SFB_TABLE>,dword
	EXTERNS	<CUR_DRV>,byte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hdl_open (REG_AH = 3Dh)
;
; Inputs:
;	REG_AL = mode (see MODE_*)
;	REG_DS:REG_DX -> name of device/file
;
; Outputs:
;	On success, REG_AX = process file handle
;	On failure, REG_AX = error
;
DEFPROC	hdl_open,DOS
	mov	bl,[bp].REG_AL		; BL = mode
	mov	si,[bp].REG_DX		; DS:SI = name
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	call	sfb_open
	jc	ho9
;
; BX is the new (or possibly old) SFB address.  Convert to a process handle.
;
ho9:	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
	ret
ENDPROC	hdl_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_open
;
; Inputs:
;	BL = mode (see MODE_*)
;	DS:SI -> name of device/file
;
; Outputs:
;	On success, carry clear, BX = SFB address
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	sfb_open,DOS
	ASSUME	DS:NOTHING
	call	dev_chkname		; is it a device name?
	jnc	so1			; yes
	call	dsk_chkname		; is it a disk file name?
	jnc	so2
	jmp	short so9		; no

so1:	mov	al,DDC_OPEN		; ES:DI -> driver
	sub	dx,dx			; no initial context
	call	dev_request		; issue the DDC_OPEN request
	jc	so9			; failed
;
; When looking for a matching existing SFB, all we require is that both
; the device driver and device context match.  For files, the context will
; be the cluster number; for devices, the context is, um, the context, which
; dev_request returned in DX.
;
; However, we relax that *slightly* for the CON device, because the first
; CON device opened is considered the "system console", so any other CON
; device *without* context will use that same SFB.
;
; Traditionally, checking used SFBs means those with non-zero HANDLES count;
; however, our SFBs are also used IFF their DRIVER seg is non-zero, so there.
;
so2:	push	si
	push	ds
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	ax,es			; AX:DI is driver, DX is context
	mov	cl,bl			; save mode in CL
	mov	si,[SFB_TABLE].off
	sub	bx,bx			; use BX to remember a free SFB
so3:	cmp	[si].SFB_DRIVER.off,di
	jne	so4			; check next SFB
	cmp	[si].SFB_DRIVER.seg,ax
	jne	so4			; check next SFB
	test	dx,dx			; any context?
	jz	so6			; no, so consider this SFB a match
	cmp	[si].SFB_CONTEXT,dx	; context match?
	je	so6			; match
so4:	test	bx,bx			; are we still looking for a free SFB?
	jnz	so5			; no
	cmp	[si].SFB_DRIVER.seg,bx	; is this one free?
	jne	so5			; no
	mov	bx,si			; yes, remember it
so5:	add	si,size SFB
	cmp	si,[SFB_TABLE].seg
	jb	so3			; keep checking

	test	bx,bx			; was there a free SFB?
	jz	so7			; no, tell the driver sorry
	mov	[bx].SFB_DRIVER.off,di
	mov	[bx].SFB_DRIVER.seg,es
	mov	[bx].SFB_CONTEXT,dx
	mov	[bx].SFB_MODE,cl
	jmp	short so8		; return new SFB

so6:	mov	bx,si			; return matching SFB
	jmp	short so8

so7:	mov	al,DDC_CLOSE		; ES:DI -> driver, DX = context
	call	dev_request		; issue the DDC_CLOSE request
	mov	ax,ERR_MAXFILES
	stc				; return no SFB (and BX is zero)

so8:	pop	ds
	pop	si
	ASSUME	DS:NOTHING
so9:	ret
ENDPROC	sfb_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_write
;
; Inputs:
;	BX = SFB address
;	CX = byte count
;	DS:SI -> data to write
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, DX, DI, ES
;
DEFPROC	sfb_write,DOS
	ASSUME	DS:NOTHING
	mov	al,DDC_WRITE
	les	di,cs:[bx].SFB_DRIVER
	mov	dx,cs:[bx].SFB_CONTEXT
	call	dev_request		; issue the DDC_WRITE request
	ret
ENDPROC	sfb_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_chkname
;
; Inputs:
;	DS:SI -> name
;
; Outputs:
;	On success, ES:DI -> device driver header (DDH), DX = context
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	dsk_chkname,DOS
;
; See if the name begins with a drive letter.  If so, convert to a drive
; number and then skip over it; otherwise, use CURDRV as the drive number.
;
	push	si
	cmp	byte ptr [si+1],':'
	mov	dl,[CUR_DRV]		; DL = drive number
	jne	dskck1
	lodsb				; AL = drive letter
	sub	al,'A'
	jb	dskck9			; error
	cmp	al,26
	cmc
	jb	dskck9
	inc	si
	xchg	dx,ax			; DL = specified drive number
;
;
;
dskck1:	nop

dskck9:	pop	si
	ret
ENDPROC	dsk_chkname

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dev_chkname
;
; Inputs:
;	DS:SI -> name
;
; Outputs:
;	On success, ES:DI -> device driver header (DDH)
;
; Modifies:
;	AX, CX, DI, ES
;
DEFPROC	dev_chkname,DOS
	ASSUME	DS:NOTHING
	les	di,[DD_LIST]
	ASSUME	ES:NOTHING
devck1:	cmp	di,-1			; end of device list?
	stc
	je	devck9			; yes, search failed
	mov	cx,8
	push	si
	push	di
	add	di,DDH_NAME
	repe	cmpsb			; compare DS:SI to ES:DI
	je	devck8			; match
;
; This could still be a match if DS:[SI-1] is an "end of device name" character
; (eg, ':', '.', or ' ') and ES:[DI-1] is a space.
;
	mov	al,[si-1]
	cmp	al,':'
	je	devck2
	cmp	al,'.'
	je	devck2
	cmp	al,' '
	jne	devck8
devck2:	cmp	byte ptr es:[di-1],' '
devck8:	pop	di
	pop	si
	je	devck9			; jump if all our compares succeeded
	les	di,es:[di]		; otherwise, on to the next device
	jmp	devck1
devck9:	ret
ENDPROC	dev_chkname

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dev_request
;
; Inputs:
;	AL = device driver command (DDC)
;	DX = device driver context, zero if none
;	ES:DI -> device driver header (DDH)
;
; Outputs:
;	If carry set, then AL contains error code
;	If carry clear, then DX contains the context, if any
;
; Modifies:
;	AX, DX
;
DEFPROC	dev_request,DOS
	ASSUME	DS:NOTHING,ES:NOTHING
	push	bx
	push	bp
	sub	sp,DDP_MAXSIZE
	mov	bp,sp			; packet created on stack
	cmp	al,DDC_OPEN
	jne	dr2
	mov	word ptr [bp].DDP_LEN,size DDP
	mov	[bp].DDP_PARMS.off,si
	mov	[bp].DDP_PARMS.seg,ds
	jmp	short dr5

dr2:	mov	word ptr [bp].DDP_LEN,size DDPRW
	mov	[bp].DDPRW_ADDR.off,si
	mov	[bp].DDPRW_ADDR.seg,ds
	mov	[bp].DDPRW_COUNT,cx

dr5:	mov	[bp].DDP_CMD,AL
	mov	[bp].DDP_STATUS,0
	mov	[bp].DDP_CONTEXT,dx
	mov	bx,bp
	push	es
	push	es:[di].DDH_STRATEGY
	push	es
	push	es:[di].DDH_INTERRUPT
	push	ss
	pop	es			; ES:BX -> packet
	call	dword ptr [bp-4]	; far call to DDH_STRATEGY
	call	dword ptr [bp-8]	; far call to DDH_INTERRUPT
	pop	ax
	pop	es			; ES restored
	add	sp,4
	mov	ax,[bp].DDP_STATUS
	mov	dx,[bp].DDP_CONTEXT
	add	sp,DDP_MAXSIZE
	test	ax,DDSTAT_ERROR
	jz	dr9
	stc				; AL contains device error code
dr9:	pop	bp
	pop	bx
	ret
ENDPROC	dev_request

DOS	ends

	end
