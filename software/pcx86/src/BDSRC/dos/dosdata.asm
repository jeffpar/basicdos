;
; BASIC-DOS Resident Data Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	extrn	sysinit:near
;
; This must be the first object module; we reuse the JMP as MCB_HEAD.
;
	public	MCB_HEAD
MCB_HEAD label	word
	jmp	sysinit

	even
	public	PSP_ACTIVE
PSP_ACTIVE	dw	1		; start with a fake system PSP

	extrn	tty_echo:near
	extrn	tty_write:near
	extrn	aux_read:near
	extrn	aux_write:near
	extrn	prn_write:near
	extrn	tty_io:near
	extrn	tty_in:near
	extrn	tty_read:near
	extrn	tty_print:near
	extrn	tty_input:near
	extrn	tty_status:near
	extrn	tty_flush:near
	extrn	mem_alloc:near
	extrn	dos_nop:near

	public	CALLTBL
CALLTBL	label	word
	; Functions 00h through 05h
	dw	tty_echo, tty_write, aux_read, aux_write, prn_write, tty_io
	; Functions 06h through 0Bh
	dw	tty_in, tty_read, tty_print, tty_input, tty_status, tty_flush
	; Functions 0Ch through 11h
	dw	dos_nop, dos_nop, dos_nop, dos_nop, dos_nop, dos_nop
	; Functions 12h through 17h
	dw	dos_nop, dos_nop, dos_nop, dos_nop, dos_nop, dos_nop
	; Functions 18h through 1Dh
	dw	dos_nop, dos_nop, dos_nop, dos_nop, dos_nop, dos_nop
	; Functions 1Eh through 23h
	dw	dos_nop, dos_nop, dos_nop, dos_nop, dos_nop, dos_nop
	; Functions 24h through 29h
	dw	dos_nop, dos_nop, dos_nop, dos_nop, dos_nop, dos_nop
	; Functions 2Ah through 2Fh
	dw	dos_nop, dos_nop, dos_nop, dos_nop, dos_nop, dos_nop
	; Functions 30h through 35h
	dw	dos_nop, dos_nop, dos_nop, dos_nop, dos_nop, dos_nop
	; Functions 36h through 3Bh
	dw	dos_nop, dos_nop, dos_nop, dos_nop, dos_nop, dos_nop
	; Functions 3Ch through 41h
	dw	dos_nop, dos_nop, dos_nop, dos_nop, dos_nop, dos_nop
	; Functions 42h through 47h
	dw	dos_nop, dos_nop, dos_nop, dos_nop, dos_nop, dos_nop
	; Functions 48h through 4Dh
	dw	mem_alloc, dos_nop, dos_nop, dos_nop, dos_nop, dos_nop

	public	CALLTBL_SIZE
CALLTBL_SIZE	equ	($ - CALLTBL) SHR 1

DOS	ends

	end
