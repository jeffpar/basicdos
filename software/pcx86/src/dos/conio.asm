;
; BASIC-DOS Console I/O Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	devapi.inc
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<strlen,sfb_get,sfb_read,sfb_write,dev_request>,near

	ASSUME	CS:DOS, DS:DOS, ES:DOS, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tty_echo (REG_AH = 01h)
;
; Reads a character from the console and echoes it; checks for CTRLC.
;
; Inputs:
;	None
;
; Outputs:
;	AL = character from console; if AL = CHR_CTRLC, issues INT_DOSCTRLC
;
; Modifies:
;	AX
;
DEFPROC	tty_echo,DOS
	call	tty_read
	jc	te9
	call	write_char
	mov	[bp].REG_AL,AL
te9:	ret
ENDPROC	tty_echo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tty_write (REG_AH = 02h)
;
; Inputs:
;	REG_DL = character to write
;
; Outputs:
;	Writes character to console; if CTRLC detected, issues INT_DOSCTRLC
;
; Modifies:
;	AX, SI
;
DEFPROC	tty_write,DOS
	mov	al,[bp].REG_DL
	jmp	write_char
ENDPROC	tty_write

DEFPROC	aux_read,DOS
	ret
ENDPROC	aux_read

DEFPROC	aux_write,DOS
	ret
ENDPROC	aux_write

DEFPROC	prn_write,DOS
	ret
ENDPROC	prn_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tty_io (REG_AH = 06h)
;
; Inputs:
;	DL = 0FFh for input check
;	DL = character to output otherwise
;
; Outputs:
;	AL = input character if ZF clear; no CTRLC checking is performed
;
; Modifies:
;	AX
;
DEFPROC	tty_io,DOS
	cmp	dl,0FFh			; input request?
	je	tio1			; yes
	xchg	ax,dx			; AL = character to write
	call	write_char
tio0:	clc
	ret

tio1:	mov	al,IO_DIRECT
	or	[bp].REG_FL,FL_ZERO
	call	read_char
	jc	tio0
	mov	[bp].REG_AL,al
	and	[bp].REG_FL,NOT FL_ZERO
	ret
ENDPROC	tty_io

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tty_in (REG_AH = 07h)
;
; Inputs:
;	None
;
; Outputs:
;	AL = character from console; no CTRLC checking is performed
;
; Modifies:
;	AX
;
DEFPROC	tty_in,DOS
	mov	al,IO_RAW
	jmp	short ttr1
ENDPROC	tty_in

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tty_read (REG_AH = 08h)
;
; Inputs:
;	None
;
; Outputs:
;	AL = character from console; if AL = CHR_CTRLC, issues INT_DOSCTRLC
;
; Modifies:
;	AX
;
DEFPROC	tty_read,DOS
	mov	al,IO_COOKED
ttr1:	call	read_char
	mov	[bp].REG_AL,al
	ret
ENDPROC	tty_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tty_print (REG_AH = 09h)
;
; Inputs:
;	REG_DS:DX -> $-terminated string to print
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, SI, DS
;
DEFPROC	tty_print,DOS
	mov	ds,[bp].REG_DS		; DS:SI -> string
	mov	si,dx
	mov	al,'$'
	call	strlen
	xchg	cx,ax			; CX = length
	jmp	write_string
ENDPROC	tty_print

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tty_input (REG_AH = 0Ah)
;
; Reads a CHR_RETURN-terminated line of console input into INPBUF.
;
; If INPBUF.INP_MAX is zero, INP_CNT will be set to zero, no data will be
; returned, and the call will return immediately.  If INPBUF.INP_MAX is one,
; no data except CHR_RETURN will be returned, and INP_CNT will be zero.
;
; Note that INP_MAX is limited to 255 and therefore INP_CNT is limited to 254.
;
; Inputs:
;	REG_DS:REG_DX -> INPBUF with INP_MAX preset to max chars
;
; Outputs:
;	Characters are stored in INPBUF.INP_DATA (including the CHR_RETURN);
;	INP_CNT is set to the number of characters (excluding the CHR_RETURN)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	tty_input,DOS
	mov	byte ptr [bp].TMP_AH,0	; TMP_AH = 0 for normal input
	jmp	read_line
