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
	DOSFCB equ 1
	include	macros.inc
	include	bios.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc
	include	cpu.inc

CODE	segment word public 'CODE'

	EXTNEAR	<ax_mem,cpu_call,end_command,hex_byte,hex_word,newline,pad>
	EXTNEAR	<parse_hex,peek_b,peek_w,put_char,put_n,skip_space,space>
	EXTBYTE	<col,trap_21>
	EXTWORD	<dos_seg,dos_vars,regs,sys_regs>

	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
;
; VEC_TAB lists what VT can trap, for cmd_v and VL: each entry is a number (a
; vector, or a software interrupt and one of its functions; eg, 1302h), a state
; (a space, or * if it's trapped), and a description, which ends how a function
; reports each call (see rpt_vec): VEC_RPT starts a report that replaces the
; description, VEC_ARG starts the arguments that follow the description, and a
; zero means that the next entry's arguments are this entry's, too.  Numbers
; with VEC_SUM in the high byte are summaries, one per vector with functions,
; for VL to list instead of those functions; they end what VT can trap.
;
; These codes display values (see put_fmt): V_BYTE or V_WORD plus an offset in
; regs (see REG_TABLE, and fault_ec), V_CYL or V_SEC for CX's cylinder or
; sector, V_STR or V_STRE for the string at DS:DX or ES:DI, V_FCB or V_FCB2 for
; the name or new name in the FCB at DS:DX, or V_FB or V_FW plus the next byte
; for a byte or word at that offset in the FCB (which may be an extended FCB).
;
; Program mode ends the table at VEC_DRV, since it hooks only INT 00h, and some
; descriptions are also messages (see monitor).  To report another function of
; a vector that's already hooked, just add it here (and a V_* code for any new
; register); a new vector also needs a stub (see dbg_int21), a vec_save slot,
; and a hook (see dbgdev_init).
;
VEC_RPT		equ	1
VEC_ARG		equ	2
VEC_SUM		equ	0FFh
V_BYTE		equ	80h
V_WORD		equ	0A0h
V_FB		equ	0C0h+1
V_FW		equ	0E0h+2
V_FCB		equ	0E0h+1
V_FCB2		equ	0E0h+11h
V_STRE		equ	0C0h+8
V_STR		equ	0C0h+14
V_SEC		equ	0C0h+16
V_CYL		equ	0E0h+16
V_DL		equ	V_BYTE+14
V_DH		equ	V_BYTE+15
V_AL		equ	V_BYTE+20
V_DS		equ	V_WORD+6
V_ES		equ	V_WORD+4
V_DX		equ	V_WORD+14
V_CX		equ	V_WORD+16
V_BX		equ	V_WORD+18
V_IP		equ	V_WORD+22
V_CS		equ	V_WORD+24
V_FEC		equ	V_WORD+28
V_FVEC		equ	V_BYTE+30
R_ES		equ	4	; offsets in regs (see REG_TABLE)
R_DS		equ	6
R_DX		equ	14
STR_COL		equ	68	; the column where a string's display ends
FCB_NEWNAME	equ	11h	; the new name in a rename FCB (see fcbio.asm)
VEC_DOS		equ	INT_DOSFUNC SHL 8
	DEFLBL	FAULT_MSG,byte
	db	"CPU fault ",V_FVEC," (EC=",V_FEC,") at ",V_CS,":",V_IP,0
	db	"System halted",0
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
	dw	VEC_DOS OR DOS_FCB_OPEN
	db	" FCB Open",0
	dw	VEC_DOS OR DOS_FCB_CLOSE
	db	" FCB Close",0
	dw	VEC_DOS OR DOS_FCB_FFIRST
	db	" FCB FindFirst",0
	dw	VEC_DOS OR DOS_FCB_FNEXT
	db	" FCB FindNext",0
	dw	VEC_DOS OR DOS_FCB_DELETE
	db	" FCB Delete",VEC_ARG,V_FCB,0
	dw	VEC_DOS OR DOS_FCB_SREAD
	db	" FCB SeqRead",0
	dw	VEC_DOS OR DOS_FCB_SWRITE
	db	" FCB SeqWrite",VEC_ARG,V_FCB
	db	" at ",V_FW,FCB_CURBLK,":",V_FB,FCBF_CURREC
	db	" size ",V_FW,FCB_RECSIZE,0
	dw	VEC_DOS OR DOS_FCB_CREATE
	db	" FCB Create",VEC_ARG,V_FCB,0
	dw	VEC_DOS OR DOS_FCB_RENAME
	db	" FCB Rename",VEC_ARG,V_FCB," to ",V_FCB2,0
	dw	VEC_DOS OR DOS_FCB_RREAD
	db	" FCB RandRead",0
	dw	VEC_DOS OR DOS_FCB_RWRITE
	db	" FCB RandWrite",VEC_ARG,V_FCB
	db	" at ",V_FB,FCBF_RELREC+2,V_FW,FCBF_RELREC
	db	" size ",V_FW,FCB_RECSIZE,0
	dw	VEC_DOS OR DOS_FCB_SIZE
	db	" FCB Size",VEC_ARG,V_FCB," size ",V_FW,FCB_RECSIZE,0
	dw	VEC_DOS OR DOS_FCB_SETREL
	db	" FCB SetRandom",VEC_ARG,V_FCB
	db	" at ",V_FW,FCB_CURBLK,":",V_FB,FCBF_CURREC
	db	" size ",V_FW,FCB_RECSIZE,0
	dw	VEC_DOS OR DOS_FCB_RBREAD
	db	" FCB BlockRead",0
	dw	VEC_DOS OR DOS_FCB_RBWRITE
	db	" FCB BlockWrite",VEC_ARG,V_FCB," ",V_CX
	db	" records at ",V_FB,FCBF_RELREC+2,V_FW,FCBF_RELREC
	db	" size ",V_FW,FCB_RECSIZE,0
	dw	VEC_DOS OR DOS_DSK_MKDIR
	db	" DOS MkDir",0
	dw	VEC_DOS OR DOS_DSK_RMDIR
	db	" DOS RmDir",0
	dw	VEC_DOS OR DOS_DSK_CHDIR
	db	" DOS ChDir",VEC_ARG,V_STR,0
	dw	VEC_DOS OR DOS_HDL_CREATE
	db	" DOS Create",VEC_ARG,V_STR," attr ",V_CX,0
	dw	VEC_DOS OR DOS_HDL_OPEN
	db	" DOS Open",VEC_ARG,V_STR,0
	dw	VEC_DOS OR DOS_HDL_CLOSE
	db	" DOS Close",VEC_ARG,"#",V_BX,0
	dw	VEC_DOS OR DOS_HDL_READ
	db	" DOS Read",0
	dw	VEC_DOS OR DOS_HDL_WRITE
	db	" DOS Write",VEC_ARG,"#",V_BX," ",V_CX
	db	" bytes at ",V_DS,":",V_DX,0
	dw	VEC_DOS OR DOS_DSK_DELETE
	db	" DOS Delete",VEC_ARG,V_STR,0
	dw	VEC_DOS OR DOS_HDL_SEEK
	db	" DOS Seek",VEC_ARG,"#",V_BX
	db	" to ",V_CX,":",V_DX," from ",V_AL,0
	dw	VEC_DOS OR (DOS_DSK_GETATTR SHR 8)
	db	" DOS Attr",VEC_ARG,V_AL," ",V_STR," attr ",V_CX,0
	dw	VEC_DOS OR DOS_HDL_IOCTL
	db	" DOS IOCTL",VEC_ARG,"#",V_BX," func ",V_AL," ",V_CX," ",V_DX,0
	dw	VEC_DOS OR DOS_DSK_FFIRST
	db	" DOS FindFirst",VEC_ARG,V_STR," attr ",V_CX,0
	dw	VEC_DOS OR DOS_DSK_FNEXT
	db	" DOS FindNext",VEC_ARG,0
	dw	VEC_DOS OR DOS_DSK_RENAME
	db	" DOS Rename",VEC_ARG,V_STR," to ",V_STRE,0
	dw	VEC_DOS OR (DOS_HDL_GETTIME SHR 8)
	db	" DOS FileTime",VEC_ARG,V_AL," #",V_BX," ",V_CX," ",V_DX,0
	dw	(VEC_SUM SHL 8) OR INT_FDC
	db	" BIOS disk functions (see VL 13)",0
	dw	(VEC_SUM SHL 8) OR INT_DOSFUNC
	db	" DOS functions (see VL 21)",0
	dw	-1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_v
