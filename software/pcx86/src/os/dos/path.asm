;
; BASIC-DOS Path and Directory Services
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
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<get_bpb,get_cdir,get_dirent,parse_name,scb_release>
	EXTNEAR	<chk_filename,chk_volopen,sfb_chkopen,flush_buffers,free_clns>
	EXTBYTE	<bpb_total,scb_locked>
	EXTWORD	<scb_active>

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
;	Unlike PC DOS, we refuse to delete a file that is open (ERR_SHARE),
;	since freeing its clusters would corrupt any SFB using them.
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
	call	chk_dirent		; can the file be deleted?
	jc	dd8			; no (AX = error code)
	push	ax
	xchg	dx,ax			; DL = drive #
	call	del_dirent		; delete DIRENT and free its clusters
	pop	ax			; AL = drive #
	jc	dd8
	call	flush_buffers		; write the modified DIRENT and FAT
	jnc	dd9
dd8:	mov	[bp].REG_AX,ax
dd9:	UNLOCK_SCB
ENDPROC	dsk_delete

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_dirent
;
; Checks that the file whose DIRENT is at DS:SI can be deleted, renamed (by
; an FCB), or truncated: it must not be read-only, a directory, or a volume
; label, and it must not be open (see sfb_chkopen).
;
; Inputs:
;	AL = drive #
;	CX = DIRENT #
;	DS:SI -> DIRENT
;	SCB_DIRCLN = directory (1st cluster) of DIRENT
;
; Outputs:
;	On success, carry clear (AL = drive # still)
;	On failure, carry set, AX = error code (ERR_ACCDENIED or ERR_SHARE)
;
; Modifies:
;	AX
;
ATTR_NOCHG	equ	DIRATTR_RDONLY OR DIRATTR_SUBDIR OR DIRATTR_VOLUME

DEFPROC	chk_dirent,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	test	[si].DIR_ATTR,ATTR_NOCHG
	jnz	cdt8			; it's not a file we can change
	push	bx
	mov	bl,MODE_ACC_RW		; BL = mode (ie, exclusive access)
	call	sfb_chkopen		; is the file open?
	pop	bx
	ret
cdt8:	mov	ax,ERR_ACCDENIED
	stc
	ret
ENDPROC	chk_dirent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; del_dirent
;
; Marks the DIRENT at DS:SI deleted and frees its clusters.  The caller must
; flush the DIRENT's buffer (and the FAT) afterward (see flush_buffers).
;
; Inputs:
;	DL = drive #
;	DS:SI -> DIRENT (in a directory buffer)
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	del_dirent,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	mov	byte ptr [si].DIR_NAME,DIRENT_DELETED
	mov	ds:[BUF_DIRTY],1
	push	[si].DIR_CLN		; save the first CLN
	call	get_bpb			; DI -> BPB
	pop	dx			; DX = first CLN
	jc	ddl9
	jmp	free_clns		; free the file's clusters
ddl9:	ret
ENDPROC	del_dirent

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
	call	chk_volopen		; is the volume open?
	jc	dr5			; yes
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
; get_path
;
; Parse the drive, directory names (separated by SCB_PATHCHAR), and filename
; at DS:SI, walking the directories as we go.  A path that begins with
; SCB_PATHCHAR starts at the root directory; otherwise, it starts at the
; drive's current directory.
;
; Inputs:
;	AH = parse flags (00h for a filename, 80h for a filespec w/wildcards)
;	BX -> active SCB
;	DS:SI -> path
;	ES:DI -> SCB_FILENAME
;
; Outputs:
;	On success, carry clear:
;		DL = drive #
;		DI -> BPB
;		SCB_DIRCLN = directory containing the filename
;		SCB_FILENAME = drive # and filename (which may be blank)
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	get_path,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>
	push	ax			; save parse flags
	push	bx
	call	parse_comp		; parse the drive and 1st name
	pop	bx
	mov	es:[di],dl		; store a 0-based drive # (parse_name
	mov	ax,ERR_BADDRIVE		; stores 1-based), unless it's invalid
	jc	gp9
	call	get_bpb			; DI -> BPB
	jc	gp9
	push	bx
	mov	al,dl
	call	get_cdir		; BX -> drive's current directory
	mov	ax,es:[bx]
	pop	bx
	mov	cl,es:[bx].SCB_PATHCHAR
	cmp	[si],cl			; is there a directory to walk?
	jne	gp7			; no
	cmp	es:[bx].SCB_FILENAME+1,' '
	jne	gp2			; the path doesn't start at the root
	sub	ax,ax