ENDPROC	tty_input

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_add
;
; This either replaces or inserts a character at BX, depending on the
; insert flag (0 or 1) in TMP_CX.  Replacing is allowed only if BL + 1 < MAX,
; inserting is allowed only if DH + 1 < MAX, and neither is allowed if the
; display length could exceed 255.
;
; Inputs:
;	AL = character
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX, DH, and input buffer updated as needed
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	con_add,near
	push	ax
	call	con_getdlen		; CH = current display length
	pop	ax
	mov	ah,[bp].TMP_CL		; AH = 0 or 1
	cmp	bl,dh			; cursor at the end?
	jb	ca0			; no
	mov	ah,1			; AH = 1
ca0:	cmp	al,CHR_SPACE
	jae	ca1
	inc	ah			; worst case for a control char
ca1:	cmp	al,CHR_TAB
	jne	ca2
	mov	ah,8			; AH = 8 (worst case for a tab)
ca2:	add	ch,ah			; could this overflow display length?
	jc	ca9			; yes
	mov	cx,[bp].TMP_CX		; CX = 0 (replace) or 1 (insert)
	mov	ah,bl
	jcxz	ca3
	mov	ah,dh
ca3:	inc	ah
	cmp	ah,es:[di]
	cmc
	jb	ca9
	mov	[bp].TMP_AL,cl		; TMP_AL = 0 (replace) or 1 (insert)
	call	con_modify		; replace/insert character (AL) at BX
ca9:	ret
ENDPROC	con_add

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_back (con_fwd)
;
; Moves the cursor back (or forward) the specified number of columns.
;
; Inputs:
;	CL = # of columns to move back (or forward)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX
;
DEFPROC	con_back
	mov	ch,0
	neg	cx
	DEFLBL	con_fwd,near
	jcxz	cbk9
	mov	al,IOCTL_MOVCUR
	call	con_ioctl
cbk9:	ret
ENDPROC	con_back

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_beg
;
; Rewinds the cursor to the beginning.  Used to implement HOME (CTRLA).
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX updated as needed
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	con_beg
	test	bx,bx			; any data to the left?
	jz	cbg9			; no
	call	con_getclen		; CH = total length, CL = length delta
	sub	bx,bx			; update buffer position
	mov	cl,ch			;
	call	con_back		; move cursor back CL characters
cbg9:	ret
ENDPROC	con_beg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_clear
;
; Clears all the characters from cursor to end.  Used to implement CTRL_END.
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX and DH updated as needed (no characters in the buffer are modified)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	con_clear
	call	con_getelen		; CH = display length to end
	mov	cl,ch
	mov	ch,0
	jcxz	ccl9
	push	bx
	push	cx
	call	con_end
	pop	cx
	mov	al,CHR_BACKSPACE
ccl1:	call	con_out			; AL = char to display
	loop	ccl1
	pop	bx			; position prior to con_end
	mov	dh,bl			; set displayed characters to BL
ccl9:	ret
ENDPROC	con_clear

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_del
;
; Deletes the character, if any, underneath the cursor.  Used to implement
; DEL and BACKSPACE.
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX, DH, and input buffer updated as needed
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	con_del
	cmp	bl,dh			; anything displayed at position?
	jae	cd9			; no
	mov	byte ptr [bp].TMP_AL,-1	; TMP_AL = -1 (delete)
	call	con_modify		; delete character at BX
	dec	dh			; reduce # displayed characters
cd9:	ret
ENDPROC	con_del

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_end
;
; Advances the cursor to the end of displayed characters.  Used to implement
; END (CTRLF), ESC (which must advance to the end before calling con_erase),
; and RETURN.
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX updated as needed
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	con_end
	call	con_getelen
	mov	cl,ch
	mov	ch,0
	call	con_fwd
	mov	bl,dh
	ret
ENDPROC	con_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_erase
;
; Erases all the characters preceding the cursor.  Used to implement ESC
; (and DOWN and CTRLX) by first calling con_end.
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX and DH updated as needed (no characters in the buffer are modified)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	con_erase
	call	con_getclen		; CH = display length to cursor
	mov	cl,ch
	mov	ch,0
	jcxz	cer9
	mov	al,CHR_BACKSPACE
cer1:	call	con_out			; AL = char to display
	loop	cer1
cer9:	sub	dh,bl			; reduce displayed characters by BL
	sub	bx,bx			; and reset BX
	ret
