;
; BASIC-DOS Word Count Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: WC [-B] [-L] [-W] [-C] [files...]
;
; Displays the number of lines, words, and bytes of input (or of each of the
; specified files, which may include wildcards, followed by their totals if
; there's more than one).  -L, -W, and -C display only the selected counts.
; Lines are counted by their LFs, and words are separated by spaces and control
; characters (eg, TAB, CR, and LF).  The exit code is 0, or 2 if a file
; couldn't be opened.
;
; -B counts only BASIC code: a line counts if it contains anything besides
; whitespace, a line number, and a comment (REM or '), and only its bytes and
; words before the comment (minus trailing whitespace and colons, but plus the
; CR/LF) are counted.
;
	UTILWALK equ 1
	include	utilvars.inc

CNT_LINES	equ	0	; offsets of the 32-bit counts in UV_CNTS
CNT_WORDS	equ	4
CNT_BYTES	equ	8
CNT_PEND	equ	12	; 16-bit pending word count (see pend)
CNT_TOTALS	equ	14	; followed by the totals, in the same order

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	bp,ds:[PSP_HEAP]	; BP -> UTILVARS
	call	getArgs
;
; If none of -L, -W, and -C were specified, display all three counts.
;
	mov	al,[bp].UV_SW+('L'-'A')
	or	al,[bp].UV_SW+('W'-'A')
	or	al,[bp].UV_SW+('C'-'A')
	jnz	m1
	inc	[bp].UV_SW+('L'-'A')
	inc	[bp].UV_SW+('W'-'A')
	inc	[bp].UV_SW+('C'-'A')
m1:	sub	dx,dx			; DX = 0 (no name to display)
	cmp	[bp].UV_NFILES,0	; any files?
	jne	m2			; yes
	call	countFile		; no, so read STDIN
	jmp	short m9

m2:	mov	cx,offset wcFile
	call	eachFile
	cmp	[bp].UV_COUNT,1		; more than one file counted?
	jbe	m9			; no
	lea	bx,[bp].UV_CNTS+CNT_TOTALS
	mov	dx,offset TOTAL
	call	printCounts
m9:	jmp	exit
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; wcFile
;
; Counts the files (for eachFile), so that main knows whether to display the
; totals.
;
; Inputs:
;	BP -> UTILVARS
;	DX -> name to display
;
DEFPROC	wcFile
	inc	[bp].UV_COUNT
;
; Fall into countFile.
;
ENDPROC	wcFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; countFile
;
; Counts the lines, words, and bytes of input, adds them to the totals, and
; displays them.
;
; Each byte goes to the handler for the current state (DI), and the state for
; the start of a line is on the stack: either cf15, which counts every byte,
; or for -B, cf2.  Bytes (CX) and words that might not be code (eg, a line
; number or trailing spaces) are pending (see pend) until code follows (see
; commit), and are discarded at the end of the line.
;
; Inputs:
;	BP -> UTILVARS
;	DX -> name to display (0 if none)
;
; Modifies:
;	AX, BX, CX, SI, DI
;
DEFPROC	countFile
	push	dx
	lea	di,[bp].UV_CNTS
	mov	bx,di			; BX -> counts
	mov	cx,CNT_TOTALS/2
	sub	ax,ax
	rep	stosw			; zero the counts (and CX)
	mov	ax,offset cf15
	CHKSW	'B'			; counting only code?
	jz	cf1			; no
	mov	ax,offset cf2
cf1:	push	ax			; save the line start state
	jmp	short cf13
;
; At the start of a line, any line number and whitespace are pending.
;
cf2:	cmp	al,'0'			; line number digit?
	jb	cf3			; no
	cmp	al,'9'
	jbe	cf12			; yes
;
; At the start of a statement, check for a comment (' or REM).
;
cf3:	cmp	al,CHR_SPACE		; whitespace (or other control char)?
	jbe	cf11			; yes
	call	toUpper
	mov	di,offset cf7
	cmp	al,'R'			; possibly REM?
	je	cf12			; yes
cf4:	mov	di,offset cf5
;
; In code, check for a comment, the end of the statement, or a string.
;
cf5:	cmp	al,CHR_SPACE		; whitespace (or other control char)?
	jbe	cf11			; yes
	cmp	al,"'"			; comment?
	je	cf9			; yes
	cmp	al,':'			; end of the statement?
	jne	cf5a			; no
	mov	di,offset cf3
	jmp	short cf12		; (a trailing colon isn't counted)
cf5a:	cmp	al,CHR_DQUOTE		; start of a string?
	jne	cf6a			; no
	mov	di,offset cf6
	jmp	short cf6a
cf6:	cmp	al,CHR_SPACE		; whitespace (or other control char)?
	jbe	cf11			; yes
	cmp	al,CHR_DQUOTE		; end of the string?
	jne	cf6a			; no
	mov	di,offset cf5
cf6a:	call	pendCode
	jmp	short cf14
;
; After an R (and then an E) at the start of a statement, check for REM.
;
cf7:	call	toUpper
	cmp	al,'E'			; still possibly REM?
	jne	cf8a			; no
	mov	di,offset cf8
	jmp	short cf12
cf8:	call	toUpper
	cmp	al,'M'			; REM?
	je	cf9			; yes
cf8a:	call	commit			; no, so the pending bytes are code
	jmp	cf4
;
; In a comment, only CR and LF matter (the end of the line discards any
; pending whitespace).
;
cf9:	mov	di,offset cf10
cf10:	cmp	al,CHR_SPACE		; whitespace (or other control char)?
	ja	cf14			; no
cf11:	cmp	al,CHR_RETURN		; CR?
	je	cf16			; yes
	cmp	al,CHR_LINEFEED		; LF?
	je	cf16			; yes
cf12:	call	pend
	jmp	short cf14

cf13:	pop	di			; DI = state for the start of a line
	push	di
	cwd				; DX = 0 (no code, not in a word)
cf14:	call	getc			; AL = next byte
	jc	cf18
	jmp	di
;
; Without -B, every byte is code.
;
cf15:	mov	dh,1
;
; At CR or LF (or any byte without -B), discard the pending counts, and if the
; line contains code, count the byte, and at LF, the line.
;
cf16:	sub	cx,cx
	mov	[bx+CNT_PEND],cx
	test	dh,dh			; any code on this line?
	jz	cf17			; no
	call	pendCode
	cmp	al,CHR_LINEFEED		; end of a line?
	jne	cf14			; no
	add	word ptr [bx+CNT_LINES],1
	adc	word ptr [bx+CNT_LINES+2],0
cf17:	cmp	al,CHR_LINEFEED		; end of a line?
	je	cf13			; yes
	jmp	cf14

cf18:	pop	ax			; discard the line state
	mov	si,bx
	mov	cx,3
cf19:	lodsw
	add	[si+CNT_TOTALS-2],ax
	lodsw
	adc	[si+CNT_TOTALS-2],ax
	loop	cf19
	pop	dx
;
; Fall into printCounts with BX -> counts.
;
ENDPROC	countFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printCounts
;
; Inputs:
;	BP -> UTILVARS
;	BX -> counts (lines, words, and bytes)
;	DX -> name to display (0 if none)
;
; Modifies:
;	AX, BX, SI, DI
;
DEFPROC	printCounts
	mov	si,offset SWITCHES
pc1:	lodsb
	cbw
	xchg	di,ax			; DI = index of the count's switch
	cmp	[bp].UV_SW[di],0	; display this count?
	je	pc2			; no
	PRINTF	<"%8lu">,[bx],:2
pc2:	add	bx,4
	cmp	si,offset SWITCHES+3
	jb	pc1
	test	dx,dx			; any name?
	jz	pc8			; no
	PRINTF	<" %s">,dx
pc8:	PRINTF	<13,10>
	ret
ENDPROC	printCounts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pendCode
;
; Adds a byte of code to the pending counts, and falls into commit.
;
; Inputs:
;	AL = byte
;	BX -> counts
;	CX = # pending bytes
;	DL = non-zero if in a word
;
; Outputs:
;	CX = 0 (no pending bytes)
;	DH = 1 (the line contains code)
;	DL updated
;
; Modifies:
;	SI
;
DEFPROC	pendCode
	call	pend
;
; Fall into commit.
;
ENDPROC	pendCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; commit
;
; Moves the pending counts to the word and byte counts.
;
; Inputs:
;	BX -> counts
;	CX = # pending bytes
;
; Outputs:
;	CX = 0 (no pending bytes)
;	DH = 1 (the line contains code)
;
; Modifies:
;	SI
;
DEFPROC	commit
	mov	dh,1
	sub	si,si
	xchg	si,[bx+CNT_PEND]
	add	[bx+CNT_WORDS],si
	adc	word ptr [bx+CNT_WORDS+2],0
	add	[bx+CNT_BYTES],cx
	adc	word ptr [bx+CNT_BYTES+2],0
	sub	cx,cx
	ret
ENDPROC	commit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pend
;
; Adds a byte to the pending counts: the byte count, and the word count if
; the byte starts a word.
;
; Inputs:
;	AL = byte
;	BX -> counts
;	CX = # pending bytes
;	DL = non-zero if in a word
;
; Outputs:
;	CX and DL updated
;
DEFPROC	pend
	inc	cx
	cmp	al,CHR_SPACE		; whitespace (or other control char)?
	ja	pd1			; no
	mov	dl,0			; DL = 0 (not in a word)
	ret
pd1:	test	dl,dl			; already in a word?
	jnz	pd9			; yes
	inc	dx			; DL = 1 (in a word)
	inc	word ptr [bx+CNT_PEND]
pd9:	ret
ENDPROC	pend

SW_LIST	db	"BCLW"
SW_LEN	equ	$ - SW_LIST

	include	utilproc.inc

SWITCHES	db	'L'-'A','W'-'A','C'-'A'
TOTAL		db	"total",0

	COMHEAP	<size UTILVARS + STACK_LEN>

CODE	ENDS

	end	main
