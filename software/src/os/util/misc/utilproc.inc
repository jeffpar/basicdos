;
; BASIC-DOS Filter Utility Procedures
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Included by each filter utility after its own code (see utilvars.inc).
;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getArgs
;
; Parses the command tail: each switch letter (eg, the 'V' in "-V") sets an
; entry in UV_SW, and "+n" (after the switch char) sets UV_COL; a quoted string
; is recorded in UV_STR and UV_STRLEN; and every other argument is treated
; as a file name, which is null-terminated in place and recorded in UV_FILES.
; For utilities that take a string (UTILRE), if no string was quoted, the
; first file name (if any) becomes the string instead (eg, "FIND BAS").
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
	int	21h			; DL = switch char
	mov	si,PSP_CMDTAIL+1
ga1:	lodsb
	cmp	al,CHR_RETURN		; end of the tail?
	je	ga9			; yes
	cmp	al,CHR_SPACE		; whitespace (or other control char)?
	jbe	ga1			; yes
	cmp	al,dl			; switch char?
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
ga9:
	IFDEF	UTILRE
	mov	cx,[bp].UV_NFILES
	cmp	[bp].UV_STR,0		; was a string quoted?
	jne	ga9a			; yes
	jcxz	ga9a			; no, and there are no file names
	lea	di,[bp].UV_FILES
	mov	si,[di]			; SI -> first file name
	mov	[bp].UV_STR,si
	push	si
	lea	si,[di+2]
	dec	cx
	dec	cx
	mov	[bp].UV_NFILES,cx
	rep	movsb			; remove it from UV_FILES
	pop	di
	mov	al,0
	dec	cx			; CX = -1
	repne	scasb
	not	cx
	dec	cx			; CX = length of the string
	mov	[bp].UV_STRLEN,cx
ga9a:
	ENDIF
	ret

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
	je	ga8			; yes
ga1a:	dec	si			; no, so re-examine the last char
ga8:	jmp	ga1
ENDPROC	getArgs

	IFDEF	UTILWALK
UTIL_PCH equ byte ptr [bp].UV_PCH
	include	util.inc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; eachFile
;
; Calls a function for each file named on the command line, or for a name
; with wildcards (? and *), for each matching file.  The file is open as the
; input (UV_HIN) when the function is called, and it's closed afterward.
;
; Inputs:
;	BP -> UTILVARS
;	CX -> function (called with BP -> UTILVARS and DX -> file name)
;
; Modifies:
;	Any
;
DEFPROC	eachFile
	mov	ax,DOS_MSC_GETPCH
	int	21h			; DL = path char (for scanSpec)
	mov	[bp].UV_PCH,dl
	sub	ax,ax
ef1:	push	ax
	push	cx
	xchg	di,ax
	mov	si,[bp].UV_FILES[di]
	call	scanSpec		; DI -> filename portion of SI
	mov	dx,offset doFile
	test	ah,ah			; any wildcards?
	jnz	ef2			; yes
	call	dx
	jmp	short ef3
ef2:	call	walkFiles		; call doFile for each match
	jnc	ef3
	mov	dx,si
	call	openErr			; report the error (eg, no matches)
ef3:	pop	cx
	pop	ax
	inc	ax
	inc	ax
	cmp	ax,[bp].UV_NFILES
	jb	ef1
	ret
ENDPROC	eachFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doFile
;
; Opens a file for eachFile (directly, or through walkFiles), calls the
; function, and closes the file.  Errors are reported by openFile, so carry is
; always clear (to keep walking).  BX isn't preserved, since eachFile doesn't
; need it.
;
; Inputs:
;	SI -> file name
;	CX -> function
;
; Modifies:
;	Any but BP
;
DEFPROC	doFile
	push	bp
	mov	bp,ds:[PSP_HEAP]	; BP -> UTILVARS
	mov	dx,si
	push	cx
	call	openFile
	pop	cx
	jc	df9
	call	cx			; DX -> file name
	mov	bx,[bp].UV_HIN
	mov	ah,DOS_HDL_CLOSE
	int	21h
df9:	clc
	pop	bp
	ret
ENDPROC	doFile
	ENDIF	; UTILWALK

	IFDEF	UTILRE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; reCompile