ENDPROC	con_erase

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_gettype
;
; Inputs:
;	BX = # characters preceding cursor
;	ES:DI -> input buffer
;
; Outputs:
;	AH = 1 if character at BX is letter or number, 0 if not.
;
; Modifies:
;	AX
;
DEFPROC	con_gettype
	mov	al,es:[di].INP_DATA[bx]
	mov	ah,0
	cmp	al,'0'
	jb	cgt9
	cmp	al,'9'
	jbe	cgt2
	cmp	al,'a'
	jb	cgt1
	cmp	al,'z'
	ja	cgt9
	sub	al,20h
cgt1:	cmp	al,'A'
	jb	cgt9
	cmp	al,'Z'
	ja	cgt9
cgt2:	inc	ah
cgt9:	ret
ENDPROC	con_gettype

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_getdlen
;
; Gets the display length of all displayed characters.
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	CH = total length, CL = length delta of final character
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	con_getdlen
	mov	cl,dh
	jmp	short con_getlen
ENDPROC	con_getdlen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_getclen
;
; Gets the display length of all characters preceding the cursor.
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	CH = total length, CL = length delta of final character
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	con_getclen
	mov	cl,bl			; CL = # of characters
	DEFLBL	con_getlen,near
	lea	si,[di].INP_DATA		; ES:SI -> all characters
	mov	al,IOCTL_GETLEN		; DL = starting column
	call	con_ioctl		; get display length values in AX
	xchg	cx,ax			; CH = total length, CL = length delta
	ret
ENDPROC	con_getclen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_getelen
;
; Gets the display length of all characters from cursor to end.
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	CH = total length, CL = length delta of final character
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	con_getelen
	push	dx
	push	ax
	mov	al,IOCTL_GETPOS
	call	con_ioctl
	mov	cl,dh
	sub	cl,bl			; CX = # displayed chars at position
	mov	dl,al			; DL = current position
	lea	si,[di].INP_DATA[bx]	; ES:SI -> characters at position
	mov	al,IOCTL_GETLEN
	call	con_ioctl		; get display length values in AX
	mov	ch,ah			; CH = display length from position
	pop	ax
	mov	ah,dl
	pop	dx
	ret
ENDPROC	con_getelen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_left
;
; Moves the cursor back one character.  Used to implement LEFT (CTRLS)
; and BACKSPACE (CTRLH).
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	Carry set if no change; otherwise, BX updated
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	con_left
	cmp	bx,1			; any data to the left?
	jb	cl9			; no
	call	con_getclen		; CH = total length, CL = length delta
	dec	bx			; update buffer position
	call	con_back		; move cursor back CL display positions
	ASSERT	NC
cl9:	ret
ENDPROC	con_left

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_next
;
; Used by con_right and con_end to advance the cursor, using the character
; in AL, and ensuring we stay within the limits of the input buffer.
;
; Inputs:
;	AL = character
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX, DH, and input buffer updated as needed
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	con_next,near
	mov	ah,es:[di].INP_MAX	; AH = max count
	sub	ah,bl			; AH = space remaining
	cmp	ah,1			; room for at least one more?
	jb	cn9			; no
	mov	byte ptr [bp].TMP_AL,0	; TMP_AL = 0 (replace)
	call	con_modify		; replace (AL) at BX
cn9:	ret
ENDPROC	con_next

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_out
;
; Displays all non-special characters, using write_char.  Used by con_modify
; ensure consistent output (eg, displaying LINEFEED as "^J").
;
; Inputs:
;	AL = character
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	con_out
	cmp	al,CHR_LINEFEED
	jne	co9
	mov	al,'^'			; for purposes of buffered input,
	call	write_char		; LINEFEED should be displayed as "^J"
	mov	al,'J'
co9:	call	write_char
	ret
ENDPROC	con_out

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_recall
;
; Moves the cursor to the end of available characters.  Used to implement
; RECALL (F3 and CTRLE).
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX and DH updated as needed
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	con_recall
;
; Calling con_end is optional, and in fact, we didn't before con_end existed,
; but now that it does, it's more efficient to jump to the end of displayed
; characters before moving rightward to the end of available characters.
;
	call	con_end
cr1:	call	con_right
	jc	cr9
	jmp	cr1
