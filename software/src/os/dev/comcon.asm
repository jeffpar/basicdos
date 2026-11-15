;
; BASIC-DOS Physical (COM) Serial Device Driver: Consoles
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The code for a port with more than one console, which is linked after
; comdev.asm (so it's part of COM1's driver, whose code every port uses).
;
	CLKTIMER equ 1
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc
	include	comdev.inc

DEV	group	CODE

CODE	segment para public 'CODE'

	EXTNEAR	<end_esc,wake_packet,resume_output,output_room,ioctl_str>
	EXTNEAR	<csi_pair,sgr_out,write_context>
	EXTWORD	<ct_seg>
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; alloc_sys
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
; free_ctx
;
; Frees a context and its shadows.  CPU$ reloads DS and ES, so neither can
; hold a block that's being freed.
;
; Inputs:
;	BP = the port's data segment
;	DS = context
;
; Outputs:
;	DS and ES = the port's data segment
;
; Modifies:
;	AX, CX, DX, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	free_ctx
	mov	es,bp
	mov	cx,ds:[CT_ATTRS]
	call	free_buf
	mov	cx,ds:[CT_SHADOW]
	call	free_buf
	mov	cx,ds
	mov	ds,bp
	DEFLBL	free_buf,near		; CX = segment, if any
	jcxz	fb9
	mov	dx,-1			; DX = -1 means CX is a segment
	mov	ah,CPU_FREE
	call	far ptr DDINT_CPU
fb9:	ret
ENDPROC	free_ctx

;
; Everything from here on is for a port with more than one console, which a
; machine with 64K or less can't have, so COM1 doesn't keep it there (see
; ddcom_init); comdev.asm calls it only for a context that has a shadow.
;
	DEFLBL	con_opt,near
;
; A port can have several consoles (see ddcom_open), each with its own context
; and a "shadow" of its screen: SHADOW_LEN characters, in a block of their own
; (and another of attributes, once a color is set; see set_color), which every
; write updates.  Only the console with focus (ct_seg) uses the terminal;
; the hotkey gives the focus to the next one, whose screen is then repainted
; from its shadow (see switch_to and paint).  The first context that a port is
; opened with gets a shadow only if SHADOW_MIN bytes of memory are free, and
; without one, the port can't have other consoles.
;
SHADOW_LEN	equ	TERM_COLS * TERM_ROWS
SHADOW_MIN	equ	1	; minimum free memory, in 64K units
PAINT_ROOM	equ	48	; the most output that one paint step adds

;
; CT_PAINT's parts.
;
CT_PCOL		equ	CT_PAINT	; next column to repaint
CT_PROW		equ	CT_PAINT+1	; next row to repaint (-1 before any)
CT_PLEN		equ	CT_PAINT+2	; # of columns to repaint on that row
CT_PATTR	equ	CT_PAINT+3	; the terminal's attributes meanwhile
;
; What a repaint starts with (see paint): CAN ends any sequence that was cut
; short, SI selects G0, and then the default attributes, no scrolling rows,
; and an empty screen.
;
	DEFLBL	PAINT_INIT,byte
	db	CHR_CTRLX,VT100_SI,CHR_ESCAPE,"[m"
	db	CHR_ESCAPE,"[r",CHR_ESCAPE,"[2J",0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; alloc_plane
;
; Allocates a shadow of the screen (SHADOW_LEN bytes), filled with AL.
;
; Inputs:
;	AL = fill byte (eg, CHR_SPACE)
;
; Outputs:
;	Carry clear if successful, AX = segment (or selector)
;
; Modifies:
;	AX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	alloc_plane
	push	cx
	push	di
	push	es
	push	ax
	mov	di,SHADOW_LEN
	call	alloc_sys		; AX = segment
	pop	cx			; CL = fill byte
	jc	alp9
	mov	es,ax
	xchg	ax,cx			; AL = fill byte, CX = segment
	push	cx
	sub	di,di
	mov	cx,SHADOW_LEN
	rep	stosb
	pop	ax			; (carry is still clear)
alp9:	pop	es
	pop	di
	pop	cx
	ret
