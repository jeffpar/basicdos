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

	EXTERNS	<dev_request,scb_delock>,near
	EXTERNS	<chk_devname,chk_filename>,near
	EXTERNS	<get_bpb,find_cln,get_cln>,near
	EXTERNS	<msc_sigctrlc,msc_sigctrlc_read>,near

	EXTERNS	<scb_locked>,byte
	EXTERNS	<scb_active,psp_active>,word
	EXTERNS	<sfb_table>,dword

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hdl_open (REG_AH = 3Dh)
;
; Inputs:
;	REG_AL = mode (see MODE_*)
;	REG_DS:REG_DX -> name of device/file
;
; Outputs:
;	On success, REG_AX = PFH (or SFH if no valid PSP), carry clear
;	On failure, REG_AX = error, carry set
;
DEFPROC	hdl_open,DOS
	call	pft_alloc		; ES:DI = free handle entry
	ASSUME	ES:NOTHING
	jc	ho9
	push	di			; save free handle entry
	mov	bl,[bp].REG_AL		; BL = mode
	mov	si,[bp].REG_DX
	mov	ds,[bp].REG_DS		; DS:SI = name of device/file
	ASSUME	DS:NOTHING
	call	sfb_open
	pop	di			; restore handle entry
	jc	ho9
	call	pft_set			; update handle entry
ho9:	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
	ret
ENDPROC	hdl_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hdl_close (REG_AH = 3Eh)
;
; Inputs:
;	REG_BX = PFH (Process File Handle)
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error
;
DEFPROC	hdl_close,DOS
	mov	bx,[bp].REG_BX		; BX = Process File Handle
	call	pfh_close
	jnc	hc9
	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
hc9:	ret
ENDPROC	hdl_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hdl_read (REG_AH = 3Fh)
;
; Inputs:
;	REG_BX = handle
;	REG_CX = byte count
;	REG_DS:REG_DX -> data buffer
;
; Outputs:
;	On success, REG_AX = bytes read, carry clear
;	On failure, REG_AX = error, carry set
;
DEFPROC	hdl_read,DOS
	mov	bx,[bp].REG_BX		; BX = PFH ("handle")
	call	sfb_get			; BX -> SFB
	jc	hr8
	mov	cx,[bp].REG_CX		; CX = byte count
	mov	es,[bp].REG_DS
	mov	dx,[bp].REG_DX		; ES:DX -> data buffer
	mov	al,IO_COOKED
	call	sfb_read
hr8:	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
hr9:	ret
ENDPROC	hdl_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hdl_write (REG_AH = 40h)
;
; Inputs:
;	REG_BX = handle
;	REG_CX = byte count
;	REG_DS:REG_DX -> data buffer
;
; Outputs:
;	On success, REG_AX = bytes written, carry clear
;	On failure, REG_AX = error, carry set
;
DEFPROC	hdl_write,DOS
	mov	bx,[bp].REG_BX		; BX = PFH ("handle")
	call	sfb_get			; BX -> SFB
	jc	hw8
	mov	cx,[bp].REG_CX		; CX = byte count
	mov	si,[bp].REG_DX
	mov	ds,[bp].REG_DS		; DS:SI = data to write
	ASSUME	DS:NOTHING
	mov	al,IO_COOKED
	call	sfb_write
	jnc	hw9
hw8:	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
hw9:	ret
ENDPROC	hdl_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hdl_seek (REG_AH = 42h)
;
; Inputs:
;	REG_BX = handle
;	REG_AL = method (ie, SEEK_BEG, SEEK_CUR, or SEEK_END)
;	REG_CX:REG_DX = distance, in bytes
;
; Outputs:
;	On success, carry clear, REG_DX:REG_AX = new file location
;	On failure, carry set, REG_AX = error
;
DEFPROC	hdl_seek,DOS
	mov	bx,[bp].REG_BX		; BX = PFH ("handle")
	call	sfb_get
	jc	hs8
	mov	ax,[bp].REG_AX		; AL = method
	mov	cx,[bp].REG_CX		; CX:DX = distance
	mov	dx,[bp].REG_DX
	call	sfb_seek		; BX -> SFB
	jc	hs8
	mov	[bp].REG_AX,dx
	mov	[bp].REG_DX,cx		; REG_DX:REG_AX = new CX:DX
	jmp	short hs9
