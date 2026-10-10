;
; BASIC-DOS Filter Utility Procedures
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Included by each filter utility after its own code (see util.inc).
;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getArgs
;
; Parses the command tail: each switch letter (eg, the 'V' in "-V") sets an
; entry in UV_SW, and "+n" (after the SWITCHAR) sets UV_COL; a quoted string
; is recorded in UV_STR and UV_STRLEN; and every other argument is treated
; as a file name, which is null-terminated in place and recorded in UV_FILES.
;
; Inputs:
;	BP -> UTILVARS
;
; Outputs:
;	UTILVARS updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
	ASSUME	CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	getArgs
	mov	ax,DOS_MSC_GETSWC
	int	21h			; DL = SWITCHAR
	mov	si,PSP_CMDTAIL+1
ga1:	lodsb
	cmp	al,CHR_RETURN		; end of the tail?
	je	ga9			; yes
	cmp	al,CHR_SPACE		; whitespace (or other control char)?
	jbe	ga1			; yes
	cmp	al,dl			; SWITCHAR?
	je	ga3			; yes
	cmp	al,CHR_DQUOTE		; quoted string?
	je	ga5			; yes
	lea	bx,[si-1]		; BX -> file name
	mov	di,[bp].UV_NFILES
	cmp	di,MAXFILES*2		; room for another?
	jae	ga2			; no, so ignore it
	mov	[bp].UV_FILES[di],bx
	inc	di
	inc	di
	mov	[bp].UV_NFILES,di
ga2:	lodsb
	cmp	al,CHR_SPACE
	ja	ga2
	mov	byte ptr [si-1],0	; null-terminate the file name
	cmp	al,CHR_RETURN		; did it end the tail?
	jne	ga1			; no
ga9:	ret

ga3:	lodsb				; consume switch chars
	cmp	al,'+'			; column switch?
	je	ga4			; yes
	and	al,NOT 20h		; upper-case it
	sub	al,'A'
	cmp	al,26			; a letter?
	jae	ga1a			; no, so re-examine it
	cbw
	xchg	di,ax
	mov	[bp].UV_SW[di],1
	jmp	ga3

ga4:	lodsb				; consume digits
	sub	al,'0'
	cmp	al,9
	ja	ga1a
	cbw
	xchg	bx,ax			; BX = digit
	mov	ax,10
	push	dx
	mul	[bp].UV_COL
	pop	dx
	add	ax,bx
	mov	[bp].UV_COL,ax
	jmp	ga4

ga5:	mov	[bp].UV_STR,si
ga6:	lodsb
	cmp	al,CHR_DQUOTE		; end of quoted string?
	je	ga7			; yes
	cmp	al,CHR_RETURN		; end of the tail?
	jne	ga6			; no
ga7:	lea	bx,[si-1]
	sub	bx,[bp].UV_STR
	mov	[bp].UV_STRLEN,bx
	cmp	al,CHR_DQUOTE		; did the string end with a quote?
	je	ga1			; yes
ga1a:	dec	si			; no, so re-examine the last char
	jmp	ga1
ENDPROC	getArgs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openFile
;
; Inputs:
;	BP -> UTILVARS
;	DX -> null-terminated file name
;
; Outputs:
;	If carry clear, UV_HIN is the file's handle (and DX is unchanged)
;	If carry set, an error has been displayed, and UV_ERR is 2
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	openFile
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	of8
	mov	[bp].UV_HIN,ax
	mov	[bp].UV_INEND,0		; and the input buffer is empty
	ret
of8:	push	dx
	mov	si,offset OPEN_ERR
	call	writeErr
	pop	si
	call	writeErr
	mov	si,offset CRLF
	call	writeErr
	mov	[bp].UV_ERR,2
	stc
	ret
ENDPROC	openFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; readLine
;
; Reads the next line of input into UV_LINE.  A line ends with LF, and a
; line without one (eg, the last line of a file, or a line longer than
; LINE_MAX) gets CR/LF appended, so every line ends with LF.
;
; Inputs:
;	BP -> UTILVARS
;
; Outputs:
;	If carry clear, DX -> line, CX = length
;	If carry set, there's no more input
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	readLine
	push	ds
	pop	es
	lea	di,[bp].UV_LINE
	mov	dx,di
	mov	cx,LINE_MAX-2
rl1:	call	getc
	jc	rl7
	stosb
	cmp	al,CHR_LINEFEED
	loopne	rl1
	je	rl9
	jmp	short rl8
rl7:	cmp	di,dx			; any chars at all?
	stc
	je	rl10			; no
rl8:	mov	ax,CHR_RETURN OR (CHR_LINEFEED SHL 8)
	stosw
rl9:	mov	cx,di
	sub	cx,dx			; CX = length (and carry is clear)
rl10:	ret
ENDPROC	readLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getc
;
; Returns the next byte of input.  CTRLZ marks the end of input, so we don't
; advance past it, ensuring that every subsequent call also ends.
;
; Inputs:
;	BP -> UTILVARS
;
; Outputs:
;	If carry clear, AL = next byte
;	If carry set, there's no more input
;
; Modifies:
;	AX, SI
;
DEFPROC	getc
	mov	si,[bp].UV_INPOS
	cmp	si,[bp].UV_INEND
	jb	gc1
	push	bx
	push	cx
	push	dx
	lea	dx,[bp].UV_INBUF
	mov	cx,INBUF_LEN
	mov	bx,[bp].UV_HIN
	mov	ah,DOS_HDL_READ
	int	21h
	jc	gc0
	mov	si,dx
	add	ax,dx
	mov	[bp].UV_INEND,ax
	cmp	ax,si			; anything read?
	jne	gc0			; yes (and carry is clear)
	stc
gc0:	pop	dx
	pop	cx
	pop	bx
	jc	gc9
gc1:	lodsb
	cmp	al,CHR_CTRLZ		; end of input?
	stc
	je	gc9			; yes
	mov	[bp].UV_INPOS,si
	clc
gc9:	ret
ENDPROC	getc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeErr
;
; Inputs:
;	SI -> null-terminated string to write to STDERR
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	writeErr
	DOSUTIL	STRLEN			; AX = length
	xchg	cx,ax
	mov	dx,si
	mov	bx,STDERR
	jmp	short writeHdl
ENDPROC	writeErr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeOut
;
; If the write fails (eg, the command reading our output through a pipe has
; ended), there's no point in continuing, so we exit.
;
; Inputs:
;	DS:DX -> data to write to STDOUT
;	CX = length
;
; Modifies:
;	AX, BX
;
DEFPROC	writeOut
	mov	bx,STDOUT
	DEFLBL	writeHdl,near
	mov	ah,DOS_HDL_WRITE
	int	21h
	jc	exit
	ret
ENDPROC	writeOut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; toUpper
;
; Inputs:
;	AL = character
;
; Outputs:
;	AL = upper-case character
;
DEFPROC	toUpper
	cmp	al,'a'
	jb	tu9
	cmp	al,'z'
	ja	tu9
	sub	al,'a'-'A'
tu9:	ret
ENDPROC	toUpper

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; exit
;
; Inputs:
;	BP -> UTILVARS
;
; Outputs:
;	Terminates with UV_ERR as the exit code
;
DEFPROC	exit
	mov	al,[bp].UV_ERR
	mov	ah,DOS_PSP_RETURN
	int	21h
ENDPROC	exit

OPEN_ERR	db	"Unable to open ",0
CRLF		db	13,10,0
