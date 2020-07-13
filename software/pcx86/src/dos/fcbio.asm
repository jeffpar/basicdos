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

	EXTERNS	<FILENAME_CHARS>,byte
	EXTERNS	<FILENAME_CHARS_LEN>,abs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_name
;
; NOTE: My observations with PC DOS 2.0 are that "ignore leading separators"
; really means "ignore leading whitespace" (ie, spaces or tabs).  This has to
; be one one of the more poorly documented APIs in terms of precise behavior.
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
	ASSERT	STRUCT,es:[bx],SCB
	mov	dl,es:[bx].SCB_CURDRV	; DL = default drive number
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
pf1c:	inc	bx
	sar	ah,1
;
; Build filename at ES:DI+BX from the string at DS:SI, making sure that all
; characters exist within FILENAME_CHARS.
;
pf2:	lodsb
pf2a:	cmp	al,' '			; check character validity
	jb	pf4			; invalid character
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
	mov	cx,FILENAME_CHARS_LEN
	mov	di,offset FILENAME_CHARS
	repne	scasb
	pop	di
	pop	cx
	jne	pf4			; invalid character
pf2e:	cmp	bl,cl
	ja	pf2			; valid character but we're at limit
	mov	es:[di+bx],al		; store it
	inc	bx
	jmp	pf2
pf3:	or	dh,1			; wildcard present
pf3a:	cmp	bl,cl
	ja	pf2
	mov	byte ptr es:[di+bx],'?'	; store '?' until we reach the limit
	inc	bx
	jmp	pf3a
;
; Advance to next part of filename (filling with blanks as appropriate)
;
pf4:	cmp	bl,cl			; are we done with the current portion?
	ja	pf5			; yes
	test	ah,01h			; leave the buffer unchanged?
	jnz	pf4a			; yes
	mov	byte ptr es:[di+bx],' '	; store ' ' until we reach the limit
pf4a:	inc	bx
	jmp	pf4

pf5:	cmp	cl,11			; did we just finish the extension?
	je	pf9			; yes
	mov	bl,9			; BL -> extension
	mov	cl,11			; CL -> extension limit
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
