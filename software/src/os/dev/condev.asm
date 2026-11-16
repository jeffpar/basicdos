;
; BASIC-DOS Video and Keyboard (VKD$) Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	BIOSAPI equ 1
	BIOSKEY equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc
	include	condev.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

;
; The rest of the driver (see convid.asm), which is linked after this module.
;
	EXTNEAR	<chk_blocked,chk_context,chk_graphics,chk_vpage,get_frame>
	EXTNEAR	<get_sesctx,scroll,set_curtype,set_geometry,set_slot>
	EXTNEAR	<slot_addr,swap_page,switch_focus,switch_to,unlock_bios>
	EXTNEAR	<chk_opt,set_pmode>
	EXTNEAR	<ddcon_setkeys,kbd_update>
	EXTNEAR	<update_biosdata,update_context,update_curtype,update_mode>
	EXTNEAR	<video_ctx,wait_focus,write_char,write_context,write_crtc16>
	EXTNEAR	<write_curpos,get_vbuf>
	extrn	ddcon_init:far

	public	VKD
VKD	DDH	<offset DEV:ddcon_end+16,,DDATTR_STDIN+DDATTR_STDOUT+DDATTR_OPEN+DDATTR_CHAR,offset ddcon_init,-1,2020202024444B56h>

	DEFLBL	CMDTBL,word
	dw	ddcon_none,   ddcon_none,   ddcon_none,   ddcon_ioctl	; 00-03
	dw	ddcon_read,   ddcon_none,   ddcon_none,   ddcon_inflush	; 04-07
	dw	ddcon_write,  ddcon_none,   ddcon_none,   ddcon_outflush; 08-0B
	dw	ddcon_none,   ddcon_open,   ddcon_close			; 0C-0E
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFLBL	IOCTBL,word
	dw	ddcon_getdd,  ddcon_none,   ddcon_none,   ddcon_none	; 00-03
	dw	ddcon_none,   ddcon_none,   ddcon_none,   ddcon_none	; 04-07
	dw	ddcon_none,   ddcon_getdim, ddcon_getpos, ddcon_getlen	; D0-D3
	dw	ddcon_movcur, ddcon_setins, ddcon_scroll, ddcon_getclr	; D4-D7
	dw	ddcon_setclr, ddcon_setpos, ddcon_getmode,ddcon_setmode	; D8-DB
	dw	ddcon_getchar,ddcon_setkeys				; DC-DD
	DEFABS	IOCTBL_SIZE,<($ - IOCTBL) SHR 1>

	DEFLBL	CON_PARMS,word
	dw	80,16,80, 25,4,25
	dw	0,0,1, 0,0,2, 0,0,1

	DEFLBL	DBL_BORDER,word
	dw	0C9BBh,0BABAh,0C8BCh,0CDCDh

	DEFLBL	SGL_BORDER,word
	dw	0DABFh,0B3B3h,0C0D9h,0C4C4h

	DEFWORD	ct_head,0	; head of context chain
	DEFWORD	ct_focus,0	; segment of context with focus
	DEFWORD	mode_ctx,0	; context not in its original mode
	DEFWORD	frame_seg,0	; frame buffer segment of PRIMARY adapter
	DEFBYTE	max_rows,25	; TODO: use this for something...
	DEFBYTE	max_cols,80	; TODO: set to correct value in ddcon_init
	DEFBYTE	bios_lock,0	; non-zero if BIOS lock in effect
	DEFBYTE	req_switch,0	; non-zero if a context switch is requested
	DEFBYTE	one_con,0	; non-zero if only one console (see con_opt)
	DEFBYTE	adapters,0	; video adapters present (see ADAPTER_*)
	DEFWORD	bios_ctx,0	; context for our own INT 10h call (see scroll)
;
; Where the next context goes on each adapter (primary, then alternate; see
; ddcon_open): the position (X,Y) of its top left, followed by its page (LO)
; and the adapter's number of pages (HI), which ddcon_init sets to 1 for an
; MDA (a CGA has 4 pages of 4K each).  Pages beyond those are virtual pages,
; kept in system memory (see swap_page).
;
	DEFWORD	con_place,<0,0400h,0,0400h>
;
; The page that each adapter is displaying, followed by its text mode (see
; show_page), indexed like con_place (so only bytes 0, 1, 4, and 5 are
; used).  ddcon_init sets the primary adapter's mode, and an alternate MDA's;
; an alternate CGA starts in MODE_CO80 (see ddcon_open).
;
	DEFBYTE	shown_page,<0,0,0,0,0,MODE_CO80>

	DEFPTR	kbd_int,0	; original keyboard hardware interrupt handler
	DEFPTR	video_int,0	; original video services interrupt handler
	DEFPTR	wait_ptr,0FFFFh,0	; chain of waiting packets (none)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;	Varies
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_req,far
	mov	di,bx			; ES:DI -> DDP
	mov	bl,es:[di].DDP_CMD
	cmp	bl,CMDTBL_SIZE
	jb	ddq1
	mov	bl,0
ddq1:	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	bh,0
	add	bx,bx
	call	CMDTBL[bx]
	ret
ENDPROC	ddcon_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_ioctl
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;	Varies
;
; Modifies:
;	AX, BX, CX, DX, DS
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_ioctl
	mov	bl,es:[di].DDP_CODE	; IOCTL code from DDP_CODE
	cmp	bl,IOCTL_OUTSTATUS	; standard sub-function code?
	jbe	dio1			; yes
	sub	bl,IOCTL_CON - 8	; no, BASIC-DOS specific sub-function
dio1:	mov	dx,es:[di].DDP_CONTEXT
	test	dx,dx			; was a context provided?
	jz	dio2			; no, force call to ddcon_none
	mov	ds,dx
	ASSUME	DS:NOTHING
	cmp	bl,IOCTBL_SIZE		; table entry exist?
	jae	dio2			; no
;
; IOCTLs that draw on the screen (eg, a CLS or COLOR from another session)
; must wait while the context is blocked (see chk_blocked).
;
	cmp	bl,IOCTL_SCROLL - (IOCTL_CON - 8)
	je	dio1a
	cmp	bl,IOCTL_SETCOLOR - (IOCTL_CON - 8)
	je	dio1a
	cmp	bl,IOCTL_SETPOS - (IOCTL_CON - 8)
	je	dio1a			; (it can erase; see ddcon_setpos)
	cmp	bl,IOCTL_SETMODE - (IOCTL_CON - 8)
	jne	dio3
dio1a:	mov	ax,ds
	call	chk_blocked		; is another context blocking us?
	jnc	dio1b			; no
	push	bx
	call	add_packet		; yes, so wait (as ddcon_write does)
	pop	bx
	jnc	dio1a			; check again
dio1c:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_WRFAULT
	ret
;
; A mode change affects the entire screen, so it also waits until the context
; has focus (see wait_focus).
;
dio1b:	cmp	bl,IOCTL_SETMODE - (IOCTL_CON - 8)
	jne	dio3
	mov	cx,es:[di].DDPRW_LENGTH	; CL = mode, CH = rows
	call	chk_vmode		; does the screen's mode change?
	jnc	dio3			; no, so there's no need for focus
	inc	cl			; (nor does a request of -1 need it,
	jz	dio3			; which never changes the mode)
	mov	ax,ds			; AX = context again
	cli
	call	wait_focus
	sti
	je	dio3			; no wait was needed
	jnc	dio1a			; the wait ended, so check again
	jmp	dio1c			; the wait was interrupted
dio2:	mov	bl,8			; no, use entry for C0h (ddcon_none)
dio3:	mov	bh,0
	add	bx,bx
	mov	cx,es:[di].DDPRW_LENGTH	; CX = IOCTL input value
	mov	dx,es:[di].DDPRW_LBA	; DX = IOCTL input value
	push	di			; some of the IOCTL subfunctions
	push	es			; modify DI and ES, so we save them
	call	IOCTBL[bx]
	pop	es
	pop	di
	jc	dio9
dio7:	mov	es:[di].DDP_CONTEXT,dx	; return pos or length in packet context
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dio9:	ret
ENDPROC	ddcon_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getdd (AL = 00h: Get Device Data)
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = CONSOLE context
;
; Outputs:
;	DX = device data bits
;
; Modifies:
;	DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getdd
;
; This is enough to make PC DOS 2.00 BASICA start successfully on BASIC-DOS.
; I haven't checked but it's probably verifying STDIN/STDOUT wasn't redirected.
;
	; mov	dx,[VKD].DDH_ATTR	; TODO: PC DOS 2.00 returns 80D3h
	mov	dx,80D3h
	ret
ENDPROC	ddcon_getdd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getdim
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = CONSOLE context
;
; Outputs:
;	DL = # columns
;	DH = # rows
;
; Modifies:
;	DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getdim
	mov	dx,ds:[CT_CURDIM]
	ret
ENDPROC	ddcon_getdim

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getpos
;
; This IOCTL is used in conjunction with IOCTL_GETLEN to obtain the display
; length of a series of bytes (up to 255).  Generally, all the caller cares
; about is the column, which is then passed to IOCTL_GETLEN.
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = CONSOLE context
;
; Outputs:
;	DX = current cursor position (DL = col, DH = row), zero-based.
;
; Modifies:
;	DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getpos
	mov	dx,ds:[CT_CURPOS]	; DX = current cursor position
	sub	dx,ds:[CT_CURMIN]	; make both row and col zero-based
	ret
ENDPROC	ddcon_getpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getchar (IOCTL_GETCHAR)
;
; Returns the character and attributes at a position in the context (for the
; SCREEN function).  A context using INT 10h passthrough (which includes every
; graphics mode) reads them with INT 10h, whose graphics mode support matches
; the pixels against the ROM font, and then restores the cursor.
;
; Inputs:
;	ES:DI -> DDPRW
;	CL = col, CH = row (zero-based)
;	DS = CONSOLE context
;
; Outputs:
;	If carry clear, DL = character, DH = attributes; carry set if the
;	position is outside the context
;
; Modifies:
;	AX, BX, DX, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getchar
	mov	dx,ds:[CT_CURMAX]
	sub	dx,ds:[CT_CURMIN]	; DL, DH = max col, row (zero-based)
	cmp	cl,dl
	ja	dgr8
	cmp	ch,dh
	ja	dgr8
	mov	dx,cx
	add	dx,ds:[CT_CURMIN]	; DL, DH = col, row in the context
	test	ds:[CT_STATUS],CTSTAT_INT10
	jnz	dgr5
	call	get_curpos		; BX = screen offset for (DL,DH)
	cli				; (see write_curpos)
	les	di,ds:[CT_SCREEN]	; ES:DI -> screen location
	mov	dx,es:[di+bx]		; DL = character, DH = attributes
	sti
	clc
	ret
dgr5:	add	dx,ds:[CT_CONPOS]	; DL = screen col, DH = screen row
	mov	bh,ds:[CT_PAGE]		; BH = display page
	mov	ah,VIDEO_SETCPOS
	call	video_ctx
	mov	ah,08h			; AL = character, AH = attributes
	call	video_ctx		; (read char and attributes)
	push	ax
	call	draw_cursor		; restore the cursor
	pop	dx
	clc
	ret