hs8:	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
hs9:	ret
ENDPROC	hdl_seek

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_open
;
; Inputs:
;	BL = mode (see MODE_*)
;	DS:SI -> name of device/file
;
; Outputs:
;	On success, BX -> SFB, DX = context (if any), carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	sfb_open,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	LOCK_SCB
	push	si
	push	ds
	push	es
	call	chk_devname		; is it a device name?
	jnc	so1			; yes
	sub	ax,ax			; AH = 0 (filename), AL = attributes
	call	chk_filename		; is it a disk filename?
	jnc	so1a			; yes
so9a:	mov	ax,ERR_NOFILE
	jmp	so9			; no

so1:	mov	ax,DDC_OPEN SHL 8	; ES:DI -> driver
	sub	dx,dx			; no initial context
	call	dev_request		; issue the DDC_OPEN request
;
; TODO: Decide what to do with device error codes; we're currently
; overwriting them with DOS error codes.
;
	jc	so9a			; failed
	mov	al,-1			; no drive # for devices

so1a:	push	ds			;
	push	si			; save DIRENT at DS:SI (if any)
;
; Although the primary goal here is to find a free SFB, a matching SFB
; will suffice if it's for a context-less device (ie, not a file).
;
so2:	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	ah,bl			; save mode in AH
	mov	cx,es			; CX:DI is driver, DX is context
	mov	si,[sfb_table].OFF
	sub	bx,bx			; use BX to remember a free SFB
so3:	test	dx,dx			; any context?
	jnz	so4			; yes, check next SFB
	cmp	[si].SFB_DEVICE.SEG,cx
	jne	so4			; check next SFB
	cmp	[si].SFB_DEVICE.OFF,di
	jne	so4			; check next SFB
	cmp	[si].SFB_CONTEXT,dx	; context-less device?
	je	so7			; yes, this SFB will suffice
so4:	test	bx,bx			; are we still looking for a free SFB?
	jnz	so5			; no
	cmp	[si].SFB_HANDLES,bl	; is this one free?
	jne	so5			; no
	mov	bx,si			; yes, remember it
so5:	add	si,size SFB
	cmp	si,[sfb_table].SEG
	jb	so3			; keep checking

	pop	si
	pop	ds
	test	bx,bx			; was there a free SFB?
	jz	so8			; no, tell the driver sorry

	test	al,al			; was a DIRENT provided?
	jl	so6			; no
	push	di
	push	es
	push	cs
	pop	es
	ASSUME	ES:DOS
	mov	di,bx			; ES:DI -> SFB (a superset of DIRENT)
	mov	cx,size DIRENT SHR 1
	rep	movsw			; copy the DIRENT into the SFB
	pop	es
	ASSUME	ES:NOTHING
	pop	di

so6:	push	cs
	pop	ds
	ASSUME	DS:DOS
	DBGINIT	STRUCT,[bx],SFB
	mov	[bx].SFB_DEVICE.OFF,di
	mov	[bx].SFB_DEVICE.SEG,es
	mov	[bx].SFB_CONTEXT,dx	; set DRIVE (AL) and MODE (AH) next
	mov	word ptr [bx].SFB_DRIVE,ax
	sub	ax,ax
	mov	[bx].SFB_HANDLES,1	; one handle reference initially
	mov	[bx].SFB_CURPOS.OFF,ax	; zero the initial file position
	mov	[bx].SFB_CURPOS.SEG,ax
	mov	[bx].SFB_CURCLN,dx	; initial position cluster
	jmp	short so9		; return new SFB

