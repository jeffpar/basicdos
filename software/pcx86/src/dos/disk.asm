;
; BASIC-DOS Disk Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<dev_request,parse_name,scb_delock>,near

	EXTERNS	<scb_locked>,byte
	EXTERNS	<scb_active>,word
	EXTERNS	<bpb_table>,dword
	EXTERNS	<bpb_total,file_name>,byte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_flush (REG_AH = 0Dh)
;
; TODO: For now, since we haven't yet implemented a buffer cache, all we
; have to do is zap the LBAs in the two BIOS sector buffers.
;
; Inputs:
;	AL = drive #, or -1 for all drives (TODO)
;
; Outputs:
;	Flush all buffers containing data for the specified drive
;
; Modifies:
;	None (carry clear)
;
DEFPROC	dsk_flush,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	dx
	push	ds
	sub	dx,dx
	mov	ds,dx
	ASSUME	DS:BIOS
	cmp	ds:[FAT_BUFHDR].BUF_DRIVE,al
	jne	df2
	mov	ds:[FAT_BUFHDR].BUF_LBA,0
df2:	cmp	ds:[DIR_BUFHDR].BUF_DRIVE,al
	jne	df3
	mov	ds:[DIR_BUFHDR].BUF_LBA,0
df3:	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	clc
	ret
ENDPROC	dsk_flush

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_setdrv (REG_AH = 0Eh)
;
; Inputs:
;	REG_DL = drive #
;
; Outputs:
;	REG_AL = # of (logical) drives
;
; Notes:
;	The spec isn't clear if this should return an error (carry set)
;	if REG_DL >= # drives; we assume that we should.
;
; TODO: Add support for logical drives; all we currently support are physical.
;
DEFPROC	dsk_setdrv,DOS
	mov	al,[bpb_total]		; AL = # (physical) drives
	cmp	dl,al			; DL valid?
	cmc
	jc	ds9			; no
	mov	bx,[scb_active]
	mov	[bx].SCB_CURDRV,dl
ds9:	mov	[bp].REG_AL,al
	ret
ENDPROC	dsk_setdrv

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_setdta (REG_AH = 1Ah)
;
; Inputs:
;	REG_DS:REG_DX -> Disk Transfer Area (DTA)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX
;
DEFPROC	dsk_setdta,DOS
	mov	bx,[scb_active]
	mov	[bx].SCB_DTA.OFF,dx
	mov	ax,[bp].REG_DS
	mov	[bx].SCB_DTA.SEG,ax
	ret
ENDPROC	dsk_setdta

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_getdrv (REG_AH = 19h)
;
; Inputs:
;	None
;
; Outputs:
;	REG_AL = current drive #
;
DEFPROC	dsk_getdrv,DOS
	mov	bx,[scb_active]
	mov	al,[bx].SCB_CURDRV
	mov	[bp].REG_AL,al
	ret
ENDPROC	dsk_getdrv

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_getdta (REG_AH = 2Fh)
;
; Inputs:
;	None
;
; Outputs:
;	REG_ES:REG_BX -> Disk Transfer Area (DTA)
;
; Modifies:
;	AX, BX
;
DEFPROC	dsk_getdta,DOS
	mov	bx,[scb_active]
	mov	ax,[bx].SCB_DTA.OFF
	mov	[bp].REG_BX,ax
	mov	ax,[bx].SCB_DTA.SEG
	mov	[bp].REG_ES,ax
	ret
ENDPROC	dsk_getdta

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_ffirst (REG_AH = 4Eh)
;
; Inputs:
;	REG_CX = attribute bits
;	REG_DS:REG_DX -> filespec
;
; Outputs:
;	If found, carry clear, DTA filled in
;	If not found, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS
;
DEFPROC	dsk_ffirst,DOS
	LOCK_SCB
	mov	al,[bp].REG_CL
	mov	ah,80h			; AH = 80h (filespec)
	mov	si,dx
	mov	ds,[bp].REG_DS		; DS:SI -> filespec
	call	chk_filename
	jc	ff8
	mov	ah,[bp].REG_CL
