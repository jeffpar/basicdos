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

	EXTERNS	<sysinit>,near

DOS	segment word public 'CODE'
;
; This must be the first object module; we reuse the JMP as MCB_HEAD.
;
	DEFLBL	MCB_HEAD,word
	jmp	sysinit

	DEFWORD	PCB_TABLE,word
	DEFWORD	SFB_TABLE,word

	DEFWORD	PSP_ACTIVE,1		; start with a fake system PSP

	EXTERNS	<tty_echo,tty_write,aux_read,aux_write,prn_write,tty_io>,near
	EXTERNS	<tty_in,tty_read,tty_print,tty_input,tty_status,tty_flush>,near
	EXTERNS	<mem_alloc,mem_free>,near
	EXTERNS	<dos_nop>,near

	DEFLBL	CALLTBL,word

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
	dw	mem_alloc, mem_free, dos_nop, dos_nop, dos_nop, dos_nop

	DEFABS	CALLTBL_SIZE,<($ - CALLTBL) SHR 1>

DOS	ends

	end