ENDPROC	con_recall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_right
;
; Moves the cursor right by (re)displaying the character, if any, underneath
; the cursor.  Used to implement RIGHT (CTRLD) and RECALL (F3 and CTRLE).
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX and DH updated as needed
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	con_right
	cmp	bl,es:[di].INP_CNT	; more existing chars?
	cmc
	jb	cr9			; no, ignore movement
	mov	al,es:[di].INP_DATA[bx]	; yes, fetch next character
	call	con_next		; and (re)display it
cr9:	ret
ENDPROC	con_right

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_cword
;
; Compares current char to previous, looking for word transition.
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	Carry clear if no transition yet
;
; Modifies:
;	AX, CX
;
DEFPROC	con_cword
	call	con_gettype		; AH = 1 if digit or letter
	xchg	cx,ax			; save in CH
	dec	bx			; examine previous char
	call	con_gettype		; AH = 1 if digit or letter
	inc	bx			; restore BX
	sub	ah,ch			; AH -= CH
	ret
ENDPROC	con_cword

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_lword
;
; Moves the cursor backward one word.  Used to implement CTRL_LEFT (CTRLW).
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX updated as needed
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	con_lword
	call	con_left
	jc	clw9
	test	bx,bx			; any (more) data to the left?
	jz	clw9			; no
	call	con_cword
	jae	con_lword
clw9:	ret
ENDPROC	con_lword

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_rword
;
; Moves the cursor forward one word.  Used to implement CTRL_RIGHT (CTRLR).
;
; Inputs:
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX updated as needed
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	con_rword
	call	con_right
	jc	crw9
	cmp	bl,es:[di].INP_CNT	; any (more) data to the right?
	jnc	crw9			; no
	call	con_cword
	jae	con_rword
crw9:	ret
ENDPROC	con_rword

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_ioctl
;
; Inputs:
;	AL = IOCTL function (eg, IOCTL_GETPOS, IOCTL_GETLEN, etc)
;	CX = length (for IOCTL_GETLEN or IOCTL_MOVCUR)
;	DL = starting position (from IOCTL_GETPOS)
;	ES:SI -> data (for IOCTL_GETLEN only)
;
; Outputs:
;	AX = position (for IOCTL_GETPOS) or length (for IOCTL_GETLEN)
;
; Modifies:
;	AX
;
DEFPROC	con_ioctl,DOS
	push	bx
	push	ds
	push	es
	pop	ds
	ASSUME	DS:NOTHING
	mov	bx,STDIN
	DOSUTIL	HDLCTL			; issue DOS_HDL_IOCTL as a DOSUTIL call
	jnc	ioc9
	sub	ax,ax			; default value (STDIN redirected?)
ioc9:	pop	ds
	pop	bx
	ret
ENDPROC	con_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_modify
;
; Inputs:
;	AL = character
;	TMP_AL = 1 to insert, 0 to replace, -1 to delete
;	BX = # characters preceding cursor
;	DH = # characters displayed
;	DL = starting column (required for display length calculations)
;	ES:DI -> input buffer
;
; Outputs:
;	BX, DH, and input buffer updated as needed
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	con_modify
	push	dx
	call	con_getelen		; CH = display length to end
	mov	dl,ah			; DL = position of cursor

	cmp	byte ptr [bp].TMP_AL,0
	jl	cm3
	jz	cm2
;
; Insert character at BX with AL and increment BX.
;
	push	ax
	push	bx
	inc	byte ptr es:[di].INP_CNT
cm1:	xchg	al,es:[di].INP_DATA[bx]
	inc	bx
	cmp	bl,es:[di].INP_CNT
	jb	cm1
	cmp	bl,dh			; have we added to displayed chars?
	jbe	cm11			; no
	inc	dh			; yes
cm11:	pop	bx
	pop	ax
	inc	bx
	inc	cx			; adjust length of displayed chars
	jmp	short cm7
;
; Replace character at BX with AL and increment BX.
;
cm2:	mov	es:[di].INP_DATA[bx],al
	call	con_out			; AL = char to display
	inc	bx
	cmp	bl,es:[di].INP_CNT	; have we extended existing chars?
	jbe	cm2a			; no
	mov	es:[di].INP_CNT,bl	; yes
cm2a:	cmp	bl,dh			; have we added to displayed chars?
	jbe	cm7			; no
	inc	dh			; yes
	jmp	short cm9
;
; Delete character at BX, shifting all higher characters down.
;
cm3:	push	bx
	dec	byte ptr es:[di].INP_CNT
	jmp	short cm3b
