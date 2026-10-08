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
	EXTNEAR	<alloc_cln,free_clns,sfb_open,dir_lba,get_dircln>
	EXTNEAR	<get_cdir,get_dirpath,new_buffer>

	EXTBYTE	<scb_locked>
	EXTWORD	<scb_active>
	EXTLONG	<clk_ptr,scb_table>

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
	mov	ds:[BUF_DIRTY],1
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
	jc	dr0			; no
dr6:	mov	ax,ERR_ACCDENIED
dr7:	stc
dr8:	mov	[bp].REG_AX,ax
dr9:	UNLOCK_SCB
	ret

dr0:	cmp	ax,ERR_NOFILE		; but was the new filename valid?
	jne	dr7			; no
	mov	bx,[scb_active]
	lea	si,[bx].SCB_DIRCLN	; CS:SI -> new directory and filename
	mov	ax,ERR_NOPATH
	cmp	byte ptr cs:[si+3],' '	; is the new filename blank?
	je	dr7			; yes
	mov	al,ERR_ACCDENIED
	cmp	byte ptr cs:[si+3],'.'	; is it "." or ".."?
	je	dr7			; yes
;
; Save the new directory, drive #, and filename (from SCB_DIRCLN and
; SCB_FILENAME) on the stack, since the next chk_filename call will
; overwrite them.
;
	ASSERT	<SCB_DIRCLN + 2>,EQ,<SCB_FILENAME>
	add	si,size SCB_FILENAME + 2
	mov	cx,(size SCB_FILENAME + 2) SHR 1
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
	mov	di,sp			; SS:DI -> new directory, drive #, etc
	cmp	al,ss:[di+2]		; same drive?
	mov	ax,ERR_NOTSAME
	jne	dr4			; no
	mov	cx,cs:[bx].SCB_DIRCLN
	cmp	cx,ss:[di]		; same directory?
	jne	dr4			; no (TODO: support moving files)
	mov	ax,ERR_ACCDENIED
	test	[si].DIR_ATTR,DIRATTR_VOLUME
	jnz	dr4
	cmp	[si].DIR_NAME,'.'	; is it "." or ".."?
	je	dr4			; yes
	push	ds
	pop	es
	ASSUME	ES:BIOS
	xchg	di,si			; ES:DI -> DIRENT, SS:SI -> directory
	mov	al,ss:[si+2]		; AL = drive #
	add	si,3			; SS:SI -> new filename
	mov	cx,size FCB_NAME
	REPS	MOVS,ES,SS,BYTE		; copy the new filename into the DIRENT
	mov	ds:[BUF_DIRTY],1
	call	flush_buffers		; write the modified DIRENT
	jmp	short dr5
dr4:	stc
dr5:	mov	cx,(size SCB_FILENAME + 2) SHR 1
dr5a:	pop	dx			; discard the saved filename
	loop	dr5a			; (without affecting carry)
	jnc	dr5b
	mov	[bp].REG_AX,ax
dr5b:	UNLOCK_SCB
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
	mov	al,ERR_ACCDENIED
	cmp	byte ptr cs:[di].SCB_FILENAME+1,'.'
	je	sc7			; the filename is "." or ".."
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
	mov	ds:[BUF_DIRTY],1
	mov	dl,cl			; DL = drive #
	call	get_bpb			; DI -> BPB
	jc	sc8
	mov	dx,bx			; DX = first CLN
	call	free_clns		; free the file's clusters
	jc	sc8
;
; Write the new (or updated) DIRENT (and FAT, if modified), and then open it.
;
sc5:	mov	al,ds:[BUF_DRIVE]
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
; Copy the SFB's directory, drive #, and filename to SCB_DIRCLN and
; SCB_FILENAME, so that get_dirent can verify the DIRENT at SFB_DIRNUM.
;
	mov	di,[scb_active]
	mov	ax,[bx].SFB_DIRCLN
	mov	[di].SCB_DIRCLN,ax
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
	mov	ds:[BUF_DIRTY],1
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
; Find a free (ie, unused or deleted) DIRENT in the SCB_DIRCLN directory, and
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
	sub	dx,dx			; DX = relative directory sector #
	sub	cx,cx			; CX = DIRENT #
ad1:	call	dir_lba			; AX = LBA
	jc	ad7
	push	dx
	xchg	dx,ax			; DX = LBA
	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset DIR_BUFHDR
	call	read_buffer		; DS:SI -> directory sector
	pop	dx
	jnc	ad1a
	ret
ad1a:	mov	ax,cs:[di].BPB_SECBYTES
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
	jmp	ad1