;
; VT traps the listed vectors, so that their exceptions stop the machine
; instead of being passed on (see dbgdev_enter), and the listed functions of
; software interrupts, so that each call is reported as it's passed on; VC
; clears the listed traps (or * for all); VL lists the vectors that can be
; trapped, with a summary for each vector with functions (see VEC_TAB), or only
; what belongs to one vector.  A vector is hex, or decimal with a trailing
; period (eg, 0D or 13.), and a function is hex (eg, 1302); a vector that has
; functions in the table selects all of them (eg, 21).  Single-steps (01h) and
; breakpoints (03h) always stop the machine.
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
	sub	cx,cx			; CL = 0 selects every entry
	jmp	short cv2
cv3:	dec	si
	push	dx
	call	parse_num		; AX = number
	pop	dx
	jc	cv9
	call	find_vec		; BX -> its state
	jc	cv3b			; it's not in the table
	call	set_vec
	jmp	cv1
cv3b:	test	ah,ah			; could it be a vector?
	stc
	jnz	cv9			; no
	xchg	cx,ax			; CL = the vector to select
cv2:	mov	bx,offset VEC_TAB	; (CH counts the entries set)
cv2a:	mov	ax,[bx]			; AX = its number
	cmp	ah,VEC_SUM		; the end of what VT can trap?
	je	cv2d			; yes
	inc	bx
	inc	bx
	test	cl,cl			; every entry?
	jz	cv2b			; yes
	cmp	ah,cl			; a function of that vector?
	jne	cv2c			; no
