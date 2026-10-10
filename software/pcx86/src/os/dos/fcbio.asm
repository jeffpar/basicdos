;
; BASIC-DOS FCB Services
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
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTBYTE	<bpb_total,scb_locked>
	EXTWORD	<scb_active>
	EXTNEAR	<sfb_open_fcb,sfb_find_fcb,sfb_seek,sfb_read,sfb_write>
	EXTNEAR	<sfb_close,sfb_chkopen,chk_filename,chk_devname,chk_volopen>
	EXTNEAR	<chk_dirent,del_dirent,add_dirent,get_dirent,get_dtime>
	EXTNEAR	<get_bpb,get_cdir,free_clns,flush_buffers,scb_release>
	EXTNEAR	<div_32_16,mul_32_16>

	EXTSTR	<FILENAME_CHARS>

;
; A rename FCB holds the new name at offset 11h, and rename_fcb builds the
; new drive # and name on the stack (in RENBUF bytes).
;
FCB_NEWNAME	equ	11h
RENBUF		equ	size FCB_DRIVE + size FCB_NAME
;
; These are the only attributes that a new (or truncated) file can be given.
;
ATTR_RHS	equ	DIRATTR_RDONLY OR DIRATTR_HIDDEN OR DIRATTR_SYSTEM
ATTR_CREATE	equ	ATTR_RHS OR DIRATTR_ARCHIVE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_create (REG_AH = 16h)
;
; Creates a file (or truncates an existing file) and opens it as fcb_open
; does, except that its SFB is opened for reading and writing.  An extended
; FCB supplies the attributes of the file.
;
; Inputs:
;	REG_DS:REG_DX -> unopened normal or extended FCB
;
; Outputs:
;	REG_AL = 00h if created, FFh otherwise
;	FCB filled in (see fcb_open) on success
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	fcb_create,DOS
	call	fcb_ptr			; DS:SI -> FCB, AL = attributes
	xchg	cx,ax			; CL = attributes
	mov	ax,1000h		; AH = 10h (FCB), AL = 0
	call	sfb_create_fcb		; BX -> SFB
	jmp	short fo0
ENDPROC	fcb_create

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_open (REG_AH = 0Fh)
;
; Opens a file (or device) and initializes its FCB, leaving CURREC and RELREC
; alone.
;
; The SFB is opened read-only, so that (as in PC DOS) any number of FCBs and
; handles can open the same file; write_fcb upgrades it to read-write when the
; FCB is first used to write.
;
; Inputs:
;	REG_DS:REG_DX -> unopened normal or extended FCB
;
; Outputs:
;	REG_AL = 00h if opened, FFh otherwise
;	FCB_DRIVE = 1-based drive # (0 for a device)
;	FCB_CURBLK = 0, FCB_RECSIZE = 128
;	FCBF_FILESIZE, FCBF_DATE, FCBF_TIME, and FCBF_CLN filled in
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	fcb_open,DOS
	call	fcb_ptr			; DS:SI -> FCB, AL = attributes
	mov	ah,10h			; AH = 10h (FCB)
	mov	bl,MODE_ACC_RO		; BL = mode
	call	sfb_open_fcb		; BX -> SFB
fo0:	mov	byte ptr [bp].REG_AL,0FFh
	jc	fo9			; failed
	mov	di,si
	push	ds
	pop	es			; ES:DI -> FCB
	mov	si,bx
	push	cs
	pop	ds			; DS:SI -> SFB
	ASSUME	DS:DOS, ES:NOTHING
	mov	[si].SFB_FCB.OFF,di
	mov	[si].SFB_FCB.SEG,es	; set SFB_FCB
	or	[si].SFB_FLAGS,SFBF_FCB	; and mark the SFB as an FCB's
	mov	al,[si].SFB_DRIVE
	inc	ax
	mov	es:[di].FCB_DRIVE,al	; set FCB_DRIVE to 1-based drive #
	add	si,SFB_SIZE		; DS:SI -> SFB.SFB_SIZE
	add	di,FCB_CURBLK		; ES:DI -> FCB.FCB_CURBLK
	sub	ax,ax
	mov	[bp].REG_AL,al		; set REG_AL to zero
	stosw				; set FCB_CURBLK to zero
	mov	al,128
	stosw				; set FCB_RECSIZE to 128
	movsw
	movsw				; set FCBF_FILESIZE from SFB_SIZE
	sub	si,(SFB_SIZE + 4) - SFB_DATE
	movsw				; set FCBF_DATE from SFB_DATE
	sub	si,(SFB_DATE + 2) - SFB_TIME
	movsw				; set FCBF_TIME from SFB_TIME
	inc	di			; skip FCBF_DEVICE
	add	si,SFB_CLN - (SFB_TIME + 2)
	movsw				; set FCBF_CLN from SFB_CLN
fo9:	ret
ENDPROC	fcb_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_close (REG_AH = 10h)
;
; Closes the SFB of an opened FCB, which updates the file's DIRENT if the
; file was modified.
;
; Inputs:
;	REG_DS:REG_DX -> opened normal or extended FCB
;
; Outputs:
;	REG_AL = 00h if closed, FFh otherwise
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	fcb_close,DOS
	call	get_fcb			; DS:BX -> SFB
	jc	fc8
