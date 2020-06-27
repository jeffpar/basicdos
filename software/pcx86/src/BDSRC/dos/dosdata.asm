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
; This must be the first object module; we reuse the JMP as mcb_head.
;
	DEFLBL	mcb_head,word
	jmp	sysinit

	DEFWORD	mcb_limit,0		; segment limit
	DEFWORD	scb_active,0		; offset of active SCB (zero if none)
	DEFWORD	psp_active,0		; segment of active PSP (zero if none)
	DEFPTR	clk_ptr,-1		; pointer to CLOCK$ DDH
	DEFBYTE	scb_locked,-1		; -1 if unlocked
	DEFBYTE	file_name,' ',11	; buffer for 11-character filename
	DEFBYTE	ddint_level,0		; device driver interrupt level

	DEFTBL	<bpb_table,scb_table,sfb_table>
;
; Constants
;
	DEFBYTE	VALID_CHARS,"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'()-@^_`{}~"
	DEFABS	VALID_COUNT,<$ - VALID_CHARS>
	DEFBYTE	STR_CTRLC,<"^C",CHR_RETURN,CHR_LINEFEED>

	EXTERNS	<psp_term>,near
	EXTERNS	<tty_echo,tty_write,aux_read,aux_write,prn_write,tty_io>,near
	EXTERNS	<tty_in,tty_read,tty_print,tty_input,tty_status,tty_flush>,near
	EXTERNS	<dsk_flush>,near
	EXTERNS	<msc_setvec,msc_getvec>,near
	EXTERNS	<psp_exec,psp_create,psp_set,psp_get>,near
	EXTERNS	<hdl_open,hdl_close,hdl_read,hdl_write,hdl_seek>,near
	EXTERNS	<mem_alloc,mem_free,mem_realloc>,near
	EXTERNS	<utl_strlen,utl_atoi,utl_itoa,utl_printf,utl_sprintf>,near
	EXTERNS	<utl_getdev,utl_ioctl,utl_load,utl_start,utl_stop,utl_unload>,near
	EXTERNS	<utl_yield,utl_sleep,utl_wait,utl_endwait,utl_hotkey>,near
	EXTERNS	<func_none>,near

	DEFLBL	FUNCTBL,word
	dw	psp_term,    tty_echo,    tty_write,   aux_read		;00h-03h
	dw	aux_write,   prn_write,   tty_io,      tty_in		;04h-07h
	dw	tty_read,    tty_print,   tty_input,   tty_status	;08h-0Bh
	dw	tty_flush,   dsk_flush,   func_none,   func_none	;0Ch-0Fh
	dw	func_none,   func_none,   func_none,   func_none	;10h-13h
	dw	func_none,   func_none,   func_none,   func_none	;14h-17h
	dw	func_none,   func_none,   func_none,   func_none	;18h-1Bh
	dw	func_none,   func_none,   func_none,   func_none	;1Ch-1Fh
	dw	func_none,   func_none,   func_none,   func_none	;20h-23h
	dw	func_none,   msc_setvec,  psp_create,  func_none	;24h-27h
	dw	func_none,   func_none,   func_none,   func_none	;28h-2Bh
	dw	func_none,   func_none,   func_none,   func_none	;2Ch-2Fh
	dw	func_none,   func_none,   func_none,   func_none	;30h-33h
	dw	func_none,   msc_getvec,  func_none,   func_none	;34h-37h
	dw	func_none,   func_none,   func_none,   func_none	;38h-3Bh
	dw	func_none,   hdl_open,    hdl_close,   hdl_read		;3Ch-3Fh
	dw	hdl_write,   func_none,   hdl_seek,    func_none	;40h-43h
	dw	func_none,   func_none,   func_none,   func_none	;44h-47h
	dw	mem_alloc,   mem_free,    mem_realloc, psp_exec		;48h-4Bh
	dw	func_none,   func_none,   func_none,   func_none	;4Ch-4Fh
	dw	psp_set,     psp_get					;50h-51h
	DEFABS	FUNCTBL_SIZE,<($ - FUNCTBL) SHR 1>

	DEFLBL	UTILTBL,word
	dw	utl_strlen,  utl_atoi,    utl_itoa,    utl_printf	;00h-03h
	dw	utl_sprintf, utl_getdev,  utl_ioctl,   utl_load		;04h-07h
	dw	utl_start,   utl_stop,    utl_unload,  utl_yield	;08h-0Bh
	dw	utl_sleep,   utl_wait,    utl_endwait, utl_hotkey	;0Ch-0Fh
	dw	func_none,   func_none,   func_none,   func_none	;10h-13h
	dw	func_none,   func_none,   func_none,   func_none	;14h-17h
	dw	func_none,   func_none,   func_none,   func_none	;18h-1Bh
	dw	func_none,   func_none,   func_none,   func_none	;1Ch-1Fh
	dw	func_none,   func_none,   func_none,   func_none	;20h-23h
	dw	utl_strlen						;24h
	DEFABS	UTILTBL_SIZE,<($ - UTILTBL) SHR 1>

DOS	ends

	end