cv2b:	call	set_vec
	inc	ch
cv2c:	call	next_vec
	jmp	cv2a
cv2d:	cmp	ch,1			; were none set (carry set if so)?
	jnc	cv1			; no
cv9:	ret
cmd_vl:	mov	bp,VEC_SUM		; BP = the vector to list (or VEC_SUM)
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
	mov	al,dh			; AL = a function's INT, or VEC_SUM
	test	al,al
	jnz	cv4a
	mov	al,dl			; or a vector
	cmp	bp,VEC_SUM		; are we listing all the vectors?
	je	cv4b			; yes
cv4a:	mov	ah,0
	cmp	ax,bp			; the one to list?
	jne	cv7			; no
cv4b:	mov	al,[bx]			; AL = its state
	cmp	dh,VEC_SUM		; a summary?
	jne	cv4e			; no
	push	bx
	mov	bx,offset VEC_TAB	; yes, so is any function trapped?
cv4c:	inc	bx
	inc	bx
	cmp	[bx-1],dl		; is this one of them?
	jne	cv4d			; no
	cmp	byte ptr [bx],'*'	; is it trapped?
	jne	cv4d			; no
	mov	al,'*'
cv4d:	call	next_vec
	cmp	byte ptr [bx+1],VEC_SUM	; the end of the functions?
	jne	cv4c			; no
	pop	bx
	mov	dh,0			; display it as a vector
