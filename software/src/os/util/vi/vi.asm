;
; BASIC-DOS Visual Editor
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: VI [file]
;
; A full-screen editor with a subset of vi's commands (see the External
; Commands page of the BASIC-DOS manual).  It works on both CON and COM (ANSI
; or VT100) consoles, using IOCTL_SETPOS and IOCTL_SCROLL to update the
; screen, and IOCTL_SETKEYS to read raw keys, which both drivers return the
; same way: non-ASCII keys (eg, cursor keys) are a zero followed by the PC
; scan code.
;
; Text (up to 64K) is kept in a separate segment as a "gap buffer": the text
; before the gap starts at offset 0, and the text after the gap ends at the
; end of the segment, so inserting or deleting at the gap is cheap, and the
; gap moves only when the text changes elsewhere (see moveGap).  All other
; code uses logical offsets (0 to V_LEN-1), and getc does the translation.
; Lines end with LF (CR/LF in files), and the last line always has one, so
; the buffer is never empty.  The segment grows as needed (see makeRoom).
;
; Deleted and yanked text is copied to separate (and shared) memory blocks,
; and there is one level of undo, which records the offset of the last
; change, the text it deleted, and the length of the text it inserted.
;
; The editor is split into modules (VI, VIBUF, VICMD, and VIMOVE) that share
; vi.inc; this one, which must be linked first, contains the startup code,
; file I/O, the command loop, key input, and the message functions.
;
	DOSFUNC equ 1
	include	vi.inc

CODE	SEGMENT word public 'CODE'

	EXTNEAR	<clampCur,clearAll,clearScreen,countLines,dispCol,getc,insChar>
	EXTNEAR	<markStatus,putText,refresh,setPos>
	EXTBYTE	<CMDTBL,MOTTBL>

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:NOTHING, SS:CODE
DEFPROC	main
	mov	bp,ds:[PSP_HEAP]	; BP -> VIVARS
	mov	di,bp
	mov	cx,size VIVARS
	sub	ax,ax
	rep	stosb
	dec	ax
	mov	[bp].V_UOFF,ax		; no undo yet
	call	getName
