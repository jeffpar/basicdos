;
; BASIC-DOS Tee Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: TEE [-A] file
;
; Copies input to STDOUT and to the specified file, which is replaced, or
; with -A, appended to (or created, if it doesn't exist).  The exit code is 0,
; or 2 if the file couldn't be opened or written.
;
	include	util.inc

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	bp,ds:[PSP_HEAP]	; BP -> UTILVARS
	call	getArgs
	mov	si,offset NO_FILE
	cmp	[bp].UV_NFILES,0	; was a file specified?
	je	m8			; no
	mov	dx,[bp].UV_FILES	; DX -> file name
	mov	ax,DOS_HDL_OPENWO
	CHKSW	'A'			; appending?
	jz	m1			; no
	int	21h			; so try opening an existing file
	jnc	m2			; and if that fails, create it
m1:	sub	cx,cx			; CX = attributes (none)
	mov	ah,DOS_HDL_CREATE
	int	21h
	mov	si,offset OPEN_ERR
	jc	m7
m2:	xchg	si,ax			; SI = file handle
	mov	bx,si
	sub	cx,cx
	sub	dx,dx
	mov	ax,DOS_HDL_SEEKEND
	int	21h			; seek to the end (of an appended file)

m3:	lea	dx,[bp].UV_INBUF
	mov	cx,INBUF_LEN
	mov	bx,STDIN
	mov	ah,DOS_HDL_READ
	int	21h
	jc	m9
	xchg	cx,ax			; CX = # bytes read
	jcxz	m9			; no more input
	mov	di,dx
	mov	al,CHR_CTRLZ
	repne	scasb			; CTRL-Z ends input
	mov	cx,di
	jne	m4			; no CTRL-Z
	dec	cx			; exclude the CTRL-Z
	sub	di,di			; DI = 0 (end of input)
m4:	sub	cx,dx			; CX = # bytes to write
	call	writeOut
	mov	bx,si
	mov	ah,DOS_HDL_WRITE
	int	21h
	jc	m6
	cmp	ax,cx			; was everything written (eg, disk full)?
	jb	m6			; no
	test	di,di			; end of input?
	jnz	m3			; no
m9:	jmp	exit

m6:	mov	si,offset WRITE_ERR
m7:	call	writeErr
	mov	si,[bp].UV_FILES
	call	writeErr
	mov	si,offset CRLF
m8:	call	writeErr
	mov	[bp].UV_ERR,2
	jmp	m9
ENDPROC	main

	include	utilproc.inc

NO_FILE		db	"Missing file name",13,10,0
WRITE_ERR	db	"Unable to write ",0

	COMHEAP	<size UTILVARS + STACK_LEN>

CODE	ENDS

	end	main
