;
; BASIC-DOS Video and Keyboard (VKD$) Device Driver: Video
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The driver's video code (scrolling, pages, focus, modes, and writing), which
; is linked after condev.asm, and ends with the driver's initialization code
; (ddcon_init), which is where the resident code ends.
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

DEV	group	CODE

CODE	segment byte public 'CODE'

	EXTBYTE	<adapters,bios_lock,max_cols,max_rows,req_switch,shown_page>
	EXTBYTE	<one_con,mode_hid>
	EXTWORD	<bios_ctx,con_place,ct_focus,ct_head,frame_seg,mode_ctx>
	EXTWORD	<save_seg,save_addr,vga_addr,vga_state>
	extrn	ddcon_int09:far
	extrn	ddcon_int10:far
	extrn	ddcon_int29:far
	extrn	ddcon_req:far
	EXTNEAR	<draw_border,draw_char,draw_cursor,draw_linefeed,free_buf>
	EXTNEAR	<get_curpos,hide_cursor,update_cursor,alloc_sys,set_gfxclr>
	EXTNEAR	<free_seg>
	EXTLONG	<kbd_int,video_int,wait_ptr>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scroll
;
; Set CL to +/- lines to scroll (negative scrolls down).  To clear all the
; scrolling rows (the entire interior, unless ddcon_scroll changed them), set
; CL >= # lines (eg, 100).  To clear the entire context, including any border,
; set CL to zero (typically only done when destroying a context).
;
; Inputs:
;	CL = # lines
;	DS = CONSOLE context
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	scroll
	push	bx
	push	cx
	push	dx
	xchg	ax,cx			; AL = # lines now
	mov	bl,VIDEO_SCROLL		; scroll up # lines in AL
	mov	cx,ds:[CT_CONPOS]
	mov	dx,cx
	test	al,al			; zero?
	jnz	scr0			; no
	add	dx,ds:[CT_CONDIM]	; yes, clear entire context
	jmp	short scr2		; (including border, if any)
scr0:	jns	scr0a			; scroll down (negative)?
	neg	al			; yes
	mov	bl,VIDEO_SCROLLDN
scr0a:	cmp	al,ds:[CT_CONDIM].HB
	jb	scr1
	mov	al,0			; zero tells BIOS to clear all lines
scr1:	add	cx,ds:[CT_SCRMIN]	; CH = row, CL = col of upper left
	add	dx,ds:[CT_SCRMAX]	; DH = row, DL = col of lower right
scr2:	mov	bh,ds:[CT_COLOR].LB	; BH = fill attributes
;
; An MDA underlines a space whose attributes are 01h (or 09h, etc), so if
; those are the current attributes (eg, after COLOR 1 or COLOR 9), the new
; lines get 07h (or 0Fh, etc) instead, rather than staying underlined after
; the attributes change; a CGA's 01h is blue, which a space doesn't show.
;
	mov	ah,77h
	and	ah,bh
	dec	ah			; underlined (01h)?
	jnz	scr2a			; no
	or	bh,06h			; yes, so use 07h
scr2a:	call	chk_graphics		; graphics mode?
	jnc	scr3			; no
	mov	bh,0			; yes, BH = fill pixels (background)
