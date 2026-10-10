;
; BASIC-DOS Find Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: FIND [-C] [-I] [-N] [-V] "string" [files...]
;
; Displays every line of input (or of the specified files) that contains
; "string".  -C displays only the number of lines, -I ignores case, -N adds
; line numbers, and -V selects lines that do NOT contain "string".  The exit
; code is 0 if any lines were selected, 1 if none, and 2 if an error occurred.
;
	include	util.inc

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	bp,ds:[PSP_HEAP]	; BP -> UTILVARS
	call	getArgs
	mov	si,offset NO_STRING
	cmp	[bp].UV_STR,0		; was a string specified?
	je	m8			; no
	inc	[bp].UV_ERR		; assume no lines will be selected
	mov	[bp].UV_PREFIX,offset COLON+2
	cmp	[bp].UV_NFILES,0	; any files?
	jne	m1			; yes
	call	findLines		; no, so read STDIN
	jmp	short m9

m1:	sub	di,di
	mov	[bp].UV_PREFIX,offset COLON
m2:	push	di
	mov	dx,[bp].UV_FILES[di]
	call	openFile
	jc	m3
	PRINTF	<13,10,"---------- %s">,dx
	CHKSW	'C'			; displaying only counts?
	jnz	m2a			; yes, so the count completes the line
	PRINTF	<13,10>
m2a:	call	findLines
	mov	bx,[bp].UV_HIN
	mov	ah,DOS_HDL_CLOSE
	int	21h
m3:	pop	di
	inc	di
	inc	di
	cmp	di,[bp].UV_NFILES
	jb	m2
	jmp	short m9

m8:	call	writeErr
	mov	[bp].UV_ERR,2
m9:	jmp	exit
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findLines
;
; Inputs:
;	BP -> UTILVARS
;
; Modifies:
;	Any
;
DEFPROC	findLines
	sub	ax,ax
	mov	[bp].UV_COUNT,ax
	mov	[bp].UV_LINENO,ax
fl1:	call	readLine		; DX -> line, CX = length
	jc	fl8
	inc	[bp].UV_LINENO
	call	matchLine		; AL = 1 if match, 0 if not
	xor	al,[bp].UV_SW+('V'-'A')	; invert the result if -V
	jz	fl1
	inc	[bp].UV_COUNT
	and	[bp].UV_ERR,2		; exit code 1 becomes 0
	CHKSW	'C'			; displaying only counts?
	jnz	fl1			; yes
	CHKSW	'N'			; displaying line numbers?
	jz	fl2			; no
	push	cx
	push	dx
	PRINTF	<"[%u]">,[bp].UV_LINENO
	pop	dx
	pop	cx
fl2:	call	writeOut
	jmp	fl1
fl8:	CHKSW	'C'
	jz	fl9
	PRINTF	<"%s%u",13,10>,[bp].UV_PREFIX,[bp].UV_COUNT
fl9:	ret
ENDPROC	findLines

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; matchLine
;
; Inputs:
;	BP -> UTILVARS
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
	mov	bx,[bp].UV_STRLEN
	sub	cx,bx			; CX = # positions to check, minus 1
	jb	ml8			; the line is too short
	inc	cx
ml1:	mov	si,[bp].UV_STR
	push	cx
	push	di
	mov	cx,bx
	jcxz	ml7			; an empty string always matches
ml2:	lodsb
	mov	ah,[di]
	inc	di
	CHKSW	'I'			; ignoring case?
	jz	ml3			; no
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

	include	utilproc.inc

NO_STRING	db	"Missing quoted string",13,10,0
COLON		db	": ",0

	COMHEAP	<size UTILVARS + STACK_LEN>

CODE	ENDS

	end	main