;
; The SFB may outlive the FCB (eg, if the FCB shared the session's console
; SFB), so it must no longer be found by sfb_find_fcb.
;
	and	[bx].SFB_FLAGS,NOT SFBF_FCB
	mov	si,-1			; SI = PFH (none)
	call	sfb_close
	mov	al,0
	jnc	fc9
fc8:	mov	al,0FFh
fc9:	mov	[bp].REG_AL,al
	ret
ENDPROC	fcb_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_sread, fcb_swrite, fcb_rread, fcb_rwrite, fcb_rbread, fcb_rbwrite
;
; Transfer sequential (14h/15h), random (21h/22h), or random block (27h/28h)
; records through the DTA.  Sequential calls advance CURBLK and CURREC without
; changing RELREC.  Single random calls set CURBLK and CURREC from RELREC
; without advancing anything.  Block calls advance RELREC, CURBLK, and CURREC
; by the number of records transferred, including a padded last record.  A
; zero-record block write truncates (or extends) the file to RELREC.
;
; Inputs:
;	REG_DS:REG_DX -> opened normal or extended FCB
;	REG_CX = record count (block calls only)
;
; Outputs:
;	REG_AL = FCBERR result
;	REG_CX = records transferred (block calls only)
;	FCBF_FILESIZE updated after writes
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	fcb_sread,DOS
	DEFLBL	fcb_swrite,near
	DEFLBL	fcb_rread,near
	DEFLBL	fcb_rwrite,near
	DEFLBL	fcb_rbread,near
	DEFLBL	fcb_rbwrite,near
	call	get_fcb			; DS:BX -> SFB, ES:DI -> FCB
	jc	fio0
	ASSUME	DS:DOS, ES:NOTHING
	mov	byte ptr [bp].REG_AL,FCBERR_EOF
	mov	cx,es:[di].FCB_RECSIZE	; CX = record size
	jcxz	fio0			; nothing can be transferred
;
; Sequential calls start at the record that CURBLK and CURREC refer to, and
; random calls start at RELREC (and set CURBLK and CURREC to match).
;
	cmp	byte ptr [bp].REG_AH,DOS_FCB_RREAD
	jae	fio1
	call	seq_fcb			; DX:AX = current record #
	jmp	short fio2
fio0:	ret
fio1:	call	get_relrec		; DX:AX = RELREC
	call	setcur_fcb
fio2:	call	mul_32_16		; DX:AX = record # * record size
	xchg	dx,ax
	xchg	cx,ax			; CX:DX = file position
	mov	al,SEEK_BEG
	call	sfb_seek
	mov	ax,1			; AX = 1 record
	cmp	byte ptr [bp].REG_AH,DOS_FCB_RBREAD
	jb	fio3
	mov	ax,[bp].REG_CX		; AX = # records (for block calls)
fio3:	mul	es:[di].FCB_RECSIZE	; DX:AX = # bytes
;
; Never allow a transfer to wrap around the end of the DTA's segment.
;
	test	dx,dx
	jnz	fio7
	mov	si,[scb_active]
	xchg	cx,ax			; CX = # bytes
	mov	ax,[si].SCB_DTA.OFF
	add	ax,cx
	jnc	fio4
	test	ax,ax			; (ending at the very end is fine)
	jnz	fio7
fio4:	mov	al,[bp].REG_AH
	cmp	al,DOS_FCB_SWRITE
	je	fio5
	cmp	al,DOS_FCB_RWRITE
	je	fio5
	cmp	al,DOS_FCB_RBWRITE
	je	fio5
	call	read_fcb		; AX = # bytes read, DL = result
	jmp	short fio8
fio5:	call	write_fcb		; AX = # bytes written, DL = result
	jmp	short fio8
fio7:	mov	dl,FCBERR_DTA
	sub	ax,ax
;
; Convert the # bytes transferred to a # records (counting any partial last
; record), and advance the FCB's records as appropriate.
;
fio8:	mov	[bp].REG_AL,dl
	sub	dx,dx
	div	es:[di].FCB_RECSIZE	; AX = # complete records
	neg	dx			; carry set if a partial record
	adc	ax,0			; AX = # records
	cmp	byte ptr [bp].REG_AH,DOS_FCB_RBREAD
	jae	fio8a			; block call
	cmp	byte ptr [bp].REG_AH,DOS_FCB_RREAD
	jae	fio9			; single random calls don't advance
	test	ax,ax			; was anything transferred?
	jz	fio9			; no
	call	seq_fcb			; DX:AX = current record #
	add	ax,1
	adc	dx,0
	jmp	short fio8b
fio8a:	mov	[bp].REG_CX,ax		; REG_CX = # records
	xchg	cx,ax			; CX = # records
	call	get_relrec		; DX:AX = RELREC
	add	ax,cx
	adc	dx,0
	call	set_relrec		; RELREC += # records
