;
; BASIC-DOS Resident Data Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	devapi.inc

	EXTNEAR	<sysinit>

DOS	segment word public 'CODE'
;
; This must be the first object module; sysinit will overwrite the fake
; INT 20h with buf_head and the JMP SYSINIT with clk_ptr.
;
	DEFLBL	buf_head,word		; 00h: head of buffer chain
	int	20h			; fake DOS terminate call @CS:0000h

	DEFLBL	clk_ptr,dword		; 02h: pointer to CLOCK$ DDH
	jmp	sysinit			; boot.asm assumes our entry @CS:0002h
	nop
;
; INT 21h function 52h (msc_getvars) returns ES:BX -> mcb_head + 2 (mcb_limit).
;
	DEFWORD	mcb_head,0		; 06h: 1st memory paragraph
	DEFWORD	mcb_limit,0		; 08h: 1st unavailable paragraph
	DEFTBL	<bpb_table,sfb_table,scb_table>
	DEFWORD	scb_active,0		; offset of active SCB (zero if none)
	DEFWORD	key_boot,0		; records key pressed at boot, if any
	EXTNEAR	scb_return
	DEFWORD	scb_stoked,<offset scb_return>
;
; scb_locked and int_level are required to be addressable as a single word.
;
	DEFBYTE	scb_locked,-1		; -1 if unlocked, >= 0 if locked
	DEFBYTE	int_level,-1		; device driver interrupt level

	DEFBYTE	bpb_total,0		; total number of BPBs
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

	EXTNEAR	<psp_term>
	EXTNEAR	<tty_echo,tty_write,aux_read,aux_write,prn_write,tty_io>
	EXTNEAR	<tty_in,tty_read,tty_print,tty_input,tty_status,tty_flush>
	EXTNEAR	<dsk_flush,dsk_getdrv,dsk_setdrv,dsk_setdta,dsk_getdta>
	EXTNEAR	<dsk_getinfo,dsk_ffirst,dsk_fnext>
	EXTNEAR	<fcb_open,fcb_close,fcb_sread,fcb_rread,fcb_setrel>
	EXTNEAR	<fcb_rbread,fcb_parse>
	EXTNEAR	<msc_getdate,msc_setdate,msc_gettime,msc_settime>
	EXTNEAR	<msc_setvec,msc_getver,msc_setctrlc,msc_getvec,msc_getswc>
	EXTNEAR	<msc_getvars,psp_exec,psp_return,psp_retcode>
	EXTNEAR	<psp_copy,psp_set,psp_get,psp_create>
	EXTNEAR	<hdl_open,hdl_close,hdl_read,hdl_write,hdl_seek,hdl_ioctl>
	EXTNEAR	<mem_alloc,mem_free,mem_realloc>
	EXTNEAR	<utl_strlen,utl_strstr,utl_strupr>
	EXTNEAR	<utl_atoi16,utl_atoi32,utl_atoi32d>
	EXTNEAR	<utl_atof64,utl_f64i32,utl_i32f64>
	EXTNEAR	<utl_itoa,utl_printf,utl_dprintf,utl_sprintf>
	EXTNEAR	<utl_tokify,utl_tokid,utl_parsesw>
	EXTNEAR	<utl_getdev,utl_getcsn,utl_load,utl_start,utl_stop,utl_end>
	EXTNEAR	<utl_waitend,utl_yield,utl_sleep,utl_wait,utl_endwait>
	EXTNEAR	<utl_hotkey,utl_lock,utl_unlock,utl_qrymem,utl_term>
	EXTNEAR	<utl_getdate,utl_gettime,utl_incdate,utl_editln,utl_restart>
	EXTNEAR	<func_none>

	DEFLBL	FUNCTBL,word
	dw	psp_term,    tty_echo,    tty_write,   aux_read		;00-03
	dw	aux_write,   prn_write,   tty_io,      tty_in		;04-07
	dw	tty_read,    tty_print,   tty_input,   tty_status	;08-0B
	dw	tty_flush,   dsk_flush,   dsk_setdrv,  fcb_open		;0C-0F
	dw	fcb_close,   func_none,   func_none,   func_none	;10-13
	dw	fcb_sread,   func_none,   func_none,   func_none	;14-17
	dw	func_none,   dsk_getdrv,  dsk_setdta,  func_none	;18-1B
	dw	func_none,   func_none,   func_none,   func_none	;1C-1F
	dw	func_none,   fcb_rread,   func_none,   func_none	;20-23
	dw	fcb_setrel,  msc_setvec,  psp_copy,    fcb_rbread	;24-27
	dw	func_none,   fcb_parse,   msc_getdate, msc_setdate	;28-2B
	dw	msc_gettime, msc_settime, func_none,   dsk_getdta	;2C-2F
	dw	msc_getver,  func_none,   func_none,   msc_setctrlc	;30-33
	dw	func_none,   msc_getvec,  dsk_getinfo, msc_getswc	;34-37
	dw	func_none,   func_none,   func_none,   func_none	;38-3B
	dw	func_none,   hdl_open,    hdl_close,   hdl_read		;3C-3F
	dw	hdl_write,   func_none,   hdl_seek,    func_none	;40-43
	dw	hdl_ioctl,   func_none,   func_none,   func_none	;44-47
	dw	mem_alloc,   mem_free,    mem_realloc, psp_exec		;48-4B
	dw	psp_return,  psp_retcode, dsk_ffirst,  dsk_fnext	;4C-4F
	dw	psp_set,     psp_get,     msc_getvars, func_none	;50-53
	dw	func_none,   psp_create					;54-55
	DEFABS	FUNCTBL_SIZE,<($ - FUNCTBL) SHR 1>

	DEFLBL	UTILTBL,word
	dw	utl_strlen,  utl_strstr,  func_none,   utl_strupr	;00-03
	dw	utl_printf,  utl_dprintf, utl_sprintf, utl_itoa		;04-07
	dw	utl_atoi16,  utl_atoi32,  utl_atoi32d, func_none	;08-0B
	dw	utl_atof64,  func_none,   utl_f64i32,  func_none	;0C-0F
	dw	utl_i32f64,  utl_tokify,  utl_tokify,  utl_tokid	;10-13
	dw	utl_parsesw, utl_getdev,  utl_getcsn,  func_none	;14-17
	dw	utl_load,    utl_start,   utl_stop,    utl_end		;18-1B
	dw	utl_waitend, utl_yield,   utl_sleep,   utl_wait		;1C-1F
	dw	utl_endwait, utl_hotkey,  utl_lock,    utl_unlock	;20-23
	dw	utl_strlen,  utl_qrymem,  utl_term,    utl_getdate	;24-27
	dw	utl_gettime, utl_incdate, utl_editln,  utl_restart	;28-2B
	DEFABS	UTILTBL_SIZE,<($ - UTILTBL) SHR 1>

DOS	ends

	end