ENDPROC	alloc_plane

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_cell
;
; Inputs:
;	CL = column, CH = row
;
; Outputs:
;	BX = offset of that cell in a shadow
;
; Modifies:
;	AX, BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_cell
	mov	al,TERM_COLS
	mul	ch			; AX = row * TERM_COLS
	mov	bl,cl
	mov	bh,0
	add	bx,ax
	ret
ENDPROC	get_cell

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; shadow_put
;
; Stores a character (and the current attributes) in the context's shadows
; (see put_shadow), at the current row.  The column isn't reset when a line wraps (see
; put_col), so it's reduced to a column on the row.
;
; Inputs:
;	AH = character
;	BX = column
;	ES = context
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	shadow_put
	push	ax
	push	bx
	push	cx
	push	ds
	push	ax
	mov	cl,bl
shp1:	sub	cl,TERM_COLS
	jae	shp1
	add	cl,TERM_COLS		; CL = column on the row
	mov	ch,es:[CT_ROW]
	call	get_cell		; BX = cell
	pop	ax			; AH = character
	mov	ds,es:[CT_SHADOW]
	mov	[bx],ah
	mov	cx,es:[CT_ATTRS]
	jcxz	shp8
	mov	ds,cx
	mov	al,byte ptr es:[CT_COLOR]
	mov	[bx],al
shp8:	pop	ds
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	shadow_put

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; shadow_erase
;
; Erases the context's shadows, if any, from a column of one row through the
; end of another.
;
; Inputs:
;	CL = column, CH = row
;	AL = last row
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	shadow_erase
	push	ax
	push	bx
	push	cx
	push	di
	inc	ax
	mov	ah,TERM_COLS
	mul	ah			; AX = the cell after the last one
	xchg	di,ax
	call	get_cell		; BX = first cell
	sub	di,bx
	mov	cx,di			; CX = # of cells
	mov	di,bx
	call	shadow_fill
	pop	di
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	shadow_erase

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; shadow_fill
;
; Fills cells of the context's shadows, if any, with spaces (and the default
; attributes, which is what an erased cell has).
;
; Inputs:
;	DI = first cell
;	CX = # of cells
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	shadow_fill
	push	es
	mov	bx,offset CT_SHADOW
	mov	al,CHR_SPACE
shf1:	cmp	word ptr [bx],0		; is there a shadow?
	je	shf2			; no
	mov	es,[bx]
	push	cx
	push	di
	rep	stosb
	pop	di
	pop	cx
shf2:	inc	bx
	inc	bx			; BX -> CT_ATTRS
	ASSERT	<CT_ATTRS>,EQ,<CT_SHADOW + 2>
	xor	al,CHR_SPACE XOR 07h	; AL = 07h (and then a space again)
	cmp	al,CHR_SPACE
	jne	shf1
	pop	es
	ret
ENDPROC	shadow_fill

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; shadow_scroll
;
; Scrolls the scrolling rows of the context's shadows, if any, by one row: up
; if the sign flag is clear, down if it's set.
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	None (flags are preserved, too)
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	shadow_scroll
	pushf
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es
	lahf
	mov	dh,ah			; DH = flags
	mov	cx,word ptr ds:[CT_TOP]	; CL = first row, CH = last row
	mov	al,ch
	sub	al,cl
	mov	ah,TERM_COLS
	mul	ah
	xchg	si,ax			; SI = # of cells to move
	mov	ch,cl
	mov	cl,0
	call	get_cell
	mov	di,bx			; DI -> first row
	mov	cx,si
	lea	si,[di+TERM_COLS]	; SI -> second row
	test	dh,dh			; scrolling up?
	js	shs1			; no
	add	bx,cx			; BX -> last row (the one to erase)
	jmp	short shs2
shs1:	lea	si,[di-1]
	add	si,cx			; SI -> end of the next-to-last row
	lea	di,[si+TERM_COLS]	; DI -> end of the last row
	std
shs2:	mov	ax,ds:[CT_SHADOW]
	call	shs3
	mov	ax,ds:[CT_ATTRS]
	call	shs3
	cld
	mov	di,bx
	mov	cx,TERM_COLS
	call	shadow_fill
	pop	es
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	popf
	ret
