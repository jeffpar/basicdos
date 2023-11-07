;
; BASIC-DOS Handle Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	disk.inc
	include	dev.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<dev_request,scb_release>
	EXTNEAR	<chk_devname,chk_filename>
	EXTNEAR	<get_bpb,get_psp,find_cln,get_cln>
	EXTNEAR	<msc_sigctrlc,msc_readctrlc>

	EXTBYTE	<scb_locked>
	EXTWORD	<scb_active>
	EXTLONG	<sfb_table>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hdl_open (REG_AH = 3Dh)
;
; Inputs:
;	REG_AL = mode (see MODE_*)
;	REG_DS:REG_DX -> name of device/file
;
; Outputs:
;	On success, carry clear, REG_AX = PFH (or SFH if no active PSP)
;	On failure, carry set, REG_AX = error code
;
DEFPROC	hdl_open,DOS
	call	pfh_alloc		; ES:DI = free handle entry
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
	call	pfh_set			; update handle entry
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
;	On failure, carry set, REG_AX = error code
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
;	On failure, REG_AX = error code, carry set
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
;	On failure, REG_AX = error code, carry set
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
;	On failure, carry set, REG_AX = error code
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
; hdl_ioctl (REG_AH = 44h)
;
; Inputs:
;	REG_AL = sub-function code (see IOCTL_* in devapi.inc)
;	REG_BX = handle
;	REG_CX = IOCTL-specific data
;	REG_DX = IOCTL-specific data
;	REG_DS:REG_SI -> optional IOCTL-specific data
;
; Outputs:
;	On success, carry clear, REG_DX = result
;	On failure, carry set, REG_AX = error code
;
DEFPROC	hdl_ioctl,DOS
	push	ax
	mov	bx,[bp].REG_BX		; BX = PFH ("handle")
	call	sfb_get
	pop	ax
	jc	hs8			; return error in REG_AX
	les	di,[bx].SFB_DEVICE	; ES:DI -> driver
	mov	bx,[bx].SFB_CONTEXT	; BX = context
	xchg	bx,dx			; DX = context, BX = REG_DX
	mov	ah,DDC_IOCTLIN
	mov	ds,[bp].REG_DS		; in case DS:SI is required as well
	ASSUME	DS:NOTHING
	call	dev_request
	jc	hs8			; return error in REG_AX
	mov	[bp].REG_DX,dx		; REG_DX = result
;
; TODO: PC DOS 2.00 apparently returns the result in REG_AX as well as REG_DX.
; If we wish to do the same, then xchg ax,dx and jmp hs8.  However, there's no
; need if no one depended on that behavior.
;
	ret
ENDPROC	hdl_ioctl

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
	sub	ax,ax			; AH = 0 (filename), AL = attributes
	DEFLBL	sfb_open_fcb,near
	LOCK_SCB
	push	si
	push	ds
	push	es
	call	chk_devname		; is it a device name?
	jnc	so1			; yes
	call	chk_filename		; is it a disk filename?
	jnc	so1a			; yes
so9a:	mov	ax,ERR_NOFILE
	jmp	so9			; no

so1:	mov	ax,DDC_OPEN SHL 8	; ES:DI -> driver
	sub	dx,dx			; no initial context
	call	dev_request		; issue the DDC_OPEN request
	jc	so9a			; failed (TODO: map device error?)
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
	cmp	[si].SFB_REFS,bl	; is this one free?
	jne	so5			; no
	mov	bx,si			; yes, remember it
so5:	add	si,size SFB
	cmp	si,[sfb_table].SEG
	jb	so3			; keep checking

	pop	si
	pop	ds
	test	bx,bx			; was there a free SFB?
	jz	so8			; no, tell the driver sorry

	push	di
	push	es
	push	cs
	pop	es
	ASSUME	ES:DOS
	mov	di,bx			; ES:DI -> SFB (a superset of DIRENT)
	test	al,al			; was a DIRENT provided?
	jl	so5a			; no
	mov	cx,size DIRENT SHR 1
	rep	movsw			; copy the DIRENT into the SFB
	jmp	short so5b
