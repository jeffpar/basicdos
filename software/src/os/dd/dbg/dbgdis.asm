;
; BASIC-DOS Loadable Serial Debugger (Disassembler)
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The 80286 (and 8086) disassembler for U, BL, and the instruction at CS:IP
; (see dis_line), and P's test for instructions to step over (see chk_over).
; It's resident, like dbgdev.asm, which LINK puts first, and it's a module of
; its own only for MASM's symbol space (its mnemonics alone define about 120
; equates).
;
	DOSFUNC equ 1
	include	macros.inc
	include	devapi.inc
	include	dosapi.inc

CODE	segment word public 'CODE'

	EXTNEAR	<at_ip,fetch,fetch_word,hex_addr,hex_byte,hex_word,ip_mem>
	EXTNEAR	<newline,pad,put_char,put_reg,put_string,reg_val,space>
	EXTBYTE	<col,mem_mode,mute>
	EXTWORD	<mem_seg>

	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING

;
; Disassembler state (see decode).
;
	DEFBYTE	opcode,0
	DEFBYTE	modrm,0			; ModRM byte (or opcode, if none)
	DEFBYTE	wbit,0			; 0 (byte), 1 (word), or 2 (far)
	DEFBYTE	opnds,0			; operand types (see OPND_TAB)
	DEFBYTE	mnemonic,0		; MNEMS index (see chk_over)
	DEFBYTE	pfx,0			; last LOCK or REP prefix (or 0)
	DEFBYTE	fmt_str,0		; 1 if a string follows (see chk_fmt)
	DEFBYTE	seg_ovr,0		; segment override (as in REGNAMES)
	DEFBYTE	ea_seg,0		; memory operand's segment, likewise
	DEFWORD	ea_off,0		; and its offset (see ea_start)

	DEFLBL	EA_MSG,byte
	db	9,"; EA = ",0
	DEFLBL	FMT_MSG,byte
	db	9,'; "',0
;
; Mnemonics, each with bit 7 set in its last character, and an M_ equate
; with its index (see put_mnem); bit 7 of an index in OPTAB means "word"
; and indexes 78h-7Eh are groups (see decode), so there can be only 120.
;
_MN = 0
MNEM	macro	text,name
	IFB	<name>
M_&text = _MN
	ELSE
M_&name = _MN
	ENDIF
_MN = _MN + 1
_LC = 0
	IRPC	c,<text>
	 IF	_LC
	db	_LC
	 ENDIF
_LC = '&c'
	ENDM
	db	_LC OR 80h
	endm

	DEFLBL	MNEMS,byte
	MNEM	ADD			; 00h-07h: ALU ops and group 1
	MNEM	OR
	MNEM	ADC
	MNEM	SBB
	MNEM	AND
	MNEM	SUB
	MNEM	XOR
	MNEM	CMP
	MNEM	ROL			; 08h-0Fh: group 2
	MNEM	ROR
	MNEM	RCL
	MNEM	RCR
	MNEM	SHL
	MNEM	SHR
	MNEM	???,BAD
	MNEM	SAR
	MNEM	JO			; 10h-1Fh: opcodes 70h-7Fh
	MNEM	JNO
	MNEM	JB
	MNEM	JNB
	MNEM	JZ
	MNEM	JNZ
	MNEM	JBE
	MNEM	JA
	MNEM	JS
	MNEM	JNS
	MNEM	JPE
	MNEM	JPO
	MNEM	JL
	MNEM	JGE
	MNEM	JLE
	MNEM	JG
	MNEM	INC			; 20h-23h: opcodes 40h-5Fh
	MNEM	DEC
	MNEM	PUSH
	MNEM	POP
	MNEM	DAA			; 24h-27h: opcodes 27h-3Fh
	MNEM	DAS
	MNEM	AAA
	MNEM	AAS
	MNEM	MOVS			; 28h-2Eh: B or W is appended
	MNEM	CMPS
	MNEM	STOS
	MNEM	LODS
	MNEM	SCAS
	MNEM	INS
	MNEM	OUTS
	MNEM	CALL			; 2Fh-35h: P steps over these
	MNEM	<INT 3>,INT3
	MNEM	INT
	MNEM	INTO
	MNEM	LOOPNZ
	MNEM	LOOPZ
	MNEM	LOOP
	MNEM	<BYTE PTR>,BYTE		; (see op_e)
	MNEM	<WORD PTR>,WORD
	MNEM	FAR
	MNEM	TEST
	MNEM	NOT
	MNEM	NEG
	MNEM	MUL
	MNEM	IMUL
	MNEM	DIV
	MNEM	IDIV
	MNEM	JMP
	MNEM	XCHG
	MNEM	MOV
	MNEM	LEA
	MNEM	NOP
	MNEM	CBW
	MNEM	CWD
	MNEM	WAIT
	MNEM	PUSHF
	MNEM	POPF
	MNEM	SAHF
	MNEM	LAHF
	MNEM	RET
	MNEM	RETF
	MNEM	LES
	MNEM	LDS
	MNEM	IRET
	MNEM	AAM
	MNEM	AAD
	MNEM	XLAT
	MNEM	ESC
	MNEM	JCXZ
	MNEM	IN
	MNEM	OUT
	MNEM	LOCK
	MNEM	REPNZ
	MNEM	REPZ
	MNEM	HLT
	MNEM	CMC
	MNEM	CLC
	MNEM	STC
	MNEM	CLI
	MNEM	STI
	MNEM	CLD
	MNEM	STD
	MNEM	PUSHA			; 80286
	MNEM	POPA
	MNEM	BOUND
	MNEM	ARPL
	MNEM	ENTER
	MNEM	LEAVE
	MNEM	SLDT			; group 6
	MNEM	STR
	MNEM	LLDT
	MNEM	LTR
	MNEM	VERR
	MNEM	VERW
	MNEM	SGDT			; group 7
	MNEM	SIDT
	MNEM	LGDT
	MNEM	LIDT
	MNEM	SMSW
	MNEM	LMSW
	MNEM	LAR
	MNEM	LSL
	MNEM	CLTS
	IF	_MN GT 78h
	ERROR	<Too many mnemonics>
	ENDIF
