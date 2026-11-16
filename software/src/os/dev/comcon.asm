;
; BASIC-DOS Physical (COM) Serial Device Driver: Consoles
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The code for a port with more than one console (and some of comdev.asm's,
; which has no room for more symbols), which is linked after comdev.asm (so
; it's part of COM1's driver, whose code every port uses).
;
	BIOSKEY equ 1
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
	EXTNEAR	<csi_pair,csi_out,write_cell,wide_reset,wide_row,ioctl_out>
	EXTNEAR	<ioctl_fault,clear_screen,ddcom_none,set_pos,scroll_shadow>
	EXTNEAR	<esc_timer,push_buffer>
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

ESC_MS		equ	110	; how long to hold an ESC (raw keys)

	DEFLBL	ANSI_RINDEX,byte
	db	CHR_ESCAPE,"M",0	; reverse index (scrolls down at the top)
	DEFLBL	ANSI_RESET,byte
	db	CHR_ESCAPE,"[0",0	; start of "select graphic rendition"
	DEFLBL	ANSI_COLORS,byte	; PC color # to ANSI color #
	db	0,4,2,6,1,5,3,7		; (ie, swap the red and blue bits)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_len
;
; Inputs:
;	CL = number of bytes
;	DL = starting column
;	ES:DI -> DDPRW (DDPRW_ADDR -> bytes)
;
; Outputs:
;	DH = total display length, DL = length delta (of the final character)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_len
	mov	bl,dl			; BL = current column
	sub	dx,dx			; DL = current len, DH = previous len
	mov	ch,0
	jcxz	gl9
	push	ds
	lds	si,es:[di].DDPRW_ADDR
gl1:	lodsb
	mov	dh,dl			; current len -> previous len
	mov	ah,1			; AH = # display columns
	cmp	al,CHR_TAB
	jne	gl2
	mov	ah,bl			; TAB advances to the next multiple of 8
	and	ah,07h
	neg	ah
	add	ah,8
	jmp	short gl3
gl2:	cmp	al,CHR_SPACE		; CONTROL character?
	jae	gl3			; no
	inc	ah			; yes, add 1 for the presumed "^"
gl3:	add	bl,ah			; advance the column
	add	dl,ah			; advance the length
	loop	gl1
	pop	ds
	sub	dl,dh			; DL = length delta for final character
	add	dh,dl			; DH = total length
gl9:	ret
ENDPROC	get_len

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_color
;
; Records the new attributes, and for ANSI terminals, sends the corresponding
; "select graphic rendition" sequence for the fill attributes (ie, foreground
; color in bits 0-2, intensity in bit 3, background color in bits 4-6, and
; blink in bit 7).  The default attributes (07h) simply reset the terminal to
; its own defaults.  The border attributes are ignored.
;
; A VT100 has no colors, so it gets the attributes that an MDA displays for
; them instead: black on white is reverse video, and a "blue" foreground is
; underlined.  Without its Advanced Video Option, a VT100 has only one of
; those (whichever its SET-UP cursor selects), and neither bold nor blink.
;
; Inputs:
;	CL = fill attributes
;	CH = border attributes
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if interrupted (DDP_STATUS updated)
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_color
	mov	ds:[CT_COLOR],cx
