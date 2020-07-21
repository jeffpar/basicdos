;
; BASIC-DOS Console I/O Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<strlen,get_sfb,sfb_read,sfb_write,dev_request>,near

	ASSUME	CS:DOS, DS:DOS, ES:BIOS, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
te9:	ret
ENDPROC	tty_echo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

DEFPROC	tty_io,DOS
	ret
ENDPROC	tty_io

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	jmp	read_char
ENDPROC	tty_in

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	jmp	read_char
ENDPROC	tty_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	push	bp
	mov	es,[bp].REG_DS
	ASSUME	ES:NOTHING
	mov	di,dx			; ES:DI -> buffer

	mov	al,IOCTL_GETPOS
	call	con_ioctl		; AL = starting column
	xchg	dx,ax			; DL = starting column
	mov	dh,0			; DH = # display characters
	sub	bx,bx			; ES:DI+BX+2 -> next buffer position

ti1:	call	tty_read
	jc	ti9

ti2:	cmp	al,CHR_RETURN
	je	ti8

	cmp	al,CHR_DEL
	jne	ti3
ti2a:	call	ttyin_del
	jmp	ti1

ti3:	cmp	al,CHR_BACKSPACE
	jne	ti4
	call	ttyin_left
	jmp	ti2a

ti4:	cmp	al,CHR_ESC
	jne	ti5
ti4a:	call	ttyin_end
	call	ttyin_erase
	jmp	ti1

ti5:	cmp	al,CHR_CTRLX
	je	ti4a
	cmp	al,CHR_CTRLB
	jne	ti6
	call	ttyin_left
	jmp	ti1

ti6:	cmp	al,CHR_CTRLE
	jne	ti6a
	call	ttyin_end
	jmp	ti1

ti6a:	cmp	al,CHR_CTRLF
	jne	ti6b
	call	ttyin_right
	jmp	ti1

ti6b:	cmp	al,CHR_CTRLR
	jne	ti7
	call	ttyin_recall
	jmp	ti1

ti7:	call	ttyin_add
	jmp	ti1
;
; BL indicates the current position within the buffer, and historically
; that's where we'd put the final character (CR); however, we now allow
; the cursor to move within the displayed data, so we need to use the end
; of the displayed data (according to DH) as the actual end.
;
ti8:	mov	bl,dh			; return all displayed chars
	mov	es:[di+bx+2],al		; store the final character (CR)
	call	ttyin_out

ti9:	mov	es:[di+1],bl		; return character count in 2nd byte
	pop	bp
	ret
ENDPROC	tty_input

DEFPROC	ttyin_add,near
	mov	ah,es:[di]		; AH = max count
	sub	ah,bl			; AH = space remaining
	cmp	ah,2			; room for at least two more?
	jb	tta9			; no
	sub	bp,bp			; BP = 0 (replace)
	call	ttyin_mod		; replace character (AL) at BX
	cmp	bl,dh			; have we increased # displayed chars?
	jbe	tta8			; no
	mov	dh,bl			; yes
tta8:	clc
tta9:	ret
ENDPROC	ttyin_add

DEFPROC	ttyin_del
	cmp	bl,dh			; anything displayed at position?
	jae	ttd9			; no
	sbb	bp,bp			; BP = -1 (delete)
	call	ttyin_mod		; delete character at BX
	dec	dh			; reduce # displayed characters
ttd9:	ret
ENDPROC	ttyin_del

DEFPROC	ttyin_end
	cmp	bl,dh			; more displayed chars?
	jae	tte9			; no
	mov	al,es:[di+bx+2]		; yes, fetch next character
	call	ttyin_add		; add it to what's being displayed
	jnc	ttyin_end
tte9:	ret
ENDPROC	ttyin_end

DEFPROC	ttyin_erase
	call	ttyin_getlen		; CH = total length
	sub	bx,bx
	mov	cl,ch
	mov	ch,bh
	jcxz	ttx9
	mov	al,CHR_BACKSPACE
ttx1:	call	ttyin_out
	loop	ttx1
ttx9:	mov	dh,cl			; zero # displayed characters, too
	ret
ENDPROC	ttyin_erase

DEFPROC	ttyin_getlen
	lea	si,[di+2]		; ES:SI -> all characters
	mov	cl,bl			; CL = # of characters
	mov	al,IOCTL_GETLEN		; DL = starting column
	call	con_ioctl		; get logical length values in AX
	xchg	cx,ax			; CH = total length, CL = length delta
	ret
ENDPROC	ttyin_getlen

DEFPROC	ttyin_left
	test	bx,bx			; any data to our left?
	jz	ttl9			; no
	call	ttyin_getlen		; CH = total length, CL = length delta
	dec	bx			; update buffer position
	call	ttyin_move		; move cursor back CL characters
ttl9:	ret
ENDPROC	ttyin_left