;
; Operand types, one per nibble (first operand in the high nibble), each
; indexing OPND_TAB (0 means none):
;
;	1: ModRM r/m	5: reg in opcode   9: imm16	D: [addr]
;	2: ModRM reg	6: imm		   A: rel8	E: DX
;	3: segment reg	7: signed imm8	   B: rel16	F: 1 or CL
;	4: AL or AX	8: imm8		   C: seg:off
;
; Sizes come from bit 0 of the opcode, unless the operands say otherwise.
;
	DEFLBL	OPND_TAB,word
	dw	op_e, op_g, op_s, op_a, op_z, op_i, op_sib, op_ib
	dw	op_iw, op_j8, op_j16, op_ap, op_o, op_dx, op_shift
;
; Groups 3 through 7 (mnemonics for each ModRM reg); bit 7 means "far".
;
	DEFLBL	GRPS,byte
	db	M_TEST,M_BAD,M_NOT,M_NEG,M_MUL,M_IMUL,M_DIV,M_IDIV
	db	M_INC,M_DEC,M_BAD,M_BAD,M_BAD,M_BAD,M_BAD,M_BAD
	db	M_INC,M_DEC,M_CALL,M_CALL+80h,M_JMP,M_JMP+80h,M_PUSH,M_BAD
	db	M_SLDT,M_STR,M_LLDT,M_LTR,M_VERR,M_VERW,M_BAD,M_BAD
	db	M_SGDT,M_SIDT,M_LGDT,M_LIDT,M_SMSW,M_BAD,M_LMSW,M_BAD
