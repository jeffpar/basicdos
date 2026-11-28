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
MAX_VARS	equ	4		; string variables (see chk_var)
;
; Hardware that a block's conditions can name (see get_hw and HW_KEYS).
;
HW_MDA		equ	01h		; an MDA (port 3B4h)
HW_CGA		equ	02h		; a CGA (port 3D4h)
HW_EGA		equ	04h		; an EGA
HW_VGA		equ	08h		; a VGA
HW_VIDEO	equ	HW_MDA OR HW_CGA OR HW_EGA OR HW_VGA
HW_COM1		equ	0010h		; serial ports (see RS232_BASE)
HW_COM2		equ	0020h
HW_COM3		equ	0040h
HW_COM4		equ	0080h
HW_LPT1		equ	0100h		; parallel ports (see PRINTER_BASE)
HW_LPT2		equ	0200h
HW_LPT3		equ	0400h
HW_HD		equ	0800h		; a hard disk
HW_286		equ	1000h		; an 80286 or later
HW_386		equ	2000h		; an 80386 or later

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
; each "INCLUDE=name" line with the lines of that block, recording string
; variables instead of copying them (see chk_var), adding them to SHELL lines
; (see copy_shell), and skipping menu lines (see chk_menu).  The last line of
; the data gets an LF if it has none, so that lines copied after it don't
; join it.
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
cb3:	call	chk_var			; NAME$=value?
	jnc	cb2			; yes (it's recorded, not copied)
	mov	bx,offset CFG_SHELL
	call	chk_key			; SHELL=?
	jne	cb4			; no
	call	copy_shell		; copy it up to its commands
cb4:	lodsb				; copy the (rest of the) line
	test	al,al
	jz	cb5
	stosb
	cmp	al,CHR_LINEFEED
	jne	cb4
	jmp	cb1
cb5:	dec	si			; SI -> null
	mov	al,CHR_LINEFEED
	stosb
cb9:	ret
ENDPROC	copy_blk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_var
;
; Records a string variable line (eg, PATH$="A:\;A:\EXT\CMD"): a name that
; ends with "$", followed by "=", at the start of the line.  A variable set
; again replaces its earlier setting (once MAX_VARS are set, a new one
; replaces the last).
;
; Inputs:
;	SI -> line
;
; Outputs:
;	Carry clear if it's a variable line (recorded in mc_vars), set if not
;
; Modifies:
;	AX, BX
;
DEFPROC	chk_var
	push	si
cv1:	lodsb
	cmp	al,'$'
	je	cv2
	cmp	al,'='			; a keyword (eg, SHELL=)?
	je	cv9			; yes
	cmp	al,' '
	ja	cv1
	jmp	short cv9
cv2:	cmp	byte ptr [si],'='	; is "=" next?
	jne	cv9			; no
	pop	si
	call	find_var		; BX -> its slot
	mov	[bx],si
	clc
	ret
cv9:	pop	si
	stc
	ret
ENDPROC	chk_var

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_var
;
; Inputs:
;	SI -> variable name (ending with "$")
;
; Outputs:
;	BX -> the variable's mc_vars slot (or an empty one), AX = its line
;	(0 if none)
;
; Modifies:
;	AX, BX
;
DEFPROC	find_var
	mov	bx,offset mc_vars
fv1:	mov	ax,[bx]
	test	ax,ax			; an empty slot?
	jz	fv9			; yes
	push	si
	push	di
	xchg	di,ax			; DI -> a variable's line
fv2:	lodsb
	scasb				; does the name match so far?
	jne	fv3			; no
	cmp	al,'$'			; the end of the name?
	jne	fv2			; no
fv3:	pop	di
	pop	si
	mov	ax,[bx]
	je	fv9			; it's the variable's slot
	inc	bx
	inc	bx
	cmp	bx,offset mc_vars + MAX_VARS * 2
	jb	fv1
	dec	bx
	dec	bx			; no room, so the last slot is reused
	sub	ax,ax
fv9:	ret
ENDPROC	find_var

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copy_shell
;
; Copies a SHELL line up to its commands, adding every string variable set so
; far (see chk_var) after the program (eg, SHELL=COMMAND.COM DIR becomes
; SHELL=COMMAND.COM PATH$="A:\" : DIR), and if PATH$ starts with a drive and
; the program doesn't, giving the program that drive (eg, A:COMMAND.COM).
;
; Inputs:
;	SI -> what follows "SHELL=", DI -> where to copy it
;
; Outputs:
;	SI -> the line's commands (if any), DI updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	copy_shell
	push	si
	mov	si,offset CFG_SHELL + 1
	movsw
	movsw
	movsw				; "SHELL="
	mov	si,offset PATH_NAME
	call	find_var		; AX -> PATH$'s line (if any)
	pop	si
	mov	bx,si			; BX -> the program
	xchg	cx,ax
	jcxz	cs2			; no PATH$
cs1:	lodsb
	cmp	al,':'			; does the program have a drive?
	je	cs2			; yes
	cmp	al,' '
	ja	cs1
	mov	si,cx
	add	si,PATH_LEN		; SI -> PATH$'s value
	lodsb
	cmp	al,'"'			; is it a string
	jne	cs2
	lodsw
	cmp	ah,':'			; that starts with a drive?
	jne	cs2			; no
	stosw				; yes, so the program gets that drive
cs2:	mov	si,bx
cs3:	lodsb				; copy the program
	cmp	al,' '
	jbe	cs4
	stosb
	jmp	cs3
cs4:	dec	si			; SI -> what follows it
	mov	bx,offset mc_vars
	sub	dx,dx			; DX = 0 until a variable is added
cs5:	mov	cx,[bx]
	jcxz	cs7			; no more variables
	test	dx,dx			; the first one?
	jz	cs6			; yes
	mov	ax,(':' SHL 8) OR ' '
	stosw				; no, so separate it with " :"
cs6:	mov	al,' '
	stosb
	push	si
	mov	si,cx
cs6a:	lodsb				; copy the variable's line
	cmp	al,' '
	jb	cs6b
	stosb
	jmp	cs6a
cs6b:	pop	si
	inc	dx
	inc	bx
	inc	bx
	cmp	bx,offset mc_vars + MAX_VARS * 2
	jb	cs5
cs7:	test	dx,dx			; were any variables added?
	jz	cs9			; no
	push	si
cs7a:	lodsb
	cmp	al,' '
	je	cs7a
	pop	si
	jb	cs9			; there are no commands
	cmp	al,':'			; do they start with a ":" already?
	je	cs9			; yes
	mov	ax,(':' SHL 8) OR ' '
	stosw				; no, so separate them with " :"
cs9:	ret
ENDPROC	copy_shell

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
; A menu with only one item (eg, on a machine whose hardware offers only one
; configuration) chooses it without being displayed.  Otherwise, make the
; menu's default choice the MENUDEFAULT item (if any), and display the items.
;
rm2:	mov	bx,[mc_items]		; BX -> the first item's name
	cmp	di,1			; is it the only one?
	jne	rm2a			; no
	jmp	rm13a			; yes, so it's chosen
rm2a:	mov	dl,'1'			; DL = default choice
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
rm13a:	call	find_blk		; SI -> its block's name
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
; 386init.asm), by which FLAGS bits 12-15 can be changed, and hard disks as
; HDC$ finds them.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	get_hw
	push	ds
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
;
; Each serial or parallel port that the ROM BIOS found has its address in
; RS232_BASE or PRINTER_BASE, which follows it.
;
	ASSERT	<offset PRINTER_BASE>,EQ,<offset RS232_BASE + 8>
	mov	si,offset RS232_BASE
	mov	cx,7			; COM1-COM4 and LPT1-LPT3
	mov	dx,HW_COM1
	sub	bx,bx			; BX = HW_* bits
gh1:	lodsw
	test	ax,ax			; is the port present?
	jz	gh2			; no
	or	bx,dx
gh2:	shl	dx,1
	loop	gh1
	mov	ax,[MEMORY_SIZE]
	mov	cx,[RS232_BASE]
	pop	ds
	ASSUME	DS:DEV
	mov	[mc_conv],ax		; Kb of conventional memory
	mov	[mc_port],cx		; COM1's port (if any)
	mov	[mc_hw],bx
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
	or	byte ptr [mc_hw+1],HW_286 SHR 8
	mov	ah,70h
	push	ax
	popf
	pushf
	pop	ax
	test	ah,70h			; could bits 12-14 be set?
	jz	gh3			; no, so it's not an 80386 or later
	or	byte ptr [mc_hw+1],HW_386 SHR 8
gh3:	mov	ah,CAS_GETEXTMEM
	int	INT_CASSETTE		; AX = Kb of extended memory
	jc	gh4
	mov	cl,10
	shr	ax,cl
	mov	[mc_ext],ax		; Mb of extended memory
gh4:	popf
;
; A hard disk is one that the ROM BIOS reports, as HDC$ finds them.
;
	push	es
	mov	ah,HDC_GETPARMS
	mov	dl,80h
	int	INT_FDC			; DL = # hard disks
	pop	es
	jc	gh4a
	test	dl,dl
	jz	gh4a
	or	byte ptr [mc_hw+1],HW_HD SHR 8
gh4a:	mov	dx,3B4h			; start with the MDA
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
	or	byte ptr [mc_hw],bl
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
gh7:	and	al,byte ptr [mc_hw]
	or	al,HW_EGA
	mov	byte ptr [mc_hw],al
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
ch1:	mov	cx,[bx]			; CX = the keyword's HW_* bits
	inc	bx
	inc	bx
	jcxz	ch2			; the end of HW_KEYS
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
ch5:	and	cx,[mc_hw]
	neg	cx			; carry set if the hardware is present
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
CFG_SHELL	db	6,"SHELL="
PATH_NAME	db	"PATH$="
PATH_LEN	equ	$ - PATH_NAME
;
; Each condition keyword follows its HW_* bits (a word), any of which meets
; it.
;
HW_KEYS		dw	HW_MDA
		db	"MDA",0
		dw	HW_CGA
		db	"CGA",0
		dw	HW_EGA
		db	"EGA",0
		dw	HW_VGA
		db	"VGA",0
		dw	HW_VIDEO
		db	"VIDEO",0
		dw	HW_COM1
		db	"COM1",0
		dw	HW_COM2
		db	"COM2",0
		dw	HW_COM3
		db	"COM3",0
		dw	HW_COM4
		db	"COM4",0
		dw	HW_LPT1
		db	"LPT1",0
		dw	HW_LPT2
		db	"LPT2",0
		dw	HW_LPT3
		db	"LPT3",0
		dw	HW_HD
		db	"HD",0
		dw	HW_286
		db	"286",0
		dw	HW_386
		db	"386",0
		dw	0
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
mc_hw		dw	0		; HW_* bits (see get_hw)
mc_secs		db	0		; seconds remaining (0FFh if none)
mc_choice	db	0		; current choice ('1' to mc_max)
mc_max		db	0		; highest choice
mc_items	dw	MAX_ITEMS dup (0)	; each item's name
mc_path		dw	MAX_LEVELS dup (0)	; each chosen block's name
mc_vars		dw	MAX_VARS dup (0)	; each string variable's line

	DEFLBL	mc_end,byte		; devinit reads CFG_FILE here

DEV	ends

	end