shs3:	test	ax,ax			; is there a shadow?
	jz	shs9			; no
	push	cx
	push	si
	push	di
	push	ds
	mov	es,ax
	mov	ds,ax
	rep	movsb
	pop	ds
	pop	di
	pop	si
	pop	cx
shs9:	ret
ENDPROC	shadow_scroll

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; switch_to
;
; Gives the focus to another of the port's consoles, unless either one is in
; the middle of an IOCTL, in which case that waits until the IOCTL ends (see
; ddcom_ioctl); switch_now doesn't wait (see ddcom_close).
;
; The console losing the focus keeps running: its output just goes no further
; than its shadow (see push_output), which already has whatever is still in
; its output buffer, so that's discarded, and its writers stop waiting.  The
; terminal's flow control state moves to the console getting the focus, which
; is then repainted (see paint).
;
; Inputs:
;	CX = context with focus
;	BX = context to switch to
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	switch_to
	mov	es,cx
	mov	es:[CT_PEND],bx
	mov	al,es:[CT_BUSY]
	mov	es,bx
	or	al,es:[CT_BUSY]		; is either one busy?
	jnz	swt9			; yes
	DEFLBL	switch_now,near
	push	ds
	mov	ds,cx
	mov	es,bx
	cli
	mov	ds:[CT_PEND],0
	call	end_esc
	mov	ax,ds:[CT_OUTPUT].BUFTAIL
	mov	ds:[CT_OUTPUT].BUFHEAD,ax
	mov	al,CTSTAT_PAUSED OR CTSTAT_CTSOFF
	and	al,ds:[CT_STATUS]	; AL = flow control state
	and	ds:[CT_STATUS],CTSTAT_KEEP
	inc	ds:[CT_BACK]
	or	al,CTSTAT_PAINT
	or	es:[CT_STATUS],al
	mov	es:[CT_BACK],0
	mov	word ptr es:[CT_PCOL],0FF00h	; (CT_PROW = -1)
	ASSERT	<CT_PROW>,EQ,<CT_PCOL + 1>
	mov	es,ds:[CT_DRV]
	ASSUME	ES:CODE
	mov	es:[ct_seg],bx
	ASSUME	ES:NOTHING
	sti
swt1:	push	bx
	call	wake_packet		; end the wait of each of its writers
	pop	bx
	jc	swt1
	mov	ds,bx
	call	resume_output		; start painting
	pop	ds
swt9:	ret
ENDPROC	switch_to

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; paint
;
; Repaints the screen of a console that just got the focus, from its shadows,
; a step at a time: called (by pull_output) whenever the output buffer is
; empty, we add steps while there's room for another (PAINT_ROOM), until the
; last one clears CTSTAT_PAINT.  The steps are PAINT_INIT, then every row
; that isn't blank (its position, and then one character per step, with the
; attributes if they change), and finally the scrolling rows, the cursor's
; position, and the current attributes.  Writes and IOCTLs wait until then.
;
; A row is repainted through its last cell that isn't a space with the default
; attributes.  A cursor that was waiting to wrap (after a character in the
; last column) is put back there by writing that character again.
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	paint
	push	cx
	push	di
	push	es
	cld
pnt1:	call	output_room
	cmp	ax,PAINT_ROOM
	jae	pnt1a
	jmp	pnt9
pnt1a:	mov	cx,word ptr ds:[CT_PCOL]	; CL = column, CH = row
	test	ch,ch			; started yet?
	jns	pnt2			; yes
	mov	si,offset PAINT_INIT
	call	ioctl_str
	mov	ds:[CT_GFX],VT100_SI
	mov	byte ptr ds:[CT_PATTR],07h
	jmp	short pnt3
pnt2:	cmp	cl,ds:[CT_PLEN]		; anything left on this row?
	jb	pnt6			; yes
;
; On to the next row: find its length, and if it isn't blank, move to it.
;
pnt3:	inc	ch
	cmp	ch,TERM_ROWS
	jae	pnt7
	mov	cl,TERM_COLS-1
	call	get_cell		; BX -> the row's last cell
	mov	cl,0
	mov	dx,cx			; DL = length (so far)
	mov	si,offset CT_SHADOW
	mov	al,CHR_SPACE
