;
; BASIC-DOS Stream Editor
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: SED [-I] [-N] "script" [file]
;
; Runs the commands in "script" on each line of input (or of the specified
; file), and then writes the line to STDOUT (unless -N).  Commands, separated
; by ';', have the form [address[,address]][!]command, where an address is a
; line #, '$' (the last line), or /RE/ (any line that matches the regular
; expression; see reCompile); a command with one address applies to the
; lines it selects, a command with two applies to each range of lines from one
; that the first address selects through one that the second selects, and '!'
; applies it to the lines NOT selected instead.  The commands are:
;
;	s/RE/text/[g][p]	replaces the first (or with g, every) match
;				of RE with text, in which '&' is the match and
;				\1-\9 are its groups (and p prints the result)
;	d			deletes the line (and starts the next one)
;	p			prints the line
;	q			prints the line (unless -N) and quits
;	=			prints the line #
;
; An empty RE (eg, "//" or "s//text/") reuses the previous one, and any
; character can delimit an s command's parts (eg, "s,/,\\,g" replaces each
; '/' with '\').  -I ignores case in REs.  The script must be quoted if it
; contains spaces (or starts with the switch char), and the exit code is 0,
; or 2 if the script is missing or invalid or the file couldn't be opened.
;
	UTILRE equ 1
	include	utilvars.inc

;
; The script is compiled into an array of SEDCMD records (ending with a record
; whose SC_CMD is 0), and the REs into SV_RES.  Since each command in a script
; takes at least two characters (eg, "p;"), a command tail (no more than 127
; characters) can't hold more than CMDS_MAX of them.
;
CMDS_MAX	equ	64

ADR_LINE	equ	1	; ADR_* address types (0 if none)
ADR_LAST	equ	2
ADR_RE		equ	3

SCF_NOT		equ	01h	; SC_FLAGS: '!' (must be bit 0; see select)
SCF_RANGE	equ	02h	; in a range of lines
SCF_G		equ	04h	; s: replace every match
SCF_P		equ	08h	; s: print the result

SEDCMD		struc
SC_CMD		db	?	; command (0 ends the script)
SC_FLAGS	db	?	; SCF_* flags
SC_A1		db	?	; first address type (ADR_*)
SC_N1		dw	?	; its line # (or offset of its compiled RE)
SC_A2		db	?	; second address type (ADR_*)
SC_N2		dw	?	; its line # (or offset of its compiled RE)
SC_RE		dw	?	; s: offset of the compiled RE
SC_REPL		dw	?	; s: offset of the (null-terminated) text
SEDCMD		ends

SEDVARS		struc
SV_UV		db	size UTILVARS dup (?)
SV_LASTRE	dw	?	; offset of the last compiled RE (for "//")
SV_LIMIT	dw	?	; s: end of the output buffer
SV_PREV		dw	?	; s: end of the last match (0 if none)
SV_DOLLAR	db	?	; non-zero if the script uses '$'
SV_LAST		db	?	; 1 if the line is the last line
SV_CMDS		db	CMDS_MAX * size SEDCMD dup (?)
SV_RES		db	RE_MAX dup (?)
SV_BUF		db	LINE_MAX dup (?); s: output (if not in UV_LINE)
SEDVARS		ends

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	bp,ds:[PSP_HEAP]	; BP -> SEDVARS
	call	getArgs
	lea	di,[bp].UV_FILES	; DI -> file name, if any
	mov	si,[bp].UV_STR
	test	si,si			; was the script quoted?
	jz	m1			; no
	mov	bx,si
	add	bx,[bp].UV_STRLEN
	mov	byte ptr [bx],0		; null-terminate it
	jmp	short m2
m1:	mov	si,offset NO_SCRIPT
	sub	[bp].UV_NFILES,2	; is there an argument for the script?
	jnb	m1a			; yes
m8:	call	writeErr
	mov	[bp].UV_ERR,2
m9:	jmp	exit
m1a:	mov	si,[di]			; SI -> script
	scasw				; DI -> file name, if any
m2:	push	di
	call	compile
	pop	di
	mov	si,offset BAD_SCRIPT
	jc	m8
	cmp	[bp].UV_NFILES,0	; was a file specified?
	je	m3			; no
	mov	dx,[di]
	call	openFile
	jc	m9
;
; Read the next line into the pattern space (UV_LBEG to UV_LEND), and if the
; script uses '$', find out if it's the last line.
;
m3:	call	readLine		; DX -> line, CX = length
	jc	m9			; no more input
	inc	[bp].UV_LINENO
	call	setLine
	cmp	[bp].SV_DOLLAR,0	; does the script use '$'?
	je	m4			; no
	call	getc			; is there more input?
	jc	m3a			; no
	dec	[bp].UV_INPOS		; yes, so put it back
	jmp	short m4
