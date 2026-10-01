;
; BASIC-DOS File Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dev.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<dev_request,chk_devname,chk_filename,scb_release>
	EXTNEAR	<get_bpb,get_cln,get_dirent,read_buffer,flush_buffers>
	EXTNEAR	<alloc_cln,free_clns,sfb_open>

	EXTBYTE	<scb_locked>
	EXTWORD	<scb_active>
	EXTLONG	<clk_ptr>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_delete (REG_AH = 41h)
;
; Inputs:
;	REG_DS:REG_DX -> name of file
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; Notes:
;	Like PC DOS, we make no attempt to detect whether the file is open.
;
DEFPROC	dsk_delete,DOS
	LOCK_SCB
	mov	si,dx
	mov	ds,[bp].REG_DS		; DS:SI -> filename
	ASSUME	DS:NOTHING
	sub	ax,ax			; AH = 0 (filename), AL = 0 (attributes)
	call	chk_filename		; DS:SI -> DIRENT, AL = drive #
	jc	dd8
	ASSUME	DS:BIOS
	mov	cl,al			; CL = drive #
	mov	ax,ERR_ACCDENIED
	test	[si].DIR_ATTR,DIRATTR_RDONLY OR DIRATTR_SUBDIR OR DIRATTR_VOLUME
	jnz	dd7
	mov	byte ptr [si].DIR_NAME,DIRENT_DELETED
	mov	[DIR_BUFHDR].BUF_DIRTY,1
	mov	bx,[si].DIR_CLN		; BX = first CLN
	mov	dl,cl			; DL = drive #
	call	get_bpb			; DI -> BPB
	jc	dd8
	mov	dx,bx			; DX = first CLN
	call	free_clns		; free the file's clusters
	jc	dd8
	mov	al,cl			; AL = drive #
	call	flush_buffers		; write the modified DIRENT and FAT
	jnc	dd9
	jmp	short dd8
dd7:	stc
dd8:	mov	[bp].REG_AX,ax
dd9:	UNLOCK_SCB
	ret
ENDPROC	dsk_delete

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_rename (REG_AH = 56h)
;
; Inputs:
;	REG_DS:REG_DX -> name of existing file
;	REG_ES:REG_DI -> new name for file
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	dsk_rename,DOS
	LOCK_SCB
	mov	si,di
	mov	ds,[bp].REG_ES		; DS:SI -> new filename
	ASSUME	DS:NOTHING
	sub	ax,ax			; AH = 0 (filename), AL = 0 (attributes)
	call	chk_filename		; does the new filename already exist?
	jnc	dr6			; yes
	cmp	ax,ERR_NOFILE		; no, but was the new filename valid?
	jne	dr7			; no
	mov	bx,[scb_active]
	lea	si,[bx].SCB_FILENAME	; CS:SI -> new drive # and filename
	mov	ax,ERR_NOPATH
	cmp	byte ptr cs:[si+1],' '	; is the new filename blank?
	je	dr7			; yes
;
; Save the new drive # and filename (from SCB_FILENAME) on the stack, since
; the next chk_filename call will overwrite it.
;
	add	si,size SCB_FILENAME
	mov	cx,size SCB_FILENAME SHR 1
dr1:	dec	si
	dec	si
	push	word ptr cs:[si]
	loop	dr1

	mov	si,[bp].REG_DX
	mov	ds,[bp].REG_DS		; DS:SI -> existing filename
	sub	ax,ax			; AH = 0 (filename), AL = 0 (attributes)
	call	chk_filename		; DS:SI -> DIRENT, AL = drive #
	jc	dr5
	ASSUME	DS:BIOS
	mov	di,sp			; SS:DI -> new drive # and filename
	cmp	al,ss:[di]		; same drive?
	mov	ax,ERR_NOTSAME
	jne	dr4			; no
	mov	ax,ERR_ACCDENIED
	test	[si].DIR_ATTR,DIRATTR_VOLUME
	jnz	dr4
	push	ds
	pop	es
	ASSUME	ES:BIOS
	xchg	di,si			; ES:DI -> DIRENT, SS:SI -> drive #
	mov	al,ss:[si]		; AL = drive #
	inc	si			; SS:SI -> new filename
	mov	cx,size FCB_NAME
	REPS	MOVS,ES,SS,BYTE		; copy the new filename into the DIRENT
	mov	[DIR_BUFHDR].BUF_DIRTY,1
	call	flush_buffers		; write the modified DIRENT
	jmp	short dr5
