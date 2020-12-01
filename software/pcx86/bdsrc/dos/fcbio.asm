;
; BASIC-DOS FCB Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTBYTE	<bpb_total>
	EXTWORD	<scb_active>
	EXTNEAR	<sfb_open_fcb,sfb_find_fcb,sfb_seek,sfb_read,sfb_close>
	EXTNEAR	<div_32_16,mul_32_16>

	EXTSTR	<FILENAME_CHARS>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_open (REG_AH = 0Fh)
;
; Open an SFB for the file.
;
; Inputs:
;	REG_DS:REG_DX -> unopened FCB
;
; Outputs:
;	REG_AL:
;	  00h: found (and FCB filled in)
;	  FFh: not found
;
; Modifies:
;
DEFPROC	fcb_open,DOS
	mov	si,dx
	mov	ds,[bp].REG_DS		; DS:SI -> FCB
	ASSUME	DS:NOTHING
	mov	ax,0FFFh		; AX = 0FFFh
	mov	[bp].REG_AL,al		; assume failure
	inc	ax			; AX = 1000h (AH = 10h, AL = 0)
	call	sfb_open_fcb
	jc	fo9
	mov	di,si
	push	ds
	pop	es			; ES:DI -> FCB
	mov	si,bx
	push	cs
	pop	ds			; DS:SI -> SFB
	mov	[si].SFB_FCB.OFF,di
	mov	[si].SFB_FCB.SEG,es	; set SFB_FCB
	or	[si].SFB_FLAGS,SFBF_FCB	; mark SFB as originating as FCB
	mov	al,[si].SFB_DRIVE
	inc	ax
	mov	es:[di].FCB_DRIVE,al	; set FCB_DRIVE to 1-based drive #
	add	si,SFB_SIZE		; DS:SI -> SFB.SFB_SIZE
	add	di,FCB_CURBLK		; ES:DI -> FCB.FCB_CURBLK
	sub	ax,ax
	mov	[bp].REG_AL,al		; set REG_AL to zero
	stosw				; set FCB_CURBLK to zero
	mov	ax,128
	stosw				; set FCB_RECSIZE to 128
	movsw
	movsw				; set FCBF_FILESIZE from SFB_SIZE
	sub	si,(SFB_SIZE + 4) - SFB_DATE
	movsw				; set FCBF_DATE from SFB_DATE
	sub	si,(SFB_DATE + 2) - SFB_TIME
	movsw				; set FCBF_TIME from SFB_TIME
	add	si,SFB_CLN - (SFB_TIME + 2)
	movsw				; set FCBF_CLN from SFB_CLN
fo9:	ret
ENDPROC	fcb_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_close (REG_AH = 10h)
;
; Update the matching directory entry from the FCB.
;
; Inputs:
;	REG_DS:REG_DX -> FCB
;
; Outputs:
;	REG_AL:
;	  00h: found
;	  FFh: not found
;
; Modifies:
;
DEFPROC	fcb_close,DOS
	call	get_fcb
	jc	fc9
	mov	si,-1			; SI = -1 (no PFH)
	call	sfb_close		; BX -> SFB
fc9:	ret
ENDPROC	fcb_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_sread (REG_AH = 14h)
;
; Read a sequential record into the DTA.
;
; Inputs:
;	REG_DS:REG_DX -> FCB
;
; Outputs:
;	REG_AL = FCBERR result
;
; Modifies:
;
DEFPROC	fcb_sread,DOS
	call	get_fcb
	jc	fsr9
	ASSUME	ES:NOTHING		; DS:BX -> SFB, ES:DI -> FCB
;
; TODO: Implement.
;
fsr9:	ret
ENDPROC	fcb_sread

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_rread (REG_AH = 21h)
;
; FCB Random Read.  From the MS-DOS 3.3 Programmer's Reference:
;
;	Function 21h reads (into the Disk Transfer Address) the record
;	pointed to by the Relative Record (FCBF_RELREC @21h) of the FCB.
;	DX must contain the offset (from the segment address in DS) of an
;	opened FCB.
;
;	Current Block (FCB_CURBLK @0Ch) and Current Record (FCBF_CURREC @20h)
;	are set to agree with the Relative Record (FCBF_RELREC @21h).  The
;	record is then loaded at the Disk Transfer Address.  The record length
;	is taken from the Record Size (FCB_RECSIZE @0Eh) of the FCB.
;
; Inputs:
;	REG_DS:REG_DX -> FCB
;
; Outputs:
;	REG_AL = FCBERR result
;
; Modifies:
;	Any
;
DEFPROC	fcb_rread,DOS
	call	get_fcb
	jc	frr9
	ASSUME	ES:NOTHING		; DS:BX -> SFB, ES:DI -> FCB
	mov	cx,1			; CX = record count
	call	seek_fcb		; set CUR fields and seek
	call	read_fcb		; read CX bytes and set DL to result
	mov	[bp].REG_AL,dl		; REG_AL = result