m3a:	inc	[bp].SV_LAST
;
; Run each command that selects the line.
;
m4:	lea	bx,[bp].SV_CMDS
m5:	cmp	[bx].SC_CMD,0		; end of the script?
	je	m7			; yes
	call	select			; carry set if not selected
	jc	m6b
	mov	al,[bx].SC_CMD
	cmp	al,'d'
	je	m3			; start the next line
	push	bx
	cmp	al,'s'
	jne	m5a
	call	subst
	jmp	short m6a
m5a:	cmp	al,'='
	jne	m5b
	PRINTF	<"%u",13,10>,[bp].UV_LINENO
	jmp	short m6a
m5b:	cmp	al,'p'
	je	m6
	CHKSW	'N'			; q: is printing suppressed?
	jnz	m9			; yes
	call	printPS
	jmp	short m9
m6:	call	printPS
m6a:	pop	bx
m6b:	add	bx,size SEDCMD
	jmp	m5
m7:	CHKSW	'N'			; is printing suppressed?
	jnz	m7a			; yes
	call	printPS
m7a:	jmp	m3
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; compile
;
; Inputs:
;	BP -> SEDVARS
;	SI -> script (null-terminated)
;
; Outputs:
;	Carry set if the script is invalid
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	compile
	lea	bx,[bp].SV_CMDS
	lea	di,[bp].SV_RES
c1:	call	skipSpace		; AL = next character
	inc	si
	cmp	al,';'			; an empty command?
	je	c1			; yes
	dec	si
	test	al,al			; end of the script?
	jz	c9			; yes (with carry clear)
	call	getAddr
	jc	c9
	cmp	[bx].SC_A1,0		; was there an address?
	je	c2			; no
	cmp	byte ptr [si],','	; is there a second one?
	jne	c2			; no
	inc	si
	add	bx,SC_A2-SC_A1
	call	getAddr
	lea	bx,[bx-(SC_A2-SC_A1)]
	jc	c9
	cmp	[bx].SC_A2,0		; was there a second address?
	je	c8			; no
c2:	call	skipSpace
	cmp	al,'!'
	jne	c3
	or	[bx].SC_FLAGS,SCF_NOT
	inc	si
	call	skipSpace
c3:	inc	si
	mov	[bx].SC_CMD,al
	cmp	al,'s'
	je	c5
	push	di
	mov	di,offset COMMANDS
	mov	cx,COMMANDS_LEN
	repne	scasb			; one of the other commands?
	pop	di
	jne	c8			; no
c4:	call	skipSpace
	test	al,al			; end of the script?
	jz	c4a			; yes
	cmp	al,';'			; end of the command?
	jne	c8			; no
c4a:	add	bx,size SEDCMD
	jmp	c1
c8:	stc
c9:	ret

c5:	lodsb				; AL = delimiter
	mov	dl,al
	test	al,al			; is there one?
	jz	c8			; no
	call	getRE			; CX -> compiled RE
	jc	c9
	mov	[bx].SC_RE,cx
	mov	[bx].SC_REPL,si
c6:	lodsb
	cmp	al,'\'			; an escape?
	jne	c6a			; no
	lodsb				; skip the escaped character
	test	al,al
	jnz	c6
c6a:	test	al,al			; end of the script?
	jz	c8			; yes, so the delimiter is missing
	cmp	al,dl			; end of the text?
	jne	c6			; no
	mov	byte ptr [si-1],0	; null-terminate it
c7:	lodsb
	mov	ah,SCF_G
	cmp	al,'g'
	je	c7a
	mov	ah,SCF_P
	cmp	al,'p'
	jne	c7b
c7a:	or	[bx].SC_FLAGS,ah
	jmp	c7
c7b:	dec	si
	jmp	c4