cv4e:	call	put_char		; its state
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
; parse_num
;
; Parses a number for VC, VL, or VT: hex, or decimal with a trailing period
; (eg, 13., as FAULT.COM numbers vectors).
;
; Inputs:
;	SI -> command text
;
; Outputs:
;	If carry clear, AX = number, and SI -> next character
;	If carry set, it's invalid
;
; Modifies:
;	AX, CX, DX, SI
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
fv1:	cmp	byte ptr [bx+1],VEC_SUM	; the end of what VT can trap?
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
; that function, as a message for that function (see put_vec): its description
; and arguments, or for a VEC_RPT entry, only its report (see VEC_TAB).  The
; report starts at column 0, even if DEBUG$ output has left col elsewhere,
; since strings stop at STR_COL, so that a report fits on one line.
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
	mov	[col],0
	call	put_vec
	mov	si,bx
rv1:	lodsb
	cmp	al,VEC_ARG		; the end of its description?
	ja	rv1			; no
	cmp	al,VEC_RPT		; does a report replace it?
	je	rv3			; yes
	lea	si,[bx+1]
	call	put_fmt			; AL = the end of its description
rv2:	cmp	al,VEC_ARG		; do its arguments follow?
	je	rv2a			; yes
	lodsb				; no, so find the next entry's
	jmp	rv2
rv2a:	call	space
rv3:	call	put_fmt
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
; Displays a VEC_TAB description or report, up to its end (0, VEC_RPT, or
; VEC_ARG), with each V_* code replaced by the value it selects (in hex), or
; for a name, in quotes, reading as much of it as its address allows (a report
; never stops the machine, even if a program passes a bad address).
;
; Inputs:
;	SI -> text
;
; Outputs:
;	AL = the end of the text, and SI -> what follows it
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	put_fmt
pf1:	lodsb
	cmp	al,VEC_ARG		; the end?
	jbe	pf9			; yes
	test	al,al			; a code?
	js	pf2			; yes
	call	put_char
	jmp	pf1
pf9:	ret
pf2:	xchg	dx,ax			; DL = the code
	mov	di,dx
	and	di,1Fh			; DI = its offset in regs
	mov	ax,regs[di]		; AX = the register
	cmp	dl,V_SEC		; CX's sector?
	jne	pf2a			; no
	and	al,3Fh			; AL = sector (the low 6 bits of CL)
	jmp	short pf5
pf2a:	cmp	dl,V_CYL		; CX's cylinder?
	jne	pf3			; no
	xchg	al,ah
	mov	cl,6
	shr	ah,cl			; AX = cylinder (CH + the high 2 of CL)
	jmp	short pf4
pf3:	cmp	dl,0C0h			; just a register?
	jb	pf4			; yes
	cmp	dl,V_FB			; a value in the FCB?
	je	pf3a			; yes
	cmp	dl,V_FW
	jne	pf6			; no
pf3a:	call	fcb_mem
	lodsb				; AX = its offset
	cbw
	add	di,ax
	call	peek_w
pf4:	test	dl,V_WORD XOR V_BYTE	; a word?
	jz	pf5			; no
	call	hex_word
	jmp	pf1
pf5:	call	hex_byte
	jmp	pf1
pf6:	xchg	di,ax			; DI = the string's offset (for V_STR*)
	mov	al,'"'
	call	put_char
	test	dl,V_WORD XOR V_BYTE	; a name in the FCB?
	jnz	pf7			; yes
	mov	ax,regs[R_DS]
	cmp	dl,V_STR		; the string at DS:DX?
	je	pf6a			; yes
	mov	ax,regs[R_ES]
pf6a:	call	ax_mem
pf6b:	cmp	[col],STR_COL		; is that as much as fits?
	jae	pf8			; yes
	call	peek_b			; AL = next character
	jc	pf8			; the address isn't valid
	test	al,al			; the end of the string?
	jz	pf8			; yes
	call	put_char
	inc	di
	jmp	pf6b