so7:	pop	ax			; throw away any DIRENT on the stack
	pop	ax
	mov	bx,si			; return matching SFB
	inc	[bx].SFB_HANDLES
	jmp	short so9

so8:	test	al,al			; did we issue DDC_OPEN?
	jge	so8a			; no
	mov	ax,DDC_CLOSE SHL 8	; ES:DI -> driver, DX = context
	call	dev_request		; issue the DDC_CLOSE request
so8a:	mov	ax,ERR_MAXFILES
	stc				; return no SFB (and BX is zero)

so9:	pop	es
	pop	ds
	pop	si
	ASSUME	DS:NOTHING,ES:NOTHING
	UNLOCK_SCB
	ret
ENDPROC	sfb_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_read
;
; Inputs:
;	AL = I/O mode
;	BX -> SFB
;	CX = byte count
;	ES:DX -> data buffer
;
; Outputs:
;	On success, carry clear, AX = bytes read
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	sfb_read,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	mov	ah,[bx].SFB_DRIVE
	test	ah,ah
	jge	sr0
	jmp	sr8			; character device

sr0:	LOCK_SCB
	mov	word ptr [bp].TMP_AX,0	; use TMP_AX to accumulate bytes read
	mov	[bp].TMP_ES,es
	mov	[bp].TMP_DX,dx
	mov	dl,ah			; DL = drive #
	call	get_bpb			; DI -> BPB if no error
	jnc	sr0a
	jmp	sr7
;
; As a preliminary matter, make sure the requested number of bytes doesn't
; exceed the current file size; if it does, reduce it.
;
sr0a:	mov	ax,[bx].SFB_SIZE.OFF
	mov	dx,[bx].SFB_SIZE.SEG
	sub	ax,[bx].SFB_CURPOS.OFF
	sbb	dx,[bx].SFB_CURPOS.SEG
	test	dx,dx			; lots of data ahead?
	jnz	sr1			; yes
	cmp	cx,ax
	jbe	sr1
	mov	cx,ax			; CX reduced
;
; Next, convert CURPOS into cluster # and cluster offset.  That's simplified
; if there's a valid CURCLN (which must be in sync with CURPOS if present);
; otherwise, we'll have to walk the cluster chain to find the correct cluster #.
;
sr1:	mov	dx,[bx].SFB_CURCLN
	test	dx,dx
	jnz	sr1a
	call	find_cln		; find cluster # for CURPOS
	mov	[bx].SFB_CURCLN,dx

sr1a:	mov	dx,[bx].SFB_CURPOS.OFF
	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	and	dx,ax			; DX = offset within current cluster

	push	bx			; save SFB pointer
	push	di			; save BPB pointer
	push	es

	mov	bx,[bx].SFB_CURCLN
	IFDEF MAXDEBUG
	PRINTF	<"Reading cluster %#05x...",13,10>,bx
	ENDIF
	sub	bx,2
	jb	sr3			; invalid cluster #
	xchg	ax,cx			; save CX
	mov	cl,[di].BPB_CLUSLOG2
	shl	bx,cl
	xchg	ax,cx			; restore CX
	add	bx,[di].BPB_LBADATA	; BX = LBA
;
; We're almost ready to read, except for the byte count in CX, which must be
; limited to whatever's in the current cluster.
;
	push	cx			; save byte count
	mov	ax,[di].BPB_CLUSBYTES
	sub	ax,dx			; AX = bytes available in cluster
	cmp	cx,ax			; if CX <= AX, we're fine
	jbe	sr2
	mov	cx,ax			; reduce CX
sr2:	mov	ah,DDC_READ
	mov	al,[di].BPB_DRIVE
	les	di,[di].BPB_DEVICE
	ASSUME	ES:NOTHING
	push	ds
	mov	si,[bp].TMP_DX
	mov	ds,[bp].TMP_ES		; DS:SI -> data buffer
	ASSUME	DS:NOTHING
	call	dev_request
	pop	ds
	ASSUME	DS:DOS
	mov	dx,cx			; DX = bytes read (assuming no error)
	pop	cx			; restore byte count

