;
; BASIC-DOS MultiConfig (CONFIG.SYS blocks and startup menus)
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	BIOSAPI equ 1
	include	macros.inc
	include	bios.inc
	include	devapi.inc
	include	uart.inc

MAX_ITEMS	equ	9		; menu items per menu (1-9)
MAX_LEVELS	equ	4		; chosen blocks recorded (see mc_path)
;
; Hardware that a block's conditions can name (see get_hw and HW_KEYS).
;
HW_MDA		equ	01h		; an MDA (port 3B4h)
HW_CGA		equ	02h		; a CGA (port 3D4h)
HW_EGA		equ	04h		; an EGA
HW_VGA		equ	08h		; a VGA
HW_VIDEO	equ	HW_MDA OR HW_CGA OR HW_EGA OR HW_VGA
HW_COM		equ	10h		; a serial port
HW_COM2		equ	20h		; a second serial port
HW_286		equ	40h		; an 80286 or later
HW_386		equ	80h		; an 80386 or later

DEV	segment para public 'CODE'

	ASSUME	CS:DEV, DS:DEV, ES:DEV, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; multi_cfg
;
; Keeps only the CFG_FILE lines of the chosen configuration: the lines before
; the first block (a line that starts with "[name]" or "[name:conditions]"),
; every [COMMON] block, and the blocks chosen from the [MENU] block's menus
; (see run_menu), with each "INCLUDE=name" line replaced by that block's
; lines.  A block whose conditions aren't met (see chk_cond) is ignored.
;
; This module follows devinit_end, and devinit reads CFG_FILE at mc_end, after
; it, so the lines that we keep (which follow CFG_FILE) can be copied over this
; code, which is never needed again.
;
; Inputs:
;	CS:mc_end -> CFG_FILE data, ES:DI -> end of the data (ES = CS)
;
; Outputs:
;	CS:SI -> lines to keep (each ending with LF), CX = their length
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
DEFPROC	multi_cfg
	push	ds
	push	cs
	pop	ds
	mov	al,0
	stosb				; null-terminate the data
	push	di			; the lines to keep go here
	call	get_hw
	call	run_menu		; mc_path -> the chosen blocks
	pop	di
	push	di
	mov	si,offset mc_end
	call	copy_blk		; keep the lines before the first block
mc1:	lodsb				; AL = '[' or null (end of data)
	test	al,al
	jz	mc9
	push	di
	mov	di,offset mc_path
	mov	cx,MAX_LEVELS
	mov	ax,si
	repne	scasw			; is it a chosen block?
	pop	di
	je	mc2			; yes
	mov	bx,offset COMMON_NAME
	call	match_blk		; an available [COMMON] block?
	jne	mc3			; no
mc2:	mov	bp,offset copy_blk
	call	with_blk
	jmp	mc1
mc3:	call	next_ln			; skip the block
	cmp	al,'['
	je	mc1
	test	al,al
	jnz	mc3
	jmp	mc1
mc9:	pop	si			; SI -> lines to keep
	mov	cx,di
	sub	cx,si			; CX = their length
	pop	ds
	ret
ENDPROC	multi_cfg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; with_blk
;
; Calls BP (copy_blk or scan_menu) with the lines of a block, which is marked
; until it returns, so that find_blk can't find it, and an INCLUDE of the block
; within it (even through other blocks) is ignored, rather than repeated
; forever.  Other INCLUDEs of a block use its lines every time (eg, a SHELL
; line for each of several consoles).
;
; Inputs:
;	SI -> block's name (after the "["), BP -> copy_blk or scan_menu
;
; Outputs:
;	SI -> next block's line (or the null at the end), DI updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	with_blk
	mov	bx,si
	mov	al,0FFh
	xchg	al,[bx]			; mark the block
	push	ax
	push	bx
	call	next_ln
	call	bp
	pop	bx
	pop	ax
	mov	[bx],al			; and unmark it
	ret