gp2:	mov	es:[bx].SCB_DIRCLN,ax
	inc	si			; skip SCB_PATHCHAR
	mov	ax,ERR_NOPATH
	test	dh,dh			; any wildcards in the directory name?
	stc
	jnz	gp9			; yes
	call	get_dir			; AX = directory
	jc	gp9
	mov	es:[bx].SCB_DIRCLN,ax
	pop	ax			; restore parse flags (AH)
	push	ax
	or	ah,02h			; leave the drive # unchanged
	push	dx
	push	di
	lea	di,[bx].SCB_FILENAME
	push	bx
	call	parse_comp		; parse the next name
	pop	bx
	pop	di
	mov	al,dh			; AL = wildcards flag
	pop	dx			; DL = drive # again
	mov	dh,al			; DH = wildcards flag
	mov	ax,es:[bx].SCB_DIRCLN
	mov	cl,es:[bx].SCB_PATHCHAR
	cmp	[si],cl			; another directory?
	je	gp2			; yes
	jmp	short gp8
gp7:	mov	es:[bx].SCB_DIRCLN,ax
gp8:	clc
gp9:	inc	sp			; discard parse flags
	inc	sp			; without affecting carry
	ret
ENDPROC	get_path

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_comp
;
; Use parse_name to parse one component of a path, and then fix up any "."
; or ".." component, which parse_name would otherwise leave blank.
;
; Inputs:
;	AH = parse flags (see parse_name)
;	DS:SI -> component (optionally preceded by a drive)
;	ES:DI -> filename buffer
;
; Outputs:
;	Same as parse_name
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	parse_comp,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	si
	call	parse_name
	pop	bx			; BX -> start of component
	pushf
	cmp	byte ptr [bx+1],':'	; does it start with a drive?
	jne	pc1			; no
	inc	bx
	inc	bx
pc1:	mov	al,'.'
	cmp	[bx],al			; does the component start with a dot?
	jne	pc9			; no
	cmp	byte ptr es:[di+9],' '	; and have no extension?
	jne	pc9			; no
	lea	si,[bx+1]		; it's "." (or "..")
	mov	es:[di+1],al
	cmp	[si],al
	jne	pc9
	inc	si
	mov	es:[di+2],al
pc9:	popf
	ret
ENDPROC	parse_comp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_dir
;
; Get the directory for the name in SCB_FILENAME, which must be either a
; subdirectory of SCB_DIRCLN, or blank or "." (ie, SCB_DIRCLN itself).
;
; Inputs:
;	DI -> BPB
;	SCB_DIRCLN and SCB_FILENAME
;
; Outputs:
;	On success, carry clear, AX = directory (1st cluster, or 0 for root)
;	On failure, carry set, AX = error code (ERR_NOPATH if not found)
;
; Modifies:
;	AX, CX
;
DEFPROC	get_dir,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>
	push	bx
	push	si
	push	ds
	mov	bx,[scb_active]
	mov	ax,es:[bx].SCB_DIRCLN
	mov	cx,word ptr es:[bx].SCB_FILENAME+1
	cmp	cl,' '			; blank?
	je	gr9			; yes (and carry is clear)
	cmp	cx,' .'			; "."?
	je	gr9			; yes (and carry is clear)
	mov	ax,-1
	mov	bl,DIRATTR_SUBDIR
	call	get_dirent		; DS:SI -> DIRENT
	jc	gr8
	mov	ax,[si].DIR_CLN
	jmp	short gr9
