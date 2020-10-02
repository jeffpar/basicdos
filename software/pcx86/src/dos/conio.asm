;
; BASIC-DOS Console I/O Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
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
; Inputs:
;	REG_DS:REG_DX -> input buffer; 1st byte must be preset to max chars
;
; Outputs:
;	Stores input characters in the input buffer starting at the 3rd byte;
;	upon receiving CHR_RETURN, the 2nd byte of buffer is set to number of
;	characters received (excluding the CHR_RETURN).
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	tty_input,DOS
	mov	es,[bp].REG_DS
	ASSUME	ES:NOTHING
	mov	di,dx			; ES:DI -> buffer
	ASSERT	BE,<cmp byte ptr es:[di],128>

	sub	cx,cx			; set insert mode OFF
	mov	[bp].TMP_CX,cx		; TMP_CX tracks insert mode
	mov	al,IOCTL_SETINS
	call	con_ioctl
	mov	[bp].TMP_DX,ax		; save original insert mode

	mov	al,IOCTL_GETPOS
	call	con_ioctl		; AL = starting column
	xchg	dx,ax			; DL = starting column
	mov	dh,0			; DH = # display characters
	sub	bx,bx			; ES:DI+BX+2 -> next buffer position

ti1:	call	tty_read
	jnc	ti2
	jmp	ti9

ti2:	cmp	al,CHR_RETURN
	je	ti8

	cmp	al,CHR_DEL
	je	ti2a
	cmp	al,CHR_CTRLG
	jne	ti3
ti2a:	call	con_del
	jmp	ti1

ti3:	cmp	al,CHR_BACKSPACE
	jne	ti4
	call	con_left
	jc	ti2a			; carry set if there's a char to delete
	jmp	ti1

ti4:	cmp	al,CHR_ESCAPE
	jne	ti5
ti4a:	call	con_end
	call	con_erase
	jmp	ti1

ti5:	cmp	al,CHR_CTRLX
	je	ti4a
	cmp	al,CHR_CTRLS
	jne	ti6
	call	con_left
	jmp	ti1

ti6:	cmp	al,CHR_CTRLA
	jne	ti6a
	call	con_beg
	jmp	ti1

ti6a:	cmp	al,CHR_CTRLF
	jne	ti6b
	call	con_end
	jmp	ti1

ti6b:	cmp	al,CHR_CTRLD
	jne	ti6c
	call	con_right
	jmp	ti1

ti6c:	cmp	al,CHR_CTRLE
	jne	ti6d
	call	con_recall
	jmp	ti1

ti6d:	cmp	al,CHR_CTRLV
	jne	ti7
	xor	byte ptr [bp].TMP_CL,1	; toggle insert mode
	mov	cl,[bp].TMP_CL
	mov	al,IOCTL_SETINS
	call	con_ioctl
	jmp	ti1

ti7:	call	con_add
	jmp	ti1
;
; BL indicates the current position within the buffer, and historically
; that's where we'd put the final character (RETURN); however, we now allow
; the cursor to move within the displayed data, so we need to use the end
; of the displayed data (according to DH) as the actual end.
;
ti8:	push	ax
	call	con_end
	pop	ax
	mov	bl,dh			; return all displayed chars
	mov	es:[di+bx+2],al		; store the final character (RETURN)
	call	con_out

	mov	cx,[bp].TMP_DX		; restore original insert mode
	mov	al,IOCTL_SETINS
	call	con_ioctl

ti9:	mov	es:[di+1],bl		; return character count in 2nd byte
	ret
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
	jb	tta0			; no
	mov	ah,1			; AH = 1
tta0:	cmp	al,CHR_TAB
	jne	tta1
	mov	ah,8			; AH = 8 (worst case for a tab)
tta1:	add	ch,ah			; could this overflow display length?
	jc	tta9			; yes
	mov	cx,[bp].TMP_CX		; CX = 0 (replace) or 1 (insert)
	mov	ah,bl
	jcxz	tta2
	mov	ah,dh
tta2:	inc	ah
	cmp	ah,es:[di]
	cmc
	jb	tta9
	mov	[bp].TMP_AL,cl		; TMP_AL = 0 (replace) or 1 (insert)
	call	con_modify		; replace/insert character (AL) at BX
tta9:	ret
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
	jcxz	ttb8
	mov	al,IOCTL_MOVCUR
	call	con_ioctl
ttb8:	ret
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
	test	bx,bx			; any data to our left?
	jz	ttb9			; no
	call	con_getclen		; CH = total length, CL = length delta
	sub	bx,bx			; update buffer position
	mov	cl,ch			;
	call	con_back		; move cursor back CL characters
ttb9:	ret
ENDPROC	con_beg

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
	jae	ttd9			; no
	mov	byte ptr [bp].TMP_AL,-1	; TMP_AL = -1 (delete)
	call	con_modify		; delete character at BX
	dec	dh			; reduce # displayed characters
ttd9:	ret
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
; Erases all the characters preceding the cursor.  Used to implement ESC (and
; DOWN ARROW and CTRLX) by first calling con_end.
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
	jcxz	ttx9
	mov	al,CHR_BACKSPACE