fio8b:	jmp	setcur_fcb
fio9:	ret
ENDPROC	fcb_sread

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_setrel (REG_AH = 24h)
;
; Sets RELREC to CURBLK * 128 + CURREC.  A block always contains 128 records,
; regardless of the record size.  No open SFB is required.
;
; Inputs:
;	REG_DS:REG_DX -> normal or extended FCB
;
; Outputs:
;	FCBF_RELREC = current record # (see set_relrec)
;
; Modifies:
;	AX, DX, SI, DI, DS, ES
;
DEFPROC	fcb_setrel,DOS
	call	fcb_ptr			; DS:SI -> FCB
	push	ds
	pop	es
	mov	di,si			; ES:DI -> FCB
	call	seq_fcb			; DX:AX = current record #
	jmp	set_relrec
ENDPROC	fcb_setrel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_size (REG_AH = 23h)
;
; Finds a file and divides its size by FCB_RECSIZE, rounding up to include
; any partial record.  The FCB need not be open.
;
; Inputs:
;	REG_DS:REG_DX -> normal or extended FCB
;	FCB_RECSIZE = non-zero record size
;
; Outputs:
;	REG_AL = 00h if found, FFh otherwise
;	FCBF_RELREC = # records on success (see set_relrec)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	fcb_size,DOS
	LOCK_SCB
	mov	byte ptr [bp].REG_AL,0FFh
	call	fcb_ptr			; DS:SI -> FCB, AL = attributes
	push	ds
	push	si
	mov	ah,10h			; AH = 10h (FCB)
	call	chk_filename		; DS:SI -> DIRENT
	pop	di
	pop	es			; ES:DI -> FCB
	jc	fsz9			; no such file
	mov	ax,[si].DIR_SIZE.LOW
	mov	dx,[si].DIR_SIZE.HIW	; DX:AX = file size
	mov	cx,es:[di].FCB_RECSIZE
	jcxz	fsz9			; no record size
	call	div_32_16		; DX:AX = # records, BX = remainder
	neg	bx			; carry set if a partial record
	adc	ax,0
	adc	dx,0			; DX:AX = # records
	call	set_relrec
	mov	byte ptr [bp].REG_AL,0
fsz9:	UNLOCK_SCB
ENDPROC	fcb_size

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_ptr
;
; Locates the normal FCB within a normal or extended FCB.
;
; Inputs:
;	REG_DS:REG_DX -> normal or extended FCB
;
; Outputs:
;	DS:SI -> normal FCB
;	AL = extended FCB attributes, or 0 for a normal FCB
;	AH = 0
;
; Modifies:
;	AX, SI, DS
;
DEFPROC	fcb_ptr,DOS
	mov	si,[bp].REG_DX
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	sub	ax,ax
	cmp	[si].FCBEX_FLAG,0FFh	; extended FCB?
	jne	fp9			; no
	mov	al,[si].FCBEX_ATTR	; yes
	add	si,size FCBEX
fp9:	ret
ENDPROC	fcb_ptr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_relrec, set_relrec
;
; Gets or sets an FCB's RELREC.  Only the low 3 bytes of RELREC are used when
; FCB_RECSIZE >= 64, and set_relrec leaves its 4th byte unchanged in that case
; (get_relrec simply sets RELREC to its current value, which masks DX:AX).
;
; Inputs:
;	DX:AX = record # (set_relrec only)
;	ES:DI -> FCB
;
; Outputs:
;	DX:AX = RELREC (masked to 3 bytes when FCB_RECSIZE >= 64)
;
; Modifies:
;	AX, DX
;
DEFPROC	get_relrec
	mov	ax,es:[di].FCBF_RELREC.LOW
	mov	dx,es:[di].FCBF_RELREC.HIW
	DEFLBL	set_relrec,near
	mov	es:[di].FCBF_RELREC.LOW,ax
	cmp	es:[di].FCB_RECSIZE,64
	jb	srr1
	mov	dh,0
	mov	byte ptr es:[di].FCBF_RELREC.HIW,dl
	ret
srr1:	mov	es:[di].FCBF_RELREC.HIW,dx
	ret
ENDPROC	get_relrec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; seq_fcb
;
; Calculates an FCB's current (sequential) record #, without changing the FCB.
;
; Inputs:
;	ES:DI -> FCB
;
; Outputs:
;	DX:AX = FCB_CURBLK * 128 + FCBF_CURREC
;
; Modifies:
;	AX, DX
;
DEFPROC	seq_fcb
	mov	ax,es:[di].FCB_CURBLK
	sub	dx,dx
	mov	dl,ah
	mov	ah,al
	mov	al,dh			; DX:AX = CURBLK * 256
	shr	dx,1
	rcr	ax,1			; DX:AX = CURBLK * 128
	or	al,es:[di].FCBF_CURREC	; (CURREC is always < 128)
	ret
