;
; BASIC-DOS Translate Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: TR [-C] [-D] [-S] set1 [set2]
;
; Copies input to output, replacing each character in set1 with the matching
; character in set2 (whose last character repeats if set2 is shorter).  -D
; deletes the characters in set1 instead, -C uses every character NOT in set1
; (in ascending order), and -S squeezes each run of a character in the last
; set into one.  A set contains characters, ranges (eg, a-z), and escapes:
; \t (TAB), \n (LF), \r (CR), or \ before any other character (eg, \- or \\),
; and it must be quoted if it contains spaces (or starts with the switch char
; and a letter).  For example, "TR a-z A-Z" converts input to upper-case, and
; "TR -D \r" removes carriage returns.
; The exit code is 0, or 2 if no set (or only one, without -D or -S) was given.
;
	DOSFUNC equ 1
	DOSPSP equ 1
	include	macros.inc
	include	devapi.inc
	include	dosapi.inc

BUF_LEN		equ	512	; input/output buffer size
STACK_LEN	equ	256	; stack space above TRVARS

SW_S		equ	01h	; TV_SW bits (see SW_CHARS)
SW_D		equ	02h
SW_C		equ	04h

F_DEL		equ	01h	; FLAGS bits: delete this input character
F_SQZ		equ	02h	; squeeze runs of this output character

;
; The translation table (XLAT) and the table of FLAGS that follows it are
; page-aligned in TV_TABLES, so that with the page in BH and a character in
; BL, [BX] is its translation and [BX+256] is its flags.  Each set's length
; is stored in the word before it.
;
TRVARS		struc
TV_SW		db	?	; switches (SW_*)
TV_NSETS	db	?	; # sets specified
TV_PAGE		dw	?	; offset of XLAT (FLAGS follows it)
TV_LEN1		dw	?	; length of set1
TV_SET1		db	256 dup (?)
TV_LEN2		dw	?	; length of set2
TV_SET2		db	256 dup (?)
TV_BUF		db	BUF_LEN dup (?)
TV_TABLES	db	512+255 dup (?)
TRVARS		ends

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	bp,ds:[PSP_HEAP]	; BP -> TRVARS
	lea	ax,[bp].TV_TABLES+255
	mov	al,0
	mov	[bp].TV_PAGE,ax
	xchg	di,ax			; DI -> XLAT
	sub	ax,ax
	mov	cx,256
m1:	stosb				; each character translates to itself
	inc	ax
	loop	m1
	mov	ch,1			; CX = 256 (and AL = 0)
	rep	stosb			; and has no flags
;
; Parse the command tail for switches and sets.
;
	mov	ax,DOS_MSC_GETSWC
	int	21h
	mov	bl,dl			; BL = switch char
	mov	si,PSP_CMDTAIL+1