DEFPROC	ttyin_mod
	push	ax
	mov	al,IOCTL_GETPOS
	call	con_ioctl
	mov	cl,dh
	sub	cl,bl			; CX = # displayed chars at position
	mov	dl,al			; DL = current position
	lea	si,[di+bx+2]		; ES:SI -> characters at position
	mov	al,IOCTL_GETLEN
	call	con_ioctl		; get logical length values in AX
	mov	ch,ah			; CH = logical length from position
	pop	ax

	test	bp,bp
	jl	ttm2
	jg	ttm9
;
; Replace character at BX with AL, and increment BX.
;
ttm1:	mov	es:[di+bx+2],al
	call	ttyin_out
	inc	bx
	cmp	bl,es:[di+1]		; have we extended existing chars?
	jbe	ttm1a			; no
	mov	es:[di+1],bl		; yes
ttm1a:	cmp	bl,dh			; have we added to displayed chars?
	jbe	ttm7			; no
	inc	dh			; yes
	jmp	short ttm9
;
; Delete character at BX, shifting all higher characters down.
;
ttm2:	push	bx
	dec	byte ptr es:[di+1]
	jmp	short ttm2b
ttm2a:	inc	bx			; start shifting characters down
	mov	al,es:[di+bx+2]
	mov	es:[di+bx+1],al
ttm2b:	cmp	bl,es:[di+1]
	jb	ttm2a
	pop	bx
	dec	cx			; adjust length of displayed chars
;
; Redisplay CL characters at SI if their display length changed.
;
ttm7:	mov	al,IOCTL_GETLEN
	call	con_ioctl		; get display lengths in AX
	cmp	ah,ch			; any change in total display length?
	je	ttm9			; no
	push	si
ttm7a:	lods	byte ptr es:[si]
	call	ttyin_out
	dec	cl
	jnz	ttm7a
	pop	si
	sub	ch,ah			; is the old display length longer?
	jbe	ttm8			; no
	mov	al,CHR_SPACE
ttm7b:	call	ttyin_out
	dec	ch
	jnz	ttm7b
;
; AH contains the length of all the displayed characters from SI, and that's
; normally how many positions we want to rewind the cursor -- unless BP >= 0,
; in which case we need to reduce AH by the display length of the single char
; at SI.
;
ttm8:	mov	ch,ah			; save original length in CH
	test	bp,bp
	jl	ttm9
	mov	cl,1
	mov	al,IOCTL_GETLEN
	call	con_ioctl		; get display lengths in AX
	sub	ch,ah
	mov	cl,ch
	call	ttyin_move		; move cursor back CL characters

ttm9:	ret
ENDPROC	ttyin_mod

DEFPROC	ttyin_move
	mov	ch,0
	jcxz	ttv9
	neg	cx
	mov	al,IOCTL_MOVHORZ
	call	con_ioctl
ttv9:	ret
ENDPROC	ttyin_move

DEFPROC	ttyin_out
	cmp	al,CHR_LINEFEED
	jne	tto2
	mov	al,'^'			; for purposes of buffered input,
	call	write_char		; LINEFEED should be displayed as "^J"
	mov	al,'J'
tto2:	call	write_char
	ret
ENDPROC	ttyin_out

DEFPROC	ttyin_recall
	cmp	bl,es:[di+1]		; more existing chars?
	jae	ttc9			; no
	mov	al,es:[di+bx+2]		; yes, fetch next character
	call	ttyin_add		; add it to what's being displayed
	jnc	ttyin_recall
ttc9:	ret
ENDPROC	ttyin_recall

DEFPROC	ttyin_right
	cmp	bl,es:[di+1]		; more existing chars?
	jae	ttr9			; no, just ignore CTRLF
	mov	al,es:[di+bx+2]		; yes, fetch next character
	call	ttyin_add
ttr9:	ret
ENDPROC	ttyin_right

DEFPROC	tty_status,DOS
	ret
ENDPROC	tty_status

DEFPROC	tty_flush,DOS
	ret
ENDPROC	tty_flush

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	push	dx
	push	di
	push	ds
	push	es
	mov	bx,STDIN
	push	ax
	call	get_sfb			; BX -> SFB
	pop	ax
	jc	ioc8
	push	es
	les	di,[bx].SFB_DEVICE	; ES:DI -> CON driver
	mov	bx,[bx].SFB_CONTEXT	; BX = context
	xchg	bx,dx			; DX = content, BX = position
	test	es:[di].DDH_ATTR,DDATTR_STDOUT
	pop	ds
	jz	ioc8
	mov	ah,DDC_IOCTLIN
	call	dev_request
	jc	ioc8
	xchg	ax,dx			; AX = position or length as requested
	jmp	short ioc9
ioc8:	mov	ax,0			; default value if error
ioc9:	pop	es
	pop	ds
	pop	di
	pop	dx
	pop	bx
	ret
ENDPROC	con_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_char
;
; Inputs:
;	AL = IO_RAW or IO_COOKED
;
; Outputs:
;	AL = character
;
; Modifies:
;	AX
;
DEFPROC	read_char,DOS
	ASSUME	ES:NOTHING
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es
	push	ax
	mov	bx,STDIN
	call	get_sfb			; BX -> SFB
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	ASSUME	DS:NOTHING, ES:NOTHING
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
	call	get_sfb			; BX -> SFB
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