;
; There's no DIRENT for a device, so let's copy DDH.DDH_NAME to SFB_NAME
; and zero the rest of the DIRENT space in the SFB.
;
so5a:	pop	ds
	pop	si			; DS:SI -> DDH
	push	si
	push	ds
	add	si,offset DDH_NAME
	mov	cx,size DDH_NAME SHR 1
	rep	movsw
	push	ax
	xchg	ax,cx
	mov	cx,(size DIRENT - size DDH_NAME) SHR 1
	rep	stosw
	pop	ax

so5b:	pop	es
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
	mov	[bx].SFB_REFS,1		; one handle reference initially
	mov	[bx].SFB_CURPOS.LOW,ax	; zero the initial file position
	mov	[bx].SFB_CURPOS.HIW,ax
	mov	[bx].SFB_CURCLN,dx	; initial position cluster
	mov	[bx].SFB_FLAGS,al	; zero flags
	jmp	short so9		; return new SFB

so7:	pop	ax			; throw away any DIRENT on the stack
	pop	ax
	mov	bx,si			; return matching SFB
	inc	[bx].SFB_REFS
	jmp	short so9

so8:	test	al,al			; did we issue DDC_OPEN?
	jge	so8a			; no
	mov	ax,DDC_CLOSE SHL 8	; ES:DI -> driver, DX = context
	call	dev_request		; issue the DDC_CLOSE request
so8a:	mov	ax,ERR_NOHANDLE
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
;	AX, BX, CX, DX, SI, DI
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
	jmp	sr6
;
; As a preliminary matter, make sure the requested number of bytes doesn't
; exceed the current file size; if it does, reduce it.
;
sr0a:	mov	ax,[bx].SFB_SIZE.LOW
	mov	dx,[bx].SFB_SIZE.HIW
	sub	ax,[bx].SFB_CURPOS.LOW
	sbb	dx,[bx].SFB_CURPOS.HIW
	jnb	sr0b
	sub	ax,ax			; no data available
	cwd
sr0b:	test	dx,dx			; lots of data ahead?
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

sr1a:	mov	dx,[bx].SFB_CURPOS.LOW
	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	and	dx,ax			; DX = offset within current cluster

	push	bx			; save SFB pointer
	push	di			; save BPB pointer
	push	es

	mov	bx,[bx].SFB_CURCLN

	DPRINTF	'f',<"Reading cluster %#05x...\r\n">,bx

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
	jc	sr6
;
; Time for some bookkeeping: adjust the SFB's CURPOS by DX.
;
	add	[bx].SFB_CURPOS.LOW,dx
	adc	[bx].SFB_CURPOS.HIW,0
	add	[bp].TMP_AX,dx		; update accumulation of bytes read
	add	[bp].TMP_DX,dx		; update data buffer offset
	ASSERT	NC
;
; We're now obliged to determine whether or not we've exhausted the current
; cluster, because if we have, then we MUST zero SFB_CURCLN.
;
	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	test	[bx].SFB_CURPOS.LOW,ax	; is CURPOS at a cluster boundary?
	jnz	sr4			; no
	push	dx
	sub	dx,dx
	xchg	dx,[bx].SFB_CURCLN	; yes, get next cluster
	call	get_cln
	xchg	ax,dx
	pop	dx
	jc	sr6
	mov	[bx].SFB_CURCLN,ax
sr4:	sub	cx,dx			; have we exhausted the read count yet?
	jbe	sr5
	jmp	sr1a			; no, keep reading clusters

sr5:	ASSERT	NC
	mov	ax,[bp].TMP_AX

sr6:	UNLOCK_SCB
	jmp	short sr9
sr7:	jmp	msc_sigctrlc

sr8:	push	ds
	push	es

	mov	ah,DDC_READ
	push	es
	mov	si,dx
	les	di,[bx].SFB_DEVICE
	mov	dx,[bx].SFB_CONTEXT
	pop	ds
	ASSUME	DS:NOTHING		; DS:SI -> data buffer (from ES:DX)
	mov	bl,al			; BL = I/O mode
	call	dev_request		; issue the DDC_READ request
	jc	sr8a