;
; The directory is full, so if it's a subdirectory, extend it with another
; cluster (DX is already the relative sector # of the new cluster).
;
ad7:	cmp	ax,ERR_NOFILE		; is the directory full?
	stc
	jne	ad9			; no, it's some other error
	call	get_dircln
	test	ax,ax			; is it the root directory?
	jz	ad7c			; yes, so it can't grow
	push	dx
	xchg	dx,ax			; DX = 1st cluster
ad7a:	mov	si,dx			; SI = current cluster
	call	get_cln			; DX = next cluster
	jc	ad7b
	mov	ax,dx
	sub	ax,2
	cmp	ax,cs:[di].BPB_CLUSTERS	; is the next cluster valid?
	jb	ad7a			; yes
	mov	dx,si			; DX = last cluster
	call	alloc_cln		; DX = new cluster (linked to the last)
	jc	ad7b
	call	init_cln		; zero the new cluster
ad7b:	pop	dx
	jnc	ad1			; search the new cluster
	ret
ad7c:	mov	ax,ERR_ACCDENIED
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
	mov	ds:[BUF_DIRTY],1
	pop	es
	ASSUME	ES:NOTHING
	pop	di
	pop	si			; DS:SI -> DIRENT
	pop	ax			; AX = DIRENT # (and carry is clear)
ad9:	ret
ENDPROC	add_dirent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_cln
;
; Zero every sector of a new directory cluster, using DIR buffers (see
; new_buffer).  The sectors are zeroed from last to first, so that the most
; recently used buffer contains the cluster's first sector (marked dirty).
;
; Inputs:
;	DX = CLN
;	DI -> BPB
;
; Outputs:
;	On success, carry clear, DS:SI -> the 1st sector's data
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, SI, DS
;
DEFPROC	init_cln,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cx
	push	dx
	push	di
	push	es
	xchg	ax,dx
	sub	ax,2
	mov	cl,cs:[di].BPB_CLUSLOG2
	shl	ax,cl
	add	ax,cs:[di].BPB_LBADATA	; AX = cluster's 1st LBA
	mov	cl,cs:[di].BPB_CLUSSECS
	mov	ch,0
	add	ax,cx			; AX = cluster's last LBA + 1
	xchg	dx,ax			; DX = LBA
ic1:	dec	dx
	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset DIR_BUFHDR
	mov	ah,0
	call	new_buffer		; DS:SI -> buffer for LBA
	jc	ic9
	ASSUME	DS:NOTHING
	mov	ds:[BUF_DIRTY],1
	push	cx
	push	di
	push	ds
	pop	es
	mov	di,si
	mov	cx,ds:[BUF_SIZE]
	shr	cx,1
	sub	ax,ax			; (and carry is clear)
	rep	stosw
	pop	di
	pop	cx
	loop	ic1
ic9:	pop	es
	pop	di
	pop	dx
	pop	cx
	ret
ENDPROC	init_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_mkdir (REG_AH = 39h)
;
; Inputs:
;	REG_DS:REG_DX -> path of new directory
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	dsk_mkdir,DOS
	LOCK_SCB
	call	chk_dirname		; DL = drive #, DI -> BPB
	jc	md8
	push	bx
	mov	ax,-1
	mov	bl,0			; BL = 0 (any attributes)
	call	get_dirent		; does the name already exist?
	pop	bx
	jnc	md6			; yes
	cmp	ax,ERR_NOFILE
	stc
	jne	md8
;
; Allocate a cluster for the new directory, and then add its DIRENT to
; the parent directory (releasing the cluster if that fails).
;
	sub	dx,dx
	call	alloc_cln		; DX = new CLN
	jc	md8
	push	dx
	mov	bl,DIRATTR_SUBDIR
	call	add_dirent		; DS:SI -> new DIRENT
	pop	dx
	jnc	md2
	push	ax
	call	free_clns		; release the new cluster
	pop	ax
	stc
	jmp	short md8
md2:	ASSUME	DS:BIOS
	mov	[si].DIR_CLN,dx
	mov	bx,dx			; BX = new CLN
	call	get_dircln
	xchg	cx,ax			; CX = parent CLN
	call	init_cln		; DS:SI -> new directory's 1st sector
	jc	md8
;
; Fill in the "." entry (with the new CLN) and ".." entry (with the
; parent CLN).
;
	push	di
	push	es
	push	ds
	pop	es
	ASSUME	ES:BIOS
	mov	di,si			; ES:DI -> 1st DIRENT
	call	get_dtime		; AX = time, DX = date
	mov	si,1			; SI = # dots in the name
md3:	push	ax
	push	cx
	mov	cx,si
	mov	al,'.'
	rep	stosb
	mov	cx,size FCB_NAME
	sub	cx,si
	mov	al,' '
	rep	stosb			; DIR_NAME
	mov	al,DIRATTR_SUBDIR
	stosb				; DIR_ATTR
	add	di,size DIR_PAD
	pop	cx
	pop	ax
	stosw				; DIR_TIME
	xchg	ax,dx
	stosw				; DIR_DATE
	xchg	ax,dx
	xchg	ax,bx
	stosw				; DIR_CLN
	xchg	ax,bx
	add	di,size DIR_SIZE
	mov	bx,cx			; BX = parent CLN (for "..")
	inc	si
	cmp	si,2
	jbe	md3
	pop	es
	ASSUME	ES:NOTHING
	pop	di
	mov	al,ds:[BUF_DRIVE]
	call	flush_buffers		; write the new directory, etc
	jnc	md9
	jmp	short md8
md6:	mov	ax,ERR_ACCDENIED
	stc
md8:	mov	[bp].REG_AX,ax
md9:	UNLOCK_SCB
	ret
ENDPROC	dsk_mkdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_rmdir (REG_AH = 3Ah)
;
; Inputs:
;	REG_DS:REG_DX -> path of directory to remove
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; Notes:
;	The directory must be empty, and it can't be the current directory
;	of any session.
;
DEFPROC	dsk_rmdir,DOS
	LOCK_SCB
	call	chk_dirname		; DL = drive #, DI -> BPB
	jc	rd0
	push	bx
	mov	ax,-1
	mov	bl,DIRATTR_SUBDIR
	call	get_dirent		; DS:SI -> DIRENT, AX = DIRENT #
	pop	bx
	jnc	rd1
	cmp	ax,ERR_NOFILE
	stc
	jne	rd0
	mov	ax,ERR_NOPATH
rd0:	jmp	rd8
	ASSUME	DS:BIOS
rd1:	push	[si].DIR_CLN		; save the directory
	push	ax			; save its DIRENT #
	call	get_dircln
	push	ax			; save its parent
	mov	si,sp
	mov	cx,ss:[si+4]		; CX = directory
;
; Make sure the directory isn't the current directory of any session.
;
	mov	bx,[scb_table].OFF
rd2:	push	bx
	mov	al,dl			; AL = drive #
	call	get_cdir		; BX -> session's current directory
	cmp	cs:[bx],cx
	pop	bx
	mov	ax,ERR_CURDIR
	stc
	je	rd7
	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	jb	rd2
;
; Make sure the directory is empty (except for "." and "..").
;
	mov	bx,[scb_active]
	mov	es:[bx].SCB_DIRCLN,cx
	push	di
	lea	di,[bx].SCB_FILENAME+1
	mov	al,'?'
	mov	cx,size FCB_NAME
	rep	stosb
	pop	di
	sub	ax,ax			; start with DIRENT # 0
rd3:	mov	bl,0			; BL = 0 (any attributes)
	call	get_dirent		; DS:SI -> DIRENT, AX = DIRENT #
	jc	rd4
	inc	ax			; AX = next DIRENT #
	cmp	[si].DIR_NAME,'.'	; "." or ".."?
	je	rd3			; yes
	mov	ax,ERR_ACCDENIED	; no, so the directory isn't empty
	stc
	jmp	short rd7
rd4:	cmp	ax,ERR_NOFILE		; did we run out of entries?
	stc
	jne	rd7			; no, some other error
;
; Find its DIRENT in the parent again (using the "?" name and its DIRENT #),
; delete it, and then free the directory's clusters.
;
	pop	ax			; AX = parent
	mov	bx,[scb_active]
	mov	es:[bx].SCB_DIRCLN,ax
	pop	ax			; AX = DIRENT #
	mov	bl,DIRATTR_SUBDIR
	call	get_dirent		; DS:SI -> DIRENT
	pop	dx			; DX = directory
	jc	rd8
	mov	[si].DIR_NAME,DIRENT_DELETED
	mov	ds:[BUF_DIRTY],1
	call	free_clns		; free the directory's clusters
	jc	rd8
	mov	al,ds:[BUF_DRIVE]
	call	flush_buffers		; write the modified DIRENT and FAT
	jnc	rd9
	jmp	short rd8
rd7:	pop	cx			; discard the saved values
	pop	cx			; (without affecting carry)
	pop	cx
rd8:	mov	[bp].REG_AX,ax
rd9:	UNLOCK_SCB
	ret
ENDPROC	dsk_rmdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_dirname
;
; Parse the path at REG_DS:REG_DX for dsk_mkdir or dsk_rmdir, whose final
; name can't be blank, ".", or "..".
;
; Inputs:
;	REG_DS:REG_DX -> path
;
; Outputs:
;	Same as get_path (and BX -> active SCB, ES = DOS)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	chk_dirname,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	call	get_dirpath		; DL = drive #, DI -> BPB
	jc	cn9
	ASSUME	ES:DOS
	mov	al,es:[bx].SCB_FILENAME+1
	cmp	al,' '			; blank?
	je	cn8			; yes
	cmp	al,'.'			; "." or ".."?
	clc
	jne	cn9			; no
cn8:	mov	ax,ERR_ACCDENIED
	stc
cn9:	ret
ENDPROC	chk_dirname

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
