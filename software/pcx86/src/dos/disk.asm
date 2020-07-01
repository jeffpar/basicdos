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

	EXTERNS	<dev_request>,near

	EXTERNS	<scb_active>,word
	EXTERNS	<bpb_table>,dword
	EXTERNS	<bpb_total,file_name>,byte

	EXTERNS	<VALID_CHARS>,byte
	EXTERNS	<VALID_COUNT>,abs

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
DEFPROC	dsk_setdrv,DOS
	mov	bx,[scb_active]
	mov	[bx].SCB_CURDRV,dl
	mov	al,[bpb_total]		; AL = # drives (TODO: physical only)
	mov	[bp].REG_AL,al
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
	mov	al,[bp].REG_CL
	mov	ah,1			; AH = 1 (filespec)
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
	mov	si,offset file_name	; FFB_FILESPEC
	rep movs byte ptr es:[di],byte ptr cs:[si]
	pop	si
	pop	cx
	add	di,size FFB_PADDING
	xchg	ax,cx
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
ff1:	lodsb
	cmp	al,' '
	je	ff2
	stosb				; FFB_NAME
ff2:	loop	ff1
	mov	al,[si]
	cmp	al,' '
	je	ff5
	mov	al,'.'
	stosb
	mov	cx,3
ff3:	lodsb
	cmp	al,' '
	je	ff4
	stosb
ff4:	loop	ff3
ff5:	sub	ax,ax
	stosb
	jnc	ff9
ff8:	mov	[bp].REG_AX,ax
ff9:	ret
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
	mov	bx,[scb_active]
	lds	si,cs:[bx].SCB_DTA	; DS:SI -> DTA (FFB)
	ASSUME	DS:NOTHING
	mov	dl,[si].FFB_DRIVE
	push	si
	lea	si,[si].FFB_FILESPEC
	mov	di,offset file_name
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
	xchg	cx,ax			; CX = DIRENT #
	mov	ax,dx			; AL = drive #, AH = search attributes
	jmp	dsk_ffill
fn8:	mov	[bp].REG_AX,ax
	ret
ENDPROC	dsk_fnext

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_filename
;
; Inputs:
;	AL = search attributes (0 if none)
;	AH = 0 for filename, 1 for filespec (ie, wildcards allowed)
;	DS:SI -> name
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
;
; See if the name begins with a drive letter.  If so, convert to a drive
; number and then skip over it; otherwise, use SCB_CURDRV as the drive number.
;
	push	bx
	push	ax
	mov	bx,[scb_active]
	ASSERT	STRUCT,es:[bx],SCB
	mov	dl,es:[bx].SCB_CURDRV	; DL = default drive number
	mov	dh,8			; DH is current file_name limit
	sub	bx,bx			; BL is current file_name position
	mov	di,offset file_name
	mov	cx,11
	mov	al,' '
	rep	stosb			; initialize file_name
	cmp	byte ptr [si+1],':'	; check for drive letter
	jne	cf1
	lodsb				; AL = drive letter
	sub	al,'A'
	jb	cf9			; error
	cmp	al,26
	cmc
	jb	cf9
	inc	si
	mov	dl,al			; DL = specified drive number
;
; Build file_name at ES:BX from the string at DS:SI, making sure that all
; characters exist within VALID_CHARS.
;
cf1:	lodsb				; get next char
	test	al,al			; terminating null?
	jz	cf4			; yes, end of name
	cmp	al,'.'			; period?
	jne	cf2			; no
	mov	bl,8			; BL -> file_name extension
	mov	dh,11			; DH -> file_name limit
	jmp	cf1
cf2:	cmp	al,'a'
	jb	cf3
	cmp	al,'z'
	ja	cf3
	sub	al,20h
cf3:	test	ah,ah			; filespec?
	jz	cf3a			; no
	cmp	al,'?'			; wildcard?
	je	cf3b			; yes
	cmp	al,'*'			; asterisk?
	je	cf3c			; yes
cf3a:	mov	cx,VALID_COUNT
	mov	di,offset VALID_CHARS
	repne	scasb
	stc
	jne	cf9			; invalid character
cf3b:	cmp	bl,dh
	jae	cf1			; valid character but we're at limit
	mov	es:[file_name][bx],al	; store it
	inc	bx
	jmp	cf1
cf3c:	cmp	bl,dh
	jae	cf1
	mov	es:[file_name][bx],'?'	; store '?' until we reach the limit
	inc	bx
	jmp	cf3c
;
; file_name has been successfully filled in, so we're ready to search
; directory sectors for a matching name.  This requires getting a fresh
; BPB for the drive.
;
cf4:	call	get_bpb			; DL = drive #
	jc	cf9
;
; ES:DI -> BPB.  Start a directory search for file_name.
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
	push	dx
	mov	al,dl			; AL = drive #
	mov	ah,size BPBEX
	mul	ah			; AX = BPB offset
	mov	di,[bpb_table].off
	add	di,ax
	cmp	di,[bpb_table].SEG
	cmc
	jc	gb9			; we don't have a BPB for the drive
	push	di			; ES:DI -> BPB
	push	es
	les	di,cs:[di].BPB_DEVICE
	mov	ah,DDC_MEDIACHK		; perform a MEDIACHK request
	call	dev_request
	jc	gb8
	test	dx,dx			; media unchanged?
	jg	gb8			; yes
	mov	ah,DDC_BUILDBPB		; ask the driver to rebuild our BPB
	call	dev_request
	jc	gb8
	call	dsk_flush		; flush any buffers with data from drive
gb8:	pop	es
	pop	di
gb9:	pop	dx
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
	push	bx
	push	cx
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
	add	dx,es:[di].BPB_RESSECS	; DX = FAT LBA
;
; Next, we need the nibble offset within the sector, which is:
;
;	((CLN * 12) % 4096) / 4
;
	and	bx,03FFh		; nibble offset (assuming 1024 nibbles)
	mov	al,es:[di].BPB_UNIT
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
	mov	al,es:[di].BPB_UNIT
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
;	ES:DI -> BPB
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
	ASSUMES	<DS,NOTHING>,<ES,DOS>	; ES = DOS since BPBs are in DOS
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

gd3:	call	read_buffer		; AL = drive #, DX = LBA
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
	mov	di,offset file_name
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
	mov	al,es:[di].BPB_DRIVE
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
;	ES:DI -> BPB
;
; Outputs:
;	On success, DS:SI -> buffer with requested data, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, SI
;
DEFPROC	read_buffer,DOS
	ASSUMES	<DS,BIOS>,<ES,DOS>	; ES = DOS since BPBs are in DOS
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
	ASSERT	Z,<cmp al,es:[di].BPB_UNIT>
	les	di,es:[di].BPB_DEVICE
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