cm3a:	inc	bx			; start shifting characters down
	mov	al,es:[di].INP_DATA[bx]
	mov	es:[di].INP_DATA[bx-1],al
cm3b:	cmp	bl,es:[di].INP_CNT
	jb	cm3a
	pop	bx
	dec	cx			; adjust length of displayed chars
;
; Redisplay CL characters at SI (and position DL) if display length changed.
;
cm7:	mov	al,IOCTL_GETLEN
	call	con_ioctl		; get display lengths in AX
	cmp	ah,ch			; any change in total display length?
	jne	cm7a			; yes
	cmp	byte ptr [bp].TMP_AL,0	; no, was this a simple replacement?
	je	cm9			; yes, we're done
cm7a:	test	cl,cl
	jz	cm7d
	push	si
	cmp	byte ptr [bp].TMP_AL,0
	je	cm7c
cm7b:	mov	al,es:[si]
	call	con_out			; AL = char to display
cm7c:	inc	si
	dec	cl
	jnz	cm7b
	pop	si
cm7d:	sub	ch,ah			; is the old display length longer?
	jbe	cm8			; no
	mov	al,CHR_SPACE
cm7e:	call	con_out			; AL = char to display
	inc	ah
	dec	ch
	jnz	cm7e
;
; AH contains the length of all the displayed characters from SI, and that's
; normally how many cols we want to rewind the cursor -- unless TMP_AL >= 0,
; in which case we need to reduce AH by the display length of the single char
; at SI.
;
cm8:	mov	ch,ah			; save original length in CH
	cmp	byte ptr [bp].TMP_AL,0
	jl	cm8a
	mov	cl,1
	mov	al,IOCTL_GETLEN
	call	con_ioctl		; get display lengths in AX
	sub	ch,ah
cm8a:	mov	cl,ch
	call	con_back		; move cursor back CL characters

cm9:	pop	ax			; this would be pop dx
	mov	dl,al			; but we only want to pop DL, not DH
	clc
	ret
ENDPROC	con_modify

DEFPROC	tty_status,DOS
	ret
ENDPROC	tty_status

DEFPROC	tty_flush,DOS
	ret
ENDPROC	tty_flush

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_char
;
; Inputs:
;	AL = IO_RAW, IO_COOKED, or IO_DIRECT
;
; Outputs:
;	If carry clear, AL = character; otherwise, carry set
;
; Modifies:
;	AX
;
DEFPROC	read_char,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es
	push	ax
	mov	bx,STDIN
	call	sfb_get			; BX -> SFB
	jc	rc9
	pop	ax
	push	ax
	mov	dx,sp
	push	ss
	pop	es			; ES:DX -> AX on stack
	mov	cx,1			; request one character from STDIN
	call	sfb_read
rc9:	pop	ax			; AX = character
	pop	es
	ASSUME	ES:NOTHING
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	read_char

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_line
;
; Internal function for console input (tty_input, REG_AH = 0Ah)
; and line editing (utl_editln, REG_AH = 23h).
;
; Inputs:
;	TMP_AH = 0 for normal input, 1 for editing notifications
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	read_line,DOS
	mov	es,[bp].REG_DS
	ASSUME	ES:NOTHING
	mov	di,dx			; ES:DI -> buffer
	sub	bx,bx			; ES:DI+BX+2 -> next buffer position

	cmp	bl,es:[di].INP_MAX	; if no room at all
	je	rlx			; then immediately bail

	sub	cx,cx			; set insert mode OFF
	mov	[bp].TMP_CX,cx		; TMP_CX tracks insert mode
	mov	al,IOCTL_SETINS
	call	con_ioctl
	mov	[bp].TMP_DX,ax		; save original insert mode

	mov	al,IOCTL_GETPOS
	call	con_ioctl		; AL = starting column
	xchg	dx,ax			; DL = starting column
	mov	dh,0			; DH = # display characters

rl1:	call	tty_read
	jnc	rl2
rlx:	jmp	rl9

rl2:	cmp	al,CHR_DEL
	je	rl2a
	cmp	al,CHR_CTRLG		; alias for DEL
	jne	rl3
rl2a:	call	con_del
	jmp	rl1

rl3:	cmp	al,CHR_BACKSPACE	; aka CTRLH
	jne	rl4
	call	con_left
	jnc	rl2a			; carry clear if character to delete
	jmp	rl1