pf7:	call	fcb_mem
	cmp	dl,V_FCB		; the name, rather than the new name?
	jne	pf7a			; no
	call	peek_b			; AL = 1-based drive
	dec	al			; is it the default drive (or invalid)?
	js	pf7b			; yes
	add	al,'A'
	call	put_char
	mov	al,':'
	call	put_char
	jmp	short pf7b
pf7a:	add	di,FCB_NEWNAME-size FCB_DRIVE
pf7b:	mov	cx,size FCB_NAME
pf7c:	inc	di
	call	peek_b			; AL = next character
	jc	pf8			; the address isn't valid
	cmp	al,' '			; padding?
	je	pf7d			; yes
	call	put_char
pf7d:	cmp	cl,4			; the end of the 8-character part?
	jne	pf7e			; no
	mov	al,'.'
	call	put_char
pf7e:	loop	pf7c
pf8:	mov	al,'"'
	call	put_char
	jmp	pf1
ENDPROC	put_fmt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fcb_mem
;
; Inputs:
;	The caller's DS:DX -> FCB or extended FCB
;
; Outputs:
;	mem_seg:DI -> FCB (see peek_b)
;
; Modifies:
;	AX, DI
;
DEFPROC	fcb_mem
	mov	di,regs[R_DX]
	mov	ax,regs[R_DS]
	call	ax_mem
	call	peek_b
	cmp	al,0FFh			; an extended FCB?
	jne	fm9			; no
	add	di,size FCBEX
fm9:	ret
ENDPROC	fcb_mem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; list_sess
;
; Displays each session with a program, for DL with no arguments: "*" if its
; LDT is the active one, its number (from 1, as in KILL), its console, and its
; program.
; We could be stopped anywhere, even in DOS, so we read DOS's tables rather
; than call it (see scb_query).  A program's PSP may be a selector in its own
; session's LDT, which isn't necessarily the active one, so we read that LDT to
; find the PSP's address, and from that, its block's name.
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	list_sess
	LOCVAR	lsPMB,byte,<size PMB>
	LOCVAR	lsBase,dword
	LOCVAR	lsSFB,word		; the SFB table
	LOCVAR	lsSCB,word		; the next SCB
	LOCVAR	lsEnd,word		; the end of the SCB table
	LOCVAR	lsNum,word		; the next SCB's session # (from 0)
	LOCVAR	lsLDT,word		; and its LDT #
	ENTER
	mov	ax,[dos_seg]
	call	ax_mem			; (for peek_w and peek_b)
	mov	di,[dos_vars]
	add	di,DV_SFB_TABLE - DV_MEM_SIZE
	call	peek_w
	mov	[lsSFB],ax
	add	di,DV_SCB_TABLE - DV_SFB_TABLE
	call	peek_w
	mov	[lsSCB],ax
	inc	di
	inc	di
	call	peek_w
	mov	[lsEnd],ax
	mov	[lsNum],0
	jmp	short ls1
ls8:	add	[lsSCB],size SCB
	inc	[lsNum]
ls1:	mov	di,[lsSCB]
	cmp	di,[lsEnd]		; any more?
	jb	ls1a			; yes
	LEAVE				; (and carry is clear)
	ret
	ASSERT	<SCB_STATUS>,EQ,0
ls1a:	call	peek_b			; AL = SCB_STATUS
	test	al,SCSTAT_LOAD		; does it have a program?
	jz	ls8			; no
;
; All the LDTs are in one 64K, so their bases differ in the low word alone.
; An empty LDT (eg, with RING=0) shares another's base, so it never counts.
;
	mov	bx,[lsNum]
	call	chk_sess		; BX = its LDT #
	mov	[lsLDT],bx
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_LDT
	call	cpu_call		; CX = base, AX = limit (-1 if empty)
	inc	ax			; is it empty?
	mov	dl,' '
	jz	ls2			; yes
	push	cx
	mov	bx,sys_regs[14]		; BX = LDTR
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_SEL
	call	cpu_call		; CX = the active LDT's base
	pop	ax
	mov	dl,' '
	cmp	ax,cx			; is this it?
	jne	ls2			; no
	mov	dl,'*'
