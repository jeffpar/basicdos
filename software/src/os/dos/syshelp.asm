;
; BASIC-DOS System Initialization Helpers
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; These functions are used only by SYSINIT (see sysinit.asm), and since this
; module is linked immediately after it, they are moved and recycled along
; with the rest of the system initialization code.
;
	BIOSAPI equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<sysinit_error,fatal_error>
	EXTWORD	<dos_seg,cfg_data,cfg_size,cbCacheData>
	EXTWORD	<init_data>
	EXTLONG	<pCacheInt21,pCacheData>

	DEFPTR	pCacheFile
	DEFPTR	pCacheActive
	DEFWORD	cbCacheActive
	DEFWORD	tbl_next		; offset of next table (see init_table)

	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_bpbtime
;
; Set the timestamp of a BPB to the current BIOS tick count (as the FDC and
; HDC drivers do whenever they access the media).
;
; Inputs:
;	DS:DI -> BPB
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	set_bpbtime
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is current tick count
	mov	[di].BPB_TIMESTAMP.OFF,dx
	mov	[di].BPB_TIMESTAMP.SEG,cx
	ret
ENDPROC	set_bpbtime

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_cfg
;
; Search for length-prefixed string at CS:SI in CFG_FILE, and if found,
; set DI to 1st character after match.
;
; Outputs:
;	Carry clear on success (DI -> 1st character after match)
;	Carry set on failure (AX = default value following string at SI)
;
; Modifies:
;	AX, SI, DI
;
DEFPROC	find_cfg
	ASSUME	DS:NOTHING, ES:NOTHING
	push	bx
	push	cx
	push	dx
	push	es
	push	ss			; (our data; see sysinit_high)
	pop	es
	ASSUME	ES:DOS
	mov	bx,si
	mov	di,[cfg_data]		; DI points to CFG_FILE data
	mov	dx,di
	add	dx,[cfg_size]		; DX points to end of CFG_FILE data
fc1:	lods	byte ptr cs:[si]	; 1st byte at CS:SI is length
	cbw
	xchg	cx,ax			; CX = length of string to find
	cli				; avoid 8086 string interrupt errata
	repe	cmps byte ptr cs:[si],es:[di]
	sti
	jne	fc2
	mov	es:[di-1],cl		; zap the CFG match to prevent reuse
	jmp	short fc9		; found it!
fc2:	add	si,cx			; move SI forward to the minimum value
	mov	al,0			; (CR and LF are now nulls)
	mov	cx,dx
	sub	cx,di			; CX = bytes left to search
	jb	fc8			; ran out
	repne	scasb
	stc
	jne	fc8			; couldn't find another line
	repe	scasb			; skip any more nulls (eg, CR+LF)
	stc
	je	fc8			; ran out
	dec	di			; DI -> 1st character of next line
	mov	si,bx
	jmp	fc1
fc8:	mov	ax,cs:[si]		; return the minimum value at SI
fc9:	pop	es
	ASSUME	ES:NOTHING
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	find_cfg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_table
;
; Initializes a table of AX entries of length DX at tbl_next (an offset in the
; DOS segment), stores the table's offset at [BX] and its limit at [BX+2] (in
; the DOS segment too), and advances tbl_next to the next paragraph.  This
; runs in sysinit's block (SS = its data), where tbl_next is.
;
; Outputs:
;	Nothing
;
; Modifies: CX, DX, DI
;
DEFPROC	init_table
	ASSUME	DS:NOTHING, ES:NOTHING
	push	ax
	push	es
	mov	es,[dos_seg]
	mul	dx			; AX = length of table in bytes
	xchg	cx,ax			; CX = length
	mov	di,ss:[tbl_next]	; ES:DI -> table
	mov	es:[bx].OFF,di		; save DS-relative offset
	mov	ax,di
	add	ax,cx			; does the table fit in the segment?
	jc	it8			; no
	add	ax,15
	jc	it8
	and	al,0F0h
	mov	ss:[tbl_next],ax
	mov	al,0
	rep	stosb			; zero the table
	mov	es:[bx].SEG,di		; save DS-relative limit
	pop	es
	pop	ax
	ret
it8:	jmp	sysinit_error		; no, sadly
ENDPROC	init_table

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cache_int21
;
; The sole purpose of this function is to intercept OPEN and READ requests
; that occur during our DOSUTIL LOAD operations, which we also know will be
; completely sequential (and therefore our caching logic can be very simple).
;
; This allows us to preload multiple copies of COMMAND.COM into memory without
; having to reread the file from disk every time.  Since we run on the caller's
; stack, we get our data segment (or selector) from init_data.
;
; Inputs:
;	AH = DOS function #
;
; Outputs:
;	Varies (function-specific)
;
DEFPROC	cache_int21,FAR
	cmp	ah,DOS_HDL_OPEN
	jne	ci2

	push	ax
	push	cx
	push	si
	push	di
	push	es
	mov	si,dx
	DOSUTIL	STRLEN			; AX = length of string at DS:SI
	xchg	cx,ax			; CX = length
	les	di,[pCacheFile]		; ES:DI -> previous filename, if any
	sub	ax,ax			; AX = 0 (no active cache data)
	test	di,di			; is there a previous filename?
	jz	ci1			; no
	repe	cmpsb			; does previous filename match current?
	jne	ci1			; no
	mov	ax,[pCacheData].OFF	; yes, init active cache data
