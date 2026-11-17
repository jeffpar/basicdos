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

	EXTBYTE	<adapters,bios_lock,max_cols,req_switch,shown_page,one_con>
	EXTWORD	<bios_ctx,con_place,ct_focus,ct_head,frame_seg,mode_ctx>
	extrn	ddcon_int09:far
	extrn	ddcon_int10:far
	extrn	ddcon_int29:far
	extrn	ddcon_req:far
	EXTNEAR	<draw_border,draw_char,draw_cursor,draw_linefeed,free_buf>
	EXTNEAR	<get_curpos,hide_cursor,update_cursor,alloc_sys,find_page>
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
	call	chk_graphics		; graphics mode?
	jnc	scr3			; no
	mov	bh,0			; yes, BH = fill pixels (background)
;
; The BIOS scrolls a context only if it has the entire screen (see mode_ctx
; and update_mode) or the context's page is displayed
; (the mouse driver hides its pointer around a BIOS scroll); otherwise, we
; scroll the page ourselves, with no BIOS data to update (and a virtual page
; is one the BIOS can't reach anyway).
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
	call	get_place		; BX = con_place index
	mov	bl,shown_page[bx]
	cmp	bl,ds:[CT_PAGE]		; is the context's page displayed?
	je	scr4			; yes
	pop	bx
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
; the others (mode_ctx), which owns the screen whether it has focus or not.
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
	je	wf9			; yes
	push	dx
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
; update_mode), every other context on the same adapter is blocked: its
; output waits (see ddcon_write and ddcon_ioctl) and its border isn't drawn,
; until that context returns to its original mode (see release_mode).
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
DEFPROC	chk_blocked
	push	bx
	push	ds
	mov	bx,[mode_ctx]
	test	bx,bx			; is any context blocking the others?
	jz	cb9			; no (and carry is clear)
	cmp	bx,ax			; is it this context?
	je	cb9			; yes (and carry is clear)
	mov	ds,bx
	mov	bx,ds:[CT_PORT]
	mov	ds,ax
	cmp	bx,ds:[CT_PORT]		; is this context on the same adapter?
	clc
	jne	cb9			; no
	stc				; yes, so it's blocked
cb9:	pop	ds
	pop	bx
	ret
ENDPROC	chk_blocked

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; release_mode
;
; Called when the context blocking the others (mode_ctx) returns to its
; original mode (or is closed): the borders of the other contexts on the same
; adapter are redrawn, and every waiting write (or IOCTL) can try again.
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
ENDPROC	release_mode

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
; blocks them).  While another context is blocking it (see chk_blocked), the
; selector is not present, so a program that loads it waits (see SELID_WAIT),
; as its output does; otherwise, it maps the adapter's video memory, since the
; context has a region (or page) of its own there.  A design that saved a
; blocked context's video memory in a buffer could map the buffer instead,
; and let the program keep running.
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
	sub	si,si
	sub	di,di			; SI:DI = 0 (not present)
	mov	ax,ds
	call	chk_blocked		; is another context blocking it?
	jc	ss1			; yes, so take it away
	call	slot_addr		; no, DX:CX = address, SI:DI = length
ss1:	mov	ax,(CPU_MAP SHL 8) OR MEMF_REMAP
	call	far ptr DDINT_CPU
	test	di,di			; is it present now?
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
;
; If ddcon_setmode asked for more than 25 rows (CT_ROWS, which applies only
; to this mode set), the BIOS gives us those rows when we load its 8x8 font
; (while the BIOS data still describes this context).  An EGA's BIOS assumes
; 14-line characters when it converts cursor types, which would hide the
; cursor in 8-line characters, so its cursor emulation is turned off as long
; as the rows are displayed (bit 0 of EGA_MISC_INFO), and a VGA goes back to
; 400 scan lines at its next mode set, whoever sets it.
;
	mov	ch,25
	test	[adapters],ADAPTER_EGA
	jz	um0
	push	ax
	push	bx
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	and	[EGA_MISC_INFO],NOT 1
	mov	bl,0
	xchg	bl,ds:[CT_ROWS]
	test	bl,bl			; more rows?
	jz	um0a			; no
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
um0a:	pop	bx
	pop	ax
um0:	call	update_context		; update CT_MODE, CT_COLS, etc
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
; (see release_mode).
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
	push	bx
	call	update_slots		; (and their video memory selectors)
	pop	bx
	jmp	short um7
um6:	mov	ax,ds
	cmp	ax,[mode_ctx]		; was this context blocking the others?
	jne	um7			; no
	push	bx
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
;	AL, DI, ES
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
; swap_page), so CT_SCREEN is loaded with interrupts off.
;
wcp3:	cli
	les	di,ds:[CT_SCREEN]	; ES:DI -> screen location
	mov	al,cl
	mov	es:[di+bx],ax		; "write" the character and attributes
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
; use, and the text modes that pages can have.  A machine with 64K or less
; has room for none of it, so ddcon_init ends the resident code here instead,
; sets one_con, and ddcon_open then refuses a second console; nothing before
; this calls any of it for the only console (see chk_opt), which always has
; the focus and a page of its own.
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
; Sets an adapter's text mode without clearing its memory.  The BIOS of an
; EGA or VGA does that if bit 7 of the mode is set.  A CGA's BIOS always
; clears all 16K, so we program a CGA ourselves: the 6845's horizontal
; timing registers (0-3, the only ones that differ between text modes) and
; the mode register, along with the BIOS's copy of the latter (which the
; BIOS writes to the mode register again after it scrolls, for example).
;
; Inputs:
;	AL = text mode (0-3)
;	DS = CONSOLE context
;
; Modifies:
;	AX, BX, DX
;
	DEFLBL	CGA_MODES,byte
	db	2Ch,28h,2Dh,29h		; mode register values for modes 0-3
	db	38h,28h,2Dh,0Ah		; 6845 registers 0-3 for 40 columns
	db	71h,50h,5Ah,0Ah		; and for 80 columns

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
shm1:	push	si
	push	es
	mov	bx,offset CGA_MODES
	xlat	CGA_MODES
	lea	si,[bx+4]		; SI -> values for 40 columns
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
	add	dl,3			; DX = mode register port again
	mov	al,bh
	out	dx,al			; new mode, with the display on
	mov	bx,BIOS
	mov	es,bx
	ASSUME	ES:BIOS
	mov	[CRT_MODE_SET],al
	pop	es
	ASSUME	ES:NOTHING
	pop	si
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
; (eg, one that uses INT 10h, since the BIOS can't write to a buffer).
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
; set_bios
;
; The rest of ddcon_setkeys, for a request with CL bit 1 set, or one that
; ends the updates.
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
	mov	di,100h			; SI:DI = length
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
sf2:	mov	es,cs:[0].DDH_DATA
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
; no swap_page moves the context meanwhile.
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
	pop	es
	pop	bp
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