ttx1:	call	con_out
	loop	ttx1
ttx9:	sub	dh,bl			; reduce displayed characters by BL
	sub	bx,bx			; and reset BX
	ret
ENDPROC	con_erase

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
	lea	si,[di+2]		; ES:SI -> all characters
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
	lea	si,[di+bx+2]		; ES:SI -> characters at position
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
; Moves the cursor back one character.  Used to implement LEFT ARROW (CTRLS)
; and BACKSPACE (CTRLH).
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
DEFPROC	con_left
	test	bx,bx			; any data to our left?
	jz	ttl9			; no
	call	con_getclen		; CH = total length, CL = length delta
	dec	bx			; update buffer position
	call	con_back		; move cursor back CL display positions
	stc
ttl9:	ret
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
	mov	ah,es:[di]		; AH = max count
	sub	ah,bl			; AH = space remaining
	cmp	ah,1			; room for at least one more?
	jb	ttn9			; no
	mov	byte ptr [bp].TMP_AL,0	; TMP_AL = 0 (replace)
	call	con_modify		; replace (AL) at BX
ttn9:	ret
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
	jne	tto2
	mov	al,'^'			; for purposes of buffered input,
	call	write_char		; LINEFEED should be displayed as "^J"
	mov	al,'J'
tto2:	call	write_char
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
	jc	ttr9
	jmp	cr1
ENDPROC	con_recall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_right
;
; Moves the cursor right by (re)displaying the character, if any, underneath
; the cursor.  Used to implement RIGHT ARROW (CTRLD) and RECALL (F3 and CTRLE).
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
	cmp	bl,es:[di+1]		; more existing chars?
	cmc
	jb	ttr9			; no, ignore movement
	mov	al,es:[di+bx+2]		; yes, fetch next character
	call	con_next		; and (re)display it
ttr9:	ret
ENDPROC	con_right

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
;	TMP_AX = 1 to insert, 0 to replace, -1 to delete
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
	jl	ttm3
	jz	ttm2
;
; Insert character at BX with AL and increment BX.
;
	push	ax
	push	bx
	inc	byte ptr es:[di+1]
ttm1:	xchg	al,es:[di+bx+2]
	inc	bx
	cmp	bl,es:[di+1]
	jb	ttm1
	cmp	bl,dh			; have we added to displayed chars?
	jbe	ttm11			; no
	inc	dh			; yes
ttm11:	pop	bx
	pop	ax
	inc	bx
	inc	cx			; adjust length of displayed chars
	jmp	short ttm7
;
; Replace character at BX with AL and increment BX.
;
ttm2:	mov	es:[di+bx+2],al
	call	con_out
	inc	bx
	cmp	bl,es:[di+1]		; have we extended existing chars?
	jbe	ttm2a			; no
	mov	es:[di+1],bl		; yes
ttm2a:	cmp	bl,dh			; have we added to displayed chars?
	jbe	ttm7			; no
	inc	dh			; yes
	jmp	short ttm9
;
; Delete character at BX, shifting all higher characters down.
;
ttm3:	push	bx
	dec	byte ptr es:[di+1]
	jmp	short ttm3b
ttm3a:	inc	bx			; start shifting characters down
	mov	al,es:[di+bx+2]
	mov	es:[di+bx+1],al
ttm3b:	cmp	bl,es:[di+1]
	jb	ttm3a
	pop	bx
	dec	cx			; adjust length of displayed chars
;
; Redisplay CL characters at SI (and position DL) if display length changed.
;
ttm7:	mov	al,IOCTL_GETLEN
	call	con_ioctl		; get display lengths in AX
	cmp	ah,ch			; any change in total display length?
	jne	ttm7a			; yes
	cmp	byte ptr [bp].TMP_AL,0	; no, was this a simple replacement?
	je	ttm9			; yes, we're done
ttm7a:	test	cl,cl
	jz	ttm7d
	push	si
	cmp	byte ptr [bp].TMP_AL,0
	je	ttm7c
ttm7b:	mov	al,es:[si]
	call	con_out
ttm7c:	inc	si
	dec	cl
	jnz	ttm7b
	pop	si
ttm7d:	sub	ch,ah			; is the old display length longer?
	jbe	ttm8			; no
	mov	al,CHR_SPACE
ttm7e:	call	con_out
	inc	ah
	dec	ch
	jnz	ttm7e
;
; AH contains the length of all the displayed characters from SI, and that's
; normally how many cols we want to rewind the cursor -- unless TMP_AX >= 0,
; in which case we need to reduce AH by the display length of the single char
; at SI.
;
ttm8:	mov	ch,ah			; save original length in CH
	cmp	byte ptr [bp].TMP_AL,0
	jl	ttm8a
	mov	cl,1
	mov	al,IOCTL_GETLEN
	call	con_ioctl		; get display lengths in AX
	sub	ch,ah
ttm8a:	mov	cl,ch
	call	con_back		; move cursor back CL characters

ttm9:	pop	ax			; this would be pop dx
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
