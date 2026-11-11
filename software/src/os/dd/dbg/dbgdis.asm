;
; BASIC-DOS Loadable Serial Debugger (Disassembler)
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The 80386 (and 80286 and 8086) disassembler for U, BL, and the instruction
; at CS:IP (see dis_line), and P's test for instructions to step over (see
; chk_over).  It's resident, like dbgdev.asm, which LINK puts first, and it's
; a module of its own only for MASM's symbol space (its mnemonics alone
; define about 140 equates).
;
	DOSFUNC equ 1
	include	macros.inc
	include	devapi.inc
	include	dosapi.inc

CODE	segment word public 'CODE'

	EXTNEAR	<at_ip,fetch,fetch_word,hex_addr,hex_byte,hex_word,ip_mem>
	EXTNEAR	<newline,pad,put_2ch,put_char,put_reg,put_string,reg_val>
	EXTNEAR	<space>
	EXTBYTE	<col,mem_mode,mute>
	EXTWORD	<mem_seg>

	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING

;
; Disassembler state (see decode).
;
	DEFBYTE	opcode,0
	DEFBYTE	opcode2,0		; the byte after 0Fh (see oe1)
	DEFBYTE	modrm,0			; ModRM byte (or opcode, if none)
	DEFBYTE	wbit,0			; 0 (byte), 1 (word), or 2 (far)
	DEFBYTE	sz,0			; SZ_* prefixes (66h and 67h)
	DEFBYTE	opnds,0			; operand types (see OPND_TAB)
	DEFBYTE	mnemonic,0		; MNEMS index (see chk_over)
	DEFBYTE	pfx,0			; last LOCK or REP prefix (or 0)
	DEFBYTE	fmt_str,0		; 1 if a string follows (see chk_fmt)
	DEFBYTE	seg_ovr,0		; segment override (as in REGNAMES)
	DEFBYTE	ea_seg,0		; memory operand's segment, likewise
	DEFWORD	ea_off,0		; and its offset (see ea_start)

SZ_OP	equ	01h			; 66h: 32-bit operands (dwords)
SZ_ADDR	equ	02h			; 67h: 32-bit addressing

	DEFLBL	EA_MSG,byte
	db	9,"; EA = ",0
	DEFLBL	FMT_MSG,byte
	db	9,'; "',0
;
; Mnemonics, each with bit 7 set in its last character, and an M_ equate
; with its index (see put_mnem).  In OPTAB, bit 7 of an index means "word",
; and indexes 78h-7Fh are groups (see decode), so OPTAB's mnemonics must be
; below 78h, and those in GRPS (where bit 7 means "far") below 80h; the rest
; (from OPTAB_0F, where 78h-7Fh are also groups, or used only by code) can
; be anywhere else.
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
	MNEM	JNO			; (and 0Fh 80h-8Fh; see dc5j)
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
	MNEM	PUSHA			; D is appended for dwords (see dc8)
	MNEM	POPA
	MNEM	PUSHF
	MNEM	POPF
	MNEM	IRET
	MNEM	MOVS			; B, W, or D is appended
	MNEM	CMPS
	MNEM	STOS
	MNEM	LODS
	MNEM	SCAS
	MNEM	INS
	MNEM	OUTS
	MNEM	CALL			; P steps over these
	MNEM	<INT 3>,INT3
	MNEM	INT
	MNEM	INTO
	MNEM	LOOPNZ
	MNEM	LOOPZ
	MNEM	LOOP
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
	MNEM	WAIT
	MNEM	SAHF
	MNEM	LAHF
	MNEM	RET
	MNEM	RETF
	MNEM	LES
	MNEM	LDS
	MNEM	AAM
	MNEM	AAD
	MNEM	XLAT
	MNEM	ESC
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
	MNEM	DAA			; opcodes 27h-3Fh
	MNEM	DAS
	MNEM	AAA
	MNEM	AAS
	MNEM	BOUND			; 80286
	MNEM	ARPL
	MNEM	ENTER
	MNEM	LEAVE
	MNEM	BT			; 80386 (in GRPS and OPTAB_0F)
	MNEM	BTS
	MNEM	BTR
	MNEM	BTC
	MNEM	CBW			; these 3, with a 32-bit prefix,
	MNEM	CWD			; become the next 3 (see dc8)
	MNEM	JCXZ
	IF	M_JCXZ GE 78h
	ERROR	<Too many OPTAB mnemonics>
	ENDIF
	MNEM	CWDE
	MNEM	CDQ
	MNEM	JECXZ
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
	MNEM	<BYTE PTR>,BYTE		; (see oe1)
	MNEM	<WORD PTR>,WORD
	MNEM	FAR
	MNEM	SET			; (see dc8)
	IF	_MN GT 80h
	ERROR	<Too many GRPS mnemonics>
	ENDIF
	REPT	80h-_MN			; (unused)
	db	'?' OR 80h
	ENDM