dgr8:	stc
	ret
ENDPROC	ddcon_getchar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getlen
;
; This IOCTL returns the display length of a series of bytes (up to 255).
;
; This assists DOS function DOS_TTY_INPUT (AH = 0Ah), which cannot accurately
; erase TAB characters (or the entire buffer) without knowing both the starting
; position (from IOCTL_GETPOS) and the display length of the buffer.
;
; TAB characters are more complicated than usual, since the total number of
; columns in a context are not always multiples of 8, and tabs must always wrap
; to column 1 on the following line.
;
; Inputs:
;	ES:DI -> DDPRW
;	CX = number of bytes (up to 255)
;	DX = starting cursor position; see IOCTL_GETPOS
;	DS = CONSOLE context
;
; Outputs:
;	DH = total display length, DL = length delta (of the final character)
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getlen
	mov	bx,dx			; BX = starting cursor position
	add	bx,ds:[CT_CURMIN]	; zero-based, so adjust to our mins
	sub	dx,dx			; DL = current len, DH = previous len
	mov	ah,ds:[CT_CURMAX].LOB	; AH = column max
	mov	bh,ds:[CT_CURMIN].LOB	; BH = column min
	lds	si,es:[di].DDPRW_ADDR
	mov	ch,0			; CL = length (255 character maximum)
	jcxz	dgl9			; nothing to do
	ASSUME	DS:NOTHING

dgl2:	lodsb
	mov	dh,dl			; current len -> previous len
	cmp	al,CHR_TAB
	jne	dgl4
	mov	al,bl			; for CHR_TAB
	sub	al,bh			; mimic write_context's TAB logic
	and	al,07h
	neg	al
	add	al,8			; AL = # output chars
dgl3:	inc	bl
	inc	dl
	cmp	bl,ah			; column still below limit?
	jbe	dgl3a			; yes
	mov	bl,bh			; no, so reset column and stop
	jmp	short dgl5
dgl3a:	dec	al
	jnz	dgl3
	jmp	short dgl5

dgl4:	cmp	al,CHR_SPACE		; CONTROL character?
	mov	al,1			; AL = # output chars
	jae	dgl4a			; no
	inc	ax			; add 1 for the "^" (see con_out)
dgl4a:	inc	bl			; advance the column
	inc	dl			; advance the length
	cmp	bl,ah			; column still below limit?
	jbe	dgl4b			; yes
	mov	bl,bh			; no, so reset column and keep going
dgl4b:	dec	al
	jnz	dgl4a

dgl5:	loop	dgl2
	sub	dl,dh			; DL = length delta for final character
	add	dh,dl			; DH = total length

dgl9:	ret
ENDPROC	ddcon_getlen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_movcur
;
; Inputs:
;	ES:DI -> DDPRW
;	CX = +/- columns to move cursor horizontally
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_movcur
	call	move_cursor
	ret
ENDPROC	ddcon_movcur

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_setins
;
; NOTE: There is no "insert mode" flag; the mode is considered OFF (0)
; if bits 0-4 of CT_CURTYPE.HIB are set, and ON (1) if bits 0-4 are clear.
;
; Inputs:
;	ES:DI -> DDPRW
;	CX = 0 to clear insert mode, 1 to set
;	DS = CONSOLE context
;
; Outputs:
;	DX = previous insert mode (0 if cleared, 1 if set)
;
; Modifies:
;	AX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_setins
	mov	ax,ds:[CT_DEFTYPE]
	ror	cl,1			; move CL bit 0 to bit 7 (and carry)
	jnc	dsi1			; "insert mode" requested?
	and	ah,0E0h			; yes, clear bits 0-4 of CT_CURTYPE.HIB
dsi1:	xchg	ds:[CT_CURTYPE],ax	; AX = previous CT_CURTYPE
	sub	dx,dx
	test	ah,1Fh			; were bits 0-4 clear?
	jnz	dsi2			; no, DX = 0
	inc	dx			; yes, DX = 1

	DEFLBL	focus_curtype,near
;
; Lock the BIOS first, so that a focus switch at interrupt time can't come
; between the focus check and the BIOS call (which would give the new focus
; context our cursor type) or in the middle of the BIOS's 6845 writes.
;
dsi2:	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	inc	[bios_lock]
	pop	ds
	ASSUME	DS:NOTHING
	mov	ax,ds
	cmp	ax,[ct_focus]		; does this context have focus?
	jne	dsi9			; no, leave cursor alone
	call	set_curtype		; update CT_CURTYPE
dsi9:	call	unlock_bios
	clc				; (ddcon_ioctl requires carry clear)
	ret
ENDPROC	ddcon_setins

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_scroll
;
; Scrolls or clears the context's scrolling rows, which are all the rows of
; its interior, unless CX = 0 and DX is non-zero, which sets them instead:
; a LINEFEED on the last scrolling row then scrolls only those rows.  The
; cursor can still be moved to any row (eg, to update a status row); changing
; the video mode makes every row a scrolling row again (see set_geometry).
;
; Inputs:
;	ES:DI -> DDPRW
;	CX = +/- lines to scroll, 0 to clear
;	DX = 0, or if CX = 0, the scrolling rows to set: DL = first row
;	(zero-based) and DH = last row + 1
;	DS = CONSOLE context
;
; Outputs:
;	Carry set if the rows are outside the context; in all other cases,
;	the cursor is moved to the first scrolling row
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_scroll
	test	cx,cx			; clearing the scrolling rows?
	jnz	dcs1			; no
	test	dx,dx			; setting them?
	jnz	dcs3			; yes
	call	draw_border		; good idea to redraw border, too
	mov	cl,100
dcs1:	call	scroll
	cmp	cl,100
	jne	dcs9
dcs2:	mov	dx,ds:[CT_SCRMIN]
	call	update_cursor
dcs9:	ret
dcs3:	cmp	dl,dh			; is there at least one row?
	jae	dcs7			; no
	cmp	dh,ds:[CT_CURDIM].HIB	; do they end below the interior?
	ja	dcs7			; yes
	mov	al,ds:[CT_CURMIN].HIB
	add	dl,al			; DL = first row in the context
	add	dh,al
	dec	dh			; DH = last row in the context
	mov	ds:[CT_SCRMIN].HIB,dl
	mov	ds:[CT_SCRMAX].HIB,dh
	jmp	dcs2
dcs7:	jmp	ddcon_none
ENDPROC	ddcon_scroll

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getclr
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = CONSOLE context
;
; Outputs:
;	DL = fill attributes
;	DH = border attributes
;
; In graphics modes, DL contains the background color (low nibble) and
; palette (high nibble) instead; see ddcon_setclr.
;
; Modifies:
;	AH, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getclr
	mov	dx,ds:[CT_COLOR]
	call	chk_graphics		; graphics mode?
	jnc	dgc9			; no
	mov	dl,dh			; yes, return background and palette