sr3:	pop	es
	pop	di			; BPB pointer restored
	pop	bx			; SFB pointer restored
	jc	sr7
;
; Time for some bookkeeping: adjust the SFB's CURPOS by DX.
;
	add	[bx].SFB_CURPOS.OFF,dx
	adc	[bx].SFB_CURPOS.SEG,0
	add	[bp].TMP_AX,dx		; update accumulation of bytes read
	add	[bp].TMP_DX,dx
	ASSERT	NC
;
; We're now obliged to determine whether or not we've exhausted the current
; cluster, because if we have, then we MUST zero SFB_CURCLN.
;
	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	test	[bx].SFB_CURPOS.OFF,ax	; is CURPOS at a cluster boundary?
	jnz	sr4			; no
	push	dx
	sub	dx,dx
	xchg	dx,[bx].SFB_CURCLN	; yes, get next cluster
	call	get_cln
	xchg	ax,dx
	pop	dx
	jc	sr7
	mov	[bx].SFB_CURCLN,ax
sr4:	sub	cx,dx			; have we exhausted the read count yet?
	jbe	sr5
	jmp	sr1a			; no, keep reading clusters

sr5:	ASSERT	NC
	mov	ax,[bp].TMP_AX

sr7:	UNLOCK_SCB
	jmp	short sr9

sr8:	push	ds
	push	es

	mov	ah,DDC_READ
	push	es
	mov	si,dx
	les	di,[bx].SFB_DEVICE
	mov	dx,[bx].SFB_CONTEXT
	pop	ds
	ASSUME	DS:NOTHING		; DS:SI -> data buffer (from ES:DX)
	push	ax			; AL = I/O mode
	call	dev_request		; issue the DDC_READ request
	pop	dx			; DL = I/O mode
	jc	sr8a
;
; If the driver is a STDIN device, and the I/O request was not "raw", then
; we need to check the returned data for CTRLC and signal it appropriately.
;
	xchg	ax,cx			; AX = original byte count
	test	es:[di].DDH_ATTR,DDATTR_STDIN
	jz	sr8a
	ASSERT	IO_RAW,EQ,0
	test	dl,dl			; IO_RAW request?
	jz	sr8a			; yes
	cmp	byte ptr [si],CHR_CTRLC
	clc
	jne	sr8a
	jmp	msc_sigctrlc

sr8a:	pop	es
	pop	ds
	ASSUME	DS:DOS

sr9:	ret
ENDPROC	sfb_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_seek
;
; Inputs:
;	BX -> SFB
;	AL = SEEK method (ie, SEEK_BEG, SEEK_CUR, or SEEK_END)
;	CX:DX = distance, in bytes
;
; Outputs:
;	On success, carry clear, new position in CX:DX
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, CX, DX, SI,DI
;
DEFPROC	sfb_seek,DOS
	ASSUMES	<DS,DOS>,<ES,DOS>
	sub	di,di
	sub	si,si			; SI:DI = offset for SEEK_BEG
	cmp	al,SEEK_CUR
	jl	ss8
	mov	di,[bx].SFB_CURPOS.OFF
	mov	si,[bx].SFB_CURPOS.SEG	; SI:DI = offset for SEEK_CUR
	je	ss8
	mov	di,[bx].SFB_SIZE.OFF
	mov	si,[bx].SFB_SIZE.SEG	; SI:DI = offset for SEEK_END
ss8:	add	dx,di
	adc	cx,si
	mov	[bx].SFB_CURPOS.OFF,dx
	mov	[bx].SFB_CURPOS.SEG,cx
;
; TODO: Feels like we should return an error if carry is set (ie, overflow)....
;
	clc