;
; The BIOS scrolls a context only if it has the entire screen (see mode_ctx
; and update_mode) or the context's page is displayed
; (the mouse driver hides its pointer around a BIOS scroll); otherwise, we
; scroll the page ourselves, with no BIOS data to update (and a virtual page
; is one the BIOS can't reach anyway), as we do for a context that another
; context is blocking (whose page may be in a buffer; see save_screen).
;
; A focus switch at interrupt time can change which page is displayed, and
; move the context to or from a virtual page (see swap_page), so interrupts
; stay off from this check until the BIOS is locked (by scroll_buf, or by
; ddcon_int10; see video_ctx).
;
scr3:	mov	ah,bl
	cli
	push	bx
	mov	bx,ds
	cmp	bx,[mode_ctx]		; does it have the entire screen?
	je	scr4			; yes
	xchg	ax,bx
	call	chk_blocked		; is another context blocking it?
	xchg	ax,bx
	jc	scr3a			; yes
	call	get_place		; BX = con_place index
	mov	bl,shown_page[bx]
	cmp	bl,ds:[CT_PAGE]		; is the context's page displayed?
	je	scr4			; yes
scr3a:	pop	bx
	call	scroll_buf
	jmp	short scr9
scr4:	pop	bx
	call	video_ctx
scr9:	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	scroll

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; video_ctx
;
; Issues INT 10h on behalf of a context, which ddcon_int10 uses instead of the
; session's context, and without waiting for the context to have focus.
;
; Inputs:
;	DS = CONSOLE context
;	Other inputs are those of the INT 10h function
;
; Outputs:
;	Those of the INT 10h function
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	video_ctx
	cli
	push	es
	mov	es,cs:[0].DDH_DATA
	ASSUME	ES:CODE
	mov	[bios_ctx],ds
	pop	es
	ASSUME	ES:NOTHING
	int	INT_VIDEO
	sti
	ret
ENDPROC	video_ctx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; wait_focus
;
; Waits until the context has focus, unless it's the context that is blocking
; the others (mode_ctx), which owns the screen whether it has focus or not
; (unless it's hidden; see hide_mode).
; The wait ID is the context segment with an offset of 1 (which no packet
; has); switch_focus ends the wait.
;
; Inputs:
;	AX = CONSOLE context
;	Interrupts off (so that no focus switch comes between the check and
;	the wait)
;
; Outputs:
;	ZF set (and carry clear) if no wait was needed; otherwise, ZF clear,
;	and carry set if the wait was interrupted (eg, by ABORT)
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	wait_focus
	cmp	ax,[ct_focus]		; does the context have focus?
	je	wf9			; yes
	cmp	ax,[mode_ctx]		; is it blocking the others?
	jne	wf1			; no
	call	chk_blocked		; yes, unless it's hidden
	jnc	wf9
wf1:	push	dx
	push	di
	mov	dx,ax
	mov	di,1			; DX:DI = wait ID
	mov	ah,DOS_UTL_WAIT		; (int_util preserves all but carry,
	call	far ptr DDINT_UTIL	; so ZF is still clear)
	mov	ax,dx
	pop	di
	pop	dx
wf9:	ret
ENDPROC	wait_focus

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_snow
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	Carry set if the context's page is in a CGA's video memory (not an
;	EGA's or VGA's, which have no "snow"; see ddcon_init)
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_snow
	call	chk_vpage
	cmc
	jnc	cn9			; it's on a virtual page
	cmp	ds:[CT_PORT].LB,0B5h	; carry set if it's an MDA (0B4h)
	cmc
	jnc	cn9
	ASSERT	ADAPTER_EGA,GT,<ADAPTER_MDA OR ADAPTER_CGA>
	cmp	[adapters],ADAPTER_EGA	; carry clear if it's an EGA or VGA
cn9:	ret
ENDPROC	chk_snow

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_curtype
;
; Sets the hardware cursor to the current type (ie, shape).
;
; Inputs:
;	DS = CONSOLE context
;
; Modifies:
;	AX, CX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_curtype
;
; While the following code works just fine (aside from modifying slightly
; different registers), it's better to use the BIOS, because it turns out
; later BIOSes will perform cursor emulation, which automatically converts
; CGA-based cursor sizes (0-7) to higher-res values.
;
	; mov	bx,ds:[CT_CURTYPE]	; BX = new values
	; mov	ah,CRTC_CURTOP		; AH = 6845 register #
	; jmp	write_crtc16		; write them
;
; Unfortunately, when we call the BIOS here, we are NOT necessarily running
; in the session for which the call is intended.  When we're called from
; ddcon_setins, we are, but when we're called from show_cursor, which is
; called from switch_focus, we may not be.
;
; The simplest solution is to call update_biosdata and then invoke the
; original INT 10h code, bypassing ddcon_int10.  Be aware that this will be
; required for any video BIOS call made on behalf of a context that is not
; ALSO the running context.
;
	mov	ax,ds
	call	chk_blocked		; (see draw_cursor)
	jc	sct9
	call	update_biosdata
	mov	cx,ds:[CT_CURTYPE]
	mov	ah,VIDEO_SETCTYPE
	pushf
	call	[video_int]
sct9:	ret
ENDPROC	set_curtype

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; show_cursor
;
; Wrapper for draw_cursor and set_curtype (used when switching focus).
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	show_cursor
	call	draw_cursor
	jmp	set_curtype
ENDPROC	show_cursor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; unlock_bios
;
; While locking is as simple as incrementing bios_lock, unlocking requires
; decrementing, checking for an unlocked (zero) state, and then checking for
; any pending switch requests.
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	unlock_bios
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	dec	[bios_lock]		; BIOS unlocked now?
	jnz	ub9			; no
	mov	al,0
	xchg	[req_switch],al
	test	al,al			; pending switch request?
	jz	ub9			; no
	push	bx
	push	cx
	push	dx
	mov	cx,[ct_focus]		; CX = context
	call	switch_now		; perform the requested switch now
	pop	dx
	pop	cx
	pop	bx
ub9:	pop	ds
	ASSUME	DS:NOTHING
	ret
ENDPROC	unlock_bios

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_graphics
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	Carry set if the context's video mode is a (CGA) graphics mode (4-6)
;
; Modifies:
;	AH
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_graphics
	mov	ah,ds:[CT_MODE]
	sub	ah,4
	cmp	ah,3
	ret
ENDPROC	chk_graphics

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_blocked
;
; While a context is in any mode other than its original mode (see
; update_mode), every other context on the same adapter is blocked: it can't
; display its page, move the cursor, or change the mode, and unless its
; memory is in a buffer (see chk_output), its output waits (see ddcon_write
; and ddcon_ioctl) and its border isn't drawn, until that context returns to
; its original mode (see release_mode).  While that context is hidden
; instead (see hide_mode), it's the only one that's blocked, but chk_mode
; still says that another context has the screen, since none of the others
; can change the mode until it returns.
;
; Inputs:
;	AX = CONSOLE context
;
; Outputs:
;	Carry set if the context is blocked
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_mode
	push	cx
	mov	cl,0			; (as if mode_ctx isn't hidden)
	jmp	short cb0
ENDPROC	chk_mode

	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_blocked
	push	cx
	mov	cl,[mode_hid]
cb0:	push	bx
	push	ds
	mov	bx,[mode_ctx]
	test	bx,bx			; is any context blocking the others?
	jz	cb9			; no (and carry is clear)
	cmp	bx,ax			; is it this context?
	je	cb8			; yes (and carry is clear)
	mov	ds,bx
	mov	bx,ds:[CT_PORT]
	mov	ds,ax
	cmp	bx,ds:[CT_PORT]		; is this context on the same adapter?
	clc
	jne	cb9			; no
	stc				; yes
cb8:	sbb	bl,bl			; BL = FFh if it's another context
	xor	bl,cl			; (or if it's this one, and hidden)
	shr	bl,1			; carry set if it's blocked
cb9:	pop	ds
	pop	bx
	pop	cx
	ret
ENDPROC	chk_blocked

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; release_mode
;
; Called when the context blocking the others (mode_ctx) returns to its
; original mode (or is closed): the borders of the other contexts on the same
; adapter are redrawn, and every waiting write (or IOCTL) can try again (see
; release_now).  The only console (see con_opt) blocks nothing, so it just
; gets its cursor back (and update_mode redraws its border).
;
; Inputs:
;	DS = CONSOLE context (mode_ctx)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	release_mode
	mov	es,cs:[0].DDH_DATA
	ASSUME	ES:CODE
	mov	[mode_ctx],0
	ASSUME	ES:NOTHING
	call	chk_opt			; one console only?
	jc	show_cursor		; yes
	jmp	release_now		; no (see con_opt)
ENDPROC	release_mode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_output
;
; The output of a blocked context goes on if its memory is a buffer (a
; virtual page, or the copy of the adapter's memory that save_screen made);
; only output to the adapter's memory waits.  The only console is never
; blocked, so the rest of this is after con_opt.
;
; Inputs:
;	AX = CONSOLE context
;
; Outputs:
;	Carry set if the context's output must wait
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_output
	call	chk_blocked		; is another context blocking it?
	jnc	cot9			; no
	jmp	chk_saved		; yes (see con_opt)
cot9:	ret
ENDPROC	chk_output

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; slot_addr
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	DX:CX = address of the context's adapter's video memory, SI:DI = length
;
; Modifies:
;	AX, CX, DX, SI, DI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	slot_addr
	call	get_frame
	mov	di,4000h		; 16K for a CGA
	cmp	ah,0B8h			; is it one?
	je	sa1			; yes
	mov	di,1000h		; 4K for an MDA
sa1:	mov	cx,16
	mul	cx
	xchg	cx,ax			; DX:CX = its address
	sub	si,si			; SI:DI = its length
	ret
ENDPROC	slot_addr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_sesctx
;
; Outputs:
;	AX = the current session's context and ZF clear if it's one of ours;
;	otherwise, AX is zero and ZF is set (see chk_context)
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_sesctx
	mov	ah,DOS_UTL_LOCK
	call	far ptr DDINT_UTIL	; AX = the session's context
	push	ax
	mov	ah,DOS_UTL_UNLOCK
	call	far ptr DDINT_UTIL
	pop	ax
ENDPROC	get_sesctx			; fall into chk_context

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_context
;
; Verify that a context (eg, the active session's context returned by
; DOSUTIL LOCK) is one of our contexts, since a session's console may be
; another device (eg, CON=COM1:9600,N,8,1 in CONFIG.SYS).
;
; Inputs:
;	AX = context segment (zero if none)
;
; Outputs:
;	If the context is ours, AX is unchanged and ZF is clear;
;	otherwise, AX is zero and ZF is set
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_context
	push	cx
	push	ds
	mov	cx,[ct_head]		; CX = 1st context
cx1:	jcxz	cx8			; no more contexts
	cmp	ax,cx			; is this the context?
	je	cx9			; yes (and ZF is set, so clear it below)
	mov	ds,cx
	mov	cx,ds:[CT_NEXT]		; CX = next context
	jmp	cx1
cx8:	sub	ax,ax			; not ours, so zero AX (and set ZF)
	jmp	short cx9a
cx9:	test	ax,ax			; clear ZF (AX can't be zero here)
cx9a:	pop	ds
	pop	cx
	ret
ENDPROC	chk_context

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; update_biosdata
;
; Called whenever the BIOS data should be updated to reflect current context
; state.  The main benefit is improved compatibility with apps that bypass our
; services (ie, access the BIOS directly).
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	AX = previous EQUIP_FLAG
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	update_biosdata
	push	es
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	ASSERT	STRUCT,ds:[0],CT

	mov	al,ds:[CT_MODE]
	xchg	[CRT_MODE],al
	mov	ds:[CTS_MODE],al

	mov	ax,ds:[CT_COLS]
	xchg	[CRT_COLS],ax
	mov	ds:[CTS_COLS],ax

	mov	ax,ds:[CT_PORT]
	xchg	[ADDR_6845],ax
	mov	ds:[CTS_PORT],ax

	mov	ax,ds:[CT_CURTYPE]
	mov	[CURSOR_MODE],ax
;
; To the BIOS, the context's page is the active page (eg, so that a BIOS
; scroll affects that page), whether or not it's displayed (see show_page).
;
	mov	al,ds:[CT_PAGE]
	xchg	[ACTIVE_PAGE],al
	mov	ds:[CTS_PAGE],al

	call	get_start
	xchg	[CRT_START],ax
	mov	ds:[CTS_START],ax

	push	bx
	mov	bl,ds:[CT_PAGE]
	mov	bh,0
	add	bx,bx			; BX = page's index in CURSOR_POSN
	mov	ax,ds:[CT_CURPOS]	; AX = cursor pos within context
	add	ax,ds:[CT_CONPOS]	; add context pos to get screen pos
	mov	CURSOR_POSN[bx],ax
	pop	bx

	mov	ax,ds:[CT_EQUIP]
	xchg	[EQUIP_FLAG],ax
	pop	es
	ret
ENDPROC	update_biosdata

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_rows
;
; If ddcon_setmode asked for more than 25 rows (CT_ROWS, which applies only
; to this mode set), the BIOS gives us those rows when we load its 8x8 font
; (while the BIOS data still describes this context).  An EGA's BIOS assumes
; 14-line characters when it converts cursor types, which would hide the
; cursor in 8-line characters, so its cursor emulation is turned off as long
; as the rows are displayed (bit 0 of EGA_MISC_INFO), and a VGA goes back to
; 400 scan lines at its next mode set, whoever sets it.
;
; Inputs:
;	DS = CONSOLE context (whose mode the BIOS just set)
;
; Outputs:
;	CH = rows
;
; Modifies:
;	CH, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_rows
	mov	ch,25
	test	[adapters],ADAPTER_EGA
	jz	sr9
	push	ax
	push	bx
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	and	[EGA_MISC_INFO],NOT 1
	mov	bl,0
	xchg	bl,ds:[CT_ROWS]
	test	bl,bl			; more rows?
	jz	sr8			; no
	mov	ch,bl
	or	[EGA_MISC_INFO],1
	ASSUME	ES:NOTHING
	mov	ax,VIDEO_FONT8X8
	mov	bl,0			; (font block 0)
	pushf
	call	[video_int]
	mov	ax,(VIDEO_ALTSEL SHL 8) OR 2
	mov	bl,VALT_SCANLINES
	pushf
	call	[video_int]
sr8:	pop	bx
	pop	ax
sr9:	ret
ENDPROC	set_rows

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; update_mode
;
; This is update_context for video mode changes, whether they come from
; IOCTL_SETMODE or from anyone else calling INT 10h directly.
;
; A mode change affects the entire screen, so in any mode other than the one
; it was created in, the context becomes a full-screen context with no border.
; In a text mode (0-3), the VKD$ driver still writes directly to the screen
; (see get_curpos, which uses the mode's columns); in any other mode, it uses
; INT 10h passthrough (CTSTAT_INT10), which allows text output to work in
; graphics modes, where text is always drawn in color 3.  When the mode is set
; back to the original mode, the context's original geometry (including any
; border) is restored.
;
; A text mode that set_pmode sets in place enters at um0c instead, since the
; BIOS has nothing to tell us: the context stays on its own page (AH), and
; it blocks no other context (SI is non-zero).
;
; Inputs:
;	DS = CONSOLE context
;	AX = previous EQUIP_FLAG
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	update_mode
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es
	mov	bl,ds:[CT_MODE]		; BL = previous mode
	call	set_rows		; CH = rows
	call	update_context		; update CT_MODE, CT_COLS, etc
	sub	si,si			; SI = 0 (the BIOS set the mode)
	mov	ah,0			; AH = page 0
um0c:	mov	cl,ds:[CT_COLS].LB	; CX = full screen
	sub	dx,dx			; DX = top left
	mov	al,ds:[CT_MODE]
	cmp	al,MODE_CO80+1		; carry set if it's a text mode (0-3)
	cmc
	sbb	bh,bh
	and	bh,CTSTAT_INT10		; BH = no border, passthrough if not
	cmp	al,ds:[CTO_MODE]	; back to the original mode?
	jne	um1			; no
	cmp	ch,25			; (which always has 25 rows)
	jne	um1
	mov	cx,ds:[CTO_DIM]		; yes, so restore the original geometry
	mov	dx,ds:[CTO_POS]
	mov	bh,ds:[CTO_STATUS]
	mov	ah,ds:[CTO_PAGE]
um1:	mov	ds:[CT_PAGE],ah
	mov	al,ds:[CT_STATUS]
	and	al,NOT (CTSTAT_BORDER OR CTSTAT_INT10)
	or	al,bh
	mov	ds:[CT_STATUS],al
	call	set_geometry
	mov	ax,ds:[CT_CURMIN]
	mov	ds:[CT_CURPOS],ax	; (the BIOS homes the cursor, too)
	mov	ax,ds:[CT_DEFTYPE]
	mov	ds:[CT_CURTYPE],ax	; (and resets its type)
;
; Graphics modes start with text color 3, background 0, and palette 1 (the
; BIOS default).  Text modes keep the current colors, unless we're leaving a
; graphics mode, in which case the default colors are restored.
;
; A context in any mode other than its original mode occupies the entire
; screen (and the BIOS cleared it), so it also blocks every other context on
; the same adapter (see chk_blocked), until it returns to its original mode
; (see release_mode).  A mode that the BIOS set without that (eg, the same
; mode, for a context that shares its page) releases the memory of the other
; contexts that save_screen saved, too.
;
	mov	al,ds:[CT_MODE]
	cmp	al,ds:[CTO_MODE]	; back to the original mode?
	jne	um5			; no
	cmp	ds:[CT_CONDIM].HB,25	; (and not with more than 25 rows?)
	jb	um6			; yes
um5:	test	si,si			; was the mode set in place?
	jnz	um6			; yes, so there's nothing to block
	push	es
	mov	es,cs:[0].DDH_DATA
	ASSUME	ES:CODE
	mov	[mode_ctx],ds		; no, so block the other contexts
	pop	es
	ASSUME	ES:NOTHING
	call	chk_opt			; one console only?
	jc	um7			; yes, so there are no others
	push	bx
	call	update_slots		; (and their video memory selectors)
	pop	bx
	jmp	short um7
um6:	mov	ax,ds
	cmp	ax,[mode_ctx]		; was this context blocking the others?
	je	um6a			; yes
	cmp	[save_seg],0		; or did it save their memory anyway?
	je	um7			; no
um6a:	push	bx
	call	release_mode		; yes, so unblock them
	pop	bx
um7:	mov	ax,1003h
	call	chk_graphics		; new mode graphics?
	jc	um8			; yes
	sub	bl,4
	cmp	bl,3			; old mode graphics?
	jae	um9			; no
	mov	ax,0707h
um8:	mov	ds:[CT_COLOR],ax
um9:	call	draw_border		; redraw the border, if any
;
; The BIOS displays page 0 after a mode change, so display the page of the
; context with focus again (which may also exchange a virtual page that the
; mode change displayed for another context; see swap_page).
;
	push	ds
	mov	ds,[ct_focus]
	call	show_page
	pop	ds
	pop	es
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	update_mode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_geometry
;
; Sets the context's dimensions and position, and then determines the cursor
; minimums and maximums from the context size, and the offset of the context
; on the screen (within its page).
;
; Inputs:
;	CL = columns, CH = rows
;	DL = x, DH = y (of the top left)
;	BH = CTSTAT_BORDER bit (set if the context has a border)
;	DS = CONSOLE context (with CT_PAGE set)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_geometry
	mov	ax,0101h
	push	cx
	sub	cx,ax
	mov	ds:[CT_CONDIM],cx	; set CT_CONDIM (CL,CH)
	mov	ds:[CT_CONPOS],dx	; set CT_CONPOS (DL,DH)
	mov	al,bh
	and	al,CTSTAT_BORDER
	mov	ah,al			; AX = 0101h for border, 0000h for none
	mov	ds:[CT_CURMIN],ax	; set CT_CURMIN (AL,AH)
	mov	ds:[CT_SCRMIN],ax	; (every row is a scrolling row)
	sub	cx,ax
	mov	ds:[CT_CURMAX],cx	; set CT_CURMAX (CL,CH)
	mov	ds:[CT_SCRMAX],cx
	pop	cx
	sub	cx,ax
	sub	cx,ax
	mov	ds:[CT_CURDIM],cx	; set CT_CURDIM (width and height)
	call	get_start
	xchg	cx,ax			; CX = offset of the page
	mov	al,dh
	mul	[max_cols]
	add	ax,ax
	mov	dh,0
	add	dx,dx
	add	ax,dx
	add	ax,cx
	mov	ds:[CT_SCREEN]._OFF,ax
	ret
ENDPROC	set_geometry

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_start
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	AX = offset of the context's page (4K per page)
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_start
	sub	ax,ax
	call	chk_vpage		; is the page virtual?
	jc	gs9			; yes, so it starts at offset 0
	mov	al,16
	mul	ds:[CT_PAGE]
	xchg	al,ah			; AX = page * 1000h
gs9:	ret
ENDPROC	get_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_place
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	BX = con_place index of the context's adapter (0 or 4)
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_place
	mov	bl,ds:[CT_STATUS]
	and	bx,CTSTAT_ADAPTER	; BX = 0 or 2
	shl	bx,1
	ret
ENDPROC	get_place

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_vpage
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	Carry set if the context is on a virtual page (see swap_page)
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_vpage
	push	bx
	call	get_place
	mov	bl,byte ptr con_place[bx+3]	; BL = # pages of the adapter
	cmp	ds:[CT_PAGE],bl		; is the page beyond them?
	cmc				; (carry set if so)
	pop	bx
	ret
ENDPROC	chk_vpage

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_frame
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	AX = segment of the context's adapter's video memory
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_frame
	mov	ax,0B000h
	cmp	ds:[CT_PORT].LB,0B4h	; monochrome adapter?
	je	gf9			; yes
	mov	ah,0B8h
gf9:	ret
ENDPROC	get_frame

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; update_context
;
; This is the reverse of update_biosdata.
;
; Inputs:
;	DS = CONSOLE context
;	AX = previous EQUIP_FLAG
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	update_context
	push	es
	push	ax
	mov	ax,BIOS
	mov	es,ax
	pop	ax
	ASSUME	ES:BIOS
	mov	[EQUIP_FLAG],ax

	mov	al,ds:[CTS_MODE]
	xchg	[CRT_MODE],al
	mov	ds:[CT_MODE],al

	mov	ax,ds:[CTS_COLS]
	xchg	[CRT_COLS],ax
	mov	ds:[CT_COLS],ax

	mov	ax,ds:[CTS_PORT]
	mov	[ADDR_6845],ax

	mov	al,ds:[CTS_PAGE]
	mov	[ACTIVE_PAGE],al

	mov	ax,ds:[CTS_START]
	mov	[CRT_START],ax

	; mov	ax,[CURSOR_MODE]	; we don't trust CURSOR_MODE
	; mov	ds:[CT_CURTYPE],ax	; update_curtype explains why

	push	bx
	mov	bl,ds:[CT_PAGE]
	mov	bh,0
	add	bx,bx			; BX = page's index in CURSOR_POSN
	mov	ax,CURSOR_POSN[bx]
	pop	bx
	sub	ax,ds:[CT_CONPOS]
	mov	ds:[CT_CURPOS],ax
	pop	es
	ret
ENDPROC	update_context

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; update_curtype
;
; Due to a bug in the original IBM PC (5150) BIOS, the initial cursor top and
; bottom scan lines are stored in the high and low *nibbles* of CURSOR_MODE.LB
; instead of the high and low *bytes* of CURSOR_MODE.  Here's the buggy code:
;
;	F177:	C70660006700	MOV	CURSOR_MODE,67H
;
; So, we'll check for that combo (ie, 67h low, 00h high) and compensate.
;
; What's worse is that the same initial values (6,7) are stored in CURSOR_MODE
; for the MDA as well, even though the MDA's defaults are different (11,12),
; and this behavior seems to be true regardless of BIOS revision.  Bummer.
;
; Inputs:
;	ES = BIOS
;
; Outputs:
;	AX = cursor type (AH = top scanline, AL = bottom scanline)
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:BIOS, SS:NOTHING
DEFPROC	update_curtype
	mov	ax,[CURSOR_MODE]
	cmp	ax,0067h		; buggy cursor scanline values?
	jne	uct1			; no
	mov	ax,0607h		; yes, fix them
uct1:	cmp	[ADDR_6845].LB,0B4h	; MDA?
	jne	uct2			; no
	cmp	ax,0607h		; bogus values for MDA?
	jne	uct2			; no
	mov	ax,0B0Ch		; yes, fix them
uct2:	mov	[CURSOR_MODE],ax
	ret
ENDPROC	update_curtype

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_char
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
DEFPROC	write_char
	push	ax
	push	bx
	mov	bh,0
	mov	ah,VIDEO_TTYOUT
	int	INT_VIDEO
	pop	bx
	pop	ax
	ret
ENDPROC	write_char

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_context
;
; Inputs:
;	AL = character
;	ES = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	write_context
	push	ax
	push	bx
	push	cx
	push	dx
	push	di
	push	ds
	push	es
	push	es
	pop	ds			; DS is now the context
;
; Check for special characters first.
;
	mov	cx,ax			; CL = character
	mov	dx,ds:[CT_CURPOS]

	cmp	al,CHR_RETURN		; RETURN?
	jne	wc1			; no
	mov	dl,ds:[CT_CURMIN].LB	; yes
	jmp	short wc8

wc1:	cmp	al,CHR_LINEFEED		; LINEFEED?
	je	wc6			; yes

	cmp	al,CHR_TAB		; TAB?
	je	wc4			; yes
;
; Like the PC BIOS, we draw any other CONTROL character (eg, CHR$(14)) as a
; glyph, except BELL, which the BIOS beeps instead (and BACKSPACE, which
; draw_char handles).  CONTROL characters typed at a DOS buffered input
; prompt are still displayed as "^" + char, since DOS does that (see con_out).
;
	cmp	al,CHR_CTRLG		; BELL?
	jne	wc7			; no
	mov	ah,VIDEO_TTYOUT		; yes, so let the BIOS beep
	call	video_ctx
	jmp	short wc9

wc4:	mov	bl,dl			; emulate a (horizontal) TAB
	sub	bl,ds:[CT_CURMIN].LB
	and	bl,07h
	neg	bl
	add	bl,8
	mov	cl,CHR_SPACE
wc5:	call	draw_char
	cmp	dl,ds:[CT_CURMIN].LB	; did the column wrap back around?
	jle	wc8			; yes, stop
	dec	bl
	jnz	wc5
	jmp	short wc8

wc6:	call	draw_linefeed		; emulate a LINEFEED
	jmp	short wc8

wc7:	call	draw_char		; draw character (CL) at CURPOS (DL,DH)

wc8:	call	update_cursor		; set CURPOS to (DL,DH)

wc9:	pop	es
	pop	ds
	pop	di
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	write_context

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_curpos
;
; Inputs:
;	AH = attributes
;	CL = character
;	DX = CURPOS (DL,DH)
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AL, DI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	write_curpos
	test	ds:[CT_STATUS],CTSTAT_INT10
	jnz	wcp8
	push	bx
	push	dx
	call	get_curpos		; BX = screen offset for CURPOS
	call	chk_snow		; is the page in CGA memory?
	jnc	wcp3			; no, don't worry about horz retrace
	mov	dx,ds:[CT_PORT]
	ASSERT	Z,<cmp dh,03h>
	add	dl,6			; DX = status port
wcp1:	in	al,dx
	test	al,01h
	jnz	wcp1			; loop until we're OUTSIDE horz retrace
	cli
wcp2:	in	al,dx
	test	al,01h
	jz	wcp2			; loop until we're INSIDE horz retrace
;
; A focus switch at interrupt time can move the context to another page (see
; swap_page), so CT_SCREEN is loaded with interrupts off, and ES is restored
; before they're on again, since a buffer that it holds can be freed while
; this session waits for another (see restore_screen).
;
wcp3:	cli
	push	es
	les	di,ds:[CT_SCREEN]	; ES:DI -> screen location
	mov	al,cl
	mov	es:[di+bx],ax		; "write" the character and attributes
	pop	es
	sti
	pop	dx
	pop	bx
	ret
;
; The context is using INT 10h passthrough (it's in a mode other than its
; original mode that isn't a text mode; see update_mode), so position the BIOS
; cursor and write the character and attributes using INT 10h instead of
; writing to the screen directly.
;
wcp8:	push	ax
	push	bx
	push	cx
	push	dx
	add	dx,ds:[CT_CONPOS]	; DL = screen col, DH = screen row
	mov	bl,ah			; BL = attributes
	mov	bh,ds:[CT_PAGE]		; BH = display page
	mov	ah,VIDEO_SETCPOS
	call	video_ctx
	mov	al,cl			; AL = character
	mov	cx,1			; CX = count
	mov	ah,VIDEO_WRITECA
	call	video_ctx
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	write_curpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_crtc16
;
; Inputs:
;	AH = 6845 register #
;	BX = 16-bit value to write
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	write_crtc16
	cli
	mov	al,bh
	call	write_crtc8
	inc	ah
	mov	al,bl
	call	write_crtc8
	sti
	ret
ENDPROC	write_crtc16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_crtc8
;
; Inputs:
;	AH = 6845 register #
;	AL = 8-bit value to write
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	DX
;
DEFPROC	write_crtc8
	mov	dx,ds:[CT_PORT]
	ASSERT	Z,<cmp dh,03h>
	xchg	al,ah
	out	dx,al			; select 6845 register
	inc	dx
	xchg	al,ah
	out	dx,al			; output AL
	ret
ENDPROC	write_crtc8

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_setkeys (IOCTL_SETKEYS)
;
; In raw keys mode, CTRLC, CTRLS, and CTRLP are just keys, rather than hotkeys
; (see check_hotkey); non-ASCII keys (eg, cursor keys) are always returned as
; a zero followed by the key's scan code (see pull_kbd).
;
; A program that runs code with BIOS data of its own (eg, V86.COM's V86
; machine) also sets CL bit 1, with a selector for that code's low memory
; (ie, with its BIOS data at 400h) in DX: until an IOCTL_SETKEYS without bit
; 1, we keep the keyboard data there current (see kbd_update), as the ROM
; does for the BIOS's.  DOS sends one if the program ends without doing so
; (see PSP_RAWKEYS).
;
; Only raw keys mode is needed for the only console (see con_opt), so the
; rest is in set_bios.
;
; Inputs:
;	ES:DI -> DDPRW
;	CL bit 0 = 1 for raw keys, 0 for normal keys
;	CL bit 1 = 1 for BIOS data to update (DX = selector), 0 for none
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_setkeys
	mov	ds:[CT_SCAN],0
	and	ds:[CT_STATUS],NOT CTSTAT_RAWKEYS
	test	cl,1			; raw keys requested?
	jz	dsk1			; no
	or	ds:[CT_STATUS],CTSTAT_RAWKEYS
dsk1:	test	cl,2			; BIOS data to update?
	jnz	dsk2			; yes
	cmp	ds:[CT_BIOS],0		; no, so were we updating any?
	je	dsk7			; no (and carry is clear)
dsk2:	call	chk_opt			; one console only?
	jc	dsk6			; yes, so there's no set_bios
	jmp	set_bios
dsk6:	clc
dsk7:	ret
ENDPROC	ddcon_setkeys

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; kbd_update
;
; If the context's program has BIOS data of its own (see ddcon_setkeys),
; copies the BIOS's keyboard data (the shift states and the buffer) to it;
; a context without focus has no keys, so its buffer is empty.  It's called
; whenever that data may have changed: after a keyboard interrupt, a read, a
; flush, and a change of focus.
;
; The only console never has any (see ddcon_setkeys), so only this test is
; resident, and the rest is in kbd_now.
;
; Inputs:
;	DS = CONSOLE context
;
; Modifies:
;	None (the flags are preserved, too)
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	kbd_update
	pushf
	cmp	ds:[CT_BIOS],0		; any BIOS data to update?
	jne	ku1			; yes
	popf
	ret
ku1:	jmp	kbd_now
ENDPROC	kbd_update

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_opt
;
; Outputs:
;	Carry set if there's only one console, which means that nothing after
;	con_opt can be called
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_opt
	cmp	[one_con],1		; (carry set if it's zero)
	cmc
co9:	ret
ENDPROC	chk_opt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; show_page
;
; Displays the context's page, if it has focus and isn't blocked by another
; context (see chk_blocked); a virtual page is exchanged with the page that
; the adapter is displaying first (see swap_page), and the adapter's mode
; is changed if the context has a text mode of its own (see set_pmode).
;
; The only console's page is always displayed, so there's nothing to do for
; it, and the rest of this is after con_opt.
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
DEFPROC	show_page
	call	chk_opt			; one console only?
	jc	co9			; yes
ENDPROC	show_page			; fall into show_now (after con_opt)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Everything from here to ddcon_init is for more than one console: switching
; the focus, the virtual pages that consoles beyond an adapter's own pages
; use, the text modes that pages can have, unblocking contexts after a mode
; change (see release_mode), and placing, opening, and closing contexts
; beside others.  A machine with 64K or less has room for none of it, so
; ddcon_init ends the resident code here instead, sets one_con, and
; ddcon_open then refuses a second console; nothing before this calls any of
; it for the only console (see chk_opt), which always has the focus and a page
; of its own.  The video memory selectors (see set_slot) are here too, since
; they exist only in protected mode, which needs more than 64K.
;
	DEFLBL	con_opt,near

	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	show_now
	mov	ax,ds
	cmp	ax,[ct_focus]		; does the context have focus?
	jne	sp9			; no
	call	chk_blocked		; is another context blocking it?
	jc	sp9			; yes
	call	swap_page
	call	chk_vpage		; still on a virtual page?
	jc	sp9			; yes (see swap_page)
	call	get_place		; BX = con_place index
	push	es
	mov	es,cs:[0].DDH_DATA
	ASSUME	ES:CODE
	mov	al,ds:[CT_PAGE]
	mov	shown_page[bx],al	; record the page being displayed
;
; The adapter's text mode follows the page (see set_pmode), unless the BIOS
; set the mode for this context (see mode_ctx), which may be a graphics mode,
; or have more rows.  When that context returns to its original mode, the
; BIOS sets the adapter's mode again, to a mode that set_hwmode may set once
; more, since we don't record it.  An MDA has only one mode, which is always
; the mode being displayed.
;
	mov	al,ds:[CT_MODE]
	mov	dx,ds
	cmp	dx,[mode_ctx]		; set by the BIOS?
	je	sp2			; yes
	cmp	al,shown_page[bx+1]	; is it the mode being displayed?
	je	sp2			; yes
	mov	shown_page[bx+1],al	; no, but it is now
	call	set_hwmode
sp2:	pop	es
	ASSUME	ES:NOTHING
	call	get_start		; AX = offset of the context's page
	shr	ax,1
	xchg	bx,ax			; BX = start address (in cells)
	mov	ah,CRTC_STARTHI
	call	write_crtc16
sp9:	ret
ENDPROC	show_now

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_hwmode
;
; Sets an adapter's mode without clearing its memory.  The BIOS of an EGA or
; VGA does that if bit 7 of the mode is set.  A CGA's BIOS always clears all
; 16K, so we program a CGA ourselves: the 6845's horizontal timing registers
; (0-3, which differ between 40 and 80 columns), the vertical ones that
; differ between text and graphics (4, 6, 7, and 9), and the mode and color
; select registers, along with the BIOS's copies of those two (the BIOS
; writes the former to the mode register again after it scrolls, for example).
;
; Inputs:
;	AL = mode (0-6)
;	DS = CONSOLE context
;
; Modifies:
;	AX, BX, DX
;
	DEFLBL	CGA_MODES,byte
	db	2Ch,28h,2Dh,29h		; mode register values for modes 0-3
	db	2Ah,2Eh,1Eh		; and for modes 4-6
	db	38h,28h,2Dh,0Ah		; 6845 registers 0-3 for 40 columns
	db	71h,50h,5Ah,0Ah		; and for 80 columns
	db	1Fh,7Fh,4		; register 4 for text and for graphics
	db	19h,64h,6		; and registers 6, 7, and 9
	db	1Ch,70h,7
	db	07h,01h,9

	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_hwmode
	test	[adapters],ADAPTER_EGA
	jz	shm1			; it's a CGA
	push	ax
	call	update_biosdata		; (the BIOS needs its EQUIP_FLAG)
	pop	ax
	push	bp
	or	al,80h			; bit 7 = no clear
	mov	ah,VIDEO_SETMODE
	pushf
	call	[video_int]
	pop	bp
	ret
shm1:	push	cx
	push	si
	push	es
	mov	bx,offset CGA_MODES
	xlat	CGA_MODES
	lea	si,[bx+7]		; SI -> values for 40 columns
	test	al,01h			; 80 columns?
	jz	shm2			; no
	add	si,4
shm2:	mov	bh,al			; BH = mode register value
	mov	dx,ds:[CT_PORT]
	add	dl,4			; DX = mode register port
	and	al,NOT 08h
	out	dx,al			; turn the display off meanwhile
	mov	ah,0			; AH = 6845 register #
	cld
shm3:	lods	byte ptr cs:[si]
	call	write_crtc8		; (DX = 6845 data port)
	inc	ah
	cmp	ah,4
	jb	shm3
	mov	si,offset CGA_MODES+15
	mov	cx,4
shm4:	lods	word ptr cs:[si]	; AL = value for text, AH = graphics
	test	bh,02h			; a graphics mode?
	jz	shm5			; no
	mov	al,ah
shm5:	mov	ah,cs:[si]		; AH = 6845 register #
	inc	si
	call	write_crtc8
	loop	shm4
	add	dl,3			; DX = mode register port again
	mov	al,bh
	out	dx,al			; new mode, with the display on
	mov	bx,BIOS
	mov	es,bx
	ASSUME	ES:BIOS
	mov	[CRT_MODE_SET],al
;
; The color select register gets the BIOS's value for the mode, too: no
; border, and palette 1 (or white pixels, in mode 6).
;
	cmp	al,1Eh			; mode 6?
	mov	al,30h
	jne	shm6			; no
	mov	al,3Fh
shm6:	inc	dx
	out	dx,al
	mov	[CRT_PALLETTE],al
	pop	es
	ASSUME	ES:NOTHING
	pop	si
	pop	cx
	ret
ENDPROC	set_hwmode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_pmode
;
; A context with a page of its own (ie, one created with all 80 columns and
; 25 rows) changes from one 25-row text mode (0-3) to another in place: it
; stays on its page, which we clear ourselves, and the mode becomes the
; page's mode, which the adapter is given whenever the page is displayed
; (see show_page and set_hwmode).  The BIOS never sets the mode, so the
; adapter's other pages aren't cleared, and no other context is blocked.
;
; Any other mode change still belongs to the BIOS, and takes the entire
; screen (see update_mode): a change to or from a graphics mode or more
; rows (ie, by a context that has the entire screen now; see mode_ctx), a
; change by a context that shares its page, and any change on an MDA.
;
; Inputs:
;	DS = CONSOLE context
;	[BP+4] = mode requested (ie, the AL that ddcon_int10 was given)
;
; Outputs:
;	Carry clear if the mode was set in place; otherwise, carry set
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_pmode
	mov	al,[bp+4]		; AL = mode requested
	cmp	al,MODE_CO80+1		; a text mode (0-3)?
	jae	spm8			; no
	cmp	ds:[CT_ROWS],0		; with the usual 25 rows?
	jne	spm8			; no
	cmp	ds:[CTO_DIM],(25 SHL 8) OR 80
	jne	spm8			; the context shares its page
	cmp	ds:[CT_PORT].LB,0B4h	; monochrome adapter?
	je	spm8			; yes
	push	si
	mov	si,ds			; SI != 0 (see update_mode)
	cmp	si,[mode_ctx]		; does it have the entire screen?
	je	spm7			; yes
	push	bx
	push	cx
	push	dx
	call	spm1			; update the context
	mov	cl,100
	call	scroll			; clear it (inside any border)
	mov	ax,ds
	cmp	ax,[ct_focus]
	jne	spm6
	call	show_cursor
spm6:	pop	dx
	pop	cx
	pop	bx
	pop	si
	clc
	ret
spm7:	pop	si
spm8:	stc
	ret
;
; update_mode does the rest, so we enter it (at um0c) with the registers that
; it saves on the stack, and it returns to our caller above.
;
spm1:	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es
	mov	bl,al
	xchg	bl,ds:[CT_MODE]		; BL = previous mode
	mov	cx,(25 SHL 8) OR 40	; CH = rows
	cmp	al,2			; a 40-column mode (0 or 1)?
	jb	spm2			; yes
	mov	cl,80
spm2:	mov	ds:[CT_COLS].LB,cl
	mov	ah,ds:[CTO_PAGE]	; AH = the context's own page
	jmp	um0c
ENDPROC	set_pmode


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swap_page
;
; A context beyond its adapter's pages is on a virtual page instead: a buffer
; in system memory, shared by every context on that page (see get_vbuf).  To
; display it, its page is exchanged with the page that the adapter is
; displaying (shown_page): both their contents and the page numbers of the
; contexts on them, so the contexts that were displayed now use the buffer,
; and the adapter's own pages never need buffers just to save them.  If no
; context moves to the buffer (eg, they've all been closed), it's freed.
;
; Nothing is exchanged while the context is blocked (see chk_blocked), which
; also keeps any context in a mode other than its original mode on the screen
; (eg, one that uses INT 10h, since the BIOS can't write to a buffer).  The
; contexts' video memory selectors follow their new pages (see set_slot).
; The caller has locked the BIOS (see bios_lock), so no switch or other swap
; can interrupt this one.
;
; Inputs:
;	DS = CONSOLE context
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	swap_page
	call	chk_vpage		; is the context on a virtual page?
	jnc	swp10			; no
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp
	push	ds
	push	es
	call	swap_now
	call	update_slots
	pop	es
	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
swp10:	ret
ENDPROC	swap_page
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; save_screen
;
; Called by ddcon_int10 before the BIOS sets a mode that set_pmode can't,
; after swap_page has displayed the context's page.  The BIOS clears the
; adapter's memory, and the context then has the entire screen (see
; update_mode), so if no context has it yet, and other contexts on the
; adapter have their pages (or regions) there, that memory is copied to a
; buffer (save_seg; see copy_alloc), which they then use instead: their
; output goes on (see chk_output), their video memory selectors map the
; buffer (see set_slot), and restore_screen copies it back when the screen
; is given up.  The context's own region is cleared first, as the BIOS would
; clear it, so that it comes back empty.  If there's no memory for the
; buffer, the others are simply blocked.
;
; A context that has the screen but is hidden (see hide_mode) sets a mode
; only when it's closed (its own requests wait until it's displayed again),
; and the others are on the screen then, so their memory is copied again
; first (see keep_others).
;
; Inputs:
;	DS = CONSOLE context
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	save_screen
	call	swap_page
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es
	mov	ax,ds
	cmp	[mode_ctx],0		; does any context have the screen?
	je	svs1			; no
	cmp	[mode_ctx],ax		; this one?
	jne	svs9			; no
	call	chk_blocked		; is it hidden?
	jnc	svs9			; no (so the others are saved already)
	call	keep_others		; yes, so save them again
	call	vga_free		; (and its own state isn't needed now)
	jmp	short svs9
svs1:	call	get_frame
	mov	dx,ax			; (a move to the same memory)
	call	move_ctxs		; is another context in the adapter's?
	jnc	svs9			; no
	call	copy_alloc		; AX = the copy, DI = its length
	jc	svs9			; (no memory, so they're blocked)
	push	ax
	push	ds:[CT_COLOR]
	mov	ds:[CT_COLOR].LB,07h	; (the attributes the BIOS clears with)
	mov	cl,0
	call	scroll			; clear this context (and any border)
	pop	ds:[CT_COLOR]
	pop	ax
	push	ds
	mov	ds,dx
	mov	es,ax
	mov	cx,di
	shr	cx,1
	sub	si,si
	sub	di,di
	rep	movsw			; copy the adapter's memory
	pop	ds
	xchg	ax,dx			; AX = adapter's memory, DX = the copy
	call	move_ctxs		; and the others use the copy
svs9:	pop	es
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	save_screen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; move_ctxs
;
; Moves the other contexts on a context's adapter from one copy of its memory
; to another (eg, from the adapter's memory to save_seg).
;
; Inputs:
;	DS = CONSOLE context (which doesn't move)
;	AX = memory to move from
;	DX = memory to move to
;
; Outputs:
;	Carry set if any context was in the memory to move from
;
; Modifies:
;	BX, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	move_ctxs
	push	cx
	push	bp
	sub	bp,bp			; BP = # contexts moved
	mov	cx,ds:[CT_PORT]		; CX = adapter port
	mov	bx,[ct_head]
mvc1:	test	bx,bx
	jz	mvc8
	mov	es,bx
	cmp	es:[CT_PORT],cx		; is it on the same adapter?
	jne	mvc2			; no
	cmp	es:[CT_SCREEN]._SEG,ax	; and in the memory to move from?
	jne	mvc2			; no
	push	ax
	mov	ax,ds
	cmp	ax,bx			; is it the context that doesn't move?
	pop	ax
	je	mvc2			; yes
	mov	es:[CT_SCREEN]._SEG,dx	; no, so it moves
	inc	bp
mvc2:	mov	bx,es:[CT_NEXT]
	jmp	mvc1
mvc8:	neg	bp			; carry set if any moved
	pop	bp
	pop	cx
	ret
ENDPROC	move_ctxs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copy_alloc
;
; Allocates the buffer for a copy of an adapter's memory (save_seg), which
; holds the other contexts' memory while a context has the screen (see
; save_screen), or that context's memory while it's hidden (see hide_mode).
; On an 80386, the buffer starts on a page boundary in the block that holds
; it (save_addr), so that a V86 machine can have its pages, too (see v86_vid
; and copy_addr).
;
; Inputs:
;	DS = CONSOLE context (on the adapter)
;
; Outputs:
;	Carry clear if successful: AX = save_seg, DI = length of the copy
;
; Modifies:
;	AX, SI, DI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	copy_alloc
	push	bx
	push	cx
	push	dx
	push	ds
	call	slot_addr		; SI:DI = length of adapter's memory
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	push	di
	call	chk_paged		; an 80386?
	jb	cal1			; no
	add	di,1000h-16		; yes (room for a page boundary)
cal1:	mov	bx,MCBOWNER_SYSTEM
	mov	ax,(CPU_ALLOC SHL 8) OR MEMF_NONE
	call	far ptr DDINT_CPU	; DX:CX = the block's address
	pop	di			; DI = length of the copy
	jc	cal9
	mov	save_addr[0],cx
	mov	save_addr[2],dx
	call	copy_addr		; DX:CX = its first page boundary
	mov	ax,CPU_MAP SHL 8	; (a GDT data selector, SI:DI = length)
	call	far ptr DDINT_CPU	; AX = its selector (or segment)
	jc	cal8
	mov	[save_seg],ax
	jmp	short cal9
cal8:	call	free_copy		; (the block)
	stc
cal9:	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	copy_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; save_ctx
;
; A context that ddcon_open puts in the adapter's memory while another
; context is blocking it uses the other contexts' copy (see save_screen), or
; if there's none yet (eg, the context that has the screen was alone), a new
; one, which starts blank.
;
; Inputs:
;	DS = CONSOLE context
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	save_ctx
	mov	ax,[save_seg]
	test	ax,ax			; is there a copy?
	jnz	svc8			; yes
	push	cx
	push	si
	push	di
	push	es
	call	copy_alloc		; AX = the copy, DI = its length
	jc	svc7
	mov	es,ax
	mov	cx,di
	shr	cx,1
	sub	di,di
	push	ax
	mov	ax,0720h
	rep	stosw			; clear it
	pop	ax
svc7:	pop	es
	pop	di
	pop	si
	pop	cx
	jc	svc9
svc8:	mov	ds:[CT_SCREEN]._SEG,ax	; the context uses the copy
svc9:	ret
ENDPROC	save_ctx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mode_switch
;
; A switch to another context on the adapter of the context that has the
; screen (mode_ctx) hides that context first (see hide_mode, or in one of an
; EGA or VGA's graphics modes, hide_vga), and a switch back to it displays it
; again (see show_mode and show_vga).  If there's no buffer to hide it in
; (see copy_alloc and vga_alloc), the switch can't happen.
;
; Inputs:
;	CX = context to switch to
;
; Outputs:
;	Carry set if the switch can't happen
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	mode_switch
	push	ax
	mov	ax,[mode_ctx]
	test	ax,ax			; does any context have the screen?
	jz	msw9			; no (and carry is clear)
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	mov	ds,ax			; DS = context with the screen
	cmp	ax,cx			; switching to it?
	jne	msw2			; no
	call	chk_blocked		; yes; is it hidden?
	jnc	msw8			; no
	cmp	ds:[CT_MODE],0Dh	; yes; in a graphics mode of a VGA?
	jb	msw1			; no
	call	show_vga		; yes, so restore its state
	jmp	short msw7
msw1:	call	show_mode		; display it again
	jmp	short msw7
msw2:	call	chk_blocked		; is it hidden already?
	jc	msw7			; yes
	mov	es,cx
	mov	ax,es:[CT_PORT]
	cmp	ax,ds:[CT_PORT]		; is the other context on its adapter?
	jne	msw7			; no
	cmp	[save_seg],0		; can it be hidden?
	stc
	je	msw8			; no
;
; A context in one of an EGA or VGA's graphics modes (0Dh-13h) has more
; memory than the buffer holds, and its programs set the adapter's registers
; themselves (see CPU_V86), so it's hidden by saving all of its state (see
; hide_vga), which only a VGA in protected mode can do.
;
	cmp	ds:[CT_MODE],0Dh
	jb	msw2a
	call	hide_vga
	jc	msw8
	jmp	short msw7
msw2a:	call	hide_mode
msw7:	clc
msw8:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
msw9:	pop	ax
	ret
ENDPROC	mode_switch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hide_mode
;
; Hides the context that has the screen (mode_ctx) so that another context
; on its adapter can be displayed: the adapter's memory and the other
; contexts' copy (see save_screen) are exchanged, so the buffer has its
; memory now (where its video memory selector maps it, so that its programs
; can keep drawing) and they use the adapter's again, in the other context's
; mode, which is set without clearing anything (see set_hwmode).  While
; it's hidden (mode_hid), it's the only context that's blocked (see
; chk_blocked), so its output waits, and so does any INT 10h call from its
; session (see wait_focus).
;
; Inputs:
;	DS = CONSOLE context (mode_ctx)
;	CX = context to display
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	hide_mode
	push	cx
	call	xchg_copy		; AX = adapter's memory, DX = the copy
	pop	bx
	push	ds
	mov	ds,bx			; DS = context to display
	call	set_mode
	mov	cl,ds:[CT_MODE]
	pop	ds
	xchg	ax,dx
	call	move_ctxs		; the others use the adapter's again
	mov	al,-1			; AL = new mode_hid
	DEFLBL	shown_mode,near
	mov	es,cs:[0].DDH_DATA
	ASSUME	ES:CODE
	mov	[mode_hid],al
	call	get_place		; BX = con_place index
	mov	shown_page[bx+1],cl	; (the mode being displayed)
	ASSUME	ES:NOTHING
	jmp	wake_ctxs		; (and their video memory selectors)
ENDPROC	hide_mode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; show_mode
;
; Displays a hidden context again (see hide_mode): the adapter's memory and
; the buffer are exchanged again, so the other contexts use their copy and
; the context has the adapter's, and its mode is set again (see set_mode),
; with its background and palette in modes 4 and 5.  The rest of what the
; context's programs set themselves (eg, with OUT) isn't.
;
; Inputs:
;	DS = CONSOLE context (mode_ctx)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	show_mode
	call	xchg_copy		; AX = adapter's memory, DX = the copy
	call	move_ctxs		; the others use the copy again
	call	set_mode
	mov	al,ds:[CT_MODE]
	sub	al,4
	cmp	al,2			; mode 4 or 5?
	jae	shw2			; no
	mov	cl,ds:[CT_COLOR].HB
	call	set_gfxclr		; yes, so set background and palette
shw2:	mov	al,0			; AL = new mode_hid
	mov	cl,ds:[CT_MODE]
	jmp	shown_mode
ENDPROC	show_mode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hide_vga and show_vga
;
; hide_vga hides the context that has the screen (mode_ctx) in one of a
; VGA's graphics modes (0Dh-13h), whose programs set the adapter's registers
; themselves, so its programs must stop, and the adapter's state must be
; saved: the BIOS saves its registers, DAC, and BIOS data (VIDEO_STATE), and
; all four planes are copied (see vga_save), to a block of their own (see
; vga_alloc); then the other context's mode is set, and the other contexts
; use the adapter's memory again, with their copy (see save_screen) put back
; there.  While the context is hidden, its video memory selector isn't
; present (see set_slot), so its programs wait when they touch it, and a V86
; machine that had the adapter's ports doesn't run at all (see CPU_V86).
;
; show_vga does the reverse: the other contexts go back to their copy, the
; planes and then the rest of the adapter's state are restored (see
; vga_restore), and the context's selector is present again, so its programs
; continue.
;
; Inputs:
;	DS = CONSOLE context (mode_ctx)
;	CX = context to display (hide_vga)
;
; Outputs:
;	Carry set if it can't be hidden (hide_vga)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	hide_vga
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	push	cx
	call	vga_alloc		; is there a VGA, and memory for it?
	jc	hg8			; no
	call	vga_save
	pop	cx
	pop	ds
	ASSUME	DS:NOTHING
	push	ds
	mov	ds,cx			; DS = context to display
	call	set_mode
	mov	cl,ds:[CT_MODE]
	pop	ds
	push	cx
	call	slot_addr		; SI:DI = length of adapter's memory
	call	get_frame		; AX = its segment
	mov	dx,[save_seg]
	push	ds
	mov	es,ax
	mov	ds,dx
	mov	cx,di
	shr	cx,1
	sub	di,di			; (and SI is zero)
	rep	movsw			; the others' memory goes back
	pop	ds
	xchg	ax,dx			; AX = the copy, DX = adapter's memory
	call	move_ctxs		; and they use the adapter's again
	pop	cx
	mov	al,-1			; AL = new mode_hid
	jmp	shown_mode		; (which clears carry)
hg8:	pop	cx
	pop	ds
	ret
ENDPROC	hide_vga

DEFPROC	show_vga
	call	keep_others		; the others use their copy again
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	call	vga_restore
	call	vga_free
	pop	ds
	ASSUME	DS:NOTHING
	mov	al,0			; AL = new mode_hid
	mov	cl,ds:[CT_MODE]
	jmp	shown_mode
ENDPROC	show_vga

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; vga_alloc
;
; Allocates the block for a VGA's state (see hide_vga): its four 64K planes,
; followed by what the BIOS saves (its registers, DAC, and BIOS data; see
; VIDEO_STATE), which only a VGA's BIOS can (since an EGA's registers can't
; be read), and only in protected mode, where the block can be anywhere (in
; real mode, a program would also write the adapter's memory itself).
;
; Outputs:
;	Carry clear if successful (vga_addr and vga_state set)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	vga_alloc
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	cmp	[CPU_TYPE],2		; protected mode? (carry set if not)
	ASSUME	ES:NOTHING
	jb	vga9			; no
	mov	ax,VIDEO_GETDCC
	pushf
	call	[video_int]
	cmp	al,1Ah			; a VGA?
	jne	vga8			; no
	mov	ax,VIDEO_STATE SHL 8
	mov	cx,7			; (registers, BIOS data, and DAC)
	pushf
	call	[video_int]		; BX = blocks of 64 bytes
	cmp	al,VIDEO_STATE		; does the BIOS have the function?
	jne	vga8			; no
	mov	cl,6
	shl	bx,cl
	mov	[vga_state],bx
	mov	di,bx
	mov	si,4			; SI:DI = 4 planes, plus the state
	mov	bx,MCBOWNER_SYSTEM
	mov	ax,(CPU_ALLOC SHL 8) OR MEMF_NONE
	call	far ptr DDINT_CPU	; DX:CX = the block's address
	jc	vga9
	mov	vga_addr[0],cx
	mov	vga_addr[2],dx
	ret				; (and carry is clear)
vga8:	stc
vga9:	ret
ENDPROC	vga_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; vga_save and vga_restore
;
; vga_save has the BIOS save the adapter's state (see VIDEO_STATE), and then
; sets the registers that let us read each plane in turn (see vga_raw) and
; copies them; vga_restore copies the planes back, and then has the BIOS
; restore the state, which includes the registers that vga_raw changed (and
; the index registers, so that a program interrupted between an index and
; its data continues as before).
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	vga_save
	mov	al,1			; save
	call	vga_bios
	call	vga_raw
	sub	bx,bx			; BX = plane
vgs1:	mov	dx,3CEh
	mov	ah,bl
	mov	al,4
	out	dx,ax			; read map select = this plane
	push	bx
	call	vga_map			; AX = selector for its copy
	mov	es,ax
	push	ds
	mov	ax,0A000h
	mov	ds,ax
	sub	si,si
	sub	di,di
	mov	cx,8000h
	rep	movsw
	pop	ds
	call	vga_unmap
	pop	bx
	inc	bx
	cmp	bl,4
	jb	vgs1
	ret
ENDPROC	vga_save

DEFPROC	vga_restore
	call	vga_raw
	sub	bx,bx			; BX = plane
vgr1:	mov	dx,3C4h
	mov	cl,bl
	mov	ah,1
	shl	ah,cl
	mov	al,2
	out	dx,ax			; map mask = this plane
	push	bx
	call	vga_map			; AX = selector for its copy
	push	ds
	mov	ds,ax
	mov	ax,0A000h
	mov	es,ax
	sub	si,si
	sub	di,di
	mov	cx,8000h
	rep	movsw
	mov	ax,ds
	pop	ds
	mov	es,ax			; ES = the copy's selector
	call	vga_unmap
	pop	bx
	inc	bx
	cmp	bl,4
	jb	vgr1
	mov	al,2			; restore
	DEFLBL	vga_bios,near
	push	ax
	mov	bx,4
	call	vga_map			; AX = selector for the state
	mov	es,ax
	pop	ax
	mov	ah,VIDEO_STATE
	mov	cx,7			; (registers, BIOS data, and DAC)
	sub	bx,bx			; ES:BX -> the state
	pushf
	call	[video_int]
ENDPROC	vga_restore			; fall into vga_unmap

;
; vga_unmap frees the selector in ES (from vga_map).
;
DEFPROC	vga_unmap
	mov	bx,es
	push	ds
	pop	es
	sub	cx,cx			; (CX = 0 for one selector)
	mov	ah,CPU_UNMAP
	call	far ptr DDINT_CPU
	ret
ENDPROC	vga_unmap

;
; vga_map returns a selector (AX) for plane BX's copy (0-3), or the state's
; (4), in the block (see vga_alloc).  The state's selector covers 64K, too,
; since the BIOS's restore reads past it (eg, its port address at 463h,
; while DS is the state's), which real mode allows.
;
DEFPROC	vga_map
	mov	cx,vga_addr[0]
	mov	dx,vga_addr[2]
	add	dx,bx			; (64K for each plane)
	sub	di,di
	mov	si,1			; SI:DI = 64K
	mov	ax,CPU_MAP SHL 8	; (a GDT data selector)
	call	far ptr DDINT_CPU
	ret
ENDPROC	vga_map

;
; vga_raw sets the registers that make each plane a 64K array at A0000h: no
; chain-4 or odd/even addressing, read mode 0 and write mode 0 (with no
; set/reset, rotation, or function, and every bit written).
;
DEFPROC	vga_raw
	mov	dx,3C4h
	mov	ax,0604h		; memory mode
	out	dx,ax
	mov	dl,0CEh
	mov	ax,0001h		; enable set/reset
	out	dx,ax
	mov	al,03h			; data rotate
	out	dx,ax
	mov	al,05h			; mode
	out	dx,ax
	mov	ax,0506h		; miscellaneous
	out	dx,ax
	mov	ax,0FF08h		; bit mask
	out	dx,ax
	ret
ENDPROC	vga_raw

;
; vga_free frees the block (see vga_alloc), if any.
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	vga_free
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	sub	cx,cx
	sub	dx,dx
	xchg	cx,vga_addr[0]
	xchg	dx,vga_addr[2]		; DX:CX = the block (or zero)
	mov	ax,cx
	or	ax,dx			; is there one?
	jz	vgf9			; no
	mov	ah,CPU_FREE
	call	far ptr DDINT_CPU
vgf9:	pop	ds
	ASSUME	DS:NOTHING
	ret
ENDPROC	vga_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_mode
;
; Sets the adapter's mode to a context's, without clearing its memory (see
; set_hwmode), and with the context's rows, if it has more than 25 (see
; set_rows).  An MDA has only one mode.
;
; Inputs:
;	DS = CONSOLE context
;
; Modifies:
;	BX, CX, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_mode
	cmp	ds:[CT_PORT].LB,0B4h	; monochrome adapter?
	je	smd9			; yes
	push	ax
	push	dx
	mov	ah,ds:[CT_CONDIM].HB
	inc	ah			; AH = rows
	cmp	ah,25			; more than 25?
	jbe	smd1			; no
	mov	ds:[CT_ROWS],ah		; yes (see set_rows)
	mov	al,2			; a VGA displays 400 scan lines for 50
	cmp	ah,50
	je	smd0
	dec	ax			; and 350 for 43
smd0:	mov	ah,VIDEO_ALTSEL
	mov	bl,VALT_SCANLINES
	pushf
	call	[video_int]
smd1:	mov	al,ds:[CT_MODE]
	call	set_hwmode
	call	set_rows
	pop	dx
	pop	ax
smd9:	ret
ENDPROC	set_mode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xchg_copy
;
; Exchanges an adapter's memory with the buffer (see copy_alloc).
;
; Inputs:
;	DS = CONSOLE context (on the adapter)
;
; Outputs:
;	AX = adapter's memory, DX = save_seg
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	xchg_copy
	call	slot_addr		; SI:DI = length of adapter's memory
	call	get_frame		; AX = its segment
	mov	dx,[save_seg]
	push	ax
	push	ds
	mov	es,ax
	mov	ds,dx
	mov	cx,di
	shr	cx,1
	sub	di,di			; (and SI is zero)
xc1:	mov	ax,es:[di]
	movsw
	mov	[si-2],ax
	loop	xc1
	pop	ds
	pop	ax
	ret
ENDPROC	xchg_copy

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; keep_others
;
; Before the BIOS sets a mode for a hidden context (ie, when it's closed),
; which clears the adapter's memory, the other contexts on its adapter go
; back to their copy (see save_screen), which replaces the context's own.
;
; Inputs:
;	DS = CONSOLE context (mode_ctx)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	keep_others
	call	slot_addr		; SI:DI = length of adapter's memory
	call	get_frame		; AX = its segment
	mov	dx,[save_seg]
	push	ds
	mov	ds,ax
	mov	es,dx
	mov	cx,di
	shr	cx,1
	sub	di,di			; (and SI is zero)
	rep	movsw			; copy the others' memory
	pop	ds
	call	move_ctxs		; and they use the copy again
	mov	es,cs:[0].DDH_DATA
	ASSUME	ES:CODE
	mov	[mode_hid],0		; (the context isn't hidden now)
	ASSUME	ES:NOTHING
	ret
ENDPROC	keep_others

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_saved
;
; The rest of chk_output, for a blocked context.
;
; Inputs:
;	AX = CONSOLE context
;
; Outputs:
;	Carry set if the context's memory is the adapter's
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_saved
	push	ds
	mov	ds,ax
	call	chk_mem			; is its memory the adapter's?
	pop	ds
	stc
	je	csv9			; yes
	clc				; no (it's a buffer)
csv9:	ret
ENDPROC	chk_saved

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_mem
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	ZF set if the context's memory is the adapter's (not a buffer)
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_mem
	push	ax
	call	get_frame
	cmp	ax,ds:[CT_SCREEN]._SEG
	pop	ax
	ret
ENDPROC	chk_mem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; restore_screen
;
; When the context that had the entire screen gives it up (see release_now),
; the BIOS has just set a mode for it again, clearing the adapter's memory,
; so the other contexts' copy (see save_screen) is copied back, they use the
; adapter's memory again, and the buffer is freed.
;
; Inputs:
;	DS = CONSOLE context
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	restore_screen
	call	slot_addr		; SI:DI = length of adapter's memory
	call	get_frame
	xchg	dx,ax			; DX = its segment
	mov	ax,[save_seg]
	test	ax,ax			; is there a copy?
	jz	rss9			; no
	call	move_ctxs		; the others use the adapter's again
	push	ds
	mov	ds,ax
	mov	es,dx
	mov	cx,di
	shr	cx,1
	sub	di,di			; (and SI is zero)
	rep	movsw			; copy theirs back
	mov	ds,dx			; (DS can't hold the one being freed)
	mov	es,cs:[0].DDH_DATA
	ASSUME	ES:CODE
	mov	[save_seg],0
	ASSUME	ES:NOTHING
	xchg	bx,ax			; BX = the copy's selector
	sub	cx,cx			; (CX = 0 for one selector)
	mov	ah,CPU_UNMAP
	call	far ptr DDINT_CPU
	call	free_copy		; and free its block
	pop	ds
rss9:	ret
ENDPROC	restore_screen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; free_copy
;
; Frees the block that holds the copy of an adapter's memory (see
; copy_alloc).
;
; Modifies:
;	AX, BX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	free_copy
	mov	cx,save_addr[0]
	mov	dx,save_addr[2]		; DX:CX = the block
	mov	ah,CPU_FREE
	call	far ptr DDINT_CPU
	ret
ENDPROC	free_copy

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copy_addr
;
; Outputs:
;	DX:CX = the address of the copy of an adapter's memory (on an 80386,
;	the first page boundary in its block; see copy_alloc)
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	copy_addr
	mov	cx,save_addr[0]
	mov	dx,save_addr[2]
	call	chk_paged		; an 80386?
	jb	cad9			; no
	add	cx,0FFFh
	adc	dx,0
	and	cx,0F000h
cad9:	ret
ENDPROC	copy_addr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_paged
;
; Outputs:
;	Carry set (ie, below) if the processor is not an 80386, which is the
;	only one whose driver uses pages
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	chk_paged
	push	ax
	push	ds
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	cmp	[CPU_TYPE],3
	pop	ds
	ASSUME	DS:NOTHING
	pop	ax
	ret
ENDPROC	chk_paged

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_bios
;
; The rest of ddcon_setkeys, for a request with CL bit 1 set, or one that
; ends the updates, which means that the program whose BIOS data it was (a
; V86 machine) has ended, normally or not (eg, DOS's reset_keys after a
; CTRL-ALT-DEL): if it left the context in one of an EGA or VGA's graphics
; modes (0Dh-13h), whose registers its programs set themselves, the context
; gets its original mode again, so that it can display text (and be hidden).
;
; Inputs:
;	CL bit 1 = 1 for BIOS data to update (DX = selector), 0 for none
;	DS = CONSOLE context
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, BX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_bios
	mov	bx,ds:[CT_BIOS]
	test	cl,2			; BIOS data to update?
	jnz	sbi2			; yes
	test	bx,bx			; no, so were we updating any?
	jz	sbi9			; no
	mov	ds:[CT_BIOS],0
	sub	cx,cx			; (one selector)
	mov	ah,CPU_UNMAP
	call	far ptr DDINT_CPU
	cmp	ds:[CT_MODE],0Dh	; in one of those graphics modes?
	jb	sbi9			; no
	mov	al,ds:[CTO_MODE]
	mov	ah,VIDEO_SETMODE
	call	video_ctx		; (see update_mode and release_mode)
	jmp	short sbi9
sbi2:	test	bx,bx			; are we updating it already?
	jnz	sbi9			; yes
	push	si
	push	di
	mov	bx,dx
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_SEL
	call	far ptr DDINT_CPU	; DX:CX = the address of its memory
	jc	sbi8			; (there are no selectors in real mode)
	add	cx,BIOS_DATA
	adc	dx,0
	sub	si,si
	mov	di,300h			; SI:DI = length (see kbd_scan)
	mov	ax,CPU_MAP SHL 8	; (a GDT data selector)
	call	far ptr DDINT_CPU	; AX = selector for its BIOS data
	jc	sbi8
	mov	ds:[CT_BIOS],ax
	call	kbd_update
sbi8:	pop	di
	pop	si
sbi9:	clc
	ret
ENDPROC	set_bios

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; kbd_scan
;
; If the context with focus has a program with BIOS data of its own (see
; ddcon_setkeys), adds a scan code to the queue there (see KQ_TAIL in
; bios.inc), unless the queue is full.  The data is the program's to change,
; so the selector covers the queue wherever a byte's index puts it.
;
; Inputs:
;	AL = scan code (and interrupts are off)
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	kbd_scan
	push	bx
	push	ds
	mov	bx,[ct_focus]
	test	bx,bx
	jz	ks9
	mov	ds,bx
	mov	bx,ds:[CT_BIOS]
	test	bx,bx			; any BIOS data to update?
	jz	ks9			; no
	mov	ds,bx
	mov	bl,ds:[KQ_TAIL - BIOS_DATA]
	mov	bh,0
	mov	ds:[bx + KQ_CODES - BIOS_DATA],al
	inc	bx
	cmp	bl,KQ_MAX
	jb	ks1
	mov	bl,0
ks1:	cmp	bl,ds:[KQ_HEAD - BIOS_DATA]	; would that fill the queue?
	je	ks9			; yes
	mov	ds:[KQ_TAIL - BIOS_DATA],bl
ks9:	pop	ds
	pop	bx
	ret
ENDPROC	kbd_scan

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; kbd_now
;
; The rest of kbd_update, which jumps here with the flags on the stack.
;
; Inputs:
;	DS = CONSOLE context (with BIOS data to update)
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	kbd_now
	push	ax
	push	cx
	push	si
	push	di
	push	ds
	push	es
	mov	ax,ds
	mov	es,ds:[CT_BIOS]
	mov	si,BIOS
	mov	ds,si
	mov	si,offset KB_FLAG
	mov	di,si
	mov	cx,offset KB_BUFFER + size KB_BUFFER - offset KB_FLAG
	cli
	cld
	rep	movsb
	cmp	ax,[ct_focus]		; does the context have focus?
	je	ku8			; yes
	mov	ax,es:[di - size KB_BUFFER - 4]
	mov	es:[di - size KB_BUFFER - 2],ax	; BUFFER_TAIL = BUFFER_HEAD
ku8:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	cx
	pop	ax
ku9:	popf
	ret
ENDPROC	kbd_now

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; switch_focus
;
; Switch focus to the next console context in our chain.
;
; This is called from check_hotkey, which is called at interrupt time, as
; well as whenever the bios_lock is released with a switch request pending.
; ddcon_open and ddcon_close use switch_to instead, which switches focus to a
; particular context (BX), unless BX is zero.
;
; Inputs:
;	CX = focus context, if any
;	BX = context to switch to, or 0 for the next (switch_to only)
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	switch_focus
;
; If bios_lock is set, then the switch must be deferred until the lock
; is released.  It may well be that there's no context to switch TO, but
; it's cheaper to defer now and ask questions later.
;
	cmp	[bios_lock],0
	je	switch_now
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	inc	[req_switch]
	pop	ds
	ASSUME	DS:NOTHING
	ret

	DEFLBL	switch_now,near
	sub	bx,bx			; BX = 0 (the next context)
	DEFLBL	switch_to,near
	push	cx
	push	si
	push	di
	push	ds
	mov	si,bx			; SI = context to switch to, if any
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	inc	[bios_lock]		; defer switches until this one is done
	ASSUME	DS:NOTHING
	mov	ah,DOS_UTL_LOCK
	call	far ptr DDINT_UTIL	; lock the current session
	push	es
	jcxz	sf8			; nothing to do
	mov	ds,cx
	ASSERT	STRUCT,ds:[0],CT
	mov	cx,si			; a particular context?
	jcxz	sf0			; no
	jmp	short sf2
sf0:	mov	cx,ds:[CT_NEXT]
	jcxz	sf1
	jmp	short sf2
sf1:	mov	cx,[ct_head]
	cmp	cx,[ct_focus]
	je	sf8			; nothing to do
sf2:	call	mode_switch		; can the switch happen?
	jc	sf8			; no
	mov	es,cs:[0].DDH_DATA
	ASSUME	ES:CODE
	xchg	cx,[ct_focus]
	ASSUME	ES:NOTHING
	mov	ds,cx
	call	kbd_update		; (it has no keys now)
	call	draw_border		; redraw the border and hide
	call	hide_cursor		; the cursor of the outgoing context
	mov	ds,[ct_focus]
	call	kbd_update		; (and it has the BIOS's)
	call	show_page		; display the page, redraw the border,
	call	draw_border		; and show the cursor of the incoming
	call	show_cursor		; context
;
; End the wait of every session that was waiting for this context to have
; focus (see wait_focus).
;
	mov	dx,ds
	mov	di,1			; DX:DI = wait ID
sf7:	mov	ah,DOS_UTL_ENDWAIT
	call	far ptr DDINT_UTIL
	jnc	sf7			; (until no more are found)
sf8:	pop	es
	mov	ah,DOS_UTL_UNLOCK
	call	far ptr DDINT_UTIL	; unlock the current session
	call	unlock_bios		; (and any switch requested meanwhile)
	pop	ds
	pop	di
	pop	si
	pop	cx
sf9:	ret
ENDPROC	switch_focus

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scroll_buf
;
; Scrolls (or clears) a window of a page that isn't displayed (a virtual
; page's buffer, or another page of the adapter), like the BIOS's VIDEO_SCROLL
; and VIDEO_SCROLLDN functions do on the screen, with the BIOS locked, so that
; no swap_page moves the context meanwhile, and unless the page is in a CGA's
; memory (see below), with the session locked, too, so that no other session
; moves it or frees its buffer (see save_screen and restore_screen).
;
; Moving a CGA's memory causes "snow" on the page it's displaying, but unlike
; the BIOS, we don't blank the display meanwhile, since the flicker would have
; no visible cause; instead, each row is moved (or filled) during vertical
; retrace (see scroll_wait), so a scroll can take a number of frames.
;
; Inputs:
;	AH = VIDEO_SCROLL or VIDEO_SCROLLDN
;	AL = # lines (0 to clear the window)
;	BH = fill attributes
;	CH,CL = row,col of top left
;	DH,DL = row,col of bottom right
;	DS = CONSOLE context
;
; Modifies:
;	AX, BX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	scroll_buf
	push	si
	push	di
	push	bp
	push	es
	call	chk_snow		; is the page in CGA memory?
	jnc	sb0			; no
	call	chk_mem			; and not in a buffer?
	stc
	je	sb0a			; yes, so the session isn't locked
sb0:	push	ax
	mov	ah,DOS_UTL_LOCK
	call	far ptr DDINT_UTIL	; lock it (and clear carry)
	pop	ax
sb0a:	sbb	bp,bp
	push	bp			; (BP = 0 if the session is locked)
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	inc	[bios_lock]
	pop	ds
	ASSUME	DS:NOTHING
	sti				; (see scroll)
	push	ds
	push	bx			; save BH (fill attributes)
	sub	dx,cx
	add	dx,0101h		; DH = rows, DL = columns
	cmp	al,dh			; every line (or more)?
	jae	sb1			; yes
	test	al,al			; clearing the window?
	jnz	sb2			; no
sb1:	mov	al,dh			; AL = # lines to clear
sb2:	mov	bl,ds:[CT_COLS].LB	; (the columns of its mode)
	mov	bh,0
	add	bx,bx
	mov	bp,bx			; BP = bytes per row
	cmp	ah,VIDEO_SCROLL		; scrolling up?
	je	sb3			; yes
	add	ch,dh
	dec	ch			; no, so start at the bottom row
	neg	bp			; and move upward
sb3:	push	dx
	mov	dx,cx
	call	get_curpos		; BX = offset of the first row
	pop	dx
	push	ax
	call	get_start		; (an adapter's page has an offset)
	add	bx,ax
	pop	ax
	mov	di,bx			; DI -> first row
	call	chk_snow		; is the page in CGA memory?
	sbb	bh,bh			; BH = -1 if so (see scroll_wait)
	call	chk_mem			; unless it's in a buffer
	je	sb3a
	mov	bh,0
sb3a:
	mov	es,ds:[CT_SCREEN]._SEG
	push	es
	pop	ds			; DS = ES = buffer
	cbw
	xchg	cx,ax			; CX = # lines
	mov	bl,cl			; BL = # lines to fill
	mov	si,di
sb4:	add	si,bp
	loop	sb4			; SI -> row that moves to the first row
	sub	dh,bl			; DH = # lines to move
	jmp	short sb6
sb5:	call	scroll_wait
	mov	cl,dl
	push	si
	push	di
	rep	movsw
	pop	di
	pop	si
	add	si,bp
	add	di,bp
sb6:	dec	dh
	jns	sb5
	pop	ax			; AH = fill attributes
	mov	al,' '
sb7:	call	scroll_wait
	mov	cl,dl
	push	di
	rep	stosw
	pop	di
	add	di,bp
	dec	bl
	jnz	sb7
	sti				; (see scroll_wait)
	pop	ds
	pop	bp
	pop	es
	test	bp,bp			; is the session locked?
	jnz	sb9			; no
	mov	ah,DOS_UTL_UNLOCK
	call	far ptr DDINT_UTIL	; yes, so unlock it
sb9:	pop	bp
	pop	di
	pop	si
	jmp	unlock_bios
ENDPROC	scroll_buf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scroll_wait
;
; Before scroll_buf moves or fills a row of a CGA's memory, waits until the
; CGA is in vertical retrace, and returns with interrupts off.  The retrace
; bit is set for the first 16 of the 38 scan lines between frames, so when
; it's set, at least 22 scan lines (1.4ms) remain, and a row of 80 columns
; takes an 8088 about 0.4ms.  Interrupts are allowed between rows; whatever
; time they take, the bit is tested again afterward.
;
; Inputs:
;	BH = 0 if the page isn't in a CGA's memory (nothing to wait for)
;
; Outputs:
;	Interrupts off (unless BH = 0)
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	scroll_wait
	test	bh,bh
	jz	sw9
	push	ax
	push	dx
sw1:	sti				; (in effect after the next opcode)
	mov	dx,3DAh
	cli
	in	al,dx
	test	al,08h			; in vertical retrace?
	jz	sw1			; not yet
	pop	dx
	pop	ax
sw9:	ret
ENDPROC	scroll_wait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swap_now
;
; Does the exchange for swap_page (see above).
;
; Inputs:
;	DS = CONSOLE context (on a virtual page)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, DS, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	swap_now
	mov	ax,ds
	call	chk_blocked		; is another context blocking it?
	jnc	swp0			; no
	ret
swp0:	call	get_place		; BX = con_place index
	mov	cl,shown_page[bx]	; CL = displayed page
	mov	ch,ds:[CT_PAGE]		; CH = virtual page
	mov	dx,ds:[CT_PORT]		; DX = adapter port
;
; The next context goes on the other page now, if it was going on either.
;
	mov	es,cs:[0].DDH_DATA
	ASSUME	ES:CODE
	mov	al,byte ptr con_place[bx+2]
	cmp	al,ch
	jne	swp2a
	mov	byte ptr con_place[bx+2],cl
swp2a:	cmp	al,cl
	jne	swp2b
	mov	byte ptr con_place[bx+2],ch
	ASSUME	ES:NOTHING
swp2b:	call	get_frame		; AX = adapter's video memory
	mov	si,ds:[CT_SCREEN]._SEG	; SI = buffer
	mov	es,ax
	mov	bp,ax			; BP = adapter's video memory, too
	mov	al,16
	mul	cl
	xchg	al,ah
	xchg	di,ax			; ES:DI -> displayed page
	push	di
	push	cx
	mov	ds,si
	sub	si,si			; DS:SI -> buffer
	mov	cx,PAGE_LEN SHR 1
swp3:	mov	ax,es:[di]
	movsw
	mov	[si-2],ax
	loop	swp3
	pop	cx
	pop	di			; DI = offset of the displayed page
	mov	si,ds			; SI = buffer again
	mov	ax,bp			; AX = adapter's video memory again
	sub	bp,bp			; BP = # contexts moved to the buffer
	mov	bx,[ct_head]
swp4:	test	bx,bx
	jz	swp7
	mov	es,bx
	cmp	es:[CT_PORT],dx		; same adapter?
	jne	swp6			; no
	cmp	es:[CTO_PAGE],ch	; on the virtual page?
	jne	swp5			; no
	mov	es:[CT_SCREEN]._SEG,ax	; yes, so it's displayed now
	add	es:[CT_SCREEN]._OFF,di
	mov	es:[CT_PAGE],cl
	mov	es:[CTO_PAGE],cl
	jmp	short swp6
swp5:	cmp	es:[CTO_PAGE],cl	; on the displayed page?
	jne	swp6			; no
	mov	es:[CT_SCREEN]._SEG,si	; yes, so it's in the buffer now
	sub	es:[CT_SCREEN]._OFF,di
	mov	es:[CT_PAGE],ch
	mov	es:[CTO_PAGE],ch
	inc	bp
swp6:	mov	bx,es:[CT_NEXT]
	jmp	swp4
swp7:	test	bp,bp			; did any context move to the buffer?
	jnz	swp9			; yes
	mov	cx,si
	mov	ds,cs:[0].DDH_DATA	; (DS can't hold the block being freed)
	call	free_buf		; no, so free it
swp9:	ret
ENDPROC	swap_now

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_vbuf
;
; Every context on a virtual page shares the page's buffer (see swap_page),
; so a new context on one uses the buffer of another context on the page, or
; else allocates a cleared buffer, owned by the system, since it outlives any
; program that opened a context.
;
; Inputs:
;	AX = new CONSOLE context (not in our chain yet)
;	BL = virtual page, BH = CTSTAT bits
;
; Outputs:
;	Carry clear if successful (the context's CT_SCREEN._SEG is the buffer);
;	otherwise, carry set, and the context has been freed
;
; Modifies:
;	ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_vbuf
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	ax			; (context)
	mov	al,bh
	and	al,CTSTAT_ADAPTER
	mov	ah,bl			; AH = page, AL = adapter bit
	call	find_page		; ES = a context on the page, if any
	jc	gvb1			; none
	mov	ax,es:[CT_SCREEN]._SEG	; AX = its buffer
	jmp	short gvb2
gvb1:	mov	di,PAGE_LEN
	call	alloc_sys		; AX = segment (or selector)
	pop	es			; ES = context
	jc	gvb8
	push	es
	mov	es,ax
	mov	cx,PAGE_LEN SHR 1
	sub	di,di
	mov	ax,0720h
	rep	stosw			; clear the buffer
	mov	ax,es
gvb2:	pop	es			; ES = context
	mov	es:[CT_SCREEN]._SEG,ax	; (and carry is clear)
	jmp	short gvb9
gvb8:	call	free_seg		; free the context
	stc
gvb9:	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	get_vbuf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; release_now
;
; The rest of release_mode, for more than one console.
;
; Inputs:
;	DS = CONSOLE context (mode_ctx)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	release_now
	call	restore_screen		; (if save_screen saved anything)
	push	ds
	mov	ax,ds:[CT_PORT]		; AX = adapter port
	mov	cx,[ct_head]
rg1:	jcxz	rg3
	mov	ds,cx
	cmp	ds:[CT_PORT],ax		; context on the same adapter?
	jne	rg2			; no
	push	ax
	call	draw_border		; yes, redraw its border (if any)
	call	show_page		; and display its page (if it has focus)
;
; The mode change also moved the cursor and reset its type, so restore those
; of the context with focus.
;
	mov	ax,ds
	cmp	ax,[ct_focus]
	jne	rg1a
	call	show_cursor
rg1a:	pop	ax
rg2:	mov	cx,ds:[CT_NEXT]
	jmp	rg1
rg3:	pop	ds
	DEFLBL	wake_ctxs,near		; (see hide_mode)
	call	update_slots		; (and give them their video memory)
;
; Now end the wait for every waiting packet that isn't a READ packet (ie,
; every blocked write or IOCTL); each one checks again whether it's blocked
; (or paused), and if so, simply waits again.  Each packet is removed from
; the chain before its wait is ended, so that it can safely be added again.
;
	push	ds
	mov	ds,cs:[0].DDH_DATA
	mov	bx,offset wait_ptr	; DS:BX -> link to the first packet
	cli
rg4:	les	di,dword ptr [bx]	; ES:DI -> next packet
	cmp	di,-1			; end of chain?
	je	rg9			; yes
	cmp	es:[di].DDP_CMD,DDC_READ; READ packet?
	je	rg5			; yes, leave it alone
	mov	ax,es:[di].DDP_PTR._OFF	; no, so unlink it
	mov	[bx]._OFF,ax
	mov	ax,es:[di].DDP_PTR._SEG
	mov	[bx]._SEG,ax
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	mov	ah,DOS_UTL_ENDWAIT
	call	far ptr DDINT_UTIL	; end the wait on DX:DI (see int_util)
	cli
	jmp	rg4			; (DS:BX still -> the same link)
rg5:	push	es
	pop	ds
	lea	bx,[di].DDP_PTR		; DS:BX -> this packet's link
	jmp	rg4
rg9:	sti
	pop	ds
	ret
ENDPROC	release_now

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; update_slots
;
; Calls set_slot for every context, after a change to which context is
; blocking the others (mode_ctx).
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	update_slots
	push	ds
	mov	cx,[ct_head]
us1:	jcxz	us9
	mov	ds,cx
	call	set_slot
	mov	cx,ds:[CT_NEXT]
	jmp	us1
us9:	pop	ds
	ret
ENDPROC	update_slots

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_slot
;
; In protected mode, a program draws on a context's video memory through an
; LDT selector that we create for the context (see ddcon_getmode) and decide
; what it maps (CPU_MAP with MEMF_REMAP), which we change only when the
; sessions that use it aren't running (eg, when another context's mode change
; blocks them).  It maps the adapter's video memory, since the context has a
; region (or page) of its own there, from the start of the context's page in
; a text mode, so that a program's offset 0 is its own page, as it would be on
; page 0 (unless the page is virtual, where it's the adapter's first page;
; see swap_page), or in an EGA or VGA's graphics modes,
; which have the screen to themselves, that memory, which the 80386 driver
; also takes to mean that a V86 machine can use the video ports; see
; CPU_V86), or while another context is blocking it
; (see chk_blocked), the copy of that memory that save_screen made, so the
; program keeps running; if there's no copy, the selector is not present,
; so a program that loads it waits (see SELID_WAIT), as its output does.
;
; Inputs:
;	DS = CONSOLE context
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_slot
	mov	bx,ds:[CT_SLOT]
	test	bx,bx			; does it have a selector?
	jz	ss9			; no
	call	slot_addr		; DX:CX = address, SI:DI = length
;
; An EGA or VGA's graphics modes (0Dh-13h) use the 64K at A0000h instead,
; and a text mode starts at the context's page (AX = its offset).
;
	sub	ax,ax
	cmp	ds:[CT_MODE],0Dh	; is the context in one of those?
	jb	ss0			; no
	mov	dx,000Ah
	mov	cx,ax			; DX:CX = A0000h
	mov	di,ax
	inc	si			; SI:DI = 64K
ss0:	cmp	ds:[CT_MODE],MODE_CO80	; a text mode (0-3)?
	jbe	ss0a			; yes
	cmp	ds:[CT_MODE],MODE_MONO	; or the MDA's?
	jne	ss0b			; no
ss0a:	call	get_start		; AX = offset of the context's page
	sub	di,ax			; SI:DI = length from there
ss0b:	push	ax
	mov	ax,ds
	call	chk_blocked		; is another context blocking it?
	jnc	ss1			; no
	cmp	ds:[CT_MODE],0Dh	; hidden in a VGA graphics mode?
	jae	ss0c			; yes, so its programs wait
	call	copy_addr		; DX:CX = the copy of adapter's memory
	mov	ax,ds
	cmp	ax,[mode_ctx]		; is it hidden there (see hide_mode)?
	je	ss1			; yes
	mov	ax,ds:[CT_SCREEN]._SEG
	cmp	ax,[save_seg]		; is its memory the copy?
	je	ss1			; yes
ss0c:	sub	si,si
	sub	di,di			; no, so take it away (SI:DI = 0)
ss1:	pop	ax
	add	cx,ax
	adc	dx,0			; DX:CX = its page (or in the copy)
	mov	ax,(CPU_MAP SHL 8) OR MEMF_REMAP
	call	far ptr DDINT_CPU
	or	si,di			; is it present now?
	jz	ss9			; no
	mov	dx,SELID_WAIT
	mov	di,bx			; DX:DI = its wait ID
ss2:	mov	ah,DOS_UTL_ENDWAIT
	call	far ptr DDINT_UTIL	; end each wait for it
	jnc	ss2
ss9:	ret
ENDPROC	set_slot

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
	mov	cx,ds:[CT_SCREEN]._SEG
	call	free_buf		; no, so free the buffer
fvb9:	pop	ds
	ret
ENDPROC	free_vbuf

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
; next_page
;
; For ddcon_open: a context that starts a page goes on the first page with no
; contexts, so that the pages of closed contexts (eg, from START) are used
; again, before any virtual page that would need a buffer.
;
; Inputs:
;	BH = CTSTAT bits, SI = con_place index
;	DS = CODE
;
; Outputs:
;	Carry set if there's no page left
;
; Modifies:
;	AX, ES
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	next_page
	cmp	word ptr con_place[si],0	; at the top left of a page?
	jne	np9				; no (and carry is clear)
	mov	al,bh
	and	al,CTSTAT_ADAPTER	; AL = adapter bit
	mov	ah,-1
np1:	inc	ah
	cmp	ah,MAX_PAGES		; any page left?
	cmc
	jc	np9			; no
	call	find_page		; is it in use?
	jnc	np1			; yes
	mov	byte ptr con_place[si+2],ah
	clc
np9:	ret
ENDPROC	next_page

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; next_place
;
; For ddcon_open: advances the adapter's next position: downward, then
; rightward, and then to the top left of the next page.
;
; Inputs:
;	CL,CH = context's columns and rows, DL,DH = its position
;	SI = con_place index
;	DS = CODE
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	next_place
	push	ax
	mov	ax,dx
	add	ah,ch			; AH = row below the context
	cmp	ah,[max_rows]		; at the bottom of the page?
	jb	nx1			; no
	mov	ah,0			; yes, so back to the top
	add	al,cl			; AL = column right of the context
	cmp	al,[max_cols]		; at the right edge of the page?
	jb	nx1			; no
	mov	al,0			; yes, so the next page
	inc	byte ptr con_place[si+2]
nx1:	mov	con_place[si],ax
	pop	ax
	ret
ENDPROC	next_place

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; open_nofocus
;
; For ddcon_open, when the new context doesn't have the focus: its cursor is
; hidden, the BIOS data is restored from the context with focus, and the
; focus goes to the new context if it's taking it (see switch_to).
;
; Inputs:
;	DS = CONSOLE context
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	open_nofocus
	call	hide_cursor		; hide its cursor
	push	ds			; and restore BIOS with data from focus
	mov	ds,[ct_focus]
	call	update_biosdata
	call	draw_cursor		; (whose cursor we may have hidden)
	pop	ds
	mov	cx,ds:[CT_PARENT]	; CX = context with focus, if taking it
	mov	bx,ds			; BX = this context
	jmp	switch_to
ENDPROC	open_nofocus

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; close_focus
;
; For ddcon_close: any context that took the focus from the closing context
; takes it back from that context's parent instead (eg, if START made B from
; A and C from B, and B closes first, then C's focus goes back to A), and if
; the closing context has focus, it goes back to the parent, if any (or else
; the next context; see switch_to).
;
; Inputs:
;	CX = ES = CONSOLE context (closing)
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	close_focus
	mov	ax,es:[CT_PARENT]	; AX = this context's parent, if any
	mov	dx,[ct_head]
	push	ds
cf1:	mov	ds,dx
	cmp	ds:[CT_PARENT],cx	; did it take the focus from this one?
	jne	cf2			; no
	mov	ds:[CT_PARENT],ax	; yes
cf2:	mov	dx,ds:[CT_NEXT]
	test	dx,dx
	jnz	cf1
	pop	ds
	cmp	[ct_focus],cx		; does this context have focus?
	jne	cf9			; no
	xchg	bx,ax			; BX = parent, if any
	jmp	switch_to
cf9:	ret
ENDPROC	close_focus

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_init,far
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS

	mov	ax,[EQUIP_FLAG]		; AX = EQUIP_FLAG
	mov	dl,[CRT_MODE]
	cmp	[MEMORY_SIZE],64	; more than 64K of memory?
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	shown_page[1],dl	; the mode displayed (see show_page)
	mov	es:[bx].DDPI_END._OFF,offset ddcon_init
	ja	ddn0			; yes
	mov	es:[bx].DDPI_END._OFF,offset con_opt
	inc	[one_con]		; one console only (see con_opt)
ddn0:
	mov	ds:[0].DDH_REQUEST,offset DEV:ddcon_req
;
; Determine what kind of video console we're dealing with (MONO or COLOR)
; and what the frame buffer segment is.
;
	mov	dx,0B000h
	mov	si,offset con_place+3	; SI -> # pages of the primary adapter
	and	ax,EQ_VIDEO_MODE
	cmp	ax,EQ_VIDEO_MONO
	je	ddn1
	mov	dx,0B800h
	add	si,4			; SI -> # pages of the alternate adapter
	mov	shown_page[5],MODE_MONO	; (and that's its only mode)
ddn1:	mov	[frame_seg],dx
	mov	byte ptr [si],1		; an MDA has only one page
;
; Record which adapters are present (see ADAPTER_*), by writing a test value
; to each adapter's cursor position (low) register, which is readable, and
; reading it back; ddcon_open uses this to reject a context for an absent
; alternate adapter.
;
	push	bx
	mov	dx,3B4h			; start with the MDA
	mov	bl,ADAPTER_MDA
ddn2:	mov	al,0Fh			; cursor position (low)
	out	dx,al
	inc	dx
	in	al,dx
	mov	ah,al			; AH = original value
	mov	al,55h
	out	dx,al
	in	al,dx
	xchg	al,ah			; AH = value read back
	out	dx,al			; restore the original value
	cmp	ah,55h			; did the adapter respond?
	jne	ddn3			; no
	or	[adapters],bl
ddn3:	mov	dx,3D4h			; then the CGA
	shl	bl,1
	cmp	bl,ADAPTER_CGA
	je	ddn2
;
; An EGA or VGA at the CGA's ports has no "snow" to avoid (see chk_snow), and
; only their BIOS has this function, which returns BH = 0 if the adapter is
; using those ports (an older BIOS returns with BL unchanged).
;
	mov	ah,VIDEO_ALTSEL
	mov	bl,VALT_EGAINFO
	int	INT_VIDEO
	cmp	bl,VALT_EGAINFO		; is there an EGA or VGA?
	je	ddn4			; no
	test	bh,bh			; at the CGA's ports?
	jnz	ddn4			; no
	or	[adapters],ADAPTER_EGA
ddn4:	pop	bx
;
; Install an INT 09h hardware interrupt handler, which we'll use to detect
; keys added to the BIOS keyboard buffer.
;
	mov	al,INT_HW_KBD
	mov	cx,offset ddcon_int09
	mov	dx,cs
	cli
	call	far ptr DDINT_SETVEC	; DX:CX = previous vector
	mov	[kbd_int]._OFF,cx
	mov	[kbd_int]._SEG,dx
	sti
;
; Install an INT 10h services handler to reflect context data into BIOS data.
;
	mov	al,INT_VIDEO
	mov	cx,offset ddcon_int10
	mov	dx,cs
	call	far ptr DDINT_SETVEC	; DX:CX = previous vector
	mov	[video_int]._OFF,cx
	mov	[video_int]._SEG,dx
;
; Install an INT 29h ("FAST PUTCHAR") handler; I think traditionally DOS
; installed its own handler, but that's really our responsibility, especially
; if we want all INT 29h I/O to go through the "system console" -- which for
; now is nothing more than whichever console was opened first.
;
	mov	al,INT_FASTCON
	mov	cx,offset ddcon_int29
	mov	dx,cs
	call	far ptr DDINT_SETVEC
	ret
ENDPROC	ddcon_init

CODE	ends

	end
