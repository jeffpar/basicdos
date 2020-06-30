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

	EXTERNS	<strlen,get_sfb,sfb_read,sfb_write>,near

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
ti1:	sub	bx,bx			; ES:DI+BX+2 -> next buffer position
	mov	cl,es:[di]
	mov	ch,0			; CX = max characters
	jcxz	ti9
ti2:	call	tty_read
	jc	ti9
ti3:	cmp	al,CHR_RETURN
	je	ti8
	cmp	al,CHR_BACKSPACE
	jne	ti7
	test	bx,bx
	jz	ti2
	call	write_char
	mov	al,' '
	call	write_char
	mov	al,CHR_BACKSPACE
	call	write_char
	dec	bx
	inc	cx
	jmp	ti2
ti7:	cmp	cl,1			; room for only one more?
	je	ti2			; yes
	mov	es:[di+bx+2],al
	inc	bx
	call	write_char
	loop	ti2
ti8:	call	write_char
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