pnt4:	cmp	word ptr [si],0		; is there a shadow?
	je	pnt5			; no
	mov	es,[si]
	mov	di,bx
	mov	cx,TERM_COLS
	std
	repe	scasb
	cld
	je	pnt5			; the whole row matched
	inc	cx			; CX = length
	cmp	cl,dl
	jbe	pnt5
	mov	dl,cl
pnt5:	inc	si
	inc	si			; SI -> CT_ATTRS
	xor	al,CHR_SPACE XOR 07h	; AL = 07h (and then a space again)
	cmp	al,CHR_SPACE
	jne	pnt4
	mov	ds:[CT_PLEN],dl
	mov	cx,dx
	mov	cl,0			; CL = column, CH = row
	test	dl,dl			; a blank row?
	jz	pnt8			; yes
	mov	al,'H'
	call	csi_pair
	jmp	short pnt8
;
; Write the next character of the row.
;
pnt6:	call	paint_cell
	inc	cx
pnt8:	mov	word ptr ds:[CT_PCOL],cx
	jmp	pnt1
;
; The last step.
;
pnt7:	mov	cx,word ptr ds:[CT_TOP]	; CL = first row, CH = last row
	cmp	cx,(TERM_ROWS-1) SHL 8	; all of them?
	je	pnt7a			; yes
	xchg	cl,ch
	mov	al,'r'
	call	csi_pair		; ESC [ first ; last r
pnt7a:	mov	al,ds:[CT_COL]
	mov	ah,0
	mov	cl,TERM_COLS
	div	cl			; AH = column on the row
	mov	ch,ds:[CT_ROW]
	mov	cl,ah
	sub	di,di
	test	ah,ah			; at the left edge?
	jnz	pnt7b			; no
	test	al,al			; of a line's first row?
	jz	pnt7b			; yes
	mov	cl,TERM_COLS-1		; no, the cursor was waiting to wrap
	inc	di
pnt7b:	mov	al,'H'
	call	csi_pair
	dec	di
	jnz	pnt7c
	call	paint_cell
pnt7c:	mov	cl,byte ptr ds:[CT_COLOR]
	cmp	cl,ds:[CT_PATTR]
	je	pnt7d
	call	sgr_out
pnt7d:	and	ds:[CT_STATUS],NOT CTSTAT_PAINT
pnt9:	pop	es
	pop	di
	pop	cx
	ret
ENDPROC	paint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; paint_cell
;
; Inputs:
;	CL = column, CH = row
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX, SI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	paint_cell
	call	get_cell		; BX = cell
	mov	ax,ds:[CT_ATTRS]
	test	ax,ax			; any attributes?
	jz	pcl1			; no
	mov	es,ax
	mov	al,es:[bx]
	cmp	al,ds:[CT_PATTR]	; the same as the terminal's?
	je	pcl1			; yes
	mov	ds:[CT_PATTR],al
	push	bx
	push	cx
	xchg	cx,ax			; CL = attributes
	call	sgr_out
	pop	cx
	pop	bx
pcl1:	mov	es,ds:[CT_SHADOW]
	mov	al,es:[bx]
	push	ds
	pop	es
	jmp	write_context
ENDPROC	paint_cell

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_shadow
;
; Gives a port's first context a shadow, so that the port can have other
; consoles, if the terminal can be repainted, its output buffer has room for
; a paint step, and there's memory to spare (see SHADOW_MIN).
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_shadow
	cmp	ds:[CT_TERM],TERM_GENERIC
	je	gsh9
	mov	ax,ds:[CT_OUTPUT].BUFEND
	sub	ax,ds:[CT_OUTPUT].BUFOFF
	cmp	ax,PAINT_ROOM * 2	; is the output buffer too small?
	jb	gsh9			; yes
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU	; DX:CX = free memory
	jc	gsh9
	cmp	dx,SHADOW_MIN		; is there enough?
	jb	gsh9			; no
	mov	al,CHR_SPACE
	call	alloc_plane		; AX = shadow
	jc	gsh9
	mov	ds:[CT_SHADOW],ax
gsh9:	ret
ENDPROC	get_shadow

CODE	ends

	end