rl4:	cmp	al,CHR_ESCAPE
	jne	rl5
rl4a:	call	con_end
	call	con_erase
	jmp	rl1

rl5:	cmp	al,CHR_CTRLX		; alias for DOWN
	jne	rl5a
	cmp	byte ptr [bp].TMP_AH,0	; editing mode?
	je	rl4a			; no
	jmp	rl10			; yes, return key in AX

rl5a:	cmp	al,CHR_CTRLS
	jne	rl6
	call	con_left
	jmp	rl1

rl6:	cmp	al,CHR_CTRLW		; alias for HOME
	jne	rl6a
	call	con_beg
	jmp	rl1

rl6a:	cmp	al,CHR_CTRLR		; alias for END
	jne	rl6b
	call	con_end
	jmp	rl1

rl6b:	cmp	al,CHR_CTRLD		; alias for RIGHT and F1
	jne	rl6c
	call	con_right
	jmp	rl1

rl6c:	cmp	al,CHR_CTRLK		; alias for CTRL_END
	jne	rl6d
	call	con_clear
	jmp	rl1

rl6d:	cmp	al,CHR_CTRLL		; alias for F3
	je	rl6e
	cmp	al,CHR_CTRLE		; alias for UP
	jne	rl6f
	cmp	byte ptr [bp].TMP_AH,0	; editing mode?
	je	rl6e			; no
	jmp	short rl10		; yes, return key in AX

rl6e:	call	con_recall
	jmp	rl1

rl6f:	cmp	al,CHR_CTRLV		; alias for INS
	jne	rl7
	xor	byte ptr [bp].TMP_CL,1	; toggle insert mode
	mov	cl,[bp].TMP_CL
	mov	al,IOCTL_SETINS
	call	con_ioctl
	jmp	rl1

rl7:	cmp	al,CHR_CTRLA		; alias for CTRL_LEFT
	jne	rl7a
	call	con_lword
	jmp	rl1

rl7a:	cmp	al,CHR_CTRLF		; alias for CTRL_RIGHT
	jne	rl7b
	call	con_rword
	jmp	rl1

rl7b:	cmp	al,CHR_RETURN
	je	rl8
	call	con_add
	jmp	rl1
;
; BL indicates the current position within the buffer, and historically
; that's where we'd put the final character (RETURN); however, we now allow
; the cursor to move within the displayed data, so we need to use the end
; of the displayed data (according to DH) as the actual end.
;
rl8:	push	ax
	call	con_end
	pop	ax
	mov	bl,dh			; return all displayed chars
	mov	es:[di].INP_DATA[bx],al	; store the final character (RETURN)
	call	con_out			; AL = char to display

	mov	cx,[bp].TMP_DX		; restore original insert mode
	mov	al,IOCTL_SETINS
	call	con_ioctl

rl9:	mov	es:[di].INP_CNT,bl	; return character count in 2nd byte
	ret

rl10:	cbw
	mov	[bp].REG_AX,ax
	ret
ENDPROC	read_line

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_char
;
; Inputs:
;	AL = character
;
; Outputs:
;	Carry clear if successful, set otherwise
;
; Modifies:
;	None
;
DEFPROC	write_char,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cx
	push	si
	push	ds
	push	ax
	mov	cx,1			; CX = length
	mov	si,sp
	push	ss
	pop	ds			; DS:SI -> character
	ASSUME	DS:NOTHING
	call	write_string
	pop	ax
	pop	ds
	ASSUME	DS:DOS
	pop	si
	pop	cx
	ret
ENDPROC	write_char

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_string
;
; Inputs:
;	CX = length
;	DS:SI -> string
;
; Outputs:
;	Carry clear if successful, set otherwise
;
; Modifies:
;	AX
;
DEFPROC	write_string,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	jcxz	ws8
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es
	push	ds
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	bx,STDOUT
	call	sfb_get			; BX -> SFB
	pop	ds
	ASSUME	DS:NOTHING
	jc	ws6
	mov	al,IO_COOKED
	call	sfb_write
	jmp	short ws7
ws6:	lodsb				; no valid SFB
	int	INT_FASTCON		; so we fallback to INT 29h
	loop	ws6
ws7:	pop	es
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
ws8:	clc
ws9:	ret
ENDPROC	write_string

DOS	ends

	end