a1:	lodsb
	cmp	al,CHR_RETURN		; end of the tail?
	je	a9			; yes
	cmp	al,CHR_SPACE		; whitespace (or other control char)?
	jbe	a1			; yes
	cmp	al,bl			; switch char?
	jne	a1a			; no
	mov	ah,[si]
	and	ah,NOT 20h
	sub	ah,'A'
	cmp	ah,26			; followed by a letter?
	jb	a6			; yes (otherwise, it's a set)
a1a:	mov	bh,CHR_DQUOTE
	cmp	al,bh			; quoted set?
	je	a2			; yes
	mov	bh,0
	dec	si
a2:	mov	cx,256			; CX = capacity
	lea	di,[bp].TV_SET1
	cmp	[bp].TV_NSETS,1
	jb	a3
	lea	di,[bp].TV_SET2
	je	a3
	lea	di,[bp].TV_BUF+2	; ignore any additional sets
	sub	cx,cx
a3:	inc	[bp].TV_NSETS
	push	di
	call	expandSet
	pop	dx
	xchg	di,dx			; DI -> set, DX -> end of set
	sub	dx,di
	mov	[di-2],dx		; store the set's length
	cmp	byte ptr [si],CHR_DQUOTE; skip any closing quote
	jne	a1
	inc	si
	jmp	a1

a6:	lodsb				; consume switch letters
	and	al,NOT 20h		; upper-case it
	cmp	al,'A'			; a letter?
	jb	a8			; no
	cmp	al,'Z'
	ja	a8			; no
	mov	di,offset SW_CHARS
	mov	cx,3
	repne	scasb			; one of ours?
	jne	a6			; no
	mov	al,1
	shl	al,cl			; AL = SW_* bit
	or	[bp].TV_SW,al
	jmp	a6
a8:	dec	si			; re-examine the last char
	jmp	a1
;
; There must be a set1, and either a set2 or -D or -S.
;
a9:	mov	cx,[bp].TV_LEN1
	jcxz	a10
	test	[bp].TV_SW,SW_D OR SW_S
	jnz	b1
	cmp	[bp].TV_LEN2,0
	jne	b1
a10:	mov	dx,offset NO_SET
	mov	cx,NO_SET_LEN
	mov	bx,STDERR
	mov	ah,DOS_HDL_WRITE
	int	21h
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 2
	int	21h
;
; Mark the characters in set1 (F_DEL), and if -C, replace set1 with all the
; characters that weren't marked (and mark them instead).
;
b1:	mov	bx,[bp].TV_PAGE
	inc	bh			; BH = FLAGS page
	lea	si,[bp].TV_SET1		; CX = length of set1
	mov	dl,F_DEL
	call	markSet
	test	[bp].TV_SW,SW_C
	jz	b3
	lea	di,[bp].TV_SET1
	mov	bl,0
b2:	xor	byte ptr [bx],F_DEL
	jz	b2a
	mov	al,bl
	stosb
b2a:	inc	bl
	jnz	b2
	lea	ax,[bp].TV_SET1
	sub	di,ax
	mov	[bp].TV_LEN1,di
;
; Unless -D, translate set1 to set2 (if any), and clear the F_DEL marks.
;
b3:	test	[bp].TV_SW,SW_D
	jnz	b5
	dec	bh			; BH = XLAT page
	mov	cx,[bp].TV_LEN1
	mov	dx,[bp].TV_LEN2
	lea	si,[bp].TV_SET1
	lea	di,[bp].TV_SET2
	test	dx,dx			; is there a set2?
	jz	b4b			; no
	jcxz	b4b			; (set1 can be empty after -C)
b4:	lodsb
	mov	bl,al
	mov	al,[di]
	mov	[bx],al			; XLAT[set1 char] = set2 char
	cmp	dx,1			; at the last char of set2?
	jbe	b4a			; yes, so keep using it
	dec	dx
	inc	di
b4a:	loop	b4
b4b:	inc	bh			; BH = FLAGS page
	mov	bl,0
	mov	di,bx
	mov	cx,256
	sub	ax,ax
	rep	stosb
;
; If -S, mark the characters in the last set (F_SQZ).
;
b5:	test	[bp].TV_SW,SW_S
	jz	b6
	lea	si,[bp].TV_SET1
	mov	cx,[bp].TV_LEN1
	cmp	[bp].TV_LEN2,0
	je	b5a
	lea	si,[bp].TV_SET2
	mov	cx,[bp].TV_LEN2
b5a:	mov	dl,F_SQZ
	call	markSet
;
; Translate the input, in place, a buffer at a time, with the XLAT page in BH
; and the last character written (if any) in DX.
;
b6:	mov	bx,[bp].TV_PAGE
	sub	dx,dx
m2:	lea	si,[bp].TV_BUF
	push	dx
	push	bx
	mov	dx,si
	mov	cx,BUF_LEN
	mov	bx,STDIN
	mov	ah,DOS_HDL_READ
	int	21h
	pop	bx
	pop	dx
	jc	m9
	xchg	cx,ax			; CX = # bytes read
	jcxz	m9			; no more input
	mov	di,si
m3:	lodsb
	cmp	al,CHR_CTRLZ		; end of input?
	je	m6			; yes (with CX non-zero)
	mov	bl,al
	test	byte ptr [bx+256],F_DEL	; delete it?
	jnz	m5			; yes
	mov	bl,[bx]			; BL = translated char
	test	byte ptr [bx+256],F_SQZ	; squeezing it?
	jz	m4			; no
	cmp	bx,dx			; same as the last char written?
	je	m5			; yes
m4:	mov	dx,bx
	mov	al,bl
	stosb
m5:	loop	m3
m6:	push	cx
	push	dx
	push	bx
	lea	dx,[bp].TV_BUF
	mov	cx,di
	sub	cx,dx			; CX = # bytes to write
	jcxz	m7
	mov	bx,STDOUT
	mov	ah,DOS_HDL_WRITE
	int	21h
m7:	pop	bx
	pop	dx
	pop	cx
	jc	m9			; the write failed
	jcxz	m2			; more input, unless CTRL-Z ended it
m9:	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; expandSet
;
; Inputs:
;	SI -> set (after any opening quote)
;	BH = CHR_DQUOTE if the set is quoted, 0 if not
;	DI -> buffer
;	CX = capacity of buffer
;
; Outputs:
;	DI -> end of set in buffer
;	SI -> the character that ended the set
;
; Modifies:
;	AX, CX, DI, SI
;
DEFPROC	expandSet
es1:	call	getChar
	jc	es9
	cmp	byte ptr [si],'-'	; a range?
	jne	es3			; no
	mov	ah,al			; AH = first char
	inc	si
	call	getChar			; AL = last char
	jc	es2			; there isn't one
	cmp	ah,al			; is the range backwards?
	ja	es1			; yes, so ignore it
	xchg	al,ah
es4:	call	putChar
	cmp	al,ah
	je	es1
	inc	ax
	jmp	es4
es2:	mov	al,ah			; a trailing '-' is itself
	call	putChar
	mov	al,'-'
es3:	call	putChar
	jmp	es1
es9:	ret
ENDPROC	expandSet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putChar
;
; Inputs:
;	AL = character
;	DI -> buffer
;	CX = capacity remaining (the character is dropped if zero)
;
; Modifies:
;	CX, DI
;
DEFPROC	putChar
	jcxz	pc9
	stosb
	dec	cx
pc9:	ret
ENDPROC	putChar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getChar
;
; Inputs:
;	SI -> next character of set
;	BH = CHR_DQUOTE if the set is quoted, 0 if not
;
; Outputs:
;	If carry clear, AL = next character (with any escape decoded)
;	If carry set, the set has ended (and SI -> the character that ended it)
;
; Modifies:
;	AL, SI
;
DEFPROC	getChar
	lodsb
	call	isEnd
	jc	gc8
	cmp	al,'\'			; escape?
	jne	gc7			; no
	lodsb
	call	isEnd
	jc	gc6
	cmp	al,'t'
	jne	gc1
	mov	al,CHR_TAB
gc1:	cmp	al,'n'
	jne	gc2
	mov	al,CHR_LINEFEED
gc2:	cmp	al,'r'
	jne	gc7
	mov	al,CHR_RETURN
gc7:	clc
	ret
gc6:	dec	si			; a trailing '\' is itself
	mov	al,'\'
	jmp	gc7
gc8:	dec	si			; (carry is still set)
	ret
ENDPROC	getChar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; isEnd
;
; Inputs:
;	AL = character
;	BH = CHR_DQUOTE if the set is quoted, 0 if not
;
; Outputs:
;	Carry set if the character ends the set: the end of the tail, the
;	closing quote of a quoted set, or a space (or other control char) after
;	an unquoted set
;
DEFPROC	isEnd
	cmp	al,CHR_RETURN
	je	ie8
	test	bh,bh
	jnz	ie1
	cmp	al,CHR_SPACE+1		; carry set if AL <= space
	ret
ie1:	cmp	al,bh
	clc
	jne	ie9
ie8:	stc
ie9:	ret
ENDPROC	isEnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; markSet
;
; Inputs:
;	SI -> set
;	CX = length of set
;	BH = FLAGS page
;	DL = flags to set for each character in the set
;
; Modifies:
;	AL, BL, CX, SI
;
DEFPROC	markSet
	jcxz	ms9
ms1:	lodsb
	mov	bl,al
	or	[bx],dl
	loop	ms1
ms9:	ret
ENDPROC	markSet

SW_CHARS	db	"CDS"
NO_SET		db	"Missing character set",13,10
NO_SET_LEN	equ	$ - NO_SET

	COMHEAP	<size TRVARS + STACK_LEN>

CODE	ENDS

	end	main
