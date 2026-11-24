;
; BASIC-DOS SDK: FIND16, a 16-bit OS/2 program
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Build it on BASIC-DOS (in protected mode) with the tools in TOOLS\BIN, by
; running MAKE in this directory:
;
;	MAKE MAKEFILE
;
; which assembles it with MASM 5.10B and links it with LINK4 (see FIND16.DEF)
; as an OS/2 1.x program: an NE file that imports OS/2's DOSCALLS functions
; and issues no interrupts, so the same file runs on OS/2 and, in protected
; mode, on BASIC-DOS, whose DOSCALLS.DLL (in EXT\DLL) turns each function into
; DOS calls.  In real mode, and on any other DOS, the file runs its stub
; instead (this file assembled with STUB defined), which only says so.
;
; Usage: FIND16 [/C] [/I] [/N] [/V] string [files...]
;
; It's FIND.COM (see SRC\UTIL\MISC\FIND.ASM), without regular expressions
; (/R), so that the two can be compared: FIND.COM's command line, files, and
; formatted output all come from BASIC-DOS (and from procedures that it shares
; with the other filters), and everything here that isn't an OS/2 function is
; the program's own.  It displays every line of input (or of the files, which
; may include wildcards) that contains string, which must be quoted if it
; contains spaces (otherwise, it's the first argument that isn't a switch).
; /C displays only the number of lines, /I ignores case, /N adds line numbers,
; and /V selects lines that do NOT contain string.  The exit code is 0 if any
; lines were selected, 1 if none, and 2 if an error occurred.
;
; OS/2 has no switch character to ask for, so a switch always starts with '/'
; (BASIC-DOS's default, too).
;
	include	macros.inc
	include	os2.inc

	IFDEF	STUB

CODE	segment word public 'CODE'

	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	main
	push	cs
	pop	ds
	mov	dx,offset nopm
	mov	ah,09h
	int	21h			; print the message
	mov	ax,4C02h
	int	21h			; and end with exit code 2
ENDPROC	main

nopm	db	"FIND16 requires protected mode",13,10,'$'

CODE	ends

STACK	segment	stack
	dw	128 dup (?)
STACK	ends

	ELSE

	.286
;
; OS/2's functions are far procedures that use the Pascal calling convention
; (see PCALL, and OS/2's other definitions, in SRC\INC\OS2.INC).
;
	extrn	DOSEXIT:far,DOSCLOSE:far,DOSFINDCLOSE:far,DOSFINDFIRST:far
	extrn	DOSFINDNEXT:far,DOSOPEN:far,DOSREAD:far,DOSWRITE:far

STDOUT		equ	1	; standard handles
STDERR		equ	2
ERROR_FILE_NOT_FOUND equ 2	; error codes that DOS has, too
ERROR_PATH_NOT_FOUND equ 3
ERROR_INVALID_DRIVE equ	15

SWCHAR		equ	'/'	; switch character
CTRLZ		equ	1Ah	; end of input
MAXFILES	equ	8	; maximum file names on the command line
TAIL_MAX	equ	256	; maximum command tail (including its null)
LINE_MAX	equ	256	; maximum line length (including CR/LF)
INBUF_LEN	equ	512	; input buffer size
OFLAGS		equ	OPENF_EXISTS	; DosOpen's open flags
OMODE		equ	OPENM_READ OR OPENM_DENYNONE	; and open mode
FFLEN		equ	size FILEFINDBUF

;
; The automatic data segment (DGROUP) holds our data and stack, and DS and SS
; address it when the program starts.  The variables in _BSS take no space in
; the file.
;
_DATA	segment word public 'DATA'
hin	dw	0		; input handle (initially STDIN)
errcode	dw	0		; exit code
prefix	dw	offset DGROUP:colon+2	; prefix for a line count (": " or "")
strptr	dw	0		; offset of the string (0 if none)
nfiles	dw	0		; # file names * 2
inpos	dw	0		; offset of next byte in inbuf
inend	dw	0		; offset of end of data in inbuf
nfnd	dw	1		; # files for DosFindFirst and DosFindNext
swlist	db	"CINV"		; the switches
SW_LEN	equ	$ - swlist
swC	db	0		; and whether each was specified, in order
swI	db	0
swN	db	0
swV	db	0
synerr	db	"Syntax error"	; (followed by crlf)
crlf	db	13,10,0
dashes	db	13,10,"---------- ",0
colon	db	": ",0
lbrack	db	"[",0
rbrack	db	"]",0
operr	db	"Unable to open ",0
fnderr	db	"Unable to find ",0
drverr	db	"Invalid drive",0
_DATA	ends

_BSS	segment word public 'BSS'
strlen	dw	?		; length of the string
nsel	dw	?		; # lines selected
lineno	dw	?		; current line #
hdir	dw	?		; directory handle
pathend	dw	?		; offset in path of a matching file's name
action	dw	?		; action taken by DosOpen
nbytes	dw	?		; # bytes read or written
files	dw	MAXFILES dup (?); offsets of file names
numbuf	db	6 dup (?)	; a number's digits, and a null
ffbuf	db	FFLEN dup (?)
tail	db	TAIL_MAX dup (?); the command tail
path	db	TAIL_MAX+13 dup (?); a matching file's path and name
line	db	LINE_MAX dup (?)
inbuf	db	INBUF_LEN dup (?)
_BSS	ends

STACK	segment	word stack 'STACK'
	dw	256 dup (?)
STACK	ends

DGROUP	group	_DATA,_BSS,STACK

CODE	segment word public 'CODE'

	ASSUME	CS:CODE, DS:DGROUP, ES:DGROUP, SS:DGROUP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; main
;
; An OS/2 program starts with DS and SS addressing its automatic data
; segment, AX = its environment's selector, and BX = the offset there of its
; command line: two strings (the program's name, and the command tail) and
; another null.  We copy the tail to our data segment, so that every pointer
; to it is a near one.
;
; Inputs:
;	AX:BX -> command line
;
DEFPROC	main,FAR
	push	ds
	pop	es
	mov	si,bx
	mov	ds,ax
	ASSUME	DS:NOTHING
m1:	lodsb				; skip the program's name
	test	al,al
	jnz	m1
	mov	di,offset DGROUP:tail
	mov	cx,TAIL_MAX-1
m2:	lodsb
	stosb
	test	al,al
	loopnz	m2
	mov	al,0
	stosb				; (in case the tail was too long)
	push	es
	pop	ds
	ASSUME	DS:DGROUP
	call	getArgs
	inc	[errcode]		; assume no lines will be selected
	sub	bx,bx
	cmp	[nfiles],bx		; any files?
	jne	m3			; yes
	call	findLines		; no, so read STDIN
	jmp	short exit
m3:	mov	[prefix],offset DGROUP:colon
m4:	push	bx
	mov	si,[files][bx]
	call	eachFile
	pop	bx
	inc	bx
	inc	bx
	cmp	bx,[nfiles]
	jb	m4
	DEFLBL	exit,near
	PCALL	DOSEXIT,1,[errcode]	; end the process
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getArgs
;
; Parses the command tail: each switch letter (eg, the 'V' in "/V") sets its
; variable, a quoted string is recorded in strptr and strlen, and every other
; argument is treated as a file name, which is null-terminated in place and
; recorded in files.  If no string was quoted, the first file name becomes
; the string instead (eg, "FIND16 BAS").
;
; An unknown switch, more than MAXFILES file names, or no string is a syntax
; error, which ends the program.
;
; Modifies:
;	AX, BX, CX, SI, DI
;
DEFPROC	getArgs
	mov	si,offset DGROUP:tail
ga1:	lodsb
	test	al,al			; end of the tail?
	jz	ga9			; yes
	cmp	al,' '			; whitespace (or other control char)?
	jbe	ga1			; yes
	cmp	al,SWCHAR		; switch char?
	je	ga3			; yes
	cmp	al,'"'			; quoted string?
	je	ga5			; yes
	lea	bx,[si-1]		; BX -> file name
	mov	di,[nfiles]
	cmp	di,MAXFILES*2		; room for another?
	jae	ga4			; no, so it's a syntax error
	mov	[files][di],bx
	inc	di
	inc	di
	mov	[nfiles],di
ga2:	lodsb
	cmp	al,' '
	ja	ga2
	mov	byte ptr [si-1],0	; null-terminate the file name
	test	al,al			; did it end the tail?
	jnz	ga1			; no
	jmp	short ga9
;
; Every character after the switch char, up to the next whitespace, must be
; in the list of switches.
;
ga3:	lodsb
	call	toUpper
	mov	di,offset DGROUP:swlist
	mov	cx,SW_LEN
	repne	scasb			; one of ours?
	jne	ga4			; no
	mov	byte ptr [di+SW_LEN-1],1; yes, so set its variable
	cmp	byte ptr [si],' '	; any more switch chars?
	ja	ga3			; yes
	jmp	ga1
ga4:	mov	dx,offset DGROUP:synerr
	call	putErr
	mov	[errcode],2
	jmp	exit

ga5:	mov	[strptr],si
ga6:	lodsb
	cmp	al,'"'			; end of quoted string?
	je	ga7			; yes
	test	al,al			; end of the tail?
	jnz	ga6			; no
ga7:	lea	bx,[si-1]
	sub	bx,[strptr]
	mov	[strlen],bx
	test	al,al			; did the string end with a quote?
	jnz	ga8			; yes
	dec	si			; no, so re-examine the null
ga8:	jmp	ga1

ga9:	cmp	[strptr],0		; was a string quoted?
	jne	ga10			; yes
	mov	cx,[nfiles]
	jcxz	ga4			; no, and there are no file names
	mov	di,offset DGROUP:files
	mov	si,[di]			; SI -> first file name
	mov	[strptr],si
	push	si
	lea	si,[di+2]
	dec	cx
	dec	cx
	mov	[nfiles],cx
	rep	movsb			; remove it from files
	pop	di
	mov	al,0
	dec	cx			; CX = -1
	repne	scasb
	not	cx
	dec	cx			; CX = length of the string
	mov	[strlen],cx
ga10:	ret
ENDPROC	getArgs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; eachFile
;
; Displays the matching lines of a file, or for a name with wildcards (? and
; *), of every file that DosFindFirst and DosFindNext find; each of those
; files' names replaces the name in a copy of the path.
;
; Inputs:
;	SI -> file name
;
; Modifies:
;	Any
;
DEFPROC	eachFile
	mov	di,si
	mov	bx,si			; BX -> the name, after any path
	mov	ah,0			; AH = 0 if no wildcards
ef1:	lodsb
	test	al,al
	jz	ef4
	cmp	al,'*'
	je	ef2
	cmp	al,'?'
	jne	ef3
ef2:	inc	ah
ef3:	cmp	al,'\'
	je	ef3a
	cmp	al,'/'
	je	ef3a
	cmp	al,':'
	jne	ef1
ef3a:	mov	bx,si			; the name starts after this char
	jmp	ef1
ef4:	mov	si,di			; SI -> file name
	test	ah,ah			; any wildcards?
	jnz	ef5			; yes
	jmp	doFile
ef5:	push	si
	mov	cx,bx
	sub	cx,si			; CX = length of the path
	mov	di,offset DGROUP:path
	rep	movsb			; copy the path
	mov	[pathend],di
	pop	si
	mov	[hdir],HDIR_CREATE
;
; DosFindFirst(file specification, directory handle, attributes (0 for
; normal files only), buffer, its size, # files to find and # found, 0).
;
	PCALL	DOSFINDFIRST,<ds,si>,ADDR,hdir,0,ADDR,ffbuf,FFLEN,ADDR,nfnd,0,0
	test	ax,ax
	jz	ef6
	jmp	openErr			; eg, no matching files
ef6:	mov	si,offset DGROUP:ffbuf+FF_NAME
	mov	di,[pathend]
ef7:	lodsb
	stosb
	test	al,al
	jnz	ef7
	mov	si,offset DGROUP:path
	call	doFile
	PCALL	DOSFINDNEXT,[hdir],ADDR,ffbuf,FFLEN,ADDR,nfnd
	test	ax,ax
	jz	ef6
	PCALL	DOSFINDCLOSE,[hdir]
	ret
ENDPROC	eachFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doFile
;
; Opens a file, displays its name and its matching lines, and closes it.
;
; Inputs:
;	SI -> file name
;
; Modifies:
;	Any
;
DEFPROC	doFile
;
; DosOpen(file name, handle, action taken, initial size, attributes, open
; flags, open mode, 0).
;
	PCALL	DOSOPEN,<ds,si>,ADDR,hin,ADDR,action,0,0,0,OFLAGS,OMODE,0,0
	test	ax,ax
	jnz	openErr
	mov	[inend],ax		; the input buffer is empty
	mov	dx,offset DGROUP:dashes
	call	putStr
	mov	dx,si
	call	putStr
	cmp	[swC],0			; displaying only counts?
	jne	df1			; yes, so the count completes the line
	mov	dx,offset DGROUP:crlf
	call	putStr
df1:	call	findLines
	PCALL	DOSCLOSE,[hin]
	ret
;
; Report an error (AX) for the file name at SI.
;
	DEFLBL	openErr,near
	mov	dx,offset DGROUP:drverr
	cmp	ax,ERROR_INVALID_DRIVE	; no such drive?
	je	oe2			; right (so no name is displayed)
	mov	dx,offset DGROUP:fnderr
	cmp	ax,ERROR_FILE_NOT_FOUND
	je	oe1
	cmp	ax,ERROR_PATH_NOT_FOUND
	je	oe1
	cmp	ax,ERROR_OPEN_FAILED	; (there's no file to open)
	je	oe1
	cmp	ax,ERROR_NO_MORE_FILES	; (no files match the wildcards)
	je	oe1
	mov	dx,offset DGROUP:operr
oe1:	call	putErr
	mov	dx,si
oe2:	call	putErr
	mov	dx,offset DGROUP:crlf
	call	putErr
	mov	[errcode],2
	ret
ENDPROC	doFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findLines
;
; Displays the lines of the input that contain the string (or with /V, those
; that don't), or with /C, their number.
;
; Modifies:
;	Any
;
DEFPROC	findLines
	sub	ax,ax
	mov	[nsel],ax
	mov	[lineno],ax
fl1:	call	readLine		; DX -> line, CX = length
	jc	fl8
	inc	[lineno]
	call	matchLine		; AL = 1 if match, 0 if not
	xor	al,[swV]		; invert the result if /V
	jz	fl1
	inc	[nsel]
	and	[errcode],2		; exit code 1 becomes 0
	cmp	[swC],0			; displaying only counts?
	jne	fl1			; yes
	cmp	[swN],0			; displaying line numbers?
	je	fl2			; no
	push	cx
	push	dx
	mov	dx,offset DGROUP:lbrack
	call	putStr
	mov	ax,[lineno]
	call	putNum
	mov	dx,offset DGROUP:rbrack
	call	putStr
	pop	dx
	pop	cx
fl2:	mov	bx,STDOUT
	call	write
	jmp	fl1
fl8:	cmp	[swC],0
	je	fl9
	mov	dx,[prefix]
	call	putStr
	mov	ax,[nsel]
	call	putNum
	mov	dx,offset DGROUP:crlf
	call	putStr
fl9:	ret
ENDPROC	findLines

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; matchLine
;
; Inputs:
;	DX -> line
;	CX = length
;
; Outputs:
;	AL = 1 if the line contains the string, 0 if not
;
; Modifies:
;	AX, BX, SI, DI
;
DEFPROC	matchLine
	push	cx
	mov	di,dx
	mov	bx,[strlen]
	sub	cx,bx			; CX = # positions to check, minus 1
	jb	ml8			; the line is too short
	inc	cx
ml1:	mov	si,[strptr]
	push	cx
	push	di
	mov	cx,bx
	jcxz	ml7			; an empty string always matches
ml2:	lodsb
	mov	ah,[di]
	inc	di
	cmp	[swI],0			; ignoring case?
	je	ml3			; no
	call	toUpper
	xchg	al,ah
	call	toUpper
ml3:	cmp	al,ah
	loope	ml2
	je	ml7			; match
	pop	di
	pop	cx
	inc	di			; advance to the next position
	loop	ml1
ml8:	mov	al,0
	pop	cx
	ret
ml7:	pop	di
	pop	cx
	pop	cx
	mov	al,1
	ret
ENDPROC	matchLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; readLine
;
; Reads the next line of input.  A line ends with LF, and a line without one
; (eg, the last line of a file, or a line longer than LINE_MAX) gets CR/LF
; appended, so every line ends with LF.
;
; Outputs:
;	If carry clear, DX -> line, CX = length
;	If carry set, there's no more input
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	readLine
	mov	di,offset DGROUP:line
	mov	dx,di
	mov	cx,LINE_MAX-2
rl1:	call	getc
	jc	rl7
	stosb
	cmp	al,10
	loopne	rl1
	je	rl9
	jmp	short rl8
rl7:	cmp	di,dx			; any chars at all?
	stc
	je	rl10			; no
rl8:	mov	ax,0A0Dh
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
; Outputs:
;	If carry clear, AL = next byte
;	If carry set, there's no more input
;
; Modifies:
;	AX, SI
;
DEFPROC	getc
	mov	si,[inpos]
	cmp	si,[inend]
	jb	gc1
	PCALL	DOSREAD,[hin],ADDR,inbuf,INBUF_LEN,ADDR,nbytes
	test	ax,ax
	jnz	gc8
	mov	si,offset DGROUP:inbuf
	mov	ax,[nbytes]
	test	ax,ax			; anything read?
	jz	gc8			; no
	add	ax,si
	mov	[inend],ax
gc1:	lodsb
	cmp	al,CTRLZ		; end of input?
	je	gc8			; yes
	mov	[inpos],si
	clc
	ret
gc8:	stc
	ret
ENDPROC	getc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putNum
;
; Inputs:
;	AX = number to write to STDOUT, in decimal
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	putNum
	mov	di,offset DGROUP:numbuf+5
	mov	byte ptr [di],0
	mov	bx,10
pn1:	sub	dx,dx
	div	bx			; DX = the next digit
	add	dl,'0'
	dec	di
	mov	[di],dl
	test	ax,ax			; any more?
	jnz	pn1			; yes
	mov	dx,di
;
; Fall into putStr.
;
ENDPROC	putNum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putStr and putErr
;
; Inputs:
;	DX -> null-terminated string to write to STDOUT (putStr) or STDERR
;	(putErr)
;
; Modifies:
;	AX, BX, CX
;
DEFPROC	putStr
	mov	bx,STDOUT
	jmp	short ps1
	DEFLBL	putErr,near
	mov	bx,STDERR
ps1:	push	di
	mov	di,dx
	mov	al,0
	mov	cx,-1
	repne	scasb
	not	cx
	dec	cx			; CX = length of the string
	pop	di
;
; Fall into write.
;
ENDPROC	putStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write
;
; If the write fails (eg, the command reading our output through a pipe has
; ended), there's no point in continuing, so we exit.
;
; Inputs:
;	BX = file handle
;	DX -> data to write
;	CX = length
;
; Modifies:
;	AX
;
DEFPROC	write
	PCALL	DOSWRITE,bx,<ds,dx>,cx,ADDR,nbytes
	test	ax,ax
	jnz	wr9
	ret
wr9:	jmp	exit
ENDPROC	write

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

CODE	ends

	ENDIF

	end	main
