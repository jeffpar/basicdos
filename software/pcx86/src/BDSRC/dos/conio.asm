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

	EXTERNS	<util_strlen,get_sfb,sfb_write>,near

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
DEFPROC	tty_write
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
;	REG_DS:REG_DX -> $-terminated string to print
;
; Outputs:
;	None
;
DEFPROC	tty_print,DOS
	mov	ax,[bp].REG_DS		; special case: if DS:DX = CS:IP
	mov	si,[bp].REG_DX		; INT 21h return address, then treat
	cmp	si,[bp].REG_IP		; this as a PRINTF macro invocation
	jne	tp1
	cmp	ax,[bp].REG_CS
	je	tty_printf
tp1:	mov	ds,ax			; DS:SI -> string
	mov	al,'$'
	call	util_strlen
	xchg	cx,ax			; CX = length
	jmp	write_tty
ENDPROC	tty_print endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tty_printf (REG_AH = 09h, REG_DS:REG_DX = CS:IP)
;
; Inputs:
;	AX:SI -> format string following INT 21h
;	all other printf-style parameters pushed on stack
;
; Outputs:
;	# of characters printed
;
BUFLEN	equ	80
DEFPROC	tty_printf,DOS
	sub	bp,2			; align BP and SP
	sub	sp,BUFLEN		; SP -> BUF
	mov	di,-BUFLEN		; [BP+DI] -> BUF
	mov	ds,ax			; DS:SI -> format string
	push	si
tpf1:	lodsb
	test	al,al
	jz	tpf8			; end of format
	cmp	al,'%'			; format specifier?
	je	tpf2			; yes
tpf1a:	test	di,di
	jz	tpf1
	mov	[bp+di],al		; buffer the character
	inc	di
	jmp	tpf1

tpf2:	jmp	tpf1a

tpf8:	lea	cx,[di+BUFLEN]		; CX = length
	mov	[bp+2].REG_AX,cx	; return that value in REG_AX
	pop	dx
	sub	si,dx
	add	[bp+2].REG_IP,si	; skip over the format string at CS:IP
	mov	si,sp
	push	ss
	pop	ds			; DS:SI -> BUF
	call	write_tty
	add	sp,BUFLEN
	add	bp,2
	ret
ENDPROC	tty_printf endp

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
DEFPROC	write_tty
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
wt8:	lodsb				; we couldn't get an SFB
	int	INT_FASTCON		; so we fallback to INT 29h
	loop	wt8
wt9:	ret
ENDPROC	write_tty

DOS	ends

	end