ENDPROC	compile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getAddr
;
; Inputs:
;	BP -> SEDVARS
;	BX -> address (offset by SC_A1)
;	SI -> script
;	DI -> next free byte in SV_RES
;
; Outputs:
;	If carry clear, the address is set (or its type remains 0 if there
;	isn't one), and SI and DI are updated
;	If carry set, the address is invalid
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	getAddr
	lodsb
	mov	ah,ADR_LAST
	cmp	al,'$'
	je	gd2
	cmp	al,'/'
	je	gd3
	dec	si
	sub	al,'0'
	cmp	al,10			; a line #?
	jae	gd9			; no, so there's no address
	push	bx
	push	di
	mov	bl,10
	mov	di,-1			; (no validation)
	DOSUTIL	ATOI16			; AX = line #
	pop	di
	pop	bx
	xchg	cx,ax
	mov	ah,ADR_LINE
	jmp	short gd4
gd2:	inc	[bp].SV_DOLLAR
	jmp	short gd4
gd3:	mov	dl,al
	call	getRE			; CX -> compiled RE
	jc	gd9
	mov	ah,ADR_RE
gd4:	mov	[bx].SC_A1,ah
	mov	[bx].SC_N1,cx
gd9:	ret
ENDPROC	getAddr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getRE
;
; Inputs:
;	BP -> SEDVARS
;	SI -> RE (after its opening delimiter)
;	DL = delimiter
;	DI -> next free byte in SV_RES
;
; Outputs:
;	If carry clear, CX -> compiled RE, and SI and DI are updated
;	If carry set, the RE is invalid
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	getRE
	mov	cx,[bp].SV_LASTRE
	cmp	[si],dl			; an empty RE?
	jne	gr1			; no
	inc	si
	cmp	cx,1			; carry set if there's no previous RE
	ret
gr1:	mov	[bp].SV_LASTRE,di
	push	bx
	call	reCompile
	pop	bx
	mov	cx,[bp].SV_LASTRE
	ret
ENDPROC	getRE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; skipSpace
;
; Inputs:
;	SI -> script
;
; Outputs:
;	AL = next character that isn't a space, and SI -> it
;
DEFPROC	skipSpace
ss1:	lodsb
	cmp	al,CHR_SPACE
	je	ss1
	dec	si
	ret
ENDPROC	skipSpace

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; select
;
; Decides whether a command applies to the line, starting or ending its
; range, if any.  As in sed, the second address isn't checked against the
; line that starts a range, unless it's a line # (which ends the range if the
; line # has been reached).
;
; Inputs:
;	BP -> SEDVARS
;	BX -> SEDCMD
;
; Outputs:
;	Carry set if the command doesn't apply
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	select
	test	[bx].SC_FLAGS,SCF_RANGE	; in a range?
	jz	se1			; no
	lea	si,[bx].SC_A2
	call	matchAddr		; does the range end here?
	jc	se4			; no
se3:	and	[bx].SC_FLAGS,NOT SCF_RANGE
	jmp	short se4
se1:	cmp	[bx].SC_A1,0		; any address?
	je	se4			; no, so the line is selected
	lea	si,[bx].SC_A1
	call	matchAddr
	jc	se5			; the line isn't selected
	cmp	[bx].SC_A2,0		; is there a second address?
	je	se4			; no
	or	[bx].SC_FLAGS,SCF_RANGE
	cmp	[bx].SC_A2,ADR_LINE
	jne	se4
	mov	ax,[bp].UV_LINENO
	cmp	ax,[bx].SC_N2		; has its line # been reached?
	jae	se3			; yes, so the range ends here
se4:	clc
se5:	sbb	al,al			; AL = -1 if not selected (or 0)
	xor	al,[bx].SC_FLAGS	; SCF_NOT inverts that
	shr	al,1			; carry set if it doesn't apply
	ret
ENDPROC	select

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; matchAddr
;
; Inputs:
;	BP -> SEDVARS
;	SI -> address (its type, followed by its line # or RE)
;
; Outputs:
;	Carry clear if the address selects the line
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	matchAddr
	lodsb				; AL = type
	mov	si,[si]			; SI = line # (or offset of RE)
	cmp	al,ADR_LAST
	jb	ma1
	je	ma2
	push	bx
	mov	bx,si
	mov	si,[bp].UV_LBEG
	call	reSearch
	pop	bx
	ret
ma1:	sub	si,[bp].UV_LINENO
	neg	si			; carry set unless the line # matches
	ret
ma2:	cmp	[bp].SV_LAST,1		; carry set unless it's the last line
	ret
ENDPROC	matchAddr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; subst
;
; Runs an s command, building the result in whichever buffer (UV_LINE or
; SV_BUF) doesn't hold the pattern space, which becomes the pattern space if
; anything was replaced.  The result is truncated at LINE_MAX-2 characters,
; and after a match, an empty match isn't replaced (eg, "s/x*/-/g" changes
; "abxd" to "-a-b-d-").
;
; Inputs:
;	BP -> SEDVARS
;	BX -> SEDCMD
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	subst
	lea	di,[bp].SV_BUF
	cmp	[bp].UV_LBEG,di		; is the pattern space in SV_BUF?
	jne	su1			; no
	lea	di,[bp].UV_LINE
su1:	push	di			; save the start of the result
	lea	ax,[di+LINE_MAX-2]
	mov	[bp].SV_LIMIT,ax
	mov	[bp].SV_PREV,0		; no matches yet
	mov	si,[bp].UV_LBEG
su2:	push	bx
	push	si
	push	di
	mov	bx,[bx].SC_RE
	call	reSearch
	pop	di
	pop	si
	pop	bx
	jc	su8			; no (more) matches
	mov	cx,[bp].UV_GRPS		; CX -> match
	cmp	cx,[bp].UV_GRPS+2	; is it empty?
	jne	su3			; no
	cmp	cx,[bp].SV_PREV		; right after the last match?
	je	su6			; yes, so skip it
su3:	call	putSpan			; copy the characters before the match
	mov	si,[bx].SC_REPL
	call	putRepl
	mov	si,[bp].UV_GRPS+2	; SI -> end of the match
	mov	[bp].SV_PREV,si
	test	[bx].SC_FLAGS,SCF_G	; replacing every match?
	jz	su8			; no
	cmp	si,[bp].UV_GRPS		; was the match empty?
	jne	su2			; no
su6:	cmp	si,[bp].UV_LEND		; any characters left?
	jae	su8			; no
	lodsb
	call	putChar			; copy the next one
	jmp	su2
su8:	mov	cx,[bp].UV_LEND
	call	putSpan			; copy the rest of the line
	pop	ax			; AX -> result
	cmp	[bp].SV_PREV,0		; was anything replaced?
	je	su9			; no
	mov	[bp].UV_LBEG,ax
	mov	[bp].UV_LEND,di
	test	[bx].SC_FLAGS,SCF_P	; printing the result?
	jnz	printPS			; yes
su9:	ret
ENDPROC	subst

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printPS
;
; Writes the pattern space, followed by CR/LF, to STDOUT.  There's always
; room for the CR/LF at UV_LEND (see readLine and subst).
;
; Inputs:
;	BP -> SEDVARS
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	printPS
	push	bx
	mov	di,[bp].UV_LEND
	mov	ax,CHR_RETURN OR (CHR_LINEFEED SHL 8)
	stosw
	mov	dx,[bp].UV_LBEG
	mov	cx,di
	sub	cx,dx
	call	writeOut
	pop	bx
	ret
ENDPROC	printPS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putRepl
;
; Inputs:
;	BP -> SEDVARS
;	SI -> s command's text
;	DI -> result
;
; Outputs:
;	DI updated
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	putRepl
pr1:	lodsb
	test	al,al			; end of the text?
	jz	pr9			; yes
	mov	ah,'0'			; '&' copies group 0 (the match)
	cmp	al,'&'
	je	pr3
	cmp	al,'\'
	jne	pr2
	lodsb				; AL = escaped character
	mov	ah,al
	sub	al,'1'
	cmp	al,9			; \1-\9?
	jb	pr3			; yes
	mov	al,ah
pr2:	call	putChar
	jmp	pr1
pr3:	push	si
	mov	al,ah
	sub	al,'0'
	cbw
	add	ax,ax
	add	ax,ax
	xchg	si,ax			; SI = offset of the group in UV_GRPS
	mov	cx,[bp].UV_GRPS[si+2]
	mov	si,[bp].UV_GRPS[si]
	call	putSpan
	pop	si
	jmp	pr1
pr9:	ret
ENDPROC	putRepl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putSpan
;
; Copies the characters from SI up to CX (none if CX isn't above SI).
;
; Inputs:
;	BP -> SEDVARS
;	SI -> first character
;	CX -> end
;	DI -> result
;
; Outputs:
;	SI and DI updated
;
; Modifies:
;	AL, SI, DI
;
DEFPROC	putSpan
pp1:	cmp	si,cx
	jae	pp9
	lodsb
	call	putChar
	jmp	pp1
pp9:	ret
ENDPROC	putSpan

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putChar
;
; Inputs:
;	BP -> SEDVARS
;	AL = character
;	DI -> result (the character is dropped if DI has reached SV_LIMIT)
;
; Modifies:
;	DI
;
DEFPROC	putChar
	cmp	di,[bp].SV_LIMIT
	jae	pc9
	stosb
pc9:	ret
ENDPROC	putChar

	include	utilproc.inc

COMMANDS	db	"dpq="
COMMANDS_LEN	equ	$ - COMMANDS
NO_SCRIPT	db	"Missing script",13,10,0
BAD_SCRIPT	db	"Invalid script",13,10,0

	COMHEAP	<size SEDVARS + STACK_LEN>

CODE	ENDS

	end	main