ENDPROC	seq_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setcur_fcb
;
; Sets an FCB's CURBLK to a record # divided by 128, and CURREC to the
; remainder.
;
; Inputs:
;	DX:AX = record #
;	ES:DI -> FCB
;
; Outputs:
;	FCB_CURBLK and FCBF_CURREC updated
;
; Modifies:
;	None
;
DEFPROC	setcur_fcb
	push	ax
	push	dx
	shl	ax,1
	rcl	dx,1			; DX:AX = record # * 2
	shr	al,1			; AL = record # MOD 128
	mov	es:[di].FCBF_CURREC,al
	mov	al,ah
	mov	ah,dl			; AX = record # / 128
	mov	es:[di].FCB_CURBLK,ax
	pop	dx
	pop	ax
	ret
ENDPROC	setcur_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_fcb
;
; Reads CX bytes for the FCB at ES:DI into the DTA.  If fewer bytes are read
; and the last record is incomplete, the rest of that record (but not any
; unread records after it) is zero-filled.
;
; Inputs:
;	CX = # bytes
;	DS:BX -> SFB
;	ES:DI -> FCB
;
; Outputs:
;	AX = # bytes read
;	DL = FCBERR result
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	read_fcb
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	es
	push	di
	push	es:[di].FCB_RECSIZE
	push	cx
	mov	si,[scb_active]
	les	dx,[si].SCB_DTA		; ES:DX -> DTA
	mov	al,IO_RAW
	call	sfb_read		; AX = # bytes read
	pop	cx			; CX = # bytes requested
	pop	si			; SI = record size
	mov	dl,FCBERR_EOF
	jc	rf8			; report an error as EOF
	cmp	ax,cx
	mov	dl,FCBERR_OK
	je	rf9			; everything was read
	mov	dl,FCBERR_EOF
	test	ax,ax
	jz	rf9			; nothing was read
	mov	cx,ax
	sub	dx,dx
	div	si			; DX = # bytes in the last record
	xchg	ax,cx			; AX = # bytes read
	sub	si,dx			; SI = # bytes needed to complete it
	test	dx,dx
	mov	dl,FCBERR_EOF
	jz	rf9			; the last record is complete
	push	ax
	mov	cx,si			; CX = # bytes to zero-fill
	mov	si,[scb_active]
	mov	di,[si].SCB_DTA.OFF
	add	di,ax			; ES:DI -> end of the data read
	sub	al,al
	rep	stosb
	pop	ax
	mov	dl,FCBERR_PARTIAL
	jmp	short rf9
rf8:	sub	ax,ax
rf9:	pop	di
	pop	es
	ret