ENDPROC	with_blk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copy_blk
;
; Copies lines to DI until the next block (or the end of the data), replacing
; each "INCLUDE=name" line with the lines of that block, and skipping menu
; lines (see chk_menu).  The last line of the data gets an LF if it has none,
; so that lines copied after it don't join it.
;
; Inputs:
;	SI -> line, DI -> where to copy it
;
; Outputs:
;	SI -> next block's line (or the null at the end), DI updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
DEFPROC	copy_blk
cb1:	mov	al,[si]
	cmp	al,'['			; the next block?
	je	cb9			; yes
	test	al,al			; the end of the data?
	jz	cb9			; yes
	call	chk_menu		; a menu line?
	je	cb2			; yes, so skip it
	mov	bx,offset CFG_INCLUDE
	call	chk_key			; INCLUDE=name?
	jne	cb3			; no
	push	si
	mov	bx,si
	call	find_blk		; SI -> the block's name
	jc	cb1a			; no such block (or it's being copied)
	mov	bp,offset copy_blk
	call	with_blk		; copy its lines
cb1a:	pop	si
cb2:	call	next_ln
	jmp	cb1
cb3:	lodsb				; copy the line
	test	al,al
	jz	cb4
	stosb
	cmp	al,CHR_LINEFEED
	jne	cb3
	jmp	cb1
cb4:	dec	si			; SI -> null
	mov	al,CHR_LINEFEED
	stosb
cb9:	ret
ENDPROC	copy_blk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; run_menu
;
; Displays the menu of the [MENU] block's MENUITEM and SUBMENU lines (see
; scan_menu), and records the block of the item chosen in mc_path; a SUBMENU
; item's block is another menu, whose lines (other than menu lines) are kept,
; too.  "MENUDEFAULT=name[,seconds]" selects the item that's chosen if ENTER
; is pressed (otherwise, it's the first), and how long to wait for a key
; before choosing it.  The menu uses the ROM BIOS, so it's on the video
; adapter's screen (or without one, a terminal on COM1; see pr_char).
;
; Outputs:
;	mc_path -> names of the chosen blocks (if any)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
DEFPROC	run_menu
	mov	bx,offset MENU_NAME
	call	find_blk		; SI -> menu block's name
	jnc	rm1
	ret				; no such block
rm1:	sub	ax,ax
	mov	[mc_def],ax		; no MENUDEFAULT yet
	dec	ax
	mov	[mc_secs],al		; and no timeout (0FFh)
	mov	di,offset mc_items
	mov	bp,offset scan_menu
	call	with_blk		; record the menu's items
	sub	di,offset mc_items
	shr	di,1			; DI = number of items
	jnz	rm2
	ret				; none
;
; Make the menu's default choice the MENUDEFAULT item (if any), and display
; the items.
;
rm2:	mov	dl,'1'			; DL = default choice
	mov	bx,[mc_def]
	test	bx,bx			; any MENUDEFAULT?
	jz	rm4			; no
	mov	si,offset mc_items
	mov	cx,di
rm3:	lodsw
	push	si
	xchg	si,ax
	call	cmp_name		; is this the default item?
	pop	si
	je	rm4			; yes
	inc	dx
	loop	rm3
	mov	dl,'1'			; it's not an item
rm4:	mov	[mc_choice],dl
	mov	ax,di
	add	al,'0'
	mov	[mc_max],al		; the highest choice
	mov	byte ptr [ITEM_NUM],'1'
	mov	si,offset mc_items
	mov	cx,di
rm5:	call	pr_crlf
	lodsw
	push	si
	push	ax
	mov	si,offset ITEM_STR
	call	pr_text			; "  n. "
	pop	si			; SI -> the item's name
	mov	bx,si
rm6:	lodsb				; look for the item's text
	cmp	al,','
	je	rm7
	cmp	al,' '
	ja	rm6
	mov	si,bx			; there's none, so show its name
rm7:	call	pr_text
	pop	si
	inc	byte ptr [ITEM_NUM]
	loop	rm5
	call	pr_crlf
	call	pr_crlf
	mov	si,offset PROMPT_STR
	call	pr_text
	call	get_ticks
	mov	[mc_last],ax
;
; Wait for ENTER (or the timeout), counting down the seconds, and updating the
; choice for each item number typed; any key other than a control character
; (eg, an XON from a terminal) ends the timeout.
;
rm8:	call	show_choice
rm9:	call	get_key
	jc	rm11			; a key is available
	mov	al,[mc_secs]
	cmp	al,0FEh			; is there a timeout?
	jae	rm9			; no
	test	al,al			; has it run out?
	jnz	rm10			; no
	mov	al,CHR_RETURN		; yes, so choose the current item
	jmp	short rm11
rm10:	call	get_ticks
	sub	ax,[mc_last]
	cmp	ax,18			; has another second passed?
	jb	rm9			; no
	add	[mc_last],ax
	dec	[mc_secs]
	jmp	rm8
rm11:	cmp	al,' '			; a control character?
	jae	rm11a			; no
	cmp	al,CHR_RETURN		; other than ENTER (eg, XON)?
	jne	rm9			; yes, so ignore it
rm11a:	mov	ah,0FEh
	cmp	[mc_secs],ah		; is there a timeout?
	jae	rm12			; no
	mov	[mc_secs],ah		; yes, so end it (see show_choice)
rm12:	cmp	al,CHR_RETURN
	je	rm13
	cmp	al,'1'			; is the key an item's number?
	jb	rm8			; no
	cmp	al,[mc_max]
	ja	rm8			; no
	mov	[mc_choice],al
	jmp	rm8
;
; Record the chosen item's block in mc_path (once mc_path is full, each choice
; replaces the last one recorded, so the final choice is always recorded).
;
rm13:	call	show_choice
	call	pr_crlf
	mov	bl,[mc_choice]
	sub	bl,'1'
	mov	bh,0
	shl	bx,1
	mov	bx,[mc_items+bx]	; BX -> the chosen item's name
	call	find_blk		; SI -> its block's name
	jc	rm15
	mov	ax,si
	mov	di,[mc_next]
	stosw
	cmp	di,offset mc_path + MAX_LEVELS * 2
	jae	rm14			; mc_path is full
	mov	[mc_next],di