;
; Fill in the DTA with the relevant bits
;
	DEFLBL	dsk_ffill,near
	ASSUME	DS:NOTHING, ES:NOTHING	; DS:SI -> DIRENT
	mov	bx,[scb_active]
	les	di,cs:[bx].SCB_DTA	; ES:DI -> DTA (FFB)
	stosw				; FFB_DRIVE, FFB_SATTR
	push	cx
	push	si
	mov	cx,11
	mov	si,offset file_name + 1	; FFB_FILESPEC
;
; TODO: MASM 4.0 generates the REP prefix before the CS: prefix,
; but if we ever use a different assembler, this must be re-verified.
;
; See: https://www.pcjs.org/documents/manuals/intel/8086/ for errata details.
;
; Fortunately, PCjs simulates the errata, so I was able to catch it; however,
; it would be even better if PCjs displayed a warning when it happened.
;
ff1:	rep	movs byte ptr es:[di],byte ptr cs:[si]
	jcxz	ff2
	jmp	ff1
ff2:	pop	si
	pop	cx
	add	di,size FFB_PADDING
	ASSERT	Z,<cmp di,80h + offset FFB_DIRNUM>
	xchg	ax,cx
	ASSERT	Z,<test ah,ah>		; assert DIRENT # < 256 (for now)
	stosw				; FFB_DIRNUM
	mov	al,[si].DIR_ATTR
	stosb				; FFB_ATTR
	mov	ax,[si].DIR_TIME
	stosw				; FFB_TIME
	mov	ax,[si].DIR_DATE
	stosw				; FFB_DATE
	mov	ax,[si].DIR_SIZE.OFF
	stosw				; FFB_SIZE
	mov	ax,[si].DIR_SIZE.SEG
	stosw
	mov	cx,8
ff3:	lodsb
	cmp	al,' '
	je	ff4
	stosb				; FFB_NAME
ff4:	loop	ff3
	mov	al,[si]
	cmp	al,' '
	je	ff7
	mov	al,'.'
	stosb
	mov	cx,3
ff5:	lodsb
	cmp	al,' '
	je	ff6
	stosb
ff6:	loop	ff5
ff7:	sub	ax,ax
	stosb
	jnc	ff9
ff8:	mov	[bp].REG_AX,ax
ff9:	UNLOCK_SCB
	ret
ENDPROC	dsk_ffirst

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_fnext (REG_AH = 4Fh)
;
; Inputs:
;	DTA -> data from previous dsk_ffirst/dsk_fnext
;
; Outputs:
;	If found, carry clear, DTA filled in
;	If not found, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS
;
DEFPROC	dsk_fnext,DOS
	LOCK_SCB
	mov	bx,[scb_active]
	lds	si,cs:[bx].SCB_DTA	; DS:SI -> DTA (FFB)
	ASSUME	DS:NOTHING
	mov	dl,[si].FFB_DRIVE
	push	si
	lea	si,[si].FFB_FILESPEC
	mov	di,offset file_name + 1
	mov	cx,11
	rep	movsb
	pop	si
	call	get_bpb			; DL = drive #
	jc	fn8
	mov	bl,[si].FFB_SATTR	; BL = search attributes
	mov	dh,bl
	mov	ax,[si].FFB_DIRNUM	; AX = prev DIRENT #
	inc	ax			; AX = next DIRENT #
	call	get_dirent
	jc	fn8
	ASSERT	Z,<test ah,ah>		; assert DIRENT # < 256 (for now)
	xchg	cx,ax			; CX = DIRENT #
	mov	ax,dx			; AL = drive #, AH = search attributes
	jmp	dsk_ffill
fn8:	mov	[bp].REG_AX,ax
	UNLOCK_SCB
	ret