gr8:	cmp	ax,ERR_NOFILE
	stc
	jne	gr9
	mov	ax,ERR_NOPATH
gr9:	pop	ds
	pop	si
	pop	bx
	ret
ENDPROC	get_dir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_parent
;
; Get the parent of a subdirectory, along with the subdirectory's name, by
; reading its ".." entry and then finding its entry in the parent.
;
; Inputs:
;	DX = subdirectory (1st cluster)
;	DI -> BPB
;
; Outputs:
;	On success, carry clear:
;		AX = parent directory (1st cluster, or 0 for the root)
;		SCB_FILENAME = subdirectory name (eg, "NAME.EXT")
;		CX = length of name
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, CX, SCB_DIRCLN
;
DEFPROC	get_parent,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>
	push	bx
	push	si
	push	ds
	push	di
	mov	bx,[scb_active]
	mov	es:[bx].SCB_DIRCLN,dx
	lea	di,[bx].SCB_FILENAME+1
	mov	ax,'..'
	stosw
	mov	al,' '
	mov	cx,size FCB_NAME - 2
	rep	stosb
	pop	di
	sub	ax,ax			; start with DIRENT # 0
	mov	bl,DIRATTR_SUBDIR
	call	get_dirent		; DS:SI -> ".." DIRENT
	jc	gt8
	mov	ax,[si].DIR_CLN		; AX = parent
	mov	bx,[scb_active]
	mov	es:[bx].SCB_DIRCLN,ax
	push	di
	lea	di,[bx].SCB_FILENAME+1
	mov	al,'?'
	mov	cx,size FCB_NAME
	rep	stosb
	pop	di
	sub	ax,ax
