;
; BASIC-DOS Resident Data Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	devapi.inc

	EXTERNS	<sysinit>,near

DOS	segment word public 'CODE'
;
; This must be the first object module; we reuse the fake INT 20h as mcb_head
; and overwrite the JMP with mcb_limit.
;
	DEFLBL	mcb_head,word		; 1st memory paragraph
	int	20h			; fake DOS terminate call

	DEFLBL	clk_ptr,dword		; pointer to CLOCK$ DDH
	jmp	sysinit			; (msc_getvars assumes at mcb_head+2)
	nop

	DEFTBL	<bpb_table,sfb_table,scb_table>

	DEFWORD	mcb_limit,0		; 1st unavailable paragraph
	DEFWORD	scb_active,0		; offset of active SCB (zero if none)
	DEFWORD	buf_head,0		; head of buffer chain
	DEFWORD	key_boot,0		; records key pressed at boot, if any
	EXTERNS	scb_return,near
	DEFWORD	scb_stoked,<offset scb_return>
	DEFBYTE	scb_locked,-1		; -1 if unlocked, >=0 if locked
	DEFBYTE	bpb_total,0		; total number of BPBs
	DEFBYTE	ddint_level,0		; device driver interrupt level
	DEFBYTE	sfh_debug,-1		; system file handle for DEBUG device
	DEFBYTE	def_switchar,'/'
;
; Constants
;
	DEFSTR	FILENAME_CHARS,"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'()-@^_`{}~"
	DEFSTR	FILENAME_SEPS,<":;.,=+/[]\<>|",CHR_DQUOTE,CHR_SPACE,CHR_TAB>
	DEFSTR	STR_CTRLC,<CHR_CTRLC,CHR_RETURN,CHR_LINEFEED>
	DEFSTR	STR_ESC,<"\",13,10>
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
	EXTERNS	<dsk_getinfo,dsk_ffirst,dsk_fnext>,near
	EXTERNS	<fcb_open,fcb_close,fcb_sread,fcb_rread,fcb_setrrec>,near
	EXTERNS	<fcb_rbread,fcb_parse>,near
	EXTERNS	<msc_getdate,msc_setdate,msc_gettime,msc_settime>,near
	EXTERNS	<msc_setvec,msc_getver,msc_setctrlc,msc_getvec,msc_getswc>,near
	EXTERNS	<msc_getvars,psp_exec,psp_exit,psp_retcode>,near
	EXTERNS	<psp_copy,psp_set,psp_get,psp_create>,near
	EXTERNS	<hdl_open,hdl_close,hdl_read,hdl_write,hdl_seek,hdl_ioctl>,near
	EXTERNS	<mem_alloc,mem_free,mem_realloc>,near
	EXTERNS	<utl_strlen,utl_strstr,utl_strupr>,near
	EXTERNS	<utl_atoi16,utl_atoi32,utl_atoi32d>,near
	EXTERNS	<utl_itoa,utl_printf,utl_dprintf,utl_sprintf>,near
	EXTERNS	<utl_tokify,utl_tokid,utl_restart,utl_getdev,utl_ioctl>,near
	EXTERNS	<utl_load,utl_start,utl_stop,utl_end,utl_waitend>,near
	EXTERNS	<utl_yield,utl_sleep,utl_wait,utl_endwait,utl_hotkey>,near
	EXTERNS	<utl_lock,utl_unlock,utl_qrymem,utl_abort>,near
	EXTERNS	<utl_getdate,utl_gettime,utl_incdate,utl_editln>,near
	EXTERNS	<func_none>,near

	DEFLBL	FUNCTBL,word
	dw	psp_term,    tty_echo,    tty_write,   aux_read		;00h-03h
	dw	aux_write,   prn_write,   tty_io,      tty_in		;04h-07h
	dw	tty_read,    tty_print,   tty_input,   tty_status	;08h-0Bh
	dw	tty_flush,   dsk_flush,   dsk_setdrv,  fcb_open		;0Ch-0Fh
	dw	fcb_close,   func_none,   func_none,   func_none	;10h-13h
	dw	fcb_sread,   func_none,   func_none,   func_none	;14h-17h
	dw	func_none,   dsk_getdrv,  dsk_setdta,  func_none	;18h-1Bh
	dw	func_none,   func_none,   func_none,   func_none	;1Ch-1Fh
	dw	func_none,   fcb_rread,   func_none,   func_none	;20h-23h
	dw	fcb_setrrec, msc_setvec,  psp_copy,    fcb_rbread	;24h-27h
	dw	func_none,   fcb_parse,   msc_getdate, msc_setdate	;28h-2Bh
	dw	msc_gettime, msc_settime, func_none,   dsk_getdta	;2Ch-2Fh
	dw	msc_getver,  func_none,   func_none,   msc_setctrlc	;30h-33h
	dw	func_none,   msc_getvec,  dsk_getinfo, msc_getswc	;34h-37h
	dw	func_none,   func_none,   func_none,   func_none	;38h-3Bh
	dw	func_none,   hdl_open,    hdl_close,   hdl_read		;3Ch-3Fh
	dw	hdl_write,   func_none,   hdl_seek,    func_none	;40h-43h
	dw	hdl_ioctl,   func_none,   func_none,   func_none	;44h-47h
	dw	mem_alloc,   mem_free,    mem_realloc, psp_exec		;48h-4Bh
	dw	psp_exit,    psp_retcode, dsk_ffirst,  dsk_fnext	;4Ch-4Fh
	dw	psp_set,     psp_get,     msc_getvars, func_none	;50h-53h
	dw	func_none,   psp_create					;54h-55h
	DEFABS	FUNCTBL_SIZE,<($ - FUNCTBL) SHR 1>

	DEFLBL	UTILTBL,word
	dw	utl_strlen,  utl_strstr,  func_none,   utl_strupr	;00h-03h
	dw	utl_printf,  utl_dprintf, utl_sprintf, utl_itoa		;04h-07h
	dw	utl_atoi16,  utl_atoi32,  utl_atoi32d, utl_tokify	;08h-0Bh
	dw	utl_tokify,  utl_tokid,   utl_restart, utl_getdev	;0Ch-0Fh
	dw	utl_ioctl,   utl_load,    utl_start,   utl_stop		;10h-13h
	dw	utl_end,     utl_waitend, utl_yield,   utl_sleep	;14h-17h
	dw	utl_wait,    utl_endwait, utl_hotkey,  utl_lock		;18h-1Bh
	dw	utl_unlock,  utl_qrymem,  func_none,   utl_abort	;1Ch-1Fh
	dw	utl_getdate, utl_gettime, utl_incdate, utl_editln	;20h-23h
	dw	utl_strlen						;24h
	DEFABS	UTILTBL_SIZE,<($ - UTILTBL) SHR 1>

DOS	ends

	end