dr4:	stc
dr5:	mov	cx,size SCB_FILENAME SHR 1
dr5a:	pop	dx			; discard the saved filename
	loop	dr5a			; (without affecting carry)
	jnc	dr9
	jmp	short dr8
dr6:	mov	ax,ERR_ACCDENIED
dr7:	stc
dr8:	mov	[bp].REG_AX,ax
dr9:	UNLOCK_SCB
	ret
ENDPROC	dsk_rename

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_create
;
; Creates a new file, or truncates an existing file, and then opens it for
; reading and writing.  If the name is a device name, the device is simply
; opened.
;
; Inputs:
;	CL = attributes (see DIRATTR_*)
;	DS:SI -> name of device/file
;
; Outputs:
;	On success, BX -> SFB, DX = context (if any), carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	sfb_create,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	LOCK_SCB
	push	si
	push	ds
	push	es
	and	cl,DIRATTR_RDONLY OR DIRATTR_HIDDEN OR DIRATTR_SYSTEM OR DIRATTR_ARCHIVE
	mov	bl,cl			; BL = attributes
	call	chk_devname		; is it a device name?
	jc	sc1			; no
	jmp	sc6			; yes, so just open the device
sc1:	sub	ax,ax			; AH = 0 (filename), AL = 0 (attributes)
	call	chk_filename		; does the file already exist?
	jnc	sc3			; yes
	cmp	ax,ERR_NOFILE		; no, but was the filename valid?
	jne	sc7			; no
;
; The file doesn't exist, and SCB_FILENAME contains the drive # and name of
; the new file, so add a DIRENT for it.
;
	mov	di,[scb_active]
	mov	dl,cs:[di].SCB_FILENAME	; DL = drive #
	mov	ax,ERR_NOPATH
	cmp	byte ptr cs:[di].SCB_FILENAME+1,' '
	je	sc7			; the filename is blank
	call	get_bpb			; DI -> BPB
	jc	sc8
	call	add_dirent		; DS:SI -> new DIRENT
	jc	sc8
	ASSUME	DS:BIOS
	jmp	short sc5