gt2:	mov	bl,DIRATTR_SUBDIR
	call	get_dirent		; AX = DIRENT #, DS:SI -> DIRENT
	jc	gt8
	inc	ax			; AX = next DIRENT # (if no match)
	cmp	[si].DIR_CLN,dx		; is this the subdirectory?
	jne	gt2			; no
	cmp	[si].DIR_NAME,'.'	; ("." and ".." don't count)
	je	gt2
	mov	bx,[scb_active]
	push	di
	lea	di,[bx].SCB_FILENAME
	call	fmt_name		; copy the name to SCB_FILENAME
	xchg	cx,di
	pop	di
	lea	ax,[bx].SCB_FILENAME
	sub	cx,ax			; CX = length of name
	mov	ax,es:[bx].SCB_DIRCLN	; AX = parent (and carry is clear)
	jmp	short gt9
gt8:	cmp	ax,ERR_NOFILE
	stc
	jne	gt9
	mov	ax,ERR_NOPATH
gt9:	pop	ds
	pop	si
	pop	bx
	ret
ENDPROC	get_parent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fmt_name
;
; Format the name of a DIRENT as "NAME.EXT" (no null terminator).
;
; Inputs:
;	DS:SI -> DIRENT
;	ES:DI -> buffer
;
; Outputs:
;	ES:DI -> end of name in buffer
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	fmt_name,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	mov	cx,8
fn1:	lodsb
	cmp	al,' '
	je	fn2
	stosb
fn2:	loop	fn1
	mov	al,[si]
	cmp	al,' '
	je	fn9
	mov	al,'.'
	stosb
	mov	cl,3
fn3:	lodsb
	cmp	al,' '
	je	fn4
	stosb
fn4:	loop	fn3
fn9:	ret
ENDPROC	fmt_name

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_chdir (REG_AH = 3Bh)
;
; Inputs:
;	REG_DS:REG_DX -> path of new current directory
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error code (eg, ERR_NOPATH)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	dsk_chdir,DOS
	LOCK_SCB
	call	get_dirpath		; DL = drive #, DI -> BPB
	jc	cd8
	call	get_dir			; AX = directory
	jc	cd8
	xchg	cx,ax			; CX = directory
	mov	al,dl
	call	get_cdir		; BX -> drive's current directory
	mov	es:[bx],cx
	jmp	short cd9
cd8:	mov	[bp].REG_AX,ax
cd9:	UNLOCK_SCB
	ret
ENDPROC	dsk_chdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_dirpath
;
; Use get_path to parse the path at REG_DS:REG_DX (eg, for dsk_chdir).
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
DEFPROC	get_dirpath,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cs
	pop	es
	ASSUME	ES:DOS
	mov	si,[bp].REG_DX
	mov	ds,[bp].REG_DS		; DS:SI -> path
	mov	bx,[scb_active]
	lea	di,[bx].SCB_FILENAME
	mov	ah,0			; AH = 0 (no wildcards)
	jmp	get_path		; DL = drive #, DI -> BPB
ENDPROC	get_dirpath

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_getcwd (REG_AH = 47h)
;
; Inputs:
;	REG_DL = drive # (0 for default, 1 for A:, and so on)
;	REG_DS:REG_SI -> 64-byte buffer
;
; Outputs:
;	On success, carry clear, and the buffer contains the path of the
;	current directory, without a drive or leading SCB_PATHCHAR (so the
;	root directory is an empty string)
;	On failure, carry set, REG_AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; Notes:
;	We don't store paths, just the 1st cluster of each current directory,
;	so we rebuild the path (from the end of the buffer back) by walking
;	".." entries up to the root, finding each subdirectory's name in its
;	parent along the way.
;
DEFPROC	dsk_getcwd,DOS
	LOCK_SCB
	mov	bx,[scb_active]
	dec	dl			; drive # specified?
	jge	cw1			; yes
	mov	dl,cs:[bx].SCB_CURDRV
cw1:	mov	ax,ERR_BADDRIVE
	cmp	dl,[bpb_total]		; valid drive #?
	cmc
	jc	cw8			; no
	mov	al,dl
	call	get_cdir		; BX -> drive's current directory
	mov	cx,cs:[bx]		; CX = current directory
	jcxz	cw1a			; the root doesn't require a fresh BPB
	call	get_bpb			; DI -> BPB
	jc	cw8
cw1a:	mov	dx,cx			; DX = current directory
	mov	bx,[bp].REG_SI
	add	bx,63			; BX -> last byte of buffer
	mov	es,[bp].REG_DS
	ASSUME	ES:NOTHING
	mov	byte ptr es:[bx],0
cw2:	push	cs
	pop	es
	ASSUME	ES:DOS
	test	dx,dx			; at the root yet?
	jz	cw6			; yes
	call	get_parent		; AX = parent, CX = length of name
	jc	cw8
	sub	bx,cx
	dec	bx			; BX -> room for SCB_PATHCHAR and name
	cmp	bx,[bp].REG_SI		; is there enough room?
	jb	cw7			; no
	xchg	dx,ax			; DX = parent
	push	di
	mov	di,bx
	mov	es,[bp].REG_DS
	ASSUME	ES:NOTHING
	mov	si,[scb_active]
	mov	al,cs:[si].SCB_PATHCHAR
	stosb
	lea	si,[si].SCB_FILENAME
	REPS	MOVS,ES,CS,BYTE
	pop	di
	jmp	cw2

cw6:	mov	es,[bp].REG_DS		; ES:BX -> path
	cmp	byte ptr es:[bx],0	; empty?
	je	cw6a			; yes
	inc	bx			; skip the leading SCB_PATHCHAR
cw6a:	mov	di,[bp].REG_SI		; ES:DI -> start of buffer
	lea	cx,[di+64]
	sub	cx,bx			; CX = length of path (incl. null)
	mov	si,bx
	push	es
	pop	ds			; DS:SI -> path
	rep	movsb			; (carry is clear)
	jmp	short cw9

cw7:	mov	ax,ERR_NOPATH
	stc
cw8:	mov	[bp].REG_AX,ax
cw9:	UNLOCK_SCB
	ret
ENDPROC	dsk_getcwd

DOS	ends

	end
