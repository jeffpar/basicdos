;
; BASIC-DOS Serial Mouse Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; MOUSE$ supports a Microsoft-compatible serial mouse on any COM port, with
; a minimal INT 33h interface (functions 00h-04h, 07h, and 08h), plus one
; BASIC-DOS function (MOUSE_EVENT) that returns queued button events.  The
; pointer is drawn only in MDA and CGA modes (an inverted character cell in
; text modes 0-3 and 7, and an arrow in graphics modes 4-6).  If no mouse
; responds at boot, the driver isn't installed (and uses no memory).
;
; Like Microsoft's driver, positions are "virtual" coordinates (640x200 in
; every mode), with one mickey per horizontal pixel and two per vertical one.
;
; Anything a program draws on top of the pointer is preserved when the
; pointer moves, because only the bits the pointer actually changed (and
; that still have the pointer's values) are restored; see ptr_update.  The
; pointer is also hidden around every INT 10h call that may change the screen
; (eg, scrolls, graphics text output, and mode changes).
;
	BIOSEQU equ 1
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	MOUSE
MOUSE	DDH	<offset DEV:ddmou_end+16,,DDATTR_CHAR,offset ddmou_init,-1,2020244553554F4Dh>

INT_MOUSE	equ	33h	; mouse services
MOUSE_EVENT	equ	0BDh	; BASIC-DOS: get the next button event
MOUSE_MAXFN	equ	08h	; highest standard function supported

VT_NONE		equ	0	; unsupported video mode (no pointer)
VT_TEXT		equ	1	; text modes 0-3 and 7
VT_CGA2		equ	2	; graphics modes 4 and 5 (2 bits per pixel)
VT_CGA1		equ	3	; graphics mode 6 (1 bit per pixel)

QUEUE_MAX	equ	8	; events in queue (must be a power of two)
EVENT_SIZE	equ	6	; event code, buttons, x, and y
ROW_BYTES	equ	3	; video bytes saved per pointer row

	DEFLBL	MOU_TBL,word
	dw	m_reset, m_show, m_hide, m_getpos			; 00-03
	dw	m_setpos, m_none, m_none, m_setx, m_sety		; 04-08

;
; The pointer shape, 8 pixels wide, as pairs of bytes: the pixels the pointer
; covers (the outline is black), and the pixels that are white.
;
	DEFLBL	SHAPE,byte
	db	80h,00h, 0C0h,00h, 0E0h,40h, 0F0h,60h	; B......., BB......
	db	0F8h,70h, 0FCh,78h, 0FEh,7Ch, 0FFh,70h	; BWB....., BWWB....
	db	0FCh,58h, 0DEh,0Ch, 9Eh,0Ch, 0Ch,00h	; (etc)
	DEFLBL	SHAPE_END,byte
SHAPE_ROWS	equ	(SHAPE_END - SHAPE) SHR 1
SAVE_LEN	equ	SHAPE_ROWS * ROW_BYTES
;
; DEFBYTE can't take an expression for its repeat count, so these do.
;
QBUF_LEN	equ	QUEUE_MAX * EVENT_SIZE
MASK_LEN	equ	ROW_BYTES * 2
SBUF_LEN	equ	SAVE_LEN * 2	; size of each half of sav_buf
SBUF2_LEN	equ	SBUF_LEN * 2

UPD_ERASE	equ	01h	; ptr_update operations
UPD_DRAW	equ	02h

;
; The current position and its limits (each as value, minimum, maximum),
; in the same order as DEF_POS, which m_reset copies them from.  Vertical
; positions are kept in mickeys (two per pixel).
;
	DEFLBL	DEF_POS,word
	dw	320,0,639, 200,0,399
	DEFWORD	cur_x,320
	DEFWORD	min_x,0
	DEFWORD	max_x,639
	DEFWORD	cur_y2,200
	DEFWORD	min_y2,0
	DEFWORD	max_y2,399

	DEFWORD	old_x,0		; position of the drawn pointer (see get_scr)
	DEFWORD	old_y,0
	DEFWORD	port_base,0	; base port of the mouse's COM port
	DEFWORD	vid_seg,0B800h	; video memory segment
	DEFWORD	old_buf,0	; sav_buf half used by the drawn pointer
	DEFWORD	new_buf,0	; sav_buf half used by the new pointer
	DEFWORD	pd_y,0		; pu_draw's screen row
	DEFWORD	pd_r,0		; pu_draw's pointer row
	DEFWORD	pd_c0,0		; pu_draw's 1st byte relative to old_xb
;
; The drawn (old) pointer's location, followed by the new pointer's location,
; in the same order (see ptr_update).
;
	DEFWORD	old_xb,0	; byte offset of the pointer within a row
	DEFWORD	old_n,0		; bytes per row on the screen
	DEFWORD	old_rows,0	; rows on the screen
	DEFWORD	old_addr,0,SHAPE_ROWS
	DEFWORD	new_xb,0
	DEFWORD	new_n,0
	DEFWORD	new_rows,0
	DEFWORD	new_addr,0,SHAPE_ROWS
	DEFPTR	int10_ptr	; original INT 10h handler
	DEFBYTE	hidden,-1	; zero if the pointer is visible
	DEFBYTE	drawn,0		; non-zero if the pointer is on the screen
	DEFBYTE	vid_type,VT_NONE
	DEFBYTE	vid_shift,3	; text column width (as a shift count)
	DEFBYTE	pr_sh,0		; pixel shift within the pointer's 1st byte
	DEFBYTE	upd_ops,0	; UPD_* operations (see ptr_update)
	DEFBYTE	buttons,0	; button state (bit 0 left, bit 1 right)
	DEFBYTE	pkt_cnt,0	; bytes of the current packet received
	DEFBYTE	pkt_b1,0	; 1st byte of the current packet
	DEFBYTE	pkt_b2,0	; 2nd byte of the current packet
	DEFBYTE	q_head,0	; next event to remove
	DEFBYTE	q_tail,0	; next event to add
	DEFBYTE	q_buf,0,QBUF_LEN
	DEFBYTE	row_mask,0,MASK_LEN
	DEFBYTE	sav_buf,0,SBUF2_LEN
	DEFBYTE	ers_buf,0,SAVE_LEN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; There are no driver commands (other than INIT); see INT 33h instead.
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;	DDP_STATUS updated
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddmou_req,far
	mov	es:[bx].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	ret
ENDPROC	ddmou_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddmou_int33 (INT 33h mouse services)
;
; Every function preserves all registers other than its outputs.
;
; Inputs:
;	AX = function (see MOU_TBL and MOUSE_EVENT)
;
; Outputs:
;	Varies
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddmou_int33,far
	sti
	cld
	push	ds
	push	cs
	pop	ds
	ASSUME	DS:CODE
	cmp	ax,MOUSE_EVENT
	je	m_event
	cmp	ax,MOUSE_MAXFN
	ja	mi9
	push	si
	mov	si,ax
	add	si,si
	call	MOU_TBL[si]
	pop	si
mi9:	pop	ds
	iret
;
; MOUSE_EVENT: if BX is zero, remove the next button event from the queue,
; and return its code in AX (1 = left button pressed, 2 = left released,
; 3 = right pressed, 4 = right released), with BX = the buttons, and CX, DX
; = the position at the time of the event; if there are no events (or BX is
; non-zero), AX is zero and BX, CX, and DX are the current values.
;
; Unlike the other functions, the position is returned in screen units:
; pixels in graphics modes, or a column and row (starting at 1) in text modes.
;
m_event:
	push	si
	cli
	mov	si,bx			; SI = request
	mov	bl,[buttons]
	mov	bh,0
	sub	ax,ax			; AX = zero (no event)
	mov	cx,[cur_x]
	mov	dx,[cur_y2]
	shr	dx,1
	test	si,si			; event requested?
	jnz	me8			; no
	mov	al,[q_head]
	cmp	al,[q_tail]		; any events?
	je	me7			; no
	mov	ah,EVENT_SIZE
	mul	ah
	xchg	si,ax
	add	si,offset q_buf		; SI -> event
	lodsw
	mov	bl,ah			; BX = buttons
	mov	ah,0			; AX = event code
	mov	cx,[si]
	mov	dx,[si+2]		; CX, DX = position
	inc	[q_head]
	and	[q_head],QUEUE_MAX-1
	jmp	short me8
me7:	mov	al,0
me8:	sti
	call	get_scr			; convert CX, DX to screen units
	cmp	[vid_type],VT_TEXT
	jne	me9
	inc	cx			; text columns and rows start at 1
	inc	dx
me9:	pop	si
	jmp	mi9
ENDPROC	ddmou_int33

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; m_reset (function 00h): hides the pointer, centers it, resets the limits,
; empties the event queue, and determines the video mode.
;
; Outputs:
;	AX = -1 (mouse installed), BX = 2 (number of buttons)
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	m_reset
	push	cx
	push	si
	push	di
	push	es
	pushf
	cli
	mov	[hidden],0		; ptr_hide will make this -1
	call	ptr_hide
	push	ds
	pop	es
	mov	si,offset DEF_POS
	mov	di,offset cur_x
	mov	cx,6
	rep	movsw
	mov	al,[q_tail]
	mov	[q_head],al
	popf
	call	get_mode
	pop	es
	pop	di
	pop	si
	pop	cx
	mov	ax,-1
	mov	bx,2
	DEFLBL	m_none,near
	ret
ENDPROC	m_reset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; m_show (function 01h) and m_hide (function 02h)
;
; As with Microsoft's driver, every m_hide must be matched by an m_show
; before the pointer will be visible again (and redundant m_shows are
; ignored).  The video mode is determined again whenever the pointer becomes
; visible, so a program should hide the pointer before changing modes.
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	m_show
	stc
	jmp	ptr_show
ENDPROC	m_show

DEFPROC	m_hide
	jmp	ptr_hide
ENDPROC	m_hide

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; m_getpos (function 03h)
;
; Outputs:
;	BX = buttons (bit 0 left, bit 1 right)
;	CX = x, DX = y (virtual coordinates)
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	m_getpos
	mov	bl,[buttons]
	mov	bh,0
	mov	cx,[cur_x]
	mov	dx,[cur_y2]
	shr	dx,1
	ret
ENDPROC	m_getpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; m_setpos (function 04h)
;
; Inputs:
;	CX = x, DX = y (virtual coordinates)
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	m_setpos
	mov	[cur_x],cx
	push	dx
	shl	dx,1
	mov	[cur_y2],dx
	pop	dx
	jmp	ptr_move
ENDPROC	m_setpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; m_setx (function 07h) and m_sety (function 08h)
;
; Inputs:
;	CX = minimum, DX = maximum (in either order)
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	m_setx
	push	cx
	push	dx
	push	si
	mov	si,offset min_x
	jmp	short msr
ENDPROC	m_setx

DEFPROC	m_sety
	push	cx
	push	dx
	push	si
	mov	si,offset min_y2
	shl	cx,1
	shl	dx,1
msr:	cmp	cx,dx
	jle	msr1
	xchg	cx,dx
msr1:	mov	[si],cx
	cmp	si,offset min_y2	; vertical limits?
	jne	msr2			; no
	inc	dx			; yes, include the 2nd mickey
msr2:	mov	[si+2],dx
	pop	si
	pop	dx
	pop	cx
	jmp	ptr_move
ENDPROC	m_sety

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddmou_int10 (BIOS video services)
;
; If the pointer is visible, hide it around any INT 10h function that may
; change the screen; ie, anything other than 01h-03h (cursor functions) and
; 0Fh (get mode).  After a mode change (function 00h), the mode is determined
; again before the pointer is redrawn.
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddmou_int10,far
	cmp	[hidden],0		; is the pointer visible?
	jne	i10x			; no
	cmp	ah,0Fh
	je	i10x
	test	ah,ah
	jz	i10a
	cmp	ah,3
	jbe	i10x
i10a:	push	ax			; save the function
	push	ds
	push	cs
	pop	ds
	ASSUME	DS:CODE
	call	ptr_hide
	pop	ds
	ASSUME	DS:NOTHING
	pushf
	call	[int10_ptr]
	push	ds
	push	cs
	pop	ds
	ASSUME	DS:CODE
	push	bp
	mov	bp,sp
	cmp	byte ptr [bp+5],1	; carry set if function was 00h
	pop	bp
	call	ptr_show
	pop	ds
	ASSUME	DS:NOTHING
	add	sp,2
	iret
i10x:	jmp	[int10_ptr]
ENDPROC	ddmou_int10

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddmou_irq (serial mouse hardware interrupt handler)
;
; Each packet is 3 bytes, where only the 1st byte has bit 6 set:
;
;	byte 1:	0 1 L R Y7 Y6 X7 X6
;	byte 2:	0 0 X5 X4 X3 X2 X1 X0
;	byte 3:	0 0 Y5 Y4 Y3 Y2 Y1 Y0
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddmou_irq,far
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp
	push	ds
	push	es
	push	cs
	pop	ds
	ASSUME	DS:CODE
	push	cs
	pop	es
	cld
	mov	dx,[port_base]
	in	al,dx			; read the RBR
	test	al,40h			; 1st byte of a packet?
	jz	irq1			; no
	mov	[pkt_b1],al
	mov	[pkt_cnt],1
	jmp	short irq8
irq1:	cmp	[pkt_cnt],1		; is this the 2nd byte?
	jne	irq2			; no
	mov	[pkt_b2],al
	inc	[pkt_cnt]
	jmp	short irq8
irq2:	cmp	[pkt_cnt],2		; is this the 3rd byte?
	jne	irq8			; no (we're out of sync)
	mov	[pkt_cnt],0
	mov	bl,[pkt_b1]
	mov	ah,bl
	mov	cl,4
	shl	ah,cl
	and	ah,0C0h
	or	al,ah
	cbw
	add	[cur_y2],ax		; add the y delta
	mov	al,bl
	mov	cl,6
	shl	al,cl
	or	al,[pkt_b2]
	cbw
	add	[cur_x],ax		; add the x delta
	push	bx
	call	do_move			; clamp the position, move the pointer
	push	cs
	pop	es
	pop	bx
;
; Update the buttons, and queue an event for each button that changed.
;
	sub	ax,ax
	test	bl,20h			; left button down?
	jz	irq3			; no
	inc	ax
irq3:	test	bl,10h			; right button down?
	jz	irq4			; no
	or	al,2
irq4:	xchg	[buttons],al
	xor	al,[buttons]		; AL = buttons that changed
	mov	ah,[buttons]		; AH = new button state
	mov	cl,1			; CL = event code for 1st button
irq5:	shr	al,1			; did this button change?
	jnc	irq7			; no
	push	ax
	mov	al,cl
	test	ah,1			; is it down now?
	jnz	irq6			; yes
	inc	ax			; no, so it's a release event
irq6:	call	add_event
	pop	ax
irq7:	shr	ah,1
	add	cl,2
	cmp	cl,5
	jb	irq5
irq8:	mov	al,20h			; EOI the interrupt
	out	20h,al
	pop	es
	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	iret
ENDPROC	ddmou_irq

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_event
;
; Adds an event (with the current buttons and position) to the queue, unless
; the queue is full.
;
; Inputs:
;	AL = event code
;	DS = ES = CS
;
; Modifies:
;	AX, DX, DI
;
	ASSUME	CS:CODE, DS:CODE, ES:CODE, SS:NOTHING
DEFPROC	add_event
	mov	dl,[q_tail]
	mov	dh,dl
	inc	dh
	and	dh,QUEUE_MAX-1
	cmp	dh,[q_head]		; is the queue full?
	je	ae9			; yes
	push	ax
	mov	al,EVENT_SIZE
	mul	dl
	add	ax,offset q_buf
	xchg	di,ax			; DI -> event
	pop	ax
	mov	ah,[buttons]
	stosw				; store the code and buttons
	mov	ax,[cur_x]
	stosw
	mov	ax,[cur_y2]
	shr	ax,1
	stosw
	mov	[q_tail],dh
ae9:	ret
ENDPROC	add_event

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ptr_hide, ptr_show, and ptr_move
;
; These preserve all registers (and the interrupt flag), and call do_hide,
; do_show, or do_move with interrupts disabled.
;
; Inputs:
;	DS = CS
;	Carry set (for ptr_show) to determine the mode if the pointer appears
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ptr_hide
	push	si
	mov	si,offset do_hide
	jmp	short ptr_call
ENDPROC	ptr_hide

DEFPROC	ptr_show
	push	si
	mov	si,offset do_show
	jmp	short ptr_call
ENDPROC	ptr_show

DEFPROC	ptr_move
	push	si
	mov	si,offset do_move
	DEFLBL	ptr_call,near
	push	ax
	push	bx
	push	cx
	push	dx
	push	di
	push	bp
	push	es
	pushf
	cld
	call	si
	popf
	pop	es
	pop	bp
	pop	di
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	pop	si
	ret
ENDPROC	ptr_move

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; do_hide, do_show, and do_move
;
; Inputs:
;	DS = CS
;	Carry set (for do_show) to determine the mode if the pointer appears
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, ES
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	do_hide
	cli
	dec	[hidden]
	jmp	short ptr_erase
ENDPROC	do_hide

DEFPROC	do_show
	jnc	ds1
	cmp	[hidden],-1		; will the pointer appear?
	jne	ds1			; no
	call	get_mode		; yes, so determine the mode
ds1:	cli
	cmp	[hidden],0		; already visible?
	je	ds9			; yes
	inc	[hidden]
	jz	ptr_draw
ds9:	ret
ENDPROC	do_show

DEFPROC	do_move
	cli
	mov	si,offset cur_x
	call	clamp
	mov	si,offset cur_y2
	call	clamp
	cmp	[hidden],0		; is the pointer visible?
	jne	ds9			; no
	cmp	[drawn],0		; is it drawn?
	je	ptr_draw		; no
	call	get_pos			; CX, DX = new position
	cmp	cx,[old_x]
	jne	dm1
	cmp	dx,[old_y]
	je	ds9			; the pointer hasn't moved
dm1:	mov	al,UPD_ERASE OR UPD_DRAW
	jmp	short ptr_update
ENDPROC	do_move

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ptr_draw and ptr_erase
;
; Inputs:
;	DS = CS (and interrupts disabled)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, ES
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ptr_draw
	cmp	[vid_type],VT_NONE
	je	pe9
	call	get_pos
	mov	al,UPD_DRAW
	jmp	short ptr_update
ENDPROC	ptr_draw

DEFPROC	ptr_erase
	cmp	[drawn],0		; is the pointer drawn?
	je	pe9			; no
	mov	al,UPD_ERASE
	jmp	short ptr_update
pe9:	ret
ENDPROC	ptr_erase

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ptr_update
;
; Erases the pointer, draws it, or both (ie, moves it).  Drawing saves each
; video byte the pointer overlaps (S) and the byte it drew (D) in one half of
; sav_buf, and erasing restores only the bits that the pointer changed and
; that still have the pointer's values (ie, it leaves alone anything drawn on
; top of the pointer).
;
; To move the pointer smoothly (ie, so that the screen is never caught with
; the pointer missing or partly drawn), all the new video bytes are computed
; first, without touching the screen: the old pointer's restored bytes go in
; ers_buf, and the new pointer's bytes (which may overlap the old pointer, in
; which case they're computed from ers_buf, and ers_buf is updated to match)
; go in the other half of sav_buf.  Then they're all copied to the screen at
; once (see pu_blit), new pointer first.
;
; Inputs:
;	AL = UPD_ERASE and/or UPD_DRAW
;	CX, DX = new position, if UPD_DRAW (see get_scr)
;	DS = CS (and interrupts disabled)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, ES
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ptr_update
	push	cx
	push	dx
	mov	[upd_ops],al
	mov	es,[vid_seg]
	mov	si,offset sav_buf
	cmp	[old_buf],si		; is the old pointer in the 1st half?
	jne	pu0			; no
	add	si,SBUF_LEN		; yes, so use the 2nd half
pu0:	mov	[new_buf],si
	cmp	[vid_type],VT_TEXT
	jne	pu2
;
; In text modes, the pointer is a single character cell.
;
	test	al,UPD_ERASE
	jz	pu1
	mov	cx,[old_x]
	mov	dx,[old_y]
	sub	bp,bp
	mov	si,[old_buf]
	call	pu_text
pu1:	pop	dx
	pop	cx
	push	cx
	push	dx
	test	[upd_ops],UPD_DRAW
	jz	pu1a
	mov	bp,1
	mov	si,[new_buf]
	call	pu_text
pu1a:	jmp	pu8
;
; In graphics modes, compute everything, and then copy it to the screen.
;
pu2:	test	al,UPD_ERASE
	jz	pu3
	call	pu_erase
	pop	dx
	pop	cx
	push	cx
	push	dx
pu3:	test	[upd_ops],UPD_DRAW
	jz	pu4
	call	pu_draw
	mov	si,[new_buf]
	add	si,SAVE_LEN		; SI -> the new pointer's bytes
	mov	bx,offset new_addr
	mov	ax,[new_n]
	mov	dx,[new_rows]
	call	pu_blit
pu4:	test	[upd_ops],UPD_ERASE
	jz	pu8
	mov	si,offset ers_buf	; SI -> old pointer's restored bytes
	mov	bx,offset old_addr
	mov	ax,[old_n]
	mov	dx,[old_rows]
	call	pu_blit

pu8:	pop	dx
	pop	cx
	mov	al,UPD_DRAW
	and	al,[upd_ops]
	mov	[drawn],al		; drawn if UPD_DRAW (or else erased)
	jz	pu9
	mov	[old_x],cx
	mov	[old_y],dx
	mov	ax,[new_buf]
	mov	[old_buf],ax
	push	ds
	pop	es
	mov	si,offset new_xb	; copy new_xb, new_n, new_rows, and
	mov	di,offset old_xb	; new_addr to old_xb, old_n, old_rows,
	mov	cx,SHAPE_ROWS + 3	; and old_addr
	rep	movsw
pu9:	ret
ENDPROC	ptr_update

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pu_erase
;
; Computes the old pointer's restored bytes (in ers_buf), restoring only the
; bits that the pointer changed and that still have the pointer's values.
;
; Inputs:
;	DS = CS, ES = video memory
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	pu_erase
	mov	si,[old_buf]
	mov	bp,offset ers_buf
	mov	bx,offset old_addr
	mov	dl,byte ptr [old_rows]
pe1:	dec	dl
	js	pe4
	mov	di,[bx]
	mov	cx,[old_n]
	push	si
	push	bp
pe2:	mov	al,es:[di]		; AL = current byte (C)
	mov	ah,[si+SAVE_LEN]	; AH = drawn byte (D)
	mov	dh,ah
	xor	ah,al
	not	ah			; AH = bits where C equals D
	xor	dh,[si]			; DH = bits the pointer changed
	and	ah,dh
	xor	al,ah			; restore them
	mov	ds:[bp],al
	inc	si
	inc	di
	inc	bp
	loop	pe2
	pop	bp
	pop	si
	add	si,ROW_BYTES
	add	bp,ROW_BYTES
	inc	bx
	inc	bx
	jmp	pe1
pe4:	ret
ENDPROC	pu_erase

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pu_draw
;
; Computes the new pointer's bytes, saving the bytes underneath (S) and the
; bytes to draw (D) in new_buf, along with the address of each row.  Where the
; new pointer overlaps the old one (if it's being erased), the bytes underneath
; are the old pointer's restored bytes in ers_buf, which are then replaced with
; the new pointer's bytes, so that pu_blit can copy ers_buf after new_buf.
;
; Inputs:
;	CX = x, DX = y (pixels)
;	DS = CS, ES = video memory
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	pu_draw
	mov	[pd_y],dx
	mov	bl,cl			; BL = pixel shift, CX = byte offset
	cmp	[vid_type],VT_CGA1
	je	pd1
	and	bl,3			; 2 bits per pixel
	shl	bl,1
	shr	cx,1
	jmp	short pd2
pd1:	and	bl,7			; 1 bit per pixel
	shr	cx,1
	shr	cx,1
pd2:	shr	cx,1
	mov	[pr_sh],bl
	mov	[new_xb],cx
	mov	ax,cx
	sub	ax,[old_xb]
	mov	[pd_c0],ax		; old pointer's column of the 1st byte
	mov	ax,80
	sub	ax,cx
	cmp	ax,ROW_BYTES		; how many bytes are on the screen?
	jbe	pd3
	mov	ax,ROW_BYTES
pd3:	mov	[new_n],ax
	mov	ax,200
	sub	ax,dx
	cmp	ax,SHAPE_ROWS		; how many rows are on the screen?
	jbe	pd4
	mov	ax,SHAPE_ROWS
pd4:	mov	[new_rows],ax
	mov	[pd_r],0

pd5:	mov	bx,[pd_r]
	cmp	bx,[new_rows]
	jb	pd5a
	ret
pd5a:	mov	si,bx
	add	si,si
	add	si,bx
	add	si,[new_buf]		; SI -> new_buf for the row
	add	bx,bx
	push	bx
	add	bx,offset SHAPE
	call	pr_mask			; build the row's masks
	pop	bx
	mov	dx,[pd_y]
	add	dx,[pd_r]		; DX = screen row
	mov	ax,dx
	shr	ax,1
	mov	cl,80
	mul	cl
	test	dl,1			; odd row?
	jz	pd6			; no
	add	ah,20h			; yes, so add 2000h
pd6:	add	ax,[new_xb]
	mov	new_addr[bx],ax
	xchg	di,ax			; DI -> 1st byte
	mov	bp,-1			; BP = -1 if no overlap
	test	[upd_ops],UPD_ERASE
	jz	pd7
	sub	dx,[old_y]		; DX = old pointer's row
	cmp	dx,[old_rows]
	jae	pd7
	mov	bp,dx
	add	bp,bp
	add	bp,dx
	add	bp,[pd_c0]		; BP = ers_buf index of the 1st byte
pd7:	mov	cx,[new_n]
	sub	bx,bx
pd8:	mov	al,es:[di]		; AL = byte underneath (S)
	cmp	bp,-1
	je	pd8a
	mov	dx,bx
	add	dx,[pd_c0]
	cmp	dx,[old_n]		; overlapping the old pointer?
	jae	pd8a			; no
	mov	dx,bp
	add	dx,bx
	xchg	bx,dx			; BX = ers_buf index
	mov	al,ers_buf[bx]		; S is the old pointer's restored byte
	xchg	bx,dx
	call	pd_byte
	xchg	bx,dx
	mov	ers_buf[bx],al		; and D replaces it
	xchg	bx,dx
	jmp	short pd8b
pd8a:	call	pd_byte
pd8b:	inc	si
	inc	di
	inc	bx
	loop	pd8
	inc	[pd_r]
	jmp	pd5
;
; Save S, and compute and save D (in AL).
;
pd_byte:
	mov	[si],al
	mov	ah,row_mask[bx]
	not	ah
	and	al,ah
	xor	al,row_mask[bx+ROW_BYTES]
	mov	[si+SAVE_LEN],al
	ret
ENDPROC	pu_draw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pu_blit
;
; Copies computed pointer bytes to the screen, as quickly as possible.
;
; Inputs:
;	AX = bytes per row
;	DX = rows
;	DS:BX -> row addresses
;	DS:SI -> bytes (ROW_BYTES per row)
;	ES = video memory
;
; Modifies:
;	BX, CX, DX, SI, DI
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	pu_blit
	test	dx,dx
	jz	bl9
bl1:	mov	di,[bx]
	mov	cx,ax
	rep	movsb
	sub	si,ax
	add	si,ROW_BYTES
	inc	bx
	inc	bx
	dec	dx
	jnz	bl1
bl9:	ret
ENDPROC	pu_blit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pu_text
;
; Erases or draws the pointer in a text mode, by inverting the attribute of
; a character cell (the character itself is never changed).  Drawing saves
; the inverted attribute (D), and erasing restores only the bits that still
; have the pointer's values.  On a CGA, we wait for a retrace before reading
; or writing video memory, to avoid "snow".
;
; Inputs:
;	CX = column, DX = row
;	SI -> sav_buf half
;	BP = 1 to draw, 0 to erase
;
; Modifies:
;	AX, BX, CX, DX, DI
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	pu_text
	mov	ax,1280
	mov	bx,cx
	mov	cl,[vid_shift]
	shr	ax,cl			; AX = 160 or 80 bytes per row
	mul	dx
	add	ax,bx
	add	ax,bx
	inc	ax
	xchg	di,ax			; DI -> attribute of the cell
	call	snow_wait
	mov	al,es:[di]		; AL = current attribute (C)
	test	bp,bp			; drawing?
	jz	pt1			; no
	xor	al,77h			; yes, invert it
	mov	[si+SAVE_LEN],al	; and save it (D)
	jmp	short pt2
pt1:	mov	ah,[si+SAVE_LEN]	; AH = D
	xor	ah,al
	not	ah			; AH = bits where C equals D
	and	ah,77h			; that the pointer inverted
	xor	al,ah			; restore them
pt2:	call	snow_wait
	stosb
	ret
ENDPROC	pu_text

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; snow_wait
;
; On a CGA, waits for the start of a horizontal retrace (unless a vertical
; retrace is in progress), when video memory can be accessed without "snow".
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	snow_wait
	cmp	byte ptr [vid_seg+1],0B8h
	jne	sw9			; not a CGA
	push	ax
	push	dx
	mov	dx,3DAh			; DX -> CGA status register
	in	al,dx
	test	al,08h			; vertical retrace?
	jnz	sw8			; yes, so there's plenty of time
sw1:	in	al,dx
	test	al,01h			; wait for the display to be enabled
	jnz	sw1
sw2:	in	al,dx
	test	al,01h			; and then for a horizontal retrace
	jz	sw2
sw8:	pop	dx
	pop	ax
sw9:	ret
ENDPROC	snow_wait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pr_mask
;
; Builds row_mask from a row of SHAPE, shifted into position (in modes 4 and
; 5, each bit of the shape becomes two bits).
;
; Inputs:
;	DS:BX -> SHAPE row
;
; Modifies:
;	AX, DX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	pr_mask
	push	cx
	push	di
	mov	di,offset row_mask
	mov	al,[bx]
	call	pm1
	mov	al,[bx+1]
	call	pm1
	pop	di
	pop	cx
	ret
pm1:	mov	ah,al
	mov	al,0
	cmp	[vid_type],VT_CGA1
	je	pm3
	mov	dl,ah
	mov	cx,8
pm2:	shl	dl,1			; double each bit
	sbb	dh,dh
	shl	dh,1
	rcl	ax,1
	shl	dh,1
	rcl	ax,1
	loop	pm2
pm3:	mov	cl,[pr_sh]
	mov	ch,0
	mov	dl,ch
	jcxz	pm5
pm4:	shr	ax,1
	rcr	dl,1
	loop	pm4
pm5:	xchg	al,ah
	mov	[di],ax
	mov	[di+2],dl
	add	di,ROW_BYTES
	ret
ENDPROC	pr_mask

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clamp
;
; Inputs:
;	DS:SI -> value, minimum, and maximum
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	clamp
	lodsw
	cmp	ax,[si]
	jge	cl1
	mov	ax,[si]
cl1:	cmp	ax,[si+2]
	jle	cl2
	mov	ax,[si+2]
cl2:	mov	[si-2],ax
	ret
ENDPROC	clamp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_pos and get_scr
;
; get_pos returns the current position in screen units: a column and row
; (starting at 0) in text modes, or pixels in graphics modes; get_scr converts
; the virtual position in CX, DX to screen units.
;
; Outputs:
;	CX, DX = position
;
; Modifies:
;	CX, DX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	get_pos
	mov	cx,[cur_x]
	mov	dx,[cur_y2]
	shr	dx,1
	DEFLBL	get_scr,near
	push	ax
	mov	al,[vid_type]
	cmp	al,VT_TEXT
	jne	gs2
	xchg	ax,cx
	mov	cl,[vid_shift]
	shr	ax,cl			; AX = column
	mov	cl,3
	shr	dx,cl			; DX = row
	xchg	cx,ax
	jmp	short gs9
gs2:	cmp	al,VT_CGA2
	jne	gs9
	shr	cx,1
gs9:	pop	ax
	ret
ENDPROC	get_pos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_mode
;
; Determines the video mode (using INT 10h function 0Fh, which the CON
; driver answers for the caller's session), and the corresponding pointer
; type, video memory segment, and text column width.
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	get_mode
	push	ax
	push	bx
	push	dx
	push	bp			; some BIOS functions trash BP
	mov	ah,0Fh
	pushf
	call	[int10_ptr]		; AL = mode, AH = columns
	pop	bp
	mov	dx,0B800h
	mov	bl,VT_TEXT
	cmp	al,7			; MDA?
	jne	gm1			; no
	mov	dh,0B0h
	jmp	short gm3
gm1:	cmp	al,4			; text mode?
	jb	gm3			; yes
	inc	bx			; BL = VT_CGA2
	cmp	al,6
	jb	gm3
	je	gm2
	mov	bl,VT_NONE - 1		; unsupported mode
gm2:	inc	bx
gm3:	mov	[vid_type],bl
	mov	[vid_seg],dx
	mov	al,3			; 8 virtual pixels per column
	cmp	ah,40			; 40 columns?
	ja	gm4			; no
	inc	ax			; 16 virtual pixels per column
gm4:	mov	[vid_shift],al
	pop	dx
	pop	bx
	pop	ax
	ret
ENDPROC	get_mode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Looks for a serial mouse on each COM port, and if one responds, installs
; the hardware interrupt, INT 33h, and INT 10h handlers; otherwise, DDPI_END
; remains zero, so the driver isn't installed.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddmou_init,far
	push	bx
	push	es
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	sti
	mov	si,offset RS232_BASE
	mov	cx,4
in1:	lods	word ptr [si]
	xchg	dx,ax			; DX = port, if any
	test	dx,dx
	jz	in2
	call	probe			; is there a mouse on this port?
	jnc	in3			; yes
in2:	loop	in1
	jmp	short in9		; no mouse, so DDPI_END stays zero

in3:	mov	cs:[port_base],dx
	mov	bx,(0EFh SHL 8) OR (INT_HW_COM1 * 4)
	cmp	dh,03h			; COM1 or COM3 (IRQ4)?
	je	in4			; yes
	mov	bx,(0F7h SHL 8) OR (INT_HW_COM2 * 4)
in4:	cli
	mov	di,bx
	and	di,00FFh
	mov	[di].OFF,offset ddmou_irq
	mov	[di].SEG,cs
	mov	ds:[INT_MOUSE * 4].OFF,offset ddmou_int33
	mov	ds:[INT_MOUSE * 4].SEG,cs
	mov	ax,offset ddmou_int10
	xchg	ds:[INT_VIDEO * 4].OFF,ax
	mov	cs:[int10_ptr].OFF,ax
	mov	ax,cs
	xchg	ds:[INT_VIDEO * 4].SEG,ax
	mov	cs:[int10_ptr].SEG,ax
	inc	dx			; DX -> IER
	mov	al,01h			; enable RBR (data received) interrupts
	out	dx,al
	sub	dx,1
	in	al,dx			; discard any data
	in	al,21h
	and	al,bh			; unmask the IRQ
	out	21h,al
	sti
	push	cs
	pop	ds
	ASSUME	DS:CODE
	call	get_mode
	pop	es
	pop	bx
	mov	es:[bx].DDPI_END.OFF,offset ddmou_init
	mov	cs:[0].DDH_REQUEST,offset DEV:ddmou_req
	ret

in9:	pop	es
	pop	bx
	ret
ENDPROC	ddmou_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; probe
;
; Resets the device on a COM port the way a Microsoft serial mouse expects
; (DTR and RTS are turned off and then on again), and waits for the mouse to
; identify itself with an "M".  If there's no mouse, the port's settings are
; restored.
;
; Inputs:
;	DX = port
;	DS = BIOS
;
; Outputs:
;	Carry clear if a mouse was found (port set to 1200 baud, 7N1)
;
; Modifies:
;	AX, BX, DI
;
	ASSUME	CS:CODE, DS:BIOS, ES:NOTHING, SS:NOTHING
DEFPROC	probe
	push	cx
	add	dx,3			; DX -> LCR
	in	al,dx
	push	ax			; save LCR
	mov	al,80h			; set DLAB
	out	dx,al
	sub	dx,3			; DX -> DLL
	in	al,dx
	mov	bl,al
	inc	dx
	in	al,dx
	mov	bh,al
	push	bx			; save the divisor
	mov	al,0
	out	dx,al
	dec	dx
	mov	al,96			; 115200 / 96 = 1200 baud
	out	dx,al
	add	dx,3
	mov	al,02h			; 7 data bits, no parity, 1 stop bit
	out	dx,al
	inc	dx			; DX -> MCR
	in	al,dx
	push	ax			; save MCR
	mov	al,0			; turn off DTR and RTS
	out	dx,al
	mov	bl,2
	call	wait_ticks		; for the mouse to reset
	sub	dx,4
	in	al,dx			; discard any data
	add	dx,4
	mov	al,0Bh			; turn on DTR, RTS, and OUT2
	out	dx,al
	inc	dx			; DX -> LSR
	mov	bl,3
	call	wait_ticks		; for the mouse to respond
	jc	pb8			; no response
	sub	dx,5
	in	al,dx			; AL = response
	add	dx,5
	cmp	al,'M'			; Microsoft mouse?
	jne	pb8			; no
	sub	dx,5
	add	sp,6			; discard the saved settings
	jmp	short pb9		; (carry is clear)

pb8:	dec	dx			; DX -> MCR
	pop	ax
	out	dx,al			; restore MCR
	dec	dx			; DX -> LCR
	mov	al,80h
	out	dx,al
	sub	dx,3
	pop	ax
	out	dx,al			; restore DLL
	inc	dx
	mov	al,ah
	out	dx,al			; restore DLM
	add	dx,2
	pop	ax
	out	dx,al			; restore LCR
	sub	dx,3
	stc
pb9:	pop	cx
	ret
ENDPROC	probe

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; wait_ticks
;
; Waits for BL timer ticks, or for data, if DX -> LSR.
;
; Inputs:
;	BL = ticks
;	DX = port
;	DS = BIOS
;
; Outputs:
;	Carry clear if data is ready (DX -> LSR), set if not
;
; Modifies:
;	AX, BX, CX
;
	ASSUME	CS:CODE, DS:BIOS, ES:NOTHING, SS:NOTHING
DEFPROC	wait_ticks
	mov	bh,byte ptr [TIMER_LOW]
	sub	cx,cx			; CX = maximum iterations
wt1:	in	al,dx
	test	dl,1			; LSR (an odd port)?
	jz	wt2			; no
	test	al,01h			; data ready?
	jnz	wt9			; yes (and carry is clear)
wt2:	cmp	bh,byte ptr [TIMER_LOW]
	je	wt3
	mov	bh,byte ptr [TIMER_LOW]
	dec	bl
	jz	wt8
wt3:	loop	wt1
wt8:	stc
wt9:	ret
ENDPROC	wait_ticks

CODE	ends

DATA	segment para public 'DATA'

ddmou_end	db	16 dup(0)

DATA	ends

	end