;
; Make sure the console supports IOCTL_GETDIM (eg, STDOUT isn't a file).
;
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDIM
	mov	bx,STDOUT
	int	21h
	mov	si,offset CON_ERR
	jc	m8
	cmp	dl,MAXCOLS		; too many columns?
	jbe	m1			; no
	mov	dl,MAXCOLS
m1:	cmp	dh,MAXROWS		; too many rows?
	jbe	m2			; no
	mov	dh,MAXROWS
m2:	cmp	dh,4			; too few rows?
	jb	m8			; yes
	mov	word ptr [bp].V_COLS,dx	; and V_ROWS
	dec	dh
	mov	[bp].V_TROWS,dh
	mov	dh,0
	lea	ax,[bp].V_ROWBUF
	add	ax,dx
	mov	[bp].V_RLIM,ax

	call	loadFile
	jc	m8

	mov	dx,offset ctrlC
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 23h
	int	21h
	mov	cl,1
	call	setKeys
	call	clearAll
	jmp	cmdLoop
;
; Display the error message at SI and exit.
;
m8:	call	writeErr
	mov	si,offset CRLF
	call	writeErr
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
ENDPROC	main

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
	mov	ah,DOS_HDL_WRITE
	int	21h
	ret
ENDPROC	writeErr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ctrlC
;
; INT 23h handler: DOS has echoed the CTRLC, so the screen must be redrawn,
; and returning with IRET continues the interrupted DOS call.
;
	ASSUME	DS:NOTHING
DEFPROC	ctrlC,FAR
	mov	cs:[fCtrlC],1
	iret
ENDPROC	ctrlC
	ASSUME	DS:CODE

	DEFBYTE	fCtrlC,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getName
;
; Copies the first argument in the command tail to V_FNAME.
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	getName
	mov	si,PSP_CMDTAIL+1
gn1:	lodsb
	cmp	al,CHR_SPACE		; whitespace?
	je	gn1			; yes
	cmp	al,CHR_TAB
	je	gn1
	lea	di,[bp].V_FNAME
	mov	cx,MAXNAME-1
gn2:	cmp	al,CHR_SPACE		; end of the name (or the tail)?
	jbe	gn9			; yes
	mov	[di],al
	inc	di
	lodsb
	loop	gn2
gn9:	mov	byte ptr [di],0
	ret
ENDPROC	getName

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; loadFile
;
; Allocates the text segment and loads V_FNAME (if any) into it, removing
; every CR and anything after CTRLZ, and makes sure the text ends with LF.
;
; Outputs:
;	If carry set, SI -> error message
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	loadFile
	sub	cx,cx			; CX = file size (none yet)
	mov	si,offset NEW_MSG
	cmp	[bp].V_FNAME,0		; is there a file name?
	je	lf2			; no
	lea	dx,[bp].V_FNAME
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	lf2			; assume it's a new file
	xchg	bx,ax			; BX = handle
	mov	ax,DOS_HDL_SEEKEND
	sub	cx,cx
	sub	dx,dx
	int	21h			; DX:AX = file size
	mov	si,offset BIG_ERR
	test	dx,dx
	jnz	lf0
	cmp	ax,MAXTEXT		; is the file too large?
	jbe	lf1			; no
lf0:	stc
	ret
lf1:	push	ax
	mov	ax,DOS_HDL_SEEKBEG
	sub	cx,cx
	sub	dx,dx
	int	21h
	pop	cx			; CX = file size
	sub	si,si			; no message yet

lf2:	push	cx
	push	si
	mov	ax,cx
	add	ax,GROW
	jnc	lf3
	mov	ax,0FFF0h
lf3:	add	ax,15
	rcr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	push	bx
	xchg	bx,ax			; BX = paragraphs
	mov	ax,bx
	mov	cl,4
	shl	ax,cl
	mov	[bp].V_GL,ax		; the entire segment is the gap
	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h
	pop	bx
	pop	si
	pop	cx
	jc	lf7
	mov	[bp].V_TSEG,ax
	mov	es,ax
	jcxz	lf5			; no file to read
;
; Read the file into the start of the segment, and then remove the CRs.
;
	push	ds
	mov	ds,ax
	sub	dx,dx
	mov	ah,DOS_HDL_READ
	int	21h
	pop	ds
	jc	lf7a
	push	ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	cx			; CX = bytes read
	push	si
	push	ds
	push	es
	pop	ds
	sub	si,si
	sub	di,di
lf4:	jcxz	lf4b
	lodsb
	dec	cx
	cmp	al,CHR_RETURN
	je	lf4
	cmp	al,CHR_CTRLZ
	je	lf4b
	stosb
	jmp	lf4
lf4b:	pop	ds
	pop	si
	mov	[bp].V_LEN,di
	mov	[bp].V_GS,di
	sub	[bp].V_GL,di
;
; Make sure the text ends with LF.
;
lf5:	mov	bx,[bp].V_LEN
	dec	bx
	call	getc
	jc	lf5a
	cmp	al,CHR_LINEFEED
	je	lf6
lf5a:	inc	bx
	mov	al,CHR_LINEFEED
	call	insChar
lf6:	mov	[bp].V_FLAGS,0
	lea	dx,[bp].V_FNAME
	mov	bx,dx
	cmp	byte ptr [bx],0		; is there a file name?
	je	lf6b			; no, so there's nothing to display
	test	si,si			; message for a new file?
	jnz	lf6a			; yes
	call	infoMsg			; display the name, lines, and bytes
	jmp	short lf6b
lf6a:	call	nameMsg
lf6b:	clc
	ret
lf7a:	mov	si,offset READ_ERR
	stc
	ret
lf7:	mov	si,offset MEM_ERR
	stc
	ret
ENDPROC	loadFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; saveFile
;
; Writes the text to the specified file, adding a CR before every LF (and
; a text containing only one empty line is written as an empty file).
;
; Inputs:
;	DX -> file name
;
; Outputs:
;	Carry clear if successful (and a message is displayed either way)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	saveFile
	push	dx
	mov	ah,DOS_HDL_CREATE
	sub	cx,cx
	int	21h
	jc	sf8
	mov	[bp].V_HDL,ax
	lea	di,[bp].V_OBUF
	sub	bx,bx
	cmp	[bp].V_LEN,1		; just one empty line?
	je	sf4			; yes
sf1:	call	getc
	jc	sf4
	cmp	al,CHR_LINEFEED
	jne	sf2
	mov	byte ptr [di],CHR_RETURN
	inc	di
sf2:	mov	[di],al
	inc	di
	lea	ax,[bp+V_OBUF+OBUF_LEN-1]
	cmp	di,ax			; is the buffer (nearly) full?
	jb	sf3			; no
	call	flushOut
	jc	sf7
sf3:	inc	bx
	jmp	sf1
sf4:	call	flushOut
sf7:	pushf
	mov	bx,[bp].V_HDL
	mov	ah,DOS_HDL_CLOSE
	int	21h
	popf
	pop	dx
	jc	sf9
	call	infoMsg
	clc
	ret
sf8:	pop	dx
sf9:
	mov	si,offset WRITE_ERR
	jmp	setMsg			; (which sets carry)
ENDPROC	saveFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; flushOut
;
; Inputs:
;	DI -> end of data in V_OBUF
;
; Outputs:
;	DI -> V_OBUF; carry set on error (eg, disk full)
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	flushOut
	lea	dx,[bp].V_OBUF
	mov	cx,di
	sub	cx,dx
	mov	di,dx
	jcxz	fo9
	push	bx
	mov	bx,[bp].V_HDL
	mov	ah,DOS_HDL_WRITE
	int	21h
	pop	bx
	jc	fo9
	cmp	ax,cx			; was everything written?
	jb	fo9			; no (and carry is set)
fo9:	ret
ENDPROC	flushOut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; infoMsg, nameMsg
;
; Displays the name of a file, followed by the text's lines and bytes (with
; a CR for every LF), or for nameMsg, by another message.
;
; Inputs:
;	DX -> file name
;	SI -> message to follow the name (nameMsg only)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	infoMsg
	call	msgName
	mov	bx,[bp].V_LEN
	mov	dx,bx
	cmp	bx,1			; just one empty line?
	ja	im1			; no
	dec	bx			; yes, so it's an empty file
	dec	dx