;
; Opcodes 60h-FFh: mnemonic (or group) and operand types; operand type FFh
; marks a prefix.  On an 8086 or 8088, set_cpu changes some of them.
;
G1	equ	78h
G2	equ	79h
G3	equ	7Ah
G4	equ	7Bh
G5	equ	7Ch
G6	equ	7Dh
G7	equ	7Eh
	DEFLBL	OPTAB,byte
	db	M_PUSHA,0, M_POPA,0, M_BOUND+80h,21h, M_ARPL,12h	; 60h
	db	4 dup (M_BAD,0)
	db	M_PUSH,90h, M_IMUL,21h, M_PUSH,70h, M_IMUL,21h	; 68h
	db	M_INS,0, M_INS,0, M_OUTS,0, M_OUTS,0
	IRP	j,<JO,JNO,JB,JNB,JZ,JNZ,JBE,JA>			; 70h
	db	M_&j,0A0h
	ENDM
	IRP	j,<JS,JNS,JPE,JPO,JL,JGE,JLE,JG>			; 78h
	db	M_&j,0A0h
	ENDM
	db	G1,16h, G1,16h, G1,16h, G1,17h			; 80h
	db	M_TEST,12h, M_TEST,12h, M_XCHG,21h, M_XCHG,21h
	db	M_MOV,12h, M_MOV,12h, M_MOV,21h, M_MOV,21h	; 88h
	db	M_MOV+80h,13h, M_LEA,21h, M_MOV+80h,31h, M_POP,10h
	db	M_NOP,0, 7 dup (M_XCHG+80h,45h)			; 90h
	db	M_CBW,0, M_CWD,0, M_CALL,0C0h, M_WAIT,0		; 98h
	db	M_PUSHF,0, M_POPF,0, M_SAHF,0, M_LAHF,0
	db	M_MOV,4Dh, M_MOV,4Dh, M_MOV,0D4h, M_MOV,0D4h	; A0h
	db	M_MOVS,0, M_MOVS,0, M_CMPS,0, M_CMPS,0
	db	M_TEST,46h, M_TEST,46h, M_STOS,0, M_STOS,0	; A8h
	db	M_LODS,0, M_LODS,0, M_SCAS,0, M_SCAS,0
	db	16 dup (M_MOV,56h)				; B0h
	db	G2,18h, G2,18h, M_RET,90h, M_RET,0		; C0h
	db	M_LES+80h,21h, M_LDS,21h, M_MOV,16h, M_MOV,16h
	db	M_ENTER,98h, M_LEAVE,0, M_RETF,90h, M_RETF,0	; C8h
	db	M_INT3,0, M_INT,80h, M_INTO,0, M_IRET,0
	db	G2,1Fh, G2,1Fh, G2,1Fh, G2,1Fh			; D0h
	db	M_AAM,80h, M_AAD,80h, M_BAD,0, M_XLAT,0
	db	8 dup (M_ESC,10h)				; D8h
	db	M_LOOPNZ,0A0h, M_LOOPZ,0A0h, M_LOOP,0A0h	; E0h
	db	M_JCXZ,0A0h
	db	M_IN,48h, M_IN,48h, M_OUT,84h, M_OUT,84h
	db	M_CALL,0B0h, M_JMP,0B0h, M_JMP,0C0h, M_JMP,0A0h	; E8h
	db	M_IN,4Eh, M_IN,4Eh, M_OUT,0E4h, M_OUT,0E4h
	db	M_LOCK,0FFh, M_BAD,0, M_REPNZ,0FFh, M_REPZ,0FFh	; F0h
	db	M_HLT,0, M_CMC,0, G3,10h, G3,10h
	db	M_CLC,0, M_STC,0, M_CLI,0, M_STI,0		; F8h
	db	M_CLD,0, M_STD,0, G4,10h, G5,10h
;
; Opcodes 0Fh 00h-06h (the 80286's two-byte opcodes, whose sizes are fixed,
; so op_e never displays one), with LOADALL (05h) left out.
;
	DEFLBL	OPTAB_0F,byte
	db	G6,10h, G7,10h, M_LAR,21h, M_LSL,21h, M_BAD,0, M_BAD,0
	db	M_CLTS,0

	DEFLBL	ALU_OPS,byte		; operands of ALU opcodes 00h-3Fh
	db	12h,21h,46h
;
; ModRM r/m (when mod isn't 3): base and index register names (as in
; REGNAMES, with index 0 meaning none).
;
	DEFLBL	RMTAB,byte
	db	0EBh,0FBh,0EDh,0FDh,0Eh,0Fh,0Dh,0Bh

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dis_line
;
; Display the address, bytes, and disassembly of an instruction, followed by
; a tab and the string that follows it, if any (see skip_fmt), or at CS:IP,
; if it has a memory operand, by a tab and the operand's address (eg, "; EA =
; 0070:0123"), in the current mode (see ea_start).
;
; Inputs:
;	mem_seg:DI -> instruction
;
; Outputs:
;	DI -> next instruction
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	dis_line
	push	bx
	push	dx
	push	di
	call	next_insn
	pop	si			; SI -> instruction
	mov	cx,di
	sub	cx,si			; CX = length
	mov	di,si
	call	hex_addr