frr9:	ret
ENDPROC	fcb_rread

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_setrel (REG_AH = 24h)
;
; FCB Set Relative Record.  From the MS-DOS 3.3 Programmer's Reference:
;
;	Function 24h sets the Relative Record (FCBF_RELREC @21h) to the file
;	address specified by the Current Block (FCB_CURBLK @0Ch) and Current
;	Record (FCBF_CURREC @20h).  DX must contain the offset (from the
;	segment address in DS) of an opened FCB.  You use this call to set the
;	file pointer before a Random Read or Write (Functions 21h, 22h, 27h,
;	or 28h).
;
; So, whereas Function 21h multiplies FCBF_RELREC by FCB_RECSIZE to get an
; offset, which it then divides by 16K to get FCB_CURBLK (and divides the
; remainder by FCB_RECSIZE to obtain FCBF_CURREC), we must do the reverse.
;
; Calculates (FCB_CURBLK * 16K) + (FCBF_CURREC * FCB_RECSIZE) and then divides
; by FCB_RECSIZE to obtain the corresponding FCBF_RELREC.
;
; Inputs:
;	REG_DS:REG_DX -> FCB
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	fcb_setrel,DOS
	call	get_fcb
	jc	fsl9
	ASSUME	ES:NOTHING		; DS:BX -> SFB, ES:DI -> FCB
	mov	ax,es:[di].FCB_CURBLK
	mov	dx,16*1024
	mul	dx			; DX:AX = FCB_CURBLK * 16K
	mov	cx,dx
	xchg	si,ax			; CX:SI = DX:AX
	mov	al,es:[di].FCBF_CURREC
	mov	ah,0
	mov	dx,es:[di].FCB_RECSIZE
	push	dx			; save FCB_RECSIZE
	mul	dx			; DX:AX = FCBF_CURREC * FCB_RECSIZE
	add	ax,si
	adc	dx,cx			; DX:AX += FCB_CURBLK * 16K
	pop	cx			; CX = FCB_RECSIZE
	call	div_32_16		; DX:AX /= CX (remainder in BX)
	mov	es:[di].FCBF_RELREC.LOW,ax
	mov	es:[di].FCBF_RELREC.HIW,dx
fsl9:	ret
ENDPROC	fcb_setrel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_rbread (REG_AH = 27h)
;
; FCB Random Block Read.  From the MS-DOS 3.3 Programmer's Reference:
;
;	Function 27h reads one or more records from a specified file to
;	the Disk Transfer Address.  DX must contain the offset (from the
;	segment address in DS) of an opened FCB.  CX contains the number
;	of records to read.  Reading starts at the record specified by the
;	Relative Record (FCBF_RELREC @21h); you must set this field with
;	Function 24h (Set Relative Record) before calling this function.
;
;	DOS calculates the number of bytes to read by multiplying the
;	value in CX by the Record Size (offset 0EH) of the FCB.
;
;	CX returns the number of records read.  The Current Block
;	(FCB_CURBLK @0Ch), Current Record (FCBF_CURREC @20h), and Relative
;	Record (FBBF_RELREC @21h) are set to address the next record.
;
; Inputs:
;	REG_DS:REG_DX -> FCB
;	REG_CX = # records to read
;
; Outputs:
;	REG_AL = FCBERR result
;	REG_CX = # records successfully read
;
; Modifies:
;	Any
;
DEFPROC	fcb_rbread,DOS
	call	get_fcb
	jc	frb9
	ASSUME	ES:NOTHING		; DS:BX -> SFB, ES:DI -> FCB
	mov	cx,[bp].REG_CX		; CX = # records
	call	seek_fcb		; set CUR fields and seek
	call	read_fcb		; read CX bytes and set DL to result
	mov	[bp].REG_AL,dl		; REG_AL = result
	jnc	frb1
	sub	ax,ax			; on error, set count to zero
frb1:	mov	cx,es:[di].FCB_RECSIZE
	sub	dx,dx
	div	cx			; AX = # bytes read / FCB_RECSIZE
	mov	[bp].REG_CX,ax		; REG_CX = # records read
	call	inc_fcb			; advance to the next record
frb9:	ret
ENDPROC	fcb_rbread

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_parse (REG_AH = 29h)
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
	sub	ax,ax
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
; Inputs:
;	REG_DS:REG_DX -> FCB
;
; Outputs:
;	If carry clear:
;	  DS:BX -> SFB
;	  ES:DI -> FCB
;	Otherwise, carry set
;
; Modifies:
;	BX, CX, DI, ES
;
DEFPROC	get_fcb,DOS
	mov	cx,[bp].REG_DS		; CX:DX -> FCB
	call	sfb_find_fcb
	jc	gf9
	mov	di,dx
	mov	es,cx			; ES:DI -> FCB
	ret
gf9:	mov	byte ptr [bp].REG_AL,FCBERR_EOF	; TODO: verify this error code
	ret
ENDPROC	get_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; inc_fcb
;
; Advance FCBF_RELREC and update the FCB_CURBLK and FCBF_CURREC fields.
;
; Inputs:
;	AX = # records to advance
;	ES:DI -> FCB
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	inc_fcb
	add	es:[di].FCBF_RELREC.LOW,ax
	adc	es:[di].FCBF_RELREC.HIW,0
	call	setcur_fcb
	ret