ENDPROC	dsk_fnext

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_filename
;
; Inputs:
;	AL = search attributes (0 if none)
;	AH = 00h for filename, 80h for filespec (ie, wildcards allowed)
;	DS:SI -> filename or filespec
;
; Outputs:
;	On success:
;		AL = drive #
;		CX = DIRENT #
;		DS:SI -> DIRENT
;		ES:DI -> driver header (DDH)
;		DX = context (1st cluster)
;	On failure, carry set
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	chk_filename,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cs
	pop	es
	ASSUME	ES:DOS
	mov	di,offset file_name	; ES:DI -> filename buffer
	push	bx
	push	ax
	call	parse_name		; DS:SI -> filename or filespec
	jc	cf9			; bail on error
;
; file_name has been successfully filled in, so we're ready to search
; directory sectors for a matching name.  This requires getting a fresh
; BPB for the drive.
;
cf4:	call	get_bpb			; DL = drive #
	jc	cf9
;
; DI -> BPB.  Start a directory search for file_name.
;
	pop	ax
	push	ax
	mov	bl,al			; BL = search attributes
	test	ah,ah
	mov	ax,0
	jnz	cf5
	dec	ax			; AX = DIRENT # (or -1)
cf5:	call	get_dirent
	jc	cf9
;
; DS:SI -> DIRENT.  Get the cluster number as the context for the SFB.
;
	xchg	cx,ax			; CX = DIRENT #
	les	di,es:[di].BPB_DEVICE	; ES:DI -> driver
	mov	al,dl			; AL = drive #
	mov	dx,[si].DIR_CLN		; DX = CLN from DIRENT

cf9:	inc	sp			; add sp,2 without affecting carry
	inc	sp
	pop	bx
	ret
ENDPROC	chk_filename

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_cln
;
; Find the CLN corresponding to CURPOS.
;
; Inputs:
;	BX -> SFB
;	DI -> BPB
;
; Outputs:
;	On success, DX = CLN, carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	find_cln,DOS
	ASSUMES	<DS,DOS>,<ES,DOS>
	mov	dx,[bx].SFB_CLN
	sub	si,si			; zero current position in CX:SI
	sub	cx,cx
;
; If our current position in CX:SI, plus CLUSBYTES, is greater than CURPOS,
; then we have reached the target cluster.
;
gc1:	add	si,[di].BPB_CLUSBYTES
	adc	cx,0
	push	cx			; save current position in CX:SI
	push	si
	sub	si,[bx].SFB_CURPOS.OFF
	sbb	cx,[bx].SFB_CURPOS.SEG
	jnc	gc9			; we've traversed enough clusters
	call	get_cln			; DX = next CLN
	pop	si
	pop	cx			; restore current position in CX:SI
	jnc	gc1
	jmp	short gc9a
gc9:	pop	si
	pop	cx
gc9a:	ret
ENDPROC	find_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_bpb
;
; As part of getting the BPB for the specified drive, this function presumes
; that the request is due to an imminent I/O request; therefore, we verify
; that the BPB is "fresh", and if it isn't, we reload it and mark it "fresh".
;
; Inputs:
;	DL = drive #
;
; Outputs:
;	On success, DI -> BPB, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, DI
;
DEFPROC	get_bpb,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cx
	push	dx
	mov	al,dl			; AL = drive #
	mov	cl,al			; save it in CL
	mov	ah,size BPBEX
	mul	ah			; AX = BPB offset
	mov	di,[bpb_table].OFF
	add	di,ax
	cmp	di,[bpb_table].SEG
	cmc
	jc	gb9			; we don't have a BPB for the drive
	push	di			; DI -> BPB
	push	es
	les	di,cs:[di].BPB_DEVICE
	mov	al,cl			; AL = drive #
	mov	ah,DDC_MEDIACHK		; perform a MEDIACHK request
	call	dev_request
	jc	gb8
	test	dx,dx			; media unchanged?
	jg	gb8			; yes
	mov	al,cl			; AL = drive #
	mov	ah,DDC_BUILDBPB		; ask the driver to rebuild our BPB
	call	dev_request
	jc	gb8
	mov	al,cl			; AL = drive #
	call	dsk_flush		; flush any buffers with data from drive
