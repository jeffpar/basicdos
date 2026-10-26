;
; BASIC-DOS Unique Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: UNIQ [-C] [-D] [-I] [-U] [file]
;
; Copies input (or the specified file) to STDOUT, writing each run of identical
; lines only once.  -C puts the number of times each line occurred in front of
; it, -D writes only the lines that were repeated, -U only the lines that
; weren't, and -I ignores case.  Since only adjacent lines are compared, input
; is usually sorted first (eg, "SORT NAMES.TXT | UNIQ").  The exit code is 0,
; or 2 if the file couldn't be opened.
;
	include	utilvars.inc

UNIQVARS	struc
UQ_UV		db	size UTILVARS dup (?)
UQ_COUNT	dd	?	; # times the saved line occurred
UQ_LEN		dw	?	; length of the saved line
UQ_LINE		db	LINE_MAX dup (?)
UNIQVARS	ends

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	bp,ds:[PSP_HEAP]	; BP -> UNIQVARS
	call	getArgs
	cmp	[bp].UV_NFILES,0	; was a file specified?
	je	m1			; no
	mov	dx,[bp].UV_FILES
	call	openFile
	jc	m9
m1:	call	readLine		; DX -> line, CX = length
	jc	m9			; no input
;
; Save the line that starts a new run.
;
m2:	lea	di,[bp].UQ_LINE
	mov	[bp].UQ_LEN,cx
	mov	si,dx
	rep	movsb			; (readLine set ES to DS)
	mov	word ptr [bp].UQ_COUNT,1
	mov	word ptr [bp].UQ_COUNT+2,cx
;
; Compare each line that follows to the saved line, counting the duplicates.
;
m3:	call	readLine
	jc	m8
	cmp	cx,[bp].UQ_LEN		; same length as the saved line?
	jne	m6			; no
	push	cx
	mov	si,dx
	lea	di,[bp].UQ_LINE
m4:	lodsb
	mov	ah,[di]
	inc	di
	CHKSW	'I'			; ignoring case?
	jz	m5			; no
	call	toUpper
	xchg	al,ah
	call	toUpper
m5:	cmp	al,ah
	loope	m4
	pop	cx
	jne	m6
	add	word ptr [bp].UQ_COUNT,1
	adc	word ptr [bp].UQ_COUNT+2,0
	jmp	m3
m6:	push	cx
	push	dx
	call	putRun
	pop	dx
	pop	cx
	jmp	m2
m8:	call	putRun
m9:	jmp	exit
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putRun
;
; Writes the saved line (unless -D or -U skips it), after its count if -C.
;
; Inputs:
;	BP -> UNIQVARS
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	putRun
	mov	si,'D'-'A'		; -D skips a line that occurred once
	mov	ax,word ptr [bp].UQ_COUNT
	dec	ax
	or	ax,word ptr [bp].UQ_COUNT+2
	jz	pr1			; it occurred once
	mov	si,'U'-'A'		; -U skips a line that was repeated
pr1:	cmp	[bp].UV_SW[si],0	; skipping it?
	jne	pr9			; yes
	CHKSW	'C'			; displaying the count?
	jz	pr2			; no
	PRINTF	<"%7lu ">,[bp].UQ_COUNT,:2
pr2:	lea	dx,[bp].UQ_LINE
	mov	cx,[bp].UQ_LEN
	jmp	writeOut
pr9:	ret
ENDPROC	putRun

	include	utilproc.inc
;
; PRINTF puts its buffer on our stack, so we need more than STACK_LEN.
;
	COMHEAP	<size UNIQVARS + STACK_LEN + 256>

CODE	ENDS

	end	main