im1:	call	countLines		; AX = # lines
	push	ax
	add	ax,dx
	mov	dx,0
	adc	dx,dx			; DX:AX = # bytes
	pop	cx
	push	dx
	push	ax
	xchg	ax,cx
	call	msgSpNum
	mov	si,offset LINES_MSG
	call	msgStr
	pop	ax
	pop	dx
	call	msgNum
	mov	si,offset BYTES_MSG
	jmp	short im8
	DEFLBL	nameMsg,near
	push	si
	call	msgName
	pop	si
im8:	call	msgStr
	jmp	msgEnd
ENDPROC	infoMsg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msgName
;
; Starts a message with a quoted file name.
;
; Inputs:
;	DX -> file name
;
; Outputs:
;	DI -> end of the message
;
; Modifies:
;	AX, SI, DI
;
DEFPROC	msgName
	lea	di,[bp].V_MSG
	mov	byte ptr [di],CHR_DQUOTE
	inc	di
	mov	si,dx
	call	msgStr
	mov	byte ptr [di],CHR_DQUOTE
	inc	di
	ret
ENDPROC	msgName

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdLoop
;
; Reads and performs commands until the editor exits.
;
DEFPROC	cmdLoop
	call	clampCur
	test	[bp].V_FLAGS,F_KEEPW	; keep the desired column?
	jnz	cl1			; yes
	mov	bx,[bp].V_CUR
	call	dispCol
	mov	[bp].V_WANT,ax
cl1:	and	[bp].V_FLAGS,NOT F_KEEPW
	call	refresh
	call	getKey
	cmp	[bp].V_MSGLEN,0		; is a message displayed?
	je	cl2			; no
	mov	[bp].V_MSGLEN,0		; yes, so erase it
	push	ax
	call	markStatus
	pop	ax
cl2:	sub	cx,cx
	call	getCount
	mov	[bp].V_COUNT,cx
	test	cx,cx
	jnz	cl3
	inc	cx			; CX = count (at least 1)
cl3:	mov	si,offset CMDTBL
	call	lookup
	jc	cmdLoop
	mov	bx,[bp].V_CUR
	cmp	si,offset MOTTBL	; is it a motion?
	ja	cl4			; yes
	call	word ptr [si-2]
	jmp	cmdLoop