_MN = 80h
	MNEM	LAR			; OPTAB_0F only
	MNEM	LSL
	MNEM	CLTS
	MNEM	SHLD
	MNEM	SHRD
	MNEM	LSS
	MNEM	LFS
	MNEM	LGS
	MNEM	MOVZX
	MNEM	MOVSX
	MNEM	BSF
	MNEM	BSR
;
; SETcc isn't in MNEMS: its "index" is M_SETO plus the condition (0-0Fh), and
; it's displayed as SET and the matching Jcc without its J (see dc8).
;
M_SETO	equ	0F0h
	IF	_MN GT M_SETO
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
; After 0Fh, C-F have other meanings (none of those operands occur there):
;
;	C: CRn, DRn, or TRn (ModRM reg)	   E: ModRM reg, and imm8 or CL
;	D: byte or word ModRM r/m	   F: 32-bit register (ModRM r/m)
;
; Sizes come from bit 0 of the opcode, unless the operands say otherwise;
; with a 66h prefix, words (and rel16 and imm16, except for 9) are dwords.
;
	DEFLBL	OPND_TAB,word
	dw	op_e, op_g, op_s, op_a, op_z, op_i, op_sib, op_ib
	dw	op_iw, op_j8, op_j16, op_ap, op_o, op_dx, op_shift
	dw	op_sr, op_ex, op_gx, op_r32
;
; Groups 3 through 8 (mnemonics for each ModRM reg); bit 7 means "far".
;
	DEFLBL	GRPS,byte
	db	M_TEST,M_BAD,M_NOT,M_NEG,M_MUL,M_IMUL,M_DIV,M_IDIV
	db	M_INC,M_DEC,M_BAD,M_BAD,M_BAD,M_BAD,M_BAD,M_BAD
	db	M_INC,M_DEC,M_CALL,M_CALL+80h,M_JMP,M_JMP+80h,M_PUSH,M_BAD
	db	M_SLDT,M_STR,M_LLDT,M_LTR,M_VERR,M_VERW,M_BAD,M_BAD
	db	M_SGDT,M_SIDT,M_LGDT,M_LIDT,M_SMSW,M_BAD,M_LMSW,M_BAD
	db	M_BAD,M_BAD,M_BAD,M_BAD,M_BT,M_BTS,M_BTR,M_BTC
;
; Opcodes 60h-FFh: mnemonic (or group) and operand types; operand types
; PFX_SEG, PFX_SIZE, and PFX_REP mark prefixes: a segment register (FS or GS),
; SZ_* bits, or a mnemonic.  On an 8086 or 8088 (or 80286), set_cpu changes
; some of them.
;
G1	equ	78h
G2	equ	79h
G3	equ	7Ah
G4	equ	7Bh
G5	equ	7Ch
G6	equ	7Dh
G7	equ	7Eh
G8	equ	7Fh
PFX_SEG	equ	0FDh
PFX_SIZE equ	0FEh
PFX_REP	equ	0FFh
	DEFLBL	OPTAB,byte
	db	M_PUSHA+80h,0, M_POPA,0, M_BOUND+80h,21h, M_ARPL,12h	; 60h
	db	20,PFX_SEG, 21,PFX_SEG, SZ_OP,PFX_SIZE, SZ_ADDR,PFX_SIZE
	db	M_PUSH+80h,60h, M_IMUL,21h, M_PUSH,70h, M_IMUL,21h	; 68h
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
	db	M_PUSHF+80h,0, M_POPF,0, M_SAHF,0, M_LAHF,0
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
	db	M_LOCK,PFX_REP, M_BAD,0, M_REPNZ,PFX_REP, M_REPZ,PFX_REP ; F0h
	db	M_HLT,0, M_CMC,0, G3,10h, G3,10h
	db	M_CLC,0, M_STC,0, M_CLI,0, M_STI,0		; F8h
	db	M_CLD,0, M_STD,0, G4,10h, G5,10h