gb8:	pop	es
	pop	di
gb9:	pop	dx
	pop	cx
	ret
ENDPROC	get_bpb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_cln
;
; For the CLN in DX, get the next CLN.
;
; Inputs:
;	DI -> BPB
;
; Outputs:
;	On success, DX = CLN, carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	get_cln,DOS
	ASSUME	ES:NOTHING
	push	bx
	push	cx
	push	bp
	push	ds
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
;
; We observe that the FAT sector # containing a 12-bit CLN is:
;
;	(CLN * 12) / 4096
;
; assuming a 512-byte sector with 4096 or 2^12 bits.  The expression
; can be simplified to (CLN * 12) SHR 12, or (CLN * 3) SHR 10, or simply
; (CLN + CLN + CLN) SHR 10.
;
; TODO: If we're serious about being sector-size-agnostic, our BPB should
; contain a (precalculated) LOG2 of BPB_SECBYTES, to avoid hard-coded shifts.
;
	mov	bx,dx
	add	dx,dx
	add	dx,bx
	mov	bx,dx
	mov	cl,10
	shr	dx,cl			; DX = FAT sector ((CLN * 3) SHR 10)
	add	dx,cs:[di].BPB_RESSECS	; DX = FAT LBA
;
; Next, we need the nibble offset within the sector, which is:
;
;	((CLN * 12) % 4096) / 4
;
	and	bx,03FFh		; nibble offset (assuming 1024 nibbles)
	mov	al,cs:[di].BPB_UNIT
	mov	si,offset FAT_BUFHDR
	call	read_buffer
	jc	gc4

	mov	bp,bx			; save nibble offset in BP
	shr	bx,1			; BX -> byte, carry set if odd nibble
	mov	dl,[si+bx]
	inc	bx
	cmp	bp,03FFh		; at the sector boundary?
	jb	gc2			; no
	inc	dx			; DX = next FAT LBA
	mov	al,cs:[di].BPB_UNIT
	mov	si,offset FAT_BUFHDR
	call	read_buffer
	jc	gc4
	sub	bx,bx
gc2:	mov	dh,[si+bx]
	shr	bp,1			; was that an odd nibble again?
	jc	gc3			; yes
	and	dx,0FFFh		; no, so make sure top 4 bits clear
	jmp	short gc4		;
gc3:	mov	cl,4			;
	shr	dx,cl			; otherwise, shift all 12 bits down
	clc

gc4:	pop	ds
	pop	bp
	pop	cx
	pop	bx
	ret
ENDPROC	get_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_dirent
;
; Inputs:
;	AX = next DIRENT #, -1 if don't care
;	BL = file attributes, 0 if don't care
;	DI -> BPB
;	DS:file_name contains filename
;
; Outputs:
;	On success, DS:SI -> DIRENT, AX = DIRENT #, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, BX, CX, SI, DS
;
DEFPROC	get_dirent,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>
	push	dx
	push	bp
	sub	dx,dx
	mov	ds,dx
	ASSUME	DS:BIOS
	mov	si,offset DIR_BUFHDR
	mov	bp,es:[di].BPB_LBAROOT
	sub	cx,cx
	test	ax,ax
	jl	gd1
	mov	dx,DIRENT_SIZE		; AX = DIRENT #
	mul	dx			; DX:AX = DIRENT offset
	div	es:[di].BPB_SECBYTES	; AX = relative sector #
	mov	cx,dx			; CX = offset within sector
	mov	dx,bp
	add	dx,ax			; DX = LBA of directory sector
	jmp	short gd3