;
; BX follows "MENUITEM=" or "SUBMENU=", so the character before the "=" tells
; them apart.
;
rm14:	cmp	byte ptr [bx-2],'U'	; a SUBMENU item?
	jne	rm15			; no
	jmp	rm1			; yes, so run its menu
rm15:	ret
ENDPROC	run_menu

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scan_menu
;
; Records the items of a menu block's MENUITEM and SUBMENU lines, including
; those of any blocks it includes, and its MENUDEFAULT line.  An item whose
; block doesn't exist (or whose conditions aren't met) isn't displayed, and
; items past MAX_ITEMS are ignored.
;
; Inputs:
;	SI -> line, DI -> next mc_items entry
;
; Outputs:
;	SI -> next block's line (or the null at the end), DI updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
DEFPROC	scan_menu
sm1:	mov	al,[si]
	cmp	al,'['			; the next block?
	je	sm9			; yes
	test	al,al			; the end of the data?
	jz	sm9			; yes
	call	chk_menu		; a menu line?
	jne	sm5			; no
	cmp	bx,offset CFG_MENUDEF
	je	sm2
	push	si
	mov	bx,si
	call	find_blk		; is the item's block available?
	pop	si
	jc	sm7			; no
	cmp	di,offset mc_items + MAX_ITEMS * 2
	jae	sm7			; no room for another item
	mov	ax,si
	stosw				; record the item's name
	jmp	short sm7
sm2:	mov	[mc_def],si
sm2a:	lodsb				; skip the default's name
	cmp	al,','			; any timeout?
	je	sm3			; yes
	cmp	al,' '
	ja	sm2a
	jmp	short sm4		; no
sm3:	mov	ah,0			; AH = seconds
sm3a:	lodsb
	sub	al,'0'
	cmp	al,9			; another digit?
	ja	sm3b			; no
	aad				; AL = AH * 10 + AL
	mov	ah,al
	jmp	sm3a
sm3b:	mov	[mc_secs],ah
sm4:	dec	si			; SI -> the character that ended it
	jmp	short sm7