;
; Opcodes 0Fh 00h-07h (the 80286's two-byte opcodes, whose sizes are fixed,
; so op_e never displays one), with LOADALL (05h) left out, and 0Fh A0h-BFh
; (the 80386's, except PUSH and POP FS and GS; see dc5f).  Other 80386
; two-byte opcodes (MOV with CRn, DRn, or TRn, Jcc, and SETcc) are decoded
; from their bits.
;
	DEFLBL	OPTAB_0F,byte
	db	G6,10h, G7,10h, M_LAR,21h, M_LSL,21h		; 00h
	db	M_BAD,0, M_BAD,0, M_CLTS,0, M_BAD,0
	db	M_BAD,0, M_BAD,0, M_BAD,0, M_BT,12h		; A0h
	db	M_SHLD,1Eh, M_SHLD,1Eh, M_BAD,0, M_BAD,0
	db	M_BAD,0, M_BAD,0, M_BAD,0, M_BTS,12h		; A8h
	db	M_SHRD,1Eh, M_SHRD,1Eh, M_BAD,0, M_IMUL,21h
	db	M_BAD,0, M_BAD,0, M_LSS,21h, M_BTR,12h		; B0h
	db	M_LFS,21h, M_LGS,21h, M_MOVZX,2Dh, M_MOVZX,2Dh
	db	M_BAD,0, M_BAD,0, G8,18h, M_BTC,12h		; B8h
	db	M_BSF,21h, M_BSR,21h, M_MOVSX,2Dh, M_MOVSX,2Dh

	DEFLBL	ALU_OPS,byte		; operands of ALU opcodes 00h-3Fh
	db	12h,21h,46h
;
; ModRM r/m (when mod isn't 3), with 16-bit addressing: base and index
; register names (as in REGNAMES, with index 0 meaning none).
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
	cmp	[ea_seg],20		; with FS or GS (which aren't saved)?
	jae	dl8			; yes
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
; Display an 80386 instruction (prefixes, mnemonic, and operands), or on an
; 8086, 8088, or 80286, an instruction as it runs there (see set_cpu).  A
; segment override is displayed with the memory operand (or after the
; instruction, if there isn't one), and 66h and 67h prefixes only change
; sizes (eg, AX to EAX, or [BX] to [EBX]), as if in a 16-bit code segment.
; The mnemonic, the last LOCK or REP prefix, and any memory operand's address
; are recorded, too (in mnemonic, pfx, ea_seg, and ea_off).
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
	mov	[sz],al
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
	cmp	dh,PFX_SEG		; prefix?
	jb	dc6			; no
	mov	ah,dl
	je	dc3s			; FS or GS
	cmp	dh,PFX_SIZE		; operand or address size?
	jne	dc1a			; no, LOCK or REP
	or	[sz],dl
	jmp	dc1
dc1a:	mov	al,dl
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
	cmp	al,0Fh			; two-byte opcode?
	je	dc5			; yes
	lea	dx,[bx+3000h+M_PUSH-6]
	jmp	short dc8		; (there's no ModRM)
dc3a:	cmp	bl,7			; DAA, DAS, AAA, or AAS?
	je	dc3b			; yes
	add	ah,16
dc3s:	mov	[seg_ovr],ah
	jmp	dc1
dc3b:	mov	dx,M_DAA
	add	dl,ah
	jmp	short dc6
dc5:	jmp	dc0f
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
	cmp	dl,G1			; group (78h-7Fh, not 80h and up)?
	jl	dc8			; no
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
	sub	al,M_CBW
	cmp	al,3			; CBW, CWD, or JCXZ?
	jae	dc8a			; no
	shr	al,1
	inc	ax			; AL = SZ_OP (or for JCXZ, SZ_ADDR)
	test	[sz],al			; 32-bit?
	jz	dc8a			; no
	add	dl,M_CWDE-M_CBW		; yes, so CWDE, CDQ, or JECXZ
dc8a:	mov	al,dl
	mov	[mnemonic],al
	mov	cl,0
	cmp	al,M_SETO		; SETcc?
	jb	dc8b			; no
	mov	al,M_SET
	call	put_mnem
	mov	al,dl
	sub	al,M_SETO-M_JO		; AL = the matching Jcc
	mov	cl,1			; (without its J)
dc8b:	call	put_mnemx
	sub	dl,M_PUSHA		; PUSHA through IRET, or a string op?
	cmp	dl,M_CALL-M_PUSHA
	jae	dc9			; no
	call	chk_dw			; dwords?
	mov	al,'D'
	jc	dc8c			; yes
	cmp	dl,M_MOVS-M_PUSHA	; string op?
	jb	dc9			; no
	mov	al,'B'
	cmp	[wbit],0
	je	dc8c
	mov	al,'W'
dc8c:	call	put_char
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
	shr	al,1
	add	al,6			; AL = 6 (imm) or 7 (signed imm8)
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
;
; Two-byte opcodes (0Fh and AL): DX = M_BAD (and no operands) unless it's
; one of the 80286's or 80386's (on an 80286, set_cpu limits it to the
; 80286's, 00h-07h).
;
dc0f:	call	fetch
	mov	[opcode2],al
	mov	dx,M_BAD
	DEFLBL	dc_386			; (set_cpu changes this on an 80286)
	cmp	al,0C0h			; past the 80386's?
	jae	dc5x			; yes
	cmp	al,0A0h			; one of OPTAB_0F's last 32?
	jae	dc5f			; yes
	cmp	al,80h			; Jcc or SETcc?
	jae	dc5j			; yes
	cmp	al,8			; one of OPTAB_0F's first 8?
	jb	dc5t			; yes
	sub	al,20h			; MOV with CRn, DRn, or TRn?
	cmp	al,7
	ja	dc5x			; no
	and	al,5
	cmp	al,5			; TR with bit 0 (25h or 27h)?
	je	dc5x			; yes, so it's not
	call	fetch
	mov	[modrm],al
	mov	dx,0FC00h+M_MOV		; (F: 32-bit register, C: CRn)
	test	[opcode2],2		; to CRn?
	jz	dc5x			; no
	mov	dh,0CFh
dc5x:	jmp	dc8
dc5f:	test	al,16h			; PUSH or POP FS or GS?
	jnz	dc5g			; no (not A0h, A1h, A8h, or A9h)
	mov	[modrm],al		; (for op_s)
	and	ax,1
	xchg	bx,ax
	lea	dx,[bx+3000h+M_PUSH]
	jmp	dc8			; (there's no ModRM)
dc5g:	sub	al,0A0h-8		; AL = OPTAB_0F index
dc5t:	cbw
	shl	ax,1
	xchg	bx,ax
	mov	dx,word ptr OPTAB_0F[bx]
	jmp	dc6a
dc5j:	mov	dx,0B000h+((M_JO-80h) AND 0FFh)	; Jcc (rel16)
	cmp	al,90h			; SETcc?
	jb	dc5k			; no
	mov	dx,1000h+((M_SETO-90h) AND 0FFh)
	dec	[wbit]			; (a byte)
dc5k:	add	dl,al
	jmp	dc6a
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
; put_mnem, put_mnemx
;
; Inputs:
;	AL = mnemonic index
;	CL = number of its characters to skip (put_mnemx only)
;
; Modifies:
;	AX, CL, SI
;
DEFPROC	put_mnem
	mov	cl,0
ENDPROC	put_mnem			; fall into put_mnemx

DEFPROC	put_mnemx
	mov	si,offset MNEMS
	mov	ah,al
pm1:	sub	ah,1
	jb	pm3
pm2:	lodsb
	test	al,al
	jns	pm2
	jmp	pm1
pm3:	lodsb
	dec	cl			; skip this character?
	jns	pm3			; yes
	mov	ah,al
	and	al,7Fh
	call	put_char
	test	ah,ah
	jns	pm3
	ret
ENDPROC	put_mnemx

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
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	put_opnd
	cmp	[opcode],0Fh		; two-byte opcode?
	jne	po1			; no
	cmp	al,0Ch			; one of its own operand types?
	jb	po1			; no
	add	al,4			; yes (see OPND_TAB)
po1:	cbw
	shl	ax,1
	xchg	bx,ax
	jmp	OPND_TAB[bx-2]
;
; MOVZX and MOVSX: the size of r/m comes from bit 0 of the opcode, and it's
; displayed for memory, since it isn't the size of reg.
;
op_ex:	and	[sz],SZ_ADDR		; (r/m is never a dword)
	mov	al,[opcode2]
	and	al,1
	mov	[wbit],al
	cmp	[modrm],0C0h		; register?
	jb	oe1b			; no

op_e:	mov	al,[modrm]
	cmp	al,0C0h			; register?
	jb	oe1			; no
oe0:	and	al,7
op_reg:	mov	ah,[wbit]		; AL = register 0-7, sized by wbit
	mov	cl,3
	shl	ah,cl
	add	al,ah
	call	chk_dw			; a dword?
	jnc	or1			; no
put_e:	mov	ah,'E'			; AL = 16-bit register (as in REGNAMES)
	call	put_ah
or1:	jmp	put_reg
;
; Display the size of a memory operand, unless there's a register operand,
; or it's ESC (or one of the 80286's two-byte opcodes).
;
oe1:	mov	al,[opnds]
	and	al,0EEh
	cmp	al,02h			; is the other operand G or S?
	je	oe2			; yes
	cmp	al,20h			; likewise
	je	oe2
	mov	ax,word ptr [opcode]	; AL = opcode, AH = opcode2
	cmp	al,0Fh			; two-byte opcode?
	jne	oe1a			; no
	cmp	ah,8			; the 80286's?
	jb	oe2			; yes
oe1a:	and	al,0F8h
	cmp	al,0D8h			; ESC?
	je	oe2			; yes
oe1b:	call	chk_dw			; a dword?
	jnc	oe1c			; no
	mov	ah,'D'
	call	put_ah
oe1c:	mov	al,M_BYTE
	add	al,[wbit]
	call	put_mnem
	call	space
oe2:	call	ea_start
	mov	al,[modrm]
	test	[sz],SZ_ADDR		; 32-bit addressing?
	jnz	oe32			; yes
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
	call	ea_reg			; index register
oe3:	mov	al,[modrm]
	test	al,40h			; 8-bit displacement?
	jnz	oe4			; yes
	test	al,al			; 16-bit (or 32-bit) displacement?
	jns	oe_end			; no
	call	oe_sep
	jmp	short oe_dir
oe4:	call	fetch
	cbw
	add	[ea_off],ax
	call	put_sbyte
	jmp	short oe_end
op_o:	call	ea_start
oe_dir:	mov	cl,SZ_ADDR
	call	fetch_v
	add	[ea_off],ax
	call	put_v
oe_end:	mov	al,']'
	jmp	put_char
;
; 32-bit addressing: r/m 4 means a SIB byte follows (scale in bits 6-7, index
; in bits 3-5, where 4 means none, and base in bits 0-2), and base 5 (EBP)
; with mod 0 means a 32-bit displacement instead (as with mod 2).  Only the
; low 16 bits of the address are recorded (see dis_line).
;
oe32:	and	al,7			; AL = r/m
	cmp	al,4			; SIB?
	je	o32a			; yes
	or	al,20h			; no, so make one (with no index)
	jmp	short o32b
o32a:	call	fetch			; AL = SIB
o32b:	push	ax
	and	al,7			; AL = base
	cmp	al,5			; EBP?
	jne	o32c			; no
	test	[modrm],0C0h		; with mod 0?
	jnz	o32c			; no
	or	[modrm],80h		; yes, so a displacement instead
	jmp	short o32d
o32c:	add	al,8
	call	ea_reg			; base register
o32d:	pop	ax
	mov	ah,al
	mov	cl,3
	shr	al,cl
	and	al,7			; AL = index
	cmp	al,4			; none?
	je	o32x			; right
	add	al,8
	mov	cl,6
	shr	ah,cl
	mov	cl,ah			; CL = scale
	call	ea_idx			; index register
	test	cl,cl			; scaled?
	jz	o32x			; no
	mov	al,'*'
	call	put_char
	mov	al,1
	shl	al,cl
	add	al,'0'			; AL = '2', '4', or '8'
	call	put_char
o32x:	jmp	oe3

;
; ea_start begins a memory operand: it records the operand's segment (the
; override, or DS) in ea_seg, and displays any override and the bracket;
; ea_reg displays a base or index register (AL, as in REGNAMES), after any
; '+' (see oe_sep), and adds its value to ea_off (SP or BP makes SS the
; segment, unless there's an override); ea_idx displays an index register
; likewise, but adds its value shifted left by CL (and preserves CL).
;
ea_start:
	mov	dl,0			; (nothing displayed yet; see oe_sep)
	mov	al,[seg_ovr]
	test	al,al			; an override?
	jnz	es1			; yes
	mov	al,19			; no, so DS
es1:	mov	[ea_seg],al
	call	put_seg
	mov	al,'['
	jmp	put_char

ea_reg:	cmp	al,12			; SP or BP?
	jb	er1			; no
	cmp	al,13
	ja	er1			; no
	cmp	[seg_ovr],0		; an override?
	jne	er1			; yes
	mov	[ea_seg],18		; no, so SS
er1:	mov	cl,0
ea_idx:	call	oe_sep
	push	ax
	test	[sz],SZ_ADDR		; 32-bit register?
	jz	er2			; no
	mov	ah,'E'
	call	put_ah
er2:	call	put_reg
	pop	ax
	call	reg_val
	shl	ax,cl
	add	[ea_off],ax
	ret
;
; oe_sep displays a '+' before each part of a memory operand after the first
; (DL is 0 before the first, and '+' after).
;
oe_sep:	test	dl,dl			; the first part?
	jz	os1			; yes
	push	ax
	mov	al,dl
	call	put_char
	pop	ax
os1:	mov	dl,'+'
	ret

op_g:	mov	al,[modrm]
	mov	cl,3
	shr	al,cl
	jmp	oe0

op_s:	mov	al,[modrm]
	mov	cl,3
	shr	al,cl
	DEFLBL	op_sreg			; (set_cpu changes this before 80386s)
	and	al,7
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
	jne	op_iv
op_ib:	call	fetch
	jmp	hex_byte
op_iv:	call	fetch_vo
	jmp	put_v
op_iw:	call	fetch_word
	jmp	hex_word

op_sib:	call	fetch
	jmp	put_sbyte

op_j8:	call	fetch
	cbw
	jmp	short oj1
op_j16:	call	fetch_vo
oj1:	add	ax,di
	jmp	hex_word

op_ap:	call	fetch_vo
	push	ax
	call	fetch_word
	call	hex_word
	mov	al,':'
	call	put_char
	pop	ax
	jmp	short put_v

op_dx:	mov	al,10
	jmp	put_reg

op_shift:
	test	[opcode],2
	jnz	op_cl
	mov	al,'1'
	jmp	put_char
op_cl:	mov	al,1			; CL
	jmp	put_reg
;
; After 0Fh: CRn, DRn, or TRn (0Fh 20h-26h, with bits 0 and 2 of the
; opcode giving the kind), and the operand after it.
;
op_sr:	mov	al,[opcode2]
	and	al,5			; AL = 0 (CR), 1 (DR), or 4 (TR)
	cmp	al,4
	jb	osr1
	mov	al,'T'-'C'
osr1:	add	al,'C'
	mov	ah,'R'
	call	put_2ch
	mov	al,[modrm]
	mov	cl,3
	shr	al,cl
	and	al,7
	add	al,'0'
	jmp	put_char

op_r32:	mov	al,[modrm]
	and	al,7
	add	al,8
	jmp	put_e
;
; SHLD and SHRD: reg, and then imm8 or (with bit 0 of the opcode) CL.
;
op_gx:	call	op_g
	mov	al,','
	call	put_char
	test	[opcode2],1		; CL?
	jnz	op_cl			; yes
	jmp	op_ib
;
; fetch_v fetches a word, or a dword if CL (SZ_OP or SZ_ADDR) is in sz (and
; fetch_vo uses SZ_OP), and put_v displays it.
;
; Outputs (fetch_v):
;	AX = word (or the dword's low word), DX = the dword's high word
;	CH = nonzero if a dword (for put_v)
;
fetch_vo:
	mov	cl,SZ_OP
fetch_v:
	call	fetch_word
	mov	ch,[sz]
	and	ch,cl			; a dword?
	jz	fv9			; no
	push	ax
	call	fetch_word
	xchg	dx,ax
	pop	ax
fv9:	ret

put_v:	test	ch,ch			; a dword?
	jz	pv1			; no
	xchg	ax,dx
	call	hex_word		; its high word
	xchg	ax,dx
pv1:	jmp	hex_word
ENDPROC	put_opnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_dw
;
; Outputs:
;	Carry set if the operands are dwords (words, with a 66h prefix)
;
; Modifies:
;	AH
;
DEFPROC	chk_dw
	mov	ah,[wbit]
	and	ah,[sz]
	shr	ah,1			; (SZ_OP is bit 0)
	ret
ENDPROC	chk_dw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_ah
;
; Inputs:
;	AH = character
;
DEFPROC	put_ah
	push	ax
	mov	al,ah
	call	put_char
	pop	ax
	ret
ENDPROC	put_ah

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
