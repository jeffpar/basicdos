;
; BASIC-DOS Loadable Serial Debugger (Vector Traps)
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; VEC_TAB, what VT can trap, and the VT, VC, and VL commands, along with the
; reports of the software interrupt functions that VT traps (see dbg_int13 and
; dbg_int21 in dbgdev.asm).  It's resident, and it's separate because VEC_TAB
; needs DOS function numbers, which dbgdev.asm has no symbol space for.
;
	BIOSAPI equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	dosapi.inc

CODE	segment word public 'CODE'

	EXTNEAR	<ax_mem,end_command,hex_byte,hex_word,newline,pad,parse_hex>
	EXTNEAR	<peek_b,put_char,skip_space,space>
	EXTBYTE	<trap_21>
	EXTWORD	<regs>

	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
;
; VEC_TAB lists what VT can trap, for cmd_v and VL: each entry is a number (a
; vector, or a software interrupt and one of its functions; eg, 1302h), a state
; (a space, or * if it's trapped), and a description.  After a function's
; description, VEC_RPT starts the report of each call, where these codes
; display the caller's registers (see put_fmt): V_BYTE or V_WORD plus a
; register's offset in regs (see REG_TABLE), V_CYL or V_SEC for CX's cylinder
; or sector, or V_STR for the string at DS:DX.  Program mode ends the table at
; VEC_DRV, since it hooks only INT 00h, and two of the descriptions are also
; messages (see monitor).
;
; To report another function of a vector that's already hooked, just add it
; here (and a V_* code for any new register); a new vector also needs a stub
; (see dbg_int21), a vec_save slot, and a hook (see dbgdev_init).
;
VEC_RPT		equ	1
V_BYTE		equ	80h
V_WORD		equ	0A0h
V_STR		equ	0C0h+14
V_SEC		equ	0C0h+16
V_CYL		equ	0E0h+16
V_DL		equ	V_BYTE+14
V_DH		equ	V_BYTE+15
V_AL		equ	V_BYTE+20
V_BX		equ	V_WORD+18
V_ES		equ	V_WORD+4
R_DS		equ	6	; offset of DS in regs (for V_STR)
STR_MAX		equ	80	; the most of a V_STR that's displayed
	DEFLBL	VEC_TAB,word
	dw	00h
	db	' '
	DEFLBL	DIV_MSG,byte
	db	"Division error",0
	DEFLBL	VEC_DRV,word
	dw	02h
	db	" Nonmaskable interrupt",0
	dw	04h
	db	' '
	DEFLBL	OVF_MSG,byte
	db	"Overflow error",0
	dw	06h
	db	" Invalid opcode",0
	dw	07h
	db	" No coprocessor",0
	dw	08h
	db	" Double fault",0
	dw	09h
	db	" Coprocessor overrun",0
	dw	0Ah
	db	" Invalid TSS",0
	dw	0Bh
	db	" Segment not present",0
	dw	0Ch
	db	" Stack fault",0
	dw	0Dh
	db	" General protection",0
	dw	(INT_FDC SHL 8) OR FDC_READ
	db	" BIOS disk reads",VEC_RPT
	db	"Disk ",V_DL," reading ",V_AL," sectors at "
	db	V_CYL,":",V_DH,":",V_SEC," into ",V_ES,":",V_BX,0
	dw	(INT_FDC SHL 8) OR FDC_WRITE
	db	" BIOS disk writes",VEC_RPT
	db	"Disk ",V_DL," writing ",V_AL," sectors at "
	db	V_CYL,":",V_DH,":",V_SEC," from ",V_ES,":",V_BX,0
	dw	(INT_DOSFUNC SHL 8) OR DOS_HDL_OPEN
	db	" DOS file opens",VEC_RPT
	db	'DOS Open "',V_STR,'"',0
	dw	-1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_v
;
; VT traps the listed vectors, so that their exceptions stop the machine
; instead of being passed on (see dbgdev_enter), and the listed functions of
; software interrupts, so that each call is reported as it's passed on; VC
; clears the listed traps (or * for all); VL lists everything that can be
; trapped (see VEC_TAB), or only what belongs to one vector.  A vector is hex,
; or decimal with a trailing period (eg, 0D or 13.), and a function is hex (eg,
; 1302).  Single-steps (01h) and breakpoints (03h) always stop the machine.
;
DEFPROC	cmd_v
	lodsb
	cmp	al,'L'
	je	cmd_vl
	mov	dh,'*'			; DH = VT's new state
	cmp	al,'T'
	je	cv1
	mov	dh,' '			; (or VC's)
	cmp	al,'C'
	stc
	jne	cv9
cv1:	call	skip_space
	lodsb
	test	al,al			; end of the list?
	jz	cv9			; yes (carry clear)
	cmp	al,'*'			; all of them?
	jne	cv3			; no
	cmp	dh,' '			; (only VC accepts *)
	stc
	jne	cv9
	mov	bx,offset VEC_TAB
cv2:	cmp	word ptr [bx],-1	; end of the table?
	je	cv1			; yes
	inc	bx
	inc	bx
	call	set_vec
	call	next_vec
	jmp	cv2
cv3:	dec	si
	push	dx
	call	parse_vec		; BX -> its state
	pop	dx
	jc	cv9
	call	set_vec
	jmp	cv1
cv9:	ret
cmd_vl:	mov	bp,-1			; BP = the vector to list (or all)
	call	end_command
	jnc	cv3a
	call	parse_num
	jc	cv9
	test	ah,ah			; is it a vector?
	stc
	jnz	cv9			; no
	xchg	bp,ax
	call	end_command
	jc	cv9
cv3a:	mov	bx,offset VEC_TAB
cv4:	mov	dx,[bx]			; DX = its number
	cmp	dx,-1			; end of the table?
	je	cv9			; yes (carry clear)
	inc	bx
	inc	bx
	test	bp,bp			; are we listing them all?
	js	cv4b			; yes
	mov	al,dh			; AL = a function's interrupt
	test	al,al
	jnz	cv4a
	mov	al,dl			; or a vector
cv4a:	mov	ah,0
	cmp	ax,bp			; the one to list?
	jne	cv7			; no
cv4b:	mov	al,[bx]
	call	put_char		; its state
	call	space
	xchg	ax,dx
	test	ah,ah			; a function?
	jz	cv5			; no
	call	hex_word
	jmp	short cv6
cv5:	call	hex_byte
cv6:	mov	al,':'
	call	put_char
	mov	ah,8
	call	pad
	lea	si,[bx+1]		; SI -> its description
	call	put_fmt
	call	newline
cv7:	call	next_vec
	jmp	cv4
ENDPROC	cmd_v

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_vec
;
; Sets an entry's state, and keeps trap_21 nonzero while any of INT 21h's
; functions is trapped: since it's the sum of their states' differences from a
; space, it's zero only when none is (see dbg_int21).
;
; Inputs:
;	BX -> entry's state
;	DH = new state
;
; Modifies:
;	AX
;
DEFPROC	set_vec
	mov	al,dh
	xchg	al,[bx]			; AL = old state
	sub	al,dh			; AL = old state - new state
	cmp	byte ptr [bx-1],INT_DOSFUNC
	jne	sv9			; it's not one of INT 21h's functions
	sub	[trap_21],al
sv9:	ret
ENDPROC	set_vec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_num, parse_vec
;
; Parses a number for VL or VT: hex, or decimal with a trailing period (eg,
; 13., as FAULT.COM numbers vectors); parse_vec then finds it in VEC_TAB.
;
; Inputs:
;	SI -> command text
;
; Outputs:
;	If carry clear, AX = number (parse_num), or BX -> its state
;	(parse_vec), and SI -> next character
;	If carry set, it's invalid
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	parse_num
	call	parse_hex		; AX = value (as hex)
	jc	vp9
	cmp	byte ptr [si],'.'	; decimal?
	jne	vp7			; no
	inc	si
	cmp	ax,32h			; more than two digits, or 32 or more?
	jae	vp8			; yes
	mov	cl,4
	mov	ah,al
	shr	ah,cl			; AH = tens digit
	and	al,0Fh			; AL = ones digit
	cmp	al,10			; is it a decimal digit?
	jae	vp8			; no
	aad				; AX = AH * 10 + AL
vp7:	clc
	ret
vp8:	stc
vp9:	ret
ENDPROC	parse_num

DEFPROC	parse_vec
	call	parse_num
	jc	vp9
ENDPROC	parse_vec			; fall into find_vec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_vec, next_vec
;
; find_vec finds a number in VEC_TAB; next_vec advances past an entry.
;
; Inputs:
;	AX = number (find_vec), or BX -> entry's state (next_vec)
;	DS = our data
;
; Outputs:
;	If carry clear, BX -> its state (find_vec), or BX -> the next entry
;	(next_vec); if carry set, it's not in the table (find_vec)
;
; Modifies:
;	BX
;
DEFPROC	find_vec
	mov	bx,offset VEC_TAB
fv1:	cmp	word ptr [bx],-1	; end of the table?
	stc
	je	nv9			; yes
	inc	bx
	inc	bx
	cmp	ax,[bx-2]		; is this it?
	je	nv9			; yes (carry clear)
	call	next_vec
	jmp	fv1
ENDPROC	find_vec

DEFPROC	next_vec
nv1:	inc	bx
	cmp	byte ptr [bx],0
	jne	nv1
	inc	bx
nv9:	ret
ENDPROC	next_vec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_trap
;
; Inputs:
;	AX = vector
;	DS = our data
;
; Outputs:
;	Carry set if VT traps the vector
;
; Modifies:
;	None
;
DEFPROC	chk_trap
	push	bx
	call	find_vec		; BX -> its state (carry set if none)
	cmc
	jnc	ctr9			; it's not in the table
	cmp	byte ptr [bx],'*'	; (carry set if it's a space)
	cmc				; (carry set if it's trapped)
ctr9:	pop	bx
	ret
ENDPROC	chk_trap

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; rpt_vec
;
; Displays the report of a call to a software interrupt function, if VT traps
; that function, as a message for that function (see put_vec).
;
; Inputs:
;	AX = number (eg, 1302h)
;	DS = our data
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	rpt_vec
	call	find_vec		; BX -> its state (carry set if none)
	jc	nv9
	cmp	byte ptr [bx],'*'	; is it trapped?
	jne	nv9			; no
	call	put_vec
	mov	si,bx
rv1:	lodsb
	cmp	al,VEC_RPT		; the end of its description?
	jne	rv1			; no
	call	put_fmt
	jmp	newline
ENDPROC	rpt_vec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_vec
;
; Displays the start of a message about a vector ("Vxxyy: "): its number (xx)
; and function number (yy), which is 00 if it has none.
;
; Inputs:
;	AH = vector, AL = function
;
; Modifies:
;	AX
;
DEFPROC	put_vec
	push	ax
	mov	al,'V'
	call	put_char
	pop	ax
	call	hex_word
	mov	al,':'
	call	put_char
	jmp	space
ENDPROC	put_vec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_fmt
;
; Displays a VEC_TAB description or report, up to its end (0 or VEC_RPT),
; with each V_* code replaced by the value it selects (in hex), or for V_STR,
; the string that it selects, reading as much of it as the address allows (a
; report never stops the machine, even if a program passes a bad address).
;
; Inputs:
;	SI -> text
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	put_fmt
pf1:	lodsb
	cmp	al,VEC_RPT		; the end?
	jbe	pf9			; yes
	test	al,al			; a code?
	js	pf2			; yes
	call	put_char
	jmp	pf1
pf2:	xchg	dx,ax			; DL = the code
	mov	di,dx
	and	di,1Fh			; DI = its offset in regs
	mov	ax,regs[di]		; AX = the register
	cmp	dl,V_STR		; the string at DS:DX?
	jne	pf3			; no
	xchg	di,ax			; DI = DX
	mov	ax,regs[R_DS]
	call	ax_mem
	mov	cx,STR_MAX
pf2a:	call	peek_b			; AL = next character
	jc	pf1			; the address isn't valid
	test	al,al			; the end of the string?
	jz	pf1			; yes
	call	put_char
	inc	di
	loop	pf2a
	jmp	pf1
pf3:	cmp	dl,V_SEC		; CX's sector?
	jne	pf3a			; no
	and	al,3Fh			; AL = sector (the low 6 bits of CL)
	jmp	short pf5
pf3a:	cmp	dl,V_CYL		; CX's cylinder?
	jne	pf4			; no
	xchg	al,ah
	mov	cl,6
	shr	ah,cl			; AX = cylinder (CH + the high 2 of CL)
pf4:	test	dl,V_WORD XOR V_BYTE	; a word?
	jz	pf5			; no
	call	hex_word
	jmp	pf1
pf5:	call	hex_byte
	jmp	pf1
pf9:	ret
ENDPROC	put_fmt

CODE	ends

	end