cl4:	mov	dl,0
	call	word ptr [si-2]		; BX = new offset, DL = motion flags
	jc	cmdLoop
	mov	[bp].V_CUR,bx
	test	dl,M_VERT		; vertical motion?
	jz	cmdLoop			; no
	or	[bp].V_FLAGS,F_KEEPW
	jmp	cmdLoop
ENDPROC	cmdLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getCount
;
; Inputs:
;	AX = key (from getKey)
;	CX = count so far
;
; Outputs:
;	AX = first key after the count, CX = count (0 if none)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	getCount
	test	ah,ah			; non-ASCII key?
	jnz	gt9			; yes
	cmp	al,'0'
	jb	gt9
	jne	gt1
	jcxz	gt9			; a leading '0' is a motion
gt1:	cmp	al,'9'
	ja	gt9
	sub	al,'0'
	cbw
	xchg	ax,cx
	mov	dx,10
	mul	dx
	add	cx,ax			; CX = (count * 10) + digit
	push	cx
	call	getKey
	pop	cx
	jmp	getCount
gt9:	ret
ENDPROC	getCount

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; lookup
;
; Inputs:
;	AL = key
;	SI -> table of 3-byte entries (key, handler), ending with zero
;
; Outputs:
;	If carry clear, SI -> entry after the matching entry
;
; Modifies:
;	SI
;
DEFPROC	lookup
lk1:	cmp	byte ptr [si],0		; end of the table?
	je	lk8			; yes
	cmp	al,[si]
	lea	si,[si+3]
	jne	lk1
	ret				; (carry clear)
lk8:	stc
	ret
ENDPROC	lookup

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getKey
;
; Returns the next key.  Non-ASCII keys (a zero followed by a scan code) are
; mapped to the equivalent command keys (eg, the up-arrow key returns 'k'),
; with AH set, so that insert mode knows they're not text.
;
; Outputs:
;	AL = key, AH = non-zero if the key was mapped (AX = 0 if the read
;	failed, eg, due to CTRLC)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	getKey
	sub	ax,ax
	xchg	ax,[bp].V_PEND
	test	ax,ax			; pending key?
	jnz	gk9			; yes
gk1:	call	readKey
	jc	gk8
	mov	ah,0
	test	al,al			; non-ASCII key?
	jnz	gk9			; no
	call	readKey			; AL = scan code
	jc	gk8
	mov	si,offset SCAN_KEYS
	call	mapKey
	jc	gk1			; ignore keys without a mapping
	mov	ah,1
gk9:	ret
;
; The read failed (eg, CTRLC), so make sure we redraw everything (the
; writes will also trigger the CTRLC, which our ctrlC handler ignores).
;
gk8:	call	clearAll
	sub	ax,ax
	ret
ENDPROC	getKey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mapKey
;
; Inputs:
;	AL = key
;	SI -> table of 2-byte entries (key, mapping), ending with zero
;
; Outputs:
;	If carry clear, AL = mapping
;
; Modifies:
;	AL, SI
;
DEFPROC	mapKey
mk1:	cmp	byte ptr [si],0		; end of the table?
	stc
	je	mk9			; yes
	cmp	al,[si]
	lea	si,[si+2]
	jne	mk1
	mov	al,[si-1]		; (carry clear)
mk9:	ret
ENDPROC	mapKey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; readKey
;
; Outputs:
;	AL = next byte from the console; carry set if the read failed
;
; Modifies:
;	AX
;
DEFPROC	readKey
	mov	ah,DOS_TTY_IN
	int	21h
	ret
ENDPROC	readKey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setKeys
;
; Inputs:
;	CL = 1 for raw keys, 0 for normal keys
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	setKeys
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_SETKEYS
	mov	bx,STDIN
	int	21h
	ret
ENDPROC	setKeys

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; quit
;
DEFPROC	quit
	mov	cl,0
	call	setKeys
	call	clearScreen
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
ENDPROC	quit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Message functions
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setMsg
;
; Inputs:
;	SI -> null-terminated message
;
; Outputs:
;	Carry set (since most messages are errors)
;
; Modifies:
;	AX, SI, DI
;
DEFPROC	setMsg
	lea	di,[bp].V_MSG
	call	msgStr
	call	msgEnd
	stc
	ret