dl1:	call	fetch
	call	hex_byte
	loop	dl1
	mov	di,si
	mov	ah,24
	call	pad
	push	di
	call	decode
	call	skip_fmt
	pop	ax			; AX -> instruction
	push	di			; (DI -> next instruction)
	cmp	[ea_seg],0		; a memory operand?
	je	dl8			; no
	xchg	di,ax
	call	at_ip			; is it CS:IP?
	jne	dl8			; no
	mov	si,offset EA_MSG
	call	put_string
	push	[mem_seg]
	mov	al,[mem_mode]
	push	ax
	call	ip_mem			; (for the current mode)
	mov	al,[ea_seg]
	call	reg_val
	mov	[mem_seg],ax
	mov	di,[ea_off]
	call	hex_addr
	pop	ax
	mov	[mem_mode],al
	pop	[mem_seg]
dl8:	pop	di
	pop	dx
	pop	bx
	jmp	newline
ENDPROC	dis_line

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; next_insn, next_skip
;
; Find the next instruction, by decoding this one with the output muted (and
; col unchanged); next_skip also skips any string that follows it (see
; skip_fmt).
;
; Inputs:
;	mem_seg:DI -> instruction
;
; Outputs:
;	DI -> next instruction
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	next_skip
	stc
	jmp	short ni1
ENDPROC	next_skip

DEFPROC	next_insn
	clc
ni1:	mov	al,[col]
	push	ax
	inc	[mute]
	pushf
	call	decode
	popf				; skipping any string, too?
	jnc	ni2			; no
	call	skip_fmt
ni2:	dec	[mute]
	pop	ax
	mov	[col],al
	ret
ENDPROC	next_insn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_over
;
; P steps over a CALL, INT, LOOP (or LOOPZ or LOOPNZ), or string instruction
; with a REP prefix (REPNZ or REPZ), and traces any other instruction; the
; next instruction follows any string after the instruction (see chk_fmt).
;
; Inputs:
;	mem_seg:DI -> instruction (at CS:IP)
;
; Outputs:
;	DI -> next instruction; carry set to step over the instruction
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	chk_over
	call	next_skip
	mov	al,[mnemonic]
	sub	al,M_MOVS
	cmp	al,M_LOOP+1-M_MOVS	; a string op, CALL, INT, or LOOP?
	jae	co9			; no (carry clear)
	cmp	al,M_CALL-M_MOVS	; CALL, INT, or LOOP?
	cmc
	jc	co9			; yes
	cmp	[pfx],M_REPNZ		; a string op with REPNZ or REPZ?
	cmc				; (carry set if so)
co9:	ret
ENDPROC	chk_over

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; decode
;
; Display an 80286 instruction (prefixes, mnemonic, and operands), or on an
; 8086 or 8088, an instruction as it runs there (see set_cpu).  A segment
; override is displayed with the memory operand (or after the instruction,
; if there isn't one).  The mnemonic, the last LOCK or REP prefix, and any
; memory operand's address are recorded, too (in mnemonic, pfx, ea_seg, and
; ea_off).
;
; Inputs:
;	mem_seg:DI -> instruction
;
; Outputs:
;	DI -> next instruction
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	decode
	sub	ax,ax
	mov	word ptr [seg_ovr],ax	; (and ea_seg)
	mov	[ea_off],ax
	mov	word ptr [pfx],ax	; (and fmt_str)
dc1:	call	fetch
	mov	[opcode],al
	mov	[modrm],al		; (see op_s and op_z)
	mov	ah,al
	and	ah,1
	mov	[wbit],ah
	cmp	al,60h			; one of OPTAB's?
	jb	dc2			; no
	mov	bl,al
	mov	bh,0
	shl	bx,1
	mov	dx,word ptr OPTAB[bx-0C0h]
	cmp	dh,0FFh			; prefix?
	jne	dc6			; no
	mov	al,dl
	mov	[pfx],al
	call	put_mnem
	call	space
	jmp	dc1
;
; Opcodes 00h-5Fh are decoded from their bits.
;
dc2:	mov	bl,al
	and	bx,7			; BX = opcode bits 0-2
	mov	ah,al
	mov	cl,3
	shr	ah,cl			; AH = opcode bits 3-6
	cmp	al,40h
	jae	dc4
	cmp	bl,6			; ALU op?
	jae	dc3			; no
	mov	dl,ah
	shr	bl,1
	mov	dh,ALU_OPS[bx]
	jmp	short dc6
