;
; BASIC-DOS Help Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: HELP [keyword|ALL|BASIC|CORE|FUNC|CMD|EXT]
;
; Displays help for a keyword, or lists the keywords in a category, from
; HELP.TXT in the EXT folder of the drive that COMMAND.COM was loaded from
; (normally the boot drive), so HELP works from any directory.  The exit code
; is 1 if there's no help for the keyword (or HELP.TXT can't be read).
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	devapi.inc
	include	dosapi.inc

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; main
;
; If a keyword is specified, display help for that keyword, or if it's a
; category (ALL, BASIC, FUNC, CMD, or EXT), list the keywords in that category
; (see findHelp), or for CORE, display help for CORE and then list the keywords
; that aren't in COMMAND's core; otherwise, display help for HELP, which
; describes the categories.  Categories are checked first, so a category hides
; any keyword with the same name.
;
HELP_TEXTLEN	equ	256

DEFPROC	main
;
; Get the console width (80 if STDOUT doesn't support GETDIM), and the switch
; and path chars, which the help text uses (see printChars).
;
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDIM
	mov	bx,STDOUT
	int	21h			; DL = # columns
	jnc	m1
	mov	dl,80
m1:	mov	[CON_COLS],dl
	mov	ax,DOS_MSC_GETSWC
	int	21h			; DL = switch char
	mov	[SWITCH_CHAR],dl
	mov	ax,DOS_MSC_GETPCH
	int	21h			; DL = path char
	mov	[PATH_CHAR],dl
;
; HELP.TXT is in the EXT folder of the drive that COMMAND.COM was loaded
; from, which COMMAND puts first in the environment, as COMSPEC (see buildEnv
; in COMMAND); if there's no COMSPEC, we use the current drive.
;
	mov	di,offset HELP_PATH
	mov	[di+2],dl
	mov	[di+6],dl
	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	al,'A'			; AL = current drive letter
	mov	cx,ds:[PSP_ENVSEG]
	jcxz	m2			; no environment
	push	di
	mov	es,cx
	sub	di,di			; ES:DI -> environment
	mov	si,offset COMSPEC
	mov	cx,COMSPEC_LEN
	repe	cmpsb			; does it start with COMSPEC?
	jne	m1a			; no
	mov	al,es:[di]		; yes, so use its drive letter
m1a:	push	ds
	pop	es
	pop	di
m2:	mov	[di],al
;
; Find the first argument (SI) and its length (CX).
;
	mov	si,PSP_CMDTAIL+1
m3:	lodsb
	cmp	al,CHR_RETURN		; end of the tail?
	je	m4			; yes
	cmp	al,CHR_SPACE		; whitespace?
	jbe	m3			; yes
m4:	dec	si
	mov	di,si			; DI -> argument, if any
m5:	lodsb
	cmp	al,CHR_SPACE		; (CHR_RETURN ends it, too)
	ja	m5
	dec	si
	xchg	cx,si
	sub	cx,di			; CX = length of argument
	mov	si,di
	jcxz	m9			; no argument
;
; If the argument is a category, list the entries tagged with the category's
; first letter in lower case (eg, "b" for BASIC), or for ALL, every entry.
;
	mov	di,offset HELP_CATS
hpc1:	mov	ah,[di]			; AH = 1st letter of the next category
	test	ah,ah			; any more?
	jz	m8			; no
	push	cx
	push	si
hpc2:	lodsb
	and	al,0DFh			; (upper-case the argument)
	cmp	al,[di]
	jne	hpc4
	inc	di
	loop	hpc2
	cmp	[di],cl			; does the category end here, too?
	jne	hpc4			; no
	pop	si
	pop	cx
	or	ah,20h			; AH = tag (eg, "b")
	cmp	ah,'a'			; ALL?
	jne	hpc3			; no
	mov	ah,0			; yes, so list every entry
hpc3:	mov	ch,ah			; CH = tag
	cmp	cx,('c' SHL 8) OR 4	; CORE (rather than CMD)?
	jne	hpc3a			; no
	push	cx
	call	doHelp			; yes, so display help for CORE first
	pop	cx
	mov	ch,'+'			; and list the entries tagged "+"
	jmp	short hpc3b		; (CORE's help ended with a blank line)
hpc3a:	call	printCRLF		; start the list with a blank line
hpc3b:	mov	cl,0			; CL = 0 to list entries
	jmp	short m8
hpc4:	pop	si
	pop	cx
hpc5:	inc	di
	cmp	byte ptr [di-1],0	; skip the rest of the category
	jne	hpc5
	jmp	hpc1
;
; Without an argument, display help for HELP (the name in HELP_PATH).
;
m9:	mov	si,offset HELP_PATH+7
	mov	cx,4
m8:	call	doHelp
	mov	ax,DOS_PSP_RETURN SHL 8
	adc	al,0			; exit code 1 if carry is set
	int	21h
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doHelp
;
; Inputs:
;	DS:SI -> name
;	CL = length of name (zero to list entries), CH = tag (zero for all)
;
; Outputs:
;	Carry set if there was no entry (or an error), clear otherwise
;
; Modifies:
;	Any
;
DEFPROC	doHelp
	mov	dx,offset HELP_PATH
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jnc	h0
	mov	cx,offset VERB_FIND
	jmp	fileError
h0:	xchg	bx,ax			; BX = handle
	push	cx
	call	findHelp		; DX = offset, CX = length
	pop	ax
	jnc	h1
	xchg	cx,ax			; CL = length of name
	mov	ah,DOS_HDL_CLOSE
	int	21h
	test	cl,cl			; were we just listing entries?
	jnz	h0a			; no
	call	printCRLF		; yes, so end with a blank line
	clc
	ret
h0a:	PRINTF	<"No help available",13,10>
	stc
	ret
h1:	push	cx
	sub	cx,cx
	mov	ax,DOS_HDL_SEEKBEG
	int	21h			; seek to 0:DX
	pop	cx			; CX = # bytes left to read
;
; Entries can be larger than our stack, so we read them in pieces, into a
; buffer on the stack (see fillHelp).  The byte before the text is the
; previous character (initially a space), and the word after the text (and
; its CHR_CTRLZ) is the end of the buffered text.
;
	sub	sp,HELP_TEXTLEN+4
	mov	si,sp
	mov	byte ptr [si],' '
	inc	si			; SI -> next char
	mov	[si+HELP_TEXTLEN+1],si	; (nothing buffered yet)
;
; Every entry ends with a blank line, so start with one, too.  Then keep track
; of the current line's available characters (DL) and maximum characters (DH),
; and print only whole words that will fit.
;
	call	printCRLF
	mov	dl,[CON_COLS]		; DL = # available chars
	dec	dx			; DL = # available chars - 1
	mov	dh,dl
;
; The first line of an entry with tags (ie, anything but a topic like CORE)
; is its syntax.
;
	cmp	[ENTRY_TAGS],0
	je	h2
	sub	dl,7			; 7 = length of "Usage: "
	push	dx
	PRINTF	<"Usage: ">
	pop	dx
h2:	call	fillHelp		; buffer more text if needed
	jc	h2c
	call	getWord			; AX = next word length
	test	al,al			; any more words?
	jz	h2c			; no
	cmp	al,dl			; will it fit on the line?
	jbe	h2a			; yes
	cmp	al,dh			; is it too large regardless?
	jbe	h2b			; no
h2a:	call	printChars		; print # chars in AL
	call	printSpace		; print whitespace that follows
	jz	h2c			; if ZF set, must have hit CHR_CTRLZ
	jmp	h2
h2b:	call	printEOL
	jmp	h2

h2c:	add	sp,HELP_TEXTLEN+4	; deallocate the buffer
	mov	ah,DOS_HDL_CLOSE
	int	21h
	ret
ENDPROC	doHelp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fillHelp
;
; If less than half a buffer of HELP text remains and there's more to read,
; move the remaining text (and the char before it) to the start of the
; buffer and fill the rest of the buffer.
;
; Inputs:
;	BX = handle
;	CX = # bytes left to read
;	SI -> next char in buffer (which follows our return address)
;
; Outputs:
;	If carry clear, CX and SI updated as appropriate
;	If carry set, an error message was printed
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	fillHelp
	mov	di,sp
	inc	di
	inc	di			; DI -> buffer
	mov	ax,[di+HELP_TEXTLEN+2]	; AX -> end of buffered text
	sub	ax,si			; AX = # bytes still buffered
	jcxz	fl9			; nothing left to read (carry clear)
	cmp	ax,HELP_TEXTLEN/2
	jae	fl9			; enough is buffered (carry clear)
	push	cx
	xchg	cx,ax
	inc	cx			; include the previous char
	dec	si
	rep	movsb			; move it to the start of the buffer
	pop	cx
	mov	si,sp
	add	si,3			; SI -> next char (at buffer + 1)
	lea	ax,[si+HELP_TEXTLEN]
	sub	ax,di			; AX = free space in buffer
	cmp	ax,cx
	jbe	fl1
	mov	ax,cx
fl1:	sub	cx,ax			; CX = # bytes left after this read
	push	cx
	push	dx
	push	si
	xchg	cx,ax			; CX = # bytes to read
	mov	si,di
	call	readInput		; read CX bytes into DS:SI
	pop	si
	pop	dx
	pop	cx
	jc	fl9
	add	di,ax
	mov	byte ptr [di],CHR_CTRLZ	; mark the end of the text
	mov	[si+HELP_TEXTLEN+1],di	; and record it
fl9:	ret
ENDPROC	fillHelp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findHelp
;
; Searches the (open) HELP file for the entry whose first word matches the
; specified name (in any case).  Entries are separated by blank lines, and
; the matching word must be followed by a character other than a letter or
; digit, so "MID" and "MID$" both match "MID$(...)", while "DEF" doesn't
; match "DEFINT".
;
; If the name is empty, the first word of every entry is listed instead (only
; letters, digits, '$', and '%' are printed, so an entry that begins with any
; other character, like '*', is omitted).
;
; An entry can begin with tags in brackets (eg, "[b+]"), which aren't part of
; the entry: a category (a lower-case letter, such as "b" for BASIC; see
; main), and "+" if it isn't in COMMAND's core.  A listing of one category
; (or of tag "+", for CORE, the entries tagged "+") lists only the entries
; that have that tag.
;
; Inputs:
;	BX = handle
;	DS:SI -> name
;	CL = length of name (zero to list entries), CH = tag (zero for all)
;
; Outputs:
;	If carry clear, DX = offset of entry, CX = length of entry
;
; Modifies:
;	AX, CX, DX, SI, DI
;
HELP_BUFLEN	equ	128

DEFPROC	findHelp
	push	bp
	mov	bp,sp
	push	si			; [bp-2] -> name
	push	cx			; [bp-4] = length of name, [bp-3] = tag
	mov	ax,2
	push	ax			; [bp-6] = # consecutive LINEFEEDs
	push	ax			; [bp-8] = offset of current entry
	sub	ax,ax
	push	ax			; [bp-10] = column (if listing),
					; [bp-9] = the current entry's tags
	sub	sp,HELP_BUFLEN
	sub	di,di			; DI = offset of next character
	mov	dx,-1			; DX = offset of matching entry (none)
	mov	al,dl			; AL = # chars matched (-1 if none)
fh1:	push	ax
	push	dx
	mov	si,sp
	add	si,4			; DS:SI -> buffer
	mov	cx,HELP_BUFLEN
	call	readInput		; AX = # bytes read
	xchg	cx,ax			; CX = # bytes read
	pop	dx
	pop	ax
	jc	fh1a
	jcxz	fh1a			; end of file
	jmp	short fh2
fh1a:	jmp	fh8
fh2:	mov	ah,[si]			; AH = next character
	inc	si
	cmp	ah,CHR_RETURN
	je	fh2a
	cmp	ah,CHR_LINEFEED
	jne	fh3
	inc	word ptr [bp-6]
fh2a:	cmp	byte ptr [bp-4],0	; listing entries?
	je	fh4			; yes
	cmp	al,[bp-4]		; does the line end a matching name?
	mov	al,-1
	je	fh4a			; yes
	jmp	short fh7
fh3:	cmp	word ptr [bp-6],2	; does an entry start here?
	mov	word ptr [bp-6],0
	jb	fh4			; no
	cmp	dx,-1			; did we already find a match?
	jne	fh9			; yes, so this is the end of it
	mov	[bp-8],di
	jmp	fh16			; check the entry's category
fh4:	cmp	al,-1			; still matching (or listing)?
	je	fh7			; no
	cmp	byte ptr [bp-4],0	; listing entries?
	je	fh11			; yes
	cmp	al,[bp-4]		; entire name matched?
	jb	fh5			; not yet
	mov	al,-1
	cmp	ah,'0'			; next character must not be
	jb	fh4a			; a digit or letter
	cmp	ah,'9'
	jbe	fh7
	cmp	ah,'A'
	jb	fh4a
	cmp	ah,'Z'
	jbe	fh7
fh4a:	mov	dx,[bp-8]		; DX = offset of matching entry
	jmp	short fh7
fh5:	push	bx
	mov	bl,al
	mov	bh,0
	add	bx,[bp-2]
	mov	bl,[bx]			; BL = next character of name
	cmp	bl,'a'
	jb	fh5a
	cmp	bl,'z'
	ja	fh5a
	sub	bl,20h			; convert lower-case to upper-case
fh5a:	cmp	bl,ah
	pop	bx
	je	fh6
	mov	al,-1			; mismatch
	jmp	short fh7
fh6:	inc	ax
fh7:	inc	di
	loop	fh7a
	jmp	fh1
fh7a:	jmp	fh2
fh8:	cmp	byte ptr [bp-10],0	; end of file; is a listing line open?
	je	fh8a			; no
	push	dx
	call	printCRLF
	pop	dx
fh8a:	cmp	dx,-1			; was there a match?
	stc
	je	fh10			; no
fh9:	mov	cx,di
	sub	cx,dx			; CX = length of entry (carry clear)
fh10:	mov	sp,bp
	pop	bp
	ret
;
; Listing: print AH if it's part of the entry's first word (AL = # chars
; printed so far); otherwise, end the word by padding it to the next column.
;
fh11:	cmp	ah,'$'
	je	fh12
	cmp	ah,'%'
	je	fh12
	cmp	ah,'0'
	jb	fh13
	cmp	ah,'9'
	jbe	fh12
	cmp	ah,'A'
	jb	fh13
	cmp	ah,'Z'
	ja	fh13
fh12:	push	ax
	mov	al,ah
	call	printChar
	pop	ax
	inc	ax
	inc	byte ptr [bp-10]
	jmp	fh7
fh13:	cmp	al,0			; anything printed?
	mov	al,-1
	je	fh15			; no
;
; If the longest name (10 characters) wouldn't fit at the next column, end
; the line instead, without padding it (so the cursor never wraps).
;
	mov	ah,[bp-10]
	or	ah,7			; AH = next column - 1
	add	ah,10
	cmp	ah,[CON_COLS]		; is there room for another name?
	jb	fh14			; yes
	push	ax
	push	cx
	push	dx
	call	printCRLF
	pop	dx
	pop	cx
	pop	ax
	mov	byte ptr [bp-10],0
fh15:	jmp	fh7
fh14:	push	ax
	mov	al,' '
	call	printChar
	pop	ax
	inc	byte ptr [bp-10]
	test	byte ptr [bp-10],7	; at the next column yet?
	jnz	fh14			; no
	jmp	fh15
;
; At the start of an entry, skip its tags and their brackets, recording the
; tags in [bp-9] (the category letter, and bit 7 for "+"), and since the next
; character may be a tag, too, it's also the start of the entry.  After the
; tags, if we're listing one category (or the "+" entries), skip the entry if
; it isn't in it.
;
fh16:	cmp	ah,'+'			; not in the core?
	jne	fh16a			; no
	or	byte ptr [bp-9],80h
	jmp	short fh16b
fh16a:	cmp	ah,'['			; a bracket or category?
	jb	fh16c			; no, so the tags are done
	cmp	ah,'a'			; a category?
	jb	fh16b			; no, so skip the bracket
	or	[bp-9],ah
fh16b:	mov	word ptr [bp-6],2	; (so the next char starts the entry)
	jmp	fh7
fh16c:	mov	al,[bp-3]		; AL = category to list (0 for all)
	cmp	byte ptr [bp-4],0	; listing entries?
	jne	fh16e			; no
	test	al,al			; all of them?
	jz	fh16e			; yes
	cmp	al,'+'			; the entries that aren't in the core?
	jne	fh16d			; no
	test	byte ptr [bp-9],80h	; is this one of them?
	jnz	fh16e			; yes
	jmp	short fh16x
fh16d:	mov	al,[bp-9]
	and	al,7Fh
	cmp	al,[bp-3]		; is the entry in the category?
	je	fh16e			; yes
fh16x:	mov	byte ptr [bp-9],0
	mov	al,-1			; no, so skip the entry
	jmp	fh7
fh16e:	mov	al,0
	xchg	al,[bp-9]
	mov	[ENTRY_TAGS],al		; (see doHelp)
	mov	al,0			; start matching
	jmp	fh4
ENDPROC	findHelp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; readInput
;
; Inputs:
;	BX = handle
;	CX = # bytes to read
;	DS:SI -> buffer
;
; Outputs:
;	If carry clear, AX = # bytes read
;	If carry set, an error message was printed
;
; Modifies:
;	AX, CX (on error), DX
;
DEFPROC	readInput
	mov	dx,si
	mov	ah,DOS_HDL_READ
	int	21h
	jnc	ri9
	mov	cx,offset VERB_READ
;
; fileError reports the error (AX) that the operation (CX -> verb) on
; HELP.TXT returned (eg, "Unable to find A:\EXT\HELP.TXT"), and sets carry.
;
	DEFLBL	fileError,near
	mov	dx,offset HELP_PATH
	EPRINTF	<"Unable to %s %s">,<13,10>,ax,cx,dx
	stc
ri9:	ret
ENDPROC	readInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getWord
;
; Inputs:
;	DS:SI -> characters to print
;
; Outputs:
;	AX = # of characters in next non-whitespace sequence (ie, "word")
;
; Modifies:
;	AX
;
DEFPROC	getWord
	push	si
gw1:	lodsb
	cmp	al,'\'			; a backslash that ends a line must be
	jne	gw2			; included in the word length, but we
	cmp	byte ptr [si],' '	; don't print it, so increase the line
	jae	gw1			; length (any other backslash is a path
	inc	dx			; char, which we print; see printChars)
	jmp	short gw3
gw2:	cmp	al,' '
	ja	gw1
	dec	si
gw3:	pop	ax
	sub	si,ax
	xchg	si,ax
	ret
ENDPROC	getWord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printChar
;
; Inputs:
;	AL = character
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	printChar
	push	dx
	xchg	dx,ax
	mov	ah,DOS_TTY_WRITE
	int	21h
	pop	dx
	ret
ENDPROC	printChar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printChars
;
; Inputs:
;	AL = character count
;	DS:SI -> characters to print
;	DL = avail characters on line
;	DH = maximum characters on line
;
; Outputs:
;	SI, DL updated as appropriate
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	printChars
	push	ax
	push	cx
	cbw
	xchg	cx,ax			; CX = count
pr1:	lodsb
	cmp	al,'\'			; lines ending with backslash
	jne	pr1b			; trigger a single newline and
	cmp	byte ptr [si],' '	; skip remaining whitespace
	jae	pr1a
	call	skipSpace
	pop	cx
	pop	ax
	ret
;
; HELP.TXT separates directory names with backslashes (which is correct when
; the path char is '\'), so we print each one as the current path char.
;
pr1a:	mov	al,[PATH_CHAR]
	jmp	short pr2
;
; HELP.TXT starts each switch with a tilde (eg, ~P), so we print each one as
; the current switch char.
;
pr1b:	cmp	al,'~'
	jne	pr1c
	mov	al,[SWITCH_CHAR]
	jmp	short pr2
;
; Asterisks around words (eg, *path*) are skipped, but an asterisk that isn't
; followed by a letter and follows a space or backslash (eg, B:\*.BAS) is a
; wildcard, so we print it.
;
pr1c:	cmp	al,'*'
	jne	pr2
	mov	ah,[si]
	and	ah,0DFh			; AH = next char (upper-cased)
	sub	ah,'A'
	cmp	ah,26			; is it a letter?
	jb	pr8			; yes
	mov	ah,[si-2]		; AH = previous char
	cmp	ah,' '
	jbe	pr2
	cmp	ah,'\'
	jne	pr8
pr2:	call	printChar
pr8:	loop	pr1
	pop	cx
	pop	ax
	sub	dl,al			; reduce available chars on line
	ret
ENDPROC	printChars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printSpace
;
; Inputs:
;	DS:SI -> characters to print
;	DL = avail characters on line
;	DH = maximum characters on line
;
; Outputs:
;	SI, DL updated as appropriate
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	printSpace
ps1:	cmp	dl,1			; if current line is almost full
	jle	skipSpace		; print CRLF and then skip all space
	lodsb
	cmp	al,CHR_TAB
	je	ps2
	cmp	al,CHR_SPACE
	ja	ps8
	jb	ps5
ps2:	call	printChar
	dec	dx
	jmp	ps1
ps5:	dec	si
	call	printEOL
	DEFLBL	skipSpace,near
	call	printEOL
ps7:	lodsb
	cmp	al,CHR_TAB		; tab at the start of a line?
	jne	ps7a			; no
	call	printChar		; yes, so indent the line
	sub	dl,8			; (by 8 chars)
	jmp	ps7
ps7a:	cmp	al,CHR_CTRLZ		; end of text?
	je	ps8			; yes
	cmp	al,CHR_SPACE		; non-whitespace?
	ja	ps8			; yes
	jmp	ps7			; keep looping
ps8:	dec	si
	ret
ENDPROC	printSpace

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printEOL
;
; Inputs:
;	DL = avail characters on line
;	DH = maximum characters on line
;
; Outputs:
;	DL = DH
;
; Modifies:
;	AX, DX
;
DEFPROC	printEOL
	mov	dl,dh			; reset available characters in DL
	DEFLBL	printCRLF,near
	PRINTF	<13,10>			; print CHR_RETURN, CHR_LINEFEED
	ret
ENDPROC	printEOL

;
; HELP_CATS contains the categories (see main), whose first letters (in
; lower case) are the tags in HELP.TXT, except for CORE (see findHelp).
;
HELP_CATS	db	"ALL",0,"BASIC",0,"CORE",0,"FUNC",0,"CMD",0,"EXT",0,0
;
; main updates HELP_PATH's drive and path chars, and with no argument, looks
; up "HELP" in it.
;
HELP_PATH	db	"A:\EXT\HELP.TXT",0
COMSPEC		db	"COMSPEC="
COMSPEC_LEN	equ	$ - COMSPEC
VERB_FIND	db	"find",0
VERB_READ	db	"read",0
CON_COLS	db	?
SWITCH_CHAR	db	?
PATH_CHAR	db	?
ENTRY_TAGS	db	?		; tags of the last entry (see findHelp)

;
; COMHEAP 0 means we don't need a heap, but BASIC-DOS will still allocate a
; minimum amount of heap space, because that's where our initial stack lives
; (with room for the buffers that doHelp and findHelp put there).
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
