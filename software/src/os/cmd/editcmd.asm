;
; BASIC-DOS Program Line Editing Commands
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; AUTO, DELETE, EDIT, and LLIST, and editPrompt, which the main loop calls
; when AUTO or EDIT has set a line to edit (see EDIT_STATE).  The program's
; text blocks and the other editing functions (eg, LIST) are in edit.asm.
;
; This module is not part of COMMAND's core (see CMD.LRF and HEAP.ASM): when
; only the core is loaded, cmdDOS refuses these commands with "Not enough
; memory" (see genUpper), so EDIT_STATE stays zero and the main loop never
; calls editPrompt.
;
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<chkProgram,getRange,syntaxError,freeCache,walkLines,delLine>
	EXTNEAR	<findLine,putNum,parseLine,storeLine,printCRLF,listLine>
	EXTNEAR	<chkOut>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

EDIT_LINE	equ	EDIT_STATE+0	; line # to edit at the next prompt
EDIT_INC	equ	EDIT_STATE+2	; AUTO increment (0 if not AUTO)
MAX_LINE	equ	65529		; largest line # (see edit.asm)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdLlist
;
; Process "LLIST [line][-[line]]", which lists lines like LIST, but to the
; printer (PRN), reporting any printer error afterward (see chkOut).  The
; range is parsed before PRN becomes STDOUT, so that errors aren't printed.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdLlist
	mov	al,'-'
	call	getRange		; AX = 1st line #, DX = last line #
	jc	ll9
	mov	cl,ds:[PSP_PFT][STDPRN]
	xchg	cl,ds:[PSP_PFT][STDOUT]	; make PRN STDOUT
	push	cx
	mov	si,offset listLine
	call	walkLines
	pop	cx
	mov	ds:[PSP_PFT][STDOUT],cl	; and restore STDOUT
	mov	bx,STDPRN
	jmp	chkOut
ll9:	ret
ENDPROC	cmdLlist

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdAuto
;
; Process "AUTO [line][,increment]", which prompts for program lines
; beginning with the given line # (default 10), which is advanced by the
; increment (default 10) after each line is entered (see editPrompt).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdAuto
	call	chkProgram
	jc	au9
	mov	al,','
	call	getRange		; AX = line #, DX = increment
	jc	au9
	jcxz	au1			; no comma, so use the default
	cmp	dx,-1			; was an increment specified?
	jne	au2			; yes
au1:	mov	dx,10
au2:	test	ax,ax			; was a line # specified?
	jnz	au3			; yes
	mov	ax,10
au3:	mov	[bx].EDIT_LINE,ax
	mov	[bx].EDIT_INC,dx
au9:	ret
ENDPROC	cmdAuto

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDelete
;
; Process "DELETE [line][-[line]]", which deletes the specified range of
; lines (at least one line # must be specified).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDelete
	call	chkProgram
	jc	de9
	mov	al,'-'
	call	getRange		; AX = 1st line #, DX = last line #
	jc	de9
	inc	dx			; was a last line # specified?
	jnz	de1			; yes
	test	ax,ax			; was a 1st line # specified?
	jnz	de1			; yes
	jmp	syntaxError		; no
de1:	dec	dx
	call	freeCache		; (the program must be recompiled)
	mov	si,offset delLine
	jmp	walkLines
de9:	ret
ENDPROC	cmdDelete

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdEdit
;
; Process "EDIT line", which displays the line for editing at the next prompt
; (see editPrompt).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdEdit
	call	chkProgram
	jc	ed9
	mov	al,'-'
	call	getRange		; AX = line #
	jc	ed9
	xchg	dx,ax			; DX = line #
	call	findLine
	jc	ed8			; not found
	jne	ed8			; not found
	mov	[bx].EDIT_LINE,dx
	mov	word ptr [bx].EDIT_INC,0
	ret
ed8:	PRINTF	<"Undefined line number",13,10,13,10>
	stc
ed9:	ret
ENDPROC	cmdEdit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; editPrompt
;
; Called by the main loop instead of prompting for a command when there's a
; line to edit (see cmdAuto and cmdEdit): the input buffer is filled with the
; line # and the line's text (if any), and displayed for editing.  If AUTO is
; active, a numbered line is added to the program and the next line # is set;
; anything else (including a numbered line with no text) ends AUTO.
;
; Inputs:
;	AX = line # to edit
;	BX -> CMDHEAP
;	DS = ES = SS
;
; Outputs:
;	Carry set if the input was processed; otherwise, carry clear (and the
;	input in INPUTBUF should be processed as usual)
;
; Modifies:
;	Any but BX
;
DEFPROC	editPrompt
	xchg	dx,ax			; DX = line #
	call	findLine		; ES:DI -> line, if any
	mov	si,di
	jc	ep1			; not found
	je	ep2			; found (CX = length)
ep1:	sub	cx,cx			; no text
ep2:	push	ds
	push	es
	push	ds
	pop	es
	lea	di,[bx].INPUTBUF.INP_DATA
	xchg	ax,dx
	call	putNum			; store the line # and a space
	pop	ds
	add	si,3			; DS:SI -> line's text
	lea	ax,[bx].INPUTBUF.INP_DATA + 254
	sub	ax,di			; AX = room left (INP_CNT max is 254)
	cmp	cx,ax
	jbe	ep3
	xchg	cx,ax
ep3:	rep	movsb
	pop	ds
	lea	ax,[bx].INPUTBUF.INP_DATA
	sub	di,ax
	xchg	ax,di
	mov	[bx].INPUTBUF.INP_CNT,al
	lea	dx,[bx].INPUTBUF
	mov	[bx].INPUT_BUF,dx
	sub	ax,ax
	mov	[bx].EDIT_LINE,ax	; (so that CTRLC ends any editing)
	xchg	ax,[bx].EDIT_INC	; AX = AUTO increment, if any
	push	ax
	DOSUTIL	EDITLN,2		; display and edit the line
	call	printCRLF
	pop	dx			; DX = AUTO increment
	test	dx,dx			; AUTO?
	jz	ep9			; no (carry clear)
	lea	si,[bx].INPUTBUF.INP_DATA
	mov	cl,[bx].INPUTBUF.INP_CNT
	push	dx
	call	parseLine		; AX = line #, CX = length of text
	pop	dx
	jc	ep8			; not a numbered line, so AUTO is done
	jcxz	ep7			; no text, so AUTO is done
	push	ax
	push	dx
	call	storeLine
	pop	dx
	pop	ax
	jc	ep7
	add	ax,dx			; AX = next line #
	jc	ep7
	cmp	ax,MAX_LINE
	ja	ep7
	mov	[bx].EDIT_LINE,ax
	mov	[bx].EDIT_INC,dx
ep7:	stc
	jmp	short ep9
ep8:	clc
ep9:	push	ss
	pop	es
	ret
ENDPROC	editPrompt

CODE	ENDS

	end