sm5:	mov	bx,offset CFG_INCLUDE
	call	chk_key			; INCLUDE=name?
	jne	sm7			; no
	push	si
	mov	bx,si
	call	find_blk		; SI -> the block's name
	jc	sm6			; no such block (or it's being scanned)
	mov	bp,offset scan_menu
	call	with_blk		; record its items
sm6:	pop	si
sm7:	call	next_ln
	jmp	sm1
sm9:	ret
ENDPROC	scan_menu

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; show_choice
;
; Displays the current choice, after the one displayed before it (or the
; space at the end of PROMPT_STR), followed by the seconds remaining, if
; there's a timeout (or blanks, if it just ended), and backs up to the choice
; again.
;
; Modifies:
;	AX, CX, SI
;
DEFPROC	show_choice
	mov	al,CHR_BACKSPACE
	call	pr_char
	mov	al,[mc_choice]
	call	pr_char
	mov	cx,TIME_LEN
	mov	al,[mc_secs]
	cmp	al,0FEh			; is there a timeout?
	jb	sc2			; yes
	ja	sc9			; no, and none is displayed
	inc	ax
	mov	[mc_secs],al		; it just ended (0FEh -> 0FFh),
sc1:	mov	al,' '			; and the time is blanked
	call	pr_char
	loop	sc1
	mov	cl,TIME_LEN
	jmp	short sc3
sc2:	aam				; AH = tens, AL = ones
	xchg	al,ah
	add	ax,'00'
	mov	word ptr [TIME_NUM],ax
	mov	si,offset TIME_STR
	call	pr_text
sc3:	mov	al,CHR_BACKSPACE
	call	pr_char
	loop	sc3
sc9:	ret
ENDPROC	show_choice

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_hw
;
; Records the hardware that blocks' conditions can name (see HW_KEYS), and
; the conventional and extended memory sizes.  Adapters are found as VKD$
; finds them (see ddcon_init): an MDA or CGA by writing its cursor position
; (low) register and reading it back, and an EGA or VGA (and the ports that it
; uses, so they don't also count as an MDA or CGA) with the EGA BIOS function
; that returns its information.  Processors are told apart as CPU$ does (see
; 386init.asm), by which FLAGS bits 12-15 can be changed.
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	get_hw
	push	ds
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,[MEMORY_SIZE]
	mov	cx,[RS232_BASE]
	mov	dx,[RS232_BASE+2]
	pop	ds
	ASSUME	DS:DEV
	mov	[mc_conv],ax		; Kb of conventional memory
	mov	[mc_port],cx		; COM1's port (if any)
	mov	al,0
	jcxz	gh1
	or	al,HW_COM
gh1:	test	dx,dx
	jz	gh2
	or	al,HW_COM2
gh2:	mov	[mc_hw],al
;
; An 8086 (or 80186) always sets FLAGS bits 12-15, an 80286 in real mode
; always clears them, and an 80386 lets us set bits 12-14.
;
	pushf
	pushf
	pop	ax
	and	ah,0Fh
	push	ax
	popf
	pushf
	pop	ax
	cmp	ah,0F0h			; are bits 12-15 still set?
	jae	gh4			; yes, so it's not an 80286 or later
	or	byte ptr [mc_hw],HW_286
	mov	ah,70h
	push	ax
	popf
	pushf
	pop	ax
	test	ah,70h			; could bits 12-14 be set?
	jz	gh3			; no, so it's not an 80386 or later
	or	byte ptr [mc_hw],HW_386
gh3:	mov	ah,CAS_GETEXTMEM
	int	INT_CASSETTE		; AX = Kb of extended memory
	jc	gh4
	mov	cl,10
	shr	ax,cl
	mov	[mc_ext],ax		; Mb of extended memory
gh4:	popf
	mov	dx,3B4h			; start with the MDA
	mov	bl,HW_MDA
gh5:	mov	al,0Fh			; cursor position (low)
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
	jne	gh6			; no
	or	[mc_hw],bl
gh6:	mov	dx,3D4h			; then the CGA
	shl	bl,1
	cmp	bl,HW_CGA
	je	gh5
	mov	ah,VIDEO_ALTSEL
	mov	bl,VALT_EGAINFO
	int	INT_VIDEO
	cmp	bl,VALT_EGAINFO		; is there an EGA or VGA?
	je	gh8			; no (older BIOSes leave BL alone)
	mov	al,not HW_CGA
	test	bh,bh			; is it using the CGA's ports?
	jz	gh7			; yes
	mov	al,not HW_MDA
gh7:	and	al,[mc_hw]
	or	al,HW_EGA
	mov	[mc_hw],al
	mov	ax,VIDEO_GETDCC
	int	INT_VIDEO
	cmp	al,VIDEO_GETDCC SHR 8	; is it a VGA?
	jne	gh8			; no
	xor	byte ptr [mc_hw],HW_EGA OR HW_VGA
;
; Without a video adapter, the menu uses COM1 (see pr_char), at the speed of
; the VT100 terminals in the demos, with DTR and RTS raised, as the ROM BIOS
; does before sending (but we don't wait for DSR and CTS, as it does, since
; a terminal may not raise them, and the COM driver ignores them, too).
;
gh8:	test	byte ptr [mc_hw],HW_VIDEO
	jz	gh9
	sub	ax,ax
	mov	[mc_port],ax		; the menu uses the video adapter
	ret
gh9:	mov	ax,(COM_INIT SHL 8) OR COM_9600N81
	cwd				; DX = 0 (COM1)
	int	INT_COM
	mov	dx,[mc_port]
	add	dx,REG_MCR
	mov	al,MCR_DTR OR MCR_RTS
	out	dx,al
	ret
ENDPROC	get_hw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_blk
;
; Finds the first block with the given name whose conditions are met (other
; than a block being used; see with_blk).
;
; Inputs:
;	BX -> name (see cmp_name)
;
; Outputs:
;	Carry clear if found, SI -> the block's name; otherwise, set
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	find_blk
	mov	si,offset mc_end
	mov	al,[si]
fb1:	test	al,al			; the end of the data?
	stc
	jz	fb9			; yes
	cmp	al,'['			; a block?
	jne	fb2			; no
	inc	si
	call	match_blk		; is it the one?
	je	fb8			; yes
fb2:	call	next_ln
	jmp	fb1
fb8:	clc
fb9:	ret
ENDPROC	find_blk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; match_blk
;
; Inputs:
;	SI -> block's name, BX -> name
;
; Outputs:
;	ZF set if the names match and the block's conditions are met
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	match_blk
	call	cmp_name
	jne	mb9
;
; chk_cond checks the block's conditions: a list of terms separated by commas
; (eg, "[D40:CGA+128K,EGA+128K,VGA+128K]"), at least one of which must be met,
; where a term is a list of keywords separated by plus signs, all of which
; must be met (see chk_hw); a block without conditions is always available.
;
	DEFLBL	chk_cond,near
	push	bx
	push	si
cc1:	lodsb
	cmp	al,':'			; any conditions?
	je	cc2			; yes
	call	chk_end
	jnz	cc1
	jmp	short cc9		; no (ZF set)
cc2:	mov	dl,1			; DL = 1 while this term is met
cc3:	call	chk_hw			; AL = 0FFh if the keyword is met
	and	dl,al
	lodsb
	cmp	al,'+'			; another keyword in this term?
	je	cc3			; yes
	cmp	dl,1			; was the term met?
	je	cc9			; yes (ZF set)
	cmp	al,','			; another term?
	je	cc2			; yes (otherwise, ZF is clear)
cc9:	pop	si
	pop	bx
mb9:	ret
ENDPROC	match_blk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_hw
;
; Checks a condition keyword: one of HW_KEYS, which is met if get_hw found
; that hardware, or a number followed by K (Kb of conventional memory) or M
; (Mb of extended memory), which is met if there's at least that much memory.
; Any other keyword is never met.
;
; Inputs:
;	SI -> keyword
;
; Outputs:
;	AL = 0FFh if met, 0 if not; SI -> the character after the keyword
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	chk_hw
	push	si
	mov	bx,offset HW_KEYS
ch1:	mov	cl,[bx]			; CL = the keyword's HW_* bits
	inc	bx
	test	cl,cl			; the end of HW_KEYS?
	jz	ch2			; yes
	call	cmp_name		; is it this keyword?
	je	ch5			; yes
ch1a:	inc	bx			; skip the keyword
	cmp	byte ptr [bx-1],0
	jne	ch1a
	jmp	ch1
ch2:	sub	bx,bx			; BX = number
ch2a:	lodsb
	sub	al,'0'
	cmp	al,9			; another digit?
	ja	ch3			; no
	cbw
	shl	bx,1
	mov	cx,bx
	shl	bx,1
	shl	bx,1
	add	bx,cx
	add	bx,ax			; BX = BX * 10 + digit
	jmp	ch2a
ch3:	mov	cx,[mc_conv]
	cmp	al,'K'-'0'		; Kb of conventional memory?
	je	ch4			; yes
	mov	cx,[mc_ext]
	cmp	al,'M'-'0'		; Mb of extended memory?
	je	ch4			; yes
	sub	cx,cx			; neither, so it's met only if zero
ch4:	cmp	cx,bx
	cmc				; carry set if CX >= BX
	jmp	short ch6
ch5:	and	cl,[mc_hw]
	neg	cl			; carry set if the hardware is present
ch6:	sbb	al,al			; AL = 0FFh if met, 0 if not
	pop	si
	mov	ah,al
ch6a:	lodsb				; skip the keyword
	call	chk_end
	jnz	ch6a
	dec	si
	mov	al,ah
	ret
ENDPROC	chk_hw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; next_ln
;
; Advances SI to the next line (or the null at the end of the data).
;
; Outputs:
;	SI -> next line, AL = its first character
;
DEFPROC	next_ln
nl1:	lodsb
	cmp	al,CHR_LINEFEED
	je	nl2
	test	al,al
	jnz	nl1
	dec	si			; SI -> null
nl2:	mov	al,[si]
	ret
ENDPROC	next_ln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmp_name
;
; Compares two names, each ending with a character that chk_end accepts (eg,
; a block's name, a MENUITEM line's, or a condition keyword).
;
; Inputs:
;	SI -> name, BX -> other name
;
; Outputs:
;	ZF set if they match
;
; Modifies:
;	AX
;
DEFPROC	cmp_name
	push	bx
	push	si
cn1:	mov	ah,[bx]
	inc	bx
	lodsb
	call	chk_end			; does the name at SI end here?
	xchg	al,ah			; (AL = BX's character)
	jz	cn2			; yes
	cmp	al,ah
	je	cn1
cn9:	pop	si
	pop	bx
	ret
cn2:	call	chk_end			; does the name at BX end here, too?
	jmp	cn9
ENDPROC	cmp_name

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_end
;
; Inputs:
;	AL = character
;
; Outputs:
;	ZF set if the character ends a name: "]", ",", ":", "+", a space, or a
;	control character
;
DEFPROC	chk_end
	cmp	al,']'
	je	ce9
	cmp	al,','
	je	ce9
	cmp	al,':'
	je	ce9
	cmp	al,'+'
	je	ce9
	cmp	al,' '
	ja	ce9			; (ZF clear)
	cmp	al,al
ce9:	ret
ENDPROC	chk_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_menu
;
; Checks for the menu lines (MENUITEM, SUBMENU, and MENUDEFAULT), which
; scan_menu uses, and copy_blk never copies.
;
; Inputs:
;	SI -> line
;
; Outputs:
;	ZF set if it's a menu line (BX -> its keyword, SI -> what follows it)
;
; Modifies:
;	AX, BX, SI
;
DEFPROC	chk_menu
	mov	bx,offset CFG_MENUITEM
cm1:	call	chk_key
	je	cm9			; a menu line
	mov	al,[bx]
	cbw
	inc	ax
	add	bx,ax			; BX -> the next keyword
	cmp	byte ptr [bx],1		; any more? (carry set at the null)
	jnc	cm1			; yes (otherwise, ZF is clear)
cm9:	ret
ENDPROC	chk_menu

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_key
;
; Inputs:
;	SI -> line, BX -> length-prefixed keyword (eg, CFG_INCLUDE)
;
; Outputs:
;	ZF set if the line starts with the keyword (SI -> what follows it)
;
; Modifies:
;	SI
;
DEFPROC	chk_key
	push	cx
	push	di
	mov	di,bx
	mov	cl,[di]
	mov	ch,0
	inc	di
	push	si
	repe	cmpsb
	pop	cx
	je	ck9
	mov	si,cx			; no match, so restore SI
ck9:	pop	di
	pop	cx
	ret
ENDPROC	chk_key

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_key
;
; Returns a key typed at the keyboard, or without a video adapter, at a
; terminal on COM1 (see pr_char).
;
; Outputs:
;	Carry set if there's a key (AL = its character), clear if not
;
; Modifies:
;	AX, DX
;
DEFPROC	get_key
	mov	ah,KBD_CHECK
	int	INT_KBD
	jz	gk1			; no key at the keyboard
	mov	ah,KBD_READ
	int	INT_KBD			; AL = character
	stc
	ret
gk1:	mov	dx,[mc_port]
	test	dx,dx			; a terminal on COM1?
	jz	gk9			; no (carry clear)
	add	dx,REG_LSR
	in	al,dx
	shr	al,1			; carry set if a character is ready
	jnc	gk9			; (LSR_DR is bit 0)
	sub	dx,REG_LSR - REG_RBR
	in	al,dx			; AL = character
	stc
gk9:	ret
ENDPROC	get_key

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_ticks
;
; Outputs:
;	AX = low word of the BIOS tick count
;
DEFPROC	get_ticks
	push	ds
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,[TIMER_LOW]
	pop	ds
	ASSUME	DS:DEV
	ret
ENDPROC	get_ticks

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pr_text, pr_crlf, and pr_char
;
; pr_text displays the text at SI up to the first control character (eg, the
; CR at the end of a line, or a null), pr_crlf displays a CR and LF, and
; pr_char displays the character in AL, all with the ROM BIOS, on the video
; adapter's screen, or without one, on a terminal on COM1 (see get_hw).
;
; Modifies:
;	AX, SI (pr_text)
;
DEFPROC	pr_text
pt1:	lodsb
	cmp	al,' '
	jb	pc9
	call	pr_char
	jmp	pt1
	DEFLBL	pr_crlf,near
	mov	al,CHR_RETURN
	call	pr_char
	mov	al,CHR_LINEFEED
	DEFLBL	pr_char,near
	push	bx
	push	dx
	mov	dx,[mc_port]
	test	dx,dx			; a terminal on COM1?
	jnz	pc1			; yes
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	jmp	short pc3
pc1:	mov	ah,al
	add	dx,REG_LSR
pc2:	in	al,dx
	test	al,LSR_THRE		; can it take another character?
	jz	pc2			; not yet
	sub	dx,REG_LSR - REG_THR
	mov	al,ah
	out	dx,al
pc3:	pop	dx
	pop	bx
pc9:	ret
ENDPROC	pr_text

MENU_NAME	db	"MENU",0
COMMON_NAME	db	"COMMON",0
CFG_INCLUDE	db	8,"INCLUDE="
CFG_MENUITEM	db	9,"MENUITEM="
CFG_SUBMENU	db	8,"SUBMENU="
CFG_MENUDEF	db	12,"MENUDEFAULT="
		db	0		; (the end of the menu lines)
;
; Each condition keyword follows its HW_* bits, any of which meets it.
;
HW_KEYS		db	HW_MDA,"MDA",0,HW_CGA,"CGA",0
		db	HW_EGA,"EGA",0,HW_VGA,"VGA",0
		db	HW_VIDEO,"VIDEO",0
		db	HW_COM,"COM",0,HW_COM2,"COM2",0
		db	HW_286,"286",0,HW_386,"386",0,0
ITEM_STR	db	"  "
ITEM_NUM	db	"1. ",0
;
; PROMPT_STR ends with an extra space, which the first choice displayed
; replaces (see show_choice), and with the choice and TIME_STR, it fits on a
; 40-column screen.
;
PROMPT_STR	db	"  Enter a choice:  ",0
TIME_STR	db	"  Time remaining: "
TIME_NUM	db	"00"
TIME_LEN	equ	$ - TIME_STR
		db	0

mc_next		dw	mc_path		; next mc_path entry
mc_def		dw	0		; MENUDEFAULT's name (if any)
mc_last		dw	0		; tick count at the last second
mc_conv		dw	0		; Kb of conventional memory
mc_ext		dw	0		; Mb of extended memory
mc_port		dw	0		; COM1's port, if the menu uses it
mc_hw		db	0		; HW_* bits (see get_hw)
mc_secs		db	0		; seconds remaining (0FFh if none)
mc_choice	db	0		; current choice ('1' to mc_max)
mc_max		db	0		; highest choice
mc_items	dw	MAX_ITEMS dup (0)	; each item's name
mc_path		dw	MAX_LEVELS dup (0)	; each chosen block's name

	DEFLBL	mc_end,byte		; devinit reads CFG_FILE here

DEV	ends

	end