dgc9:	ret
ENDPROC	ddcon_getclr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_setclr
;
; Inputs:
;	ES:DI -> DDPRW
;	CL = fill attributes
;	CH = border attributes
;	DL, DH = the bits of CL, CH to set (the other bits keep their current
;	values, so a caller needn't get them first; see IOCTL_GETCOLOR)
;	DS = CONSOLE context
;
; In graphics modes, the low nibble of CL is the background color and the
; high nibble is the palette (only bit 0 matters), and CH is ignored; text
; is always drawn in color 3, so we save these values in CT_COLOR.HIB, which
; is otherwise unused, since graphics mode contexts have no border.
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_setclr
	mov	bx,dx			; BX = bits to set
	call	ddcon_getclr		; DX = current attributes
	xor	cx,dx
	and	cx,bx
	xor	cx,dx			; CX = attributes with those bits set
	call	chk_graphics		; graphics mode?
	jc	sc5			; yes
	mov	ax,cx
	xchg	ds:[CT_COLOR],ax
	cmp	ah,ch			; border color changed?
	je	sc9			; no
	call	draw_border
sc9:	ret

sc5:	mov	ds:[CT_COLOR].HIB,cl
	mov	bl,cl
	and	bl,0Fh			; BL = background color
	mov	bh,0			; BH = 0 (set background)
	call	set_palette
	mov	bx,0100h		; BH = 1 (set palette), BL = 0
	test	cl,10h			; palette 1?
	jz	set_palette		; no
	inc	bx			; yes
	DEFLBL	set_palette,near
	mov	ah,VIDEO_SETPAL
	jmp	video_ctx		; (with the context's BIOS data)
ENDPROC	ddcon_setclr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_setpos
;
; Inputs:
;	ES:DI -> DDPRW
;	CL = col, CH = row (zero-based, like IOCTL_GETPOS), or -1 to keep
;	the current col or row
;	DL = 0 to hide the cursor, 1 to show it, or any other value to
;	leave it alone
;	DH = 1 to erase from the new position to the end of the row
;	DS = CONSOLE context
;
; Outputs:
;	Carry set if the position is outside the context (DDERR_SEEK)
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_setpos
	mov	ax,ds:[CT_CURPOS]
	sub	ax,ds:[CT_CURMIN]	; AL = current col, AH = current row
	cmp	cl,-1			; keep the current col?
	jne	dsp0b			; no
	mov	cl,al
dsp0b:	cmp	ch,-1			; keep the current row?
	jne	dsp0c			; no
	mov	ch,ah
dsp0c:	cmp	cl,ds:[CT_CURDIM].LOB
	jae	dsp8
	cmp	ch,ds:[CT_CURDIM].HIB
	jae	dsp8
	push	dx
	mov	bx,dx
	mov	dx,cx
	add	dx,ds:[CT_CURMIN]	; DX = new cursor position
	dec	bh			; erase to the end of the row?
	jnz	dsp0			; no
	push	dx
	mov	cl,CHR_SPACE
	mov	ah,ds:[CT_COLOR].LOB	; AH = attributes
dsp0a:	call	write_curpos		; (as draw_char does)
	inc	dx
	cmp	dl,ds:[CT_CURMAX].LOB
	jle	dsp0a
	pop	dx
dsp0:	call	update_cursor		; (which also clears carry)
	pop	dx
	cmp	dl,1			; change the cursor's visibility?
	ja	dsp9			; no
;
; Like ddcon_setins, we start with the default cursor type; to hide the
; cursor, we set bit 5 of the top scan line (the 6845's "no cursor" mode).
; As a result, the next IOCTL_SETINS (eg, from the DOS line editor) makes
; the cursor visible again, which is how BASIC's LOCATE ,,0 behaves, too.
;
	mov	ax,ds:[CT_DEFTYPE]
	test	dl,dl			; hide the cursor?
	jnz	dsp1			; no
	or	ah,20h			; yes
dsp1:	mov	ds:[CT_CURTYPE],ax
	jmp	focus_curtype		; update the cursor if we have focus
dsp8:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_SEEK
	stc
dsp9:	ret
ENDPROC	ddcon_setpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getmode
;
; Returns the context's video mode, or (if CL is 1) the segment of its video
; memory, which is all a program needs to draw directly (eg, the graphics
; statements; see gfxInit).  In protected mode, that's an LDT selector of the
; context's own (see set_slot), so that we can take it away while another
; context is using the screen; the context's sessions share its LDT (see
; SCB_LDT).  If CL is 2, it returns the number of contexts instead, and
; whether this one has focus (eg, so that COMMAND.COM can mention SHIFT-TAB,
; which switches between them, only on the console that the user sees).
;
; Inputs:
;	ES:DI -> DDPRW
;	CL = 0 for the video mode, 1 for the video memory, 2 for the number of
;	contexts
;	DS = CONSOLE context
;
; Outputs:
;	DL = video mode, DX = segment (or selector) of video memory, or DL =
;	number of contexts and DH = 1 if this context has focus (0 if not)
;
; Modifies:
;	AX, BX, CX, DX, DS
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getmode
	mov	dl,ds:[CT_VMODE]
	dec	dl			; is there a virtual mode?
	jns	dgm0a			; yes, so that's the context's mode
	mov	dl,ds:[CT_MODE]
dgm0a:	dec	cl			; video memory instead?
	jz	dgm0			; yes
	dec	cl			; the number of contexts?
	jnz	dgm9			; no
	sub	dx,dx
	mov	ax,ds
	cmp	ax,[ct_focus]		; does this context have focus?
	jne	dgn0			; no
	inc	dh			; yes (DH = 1)
dgn0:	mov	cx,[ct_head]
dgn1:	jcxz	dgm9
	inc	dx
	mov	ds,cx
	mov	cx,ds:[CT_NEXT]
	jmp	dgn1
dgm0:	mov	dx,ds:[CT_SLOT]
	test	dx,dx			; does it have a selector yet?
	jnz	dgm3			; yes
	push	si
	push	di			; (ES:DI -> DDPRW, for ddcon_none)
	call	slot_addr		; DX:CX = address, SI:DI = length
	mov	ax,(CPU_MAP SHL 8) OR MEMF_LDT OR MEMF_USER
	call	far ptr DDINT_CPU	; AX = selector (or segment), DX = ID
	jc	dgm8
	test	al,4			; the segment itself (real mode)?
	jz	dgm1			; yes (an LDT selector has TI set)
	mov	ds:[CT_SLOT],dx
	push	dx
	call	set_slot		; (not present, if we're blocked)
	pop	dx
	pop	di
	pop	si
dgm3:	mov	dh,0
	mov	cl,3
	shl	dx,cl
	or	dl,7			; DX = its selector (LDT, RPL 3)
	ret
dgm1:	pop	di
	pop	si
	xchg	dx,ax			; DX = segment
dgm9:	ret
dgm8:	pop	di
	pop	si
	jmp	ddcon_none
ENDPROC	ddcon_getmode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_setmode
;
; Sets a new video mode (0-6 on a CGA, or 7 on an MDA, where modes 2 and 3
; are treated as 7 as well) for the context's adapter.  The new mode affects
; the entire screen, so the context becomes a full-screen context (see
; update_mode), unless the mode is virtual (see chk_vmode): then the screen's
; mode stays the same, and the context is simply cleared, without its border
; (or with it again, when the original mode is requested).
;
; A text mode (0-3) can also have 43 rows on an EGA or VGA, or 50 rows on a
; VGA, using the adapter's 8x8 font, which update_mode loads as soon as the
; mode is set (see CT_ROWS).  A VGA displays 350 scan lines for 43 rows and
; 400 for 50, which it must be told before the mode is set; only its BIOS has
; that function, so that's also how we know that it's a VGA.
;
; Inputs:
;	ES:DI -> DDPRW
;	CL = video mode
;	CH = rows (0 or 25 for the mode's usual 25 rows, or 43 or 50)
;	DS = CONSOLE context
;
; Outputs:
;	Carry set if the mode or rows aren't supported by the adapter
;
; Modifies:
;	AX, BX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_setmode
	call	chk_vmode		; does the screen's mode change?
	jc	dsm0			; yes
	mov	bh,0			; BH = no border
	mov	al,cl
	inc	ax			; AL = virtual mode + 1
	cmp	cl,ds:[CT_MODE]		; is the original mode requested?
	jne	dsm0a			; no
	mov	bh,ds:[CTO_STATUS]	; yes, so the border (if any) returns
	mov	al,0
dsm0a:	mov	ds:[CT_VMODE],al
	mov	cx,ds:[CTO_DIM]
	mov	dx,ds:[CTO_POS]
	mov	al,ds:[CT_STATUS]
	and	al,NOT CTSTAT_BORDER
	or	al,bh
	mov	ds:[CT_STATUS],al
	call	set_geometry
	mov	cl,0
	call	scroll			; clear the entire context
	call	draw_border
	mov	dx,ds:[CT_CURMIN]
	jmp	update_cursor		; home the cursor (and clear carry)
dsm0:	cmp	ds:[CT_PORT].LOB,0B4h	; monochrome adapter?
	jne	dsm1			; no
	cmp	cl,MODE_MONO
	je	dsm2
	sub	cl,2
	cmp	cl,1			; mode 2 or 3?
	ja	dsm8			; no
	mov	cl,MODE_MONO
	jmp	short dsm2
dsm1:	cmp	cl,6			; CGA modes 0-6 only
	ja	dsm8
;
; ddcon_int10 does the rest for this context, which may not be the session's
; context (see video_ctx): it locks the BIOS and the session, displays a
; virtual page, and updates the context for the new mode (see update_mode).
;
dsm2:	test	ch,ch			; rows omitted?
	jz	dsm5			; yes
	cmp	ch,25			; the usual rows?
	je	dsm5			; yes
	cmp	cl,MODE_CO80		; more rows need a text mode (0-3)
	ja	dsm8
	test	[adapters],ADAPTER_EGA	; on an EGA or VGA
	jz	dsm8
	mov	ax,(VIDEO_ALTSEL SHL 8) OR 2
	cmp	ch,50			; 50 rows (400 scan lines)?
	je	dsm3			; yes
	cmp	ch,43			; 43 rows (350 scan lines)?
	jne	dsm8			; no, and those are the only choices
	dec	ax
dsm3:	mov	bl,VALT_SCANLINES
	push	cx
	call	video_ctx		; AL = 12h if it's a VGA
	pop	cx
	sub	al,VIDEO_ALTSEL		; AL = 0 if so
	cmp	ch,50			; 43 rows work on either adapter,
	jne	dsm4
	test	al,al			; but 50 rows need the VGA
	jnz	dsm8
dsm4:	mov	ds:[CT_ROWS],ch		; (see update_mode)
dsm5:	mov	ds:[CT_VMODE],0		; (a virtual mode ends here, too)
	mov	al,cl
	mov	ah,VIDEO_SETMODE
	call	video_ctx
	clc
	ret
dsm8:	jmp	ddcon_none
ENDPROC	ddcon_setmode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_vmode
;
; A context that shares the screen (eg, one of two 40-column contexts on an
; 80-column screen) can't change the screen's mode without taking the entire
; screen (see update_mode).  But if it's as wide as the text mode requested
; (eg, a program in a 40-column context asks for 40 columns), there's no need
; to: the mode becomes the context's virtual mode (CT_VMODE, which is what
; IOCTL_GETMODE then reports), and the context gives up its border, so the
; program gets all the context's columns and rows.  Requesting the original
; mode ends the virtual mode, and so does a mode of -1, which is a request to
; do only that (it fails if there's no virtual mode; see COMMAND's CLS).
;
; More than 25 rows are never virtual (see ddcon_setmode): they always change
; the screen's mode, and so does any request from a context that has them.
;
; Inputs:
;	CL = video mode requested
;	CH = rows requested
;	DS = CONSOLE context
;
; Outputs:
;	Carry clear if the mode is (or ends) a virtual mode (and if CL was
;	-1, it's now the original mode), set if the screen's mode must change
;
; Modifies:
;	AX, CL
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_vmode
	cmp	ch,25			; more than 25 rows requested?
	ja	cvm8			; yes
	cmp	ds:[CT_CONDIM].HIB,25	; or displayed now?
	jae	cvm8			; yes
	mov	al,ds:[CT_MODE]
	cmp	al,ds:[CTO_MODE]	; is the context in its original mode?
	jne	cvm8			; no
	cmp	cl,-1			; only ending the virtual mode?
	jne	cvm0			; no
	cmp	ds:[CT_VMODE],1		; yes; carry set if there isn't one
	jc	cvm9
	mov	cl,al			; (and carry is clear)
	ret
cvm0:	cmp	cl,al			; is that the mode requested?
	jne	cvm1			; no
	cmp	ds:[CT_VMODE],1		; yes; carry set if there's no virtual
	ret				; mode to end
cvm1:	cmp	cl,MODE_CO80+1		; a text mode (0-3)?
	jae	cvm8			; no
	mov	ah,40
	cmp	cl,2			; a 40-column mode (0 or 1)?
	jb	cvm2			; yes
	mov	ah,80
cvm2:	cmp	ah,ds:[CTO_DIM].LOB	; as wide as the context?
	jne	cvm8			; no
	cmp	ah,ds:[CT_COLS].LOB	; and as wide as the screen?
	je	cvm8			; yes, so there's nothing virtual
	clc
	ret
cvm8:	stc
cvm9:	ret
ENDPROC	chk_vmode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_read
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_read
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	dcr8
;
; If the current context doesn't have focus, then we're not going to
; bother checking the keyboard buffer.  We still won't block non-blocking
; requests, but no data will be returned as long as we're out-of-focus.
;
	mov	dx,es:[di].DDP_CONTEXT
	cmp	dx,[ct_focus]
	jne	dcr0

	call	pull_kbd
	push	ds
	mov	ds,dx
	call	kbd_update		; (which preserves the flags)
	pop	ds
	jnc	dcr8
;
; For READ requests that cannot be satisfied, we add this packet to an
; internal chain of "reading" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
; For character devices, DDP_UNIT contains the I/O mode (IO_RAW, IO_COOKED,
; or IO_DIRECT).
;
dcr0:	cmp	es:[di].DDP_UNIT,0
	jge	dcr1		; normal blocking request (not IO_DIRECT)
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_NOTREADY
	jmp	short dcr9

dcr1:	mov	ds,dx
	ASSUME	DS:NOTHING
	ASSERT	STRUCT,ds:[0],CT
	or	ds:[CT_STATUS],CTSTAT_INPUT
	call	add_packet
	jc	dcr2
;
; The wait can also end without the request being satisfied (eg, when an
; ABORT ends it; see ddcon_int09), in which case it's a read fault too, since
; whatever is in the caller's buffer was never read.
;
	cmp	es:[di].DDPRW_LENGTH,0	; was the request satisfied?
	je	dcr8			; yes
dcr2:	and	ds:[CT_STATUS],NOT CTSTAT_INPUT
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_RDFAULT
	jmp	short dcr9

dcr8:	mov	es:[di].DDP_STATUS,DDSTAT_DONE

dcr9:	sti
	ret
ENDPROC	ddcon_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_write
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_write
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	dcw8

	lds	si,es:[di].DDPRW_ADDR
	ASSUME	DS:NOTHING
	mov	dx,es:[di].DDP_CONTEXT
	test	dx,dx
	jnz	dcw2

dcw1:	lodsb
	call	write_char
	loop	dcw1
	jmp	short dcw8

dcw2:	push	es
	mov	es,dx
dcw3:	test	es:[CT_STATUS],CTSTAT_PAUSED
	jnz	dcw3a
	push	ax
	mov	ax,es
	call	chk_blocked		; is another context blocking us?
	pop	ax
	jnc	dcw4			; no
;
; For WRITE requests that cannot be satisfied (because the context is paused
; or blocked), we add this packet to an internal chain of "writing" packets,
; and then tell DOS that we're waiting; DOS will suspend the current SCB until
; we notify DOS that this packet's conditions are satisfied.
;
dcw3a:	pop	es			; ES:DI -> packet again
	mov	es:[di].DDPRW_LENGTH,cx
	mov	es:[di].DDPRW_ADDR.OFF,si
	call	add_packet
	jnc	dcw2			; if return is OK, try writing again
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_WRFAULT
	jmp	short dcw9

dcw4:	lodsb
	call	write_context
	loop	dcw3
	pop	es
;
; DOS reports the number of bytes written as the original length minus
; DDPRW_LENGTH (the number of bytes remaining), so we must zero it.
;
dcw8:	mov	es:[di].DDPRW_LENGTH,cx	; CX is zero
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dcw9:	ret
ENDPROC	ddcon_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_atoi
;
; Gets the next value of a context descriptor (see ddcon_open).  ATOI16
; advances SI past whatever follows a value, so if that was the null that
; ends the descriptor, SI goes back to it first; otherwise, the values that
; a short descriptor omits (eg, "VKD$:80,25") would come from whatever
; follows it in memory.
;
; Inputs:
;	BL = 10
;	DS:SI -> descriptor
;	ES:DI -> next entry in CON_PARMS
;
; Outputs:
;	AX = value (the entry's default if there's none), SI and DI updated
;
; Modifies:
;	AX, CX, DX, SI, DI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	con_atoi
	cmp	byte ptr [si-1],0	; did the last value end the string?
	jne	ca1			; no
	dec	si			; yes, so the rest are defaults
ca1:	DOSUTIL	ATOI16
	ret
ENDPROC	con_atoi

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_open
;
; The format of the optional context descriptor is:
;
;	[device]:[cols],[rows],[border],[adapter],[focus]
;
; where [device] is "VKD$" (otherwise you wouldn't be here), [cols] is number
; of columns (up to 80), [rows] is number of rows (up to 25), [border] is 1 for
; a border or 0 for none, [adapter] is the adapter #, in case there is more
; than one video adapter (adapter 0 is the default, and 2 is the adapter of
; the session's own context, which START uses), and [focus] is 1 to take
; the focus (eg, for START), which goes back to the context that had it when
; this one closes (see ddcon_close).  The first context always gets the focus.
; Values can be omitted (eg, "VKD$:,,1"), including all those at the end (eg,
; "VKD$:80,25"), and their defaults (see CON_PARMS) are 80, 25, 0, 0, and 0.
;
; Without a descriptor (ie, "VKD$" or "VKD$:"), no context is created: the
; open adds a reference to the session's current context instead.
;
; Each adapter's contexts are placed automatically, starting at the top left
; of its first page and filling the page downward, then rightward, and then
; the next page, until the adapter has no pages left (see con_place); the
; pages after those (up to MAX_PAGES) are virtual pages (see swap_page).
;
; Obviously future hardware (imagine an ENHANCED Graphics Adapter, for example)
; will be able to support more rows and other features, but we're designing
; exclusively for the MDA and CGA for now.
;
; Inputs:
;	ES:DI -> DDP
;	[DDP].DDP_PTR -> context descriptor (eg, "VKD$:80,25")
;
; Outputs:
;	[DDP].DDP_CONTEXT set with
;
; Notes:
;	We presume that the current SCB is locked for duration of this call;
;	if that presumption ever proves false, then use the DOSUTIL LOCK API.
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_open
	push	di
	push	es

	push	ds
	lds	si,es:[di].DDP_PTR
	ASSUME	DS:NOTHING
;
; DDP_PTR points to the device name: "VKD$", or "CON" when a session whose
; console is ours opens CON with a descriptor (eg, START's "CON:80,25,0,0,1";
; see chk_devname), which is no different.  Any descriptor follows the colon.
;
dco0b:	lodsb
	test	al,al			; end of the name?
	jz	dco0			; yes
	cmp	al,':'			; is it a colon?
	jne	dco0b			; no
	cmp	byte ptr [si],0		; anything after the colon?
	jne	dco1			; yes
dco0:	pop	ds
	mov	ah,DOS_UTL_LOCK
	call	far ptr DDINT_UTIL	; get the current context in AX
	call	chk_context		; is it one of ours?
	jz	dco0a			; no (eg, the session console is COM1)
	mov	ds,ax
	ASSERT	STRUCT,ds:[0],CT
	inc	ds:[CT_REFS]
dco0a:	push	ax
	mov	ah,DOS_UTL_UNLOCK
	call	far ptr DDINT_UTIL	; unlock the current session
	pop	ax
	cmp	ax,1			; set carry if no context (AX is zero)
	jmp	dco7
;
; The device name consists of "VKD$:...."  We're not sure what "...." is yet,
; but hopefully it conforms to the context descriptor format described above.
;
dco1:	push	cs
	pop	es
	mov	bl,10			; use base 10
	mov	di,offset CON_PARMS	; ES:DI -> parm defaults/limits
	call	con_atoi		; updates SI, DI, and AX
	mov	cl,al			; CL = cols
	call	con_atoi
	mov	ch,al			; CH = rows
	call	con_atoi
	mov	bh,al			; BH = border (0 for none)
	ASSERT	CTSTAT_BORDER,EQ,01h
	call	con_atoi
	shl	al,1
	or	bh,al			; BH includes adapter bit, too
	ASSERT	CTSTAT_ADAPTER,EQ,02h
	ASSERT	CTSTAT_SAME,EQ,04h
	call	con_atoi
	xchg	di,ax			; DI = 1 to take the focus
	pop	ds
	ASSUME	DS:CODE
;
; A machine with 64K or less gets only one console (see con_opt).
;
	cmp	[one_con],0
	je	dco1q
	cmp	[ct_head],0		; is there a console already?
	je	dco1q			; no
	stc
	jmp	dco7
dco1q:
;
; An adapter of 2 is the adapter of the session's context, if it has one of
; ours (otherwise, the primary adapter).
;
	test	bh,CTSTAT_SAME		; session's adapter requested?
	jz	dco1s			; no
	xor	bh,CTSTAT_SAME
	call	get_sesctx		; AX = the session's context
	jz	dco1s			; it isn't ours
	mov	es,ax
	mov	al,es:[CT_STATUS]
	and	al,CTSTAT_ADAPTER
	or	bh,al			; BH = that context's adapter bit
dco1s:	test	bh,CTSTAT_ADAPTER	; alternate adapter requested?
	jz	dco1w			; no
	cmp	[adapters],ADAPTER_MDA OR ADAPTER_CGA
	stc
	jne	dco1x			; it isn't present
;
; Place the context at the adapter's next position (see con_place), reducing
; its size to fit the rest of the page, as long as it's still at least the
; minimum size (see CON_PARMS).
;
dco1w:	mov	al,bh
	and	ax,CTSTAT_ADAPTER	; AX = 0 or 2
	shl	ax,1
	xchg	si,ax			; SI = 0 (primary) or 4 (alternate)
;
; A context that starts a page goes on the first page with no contexts, so
; that the pages of closed contexts (eg, from START) are used again, before
; any virtual page that would need a buffer.
;
	cmp	word ptr con_place[si],0	; at the top left of a page?
	jne	dco1v				; no
	mov	al,bh
	and	al,CTSTAT_ADAPTER	; AL = adapter bit
	mov	ah,-1
dco1r:	inc	ah
	cmp	ah,MAX_PAGES		; any page left?
	cmc
	jc	dco1x			; no
	call	find_page		; is it in use?
	jnc	dco1r			; yes
	mov	byte ptr con_place[si+2],ah
dco1v:	mov	ax,con_place[si+2]	; AL = page, AH = # pages
	cmp	al,MAX_PAGES		; is there a page left?
	cmc
	jc	dco1x			; no
	mov	bl,al			; BL = page
	mov	dx,con_place[si]	; DL = x, DH = y
	mov	al,[max_cols]
	sub	al,dl			; AL = columns left
	cmp	cl,al			; are there enough?
	jbe	dco1t			; yes
	mov	cl,al			; no, so use what's left
dco1t:	mov	al,[max_rows]
	sub	al,dh			; AL = rows left
	cmp	ch,al			; are there enough?
	jbe	dco1u			; yes
	mov	ch,al			; no, so use what's left
dco1u:	cmp	cl,16			; still at least the minimum columns?
	jb	dco1x			; no
	cmp	ch,4			; still at least the minimum rows?
	jb	dco1x			; no

	push	di
	mov	di,size CONTEXT
	call	alloc_sys		; AX = the context's segment
	pop	di
	jc	dco1x
	cmp	bl,byte ptr con_place[si+3]
	jb	dco1a			; not a virtual page
	call	get_vbuf		; find (or allocate) its buffer
	jnc	dco1a
dco1x:	jmp	dco7
;
; Advance the adapter's next position: downward, then rightward, and then to
; the top left of the next page.
;
dco1a:	push	ax
	mov	ax,dx
	add	ah,ch			; AH = row below the context
	cmp	ah,[max_rows]		; at the bottom of the page?
	jb	dco1b			; no
	mov	ah,0			; yes, so back to the top
	add	al,cl			; AL = column right of the context
	cmp	al,[max_cols]		; at the right edge of the page?
	jb	dco1b			; no
	mov	al,0			; yes, so the next page
	inc	byte ptr con_place[si+2]
dco1b:	mov	con_place[si],ax
	pop	ax
	neg	di			; set carry if taking the focus
	sbb	di,di
	and	di,[ct_focus]		; DI = context giving it up, if any
	mov	ds,ax
	ASSUME	DS:NOTHING
	DBGINIT	STRUCT,ds:[0],CT
;
; Inserting the new context at the head of the chain (ct_head) is the
; simplest way to update the chain, but we prefer to chain the contexts
; in the order they were created, to provide more natural focus cycling.
;
;	xchg	[ct_head],ax
;	mov	ds:[CT_NEXT],ax
;
dco2:	mov	ds:[CT_NEXT],0
	mov	ds:[CT_PARENT],di
	mov	ds:[CT_SCAN],0
	mov	ds:[CT_BIOS],0
	mov	ds:[CT_SLOT],0		; no video memory selector yet
	mov	ds:[CT_PAGE],bl
	mov	ds:[CTO_PAGE],bl
	mov	bl,1			; set CT_REFS to 1 and CT_STATUS to BH
	mov	word ptr ds:[CT_REFS],bx
	sub	si,si			; SI = 0 (see below)
	mov	di,offset ct_head
	mov	es,cs:[0].DDH_DATA
dco2a:	mov	ax,es:[di]		; ES:DI -> next context segment
	test	ax,ax
	jz	dco2b
	mov	es,ax
	mov	di,offset CT_NEXT
;
; Since we're stepping through every context, this is a good opportunity
; to look for one on the same adapter (SI), since it has everything we need
; to know about the adapter (see below).
;
	mov	al,es:[di].CT_STATUS
	xor	al,bh
	test	al,CTSTAT_ADAPTER	; is it on the same adapter?
	jnz	dco2a			; no
	mov	si,es			; yes
	jmp	dco2a
dco2b:	mov	es:[di],ds
;
; Set the context's dimensions (CL,CH) and position (DL,DH), saving them so
; that they can be restored later (see update_mode).
;
	mov	ds:[CTO_DIM],cx
	mov	ds:[CTO_POS],dx
	mov	al,bh
	and	al,CTSTAT_BORDER
	mov	ds:[CTO_STATUS],al
	mov	word ptr ds:[CT_VMODE],0	; (and the CT_ROWS after it)
	call	set_geometry
	mov	ds:[CT_COLOR],0707h	; default fill and border attributes
;
; Importing the BIOS CURSOR_POSN into CURPOS seemed like a nice idea initially,
; but now that we're clearing interior below, it seems best to use a default.
;
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	; mov	ax,[CURSOR_POSN]
	mov	ax,ds:[CT_CURMIN]	; get CT_CURMIN
	mov	ds:[CT_CURPOS],ax	; set CT_CURPOS (X and Y)
;
; The adapter's original mode, port, equipment flags, and default cursor type
; come from another context on the adapter, if there is one, because the BIOS
; data describes whichever adapter was used last (eg, by the context with
; focus), which may not be this one.
;
	test	si,si			; another context on the adapter?
	jz	dco3			; no
	push	ds
	mov	ds,si
	mov	bl,ds:[CTO_MODE]
	mov	cx,ds:[CT_EQUIP]
	mov	dx,ds:[CT_PORT]
	mov	ax,ds:[CT_DEFTYPE]
	pop	ds
	jmp	short dco4
;
; Otherwise, they come from the BIOS data, if that describes the adapter (ie,
; it has the adapter's port); if not, the adapter must be initialized first.
;
; WARNING: The following code to support alternate adapters is very fragile;
; it assumes we're dealing EXCLUSIVELY with MDA and CGA adapters, and that the
; monitor bits in the equipment flags are always set to either EQ_VIDEO_MONO
; (30h) or EQ_VIDEO_CO80 (20h), and therefore by toggling EQ_VIDEO_CO40 (10h)
; prior to INT 10h initialization of the adapter, the correct "equipment" will
; be enabled.
;
dco3:	mov	bl,[CRT_MODE]
	mov	cx,[EQUIP_FLAG]		; snapshot the equipment flags
	mov	dx,3B4h
	mov	al,[frame_seg].HIB	; AL = B0h (MDA) or B8h (CGA)
	shr	al,1
	shr	al,1			; bit 1 is set if the primary is a CGA
	xor	al,bh
	test	al,CTSTAT_ADAPTER	; is the context's adapter the MDA?
	jz	dco3a			; yes
	mov	dl,0D4h			; no, so its port is 3D4h
dco3a:	cmp	dx,[ADDR_6845]		; does the BIOS data describe it?
	je	dco3c			; yes
	xor	cl,EQ_VIDEO_CO40
	mov	bl,MODE_MONO		; default
	cmp	dl,0B4h
	je	dco3b
	mov	bl,MODE_CO80
dco3b:	xchg	[EQUIP_FLAG],cx
;
; We bypass ddcon_int10 here, because it would treat this mode change as a
; change to the session's context (see update_mode), which isn't this one.
;
	mov	al,bl			; AL = new video mode
	mov	ah,VIDEO_SETMODE
	pushf
	call	[video_int]
	xchg	[EQUIP_FLAG],cx
dco3c:	call	update_curtype		; AX = default cursor type
dco4:	mov	ds:[CT_CURTYPE],ax
	mov	ds:[CT_DEFTYPE],ax
	mov	ds:[CT_PORT],dx
	mov	ds:[CT_EQUIP],cx
	mov	ds:[CT_MODE],bl
	mov	ds:[CTO_MODE],bl
	mov	ax,80
	cmp	bl,2			; is it a 40-column mode (0 or 1)?
	jae	dco4a			; no
	mov	al,40
dco4a:	mov	ds:[CT_COLS],ax
	call	chk_vpage		; is it on a virtual page?
	jc	dco4b			; yes (see get_vbuf)
	call	get_frame
	mov	ds:[CT_SCREEN].SEG,ax
dco4b:
;
; If we're creating a session on a secondary adapter, then like the mode
; change above, we must temporarily change EQUIP_FLAG, because until we finish
; this open call, the DOSUTIL LOCK function will be unable to tell our INT 10h
; hook what the correct context is.
;
	xchg	[EQUIP_FLAG],cx
	push	cx
	mov	cl,100
	call	scroll			; clear the context's interior
	pop	[EQUIP_FLAG]
;
; If no context has focus, this one gets it, now that it's in our chain and
; ready for a focus switch at interrupt time.
;
	mov	es,cs:[0].DDH_DATA
	ASSUME	ES:CODE
	cmp	[ct_focus],0
	jne	dco5
	mov	[ct_focus],ds
dco5:
	ASSUME	ES:NOTHING
	call	draw_border		; draw the context's border, if any

	mov	ax,ds
	cmp	ax,[ct_focus]		; does new context have focus?
	je	dco6			; yes
	call	hide_cursor		; no, so hide cursor
	push	ds			; and restore BIOS with data from focus
	mov	ds,[ct_focus]
	call	update_biosdata
	call	draw_cursor		; (whose cursor we may have hidden)
	pop	ds
	mov	cx,ds:[CT_PARENT]	; CX = context with focus, if taking it
	mov	bx,ds			; BX = this context
	call	switch_to
dco6:	clc
;
; An unavailable adapter or a failure to allocate memory is an open error,
; and an open's error is a DOS error code (see dev_request).
;
dco7:	pop	es
	pop	di			; ES:DI -> DDP again
	jnc	dco8
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + ERR_NOMEMORY
	jmp	short dco9

dco8:	mov	es:[di].DDP_CONTEXT,ds
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dco9:	ret
ENDPROC	ddcon_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_close
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_close
	mov	cx,es:[di].DDP_CONTEXT
	push	es
	jcxz	dcc0			; no context
	mov	es,cx
	dec	es:[CT_REFS]
	jz	dcc0a
dcc0:	jmp	dcc7
dcc0a:
;
; If the context isn't in its original mode, then the other contexts on the
; same adapter are blocked (see chk_blocked), so restore the context's original
; mode and unblock them.
;
	cmp	[mode_ctx],cx
	jne	dcc1
	push	ds
	mov	ds,cx
	ASSUME	DS:NOTHING
	mov	al,ds:[CTO_MODE]
	mov	ah,VIDEO_SETMODE
	call	video_ctx		; (see update_mode and release_mode)
	pop	ds
	ASSUME	DS:CODE

;
; Any context that took the focus from this one takes it back from this one's
; parent instead (eg, if START made B from A and C from B, and B closes first,
; then C's focus goes back to A).
;
dcc1:	mov	ax,es:[CT_PARENT]	; AX = this context's parent, if any
	mov	dx,[ct_head]
	push	ds
dcc1a:	mov	ds,dx
	ASSUME	DS:NOTHING
	cmp	ds:[CT_PARENT],cx	; did it take the focus from this one?
	jne	dcc1b			; no
	mov	ds:[CT_PARENT],ax	; yes
dcc1b:	mov	dx,ds:[CT_NEXT]
	test	dx,dx
	jnz	dcc1a
	pop	ds
	ASSUME	DS:CODE
;
; If this context has focus, it goes back to the parent, if any (or else the
; next context).  If it's our last context, no context has focus now, as when
; we started (eg, with CON=COM1, after a program's own VKD$ context closes, or
; a CON=VKD$ console's last session ends), and the next one we open gets it.
;
	cmp	[ct_focus],cx
	jne	dcc2
	cmp	[one_con],0		; one console only (see con_opt)?
	jne	dcc1c			; yes
	xchg	bx,ax			; BX = parent, if any
	call	switch_to
dcc1c:	cmp	[ct_focus],cx		; is there another context?
	jne	dcc2			; yes, and it has focus
	sub	ax,ax
	mov	[ct_focus],ax		; no, so none has focus
;
; Remove the context from our chain.
;
; Clear the context first, because ddcon_int10 must still find it in our chain
; (see chk_context); otherwise, the BIOS would clear whichever page is active.
;
dcc2:	push	ds
	mov	ds,cx
	push	cx
	mov	cl,0			; clear the entire context
	call	scroll
	pop	ax			; AX = context to free
	pop	ds
	push	ds
	mov	bx,offset ct_head	; DS:BX -> 1st context
dcc3:	mov	cx,[bx].CT_NEXT
	ASSERT	NZ,<test cx,cx>
	jcxz	dcc4			; context not found
	cmp	cx,ax
	je	dcc4
	mov	ds,cx
	ASSUME	DS:NOTHING
	sub	bx,bx			; DS:BX -> next context
	jmp	dcc3			; keep looking
dcc4:	mov	cx,es:[CT_NEXT]		; move this context's CT_NEXT
	mov	[bx].CT_NEXT,cx		; to the previous context's CT_NEXT
	pop	ds
	ASSUME	DS:CODE
;
; We are now free to free the context segment in ES (and its virtual page's
; buffer, if no other context is on that page).
;
	call	free_vbuf
	call	free_ctx

dcc7:	pop	es

	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcon_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; free_ctx
;
; Frees a context's memory, and its video memory selector, if any (whose
; sessions are all gone).
;
; Inputs:
;	ES = CONSOLE context
;
; Modifies:
;	AX, BX, CX, DX, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	free_ctx
	mov	bx,es:[CT_SLOT]
	test	bx,bx			; is there a selector?
	jz	free_seg		; no
	mov	ah,CPU_UNMAP
	call	far ptr DDINT_CPU	; free it (by its ID)
	DEFLBL	free_seg,near		; (see get_vbuf)
	mov	cx,es
	mov	es,cs:[0].DDH_DATA	; (ES can't hold the block being freed)
	jmp	short free_buf
ENDPROC	free_ctx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; free_vbuf
;
; Frees a context's virtual page buffer if no other context is on that page.
;
; Inputs:
;	ES = CONSOLE context (no longer in our chain)
;
; Modifies:
;	AX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	free_vbuf
	push	ds
	push	es
	pop	ds			; DS = context
	call	chk_vpage		; is it on a virtual page?
	jnc	fvb9			; no
	mov	al,ds:[CT_STATUS]
	and	al,CTSTAT_ADAPTER
	mov	ah,ds:[CTO_PAGE]	; AH = page, AL = adapter bit
	call	find_page		; is another context on the page?
	push	ds
	pop	es			; (ES = context again)
	jnc	fvb9			; yes
	mov	cx,ds:[CT_SCREEN].SEG
	call	free_buf		; no, so free the buffer
fvb9:	pop	ds
	ret
ENDPROC	free_vbuf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; alloc_sys
;
; Contexts and virtual page buffers are owned by the system, rather than by
; the program that opens a context (eg, START), since they outlive it.
;
; Inputs:
;	DI = length
;
; Outputs:
;	Carry clear if successful, AX = segment (or selector)
;
; Modifies:
;	AX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	alloc_sys
	push	bx
	push	cx
	push	dx
	sub	si,si			; SI:DI = length
	mov	bx,MCBOWNER_SYSTEM
	mov	ax,CPU_ALLOC SHL 8	; AL = 0 (a GDT data selector)
	call	far ptr DDINT_CPU
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	alloc_sys

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; free_buf
;
; Inputs:
;	CX = context or virtual page buffer (from alloc_sys), which DS and ES
;	must not hold (since CPU$ reloads them)
;
; Modifies:
;	AX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	free_buf
	mov	dx,-1			; DX = -1 means CX is a segment
	mov	ah,CPU_FREE
	call	far ptr DDINT_CPU
	ret
ENDPROC	free_buf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_page
;
; Inputs:
;	AL = CTSTAT_ADAPTER bit, AH = page
;
; Outputs:
;	Carry clear if a context in our chain is on that page (ES = context);
;	carry set if none
;
; Modifies:
;	ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	find_page
	push	bx
	mov	bx,[ct_head]
fp1:	test	bx,bx			; any more contexts?
	stc
	jz	fp9			; no
	mov	es,bx
	mov	bl,es:[CT_STATUS]
	and	bl,CTSTAT_ADAPTER
	mov	bh,es:[CTO_PAGE]
	cmp	bx,ax			; is this context on the page?
	je	fp9			; yes (and carry is clear)
	mov	bx,es:[CT_NEXT]
	jmp	fp1
fp9:	pop	bx
	ret
ENDPROC	find_page

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_none (handler for unimplemented functions)
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_none
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	stc
	ret
ENDPROC	ddcon_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_inflush
;
; Discards the context's keyboard type-ahead, which can only be in the BIOS
; keyboard buffer if the context has focus.
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	DDP updated
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_inflush
	mov	ax,es:[di].DDP_CONTEXT
	cmp	ax,[ct_focus]		; does the context have focus?
	jne	dif9			; no
	push	ds
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	cli
	mov	ax,[BUFFER_TAIL]
	mov	[BUFFER_HEAD],ax	; the buffer is now empty
	sti
	mov	ds,es:[di].DDP_CONTEXT
	call	kbd_update
	pop	ds
	ASSUME	DS:CODE
dif9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcon_inflush

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_outflush
;
; Ends the context's pause (see check_hotkey), if any; VKD$ output isn't
; buffered, so there's nothing to discard.
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	DDP updated
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_outflush
	mov	ax,es:[di].DDP_CONTEXT
	test	ax,ax			; is there a context?
	jz	dof9			; no
	push	ds
	mov	ds,ax
	ASSUME	DS:NOTHING
	and	ds:[CT_STATUS],NOT CTSTAT_PAUSED
	pop	ds
	ASSUME	DS:CODE
dof9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcon_outflush

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_int09 (keyboard hardware interrupt handler)
;
; When keys appear in the BIOS keyboard buffer, deliver them to whichever
; context 1) has focus, and 2) has a pending read request.  Otherwise, let
; them stay in the BIOS buffer.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_int09,far
	call	far ptr DDINT_ENTER
	jc	i09c

	push	ax
	in	al,60h			; peek at the scan code
	cmp	al,SCAN_DEL		; DEL key pressed?
	jne	i09b			; no
	push	ds
	mov	ax,BIOS
	mov	ds,ax
	mov	al,ds:[KB_FLAG]		; CTRL and ALT pressed as well?
	and	al,CTL_SHIFT OR ALT_SHIFT
	cmp	al,CTL_SHIFT OR ALT_SHIFT
	jne	i09a			; no
;
; After notifying DOS of the "CTRL-ALT-DEL" hotkey, we're going to
; clear the CTL_SHIFT flag in order to let the BIOS process the interrupt
; without rebooting the machine.
;
	push	cx
	mov	cx,[ct_focus]		; CX = context
	jcxz	i09
	push	dx
	mov	dx,CHR_CTRLD		; DL = char code, DH = scan code
	mov	ah,DOS_UTL_HOTKEY
	call	far ptr DDINT_UTIL	; notify DOS
	and	ds:[KB_FLAG],NOT CTL_SHIFT
	mov	ds,cx
	ASSERT	STRUCT,ds:[0],CT
	or	ds:[CT_STATUS],CTSTAT_ABORT
	pop	dx
i09:	pop	cx
i09a:	pop	ds
i09b:	pop	ax
	clc

i09c:	pushf
	call	[kbd_int]
	jnc	i09d			; carry set if DOS isn't ready
	jmp	i09z

i09d:	push	ax
	push	bx
	push	cx
	push	dx
	push	di
	push	ds
	push	es

	sti
	mov	cx,[ct_focus]		; CX = context
	call	check_hotkey
	jc	i09e
	xchg	dx,ax			; DL = char code, DH = scan code
	mov	ah,DOS_UTL_HOTKEY
	call	far ptr DDINT_UTIL	; notify DOS

i09e:	mov	ds,cx			; DS = context
	mov	cx,cs:[0].DDH_DATA
	mov	es,cx
	mov	bx,offset wait_ptr	; CX:BX -> ptr
	les	di,es:[bx]		; ES:DI -> packet, if any
	ASSUME	ES:NOTHING

i09f:	cmp	di,-1			; end of chain?
	je	i09w			; yes

	ASSERT	STRUCT,es:[di],DDP

	mov	dx,ds
	cmp	es:[di].DDP_CONTEXT,dx	; packet from console with focus?
	jne	i09i			; no

	cmp	es:[di].DDP_CMD,DDC_READ; READ packet?
	je	i09g			; yes, look for keyboard data
;
; For WRITE packets (which we'll assume this is for now), we need to end the
; wait if the context is no longer paused (ie, if check_hotkey cleared PAUSED).
;
	ASSERT	STRUCT,ds:[0],CT
	test	ds:[CT_STATUS],CTSTAT_PAUSED
	jz	i09h			; yes, we're no longer paused
	jmp	short i09i		; still paused, check next packet

i09g:	call	pull_kbd		; pull keyboard data
	jnc	i09h
	test	ds:[CT_STATUS],CTSTAT_ABORT
	jz	i09i			; not enough data, and no ABORT pending
;
; Notify DOS that this packet is done waiting.
;
i09h:	and	ds:[CT_STATUS],NOT CTSTAT_INPUT
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	mov	ah,DOS_UTL_ENDWAIT
	call	far ptr DDINT_UTIL	; end the wait on DX:DI (see int_util)
;
; If carry is set, ENDWAIT failed.  There are two cases: 1) the WAIT request
; hasn't been set yet (eg, a race condition), and 2) the WAIT request was
; aborted (nothing we can do about that).
;
; TODO: To avoid the potential race condition, the entire pull_kbd + add_packet
; path disables interrupts.  Consider lighter-weight solutions.
;
; In any case, proceed with packet removal now.
;
	cli
	mov	ax,es:[di].DDP_PTR.OFF
	mov	dx,es:[di].DDP_PTR.SEG
	mov	es,cx
	mov	es:[bx].OFF,ax
	mov	es:[bx].SEG,dx
	or	ds:[CT_STATUS],CTSTAT_ABORT
	jmp	short i09w

i09i:	lea	bx,[di].DDP_PTR		; update prev addr ptr in CX:BX
	mov	cx,es

	les	di,es:[di].DDP_PTR
	jmp	i09f

i09w:	ASSERT	STRUCT,ds:[0],CT
	call	kbd_update		; (the keys may have changed)
	test	ds:[CT_STATUS],CTSTAT_ABORT
	jz	i09x
	and	ds:[CT_STATUS],NOT CTSTAT_ABORT
	stc
i09x:	pop	es
	pop	ds
	pop	di
	pop	dx
	pop	cx
	pop	bx
	pop	ax
i09z:	jmp	far ptr DDINT_LEAVE
ENDPROC	ddcon_int09

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_int10 (BIOS video services)
;
; Originally, the plan was to ignore apps that issue INT 10h and support only
; "well-behaved" apps that use DOS/CONSOLE interfaces, but we can't ignore the
; INT 10h functions we issue ourselves (like mode changes and scrolls), so we
; now perform BIOS data context switching on all INT 10h calls.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_int10,far
;
; We preserve the original AX for inspection after the call (but we still
; return the updated AX), and we preserve BP, which has the added benefit of
; fixing an INT 10h "bug" where certain functions would trash BP, and makes
; it easier for this code to access data on the stack.
;
; The BIOS says for INT 10h:
;
;	CS,SS,DS,ES,BX,CX,DX PRESERVED DURING CALL
;	ALL OTHERS DESTROYED
;
; but in fact, SI, DI, and flags are explicitly preserved as well, BP is
; trashed by only a few functions (scroll and graphics read), and virtually
; no other BIOS services alter BP.  So rather than let this odd behavior
; expose us to potential bugs downstream, we preserve BP, too.
;
	push	bp
	push	ax
;
; BIOS locking prevents focus switches and DOS locking prevents session
; switches, both of which are problematic in the middle of certain INT 10h
; operations, especially mode changes and scrolls.  Originally, the scroll
; function issued its own locks, but locking at this level makes that
; unnecessary now.
;
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
;
; BASIC-DOS programs have no reason to call INT 10h, and the BIOS knows only
; about the screen (eg, it can't draw on a virtual page, and its cursor calls
; change the cursor that's displayed), so a session whose context doesn't
; have focus waits here until it does (see wait_focus).  Our own calls on
; behalf of a context (bios_ctx) and calls made while the BIOS is locked (eg,
; by the BIOS itself, in the middle of another INT 10h) never wait.  If the
; wait is interrupted (eg, by KILL), we return without calling the BIOS.
;
	cmp	[bios_ctx],0		; is this one of our own calls?
	jne	i10v			; yes
	cmp	[bios_lock],0		; is the BIOS locked?
	jne	i10v			; yes
i10u:	call	get_sesctx		; is the session's context ours?
	jz	i10v			; no
	call	wait_focus
	je	i10v			; no wait was needed
	jnc	i10u			; the wait ended, so check again
	pop	ds
	pop	ax
	pop	bp
	iret
i10v:	inc	[bios_lock]
;
; DOSUTIL LOCK has been updated to return the active session's CONSOLE
; context in AX.  However, during system initialization, that context may
; not exist yet, and if the session's CONSOLE is another device (eg, COM1),
; then the context isn't ours either.
;
	mov	ah,DOS_UTL_LOCK
	call	far ptr DDINT_UTIL	; ensure EQUIP_FLAG remains stable
	cmp	[bios_ctx],0		; is a specific context requested?
	je	i10y			; no
	mov	ax,[bios_ctx]		; yes (see scroll)
	mov	[bios_ctx],0
i10y:	pop	ds
	ASSUME	DS:NOTHING
	call	chk_context		; zero AX if the context isn't ours
	push	ax			; save the context segment
	test	ax,ax			; is it valid?
	jz	i10a			; no
	push	ds			; yes
	mov	ds,ax			; load it
	mov	bp,sp
	cmp	byte ptr [bp+5],VIDEO_SETMODE	; setting a video mode?
	jne	i10z			; no
	call	chk_opt			; one console only?
	jc	i10z			; yes (see con_opt)
	call	set_pmode		; can the mode be set in place?
	jnc	i10p			; yes, and it has been
	call	swap_page		; no (see swap_page)
i10z:	call	update_biosdata		; returns current EQUIP_FLAG
	pop	ds

i10a:	push	ax			; save EQUIP_FLAG
	mov	bp,sp
;
; Each context has a page of its own, and selecting another would display
; some other context's page, so we ignore VIDEO_SETPAGE, unless the context
; is using the entire screen (see mode_ctx).
;
	cmp	byte ptr [bp+5],VIDEO_SETPAGE
	jne	i10d
	mov	ax,[bp+2]		; AX = context
	test	ax,ax			; is it ours?
	jz	i10d			; no
	cmp	ax,[mode_ctx]
	mov	ax,[bp+4]		; AX = caller's AX
	jne	i10e			; ignore it
i10d:	mov	ax,[bp+4]		; AX = caller's AX
	mov	bp,[bp+6]		; BP = caller's BP

	pushf
	call	[video_int]		; issue the original INT 10h

i10e:	mov	bp,sp
	xchg	[bp+4],ax		; update AX return value on stack
	cmp	word ptr [bp+2],0	; is the context segment valid?
	je	i10x			; no
	push	ds			; yes
	mov	ds,[bp+2]		; load it
	cmp	ah,VIDEO_SETMODE	; did the caller set a video mode?
	mov	ax,[bp]			; AX = EQUIP_FLAG from update_biosdata
	jne	i10b			; no
	call	update_mode		; yes (see update_mode)
	jmp	short i10c
i10b:	call	update_context
i10c:	pop	ds

i10x:	pop	ax			; clean up the stack
	pop	ax			; (eg, ADD SP,4)
	mov	ah,DOS_UTL_UNLOCK
	call	far ptr DDINT_UTIL	; unlock the current session
	call	unlock_bios

	pop	ax
	pop	bp
	iret
;
; set_pmode set the mode without the BIOS, so there's no more to do.
;
i10p:	pop	ds
	push	ax			; (i10x removes two words)
	jmp	i10x
ENDPROC	ddcon_int10

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_int29 (handler for INT_FASTCON: fast console I/O)
;
; Inputs:
;	AL = character to display
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_int29,far
	push	dx
	mov	dx,[ct_focus]		; for now, use the context with focus
	test	dx,dx
	jnz	i29a
	call	write_char
	jmp	short i29b
i29a:	push	es
	mov	es,dx
	call	write_context
	pop	es
i29b:	pop	dx
	iret
ENDPROC	ddcon_int29

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_packet
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	Carry clear if the packet was satisfied, set if the wait was interrupted
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	add_packet
	cli
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	ax,di
	xchg	[wait_ptr].OFF,ax
	mov	es:[di].DDP_PTR.OFF,ax
	mov	ax,es
	xchg	[wait_ptr].SEG,ax
	mov	es:[di].DDP_PTR.SEG,ax
	pop	ds
	ASSUME	DS:NOTHING
;
; The WAIT condition will be satisfied when enough data is received
; (for a READ packet) or when the context is unpaused (for a WRITE packet).
;
	push	dx
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	mov	ah,DOS_UTL_WAIT
	call	far ptr DDINT_UTIL	; wait on DX:DI (see int_util)
	jnc	ap9
;
; The wait was interrupted (eg, by ABORT or CTRLC), so the packet must be
; removed from the chain.  However, if it's no longer on the chain, then our
; interrupt handler satisfied it after all (eg, it delivered the CTRLC that
; interrupted the wait), so treat that as success.
;
	call	remove_packet		; carry clear if packet removed
	cmc				; carry set if packet removed
ap9:	pop	dx
	sti
	ret
ENDPROC	add_packet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; remove_packet
;
; Removes a packet from the chain of waiting packets, if it's still there.
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	Carry clear if the packet was removed, set if it wasn't found
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	remove_packet
	push	bx
	push	cx
	push	ds
	mov	ds,cs:[0].DDH_DATA
	mov	bx,offset wait_ptr	; DS:BX -> first link
	mov	cx,es			; CX:DI -> packet to remove
	pushf
	cli
rp1:	mov	ax,[bx].OFF
	cmp	ax,-1			; end of chain?
	je	rp8			; yes, packet not found
	cmp	ax,di
	jne	rp2
	cmp	[bx].SEG,cx
	je	rp3
rp2:	lds	bx,dword ptr [bx]	; DS:BX -> next packet
	lea	bx,[bx].DDP_PTR		; DS:BX -> its link
	jmp	rp1
rp3:	mov	ax,es:[di].DDP_PTR.OFF	; unlink the packet
	mov	[bx].OFF,ax
	mov	ax,es:[di].DDP_PTR.SEG
	mov	[bx].SEG,ax
	popf
	clc
	jmp	short rp9
rp8:	popf
	stc
rp9:	pop	ds
	pop	cx
	pop	bx
	ret
ENDPROC	remove_packet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; check_hotkey
;
; Check for key combinations considered "hotkeys" by BASIC-DOS; if a hotkey
; is detected, carry is cleared, indicating that a DOSUTIL HOTKEY notification
; should be issued.
;
; For example, CTRLC (and CTRL_BREAK, which we convert to CTRLC) are considered
; hotkeys, so that DOS functions need not "poll" the console to determine if a
; CTRLC has been typed.  Ditto for CTRLP, which DOS likes to use for turning
; "printer echo" on and off.
;
; Another advantage to using HOTKEY notifications is the hotkeys don't get
; buried in the input stream; as soon as they're typed, notification occurs.
;
; This function also includes some internal hotkey checks; eg, CTRLS for
; toggling the console's PAUSE state, and SHIFT-TAB (or CONFIG.SYS's HOTKEY
; setting, if any; see HOT_KEY) for toggling focus between consoles; internal
; hotkeys do not generate system HOTKEY notifications.
;
; TODO: CTRLC can still get "buried" in a sense: if you fill up the ROM's
; keyboard buffer, the ROM will never add CTRLC, so it's CTRL_BREAK to the
; rescue again.  One alternative is to maintain our own (per console) buffer
; and always suck the ROM's buffer dry; that's better for session focus, but
; there are ripple effects: for example, we would be forced to simulate at
; least some of the ROM BIOS keyboard services then.  An intermediate hack
; would be to always toss the last key whenever the buffer has reached
; capacity, so that there's always room for one more key....
;
; Inputs:
;	CX = focus context, if any
;
; Outputs:
;	If carry clear, AL = hotkey char code, AH = hotkey scan code
;
; Modifies:
;	AX, BX, CX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	check_hotkey
	push	ds
	mov	bx,BIOS
	mov	ds,bx
	ASSUME	DS:BIOS

	mov	bx,[BUFFER_TAIL]
	cmp	bx,[BUFFER_HEAD]
	je	ch0a			; BIOS buffer empty
	sub	bx,2			; rewind the tail
	cmp	bx,offset KB_BUFFER
	jae	ch0
	add	bx,size KB_BUFFER
ch0:	mov	ax,[bx]			; AL = char code, AH = scan code
;
; Let's take care of internal hotkeys first (in part because it seems
; unlikely we would want them to affect things like a console's PAUSE state).
;
	cmp	al,[HOT_KEY]		; the HOTKEY setting (zero if none)?
	jne	ch1			; no
	test	al,al			; without one, the key is SHIFT-TAB
	jnz	ch0b			; (which has no character either)
	cmp	ah,SCAN_TAB
	jne	ch1
ch0b:	mov	[BUFFER_TAIL],bx	; update tail, consuming the character
	cmp	[one_con],0		; is there anything to switch to?
	jne	ch0a			; no (see con_opt)
	call	switch_focus
ch0a:	stc				; (no system hotkey)
	pop	ds
	ret
;
; CTRL-BREAK (which the BIOS stores as zero) is removed from the buffer and,
; as an interim measure, treated like CTRL-ALT-DEL (see ddcon_int09): DOS only
; notices CTRLC when a program calls DOS, whereas an ABORT also stops a program
; that doesn't (eg, a BASIC loop with no I/O).
;
ch1:	test	ax,ax			; CTRL-BREAK?
	jnz	ch1a			; no
	mov	[BUFFER_TAIL],bx	; yes, remove it from the buffer
	mov	al,CHR_CTRLD		; and report an ABORT (carry clear)
	jcxz	ch9
	push	ds
	mov	ds,cx
	ASSUME	DS:NOTHING
	or	ds:[CT_STATUS],CTSTAT_ABORT
	pop	ds
	ASSUME	DS:BIOS
	jmp	short ch9
;
; In raw keys mode, CTRLC, CTRLS, and CTRLP are just keys (eg, for VI's
; WordStar keys).
;
ch1a:	jcxz	ch1b
	push	ds
	mov	ds,cx
	ASSUME	DS:NOTHING
	test	ds:[CT_STATUS],CTSTAT_RAWKEYS
	pop	ds
	ASSUME	DS:BIOS
	jnz	ch0a			; raw keys mode
;
; CTRLC is reported to DOS and left in the buffer, and that's all; the driver
; doesn't discard any type-ahead or end any pause, since DOS does that
; consistently for every console device (see DDC_INFLUSH and DDC_OUTFLUSH).
;
ch1b:	cmp	al,CHR_CTRLC		; CTRLC?
	je	ch9			; yes, return carry clear
;
; Do PAUSE checks next, because only CTRLS toggles PAUSE, and everything else
; disables it.
;
	jcxz	ch6
	push	ds
	mov	ds,cx
	ASSUME	DS:NOTHING
	ASSERT	STRUCT,ds:[0],CT
;
; This is currently the sole use of CTSTAT_INPUT: to avoid treating CTRLS as
; a pause key if the context is waiting for input.  This makes it possible for
; the CONIO buffered input code to use CTRLS for input control as well.
;
	test	ds:[CT_STATUS],CTSTAT_INPUT
	stc
	jnz	ch3
	cmp	al,CHR_CTRLS		; CTRLS?
	jne	ch2			; no (anything else unpauses)
	xor	ds:[CT_STATUS],CTSTAT_PAUSED
	jmp	short ch3
ch2:	test	ds:[CT_STATUS],CTSTAT_PAUSED
	stc
	jz	ch3
	and	ds:[CT_STATUS],NOT CTSTAT_PAUSED
ch3:	pop	ds
	ASSUME	DS:BIOS
	jc	ch6
	mov	[BUFFER_TAIL],bx	; update tail, consuming the character
	jmp	short ch8

ch6:	cmp	al,CHR_CTRLP		; CTRLP?
	je	ch9			; yes, return carry clear

ch8:	stc
ch9:	pop	ds
	ret
ENDPROC	check_hotkey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; draw_border
;
; Inputs:
;	DS = CONSOLE context
;	If DS matches ct_focus, then a double-wide border will be drawn
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	draw_border
	test	ds:[CT_STATUS],CTSTAT_BORDER
	jz	db9
	mov	ax,ds
	call	chk_blocked		; is another context blocking us?
	jc	db9			; yes, so leave the screen alone
	mov	si,offset DBL_BORDER
	cmp	ax,[ct_focus]
	je	db1
	mov	si,offset SGL_BORDER
db1:	sub	dx,dx			; get top left X,Y (DL,DH)
	mov	bx,ds:[CT_CONDIM]	; get bottom right X,Y (BL,BH)
	lods	word ptr cs:[si]
	xchg	cx,ax
	call	draw_vertpair
	ASSUME	ES:NOTHING
	lods	word ptr cs:[si]
	xchg	cx,ax
db2:	inc	dh			; advance Y, holding X constant
	cmp	dh,bh
	jae	db3
	call	draw_vertpair
	jmp	db2
db3:	lods	word ptr cs:[si]
	xchg	cx,ax
	call	draw_vertpair
	lods	word ptr cs:[si]
	xchg	cx,ax
db4:	mov	dh,0
	inc	dx			; advance X, holding Y constant
	cmp	dl,bl
	jae	db9
	call	draw_horzpair
	jmp	db4
db9:	ret
ENDPROC	draw_border

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; draw_char
;
; Inputs:
;	CL = character
;	DX = CURPOS (DL,DH)
;	DS = CONSOLE context
;
; Outputs:
;	Updates cursor position in (DL,DH)
;
; Modifies:
;	AX, DX, DI, ES
;
DEFPROC	draw_char
	push	cx
	mov	ch,1			; CH = amount to advance DL
	cmp	cl,CHR_BACKSPACE
	jne	dc1
;
; This code treats CHR_BACKSPACE as a "destructive" backspace (ie, erasing
; the character underneath the cursor first), which means changing CL to
; CHR_SPACE and not advancing DL afterward.  That is done primarily as an
; optimization for the DOS CONIO functions, which would otherwise have to
; output 3 characters (backspace, space, backspace again) to do the same thing.
;
	mov	cl,CHR_SPACE		; make this "destructive"
	dec	ch			; no advance for backspace
	dec	dl
	cmp	dl,ds:[CT_CURMIN].LOB
	jge	dc1
	mov	dl,ds:[CT_CURMAX].LOB
	dec	dh
	cmp	dh,ds:[CT_CURMIN].HIB
	jge	dc1
	mov	dx,ds:[CT_CURMIN]

dc1:	mov	ah,ds:[CT_COLOR].LOB	; AH = attributes
	call	write_curpos		; write CL at (DL,DH)
;
; Advance DL, advance DH as needed, and scroll the context as needed.
;
	add	dl,ch			; advance DL
	pop	cx

	cmp	dl,ds:[CT_CURMAX].LOB
	jle	dc9
	mov	dl,ds:[CT_CURMIN].LOB

;
; On the last scrolling row, the scrolling rows scroll; on any other row, the
; cursor moves down (unless it's on the last row of the context, below the
; scrolling rows).
;
	DEFLBL	draw_linefeed,near
	cmp	dh,ds:[CT_SCRMAX].HIB
	je	dc2
	cmp	dh,ds:[CT_CURMAX].HIB
	jge	dc9
	inc	dh
	ret
dc2:	push	cx
	mov	cl,1
	call	scroll			; scroll the rows up 1 line
	pop	cx
dc9:	ret
ENDPROC	draw_char

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; draw_cursor
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	draw_cursor
;
; A context that another context is blocking isn't on the screen, so the
; cursor there isn't ours to move (see chk_blocked).
;
	mov	ax,ds
	call	chk_blocked
	jc	dcu9
	mov	dx,ds:[CT_CURPOS]
	test	ds:[CT_STATUS],CTSTAT_INT10
	jnz	dcs8
	call	get_curpos		; BX = screen offset for CURPOS
	add	bx,ds:[CT_SCREEN].OFF	; add the context's buffer offset

	DEFLBL	set_cursor,near
	shr	bx,1			; screen offset to cell offset
	mov	ah,CRTC_CURHI		; AH = 6845 CURSOR ADDR (HI) register
	call	write_crtc16		; update cursor position using BX
dcu9:	ret
;
; The context is using INT 10h passthrough, so position the cursor using
; INT 10h as well; otherwise, an emulator like pc.js wouldn't see the cursor
; move back after a destructive backspace (see draw_char).
;
dcs8:	add	dx,ds:[CT_CONPOS]	; DL = screen col, DH = screen row
	mov	bh,ds:[CT_PAGE]		; BH = display page
	mov	ah,VIDEO_SETCPOS
	jmp	video_ctx
ENDPROC	draw_cursor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; draw_horzpair
;
; Inputs:
;	CH = top char
;	CL = bottom char
;	DL,DH = top X,Y
;	BL,BH = bottom X,Y
;	DS = CONSOLE context
;
; Modifies:
;	DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	draw_horzpair
	mov	ah,ds:[CT_COLOR].HIB
	xchg	cl,ch
	call	write_curpos
	xchg	cl,ch
	xchg	dh,bh
	call	write_curpos
	xchg	dh,bh
	ret
ENDPROC	draw_horzpair

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; draw_vertpair
;
; Inputs:
;	CH = left char
;	CL = right char
;	DL,DH = left X,Y
;	BL,BH = right X,Y
;	DS = CONSOLE context
;
; Modifies:
;	DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	draw_vertpair
	mov	ah,ds:[CT_COLOR].HIB
	xchg	cl,ch
	call	write_curpos
	xchg	dl,bl
	xchg	cl,ch
	call	write_curpos
	xchg	dl,bl
	ret
ENDPROC	draw_vertpair

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_curpos
;
; Inputs:
;	DX = CURPOS (DL,DH)
;	DS = CONSOLE context
;
; Outputs:
;	BX -> screen buffer offset
;
; Modifies:
;	BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_curpos
	push	ax
	mov	al,dh
	mul	ds:[CT_COLS].LOB	; (the columns of the context's mode)
	add	ax,ax			; AX = offset to row
	sub	bx,bx
	mov	bl,dl
	add	bx,bx
	add	bx,ax			; BX = offset to row and col
	pop	ax
	ret
ENDPROC	get_curpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hide_cursor
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	hide_cursor
;
; If the context with focus is blocked, then the cursor on the screen belongs
; to the context that's blocking it, and stays there.
;
	mov	ax,[ct_focus]
	call	chk_blocked
	jc	hc9
	mov	bx,4000			; (an offset past the visible screen)
	jmp	set_cursor
hc9:	ret
ENDPROC	hide_cursor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; move_cursor
;
; Inputs:
;	DS = CONSOLE context
;	CX = +/- position delta
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	move_cursor
	mov	dx,ds:[CT_CURPOS]	; DX = current cursor position
	xchg	ax,cx
	idiv	ds:[CT_CURDIM].LOB	; AL = # lines, AH = # columns (signed)

mc1:	add	dh,al
	cmp	dh,ds:[CT_CURMIN].HIB
	jge	mc1a
	mov	dh,ds:[CT_CURMIN].HIB
mc1a:	cmp	dh,ds:[CT_CURMAX].HIB
	jle	mc2
	mov	dh,ds:[CT_CURMAX].HIB

mc2:	add	dl,ah
	cmp	dl,ds:[CT_CURMIN].LOB
	jge	mc2a
	add	dl,ds:[CT_CURMAX].LOB
	inc	dl
	sub	dl,ds:[CT_CURMIN].LOB
	cmp	dh,ds:[CT_CURMIN].HIB
	jle	mc2a
	dec	dh

mc2a:	cmp	dl,ds:[CT_CURMAX].LOB
	jle	mc8
	sub	dl,ds:[CT_CURMAX].LOB
	dec	dl
	add	dl,ds:[CT_CURMIN].LOB
	cmp	dh,ds:[CT_CURMAX].HIB
	jge	mc8
	inc	dh

	DEFLBL	update_cursor,near
mc8:	mov	ds:[CT_CURPOS],dx
	mov	ax,ds
;
; Interrupts stay off from the focus check until the cursor is drawn (see
; write_crtc16); otherwise, a focus switch at interrupt time could come
; between them, and we'd then move the new focus context's cursor to our
; position.
;
	cli
	cmp	ax,[ct_focus]		; does this context have focus?
	jne	mc9			; no, leave cursor alone
	call	draw_cursor
mc9:	sti
	clc
	ret
ENDPROC	move_cursor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pull_kbd
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if request satisfied, set if not
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pull_kbd
	push	bx
	push	ds
;
; A non-ASCII key (eg, a cursor key) is returned as a zero followed by its
; scan code, as on PC DOS, so the scan code is held in CT_SCAN until then;
; the DOS line editor maps those keys to its editing keys (see read_line).
;
pl1:	mov	ds,es:[di].DDP_CONTEXT
	sub	ax,ax
	xchg	al,ds:[CT_SCAN]
	test	al,al			; pending scan code?
	jnz	pl7			; yes

	mov	bx,BIOS
	mov	ds,bx
	ASSUME	DS:BIOS
	cli
	mov	bx,[BUFFER_HEAD]
	cmp	bx,[BUFFER_TAIL]
	stc
	je	pl3			; BIOS buffer empty
	mov	ax,[bx]			; AL = char code, AH = scan code
	add	bx,2
	cmp	bx,offset KB_BUFFER + size KB_BUFFER
	jne	pl2
	sub	bx,size KB_BUFFER
pl2:	mov	[BUFFER_HEAD],bx
	clc
pl3:	sti
	jc	pl9

	test	al,al			; ASCII zero?
	jz	pl4			; yes, must be a special-function key
	cmp	al,0E0h			; ditto for E0h, which future keyboards
	jne	pl7			; may generate....
pl4:	mov	ds,es:[di].DDP_CONTEXT
	mov	ds:[CT_SCAN],ah		; return the scan code next
	mov	al,0

pl7:	lds	bx,es:[di].DDPRW_ADDR	; DS:BX -> next read/write address
	ASSUME	DS:NOTHING
	mov	[bx],al
	IFDEF MAXDEBUG
	test	al,al
	jnz	pl8
	xchg	al,ah
	DPRINTF	<"null character, scan code %#04x\r\n">,ax
	ENDIF
pl8:	inc	bx
	mov	es:[di].DDPRW_ADDR.OFF,bx
	dec	es:[di].DDPRW_LENGTH	; have we satisfied the request yet?
	jnz	pl1			; no
	clc

pl9:	pop	ds
	ASSUME	DS:NOTHING
	pop	bx
	ret
ENDPROC	pull_kbd

CODE	ends

DATA	segment para public 'DATA'

ddcon_end	db	16 dup(0)

DATA	ends

	end