;
; The file already exists (DS:SI -> DIRENT, AL = drive #), so truncate it,
; unless it's read-only (or not a file at all).
;
sc3:	mov	cl,al			; CL = drive #
	mov	ax,ERR_ACCDENIED
	test	[si].DIR_ATTR,DIRATTR_RDONLY OR DIRATTR_SUBDIR OR DIRATTR_VOLUME
	jnz	sc7
	mov	[si].DIR_ATTR,bl
	call	get_dtime		; AX = time, DX = date
	mov	[si].DIR_TIME,ax
	mov	[si].DIR_DATE,dx
	sub	bx,bx
	mov	[si].DIR_SIZE.LOW,bx
	mov	[si].DIR_SIZE.HIW,bx
	xchg	bx,[si].DIR_CLN		; BX = first CLN (and zero DIR_CLN)
	mov	[DIR_BUFHDR].BUF_DIRTY,1
	mov	dl,cl			; DL = drive #
	call	get_bpb			; DI -> BPB
	jc	sc8
	mov	dx,bx			; DX = first CLN
	call	free_clns		; free the file's clusters
	jc	sc8
;
; Write the new (or updated) DIRENT (and FAT, if modified), and then open it.
;
sc5:	mov	al,[DIR_BUFHDR].BUF_DRIVE
	call	flush_buffers
	jc	sc8
sc6:	pop	es
	pop	ds
	pop	si
	ASSUME	DS:NOTHING, ES:NOTHING
	mov	bl,MODE_ACC_RW		; BL = mode
	call	sfb_open
	jmp	short sc9
sc7:	stc
sc8:	pop	es
	pop	ds
	pop	si
sc9:	UNLOCK_SCB
	ret
ENDPROC	sfb_create

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_commit
;
; Update the DIRENT for a modified file (ie, its time, date, first cluster,
; and size), and then write all modified buffers for the file's drive.
;
; Inputs:
;	BX -> SFB
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX
;
DEFPROC	sfb_commit,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	push	cs
	pop	es
	ASSUME	ES:DOS
;
; Copy the SFB's drive # and filename to SCB_FILENAME, so that get_dirent
; can verify the DIRENT at SFB_DIRNUM.
;
	mov	di,[scb_active]
	lea	di,[di].SCB_FILENAME	; ES:DI -> SCB_FILENAME
	mov	al,[bx].SFB_DRIVE
	stosb
	mov	si,bx			; DS:SI -> SFB_NAME
	mov	cx,size SFB_NAME
	rep	movsb
	mov	dl,al			; DL = drive #
	call	get_bpb			; DI -> BPB
	jc	scm9
	push	bx
	mov	ax,[bx].SFB_DIRNUM	; AX = DIRENT #
	mov	bl,0			; BL = attributes (none)
	call	get_dirent		; DS:SI -> DIRENT
	pop	bx
	jc	scm9
	ASSUME	DS:BIOS
	call	get_dtime		; AX = time, DX = date
	mov	cs:[bx].SFB_TIME,ax
	mov	cs:[bx].SFB_DATE,dx
	mov	[si].DIR_TIME,ax
	mov	[si].DIR_DATE,dx
	mov	ax,cs:[bx].SFB_CLN
	mov	[si].DIR_CLN,ax
	mov	ax,cs:[bx].SFB_SIZE.LOW
	mov	[si].DIR_SIZE.LOW,ax
	mov	ax,cs:[bx].SFB_SIZE.HIW
	mov	[si].DIR_SIZE.HIW,ax
	or	[si].DIR_ATTR,DIRATTR_ARCHIVE
	mov	[DIR_BUFHDR].BUF_DIRTY,1
	and	cs:[bx].SFB_FLAGS,NOT SFBF_DIRTY
	mov	al,cs:[bx].SFB_DRIVE
	call	flush_buffers		; write the DIRENT (and FAT)

scm9:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	sfb_commit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_file (called by sfb_write for block devices)
;
; Inputs:
;	AL = I/O mode (not used)
;	BX -> SFB
;	CX = byte count
;	DS:SI -> data buffer
;
; Outputs:
;	On success, carry clear, AX = bytes written
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, BX, DX, DI, ES
;
; Notes:
;	Like PC DOS, running out of disk space is not treated as an error;
;	the number of bytes returned will simply be less than requested.
;
DEFPROC	write_file,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	LOCK_SCB
	push	cx
	push	si
	push	ds
	mov	word ptr [bp].TMP_AX,0	; use TMP_AX to accumulate bytes written
	mov	[bp].TMP_ES,ds
	mov	[bp].TMP_DX,si		; TMP_ES:TMP_DX -> data buffer
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	ax,ERR_ACCDENIED
	test	[bx].SFB_MODE,MODE_ACC_WO OR MODE_ACC_RW
	jz	wf7			; file was not opened for writing
	mov	dl,[bx].SFB_DRIVE
	call	get_bpb			; DI -> BPB if no error
	jnc	wf1
	jmp	short wf9

wf7:	stc
	jmp	short wf9
wf8:	mov	ax,[bp].TMP_AX		; AX = total bytes written
	clc
wf9:	pop	ds
	ASSUME	DS:NOTHING
	pop	si
	pop	cx
	UNLOCK_SCB
	ret

	ASSUME	DS:DOS
wf1:	jcxz	wf8			; nothing (more) to write
	call	get_wcln		; DX = CLN for CURPOS
	jnc	wf2
	cmp	ax,ERR_DISKFULL		; out of disk space?
	je	wf8			; yes, return the bytes written so far
	jmp	wf7
;
; Convert the cluster # (DX) and CURPOS into an LBA (BX) and offset (DX).
;
wf2:	mov	[bx].SFB_CURCLN,dx
	push	bx			; save SFB pointer
	push	di			; save BPB pointer
	push	cx			; save byte count
	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	and	ax,[bx].SFB_CURPOS.LOW	; AX = offset within current cluster
	mov	bx,dx
	sub	bx,2
	mov	cl,[di].BPB_CLUSLOG2
	shl	bx,cl
	add	bx,[di].BPB_LBADATA	; BX = LBA
;
; We're almost ready to write, except for the byte count in CX, which must be
; limited to whatever fits in the current cluster.
;
	pop	cx			; CX = byte count
	push	cx
	mov	dx,[di].BPB_CLUSBYTES
	sub	dx,ax			; DX = bytes available in cluster
	cmp	cx,dx			; if CX <= DX, we're fine
	jbe	wf3
	mov	cx,dx			; reduce CX
wf3:	xchg	dx,ax			; DX = offset within cluster
	mov	ah,DDC_WRITE
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
	mov	dx,cx			; DX = bytes written (assuming no error)
	pop	cx			; restore byte count
	pop	di			; BPB pointer restored
	pop	bx			; SFB pointer restored
	jc	wf9
;
; Time for some bookkeeping: adjust the SFB's CURPOS by DX, and if CURPOS
; is now beyond SIZE, then update SIZE as well.
;
	add	[bx].SFB_CURPOS.LOW,dx
	adc	[bx].SFB_CURPOS.HIW,0
	add	[bp].TMP_AX,dx		; update accumulation of bytes written
	add	[bp].TMP_DX,dx		; update data buffer offset
	or	[bx].SFB_FLAGS,SFBF_DIRTY
	mov	ax,[bx].SFB_CURPOS.LOW
	mov	si,[bx].SFB_CURPOS.HIW
	cmp	si,[bx].SFB_SIZE.HIW
	jb	wf5
	ja	wf4
	cmp	ax,[bx].SFB_SIZE.LOW
	jbe	wf5
wf4:	mov	[bx].SFB_SIZE.LOW,ax
	mov	[bx].SFB_SIZE.HIW,si
;
; As in sfb_read, if CURPOS is now at a cluster boundary, advance SFB_CURCLN
; to the next cluster, or zero it if there is no next cluster (get_wcln will
; extend the chain if and when another write occurs).
;
wf5:	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	test	[bx].SFB_CURPOS.LOW,ax	; is CURPOS at a cluster boundary?
	jnz	wf6			; no
	push	dx
	sub	dx,dx
	xchg	dx,[bx].SFB_CURCLN	; DX = current CLN (and zero SFB_CURCLN)
	call	get_cln			; DX = next CLN
	jc	wf5a
	mov	ax,dx
	sub	ax,2
	cmp	ax,[di].BPB_CLUSTERS	; is the next CLN valid?
	jae	wf5a			; no
	mov	[bx].SFB_CURCLN,dx	; yes
wf5a:	pop	dx
wf6:	sub	cx,dx			; reduce the write count
	jmp	wf1			; and keep writing clusters
ENDPROC	write_file

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_wcln (see also: find_cln in disk.asm)
;
; Find the CLN corresponding to CURPOS for writing, which means allocating
; the file's first cluster and/or extending its cluster chain as needed.
;
; Inputs:
;	BX -> SFB
;	DI -> BPB
;
; Outputs:
;	On success, carry clear, DX = CLN
;	On failure, carry set, AX = error code (eg, ERR_DISKFULL)
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	get_wcln,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	mov	dx,[bx].SFB_CURCLN
	mov	ax,dx
	sub	ax,2
	cmp	ax,[di].BPB_CLUSTERS	; is CURCLN a valid data cluster?
	jae	gw1			; no
	clc
	ret
;
; We have to walk the cluster chain, so convert CURPOS to a cluster index.
;
gw1:	push	cx
	mov	ax,[bx].SFB_CURPOS.LOW
	mov	dx,[bx].SFB_CURPOS.HIW
	cmp	dx,[di].BPB_CLUSBYTES	; would the division overflow?
	jae	gw7			; yes (the position is far too large)
	div	[di].BPB_CLUSBYTES	; AX = cluster index
	xchg	cx,ax			; CX = cluster index
	mov	dx,[bx].SFB_CLN		; DX = first CLN
	test	dx,dx			; does the file have any clusters yet?
	jnz	gw2			; yes
	call	alloc_cln		; DX = new CLN (with no previous CLN)
	jc	gw8
	mov	[bx].SFB_CLN,dx
	mov	[bx].SFB_CONTEXT,dx
gw2:	jcxz	gw8			; carry is clear
gw3:	mov	si,dx			; SI = current CLN
	call	get_cln			; DX = next CLN
	jc	gw8
	mov	ax,dx
	sub	ax,2
	cmp	ax,[di].BPB_CLUSTERS	; is the next CLN valid?
	jb	gw4			; yes
	mov	dx,si			; no, so extend the chain
	call	alloc_cln		; DX = new CLN (linked to SI)
	jc	gw8
gw4:	loop	gw3
	clc
	jmp	short gw8
gw7:	mov	ax,ERR_DISKFULL
	stc
gw8:	pop	cx
	ret
ENDPROC	get_wcln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_dirent
;
; Find a free (ie, unused or deleted) DIRENT in the root directory, and
; initialize it with the name in SCB_FILENAME, the specified attributes, the
; current time and date, and zero for both the first cluster and file size.
;
; Inputs:
;	BL = attributes
;	DI -> BPB
;	SCB_FILENAME contains the filename
;
; Outputs:
;	On success, carry clear, DS:SI -> DIRENT, AX = DIRENT #
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, CX, DX, SI, DS
;
DEFPROC	add_dirent,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	dx,cs:[di].BPB_LBAROOT	; DX = LBA of 1st directory sector
	sub	cx,cx			; CX = DIRENT #
ad1:	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset DIR_BUFHDR
	call	read_buffer		; DS:SI -> directory sector
	jc	ad9
	mov	ax,cs:[di].BPB_SECBYTES
	add	ax,si			; AX -> end of sector data
ad2:	cmp	byte ptr [si],DIRENT_END
	je	ad8
	cmp	byte ptr [si],DIRENT_DELETED
	je	ad8
	add	si,size DIRENT
	inc	cx
	cmp	si,ax
	jb	ad2
	inc	dx			; advance to the next directory sector
	cmp	dx,cs:[di].BPB_LBADATA
	jb	ad1
	mov	ax,ERR_ACCDENIED	; the directory is full
	stc
	ret

ad8:	push	cx			; save DIRENT #
	push	si			; save DIRENT address
	push	di
	push	es
	push	ds
	pop	es
	ASSUME	ES:BIOS
	mov	di,si			; ES:DI -> DIRENT
	mov	si,[scb_active]
	lea	si,[si].SCB_FILENAME+1	; CS:SI -> filename
	mov	cx,size FCB_NAME
	REPS	MOVS,ES,CS,BYTE		; DIR_NAME
	mov	al,bl
	stosb				; DIR_ATTR
	sub	ax,ax
	mov	cx,size DIR_PAD SHR 1
	rep	stosw			; DIR_PAD
	call	get_dtime		; AX = time, DX = date
	stosw				; DIR_TIME
	xchg	ax,dx
	stosw				; DIR_DATE
	sub	ax,ax
	stosw				; DIR_CLN
	stosw				; DIR_SIZE.LOW
	stosw				; DIR_SIZE.HIW
	mov	[DIR_BUFHDR].BUF_DIRTY,1
	pop	es
	ASSUME	ES:NOTHING
	pop	di
	pop	si			; DS:SI -> DIRENT
	pop	ax			; AX = DIRENT # (and carry is clear)
ad9:	ret
ENDPROC	add_dirent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_dtime
;
; Get the current time and date in "packed" DIRENT format (see DIR_TIME and
; DIR_DATE in disk.inc).
;
; Inputs:
;	None
;
; Outputs:
;	AX = time
;	DX = date
;
; Modifies:
;	AX, DX
;
DEFPROC	get_dtime,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	di
	push	es
	les	di,cs:[clk_ptr]
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_GETTIME
	call	dev_request		; DX = time
	push	dx
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_GETDATE
	call	dev_request		; DX = date
	pop	ax			; AX = time
	pop	es
	pop	di
	ret
ENDPROC	get_dtime

DOS	ends

	end
