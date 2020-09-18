;
; BASIC-DOS FCB Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<bpb_total>,byte
	EXTERNS	<scb_active>,word
	EXTERNS	<sfb_open_fcb,sfb_find_fcb,sfb_seek,sfb_read,sfb_close>,near
	EXTERNS	<mul_32_16>,near

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
	mov	cx,[bp].REG_DS		; CX:DX -> FCB
	call	sfb_find_fcb
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
;	REG_AL:
;	  00h: read successful
;	  01h: EOF, empty record
;	  02h: DTA too small
;	  03h: EOF, partial record
;
; Modifies:
;
DEFPROC	fcb_sread,DOS
	mov	cx,[bp].REG_DS		; CX:DX -> FCB
	call	sfb_find_fcb
;
; TODO: Implement.
;
fs9:	ret
ENDPROC	fcb_sread

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_rread (REG_AH = 21h)
;
; Read a random record (FCBF_RELREC) into the DTA.  The current block
; (FCB_CURBLK) and current record (FCBF_CURREC) are set to agree with the
; relative record (FCBF_RELREC).  The record is then read into the DTA,
; using the FCB's record size (FCB_RECSIZE).
;
; Inputs:
;	REG_DS:REG_DX -> FCB
;
; Outputs:
;	REG_AL:
;	  00h: read successful
;	  01h: EOF, empty record
;	  02h: DTA too small
;	  03h: EOF, partial record
;
; Modifies:
;	Any
;
DEFPROC	fcb_rread,DOS
	mov	cx,[bp].REG_DS		; CX:DX -> FCB
	call	sfb_find_fcb
	jc	fs9			; TODO: decide how to treat this error
	mov	di,dx
	mov	es,cx			; ES:DI -> FCB
	ASSUME	ES:NOTHING
;
; At this point, DS:BX -> SFB and ES:DI -> FCB.
;
; Multiply the requested record (FCBF_RELREC) by the record size (FCB_RECSIZE)
; to get the offset.
;
	mov	cx,es:[di].FCB_RECSIZE
	mov	ax,es:[di].FCBF_RELREC.LOW
	mov	dx,es:[di].FCBF_RELREC.HIW
	cmp	cx,64
	jb	fr1
	mov	dh,0
fr1:	call	mul_32_16		; DX:AX = DX:AX * CX

	xchg	dx,ax			; AX:DX
	xchg	cx,ax			; CX:DX
	mov	al,SEEK_BEG		; seek to absolute offset CX:DX
	call	sfb_seek
	xchg	ax,cx			; AX:DX
	xchg	ax,dx			; DX:AX
	mov	cx,16*1024		; CX = 16K
	div	cx			; AX = block #
	mov	es:[di].FCB_CURBLK,ax	; update FCB's current block
	xchg	ax,dx			; AX = byte offset within block
	sub	dx,dx
	mov	cx,es:[di].FCB_RECSIZE	; CX = # bytes to read
	div	cx			; AX = record # within block
	ASSERT	Z,<test ah,ah>
	mov	es:[di].FCBF_CURREC,al

	mov	al,IO_RAW		; TODO: matter for block devices?
	mov	si,[scb_active]
	les	dx,[si].SCB_DTA		; ES:DX -> DTA

	DPRINTF	<"fcb_rread: requesting %#x bytes from %#lx into %04x:%04x",13,10>,cx,[bx].SFB_CURPOS.LOW,[bx].SFB_CURPOS.HIW,es,dx

	push	cx
	push	dx
	call	sfb_read
	pop	di			; ES:DI -> DTA now
	pop	cx
	mov	dl,0			; DL = default return code (00h)
	jc	fr6
	test	ax,ax
	jnz	fr7
fr6:	inc	dx			; DL = 01h (EOF, no data)
	jmp	short fr8
fr7:	cmp	ax,cx
	je	fr8
;
; Fill the remainder of the DTA with zeros.
;
	sub	cx,ax			; CX = # of bytes to fill
	add	di,ax
	mov	al,0
	rep	stosb

	mov	dl,3			; DL = 03h (EOF, partial record)
fr8:	mov	[bp].REG_AL,dl		; REG_AL = return code

	DPRINTF	<"fcb_rread: returned %#.2x",13,10>,dx

fr9:	ret
ENDPROC	fcb_rread

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
	jnz	pf1c			; no
	mov	al,0			; yes, specify 0 for default drive
	jmp	short pf1b
pf1a:	inc	si			; skip colon
	sub	al,'A'			; AL = drive number
	mov	dl,al			; DL = drive number (validate later)
	inc	ax			; store 1-based drive number
pf1b:	mov	es:[di+bx],al
pf1c:	inc	di
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
pf9:	cmp	dl,[bpb_total]
	cmc				; carry clear if >= 0 and < bpb_total
	ret
ENDPROC	parse_name

DOS	ends

	end
