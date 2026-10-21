;
; BASIC-DOS Word Count Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: WC [-L] [-W] [-C] [files...]
;
; Displays the number of lines, words, and bytes of input (or of each of the
; specified files, which may include wildcards, followed by their totals if
; there's more than one).  -L, -W, and -C display only the selected counts.
; Lines are counted by their LFs, and words are separated by spaces and control
; characters (eg, TAB, CR, and LF).  The exit code is 0, or 2 if a file
; couldn't be opened.
;
	UTILWALK equ 1
	include	utilvars.inc

CNT_LINES	equ	0	; offsets of the 32-bit counts in UV_CNTS
CNT_WORDS	equ	4
CNT_BYTES	equ	8
CNT_TOTALS	equ	12	; followed by the totals, in the same order

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
	mov	cx,6
	sub	ax,ax
	rep	stosw			; zero the counts (and CX)
	cwd				; DX = 0 (not in a word)
cf1:	call	getc			; AL = next byte
	jc	cf8
	add	word ptr [bx+CNT_BYTES],1
	adc	word ptr [bx+CNT_BYTES+2],0
	cmp	al,CHR_LINEFEED		; end of a line?
	jne	cf2			; no
	add	word ptr [bx+CNT_LINES],1
	adc	word ptr [bx+CNT_LINES+2],0
cf2:	cmp	al,CHR_SPACE		; whitespace (or other control char)?
	ja	cf3			; no
	sub	dx,dx			; DX = 0 (not in a word)
	jmp	cf1
cf3:	test	dx,dx			; already in a word?
	jnz	cf1			; yes
	inc	dx
	add	word ptr [bx+CNT_WORDS],1
	adc	word ptr [bx+CNT_WORDS+2],0
	jmp	cf1
cf8:	mov	si,bx
	mov	cl,3			; CX = 3 (getc preserves CX)
cf9:	lodsw
	add	[si+CNT_TOTALS-2],ax
	lodsw
	adc	[si+CNT_TOTALS-2],ax
	loop	cf9
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

	include	utilproc.inc

SWITCHES	db	'L'-'A','W'-'A','C'-'A'
TOTAL		db	"total",0

	COMHEAP	<size UTILVARS + STACK_LEN>

CODE	ENDS

	end	main
