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

	DEFTBL	<BPB_TABLE,PCB_TABLE,SFB_TABLE>

	DEFWORD	SFB_SYSCON,0		; SFB of the system console
	DEFWORD	PSP_ACTIVE,1		; start with a fake system PSP
	DEFBYTE	CUR_DRV,0		; current drive number
	DEFBYTE	FILE_NAME,' ',11	; buffer for 11-character filename
;
; Constants
;
	DEFBYTE	VALID_CHARS,"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'()-@^_`{}~"
	DEFABS	VALID_COUNT,<$ - VALID_CHARS>

	EXTERNS	<tty_echo,tty_write,aux_read,aux_write,prn_write,tty_io>,near
	EXTERNS	<tty_in,tty_read,tty_print,tty_input,tty_status,tty_flush>,near
	EXTERNS	<mcb_alloc,mcb_free>,near
	EXTERNS	<util_func,dos_none>,near

	DEFLBL	FUNCTBL,word
	dw	tty_echo, tty_write, aux_read, aux_write	; 00h-03h
	dw	prn_write, tty_io, tty_in, tty_read		; 04h-07h
	dw	tty_print, tty_input, tty_status, tty_flush	; 08h-0Bh
	dw	dos_none, dos_none, dos_none, dos_none		; 0Ch-0Fh
	dw	dos_none, dos_none, dos_none, dos_none		; 10h-13h
	dw	dos_none, dos_none, dos_none, dos_none		; 14h-17h
	dw	util_func, dos_none, dos_none, dos_none		; 18h-1Bh
	dw	dos_none, dos_none, dos_none, dos_none		; 1Ch-1Fh
	dw	dos_none, dos_none, dos_none, dos_none		; 20h-23h
	dw	dos_none, dos_none, dos_none, dos_none		; 24h-27h
	dw	dos_none, dos_none, dos_none, dos_none		; 28h-2Bh
	dw	dos_none, dos_none, dos_none, dos_none		; 2Ch-2Fh
	dw	dos_none, dos_none, dos_none, dos_none		; 30h-33h
	dw	dos_none, dos_none, dos_none, dos_none		; 34h-37h
	dw	dos_none, dos_none, dos_none, dos_none		; 38h-3Bh
	dw	dos_none, dos_none, dos_none, dos_none		; 3Ch-3Fh
	dw	dos_none, dos_none, dos_none, dos_none		; 40h-43h
	dw	dos_none, dos_none, dos_none, dos_none		; 44h-47h
	dw	mcb_alloc, mcb_free, dos_none, dos_none		; 48h-4Bh
	dw	dos_none, dos_none				; 4Ch-4Fh
	DEFABS	FUNCTBL_SIZE,<($ - FUNCTBL) SHR 1>

DOS	ends

	end
