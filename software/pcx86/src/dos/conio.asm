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
;	AX, BX, CX, SI, DI, ES
;
DEFPROC	tty_input,DOS
	mov	es,[bp].REG_DS
	ASSUME	ES:NOTHING
	mov	di,dx			; ES:DI -> buffer

	mov	al,IOCTL_GETPOS
	call	con_ioctl		; AX = starting position
	xchg	dx,ax			; move to DX

ti1:	sub	bx,bx			; ES:DI+BX+2 -> next buffer position
	mov	cl,es:[di]
	mov	ch,0			; CX = max characters
	jcxz	ti9

ti2:	call	tty_read
	jc	ti9
ti3:	cmp	al,CHR_RETURN
	je	ti8

	cmp	al,CHR_BACKSPACE
	je	ti3a
	cmp	al,CHR_ESC
	je	ti3a
	jmp	short ti7
;
; Get logical length of data, to determine backspace length.
;
ti3a:	test	bx,bx			; any data?
	jz	ti2			; no, don't bother
	push	bx
	push	cx
	push	ax			; save character
	lea	si,[di+2]		; ES:SI -> characters
	mov	cx,bx			; CX = length
	mov	al,IOCTL_GETLEN
	call	con_ioctl		; get logical length values in AX
	xchg	cx,ax			; CH = total length, CL = length delta
	pop	ax			; restore character
;
; If char is BACKSPACE, output CL times; if ESC, output CH times.
;
	cmp	al,CHR_BACKSPACE
	pop	ax			; AX is now original CX
	pop	bx			; BX restored
	jne	ti3b
	mov	ch,cl
	dec	bx
	inc	ax
	jmp	short ti3c
ti3b:	sub	bx,bx
ti3c:	xchg	cx,ax			; CX restored, AH = erase count
	mov	al,CHR_BACKSPACE
ti3d:	call	write_char
	dec	ah
	jnz	ti3d
	test	bx,bx
	jnz	ti2
	jmp	ti1

ti7:	cmp	cl,1			; room for only one more?
	je	ti2			; yes
	mov	es:[di+bx+2],al
	inc	bx
	call	write_char
	loop	ti2

ti8:	mov	es:[di+bx+2],al		; store the final character (CR)
	call	write_char
	mov	al,CHR_LINEFEED
	call	write_char

ti9:	mov	es:[di+1],bl		; return character count in 2nd byte
	ret
ENDPROC	tty_input

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
;	AL = IOCTL_GETPOS or IOCTL_GETLEN
;	CX = length (for IOCTL_GETLEN)
;	DX = starting position (from IOCTL_GETPOS)
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
	jc	gcp8
	push	es
	les	di,[bx].SFB_DEVICE	; ES:DI -> CON driver
	mov	bx,[bx].SFB_CONTEXT	; BX = context
	xchg	bx,dx			; DX = content, BX = position
	test	es:[di].DDH_ATTR,DDATTR_STDOUT
	pop	ds
	jz	gcp8
	mov	ah,DDC_IOCTLIN
	call	dev_request
	jc	gcp8
	xchg	ax,dx			; AX = position or length as requested
	jmp	short gcp9
gcp8:	mov	ax,0			; default value if error
gcp9:	pop	es
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
