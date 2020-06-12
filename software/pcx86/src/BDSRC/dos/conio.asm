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

	EXTERNS	<strlen,get_sfb,sfb_write>,near

	ASSUME	CS:DOS, DS:DOS, ES:BIOS, SS:NOTHING

DEFPROC	tty_echo
	ret
ENDPROC	tty_echo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tty_write (REG_AH = 02h)
;
; Inputs:
;	REG_DL = character to write
;
; Outputs:
;	None
;
DEFPROC	tty_write,DOS
	lea	si,[bp].REG_DX
	push	ss
	pop	ds		; DS:SI -> character
	mov	cx,1		; CX = length
	jmp	write_tty
ENDPROC	tty_write

DEFPROC	aux_read
	ret
ENDPROC	aux_read

DEFPROC	aux_write
	ret
ENDPROC	aux_write

DEFPROC	prn_write
	ret
ENDPROC	prn_write

DEFPROC	tty_io
	ret
ENDPROC	tty_io

DEFPROC	tty_in
	ret
ENDPROC	tty_in

DEFPROC	tty_read
	ret
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
DEFPROC	tty_print,DOS
	mov	ds,[bp].REG_DS		; DS:SI -> string
	mov	si,dx
	mov	al,'$'
	call	strlen
	xchg	cx,ax			; CX = length
	jmp	write_tty
ENDPROC	tty_print endp

DEFPROC	tty_input
	ret
ENDPROC	tty_input endp

DEFPROC	tty_status
	ret
ENDPROC	tty_status endp

DEFPROC	tty_flush
	ret
ENDPROC	tty_flush endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_tty
;
; Inputs:
;	CX = length
;	DS:SI -> string
;
; Outputs:
;	Carry clear if successful, set otherwise
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	write_tty
	ASSUME	DS:NOTHING,ES:NOTHING
	jcxz	wt9
	push	ds
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	bx,STDOUT
	call	get_sfb			; BX -> SFB
	pop	ds
	ASSUME	DS:NOTHING
	jc	wt8
	call	sfb_write
	ret
wt8:	lodsb				; no valid SFB
	int	INT_FASTCON		; so we fallback to INT 29h
	loop	wt8
wt9:	ret
ENDPROC	write_tty

DOS	ends

	end
