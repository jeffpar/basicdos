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
; This must be the first object module; we reuse the fake INT 20h
; as mcb_head and overwrite the JMP with mcb_limit.
;
	DEFLBL	mcb_head,word
	int	20h			; fake DOS terminate call
	DEFLBL	mcb_limit,word
	jmp	sysinit

	DEFWORD	scb_active,0		; offset of active SCB (zero if none)
	DEFWORD	psp_active,0		; segment of active PSP (zero if none)
	DEFPTR	clk_ptr,-1		; pointer to CLOCK$ DDH
	DEFBYTE	scb_locked,<-1,4Ah>	; -1 if unlocked
	DEFBYTE	bpb_total,0		; total number of BPBs
	DEFBYTE	file_name,' ',11	; buffer for 11-character filename
	DEFBYTE	ddint_level,0		; device driver interrupt level

	DEFTBL	<bpb_table,scb_table,sfb_table>
;
; Constants
;
	DEFBYTE	VALID_CHARS,"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'()-@^_`{}~"
	DEFABS	VALID_COUNT,<$ - VALID_CHARS>
	DEFBYTE	STR_CTRLC,<CHR_CTRLC,CHR_RETURN,CHR_LINEFEED>
	DEFBYTE	STR_ESC,<"\",13,10>
	DEFBYTE	JAN,<"January",0>
	DEFBYTE	FEB,<"February",0>
	DEFBYTE	MAR,<"March",0>
	DEFBYTE	APR,<"April",0>
	DEFBYTE	MAY,<"May",0>
	DEFBYTE	JUN,<"June",0>
	DEFBYTE	JUL,<"July",0>
	DEFBYTE	AUG,<"August",0>
	DEFBYTE	SEP,<"September",0>
	DEFBYTE	OCT,<"October",0>
	DEFBYTE	NOV,<"November",0>
	DEFBYTE	DEC,<"December",0>
	DEFWORD	MONTHS,<JAN,FEB,MAR,APR,MAY,JUN,JUL,AUG,SEP,OCT,NOV,DEC>
	DEFBYTE	SUN,<"Sunday",0>
	DEFBYTE	MON,<"Monday",0>
	DEFBYTE	TUE,<"Tuesday",0>
	DEFBYTE	WED,<"Wednesday",0>
	DEFBYTE	THU,<"Thursday",0>
	DEFBYTE	FRI,<"Friday",0>
	DEFBYTE	SAT,<"Saturday",0>
	DEFWORD	DAYS,<SUN,MON,TUE,WED,THU,FRI,SAT>
	DEFBYTE	MONTH_DAYS,<31,28,31,30,31,30,31,31,30,31,30,31>

	EXTERNS	<psp_term>,near
	EXTERNS	<tty_echo,tty_write,aux_read,aux_write,prn_write,tty_io>,near
	EXTERNS	<tty_in,tty_read,tty_print,tty_input,tty_status,tty_flush>,near
	EXTERNS	<dsk_flush,dsk_getdrv,dsk_setdrv,dsk_setdta,dsk_getdta>,near
	EXTERNS	<dsk_ffirst,dsk_fnext>,near
	EXTERNS	<msc_setvec,msc_getver,msc_setctrlc,msc_getvec>,near
	EXTERNS	<psp_exec,psp_exit,psp_retcode,psp_create,psp_set,psp_get>,near
	EXTERNS	<hdl_open,hdl_close,hdl_read,hdl_write,hdl_seek>,near
	EXTERNS	<mem_alloc,mem_free,mem_realloc>,near
	EXTERNS	<utl_strlen,utl_strstr,utl_strupr,utl_atoi16,utl_atoi32>,near
	EXTERNS	<utl_itoa,utl_printf,utl_sprintf,utl_tokify,utl_tokid>,near
	EXTERNS	<utl_getdev,utl_ioctl,utl_load,utl_start,utl_stop,utl_unload>,near
	EXTERNS	<utl_yield,utl_sleep,utl_wait,utl_endwait,utl_hotkey>,near
	EXTERNS	<utl_lock,utl_unlock,utl_qrymem,utl_abort>,near
	EXTERNS	<func_none>,near

	DEFLBL	FUNCTBL,word
	dw	psp_term,    tty_echo,    tty_write,   aux_read		;00h-03h
	dw	aux_write,   prn_write,   tty_io,      tty_in		;04h-07h
	dw	tty_read,    tty_print,   tty_input,   tty_status	;08h-0Bh
	dw	tty_flush,   dsk_flush,   dsk_setdrv,  func_none	;0Ch-0Fh
	dw	func_none,   func_none,   func_none,   func_none	;10h-13h
	dw	func_none,   func_none,   func_none,   func_none	;14h-17h
	dw	func_none,   dsk_getdrv,  dsk_setdta,  func_none	;18h-1Bh
	dw	func_none,   func_none,   func_none,   func_none	;1Ch-1Fh
	dw	func_none,   func_none,   func_none,   func_none	;20h-23h
	dw	func_none,   msc_setvec,  psp_create,  func_none	;24h-27h
	dw	func_none,   func_none,   func_none,   func_none	;28h-2Bh
	dw	func_none,   func_none,   func_none,   dsk_getdta	;2Ch-2Fh
	dw	msc_getver,  func_none,   func_none,   msc_setctrlc	;30h-33h
	dw	func_none,   msc_getvec,  func_none,   func_none	;34h-37h
	dw	func_none,   func_none,   func_none,   func_none	;38h-3Bh
	dw	func_none,   hdl_open,    hdl_close,   hdl_read		;3Ch-3Fh
	dw	hdl_write,   func_none,   hdl_seek,    func_none	;40h-43h
	dw	func_none,   func_none,   func_none,   func_none	;44h-47h
	dw	mem_alloc,   mem_free,    mem_realloc, psp_exec		;48h-4Bh
	dw	psp_exit,    psp_retcode, dsk_ffirst,  dsk_fnext	;4Ch-4Fh
	dw	psp_set,     psp_get					;50h-51h
	DEFABS	FUNCTBL_SIZE,<($ - FUNCTBL) SHR 1>

	DEFLBL	UTILTBL,word
	dw	utl_strlen,  utl_strstr,  func_none,   utl_strupr	;00h-03h
	dw	func_none,   func_none,   utl_atoi16,  utl_atoi32	;04h-07h
	dw	utl_itoa,    utl_printf,  utl_sprintf, utl_tokify	;08h-0Bh
	dw	utl_tokid,   func_none,   func_none,   func_none	;0Ch-0Fh
	dw	utl_getdev,  utl_ioctl,   utl_load,    utl_start	;10h-13h
	dw	utl_stop,    utl_unload,  utl_yield,   utl_sleep	;14h-17h
	dw	utl_wait,    utl_endwait, utl_hotkey,  utl_lock		;18h-1Bh
	dw	utl_unlock,  utl_qrymem,  func_none,   utl_abort	;1Ch-1Fh
	dw	func_none,   func_none,   func_none,   func_none	;20h-23h
	dw	utl_strlen						;24h
	DEFABS	UTILTBL_SIZE,<($ - UTILTBL) SHR 1>

DOS	ends

	end
