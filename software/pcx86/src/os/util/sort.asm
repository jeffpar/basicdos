;
; BASIC-DOS Sort Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: SORT [-R] [-+n] [file]
;
; Sorts lines of input (or of the specified file), ignoring case, and writes
; them to STDOUT.  -R sorts in reverse order, and -+n sorts on the characters
; starting at column n.  Up to 64K of input can be sorted.
;
; Lines are stored in a separate segment: their text grows up from offset 0,
; and an array of line offsets grows down from the top, and when the two
; meet, we're out of memory.  The offsets are then sorted with a Shell sort.
;
	include	util.inc

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	bp,ds:[PSP_HEAP]	; BP -> UTILVARS
	call	getArgs
	cmp	[bp].UV_NFILES,0	; was a file specified?
	je	m1			; no
	mov	dx,[bp].UV_FILES
	call	openFile
	jnc	m1
	jmp	exit
;
; Allocate up to 0FFFh paragraphs (just shy of 64K) for line storage.
;
m1:	mov	bx,0FFFh
	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h
	jnc	m2
	test	bx,bx			; BX = max paragraphs available
	jz	m8
	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h
	jc	m8
m2:	mov	[bp].UV_SEG,ax
	mov	cl,4
	shl	bx,cl
	dec	bx
	dec	bx
	mov	[bp].UV_PTRS,bx		; offset of the first line pointer
;
; Read all the lines.
;
m3:	call	readLine		; DX -> line, CX = length
	jc	m4
	mov	es,[bp].UV_SEG
	mov	di,[bp].UV_TEXT
	mov	bx,[bp].UV_PTRS
	mov	ax,di
	add	ax,cx			; AX = end of line text
	cmp	ax,bx			; does it overlap the line pointer?
	ja	m8			; yes
	mov	es:[bx],di
	dec	bx
	dec	bx
	mov	[bp].UV_PTRS,bx
	mov	si,dx
	rep	movsb
	mov	[bp].UV_TEXT,di
	add	[bp].UV_COUNT,2
	jmp	m3
;
; Shell sort the line pointers, which start at UV_PTRS+2 (BX), and then
; write the lines in order.
;
m4:	call	sortLines
	mov	cx,[bp].UV_COUNT
	shr	cx,1
	jcxz	m9
	mov	bx,[bp].UV_PTRS
m5:	inc	bx
	inc	bx
	mov	di,es:[bx]
	mov	dx,di			; DX -> line
	push	cx
	mov	al,CHR_LINEFEED
	mov	cx,LINE_MAX
	repne	scasb			; every line ends with LF
	mov	cx,di
	sub	cx,dx			; CX = length
	push	bx
	push	ds
	push	es
	pop	ds
	call	writeOut
	pop	ds
	pop	bx
	pop	cx
	loop	m5
	jmp	short m9

m8:	mov	si,offset NO_MEMORY
	call	writeErr
	mov	[bp].UV_ERR,1
m9:	jmp	exit
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sortLines
;
; Inputs:
;	BP -> UTILVARS
;
; Outputs:
;	ES = UV_SEG, and the line pointers above UV_PTRS are sorted
;
; Modifies:
;	Any except ES
;
DEFPROC	sortLines
	mov	es,[bp].UV_SEG
	mov	ax,[bp].UV_COUNT	; AX = # lines * 2
sl1:	shr	ax,1
	and	ax,NOT 1		; AX = gap, in bytes (always even)
	jz	sl9
	mov	[bp].UV_GAP,ax
	mov	cx,ax			; CX = index i, in bytes
sl2:	cmp	cx,[bp].UV_COUNT
	jae	sl8
	mov	bx,[bp].UV_PTRS
	inc	bx
	inc	bx
	add	bx,cx			; BX -> line pointer i (and j)
	mov	dx,es:[bx]		; DX = line pointer i
sl3:	mov	di,bx
	sub	di,[bp].UV_GAP		; DI -> line pointer j-gap
	cmp	di,[bp].UV_PTRS		; is j < gap?
	jbe	sl4			; yes
	push	cx
	push	di
	mov	si,es:[di]
	mov	di,dx
	call	compare			; is line j-gap > line i?
	pop	di
	pop	cx
	jbe	sl4			; no
	mov	ax,es:[di]
	mov	es:[bx],ax		; move line pointer j-gap up to j
	mov	bx,di
	jmp	sl3
sl4:	mov	es:[bx],dx		; store line pointer i at j
	inc	cx
	inc	cx
	jmp	sl2
sl8:	mov	ax,[bp].UV_GAP
	jmp	sl1
sl9:	ret
ENDPROC	sortLines

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; compare
;
; Compares two lines (ignoring case), starting at column UV_COL, and in
; reverse if -R.
;
; Inputs:
;	BP -> UTILVARS
;	ES:SI -> 1st line
;	ES:DI -> 2nd line
;
; Outputs:
;	Flags set as if the 1st line was compared to the 2nd (eg, JA if the
;	1st line sorts after the 2nd)
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	compare
	CHKSW	'R'
	jz	cp1
	xchg	si,di
cp1:	call	skipCol
	xchg	si,di
	call	skipCol
	xchg	si,di
cp2:	mov	al,es:[di]
	call	toUpper
	mov	ah,al
	lods	byte ptr es:[si]
	call	toUpper
	inc	di
	cmp	al,ah
	jne	cp9
	cmp	al,CHR_LINEFEED		; every line ends with LF
	jne	cp2
cp9:	ret
ENDPROC	compare

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; skipCol
;
; Inputs:
;	BP -> UTILVARS
;	ES:SI -> line
;
; Outputs:
;	SI advanced to column UV_COL (or to the end of the line)
;
; Modifies:
;	CX, SI
;
DEFPROC	skipCol
	mov	cx,[bp].UV_COL
	jcxz	sc9
sc1:	dec	cx			; columns start at 1
	jz	sc9
	cmp	byte ptr es:[si],CHR_RETURN
	je	sc9
	cmp	byte ptr es:[si],CHR_LINEFEED
	je	sc9
	inc	si
	jmp	sc1
sc9:	ret
ENDPROC	skipCol

	include	utilproc.inc

NO_MEMORY	db	"Insufficient memory",13,10,0

	COMHEAP	<size UTILVARS + STACK_LEN>

CODE	ENDS

	end	main