ss9:	ret
ENDPROC	sfb_seek

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_write
;
; Inputs:
;	AL = I/O mode
;	BX -> SFB
;	CX = byte count
;	DS:SI -> data buffer
;
; Outputs:
;	On success, carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, DX, DI, ES
;
DEFPROC	sfb_write,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	cmp	cs:[bx].SFB_DRIVE,0
	jl	sw7
	stc				; no writes to block devices (yet)
	jmp	short sw9

sw7:	mov	ah,DDC_WRITE
	les	di,cs:[bx].SFB_DEVICE
	mov	dx,cs:[bx].SFB_CONTEXT
;
; If the driver is a STDOUT device, and the I/O request was not "raw", then
; we need to check for a CTRLC signal.
;
	test	es:[di].DDH_ATTR,DDATTR_STDOUT
	jz	sw8
	cmp	al,IO_RAW
	je	sw8
	mov	bx,cs:[scb_active]	; TODO: always have an scb_active
	test	bx,bx
	jz	sw8
	cmp	cs:[bx].SCB_CTRLC_ACT,0
	je	sw8
	push	cs
	pop	ds
	jmp	msc_sigctrlc_read

sw8:	call	dev_request		; issue the DDC_WRITE request

sw9:	ret
ENDPROC	sfb_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_close
;
; Decrement the handle reference count, and if zero, close the device
; (if it's a device handle), mark the SFB unused, and mark any PFH as unused.
;
; Inputs:
;	BX -> SFB
;	SI = PFH, -1 if none
;
; Outputs:
;	Carry clear if success
;
; Modifies:
;	AX, DX, DI, ES
;
DEFPROC	sfb_close,DOS
	LOCK_SCB
	dec	[bx].SFB_HANDLES
	jnz	sc8
	mov	al,[bx].SFB_DRIVE	; did we issue a DDC_OPEN?
	test	al,al			; for this SFB?
	jge	sc7			; no
	les	di,[bx].SFB_DEVICE	; ES:DI -> driver
	mov	dx,[bx].SFB_CONTEXT	; DX = context
	mov	ax,DDC_CLOSE SHL 8	;
	call	dev_request		; issue the DDC_CLOSE request
sc7:	sub	ax,ax
	mov	[bx].SFB_DEVICE.OFF,ax
	mov	[bx].SFB_DEVICE.SEG,ax	; mark SFB as unused
sc8:	test	si,si			; valid PFH?
	jl	sc9			; no
	mov	ax,[psp_active]
	test	ax,ax			; if we're called by sysinit
	jz	sc9			; there may be no valid PSP yet
	push	ds
	mov	ds,ax
	ASSUME	DS:NOTHING
	mov	ds:[PSP_PFT][si],SFH_NONE
	pop	ds
	ASSUME	DS:DOS
sc9:	UNLOCK_SCB
	ret
ENDPROC	sfb_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_get
;
; Inputs:
;	BX = handle (PFH)
;
; Outputs:
;	On success, BX -> SFB, carry clear
;	On failure, AX = ERR_BADHANDLE, carry set
;
; Modifies:
;	AX, BX
;
DEFPROC	sfb_get,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	mov	ax,[psp_active]		; if there's no PSP yet
	test	ax,ax			; then BX must an SFH, not a PFH
	jz	gs1
	cmp	bl,size PSP_PFT		; is the PFH within PFT bounds?
	jae	gs8			; no
	push	ds
	mov	ds,ax
	ASSUME	DS:NOTHING
	mov	bl,ds:[PSP_PFT][bx]	; BL = SFH
	pop	ds

	DEFLBL	get_sfh_sfb,near
gs1:	mov	al,size SFB		; convert SFH to SFB
	mul	bl
	add	ax,[sfb_table].OFF
	cmp	ax,[sfb_table].SEG	; is the SFB valid?
	xchg	bx,ax			; BX -> SFB
	jb	gs9			; yes
gs8:	mov	ax,ERR_BADHANDLE
gs9:	cmc
	ret
ENDPROC	sfb_get

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pft_alloc
;
; Inputs:
;	None
;
; Outputs:
;	On success, ES:DI -> PFT, carry clear (DI will be zero if no PSP)
;	On failure, AX = ERR_MAXFILES, carry set
;
; Modifies:
;	AX, BX, CX, DI, ES
;
DEFPROC	pft_alloc,DOS
	ASSUMES	<DS,DOS>,<ES,DOS>
	mov	di,[psp_active]		; get the current PSP
	test	di,di			; if we're called by sysinit
	jz	gp9			; there may be no valid PSP yet
	mov	es,di
	ASSUME	ES:NOTHING		; find a free handle entry
	mov	al,SFH_NONE		; AL = 0FFh (indicates unused entry)
	mov	cx,size PSP_PFT
	mov	di,offset PSP_PFT
	repne	scasb
	jne	gp8			; if no entry, return error w/carry set
	dec	di			; rewind to entry
	jmp	short gp9
gp8:	mov	ax,ERR_MAXFILES
	stc
gp9:	ret
ENDPROC	pft_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pft_set
;
; This returns a PFT # (aka PFH or Process File Handle) if pft_alloc found
; a valid PSP; otherwise, it returns the SFB # (aka SFH or System File Handle).
;
; Inputs:
;	BX -> SFB
;	ES:DI -> PFT
;
; Outputs:
;	FT updated, AX = PFH or SFH (see above), carry clear
;
; Modifies:
;	AX, BX, CX, DI
;
DEFPROC	pft_set,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	xchg	ax,bx			; AX = SFB address
	sub	ax,[sfb_table].OFF
	mov	cl,size SFB
	div	cl			; AL = SFB # (from SFB address)
	ASSERT	Z,<test ah,ah>		; assert that the remainder is zero
	test	di,di			; did we find a free PFT entry?
	jnz	sp8			; yes
	mov	[bp].REG_DX,dx		; no, return context in REG_DX
	jmp	short sp9		; and return the SFB # in REG_AX
sp8:	stosb				; yes, store SFB # in the PFT entry
	sub	di,offset PSP_PFT + 1	; convert PFT entry into PFH
	xchg	ax,di			; AX = handle
sp9:	ret
ENDPROC	pft_set

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfh_addref
;
; Inputs:
;	AL = SFH
;	AH = # refs
;
; Modifies:
;	None
;
DEFPROC	sfh_addref,DOS
	push	bx
	mov	bl,al
	push	ax
	call	get_sfh_sfb
	pop	ax
	jc	sfa9
	add	[bx].SFB_HANDLES,ah
	ASSERT	NC
sfa9:	pop	bx
	ret
ENDPROC	sfh_addref

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pfh_close
;
; Close the process file handle in BX.
;
; Inputs:
;	BX = handle (PFH)
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error
;
; Modifies:
;	AX, DX
;
DEFPROC	pfh_close,DOS
	push	bx
	push	si
	mov	si,bx			; SI = PFH
	call	sfb_get
	jc	pfc9
	push	di
	push	es
	call	sfb_close		; BX -> SFB, SI = PFH
	pop	es
	pop	di
pfc9:	pop	si
	pop	bx
	ret
ENDPROC	pfh_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfh_close
;
; Close the system file handle in BX.
;
; Inputs:
;	BX = handle (SFH)
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error
;
; Modifies:
;	AX, DX
;
DEFPROC	sfh_close,DOS
	push	bx
	push	si
	call	get_sfh_sfb
	jc	sfc9
	push	di
	push	es
	mov	si,-1			; no PFH
	call	sfb_close		; BX -> SFB
	pop	es
	pop	di
sfc9:	pop	si
	pop	bx
	ret
ENDPROC	sfh_close

DOS	ends

	end