;
; Compiles a regular expression (RE) in the style of UNIX ed and sed: a
; character matches itself (unless it's preceded by '\', which makes any
; character an ordinary one), '.' matches any character, [chars] matches any
; of the chars or ranges (eg, a-z) in brackets, and [^chars] any character NOT
; in them ("]" can be the first char, and "-" the first or last), '*' after
; any of those matches it zero or more times, '^' at the start matches the
; beginning of the line and '$' at the end its end, and \( and \) mark the
; groups (up to 9) that SED's replacements can refer to.  The nodes are
; bracketed by group 0's marks (the match itself).
;
; The worst case (4 bytes per ordinary character) can't exceed RE_MAX for
; the REs of a single command tail.
;
; Inputs:
;	SI -> RE
;	DL = delimiter that ends the RE (0 if it's null-terminated)
;	DI -> buffer for the compiled RE
;
; Outputs:
;	If carry clear, SI -> character after the delimiter, DI -> end of RE
;	If carry set, the RE is invalid
;
; Modifies:
;	AX, BX, CX, SI, DI
;
DEFPROC	reCompile
	push	bp
	mov	bp,sp			; BP = stack to restore on an error
	sub	cx,cx			; CL = # groups, CH = # groups open
	mov	ax,RE_GRP		; AH = 0 (start of group 0)
	stosw
	lea	bx,[di-2]		; BX -> last node ('*' repeats a class)
	cmp	byte ptr [si],'^'	; does the RE start with '^'?
	jne	rc1			; no
	inc	si
	mov	al,RE_BOL
	stosb
rc1:	lodsb
	cmp	al,dl			; end of the RE?
	je	rc8			; yes
	cmp	al,'*'
	jne	rc2
	cmp	byte ptr [bx],RE_NCCL	; does '*' follow a class?
	jb	rc2			; no, so it's an ordinary character
	or	byte ptr [bx],RE_STAR
	jmp	rc1
rc2:	mov	bx,di			; BX -> this node
	test	al,al			; end of the string?
	jz	rc9			; yes, so the delimiter is missing
	cmp	al,'.'
	je	rc5
	cmp	al,'['
	je	rk0
	cmp	al,'$'
	jne	rc3
	cmp	[si],dl			; is '$' at the end of the RE?
	jne	rc4			; no
	mov	al,RE_EOL
	stosb
	jmp	rc1
rc3:	cmp	al,'\'
	jne	rc4
	lodsb
	cmp	al,'('
	je	rc6
	cmp	al,')'
	je	rc7
	test	al,al			; is '\' at the end of the string?
	jnz	rc4			; no
rc9:	mov	sp,bp			; (an error)
	pop	bp
	stc
	ret

rc8:	test	ch,ch			; any group still open?
	jnz	rc9			; yes
	mov	ax,RE_GRP OR (2 SHL 8)	; end of group 0
	stosw
	mov	al,RE_END
	stosb
	pop	bp
	ret

rk0:	mov	ax,RE_CCL		; AH = 0 (no pairs yet)
	cmp	byte ptr [si],'^'	; negated?
	jne	rk1			; no
	inc	si
	dec	ax			; AL = RE_NCCL
rk1:	stosw
	lodsb				; a ']' here is an ordinary character
	jmp	short rk3
rk2:	lodsb
	cmp	al,']'			; end of the class?
	je	rc1			; yes
rk3:	test	al,al			; end of the string?
	jz	rc9			; yes
	mov	ah,al			; AH = last character of the pair
	cmp	byte ptr [si],'-'	; a range?
	jne	rk4			; no
	cmp	byte ptr [si+1],']'	; unless the '-' ends the class
	je	rk4
	inc	si
	lodsb
	xchg	al,ah			; AH = last character of the range
	test	ah,ah			; end of the string?
	jz	rc9			; yes
rk4:	stosw
	inc	byte ptr [bx+1]		; count the pair
	jmp	rk2

rc4:	push	ax
	mov	ax,RE_CCL OR (1 SHL 8)	; a class with one pair
	stosw
	pop	ax
	mov	ah,al			; (the character twice)
	stosw
	jmp	rc1

rc5:	mov	ax,RE_NCCL		; a negated class with no pairs
	stosw
	jmp	rc1

rc6:	inc	cx			; CL = group #
	cmp	cl,9
	ja	rc9
	mov	al,cl
	add	al,al
	add	al,al			; AL = offset of the group's start
	push	ax
	inc	ch
	jmp	short rc7a
rc7:	dec	ch			; any group open?
	js	rc9			; no
	pop	ax
	or	al,2			; AL = offset of the group's end
rc7a:	mov	ah,al
	mov	al,RE_GRP
	stosw
	jmp	rc1
ENDPROC	reCompile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setLine
;
; Sets the line that reSearch matches, without its CR/LF (or LF).
;
; Inputs:
;	BP -> UTILVARS
;	DX -> line (which ends with LF)
;	CX = length
;
; Outputs:
;	UV_LBEG and UV_LEND set, and SI -> line
;
; Modifies:
;	SI
;
DEFPROC	setLine
	mov	[bp].UV_LBEG,dx
	mov	si,dx
	add	si,cx
	dec	si			; SI -> LF
	cmp	si,dx			; anything before it?
	je	sn9			; no
	cmp	byte ptr [si-1],CHR_RETURN
	jne	sn9
	dec	si			; SI -> CR
sn9:	mov	[bp].UV_LEND,si
	mov	si,dx
	ret
ENDPROC	setLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; reSearch
;
; Finds the first match of a compiled RE in the line (see setLine) at or after
; the specified position.  With -I, letters match either case.
;
; Inputs:
;	BP -> UTILVARS
;	BX -> compiled RE
;	SI -> position in the line
;
; Outputs:
;	If carry clear, UV_GRPS contains the match (and the groups)
;	If carry set, there's no match
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	reSearch
rs1:	push	si
	push	bx
	mov	di,bx
	call	advance
	pop	bx
	pop	si
	jnc	rs9
	inc	si
	cmp	[bp].UV_LEND,si		; carry set if past the end
	jae	rs1
rs9:	ret
ENDPROC	reSearch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; advance
;
; Matches the rest of a compiled RE at the specified position.  A repeated
; class matches as many characters as it can, and then gives them back one at
; a time until the rest of the RE matches (calling advance recursively, which
; uses 8 bytes of stack for each repeat in progress), as ed and sed did.
;
; Inputs:
;	BP -> UTILVARS
;	DI -> compiled RE
;	SI -> position in the line
;
; Outputs:
;	Carry clear if the rest matched
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	advance
ad1:	mov	ah,[di]			; AH = opcode
	inc	di
	cmp	ah,RE_GRP
	ja	ad4			; a class
	je	ad3			; a group mark
	test	ah,ah			; end of the RE?
	jz	ad9			; yes (with carry clear)
	mov	bx,[bp].UV_LBEG
	dec	ah			; RE_BOL?
	jz	ad2			; yes
	mov	bx,[bp].UV_LEND
ad2:	cmp	si,bx			; at the beginning (or end)?
	je	ad1			; yes
	stc
ad9:	ret
ad3:	mov	bl,[di]
	inc	di
	mov	bh,0
	add	bx,bp
	mov	[bx].UV_GRPS,si		; record the group's start (or end)
	jmp	ad1
ad4:	test	ah,RE_STAR		; repeated?
	jnz	ad5			; yes
	call	matchOne
	jnc	ad1
	ret
ad5:	push	si			; save the first position
	mov	dx,di			; DX -> class
ad6:	mov	di,dx
	call	matchOne		; match as many as possible
	jnc	ad6
	pop	cx			; CX = first position
ad7:	push	si
	push	cx
	push	di
	call	advance			; does the rest match here?
	pop	di
	pop	cx
	pop	si
	jnc	ad9			; yes
	dec	si			; no, so give one back
	cmp	si,cx			; carry set if none left
	jnb	ad7
	ret
ENDPROC	advance

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; matchOne
;
; Inputs:
;	BP -> UTILVARS
;	AH = class opcode (RE_CCL or RE_NCCL, and RE_STAR)
;	DI -> class (# pairs, and the pairs)
;	SI -> position in the line
;
; Outputs:
;	DI -> next node
;	If carry clear, the character at SI matched, and SI is advanced
;
; Modifies:
;	AL, BX, CX, SI, DI
;
DEFPROC	matchOne
	mov	cl,[di]
	mov	ch,0			; CX = # pairs
	inc	di
	mov	bx,di			; BX -> pairs
	add	di,cx
	add	di,cx			; DI -> next node
	cmp	si,[bp].UV_LEND		; any characters left?
	cmc
	jc	mo9			; no
	lodsb
	call	inClass			; carry set if AL is in the class
	jc	mo8
	CHKSW	'I'			; ignoring case?
	jz	mo8			; no (and carry is clear)
	or	al,20h
	sub	al,'a'
	cmp	al,26			; a letter?
	jae	mo8			; no (and carry is clear)
	add	al,'a'			; AL = lower-case letter
	call	inClass
	jc	mo8
	sub	al,20h			; AL = upper-case letter
	call	inClass
mo8:	sbb	al,al			; AL = -1 if in the class, 0 if not
	xor	al,ah			; RE_CCL inverts that (RE_NCCL doesn't)
	shr	al,1			; carry clear if the character matched
	jnc	mo9
	dec	si
mo9:	ret
ENDPROC	matchOne

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; inClass
;
; Inputs:
;	AL = character
;	BX -> pairs
;	CX = # pairs
;
; Outputs:
;	Carry set if the character is in one of the pairs (ranges)
;
DEFPROC	inClass
	push	bx
	push	cx
	jcxz	ic8
ic1:	cmp	al,[bx]			; below the range?
	jb	ic2			; yes
	cmp	[bx+1],al		; carry set if above the range
	cmc
	jc	ic9			; it's in the range
ic2:	inc	bx
	inc	bx
	loop	ic1
ic8:	clc
ic9:	pop	cx
	pop	bx
	ret
ENDPROC	inClass
	ENDIF	; UTILRE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openFile
;
; openErr reports an error (AX) for a file (DX) the same way.
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
	jc	openErr
	mov	[bp].UV_HIN,ax
	mov	[bp].UV_INEND,0		; and the input buffer is empty
	ret
	DEFLBL	openErr,near
	push	dx
	mov	si,offset FIND_ERR
	cmp	ax,ERR_NOFILE		; file not found?
	je	of9			; yes
	cmp	ax,ERR_NOPATH		; path not found?
	je	of9			; yes
	mov	si,offset OPEN_ERR
of9:	call	writeErr
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
FIND_ERR	db	"Unable to find ",0
CRLF		db	13,10,0