ENDPROC	read_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_fcb
;
; Writes CX bytes from the DTA for the FCB at ES:DI (a zero-byte write sets
; the file's size to its current position; see write_file), and copies the
; file's new size to the FCB.
;
; Since fcb_open opens an SFB read-only, the first write upgrades it to
; read-write, unless the file is read-only or another SFB has it open for
; writing (other SFBs reading the file don't matter, as in PC DOS).
;
; Inputs:
;	CX = # bytes
;	DS:BX -> SFB
;	ES:DI -> FCB
;
; Outputs:
;	AX = # bytes written
;	DL = FCBERR result (FCBERR_EOF if the disk is full or not writable)
;	FCBF_FILESIZE updated
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	write_fcb
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	test	[bx].SFB_MODE,MODE_ACC_WO OR MODE_ACC_RW
	jnz	wfc2			; the SFB is already writable
	cmp	[bx].SFB_DRIVE,0
	jl	wfc2			; devices don't check the mode
	test	[bx].SFB_ATTR,DIRATTR_RDONLY
	jnz	wfc8			; the file is read-only
	push	bx
	push	cx
	mov	si,[scb_active]
	mov	ax,[bx].SFB_DIRCLN
	mov	[si].SCB_DIRCLN,ax	; SCB_DIRCLN = directory of DIRENT
	mov	al,[bx].SFB_DRIVE	; AL = drive #
	mov	cx,[bx].SFB_DIRNUM	; CX = DIRENT #
	mov	bl,MODE_ACC_RO		; BL = mode (to check for writers only)
	call	sfb_chkopen		; is another SFB writing the file?
	pop	cx
	pop	bx
	jc	wfc8			; yes
	mov	[bx].SFB_MODE,MODE_ACC_RW
wfc2:	push	bx
	push	es
	push	di
	push	cx
	mov	si,[scb_active]
	lds	si,[si].SCB_DTA		; DS:SI -> DTA
	ASSUME	DS:NOTHING
	mov	al,IO_RAW
	call	sfb_write		; AX = # bytes written
	pop	cx
	pop	di
	pop	es
	pop	bx
	push	cs
	pop	ds
	ASSUME	DS:DOS
	jc	wfc8
	cmp	ax,cx
	mov	dl,FCBERR_OK
	je	wfc9			; everything was written
	mov	dl,FCBERR_EOF		; the disk is full
	jmp	short wfc9
wfc8:	sub	ax,ax
	mov	dl,FCBERR_EOF
wfc9:	mov	si,[bx].SFB_SIZE.LOW
	mov	es:[di].FCBF_FILESIZE.LOW,si
	mov	si,[bx].SFB_SIZE.HIW
	mov	es:[di].FCBF_FILESIZE.HIW,si
	ret
ENDPROC	write_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_parse (REG_AH = 29h)
;
; Parse a filespec into an unopened FCB using the caller's parse flags.
;
; Inputs:
;	REG_AL = parse flags
;	REG_DS:REG_SI -> filespec to parse
;	REG_ES:REG_DI -> buffer for unopened FCB
;
; Outputs:
;	REG_AL:
;	  00h: no wildcard characters
;	  01h: some wildcard characters
;	  FFh: invalid drive letter
;	REG_DS:REG_SI -> next unparsed character
;
; Modifies:
;
;	AX, BX, CX, DX, SI, DS, ES
;
DEFPROC	fcb_parse,DOS
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	ASSUME	DS:NOTHING, ES:NOTHING
	or	al,80h			; AL = 80h (wildcards allowed)
	mov	ah,al			; AH = parse flags
	call	parse_name
;
; Documentation says function 29h "creates an unopened" FCB.  Apparently
; all that means is that, in addition to the drive and filename being filled
; in (or not, depending on the inputs), FCB_CURBLK and FCB_RECSIZE get zeroed
; as well.
;
	mov	ax,0
	mov	es:[di].FCB_CURBLK,ax
	mov	es:[di].FCB_RECSIZE,ax

	mov	al,dh			; AL = wildcard flag (DH)
	jnc	fp8			; drive valid?
	sbb	al,al			; AL = 0FFh if not
fp8:	mov	[bp].REG_AL,al		; update caller's AL
	mov	[bp].REG_SI,si		; update caller's SI
	ret
ENDPROC	fcb_parse

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_fcb
;
; Locate the SFB associated with an opened normal or extended FCB.
;
; Inputs:
;	REG_DS:REG_DX -> FCB
;
; Outputs:
;	If carry clear:
;	  DS:BX -> SFB
;	  ES:DI -> FCB
;	Otherwise, carry set and REG_AL = FCBERR_EOF
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	get_fcb,DOS
	call	fcb_ptr
	mov	dx,si
	mov	cx,ds
	push	cs
	pop	ds
	call	sfb_find_fcb
	jc	gf9
	mov	di,dx
	mov	es,cx
	ret
gf9:	mov	byte ptr [bp].REG_AL,FCBERR_EOF
	ret
ENDPROC	get_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copy_name
;
; Copy the eleven-byte FCB name and extension, converting to uppercase.
;
; Inputs:
;	DS:SI -> device or filename
;	ES:DI -> filename buffer
;
; Outputs:
;	filename buffer filled in
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	copy_name,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>
	mov	cx,size FCB_NAME
;
; TODO: Expand this code to a separate function which, like parse_name, upper-
; cases and validates all characters against FILENAME_CHARS.
;
cn2:	lodsb
	cmp	al,'a'
	jb	cn3
	cmp	al,'z'
	ja	cn3
	sub	al,20h
cn3:	stosb
	loop	cn2
	ret
ENDPROC	copy_name

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_name
;
; Parse a filespec into drive, name, and extension fields.
;
; NOTE: My observations with PC DOS 2.0 are that "ignore leading separators"
; really means "ignore leading whitespace" (ie, spaces or tabs).  This has to
; be one of the more poorly documented APIs in terms of precise behavior.
;
; Inputs:
;	AH = parse flags
;	  01h: ignore leading separators
;	  02h: leave drive in buffer unchanged if unspecified
;	  04h: leave filename in buffer unchanged if unspecified
;	  08h: leave extension in buffer unchanged if unspecified
;	  80h: allow wildcards
;	DS:SI -> string to parse
;	ES:DI -> buffer for filename
;
; Outputs:
;	Carry clear if drive number valid, set otherwise
;	DL = drive number (actual drive number if specified, default if not)
;	DH = wildcards flag (1 if any present, 0 if not)
;	SI -> next unparsed character
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	parse_name,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
;
; See if the name begins with a drive letter.  If so, convert it to a drive
; number and then skip over it; otherwise, use SCB_CURDRV as the drive number.
;
	mov	bx,[scb_active]
	ASSERT	STRUCT,cs:[bx],SCB
	mov	dl,cs:[bx].SCB_CURDRV	; DL = default drive number
	mov	dh,0			; DH = wildcards flag
	mov	cl,8			; CL is current filename limit
	sub	bx,bx			; BL is current filename position

pf0:	lodsb
	test	ah,01h			; skip leading whitespace?
	jz	pf1			; no
	cmp	al,CHR_SPACE
	je	pf0
	cmp	al,CHR_TAB
	je	pf0			; keep looping until no more whitespace

pf1:	sar	ah,1
	cmp	byte ptr [si],':'	; drive letter?
	je	pf1a			; yes
	dec	si
	test	ah,01h			; update drive #?
	jnz	pf1d			; no
	mov	al,0			; yes, specify 0 for default drive
	jmp	short pf1c
pf1a:	inc	si			; skip colon
	sub	al,'A'			; AL = drive number
	cmp	al,20h			; possibly lower case?
	jb	pf1b			; no
	sub	al,20h			; yes
pf1b:	mov	dl,al			; DL = drive number (validate later)
	inc	ax			; store 1-based drive number
pf1c:	mov	es:[di+bx],al
pf1d:	inc	di			; advance DI past FCB_DRIVE
	sar	ah,1
;
; Build filename at ES:DI+BX from the string at DS:SI, making sure that all
; characters exist within FILENAME_CHARS.
;
pf2:	lodsb
pf2a:	cmp	al,' '			; check character validity
	jb	pf4			; invalid character
	cmp	al,'.'
	je	pf4a
	cmp	al,'a'
	jb	pf2b
	cmp	al,'z'
	ja	pf2b
	sub	al,20h
pf2b:	test	ah,80h			; filespec?
	jz	pf2d			; no
	cmp	al,'?'			; wildcard?
	jne	pf2c
	or	dh,1			; wildcard present
	jmp	short pf2e
pf2c:	cmp	al,'*'			; asterisk?
	je	pf3			; yes, fill with wildcards
pf2d:	push	cx
	push	di
	push	es
	push	cs
	pop	es
	ASSUME	ES:DOS
	mov	cx,FILENAME_CHARS_LEN
	mov	di,offset FILENAME_CHARS
	repne	scasb
	pop	es
	ASSUME	ES:NOTHING
	pop	di
	pop	cx
	jne	pf4			; invalid character
pf2e:	and	ah,0FEh		; this component was specified
	cmp	bl,cl
	jae	pf2			; valid character but we're at limit
	mov	es:[di+bx],al		; store it
	inc	bx
	jmp	pf2
pf3:	and	ah,0FEh
	or	dh,1			; wildcard present
pf3a:	cmp	bl,cl
	jae	pf2
	mov	byte ptr es:[di+bx],'?'	; store '?' until we reach the limit
	inc	bx
	jmp	pf3a
;
; Advance to next part of filename (filling with blanks as appropriate)
;
pf4:	dec	si
pf4a:	cmp	bl,cl			; are we done with the current portion?
	jae	pf5			; yes
	test	ah,01h			; leave the buffer unchanged?
	jnz	pf4b			; yes
	mov	byte ptr es:[di+bx],' '	; store ' ' until we reach the limit
pf4b:	inc	bx
	jmp	pf4a

pf5:	cmp	cl,size FCB_NAME	; did we just finish the extension?
	je	pf9			; yes
	mov	bl,8			; BL -> extension
	mov	cl,size FCB_NAME	; CL -> extension limit
	sar	ah,1			; shift the parse flags
	jmp	pf2
;
; Last but not least, validate the drive number
;
pf9:	dec	di			; rewind DI to FCB_DRIVE
	cmp	dl,cs:[bpb_total]
	cmc				; carry clear if >= 0 and < bpb_total
	ret
ENDPROC	parse_name

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_ffirst (REG_AH = 11h)
;
; Starts a (wildcard) search of the current directory of the FCB's drive.
; The search state is kept in the FCB (see find_fcb), not in the DTA.
;
; Inputs:
;	REG_DS:REG_DX -> unopened normal or extended search FCB
;
; Outputs:
;	REG_AL = 00h if found, FFh otherwise
;	DTA = 1-based drive # followed by the 32-byte DIRENT, preceded by
;	the 7 bytes of an extended FCB if the search FCB was extended
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	fcb_ffirst,DOS
	call	fcb_ptr			; DS:SI -> FCB, AL = attributes
	mov	word ptr [si].FCB_CURBLK,0
	jmp	short ff0
ENDPROC	fcb_ffirst

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_fnext (REG_AH = 12h)
;
; Continues a search started by fcb_ffirst with the same FCB.
;
; Inputs:
;	REG_DS:REG_DX -> normal or extended search FCB
;
; Outputs:
;	REG_AL = 00h if found, FFh otherwise
;	DTA filled in as for fcb_ffirst
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	fcb_fnext,DOS
	call	fcb_ptr			; DS:SI -> FCB, AL = attributes
ff0:	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	LOCK_SCB
	call	find_fcb		; DS:SI -> DIRENT
	jc	ff8
	push	ds
	push	si
	mov	si,[scb_active]
	les	di,cs:[si].SCB_DTA	; ES:DI -> DTA
	cmp	byte ptr [bp].TMP_AH,0	; extended search FCB?
	je	ff1			; no
	mov	al,0FFh
	stosb				; FCBEX_FLAG = 0FFh
	sub	ax,ax
	stosw
	stosw
	stosb				; FCBEX_RESERVED = 0
	mov	al,[bp].TMP_AL
	stosb				; FCBEX_ATTR = search attributes
ff1:	mov	al,[bp].TMP_BL
	inc	ax
	stosb				; FCB_DRIVE = 1-based drive #
	pop	si
	pop	ds
	mov	cx,size DIRENT
	rep	movsb			; and the DIRENT follows
	mov	byte ptr [bp].REG_AL,0
	UNLOCK_SCB
ff8:	mov	byte ptr [bp].REG_AL,0FFh
	UNLOCK_SCB
ENDPROC	fcb_fnext

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_fcb
;
; Finds the next DIRENT matching an FCB, starting with the DIRENT # in
; FCB_CURBLK (a field that an unopened search, delete, or rename FCB doesn't
; otherwise use), and advances FCB_CURBLK past it.
;
; Inputs:
;	AL = search attributes
;	DS:SI -> normal FCB
;	FCB_CURBLK = 1st DIRENT # to examine
;
; Outputs:
;	On success, carry clear:
;	  AL = drive #
;	  CX = DIRENT #
;	  DS:SI -> DIRENT
;	  FCB_DRIVE set to the 1-based drive #
;	Otherwise, carry set
;	TMP_ES:TMP_DX -> normal FCB
;	TMP_AL = search attributes, TMP_AH = 1 if extended FCB (0 if not)
;	TMP_BL = drive #
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	find_fcb,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	mov	[bp].TMP_AL,al
	mov	byte ptr [bp].TMP_AH,0
	cmp	si,[bp].REG_DX		; extended FCB?
	je	fnd1			; no
	inc	byte ptr [bp].TMP_AH	; yes
fnd1:	mov	[bp].TMP_DX,si
	mov	[bp].TMP_ES,ds
	push	[si].FCB_CURBLK		; save the 1st DIRENT # to examine
	call	name_fcb		; DL = drive #, DI -> BPB
	pop	ax			; AX = 1st DIRENT # to examine
	jc	fnd9
	mov	[bp].TMP_BL,dl
	mov	bl,[bp].TMP_AL
	or	bl,DIRATTR_SEARCH	; BL = search attributes
	call	get_dirent		; DS:SI -> DIRENT, AX = DIRENT #
	jc	fnd9
	mov	cx,ax			; CX = DIRENT #
	inc	ax
	mov	es,[bp].TMP_ES
	mov	di,[bp].TMP_DX		; ES:DI -> FCB
	mov	es:[di].FCB_CURBLK,ax	; resume after this DIRENT next time
	mov	al,dl
	inc	ax
	mov	es:[di].FCB_DRIVE,al	; set FCB_DRIVE to 1-based drive #
	mov	al,dl			; AL = drive # (and carry is clear)
fnd9:	ret
ENDPROC	find_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; name_fcb
;
; Copies the drive # and name of an FCB to SCB_FILENAME, sets SCB_DIRCLN to
; the drive's current directory (FCBs always refer to the current directory),
; and gets the drive's BPB, which is everything get_dirent needs to search.
;
; Inputs:
;	DS:SI -> FCB
;
; Outputs:
;	On success, carry clear, DL = drive #, DI -> BPB
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	name_fcb,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cs
	pop	es
	ASSUME	ES:DOS
	mov	bx,[scb_active]
	lea	di,[bx].SCB_FILENAME	; ES:DI -> filename buffer
	lodsb				; AL = FCB_DRIVE
	dec	al			; convert 1-based drive # to 0-based
	jge	nf1			; (0 means the current drive)
	mov	al,es:[bx].SCB_CURDRV
nf1:	stosb				; store drive # in the filename buffer
	xchg	dx,ax			; DL = drive #
	call	copy_name
	mov	al,dl
	call	get_cdir		; BX -> drive's current directory
	mov	ax,es:[bx]
	mov	bx,[scb_active]
	mov	es:[bx].SCB_DIRCLN,ax
	jmp	get_bpb			; DI -> BPB
ENDPROC	name_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_delete (REG_AH = 13h), fcb_rename (REG_AH = 17h)
;
; Deletes or renames every file matching the FCB.  As in PC DOS, files that
; can't be changed (read-only files, directories, and volume labels, as well
; as open files) are skipped.  Each '?' in a new name keeps the corresponding
; character of the old name.
;
; Inputs:
;	REG_DS:REG_DX -> unopened normal or extended FCB
;	For rename, the new name begins at offset 11h (FCB_NEWNAME)
;
; Outputs:
;	REG_AL = 00h if any files changed, FFh otherwise
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	fcb_delete,DOS
	DEFLBL	fcb_rename,near
	LOCK_SCB
	mov	byte ptr [bp].REG_AL,0FFh
	call	fcb_ptr			; DS:SI -> FCB, AL = attributes
	mov	word ptr [si].FCB_CURBLK,0
fchg0:	call	find_fcb		; DS:SI -> DIRENT, AL = drive #
	jc	fchg9			; no (more) matches
	call	chk_dirent		; can the file be changed?
	jc	fchg6			; no, so skip it
	cmp	byte ptr [bp].REG_AH,DOS_FCB_RENAME
	je	fchg2
	xchg	dx,ax			; DL = drive #
	call	del_dirent		; delete DIRENT and free its clusters
	jmp	short fchg4
fchg2:	call	rename_fcb		; rename the DIRENT
fchg4:	jc	fchg8
	mov	al,[bp].TMP_BL		; AL = drive #
	call	flush_buffers		; write the modified DIRENT (and FAT)
	jc	fchg8
	mov	byte ptr [bp].REG_AL,0	; at least one file changed
fchg6:	mov	si,[bp].TMP_DX
	mov	ds,[bp].TMP_ES		; DS:SI -> FCB again
	mov	al,[bp].TMP_AL		; AL = search attributes
	jmp	fchg0
fchg8:	mov	byte ptr [bp].REG_AL,0FFh
fchg9:	UNLOCK_SCB
ENDPROC	fcb_delete

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; rename_fcb
;
; Renames the DIRENT at DS:SI, using the new name in the rename FCB.  The new
; name is built on the stack and checked (it must not already exist) before
; the DIRENT is changed, and since that check may evict the DIRENT's buffer,
; the DIRENT is found again before it's renamed.
;
; Inputs:
;	DS:SI -> DIRENT
;	TMP_ES:TMP_DX -> normal rename FCB
;	TMP_AL = search attributes
;	TMP_BL = drive #
;
; Outputs:
;	On success, carry clear (DIRENT renamed and its buffer dirty)
;	Otherwise, carry set
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	rename_fcb
	sub	sp,RENBUF
	mov	di,sp			; SS:DI -> new drive # and name
	mov	al,[bp].TMP_BL
	inc	ax
	mov	ss:[di],al		; store 1-based drive #
	inc	di
	mov	es,[bp].TMP_ES
	mov	bx,[bp].TMP_DX
	add	bx,FCB_NEWNAME		; ES:BX -> new name
	mov	cx,size FCB_NAME
rn1:	mov	al,es:[bx]
	inc	bx
	cmp	al,'?'			; wildcard?
	jne	rn2			; no
	mov	al,[si]			; yes, so keep the old character
rn2:	mov	ss:[di],al
	inc	di
	inc	si
	loop	rn1
	mov	si,sp
	push	ss
	pop	ds			; DS:SI -> new drive # and name
	mov	ax,1000h		; AH = 10h (FCB), AL = 0 (attributes)
	call	chk_filename		; does the new name already exist?
	jnc	rn8			; yes
	cmp	ax,ERR_NOFILE		; no, but was the new name valid?
	jne	rn8			; no
	mov	si,[bp].TMP_DX
	mov	ds,[bp].TMP_ES		; DS:SI -> FCB
	dec	[si].FCB_CURBLK		; back up to the same DIRENT
	mov	al,[bp].TMP_AL
	call	find_fcb		; DS:SI -> DIRENT
	jc	rn8
	push	ds
	pop	es
	mov	di,si			; ES:DI -> DIRENT
	mov	si,sp
	inc	si			; SS:SI -> new name
	mov	cx,size FCB_NAME
	REPS	MOVS,ES,SS,BYTE		; copy the new name into the DIRENT
	mov	ds:[BUF_DIRTY],1
	add	sp,RENBUF
	clc
	ret
rn8:	add	sp,RENBUF
	stc
	ret
ENDPROC	rename_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_create, sfb_create_fcb
;
; Creates a new file, or truncates an existing file, and then opens it for
; reading and writing.  If the name is a device name, the device is simply
; opened.
;
; Inputs:
;	CL = attributes (see DIRATTR_*)
;	DS:SI -> name of device/file (sfb_create)
;	DS:SI -> normal FCB (sfb_create_fcb with AX = 1000h)
;
; Outputs:
;	On success, BX -> SFB, DX = context (if any), carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	sfb_create,DOS
	sub	ax,ax			; AH = 0 (filename), AL = 0 (attrs)
	DEFLBL	sfb_create_fcb,near
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	LOCK_SCB
	push	si
	push	ds
	push	es
	push	ax
	and	cl,ATTR_CREATE
	mov	bl,cl			; BL = attributes
	call	chk_devname		; is it a device name?
	jc	sc1			; no
	jmp	sc6			; yes, so just open the device
sc1:	pop	ax
	push	ax			; AH = name type, AL = 0 (attributes)
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
	xchg	ax,dx			; AL = drive #
	call	chk_volopen		; is the volume open?
	jc	sc8			; yes
	call	add_dirent		; DS:SI -> new DIRENT
	jc	sc8
	ASSUME	DS:BIOS
	jmp	short sc5
;
; The file already exists (DS:SI -> DIRENT, AL = drive #), so truncate it,
; unless it can't be changed (eg, it's read-only or open).
;
sc3:	call	chk_dirent		; can the file be truncated?
	jc	sc8			; no (AX = error code)
	mov	cl,al			; CL = drive #
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
sc6:	pop	ax
	pop	es
	pop	ds
	pop	si
	ASSUME	DS:NOTHING, ES:NOTHING
	mov	bl,MODE_ACC_RW		; BL = mode
	call	sfb_open_fcb
	jmp	short sc9
sc7:	stc
sc8:	pop	dx			; discard the saved AX
	pop	es
	pop	ds
	pop	si
sc9:	UNLOCK_SCB
ENDPROC	sfb_create

DOS	ends

	end