;
; If the driver is a STDIN device, and the I/O request was not "raw", then
; we need to check the returned data for CTRLC and signal it appropriately.
;
	test	ax,ax			; any bytes returned?
	jz	sr8a			; no
	test	es:[di].DDH_ATTR,DDATTR_STDIN
	jz	sr8a
	ASSERT	IO_RAW,EQ,0
	test	bl,bl			; IO_RAW (or IO_DIRECT) request?
	jle	sr8a			; yes
	cmp	byte ptr [si],CHR_CTRLC
	je	sr7
	clc

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
;	AL = SEEK method (ie, SEEK_BEG, SEEK_CUR, or SEEK_END)
;	BX -> SFB
;	CX:DX = distance, in bytes
;
; Outputs:
;	On success, carry clear, new position in CX:DX
;
; Modifies:
;	AX, CX, DX (although technically SEEK_BEG doesn't change CX:DX)
;
DEFPROC	sfb_seek,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	si
	sub	si,si
	mov	[bx].SFB_CURCLN,si	; invalidate SFB_CURCLN
;
; Check the method against the middle value (SEEK_CUR).  It's presumed to
; be SEEK_BEG if less than and SEEK_END if greater than.  Unlike PC DOS, we
; don't return an error if the method isn't EXACTLY one of those values.
;
	cmp	al,SEEK_CUR
	mov	ax,si			; SI:AX = offset for SEEK_BEG
	jl	ss7
	mov	ax,[bx].SFB_CURPOS.LOW
	mov	si,[bx].SFB_CURPOS.HIW	; SI:AX = offset for SEEK_CUR
	je	ss7
	mov	ax,[bx].SFB_SIZE.LOW
	mov	si,[bx].SFB_SIZE.HIW	; SI:AX = offset for SEEK_END
ss7:	add	dx,ax
	adc	cx,si
	mov	[bx].SFB_CURPOS.LOW,dx
	mov	[bx].SFB_CURPOS.HIW,cx
;
; TODO: Technically, we'll return an error of sorts if the addition resulted
; in an overflow (ie, carry set).  However, no error code has been assigned to
; that condition, and I'm not sure PC DOS considered that an error.
;
	pop	si
	ret
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
;	AX, BX, DX, DI, ES
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
	ASSERT	IO_RAW,EQ,0
	test	al,al			; IO_RAW (or IO_DIRECT) request?
	jle	sw8			; yes
	mov	bx,cs:[scb_active]
	ASSERT	STRUCT,cs:[bx],SCB
	cmp	cs:[bx].SCB_CTRLC_ACT,0
	je	sw8
	push	cs
	pop	ds
	jmp	msc_readctrlc

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
	dec	[bx].SFB_REFS
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
	call	get_psp			; if we're called by sysinit
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
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	call	get_psp			; if there's no PSP yet
	jz	sg1			; then BX must an SFH, not a PFH
	cmp	bl,size PSP_PFT		; is the PFH within PFT bounds?
	jae	sg8			; no
	push	ds
	mov	ds,ax
	mov	bl,ds:[PSP_PFT][bx]	; BL = SFH
	pop	ds

	DEFLBL	sfb_from_sfh,near
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
sg1:	mov	al,size SFB		; convert SFH to SFB
	mul	bl
	add	ax,[sfb_table].OFF
	cmp	ax,[sfb_table].SEG	; is the SFB valid?
	xchg	bx,ax			; BX -> SFB
	jae	sg8
	cmp	cs:[bx].SFB_REFS,0	; is the SFB open?
	jne	sg9			; yes (carry clear)
sg8:	mov	ax,ERR_BADHANDLE
	stc
sg9:	ret
ENDPROC	sfb_get

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_find_fcb
;
; Inputs:
;	CX:DX = address of FCB
;
; Outputs:
;	On success, carry clear, BX -> SFB
;	On failure, carry set
;
; Modifies:
;	BX
;
DEFPROC	sfb_find_fcb,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	mov	bx,[sfb_table].OFF
sff1:	test	[bx].SFB_FLAGS,SFBF_FCB
	jz	sff8
	cmp	[bx].SFB_FCB.OFF,dx
	jne	sff8
	cmp	[bx].SFB_FCB.SEG,cx
	je	sff9
sff8:	add	bx,size SFB
	cmp	bx,[sfb_table].SEG
	jb	sff1
	stc
sff9:	ret
ENDPROC	sfb_find_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pfh_alloc
;
; Inputs:
;	None
;
; Outputs:
;	On success, ES:DI -> PFT, carry clear (DI will be zero if no PSP)
;	On failure, AX = ERR_NOHANDLE, carry set
;
; Modifies:
;	AX, BX, CX, DI, ES
;
DEFPROC	pfh_alloc,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	call	get_psp			; get the current PSP
	xchg	di,ax			; if we're called by sysinit
	jz	pa9			; there may be no valid PSP yet
	mov	es,di			; find a free handle entry
	mov	al,SFH_NONE		; AL = 0FFh (indicates unused entry)
	mov	cx,size PSP_PFT
	mov	di,offset PSP_PFT
	repne	scasb
	jne	pa8			; if no entry, return error w/carry set
	dec	di			; rewind to entry
	jmp	short pa9
pa8:	mov	ax,ERR_NOHANDLE
	stc
pa9:	ret
ENDPROC	pfh_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pfh_set
;
; This returns a PFT # (aka PFH or Process File Handle) if pfh_alloc found
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
DEFPROC	pfh_set,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	xchg	ax,bx			; AX = SFB address
	sub	ax,[sfb_table].OFF
	mov	cl,size SFB
	div	cl			; AL = SFB # (from SFB address)
	ASSERT	Z,<test ah,ah>		; assert that the remainder is zero
	test	di,di			; did we find a free PFT entry?
	jz	ps9			; no
	stosb				; yes, store SFB # in the PFT entry
	sub	di,offset PSP_PFT + 1	; convert PFT entry into PFH
	xchg	ax,di			; AX = handle
ps9:	ret
ENDPROC	pfh_set

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
;	On failure, carry set, REG_AX = error code
;
; Modifies:
;	AX, DX
;
DEFPROC	pfh_close,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	bx
	push	si
	mov	si,bx			; SI = PFH
	call	sfb_get
	jc	pc9
	push	di
	push	es
	call	sfb_close		; BX -> SFB, SI = PFH
	pop	es
	pop	di
pc9:	pop	si
	pop	bx
	ret
ENDPROC	pfh_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfh_add_ref
;
; Inputs:
;	AL = SFH
;	AH = # refs
;
; Modifies:
;	None
;
DEFPROC	sfh_add_ref,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	bx
	mov	bl,al
	push	ax
	call	sfb_from_sfh
	pop	ax
	jc	sha9
	add	cs:[bx].SFB_REFS,ah
	ASSERT	NC
sha9:	pop	bx
	ret
ENDPROC	sfh_add_ref

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
;	On failure, carry set, REG_AX = error code
;
; Modifies:
;	AX, DX
;
DEFPROC	sfh_close,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	bx
	push	si
	call	sfb_from_sfh
	jc	shc9
	push	di
	push	es
	mov	si,-1			; no PFH
	call	sfb_close		; BX -> SFB
	pop	es
	pop	di
shc9:	pop	si
	pop	bx
	ret
ENDPROC	sfh_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfh_context
;
; Inputs:
;	AL = SFH
;
; Outputs:
;	AX = context (carry clear), zero if none (carry set)
;
; Modifies:
;	AX
;
DEFPROC	sfh_context,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	bx
	mov	bl,al
	call	sfb_from_sfh
	mov	ax,0
	jc	shx9
	mov	ax,[bx].SFB_CONTEXT
shx9:	pop	bx
	ret
ENDPROC	sfh_context

DOS	ends

	end
