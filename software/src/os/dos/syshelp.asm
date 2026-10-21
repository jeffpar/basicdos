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
	EXTLONG	<pCacheInt21,pCacheData>

	DEFPTR	pCacheFile
	DEFPTR	pCacheActive
	DEFWORD	cbCacheActive

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
	push	cs
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
; Initializes table with AX entries of length DX at ES:0, stores DOS segment-
; relative table offset at [BX], table limit at [BX+2], and finally adjusts ES.
;
; Outputs:
;	Nothing
;
; Modifies: CX, DX, DI
;
DEFPROC	init_table
	ASSUME	DS:NOTHING, ES:NOTHING
	push	ax
	mul	dx			; AX = length of table in bytes
	xchg	cx,ax			; CX = length
	sub	di,di
	mov	ax,di
	rep	stosb			; zero the table
	push	ds
	mov	ds,[dos_seg]
	mov	ax,es
	mov	dx,ds
	sub	ax,dx			; AX = distance from DS:0 in paras
	mov	dx,ax			; save for DS overflow check
	mov	cl,4
	shl	ax,cl			; AX = DS-relative offset
	mov	[bx].OFF,ax		; save DS-relative offset
	add	ax,di
	mov	[bx].SEG,ax		; save DS-relative limit
	pop	ds
	add	di,15
	mov	cl,4
	shr	di,cl			; DI = length of table in paras
	add	dx,di			; check for DS overflow
	cmp	dx,1000h		; have we exceeded the DS 64K limit?
	jbe	it9			; no
	jmp	sysinit_error		; yes, sadly
it9:
	mov	ax,es
	add	ax,di
	mov	es,ax			; ES = next available paragraph
	pop	ax
	ret
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
; having to reread the file from disk every time.
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
	sub	ax,ax
	mov	[pCacheActive].OFF,ax	; no active cache data yet
	DOSUTIL	STRLEN			; AX = length of string at DS:SI
	xchg	cx,ax			; CX = length
	les	di,[pCacheFile]		; ES:DI -> previous filename, if any
	test	di,di			; is there a previous filename?
	jz	ci1			; no
	repe	cmpsb			; does previous filename match current?
	jne	ci1			; no
	mov	ax,[pCacheData].OFF	; yes, init active cache data
	mov	[pCacheActive].OFF,ax
	mov	ax,[pCacheData].SEG
	mov	[pCacheActive].SEG,ax
	mov	ax,[cbCacheData]
	mov	[cbCacheActive],ax
ci1:	mov	[pCacheFile].OFF,dx	; in any case, remember this filename
	mov	[pCacheFile].SEG,ds
	pop	es
	pop	di
	pop	si
	pop	cx
	pop	ax
	jmp	short ci9

ci2:	cmp	ah,DOS_HDL_SEEK
	jne	ci4
	cmp	[pCacheActive].OFF,0	; is the cached file open?
	je	ci9			; no
;
; Only SEEK_BEG and SEEK_END are supported (with offsets in DX), since those
; are the only methods load_program uses.
;
	push	bx
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
	sub	[cbCacheActive],ax
	add	[pCacheActive].OFF,ax
	ASSERT	NC
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
; console_warning (and open_error, which halts; moved here from SYSINIT
; to save symbol space there)
;
; Inputs:
;	AX = error code
;	DX -> CONSOLE setting
;
; Modifies:
;	AX
;
DEFPROC	console_warning
	EPRINTF	<"Warning: unable to open console %s">,<13,10>,ax,dx
	ret
ENDPROC	console_warning


	DEFLBL	open_error,near
	EPRINTF	<"Unable to open %s">,,ax,dx
	jmp	fatal_error

DOS	ends

	end
