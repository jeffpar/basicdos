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

	ASSUME	CS:DOS, DS:DOS, ES:BIOS, SS:NOTHING

DEFPROC	tty_echo
	ret
ENDPROC	tty_echo

DEFPROC	tty_write
	ret
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

DEFPROC	tty_print
	ret
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

DOS	ends

	end