ENDPROC	setMsg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msgEnd
;
; Inputs:
;	DI -> end of the message in V_MSG
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, DI
;
DEFPROC	msgEnd
	lea	ax,[bp].V_MSG
	sub	di,ax
	xchg	ax,di
	mov	[bp].V_MSGLEN,al
	jmp	markStatus
ENDPROC	msgEnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msgStr
;
; Inputs:
;	SI -> null-terminated string to append at DI
;
; Modifies:
;	AL, SI, DI
;
DEFPROC	msgStr
ms1:	lodsb
	test	al,al
	jz	ms9
	mov	[di],al
	inc	di
	jmp	ms1
ms9:	ret
ENDPROC	msgStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msgNum, msgSpNum
;
; Appends the decimal value of DX:AX (or AX, preceded by a space) at DI.
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	msgSpNum
	mov	byte ptr [di],CHR_SPACE
	inc	di
	sub	dx,dx
	DEFLBL	msgNum,near
	push	bx
	mov	bx,10
	sub	si,si
mn1:	mov	cx,ax
	xchg	ax,dx
	sub	dx,dx
	div	bx			; AX = high quotient, DX = remainder
	xchg	ax,cx
	div	bx			; AX = low quotient, DX = digit
	push	dx
	inc	si
	mov	dx,cx			; DX:AX = quotient
	or	cx,ax
	jnz	mn1
	mov	cx,si
mn2:	pop	ax
	add	al,'0'
	mov	[di],al
	inc	di
	loop	mn2
	pop	bx
	ret
ENDPROC	msgSpNum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; readCmd
;
; Reads a command line (or search pattern) on the status row.
;
; Inputs:
;	AL = prompt character (eg, ':')
;
; Outputs:
;	If carry clear, SI -> null-terminated text, CX = length
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	readCmd
	mov	[bp].V_LINE,al
	mov	cx,1
rc1:	push	cx
	lea	si,[bp].V_LINE
	call	putText
	pop	cx
	push	cx
	mov	ch,[bp].V_TROWS
	call	setPos
	call	getKey
	pop	cx
	test	ah,ah			; non-ASCII key?
	jnz	rc1			; yes, ignore it
	cmp	al,CHR_RETURN
	je	rc8
	cmp	al,CHR_ESCAPE
	je	rc7
	cmp	al,CHR_BACKSPACE
	je	rc4
	cmp	al,CHR_DEL
	je	rc4
	cmp	al,CHR_SPACE		; other control character?
	jb	rc1			; yes, ignore it
	mov	dl,[bp].V_COLS
	dec	dx
	dec	dx
	cmp	cl,dl			; is the line full?
	jae	rc1			; yes
	mov	si,cx
	mov	[bp+si].V_LINE,al
	inc	cx
	jmp	rc1
rc4:	dec	cx			; erasing the prompt cancels
	jnz	rc1
rc7:	call	markStatus
	stc
	ret
rc8:	call	markStatus
	mov	si,cx
	mov	[bp+si].V_LINE,0
	dec	cx
	lea	si,[bp+V_LINE+1]
	clc
	ret
ENDPROC	readCmd


;
; Non-ASCII keys (scan codes) and their equivalent commands.
;
SCAN_KEYS	db	SCAN_UP,'k',SCAN_DOWN,'j',SCAN_LEFT,'h'
		db	SCAN_RIGHT,'l',SCAN_HOME,'0',SCAN_END,'$'
		db	SCAN_PGUP,CHR_CTRLB,SCAN_PGDN,CHR_CTRLF
		db	SCAN_DEL,'x',SCAN_INS,'i',0

NEW_MSG		db	" [New File]",0
LINES_MSG	db	" lines, ",0
BYTES_MSG	db	" bytes",0
CON_ERR		db	"Console required",0
BIG_ERR		db	"File too large",0
READ_ERR	db	"Read error",0
	DEFLBL	MEM_ERR,byte
		db	"Out of memory",0
WRITE_ERR	db	"Write error",0
CRLF		db	13,10,0

CODE	ENDS

	end	main