gd1:	mov	al,es:[di].BPB_DRIVE	; AL = drive #
	cmp	[si].BUF_DRIVE,al
	jne	gd2
	mov	dx,[si].BUF_LBA
	test	dx,dx
	jz	gd2
	mov	bp,dx
gd2:	mov	dx,bp

gd3:	mov	al,es:[di].BPB_DRIVE
	call	read_buffer		; AL = drive #, DX = LBA
	jc	gd7a

	mov	ax,es:[di].BPB_SECBYTES
	add	ax,si			; AX -> end of sector data
	add	si,cx			; DS:SI+CX -> DIRENT

gd5:	cmp	byte ptr [si],DIRENT_END
	je	gd6			; 0 indicates end of allocated entries
	cmp	byte ptr [si],DIRENT_DELETED
	je	gd5e
	test	bl,bl			; any attributes specified?
	jz	gd5a			; no
	mov	cl,[si].DIR_ATTR	; CL = attributes
	test	cl,bl			; any of the attributes we care about?
	jz	gd5e			; no

gd5a:	push	di
	mov	cx,11
	mov	di,offset file_name + 1	; skip drive # for DIRENT comparison
gd5b:	mov	bh,es:[di]
	inc	di
	cmp	bh,'?'
	je	gd5c
	cmp	bh,[si]
	jne	gd5d
gd5c:	lea	si,[si+1]
	loop	gd5b
gd5d:	pop	di
	je	gd8

	add	si,cx
	sub	si,11
gd5e:	add	si,size DIRENT
	cmp	si,ax
	jb	gd5

	mov	si,offset DIR_BUFHDR	; advance to next directory sector
	inc	dx
	cmp	dx,es:[di].BPB_LBADATA
	jb	gd7
gd6:	mov	dx,es:[di].BPB_LBAROOT

gd7:	sub	cx,cx			; start at offset zero of next sector
	cmp	dx,bp			; back to the 1st LBA again?
	jne	gd3			; not yet

	mov	ax,ERR_NOFILE		; out of sectors, so no match
	stc
gd7a:	jmp	short gd9

gd8:	lea	si,[si-11]		; rewind SI to matching DIRENT
	mov	cx,si
	sub	ax,es:[di].BPB_SECBYTES
	sub	cx,ax			; CX = DIRENT offset
	sub	dx,es:[di].BPB_LBAROOT
	xchg	ax,dx			; AX = relative sector #
	mul	es:[di].BPB_SECBYTES
	add	ax,cx
	mov	cx,DIRENT_SIZE
	div	cx			; AX = DIRENT #
	clc				; make sure carry is still clear

gd9:	pop	bp
	pop	dx
	ret
ENDPROC	get_dirent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_buffer
;
; Inputs:
;	AL = drive #
;	DX = LBA
;	DS:SI -> BUFHDR
;	DI -> BPB
;
; Outputs:
;	On success, DS:SI -> buffer with requested data, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, SI
;
DEFPROC	read_buffer,DOS
	ASSUMES	<DS,BIOS>,<ES,NOTHING>
	cmp	[si].BUF_DRIVE,al
	jne	rb1
	cmp	[si].BUF_LBA,dx
	jne	rb1
	add	si,size BUFHDR
	jmp	short rb9
rb1:	push	bx
	push	cx
	push	dx
	mov	[si].BUF_DRIVE,al	; AL = unit #
	mov	[si].BUF_LBA,dx
	mov	cx,[si].BUF_SIZE	; CX = byte count
	mov	bx,dx			; BX = LBA
	sub	dx,dx			; DX = offset (0)
	add	si,size BUFHDR		; DS:SI -> data buffer
	mov	ah,DDC_READ
	push	di
	push	es
	ASSERT	Z,<cmp al,cs:[di].BPB_UNIT>
	les	di,cs:[di].BPB_DEVICE
	call	dev_request
	pop	es
	pop	di
	pop	dx
	pop	cx
	pop	bx
rb9:	ret
ENDPROC	read_buffer

DOS	ends

	end