dc3:	and	ah,3
	cmp	al,20h			; PUSH or POP segment?
	jae	dc3a			; no
	DEFLBL	dc_0f			; (set_cpu changes this on an 8086)
	cmp	al,0Fh			; 80286 two-byte opcode?
	je	dc5			; yes
	lea	dx,[bx+3000h+M_PUSH-6]
	jmp	short dc8		; (there's no ModRM)
dc3a:	cmp	bl,7			; DAA, DAS, AAA, or AAS?
	je	dc3b			; yes
	add	ah,16
	mov	[seg_ovr],ah
	jmp	dc1
dc3b:	mov	dx,M_DAA
	add	dl,ah
	jmp	short dc6
dc5:	call	fetch			; AL = second opcode byte
	cmp	al,7			; one of OPTAB_0F's?
	jb	dc5a			; yes
	mov	al,4			; no, so use an undefined one
dc5a:	cbw
	shl	ax,1
	xchg	bx,ax
	mov	dx,word ptr OPTAB_0F[bx]
	jmp	short dc6
dc4:	and	ah,3			; INC, DEC, PUSH, or POP
	mov	dx,5000h+M_INC
	add	dl,ah
;
; DL = mnemonic (or group), and DH = operand types.
;
dc6:	test	dl,dl			; word operands?
	jns	dc6a			; no
	mov	[wbit],1
	and	dl,7Fh
dc6a:	mov	al,dh
	sub	al,10h
	cmp	al,30h			; is the first operand E, G, or S?
	jae	dc8			; no, so there's no ModRM
	call	fetch
	mov	[modrm],al
	cmp	dl,G1			; group?
	jb	dc8			; no
	mov	cl,3
	shr	al,cl
	and	ax,7			; AX = ModRM reg
	sub	dl,G1
	shl	dl,cl
	add	al,dl
	mov	dl,al
	cmp	al,16			; group 1 or 2?
	jb	dc8			; yes (the mnemonic is AL)
	xchg	bx,ax
	mov	dl,GRPS[bx-16]
	test	dl,dl			; far?
	jns	dc7			; no
	mov	[wbit],2
	and	dl,7Fh
dc7:	cmp	dl,M_TEST		; TEST has an immediate operand, too
	jne	dc8
	mov	dh,16h

dc8:	mov	[opnds],dh
	mov	al,dl
	mov	[mnemonic],al
	call	put_mnem
	sub	dl,M_MOVS		; string instruction?
	cmp	dl,M_CALL-M_MOVS
	jae	dc9			; no
	mov	al,'B'
	cmp	[wbit],0
	je	dc8a
	mov	al,'W'
dc8a:	call	put_char
dc9:	mov	al,[opnds]
	test	al,al
	jz	dc10
	mov	ah,32
	call	pad
	mov	al,[opcode]
	xor	al,0D8h
	cmp	al,8			; ESC?
	jae	dc9a			; no
	mov	cl,3			; display its code (opcode bits 0-2,
	shl	al,cl			; then ModRM reg)
	mov	ah,[modrm]
	shr	ah,cl
	and	ah,7
	or	al,ah
	call	hex_byte
	mov	al,','
	call	put_char
dc9a:	mov	al,[opnds]
	mov	cl,4
	shr	al,cl
	call	put_opnd
	mov	al,[opnds]
	and	al,0Fh
	jz	dc10
	call	dc12			; the second operand
	mov	al,[opcode]
	xor	al,69h
	test	al,0FDh			; IMUL reg,r/m,imm (69h or 6Bh)?
	jnz	dc10			; no
	neg	al
	add	al,9			; AL = 9 (imm16) or 7 (signed imm8)
	call	dc12			; the third operand
dc10:	cmp	[ea_seg],0		; a memory operand?
	jne	dc11			; yes (so any override was displayed)
	cmp	[seg_ovr],0		; unused segment override?
	je	dc11			; no
	call	space
	jmp	put_seg
dc11:	cmp	[opcode],0CDh		; INT n?
	je	chk_fmt			; yes
	ret
dc12:	push	ax
	mov	al,','
	call	put_char
	pop	ax
	jmp	put_opnd
ENDPROC	decode
;
; chk_fmt
;
; The INT_DOSUTIL functions DOS_UTL_PRINTF through DOS_UTL_SPRINTF return after
; the null-terminated string that follows the INT (see CCALL), so after an INT
; n, decode comes here to set fmt_str if it's one of them: its function is the
; saved AH if the INT is at CS:IP, or else the MOV AH,imm8 just before it (as
; DOSUTIL makes), if any.
;
; Inputs:
;	mem_seg:DI -> the byte after INT n
;
; Modifies:
;	AX, BX
;
DEFPROC	chk_fmt
	dec	di
	call	fetch			; AL = n
	cmp	al,INT_DOSUTIL		; a DOS utility function?
	jne	cf9			; no
	dec	di
	dec	di			; DI -> the INT
	call	at_ip			; is it at CS:IP?
	jne	cf1			; no
	mov	al,8			; (AX, as in REGNAMES)
	call	reg_val			; AH = the function
	jmp	short cf2
cf1:	dec	di
	dec	di
	call	fetch_word		; AX = the two bytes before the INT
	cmp	al,0B4h			; MOV AH,imm8 (with AH = the function)?
	jne	cf8			; no
cf2:	sub	ah,DOS_UTL_PRINTF
	cmp	ah,DOS_UTL_SPRINTF-DOS_UTL_PRINTF
	ja	cf8			; not one with a string after the INT
	inc	[fmt_str]
cf8:	inc	di
	inc	di			; DI -> the byte after the INT again
cf9:	ret
ENDPROC	chk_fmt

;
; skip_fmt
;
; If a string follows the instruction (see chk_fmt), display a tab, "; ", and
; the string in quotes, with \r, \n, \t, or \xNN for any other character that
; isn't printable, and skip it.
;
; Inputs:
;	mem_seg:DI -> the byte after the instruction
;
; Outputs:
;	DI -> the byte after its string, if any
;
; Modifies:
;	AX, SI
;
DEFPROC	skip_fmt
	cmp	[fmt_str],0		; a string?
	je	sf9			; no
	mov	si,offset FMT_MSG
	call	put_string		; tab, "; ", and the opening quote
sf1:	call	fetch
	jc	sf8			; (the address isn't valid)
	test	al,al			; end of the string?
	jz	sf8			; yes
	cmp	al,' '			; a control character?
	jb	sf2			; yes
	cmp	al,7Fh			; or DEL or above?
	jb	sf5			; no
sf2:	mov	ah,al
	mov	al,'\'
	call	put_char
	mov	al,'r'
	cmp	ah,CHR_RETURN
	je	sf5
	mov	al,'n'
	cmp	ah,CHR_LINEFEED
	je	sf5
	mov	al,'t'
	cmp	ah,CHR_TAB
	je	sf5
	mov	al,'x'
	call	put_char
	mov	al,ah
	call	hex_byte
	jmp	sf1
sf5:	call	put_char
	jmp	sf1
sf8:	mov	al,'"'
	jmp	put_char		; the closing quote
sf9:	ret
ENDPROC	skip_fmt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_mnem
;
; Inputs:
;	AL = mnemonic index
;
; Modifies:
;	AX, SI
;
DEFPROC	put_mnem
	mov	si,offset MNEMS
	mov	ah,al
pm1:	dec	ah
	js	pm3
pm2:	lodsb
	test	al,al
	jns	pm2
	jmp	pm1
pm3:	lodsb
	mov	ah,al
	and	al,7Fh
	call	put_char
	test	ah,ah
	jns	pm3
	ret
ENDPROC	put_mnem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_seg
;
; Display the segment override, if any.
;
; Modifies:
;	AX, BX
;
DEFPROC	put_seg
	mov	al,[seg_ovr]
	test	al,al
	jz	psg9
	call	put_reg
	mov	al,':'
	jmp	put_char
psg9:	ret
ENDPROC	put_seg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_opnd
;
; Display an operand (and fetch any bytes it needs).
;
; Inputs:
;	AL = operand type (1-15; see OPND_TAB)
;
; Modifies:
;	AX, BX, CX, SI, DI
;
DEFPROC	put_opnd
	cbw
	shl	ax,1
	xchg	bx,ax
	jmp	OPND_TAB[bx-2]

op_e:	mov	al,[modrm]
	cmp	al,0C0h			; register?
	jb	oe1			; no
oe0:	and	al,7
op_reg:	mov	ah,[wbit]		; AL = register 0-7, sized by wbit
	mov	cl,3
	shl	ah,cl
	add	al,ah
	jmp	put_reg
;
; Display the size of a memory operand, unless there's a register operand,
; or it's ESC.
;
oe1:	mov	al,[opnds]
	and	al,0EEh
	cmp	al,02h			; is the other operand G or S?
	je	oe2			; yes
	cmp	al,20h			; likewise
	je	oe2
	mov	al,[opcode]
	cmp	al,0Fh			; 80286 two-byte opcode?
	je	oe2			; yes
	and	al,0F8h
	cmp	al,0D8h			; ESC?
	je	oe2			; yes
	mov	al,M_BYTE
	add	al,[wbit]
	call	put_mnem
	call	space
oe2:	call	ea_start
	mov	al,[modrm]
	and	al,0C7h
	cmp	al,06h			; direct address?
	je	oe_dir			; yes
	and	ax,7
	xchg	bx,ax
	mov	al,RMTAB[bx]
	push	ax
	and	al,0Fh
	call	ea_reg			; base register
	pop	ax
	mov	cl,4
	shr	al,cl
	jz	oe3
	push	ax
	mov	al,'+'
	call	put_char
	pop	ax
	call	ea_reg			; index register
oe3:	mov	al,[modrm]
	test	al,40h			; 8-bit displacement?
	jnz	oe4			; yes
	test	al,al			; 16-bit displacement?
	jns	oe_end			; no
	mov	al,'+'
	call	put_char
	jmp	short oe_dir
oe4:	call	fetch
	cbw
	add	[ea_off],ax
	call	put_sbyte
	jmp	short oe_end

op_o:	call	ea_start
oe_dir:	call	fetch_word
	add	[ea_off],ax
	call	hex_word
oe_end:	mov	al,']'
	jmp	put_char
;
; ea_start begins a memory operand: it records the operand's segment (the
; override, or DS) in ea_seg, and displays any override and the bracket;
; ea_reg displays a base or index register (AL, as in REGNAMES), and adds
; its value to ea_off (BP makes SS the segment, unless there's an override).
;
ea_start:
	mov	al,[seg_ovr]
	test	al,al			; an override?
	jnz	es1			; yes
	mov	al,19			; no, so DS
es1:	mov	[ea_seg],al
	call	put_seg
	mov	al,'['
	jmp	put_char

ea_reg:	push	ax
	call	put_reg
	pop	ax
	cmp	al,13			; BP?
	jne	er1			; no
	cmp	[seg_ovr],0		; an override?
	jne	er1			; yes
	mov	[ea_seg],18		; no, so SS
er1:	call	reg_val
	add	[ea_off],ax
	ret

op_g:	mov	al,[modrm]
	mov	cl,3
	shr	al,cl
	jmp	oe0

op_s:	mov	al,[modrm]
	mov	cl,3
	shr	al,cl
	and	al,3
	add	al,16
	jmp	put_reg

op_a:	mov	al,0
	jmp	op_reg

op_z:	mov	al,[opcode]
	mov	ah,al
	and	ah,0F8h
	cmp	ah,0B0h			; MOV reg8,imm8?
	mov	ah,0
	je	oz1			; yes
	inc	ah
oz1:	mov	[wbit],ah
	jmp	oe0

op_i:	cmp	[wbit],0
	jne	op_iw
op_ib:	call	fetch
	jmp	hex_byte
op_iw:	call	fetch_word
	jmp	hex_word

op_sib:	call	fetch
	jmp	put_sbyte

op_j8:	call	fetch
	cbw
	jmp	short oj1
op_j16:	call	fetch_word
oj1:	add	ax,di
	jmp	hex_word

op_ap:	call	fetch_word
	push	ax
	call	fetch_word
	call	hex_word
	mov	al,':'
	call	put_char
	pop	ax
	jmp	hex_word

op_dx:	mov	al,10
	jmp	put_reg

op_shift:
	mov	al,1			; CL
	test	[opcode],2
	jnz	os1
	mov	al,'1'
	jmp	put_char
os1:	jmp	put_reg
ENDPROC	put_opnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_sbyte
;
; Inputs:
;	AL = signed byte (displayed as +XX or -XX)
;
; Modifies:
;	AX
;
DEFPROC	put_sbyte
	mov	ah,'+'
	test	al,al
	jns	psb1
	neg	al
	mov	ah,'-'
psb1:	xchg	al,ah
	call	put_char
	xchg	al,ah
	jmp	hex_byte
ENDPROC	put_sbyte

CODE	ends

	end