ci1:	mov	es,cs:[init_data]
	ASSUME	ES:DOS
	mov	[pCacheActive].OFF,ax
	mov	ax,[pCacheData].SEG
	mov	[pCacheActive].SEG,ax
	mov	ax,[cbCacheData]
	mov	[cbCacheActive],ax
	mov	[pCacheFile].OFF,dx	; in any case, remember this filename
	mov	[pCacheFile].SEG,ds
	pop	es
	ASSUME	ES:NOTHING
	pop	di
	pop	si
	pop	cx
	pop	ax
	jmp	ci9

ci2:	cmp	ah,DOS_HDL_SEEK
	jne	ci4
	cmp	[pCacheActive].OFF,0	; is the cached file open?
	je	ci9			; no
;
; Only SEEK_BEG and SEEK_END are supported (with offsets in DX), since those
; are the only methods load_program uses.
;
	push	bx
	push	es
	mov	es,cs:[init_data]
	ASSUME	ES:DOS
	mov	bx,dx			; BX = offset
	sub	al,SEEK_END
	cmp	al,1			; carry set if SEEK_END
	sbb	ax,ax
	and	ax,[cbCacheData]
	add	bx,ax			; BX = new position
	mov	ax,[pCacheData].OFF
	add	ax,bx
	mov	[pCacheActive].OFF,ax
	mov	ax,[cbCacheData]
	sub	ax,bx
	mov	[cbCacheActive],ax
	xchg	ax,bx			; DX:AX = new position
	sub	dx,dx
	pop	es
	ASSUME	ES:NOTHING
	pop	bx
	jmp	short ci10		; (carry is clear)

ci4:	cmp	ah,DOS_HDL_READ
	jne	ci9

	push	cx
	push	si
	push	di
	push	ds
	push	es
	push	ds
	pop	es
	mov	di,dx			; ES:DI -> destination
	lds	si,[pCacheActive]	; DS:SI -> source data
	test	si,si			; does any source data exist?
	stc
	jz	ci8			; no
	mov	ax,cx			; AX = # bytes to copy
	cmp	ax,[cbCacheActive]	; do we have as much data as requested?
	jbe	ci3			; yes
	mov	ax,[cbCacheActive]	; no
ci3:	mov	cx,ax
	rep	movsb
	mov	es,cs:[init_data]
	ASSUME	ES:DOS
	sub	[cbCacheActive],ax
	add	[pCacheActive].OFF,ax
	ASSERT	NC
	ASSUME	ES:NOTHING
ci8:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	cx
	jnc	ci10

ci9:	pushf
	call	[pCacheInt21]
ci10:	ret	2
ENDPROC	cache_int21

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; open_dev
;
; Opens the device in a CONFIG.SYS setting (eg, "PRN=LPT2"), or if there's
; no such setting, the default device.  If the device can't be opened, the
; session has no such device (SFH_NODEV), which is reported for a setting
; but not for a default (eg, LPT1 on a machine without a parallel port).
;
; Inputs:
;	SI -> setting (eg, CFG_PRN)
;	DX -> default device (eg, "LPT1")
;
; Outputs:
;	AL = SFH, or SFH_NODEV
;
; Modifies:
;	AX, DX, SI, DI
;
DEFPROC	open_dev
	call	find_cfg		; look for the setting
	jc	od1			; not found
	mov	dx,di			; DX -> setting
od1:	sbb	si,si			; SI = -1 if not found, 0 if found
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jnc	od9
	inc	si			; was the device from a setting?
	jz	od8			; no
	call	open_warning
od8:	mov	al,SFH_NODEV
od9:	ret
ENDPROC	open_dev

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; open_warning (and open_error, which halts; moved here from SYSINIT
; to save symbol space there)
;
; Inputs:
;	AX = error code
;	DX -> device setting (eg, "COM2:9600,N,8,1")
;
; Modifies:
;	AX
;
DEFPROC	open_warning
	EPRINTF	<"Warning: unable to open %s">,<13,10>,ax,dx
	ret
ENDPROC	open_warning


	DEFLBL	open_error,near
	EPRINTF	<"Unable to open %s">,,ax,dx
	jmp	fatal_error

DOS	ends

	end