ENDPROC	inc_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copy_name
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
pf2e:	cmp	bl,cl
	jae	pf2			; valid character but we're at limit
	mov	es:[di+bx],al		; store it
	inc	bx
	jmp	pf2
pf3:	or	dh,1			; wildcard present
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
	cmp	dl,[bpb_total]
	cmc				; carry clear if >= 0 and < bpb_total
	ret
ENDPROC	parse_name

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_fcb
;
; Read CX bytes for FCB at ES:DI into current DTA.
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
;	AX, CX, DX, SI
;
DEFPROC	read_fcb
	mov	al,IO_RAW		; TODO: matter for block devices?
	push	es
	push	di
	push	es:[di].FCB_RECSIZE
	mov	si,[scb_active]
	les	dx,[si].SCB_DTA		; ES:DX -> DTA

	DPRINTF	'f',<"read_fcb: requesting %#x bytes from %#lx into %04x:%04x\r\n">,cx,[bx].SFB_CURPOS.LOW,[bx].SFB_CURPOS.HIW,es,dx

	push	cx
	push	dx
	call	sfb_read
	pop	di			; ES:DI -> DTA now
	pop	cx
	mov	dl,FCBERR_OK		; DL = 00h (FCBERR_OK)
	pop	si			; SI = FCB_RECSIZE
	jc	rf4
	test	ax,ax
	jnz	rf5
rf4:	sub	ax,ax			; TODO: throw away error code?
	inc	dx			; DL = 01h (FCBERR_EOF)
	jmp	short rf8

rf5:	sub	cx,ax			; did we read # bytes requested?
	jz	rf8			; yes
;
; Fill the remainder of the last incomplete record (if any) with zeros.
;
	xchg	ax,cx			; CX = # bytes read
	sub	dx,dx			; DX:AX = # bytes not read
	div	si			; DX = remainder from DX:AX / SI
	xchg	cx,dx			; CX = # of bytes to fill
	add	di,dx
	mov	al,0
	rep	stosb
	xchg	ax,dx			; AX = # bytes read
	mov	dl,FCBERR_PARTIAL	; DL = 03h (FCBERR_PARTIAL)

rf8:	DPRINTF	'f',<"read_fcb: read %#x bytes (result %#.2x)\r\n">,ax,dx

	pop	di
	pop	es
	ret
ENDPROC	read_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; seek_fcb
;
; Set the FCB_CURBLK and FCBF_CURREC fields to match the FCBF_RELREC field,
; and then seek to FCBF_RELREC * FCB_RECSIZE.
;
; Inputs:
;	CX = # records
;	ES:DI -> FCB
;
; Outputs:
;	CX = # bytes to read
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	seek_fcb
	push	cx			; CX = # records
	call	setcur_fcb
	call	mul_32_16		; DX:AX = DX:AX * CX
	xchg	dx,ax
	xchg	cx,ax			; CX:DX = offset
	mov	al,SEEK_BEG		; seek to absolute offset CX:DX
	call	sfb_seek
	pop	ax			; AX = # records
	mul	es:[di].FCB_RECSIZE
	ASSERT	Z,<test dx,dx>
	xchg	cx,ax			; CX = # bytes to read
	ret
ENDPROC	seek_fcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setcur_fcb
;
; Set the FCB_CURBLK and FCBF_CURREC fields to match the FCBF_RELREC field.
;
; Note that block size is always FCB_RECSIZE * 128 (a block is defined as 128
; records), so FCB_CURBLK is FCBF_RELREC/128 and FCBF_CURREC is the remainder.
;
; Inputs:
;	ES:DI -> FCB
;
; Outputs:
;	CX = FCB_RECSIZE
;	DX:AX = FCBF_RELREC
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	setcur_fcb
	mov	ax,es:[di].FCBF_RELREC.LOW
	mov	dx,es:[di].FCBF_RELREC.HIW
	mov	cx,es:[di].FCB_RECSIZE	; CX = FCB_RECSIZE
	cmp	cx,64
	jb	sc1
	mov	dh,0			; use only 3 bytes if RECSIZE >= 64
;
; Even if DX:AX was reduced to FFFFFFh by virtue of RECSIZE >= 64, division
; by 128 (80h) would not be safe (DX:AX would have to be reduced to 7FFFFFh),
; so we must always use div_32_16.  However, all that does is prevent a
; division overflow; if DX is non-zero on return, the caller is requesting a
; relative record that's too large.  TODO: How should we deal with that?
;
sc1:	push	dx
	push	ax
	push	bx
	push	cx
	mov	cx,128
	call	div_32_16		; DX:AX /= 128 (BX = remainder)
	ASSERT	Z,<test dx,dx>
	mov	es:[di].FCB_CURBLK,ax	; update FCB's current block
	mov	es:[di].FCBF_CURREC,bl	; update FCB's current record
	pop	cx
	pop	bx
	pop	ax
	pop	dx
	ret
ENDPROC	setcur_fcb

DOS	ends

	end