ls2:	mov	al,dl
	call	put_char
	mov	al,byte ptr [lsNum]
	inc	ax			; AL = session # (from 1)
	call	hex_byte
	call	space
	mov	di,[lsSCB]
	add	di,SCB_SFHOUT
	call	peek_b			; AL = SFH of the session's console
	cmp	al,SFH_NODEV		; is there one?
	jae	ls4			; no (it's SFH_NODEV or SFH_NONE)
	mov	ah,size SFB
	mul	ah
	add	ax,[lsSFB]
	xchg	di,ax			; DI -> SFB
	ASSERT	<SFB_NAME>,EQ,0
	mov	cx,8
ls3:	call	peek_b			; display up to 8 characters of it
	inc	di
	test	al,al
	jz	ls4
	call	put_char
	loop	ls3
ls4:	mov	ah,12			; (the column after the console's name)
	call	pad
	mov	di,[lsSCB]
	add	di,SCB_PSP
	call	peek_w			; AX = its program's PSP
	xchg	si,ax			; SI = PSP
	test	si,4			; an LDT selector?
	jnz	ls5			; yes
	mov	bx,si
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_SEL
	call	cpu_call		; DX:CX = its address
	jmp	short ls6
ls5:	and	si,NOT 7
	inc	si
	inc	si			; SI -> the descriptor's base
	mov	bx,[lsLDT]
	push	ss
	pop	es
	lea	di,[lsBase]
	mov	cx,4
	mov	ax,(CPU_RWMEM SHL 8) OR ADDR_LDT
	call	cpu_call
	mov	cx,[lsBase].LOW
	mov	dx,[lsBase].HIW
	mov	dh,0			; DX:CX = its address
ls6:	jc	ls7			; (we can't tell)
	mov	bx,-1			; BX = -1 (the block at DX:CX)
	push	ss
	pop	es
	lea	di,[lsPMB]		; ES:DI -> PMB buffer
	mov	ah,CPU_QUERY
	call	cpu_call
	jc	ls7			; (there's no such block)
	lea	si,[di].PMB_NAME	; ES:SI -> its name
	mov	cx,size PMB_NAME
	call	put_n
ls7:	call	newline
	jmp	ls8
ENDPROC	list_sess

;
; chk_sess returns carry set unless BX (from 0) is a session #, and then ZF set
; unless the session has a program, as list_sess requires, in which case BX is
; its LDT # (for ADDR_LDT; sessions can share one).
;
; Modifies:
;	BX, and the memory to access (see ax_mem)
;
DEFPROC	chk_sess
	push	ax
	push	di
	mov	ax,[dos_seg]
	call	ax_mem
	mov	di,[dos_vars]
	add	di,DV_SCB_TABLE - DV_MEM_SIZE
	call	peek_w			; AX = the SCB table
	push	ax
	inc	di
	inc	di
	call	peek_w			; AX = its end
	pop	di
	push	ax
	mov	al,size SCB
	mul	bl
	add	di,ax			; DI -> session's SCB
	pop	ax
	cmp	bx,MAX_SESSIONS		; is it a session #?
	jae	cks8			; no
	cmp	di,ax			; is it in the table?
	jae	cks8			; no
	ASSERT	<SCB_STATUS>,EQ,0
	call	peek_b			; AL = SCB_STATUS
	and	al,SCSTAT_LOAD		; (which clears carry)
	jz	cks9			; no program
	add	di,SCB_LDT
	call	peek_b			; AL = its LDT #
	cbw
	xchg	bx,ax			; BX = its LDT #
	test	sp,sp			; (ZF and carry clear)
	jmp	short cks9
cks8:	stc
cks9:	pop	di
	pop	ax
	ret
ENDPROC	chk_sess

CODE	ends

	end