;
; The first color that isn't the default gives a console with a shadow a
; second one, for attributes (if there's no memory for it, a repaint just
; won't have any).
;
	cmp	cl,07h			; default attributes?
	je	sgr_out			; yes
	cmp	ds:[CT_SHADOW],0	; is there a shadow?
	je	sgr_out			; no
	cmp	ds:[CT_ATTRS],0		; with attributes already?
	jne	sgr_out			; yes
	mov	al,07h
	call	alloc_plane		; AX = segment
	jc	sgr_out
	mov	ds:[CT_ATTRS],ax
	DEFLBL	sgr_out,near		; (CL = attributes; see paint)
	cmp	ds:[CT_TERM],TERM_GENERIC
	je	stc9			; nothing to send (carry clear)
	mov	si,offset ANSI_RESET
	call	ioctl_str		; ESC [ 0
	jc	stc8
	cmp	ds:[CT_TERM],TERM_VT100
	je	stc2
	cmp	cl,07h			; default attributes?
	je	stc7			; yes, so the reset is all we need
	mov	ah,'3'			; foreground color
	mov	al,cl
	call	ansi_color
	jc	stc8
	mov	ah,'4'			; background color
	mov	al,cl
	shr	al,1
	shr	al,1
	shr	al,1
	shr	al,1
	call	ansi_color
	jmp	short stc4

stc2:	mov	ah,cl
	and	ah,77h			; AH = colors
	cmp	ah,70h			; black on white?
	jne	stc3			; no
	mov	al,'7'			; reverse video
	call	sgr_parm
	jc	stc8
stc3:	and	ah,07h
	dec	ah			; "blue" foreground?
	jnz	stc5			; no
	mov	al,'4'			; underline
	call	sgr_parm
stc4:	jc	stc8
stc5:	test	cl,08h			; intensity bit set?
	jz	stc6			; no
	mov	al,'1'			; bold (aka bright)
	call	sgr_parm
	jc	stc8
stc6:	test	cl,cl			; blink bit set?
	jns	stc7			; no
	mov	al,'5'			; blink
	call	sgr_parm
	jc	stc8
stc7:	mov	al,'m'
	call	ioctl_out
	jc	stc8
stc9:	ret
stc8:	jmp	ioctl_fault
ENDPROC	set_color

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ansi_color
;
; Sends ";" followed by the prefix and the ANSI color # for a PC color #.
;
; Inputs:
;	AH = prefix ('3' for foreground, '4' for background)
;	AL = PC color # (in bits 0-2)
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if the wait was interrupted
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ansi_color
	and	al,07h
	mov	bl,al
	mov	bh,0
	mov	bl,cs:ANSI_COLORS[bx]	; BL = ANSI color #
	push	bx
	mov	al,ah
	call	sgr_parm		; ";" and prefix
	pop	bx
	jc	ac9
	mov	al,bl
	add	al,'0'
	call	ioctl_out		; color #
ac9:	ret
ENDPROC	ansi_color

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sgr_parm
;
; Sends ";" followed by the character in AL.
;
; Inputs:
;	AL = character
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if the wait was interrupted
;
; Modifies:
;	BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	sgr_parm
	push	ax
	mov	al,';'
	call	ioctl_out
	pop	ax
	jc	sg9
	call	ioctl_out
sg9:	ret
ENDPROC	sgr_parm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; move_cur
;
; Moving left is done with BACKSPACEs.  There's no ASCII equivalent for moving
; right, so ANSI terminals get the "cursor forward" sequence, and GENERIC
; terminals get the characters from CT_LINE (ie, what should already be there).
;
; Inputs:
;	CX = +/- columns to move
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if interrupted (DDP_STATUS updated)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	move_cur
	test	cx,cx
	jz	mc9
	jg	mc3
	neg	cx			; CX = # columns to move left
mc1:	cmp	ds:[CT_COL],0		; already at the left edge?
	je	mc9			; yes
	mov	al,CHR_BACKSPACE
	call	ioctl_out
	jc	mc8
	dec	ds:[CT_COL]
	loop	mc1
	jmp	short mc9

mc3:	cmp	ds:[CT_TERM],TERM_GENERIC
	je	mc5
	mov	al,'C'			; "cursor forward"
	call	csi_out
	jc	mc9a
	jmp	short mc7

mc5:	mov	bl,ds:[CT_COL]
	mov	bh,0
	mov	al,CHR_SPACE		; beyond the end of the line, use SPACE
	cmp	bl,ds:[CT_LLEN]
	jae	mc6
	mov	al,ds:[CT_LINE][bx]
mc6:	call	ioctl_out
	jc	mc8
mc7:	inc	ds:[CT_COL]
	loop	mc3

mc9:	clc
mc9a:	ret
mc8:	jmp	ioctl_fault
ENDPROC	move_cur

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scroll_lines
;
; Scrolls an ANSI terminal's scrolling rows up (by sending LINEFEEDs at the
; last one) or down (by sending "reverse index" sequences at the first one).
; The cursor is left on that row.
;
; Inputs:
;	CX = +/- lines to scroll (non-zero)
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if interrupted (DDP_STATUS updated)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	scroll_lines
	push	cx
	test	cx,cx			; scrolling up?
	mov	cl,0
	mov	ch,ds:[CT_BOT]		; yes, from the last row
	jns	sl1
	mov	ch,ds:[CT_TOP]		; no, from the first row
sl1:	cmp	ch,ds:[CT_ROW]		; is the cursor on that row already?
	je	sl1a			; yes (the column doesn't matter)
	call	set_pos
sl1a:	pop	cx
	jc	sl9
sl2:	test	cx,cx			; (the sign is shadow_scroll's input)
	call	scroll_shadow
	js	sl3
	mov	al,CHR_LINEFEED
	call	ioctl_out
	dec	cx
	jmp	short sl4
sl3:	mov	si,offset ANSI_RINDEX
	call	ioctl_str
	inc	cx
sl4:	jc	sl8
	jnz	sl2
sl9:	ret
sl8:	jmp	ioctl_fault
ENDPROC	scroll_lines

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; raw_input
;
; Translates a byte from an ANSI or VT100 terminal into what the VKD$ driver
; returns (see pull_kbd): non-ASCII keys are a zero followed by the PC scan
; code, which the DOS line editor maps to its editing keys (see read_line).
; The cursor keys send ESC [ A-D (or ESC O A-D), Home and End send ESC [ H
; and F (or ESC [ 1 ~ and 4 ~), Insert, Delete, PgUp, and PgDn send ESC [ 2-3 ~
; and 5-6 ~, and F1-F10 send ESC O P-S and ESC [ 15 ~ through 21 ~; other
; sequences are discarded.
;
; An ESC is held until the next byte arrives, or until ESC_MS pass without
; one, in which case it's just an ESC (see esc_timeout).  For VT100 terminals,
; DELETE (7Fh) erases the previous character, so it becomes BACKSPACE, and
; BACKSPACE becomes the Delete key.
;
; Inputs:
;	AL = byte
;	DS = context
;
; Outputs:
;	If carry clear, AL = byte to buffer; carry set if nothing to buffer
;
; Modifies:
;	AX, BX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	raw_input
	pushf
	cli
	call	raw_byte
	jc	rw8
	popf
	clc
	ret
rw8:	popf
	stc
	ret
ENDPROC	raw_input

DEFPROC	raw_byte
	cmp	ds:[CT_TERM],TERM_GENERIC
	je	rb0			; (carry clear)
	mov	ah,ds:[CT_ESC]		; AH = escape state
	test	ah,ah			; in a sequence?
	jnz	rb3			; yes
	cmp	al,CHR_ESCAPE		; ESC?
	jne	rb1			; no
	inc	ds:[CT_ESC]		; yes, hold it (state 1)
	mov	ax,ESC_MS
	call	esc_timer
	stc
	ret
rb0:	clc
	ret

rb1:	cmp	ds:[CT_TERM],TERM_VT100	; VT100 terminal?
	jne	rb0			; no
	cmp	al,CHR_DEL		; DELETE?
	jne	rb2			; no
	mov	al,CHR_BACKSPACE	; yes, it erases the previous character
	ret				; (carry clear)
rb2:	cmp	al,CHR_BACKSPACE	; BACKSPACE?
	clc
	jne	rb0			; no
	mov	al,SCAN_DEL		; yes, it's the Delete key
	jmp	short rb7
;
; State 1 (ESC received): '[' begins a control sequence (state 2) and 'O'
; begins a single-shift sequence (state 3); otherwise, buffer the ESC and
; then process the byte normally.
;
rb3:	dec	ah			; state 1?
	jnz	rb5			; no
	call	end_esc
	mov	ah,2
	cmp	al,'['
	je	rb4
	inc	ah
	cmp	al,'O'
	je	rb4
	push	ax
	mov	al,CHR_ESCAPE
	call	push_key
	pop	ax
	jmp	raw_byte
rb4:	mov	ds:[CT_ESC],ah
	mov	ds:[CT_ESCPARM],0
	stc
	ret
;
; States 2 and 3: digits are a parameter (anything after a ';', such as a
; modifier, is ignored for a key), and the first byte from 40h on ends the
; sequence.
;
rb5:	cmp	al,'@'			; final byte?
	jae	rb6			; yes
	mov	ah,ds:[CT_ESCPARM]
	sub	al,'0'
	cmp	al,9			; digit?
	ja	rb5a			; no
	test	ah,ah			; after a ';'?
	js	rb5c			; yes
	mov	bh,al
	mov	al,ah
	mov	bl,10
	mul	bl
	add	al,bh			; AL = (parameter * 10) + digit
	jmp	short rb5b
rb5a:	cmp	al,';'-'0'		; ';'?
	jne	rb8			; no, ignore it
	or	ah,80h
	xchg	al,ah
rb5b:	mov	ds:[CT_ESCPARM],al
rb8:	stc
	ret
;
; Without the option, MODE_WIDE has fewer rows (see set_mode).  The report
; then ends like any sequence that isn't a key (ie, it's discarded).
;
rb6:	mov	ds:[CT_ESC],0		; the sequence is over
	cmp	al,'c'			; device attributes?
	jne	rb6b			; no
	cmp	ds:[CT_ESCPARM],0C1h	; a VT100 (1) with no such option?
	jne	rb6b			; no
	mov	ds:[CT_WROWS],WIDE_ROWS
rb6b:	mov	si,offset ANSI_FINALS
	cmp	al,'~'			; numbered key?
	jne	rb6a			; no
	mov	al,ds:[CT_ESCPARM]
	and	al,3Fh			; AL = number
	mov	si,offset ANSI_NUMS
rb6a:	call	map_key			; AL = scan code
	jc	rb9a			; discard unknown sequences
;
; Buffer a zero, and return the scan code in AL to be buffered next.
;
rb7:	push	ax
	mov	al,0
	call	push_key
	pop	ax
rb9:	clc
rb9a:	ret
;
; A digit after a ';' matters only in a VT100's device attributes report
; (ESC [ ? 1 ; n c, which VT100_INIT asks for), where n has bit 1 set if the
; Advanced Video Option is installed; bit 6 records a digit without it.
;
rb5c:	not	al
	and	al,2
	ror	al,1
	ror	al,1
	ror	al,1			; AL = 40h if the digit has no bit 1
	and	ah,NOT 40h
	or	al,ah
	jmp	rb5b
ENDPROC	raw_byte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; push_key
;
; Inputs:
;	AL = byte to add to the context's input buffer
;	DS = context
;
; Modifies:
;	BX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	push_key
	mov	si,offset CT_INPUT
	call	push_buffer
	jc	pk9
	mov	[bx],al
pk9:	ret
ENDPROC	push_key

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; map_key
;
; Inputs:
;	AL = byte
;	CS:SI -> table of (byte, scan code) pairs, ending with zero
;
; Outputs:
;	If carry clear, AL = scan code
;
; Modifies:
;	AL, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	map_key
mk1:	cmp	byte ptr cs:[si],0	; end of the table?
	stc
	je	mk9			; yes
	cmp	al,cs:[si]
	lea	si,[si+2]
	jne	mk1
	mov	al,cs:[si-1]		; (carry clear)
mk9:	ret
ENDPROC	map_key

	DEFLBL	ANSI_FINALS,byte
	db	'A',SCAN_UP,'B',SCAN_DOWN,'C',SCAN_RIGHT,'D',SCAN_LEFT
	db	'H',SCAN_HOME,'F',SCAN_END,'P',SCAN_F1,'Q',SCAN_F2
	db	'R',SCAN_F3,'S',SCAN_F4,0
	DEFLBL	ANSI_NUMS,byte
	db	1,SCAN_HOME,2,SCAN_INS,3,SCAN_DEL,4,SCAN_END
	db	5,SCAN_PGUP,6,SCAN_PGDN,15,SCAN_F5,17,SCAN_F6
	db	18,SCAN_F7,19,SCAN_F8,20,SCAN_F9,21,SCAN_F10,0

;
; Everything from here on is for a port with more than one console, or for
; a mode set (see set_mode), neither of which a machine with 64K or less can
; have, so COM1 doesn't keep it there (see ddcom_init); comdev.asm calls it
; only for a context that has a shadow, or on a machine with more memory.
;
	DEFLBL	con_opt,near
;
; A port can have several consoles (see ddcom_open), each with its own context
; and a "shadow" of its screen: SHADOW_LEN characters (every row has room for
; WIDE_COLS, whatever the console's columns are), in a block of their own
; (and another of attributes, once a color is set; see set_color), which every
; write updates.  Only the console with focus (ct_seg) uses the terminal;
; the hotkey gives the focus to the next one, whose screen is then repainted
; from its shadow (see switch_to and paint).  The first context that a port is
; opened with gets a shadow only if SHADOW_MIN bytes of memory are free, and
; without one, the port can't have other consoles.
;
SHADOW_LEN	equ	WIDE_COLS * TERM_ROWS
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
	mov	al,WIDE_COLS
	mul	ch			; AX = row * WIDE_COLS
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
shp1:	sub	cl,es:[CT_COLS]
	jae	shp1
	add	cl,es:[CT_COLS]		; CL = column on the row
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
	mov	ah,WIDE_COLS
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
	mov	ah,WIDE_COLS
	mul	ah
	xchg	si,ax			; SI = # of cells to move
	mov	ch,cl
	mov	cl,0
	call	get_cell
	mov	di,bx			; DI -> first row
	mov	cx,si
	lea	si,[di+WIDE_COLS]	; SI -> second row
	test	dh,dh			; scrolling up?
	js	shs1			; no
	add	bx,cx			; BX -> last row (the one to erase)
	jmp	short shs2
shs1:	lea	si,[di-1]
	add	si,cx			; SI -> end of the next-to-last row
	lea	di,[si+WIDE_COLS]	; DI -> end of the last row
	std
shs2:	mov	ax,ds:[CT_SHADOW]
	call	shs3
	mov	ax,ds:[CT_ATTRS]
	call	shs3
	cld
	mov	di,bx
	mov	cx,WIDE_COLS
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
	mov	ax,0FF00h		; (CT_PROW = -1)
	mov	dl,ds:[CT_COLS]
	xor	dl,es:[CT_COLS]		; (only WIDE_COLS has bit 7 set)
	jns	swt0
	inc	ax			; CT_PCOL = 1 to set its columns, too
swt0:	mov	word ptr es:[CT_PCOL],ax
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
; last one clears CTSTAT_PAINT.  The steps are PAINT_INIT (and the columns,
; if the last console's were wide and ours aren't, or vice versa), every row
; that isn't blank (its position, and then one character per step, with the
; attributes if they change), and finally the scrolling rows, the cursor's
; position, and the current attributes.  Writes and IOCTLs wait until then.
; In 40-column mode, those rows (and the cursor's) are made double-width
; again (see wide_reset).
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
	test	cl,cl			; set the columns? (see switch_to)
	jz	pnt1b			; no
	call	col_mode
pnt1b:	call	wide_reset		; (every row is single-width now)
	mov	ds:[CT_GFX],VT100_SI
	mov	byte ptr ds:[CT_PATTR],07h
	jmp	short pnt3
pnt2:	cmp	cl,ds:[CT_PLEN]		; anything left on this row?
	jb	pnt6			; yes
;
; On to the next row: find its length, and if it isn't blank, move to it.
;
pnt3:	inc	ch
	cmp	ch,ds:[CT_ROWS]
	jae	pnt7
	mov	cl,WIDE_COLS-1
	call	get_cell		; BX -> the row's last cell
	mov	cl,0
	mov	dx,cx			; DL = length (so far)
	mov	si,offset CT_SHADOW
	mov	al,CHR_SPACE
pnt4:	cmp	word ptr [si],0		; is there a shadow?
	je	pnt5			; no
	mov	es,[si]
	mov	di,bx
	mov	cx,WIDE_COLS
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
	call	wide_row
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
	xchg	cl,ch
	mov	al,'r'
	call	csi_pair		; ESC [ first ; last r
	mov	al,ds:[CT_COL]
	mov	ah,0
	div	ds:[CT_COLS]		; AH = column on the row
	mov	ch,ds:[CT_ROW]
	mov	cl,ah
	sub	di,di
	test	ah,ah			; at the left edge?
	jnz	pnt7b			; no
	test	al,al			; of a line's first row?
	jz	pnt7b			; yes
	mov	cl,ds:[CT_COLS]		; no, the cursor was waiting to wrap
	dec	cx
	inc	di
pnt7b:	mov	al,'H'
	call	csi_pair
	call	wide_row
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
	push	bx			; (what write_context saves)
	push	dx
	push	si
	push	ds
	jmp	write_cell
ENDPROC	paint_cell

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_mode
;
; IOCTL_SETMODE, for a VT100: video modes 2 and 3 select 80 columns, modes 0
; and 1 select 40, which a VT100 displays by making rows double-width (and
; only a row at a time; see wide_row), and MODE_WIDE selects its 132 columns,
; which have only WIDE_ROWS rows without the Advanced Video Option (CT_WROWS).
; A change clears the screen and makes every row a scrolling row again, like
; VKD$.  The graphics modes (4-6) change nothing, and there are no others.
;
; Inputs:
;	CL = video mode
;	CH = rows (0 for the mode's)
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if not (DDP_STATUS updated)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_mode
	cmp	ds:[CT_TERM],TERM_VT100
	jne	smd8
	cmp	ch,25			; more than 25 rows (see VKD$)?
	ja	smd8			; yes, which a terminal doesn't have
	mov	al,WIDE_COLS
	mov	ah,ds:[CT_WROWS]
	cmp	cl,MODE_WIDE
	je	smd2
	cmp	cl,6			; a mode at all (eg, not -1)?
	ja	smd8			; no
	mov	ax,(TERM_ROWS SHL 8) OR TERM_COLS
	cmp	cl,3			; a text mode?
	ja	smd9			; no (and carry is clear)
	test	cl,2			; 80 columns?
	jnz	smd2			; yes
	shr	al,1
smd2:	cmp	al,ds:[CT_COLS]		; any change?
	je	smd9			; no (and carry is clear)
	mov	bx,ax
	dec	bh			; BH = last row
	xchg	ax,word ptr ds:[CT_COLS]
	ASSERT	<CT_ROWS>,EQ,<CT_COLS + 1>
	xor	al,bl			; (only WIDE_COLS has bit 7 set)
	mov	bl,0
	mov	word ptr ds:[CT_TOP],bx
	ASSERT	<CT_BOT>,EQ,<CT_TOP + 1>
	jns	smd3			; no columns to set
	call	col_mode
	jc	smd7
smd3:	mov	al,'r'
	call	csi_out			; ESC [ r
	jc	smd9
	call	clear_screen		; (which makes every row single-width)
smd9:	ret
smd7:	jmp	ioctl_fault
smd8:	jmp	ddcom_none
ENDPROC	set_mode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; col_mode
;
; Sets a VT100's columns (the "column mode" sequence: ESC [ ? 3 h for 132,
; or ESC [ ? 3 l for 80), which also clears its screen.
;
; Inputs:
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if the wait was interrupted
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	col_mode
	mov	si,offset VT100_COLS
	call	ioctl_str
	jc	cmo9
	mov	al,'h'
	cmp	ds:[CT_COLS],WIDE_COLS
	je	cmo1
	mov	al,'l'
cmo1:	call	ioctl_out
cmo9:	ret
ENDPROC	col_mode

	DEFLBL	VT100_COLS,byte
	db	CHR_ESCAPE,"[?3",0

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
