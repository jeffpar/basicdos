;
; BASIC-DOS More Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: MORE [file]
;
; Displays input (or the specified file) one screen at a time.  After each
; screen, "-- More --" is displayed, and a key is read from STDERR (since
; STDIN is usually a pipe); press any key to continue, or CTRL-C to stop.
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
	jc	m9
;
; Get the console dimensions (DL = cols, DH = rows).
;
m1:	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDIM
	mov	bx,STDOUT
	int	21h
	jnc	m2
	mov	dx,(25 SHL 8) OR 80	; STDOUT doesn't support GETDIM
m2:	dec	dh			; leave the last row for the prompt
	mov	word ptr [bp].UV_COLS,dx; and UV_ROWS

m3:	call	readLine		; DX -> line, CX = length
	jc	m9
	call	countRows		; AL = # rows the line will occupy
	add	al,[bp].UV_USED
	cmp	al,[bp].UV_ROWS		; will it fit on this page?
	jbe	m4			; yes
	push	cx
	push	dx
	call	waitKey
	pop	dx
	pop	cx
	call	countRows		; it will start the new page
m4:	mov	[bp].UV_USED,al
	call	writeOut
	jmp	m3

m9:	jmp	exit
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; countRows
;
; Calculates the number of console rows a line will occupy, assuming that
; output wraps at the last column and that tabs stop every 8 columns.
;
; Inputs:
;	BP -> UTILVARS
;	DX -> line
;	CX = length
;
; Outputs:
;	AL = # rows
;
; Modifies:
;	AX, BX, SI
;
DEFPROC	countRows
	push	cx
	mov	si,dx
	sub	bx,bx			; BL = column, BH = extra rows
cr1:	lodsb
	cmp	al,CHR_RETURN		; end of the line?
	je	cr9			; yes
	cmp	al,CHR_LINEFEED
	je	cr9
	cmp	al,CHR_TAB
	jne	cr2
	or	bl,7			; advance to the next tab stop
cr2:	inc	bx
	cmp	bl,[bp].UV_COLS		; past the last column?
	jb	cr3			; no
	sub	bl,[bp].UV_COLS		; yes, so wrap
	inc	bh
cr3:	loop	cr1
cr9:	mov	al,bh
	inc	ax			; AL = # rows
	pop	cx
	ret
ENDPROC	countRows

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; waitKey
;
; Displays the prompt, waits for a key, and then erases the prompt.
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	waitKey
	mov	dx,offset MORE_MSG
	mov	cx,MORE_LEN
	call	writeOut
	push	ax
	mov	dx,sp
	mov	cx,1
	mov	bx,STDERR
	mov	ah,DOS_HDL_READ
	int	21h
	pop	ax
	mov	dx,offset ERASE_MSG
	mov	cx,ERASE_LEN
	jmp	writeOut
ENDPROC	waitKey

MORE_MSG	db	"-- More --"
MORE_LEN	equ	$ - MORE_MSG
ERASE_MSG	db	13,"          ",13
ERASE_LEN	equ	$ - ERASE_MSG

	include	utilproc.inc

	COMHEAP	<size UTILVARS + STACK_LEN>

CODE	ENDS

	end	main
