;
; BASIC-DOS Loadable Serial Debugger (Disassembler and Assembler)
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The 80386 (and 80286 and 8086) and 80387 disassembler for U, BL, and the
; instruction at CS:IP (see dis_line), and P's test for instructions to step
; over (see chk_over), and the assembler for A (see cmd_a), which uses the
; same tables.  It's resident, like dbgdev.asm, which LINK puts first, and
; it's a module of its own only for MASM's symbol space (its mnemonics alone
; define about 220 equates).
;
	DOSFUNC equ 1
	include	macros.inc
	include	devapi.inc
	include	dosapi.inc

CODE	segment word public 'CODE'

	EXTNEAR	<at_ip,end_command,fetch_word,get_line,hex_addr,hex_byte>
	EXTNEAR	<hex_word,ip_mem,newline,pad,parse_addr,peek_b,poke_b>
	EXTNEAR	<put_2ch,put_char,put_reg,put_string,reg_val,skip_space>
	EXTNEAR	<space,store_list>
	EXTBYTE	<REGNAMES,a_mode,col,command,mem_mode,mute>
	EXTWORD	<a_off,a_seg,mem_seg>

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

MUTE_PROBE equ	80h			; mute bit: A is probing (see probe)

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
MNAME	macro	text
_LC = 0
	IRPC	c,<text>
	 IF	_LC
	db	_LC
	 ENDIF
_LC = '&c'
	ENDM
	db	_LC OR 80h
	endm

_MN = 0
MNEM	macro	text,name
	IFB	<name>
M_&text = _MN
	ELSE
M_&name = _MN
	ENDIF
_MN = _MN + 1
	MNAME	<text>
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
	MNEM	CWD			; become CWDE, CDQ, and JECXZ (see
	MNEM	JCXZ			; dc8)
	IF	M_JCXZ GE 78h
	ERROR	<Too many OPTAB mnemonics>
	ENDIF
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
	MNEM	<DWORD PTR>,DWORD
	MNEM	<QWORD PTR>,QWORD
	MNEM	<TBYTE PTR>,TBYTE
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
	MNEM	CWDE
	MNEM	CDQ
	MNEM	JECXZ
;
; The 80x87's mnemonics (see dc_fpu), from M_FADD to MNEM_CNT, in groups
; whose order decode (and A) rely on; MSKIP marks an unused index, displayed
; as ???.
;
MSKIP	macro
_MN = _MN + 1
	MNAME	<???>
	endm
	MNEM	FADD			; ESC reg 0-7 (D8h and DCh)
	MNEM	FMUL
	MNEM	FCOM
	MNEM	FCOMP
	MNEM	FSUB
	MNEM	FSUBR
	MNEM	FDIV
	MNEM	FDIVR
	MNEM	FLD			; M_FADD+8 (D9h and DDh)
	MNEM	FST
	MNEM	FSTP
	MNEM	FIADD			; ESC reg 0-7 (DAh and DEh)
	MNEM	FIMUL
	MNEM	FICOM
	MNEM	FICOMP
	MNEM	FISUB
	MNEM	FISUBR
	MNEM	FIDIV
	MNEM	FIDIVR
	MNEM	FILD			; M_FIADD+8 (DBh and DFh)
	MNEM	FIST
	MNEM	FISTP
	MNEM	FADDP			; DEh reg 0-7 (except 2 and 3)
	MNEM	FMULP
	MNEM	FCOMPP
	MNEM	FUCOMPP
	MNEM	FSUBP
	MNEM	FSUBRP
	MNEM	FDIVP
	MNEM	FDIVRP
	MNEM	FCHS			; D9h E0h-FFh
	MNEM	FABS
	MSKIP
	MSKIP
	MNEM	FTST
	MNEM	FXAM
	MSKIP
	MSKIP
	MNEM	FLD1
	MNEM	FLDL2T
	MNEM	FLDL2E
	MNEM	FLDPI
	MNEM	FLDLG2
	MNEM	FLDLN2
	MNEM	FLDZ
	MSKIP
	MNEM	F2XM1
	MNEM	FYL2X
	MNEM	FPTAN
	MNEM	FPATAN
	MNEM	FXTRACT
	MNEM	FPREM1
	MNEM	FDECSTP
	MNEM	FINCSTP
	MNEM	FPREM
	MNEM	FYL2XP1
	MNEM	FSQRT
	MNEM	FSINCOS
	MNEM	FRNDINT
	MNEM	FSCALE
	MNEM	FSIN
	MNEM	FCOS
	MNEM	FNSTENV			; these 8 also have WAIT forms (see
	MNEM	FNSTCW			; M_FWAITS)
	MNEM	FNSAVE
	MNEM	FNSTSW
	MNEM	FNENI
	MNEM	FNDISI
	MNEM	FNCLEX
	MNEM	FNINIT
	MNEM	FSETPM
	MNEM	FLDENV
	MNEM	FLDCW
	MNEM	FBLD
	MNEM	FBSTP
	MNEM	FRSTOR
	MNEM	FXCH
	MNEM	FNOP
	MNEM	FFREE
	MNEM	FUCOM
	MNEM	FUCOMP
MNEM_CNT equ	_MN
;
; Other names that A accepts (see find_mnem), each with the index it means;
; the first two are keywords for jumps (like BYTE PTR, WORD PTR, FAR, and
; DWORD PTR, whose sizes A gets from their order; see parse_opnd), so they
; take M_SET's index and the unused one after it, and DB and DW are A's own
; (see asm_line), so they take the indexes after MNEMS.
;
M_SHORT	equ	M_SET
M_NEAR	equ	M_SET+1
M_DB	equ	MNEM_CNT
M_DW	equ	MNEM_CNT+1
M_FWAITS equ	MNEM_CNT+2		; FSTENV through FINIT (see below)
	IF	M_NEAR GE 80h
	ERROR	<No room for A's names>
	ENDIF
MALIAS	macro	text,index
	db	index
	MNAME	<text>
	endm

	DEFLBL	ALIASES,byte
	MALIAS	JE,M_JZ
	MALIAS	JNE,M_JNZ
	MALIAS	JC,M_JB
	MALIAS	JNAE,M_JB
	MALIAS	JNC,M_JNB
	MALIAS	JAE,M_JNB
	MALIAS	JNA,M_JBE
	MALIAS	JNBE,M_JA
	MALIAS	JP,M_JPE
	MALIAS	JNP,M_JPO
	MALIAS	JNGE,M_JL
	MALIAS	JNL,M_JGE
	MALIAS	JNG,M_JLE
	MALIAS	JNLE,M_JG
	MALIAS	LOOPE,M_LOOPZ
	MALIAS	LOOPNE,M_LOOPNZ
	MALIAS	REP,M_REPZ
	MALIAS	REPE,M_REPZ
	MALIAS	REPNE,M_REPNZ
	MALIAS	SAL,M_SHL
	MALIAS	SHORT,M_SHORT
	MALIAS	NEAR,M_NEAR
	MALIAS	<DB>,M_DB
	MALIAS	<DW>,M_DW
	MALIAS	FWAIT,M_WAIT
;
; The WAIT forms of FNSTENV through FNINIT, which A assembles with a WAIT
; (9Bh) before them (see asm_line).
;
	MALIAS	FSTENV,M_FWAITS
	MALIAS	FSTCW,M_FWAITS+1
	MALIAS	FSAVE,M_FWAITS+2
	MALIAS	FSTSW,M_FWAITS+3
	MALIAS	FENI,M_FWAITS+4
	MALIAS	FDISI,M_FWAITS+5
	MALIAS	FCLEX,M_FWAITS+6
	MALIAS	FINIT,M_FWAITS+7
	DEFLBL	ALIASES_END,byte
;
; SETcc isn't in MNEMS: its "index" is M_SETO plus the condition (0-0Fh), and
; it's displayed as SET and the matching Jcc without its J (see dc8).
;
M_SETO	equ	0F0h
	IF	M_FWAITS+8 GT M_SETO
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
; and after ESC (D8h-DFh), C-E have others (see dc_fpu and fix_type):
;
;	C: ST		D: ST(i) (ModRM r/m)	E: memory (sized by wbit)
;
; Sizes come from bit 0 of the opcode, unless the operands say otherwise;
; with a 66h prefix, words (and rel16 and imm16, except for 9) are dwords.
;
	DEFLBL	OPND_TAB,word
	dw	op_e, op_g, op_s, op_a, op_z, op_i, op_sib, op_ib
	dw	op_iw, op_j8, op_j16, op_ap, op_o, op_dx, op_shift
	dw	op_sr, op_ex, op_gx, op_r32
	dw	op_st, op_sti, op_fm
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
	db	8 dup (M_BAD,10h)	; (ESC; see dc_fpu)		; D8h
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
	cmp	dl,M_BAD		; ESC (the 80x87's opcodes)?
	jne	dc6b			; no
	jmp	dc_fpu
dc6b:	cmp	dl,G1			; group (78h-7Fh, not 80h and up)?
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
	test	[mute],MUTE_PROBE	; probing for A (see probe)?
	jz	dc8d			; no
	ret				; yes, which needs only this much
dc8d:	mov	cl,0
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
	mov	al,[opnds]
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

;
; dc_fpu
;
; ESC opcodes (D8h-DFh) are the 80x87's (including the 80287's and 80387's):
; with memory, D8h, DAh, DCh, and DEh have FADD through FDIVR (or FIADD
; through FIDIVR) for ModRM reg 0-7, and D9h, DBh, DDh, and DFh have loads
; and stores (see FPU_MEM), and the memory's size depends on the opcode (see
; FPU_SIZES); and with ModRM mod 3, D8h, DCh, and DEh have FADD through FDIVR
; (or FADDP through FDIVRP) with ST and ST(i), where DCh and DEh swap the
; ModRM reg 4-7 forms (eg, DCh E8h is FSUB ST(i),ST), and the rest are
; FLD, FXCH, FFREE, FST, FSTP, FUCOM, and FUCOMP with ST(i), or have no
; operands (D9h E0h-FFh, and those in FPU_ONE).
;
; Inputs:
;	AL = ModRM (in modrm, too), and the opcode in opcode
;
; Outputs:
;	DL = mnemonic, DH = operand types; wbit = memory's size (as in BYTE
;	PTR through TBYTE PTR, or FFh if none); then it goes to dc8
;
DEFPROC	dc_fpu
	mov	cl,3
	mov	bl,al
	shr	bl,cl
	and	bx,7			; BX = ModRM reg
	mov	ah,[opcode]
	and	ah,7			; AH = opcode bits 0-2
	cmp	al,0C0h			; memory?
	jae	dfr			; no
;
; Memory: the size is the opcode's (see FPU_SIZES), unless FPU_MEM has it.
;
	mov	si,bx
	mov	bl,ah
	shr	bl,1
	mov	cl,FPU_SIZES[bx]
	mov	[wbit],cl
	mov	bx,si
	mov	dx,0E000h+M_FADD	; (memory)
	test	ah,2			; FIADD...FIDIVR (or FILD...FISTP)?
	jz	dfm1			; no
	mov	dl,M_FIADD
dfm1:	test	ah,1			; D9h, DBh, DDh, or DFh?
	jnz	dfm2			; yes
	add	dl,bl			; FADD...FDIVR (or FIADD...FIDIVR)
	jmp	short dfx
dfm2:	cmp	bl,4			; reg 0-3?
	jae	dfm3			; no
	add	dl,M_FLD-M_FADD		; FLD (or FILD), FST, or FSTP
	dec	bx			; reg 0?
	js	dfx			; yes
	jnz	dfm2a			; no (2 or 3)
	mov	dl,M_BAD		; reg 1
dfm2a:	add	dl,bl
	jmp	short dfx
dfm3:	and	ah,6
	shl	ah,1
	add	bl,ah
	shl	bx,1			; BX = 2 * (index + 4)
	mov	dx,word ptr FPU_MEM[bx-8]	; DL = mnemonic, DH = size
	mov	[wbit],dh
	mov	dh,0E0h			; (memory)
	jmp	short dfx
df9:	mov	dh,0D0h			; ST(i)
	jmp	short dfx
df_bad:	mov	dx,M_BAD		; (no operands)
dfx:	jmp	dc8
;
; With mod 3: first the instructions with no operands.
;
dfr:	mov	si,offset FPU_ONE
df1:	cmp	ax,[si]			; ModRM and opcode bits match?
	je	df2			; yes
	add	si,3
	cmp	si,offset FPU_ONE_END
	jb	df1
	cmp	ah,1			; D9h?
	jne	df4			; no
	cmp	al,0E0h			; E0h-FFh?
	jb	df3			; no
	add	al,M_FCHS-0E0h
	mov	dx,ax
	mov	dh,0			; (no operands)
	jmp	short dfx
df2:	mov	dl,[si+2]
	mov	dh,0			; (no operands)
	cmp	dl,M_FNSTSW		; FNSTSW AX?
	jne	dfx			; no
	mov	dh,40h			; (AX, a word, since wbit is 1)
	jmp	short dfx
df3:	mov	dl,M_FLD
	dec	bx			; FLD (reg 0) or FXCH (reg 1)?
	js	df9			; FLD
	jnz	df_bad			; neither
	mov	dl,M_FXCH
	jmp	short df9
df4:	cmp	ah,5			; DDh?
	jne	df5			; no
	mov	dl,FPU_DD[bx]
	jmp	short df9
df5:	test	ah,1			; DBh or DFh?
	jnz	df_bad			; yes
	cmp	ah,2			; DAh?
	je	df_bad			; yes
	mov	dl,M_FADD
	test	ah,ah			; D8h?
	jnz	df6			; no
	add	dl,bl			; ST,ST(i)
	mov	dh,0CDh
	and	bl,6
	cmp	bl,2			; FCOM or FCOMP?
	jne	dfx			; no
	jmp	short df9		; yes (just ST(i))
df6:	cmp	ah,6			; DEh?
	jne	df7			; no
	mov	dl,M_FADDP
df7:	mov	al,bl
	and	al,6
	cmp	al,2			; reg 2 or 3?
	je	df_bad			; yes
	cmp	bl,4			; reg 4-7?
	jb	df8			; no
	xor	bl,1			; yes (which are swapped)
df8:	add	dl,bl
	mov	dh,0DCh			; ST(i),ST
	jmp	dc8
ENDPROC	dc_fpu
;
; FPU_SIZES are the sizes of memory (as in BYTE PTR through TBYTE PTR) for
; opcodes D8h-D9h, DAh-DBh, DCh-DDh, and DEh-DFh, and FPU_MEM has the
; mnemonics and sizes of D9h, DBh, DDh, and DFh with ModRM reg 4-7 (FFh is
; no size).
;
	DEFLBL	FPU_SIZES,byte
	db	3,3,4,1
	DEFLBL	FPU_MEM,byte
	db	M_FLDENV,0FFh, M_FLDCW,1, M_FNSTENV,0FFh, M_FNSTCW,1	; D9h
	db	M_BAD,0FFh, M_FLD,5, M_BAD,0FFh, M_FSTP,5		; DBh
	db	M_FRSTOR,0FFh, M_BAD,0FFh, M_FNSAVE,0FFh, M_FNSTSW,1	; DDh
	db	M_FBLD,5, M_FILD,4, M_FBSTP,5, M_FISTP,4		; DFh
;
; FPU_DD has DDh's mnemonics with ST(i), for ModRM reg 0-7, and FPU_ONE has
; the ModRM, opcode bits 0-2, and mnemonic of each instruction with no
; operands (except FNSTSW AX) that isn't D9h E0h-FFh.
;
	DEFLBL	FPU_DD,byte
	db	M_FFREE,M_BAD,M_FST,M_FSTP,M_FUCOM,M_FUCOMP,M_BAD,M_BAD
	DEFLBL	FPU_ONE,byte
	db	0D0h,1,M_FNOP
	db	0E9h,2,M_FUCOMPP
	db	0E0h,3,M_FNENI
	db	0E1h,3,M_FNDISI
	db	0E2h,3,M_FNCLEX
	db	0E3h,3,M_FNINIT
	db	0E4h,3,M_FSETPM
	db	0D9h,6,M_FCOMPP
	db	0E0h,7,M_FNSTSW
	DEFLBL	FPU_ONE_END,byte

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
	call	fix_type
	cbw
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
; or it's one of the 80286's two-byte opcodes.
;
oe1:	mov	al,[opnds]
	and	al,0EEh
	cmp	al,02h			; is the other operand G or S?
	je	oe2			; yes
	cmp	al,20h			; likewise
	je	oe2
	mov	ax,word ptr [opcode]	; AL = opcode, AH = opcode2
	cmp	al,0Fh			; two-byte opcode?
	jne	oe1b			; no
	cmp	ah,8			; the 80286's?
	jb	oe2			; yes
oe1b:	mov	al,M_BYTE
	add	al,[wbit]
	call	chk_dw			; a dword?
	jnc	oe1c			; no
	mov	al,M_DWORD
oe1c:	call	put_mnem
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
;
; After ESC: ST, ST(i), and memory, whose size (if any) is wbit.
;
op_sti:	call	op_st
	mov	al,'('
	call	put_char
	mov	al,[modrm]
	and	al,7
	add	al,'0'
	mov	ah,')'
	jmp	short os2
op_st:	mov	ax,'T' SHL 8 + 'S'
os2:	jmp	put_2ch

op_fm:	mov	al,[wbit]
	cmp	al,0FFh			; no size?
	je	of1			; right
	add	al,M_BYTE
	call	put_mnem
	call	space
of1:	jmp	oe2
ENDPROC	put_opnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fix_type
;
; Operand types C-F have other meanings after 0Fh and ESC (see OPND_TAB).
;
; Inputs:
;	AL = operand type (1-15)
;
; Outputs:
;	AL = OPND_TAB index (1-22)
;
; Modifies:
;	AH
;
DEFPROC	fix_type
	cmp	al,0Ch			; one with other meanings?
	jb	ft9			; no
	mov	ah,[opcode]
	cmp	ah,0Fh			; after 0Fh?
	je	ft1			; yes
	and	ah,0F8h
	cmp	ah,0D8h			; after ESC?
	jne	ft9			; no
	add	al,4
ft1:	add	al,4
ft9:	ret
ENDPROC	fix_type

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
; fetch
;
; While A is probing (see probe), the instruction is in our own data.
;
; Inputs:
;	mem_seg:DI -> next instruction byte
;
; Outputs:
;	AL = next instruction byte; DI advanced
;
DEFPROC	fetch
	test	[mute],MUTE_PROBE	; probing for A?
	jnz	fe1			; yes
	call	peek_b
	inc	di
	ret
fe1:	mov	al,[di]
	inc	di
	ret
ENDPROC	fetch

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; The assembler (A), which finds each instruction by probing: it decodes
; every opcode (and for a group, every ModRM reg) with decode's own tables,
; and for each one with the instruction's mnemonic, checks the operands
; against its operand types and encodes them (see try_enc), keeping the
; shortest encoding.  Opcodes are tried from FFh down, so that one of the
; 8086's or 80286's aliases (eg, 60h-6Fh for Jcc on an 8086) never wins
; over the usual opcode, and 82h (80h's alias) is never tried.
;
; Each operand that asm_line parses is OP_LEN bytes: its kind (K_*), its size
; (0, 1, or 3 for an 8-bit, 16-bit, or 32-bit register; 0, 1, or 4 for CRn,
; DRn, or TRn; for memory or an immediate, a keyword's size, 0-5 for BYTE
; PTR, WORD PTR, FAR, DWORD PTR, SHORT, or NEAR, or FFh if none), its number
; (a register's 0-7, a segment register's 0-5, or memory's ModRM mod and r/m
; bits), memory's displacement length (plus 80h if a SIB follows the ModRM),
; its SIB, and its 32-bit value (an immediate, memory's displacement, or
; segment:offset's offset, whose segment is in the high word).
;
OP_KIND	equ	0
OP_SIZE	equ	1
OP_NUM	equ	2
OP_DLEN	equ	3
OP_SIBB	equ	4			; (after OP_DLEN, and before OP_VAL)
OP_VAL	equ	5
OP_SEG	equ	7
OP_LEN	equ	10

K_REG	equ	1
K_SREG	equ	2
K_MEM	equ	3
K_IMM	equ	4
K_FAR	equ	5
K_CTL	equ	6			; CRn, DRn, or TRn
K_ST	equ	7			; ST or ST(i)

SZ_D	equ	3			; dword size (as in OP_SIZE and a_w)
SZ_SHORT equ	M_SHORT-M_BYTE		; SHORT's size
SZ_NEAR	equ	M_NEAR-M_BYTE		; NEAR's size
SZ_CTL	equ	80h			; a_sz: CRn, DRn, or TRn (no 66h)
	IF	SZ_D NE M_DWORD-M_BYTE
	ERROR	<DWORD PTR must follow FAR>
	ENDIF

	DEFBYTE	a_pfx,0			; LOCK or REP prefix (or 0)
	DEFBYTE	a_segp,0		; segment override (or 0), after a_pfx
	DEFBYTE	a_sz,0			; SZ_* prefixes (66h and 67h)
	DEFBYTE	a_swap,0		; 1 after swapping operands, after a_sz
	DEFBYTE	a_mnem,0		; mnemonic (as in MNEMS)
	DEFBYTE	a_isize,0		; size suffix, after a_mnem (see
					; find_mnem)
	DEFBYTE	a_op,0			; opcode (or the byte after 0Fh) tried
	DEFBYTE	a_page,0		; 1 while trying 0Fh opcodes
	DEFBYTE	a_reg,0			; ModRM tried (see probe)
	DEFBYTE	a_hm,0			; 1 if the opcode has a ModRM
	DEFBYTE	a_w,0			; 0 (byte), 1 (word), 2 (far), or 3
					; (dword: a word, with a 66h prefix)
	DEFBYTE	a_ms,0			; size given to memory (see chk_ms)
	DEFBYTE	a_len,0			; length of the best encoding (or FFh)
	DEFBYTE	a_mask,0		; sizes given to memory (see chk_ms)
	DEFBYTE	a_fpu,0			; FFh if an 80x87 instruction
	DEFBYTE	a_probe,0,3		; the opcode (and ModRM) to decode
	DEFBYTE	a_cand,0,16		; the encoding being tried
	DEFBYTE	a_best,0,16		; the best encoding so far
	DEFBYTE	a_ops,0,4*OP_LEN	; operands (and an empty one after)
	DEFWORD	a_err,0			; where the line went wrong
	DEFWORD	a_sp0,0			; SP for asm_err
	DEFWORD	a_sp,0			; SP for ae_fail

	DEFLBL	ERR_MSG,byte
	db	"^ Error",0
;
; Operand types (as in OPND_TAB, with those after 0Fh at 10h-13h; see
; te_opnd), and the procedures that check and encode them (see te_opnd).
;
	DEFLBL	ASM_TAB,word
	dw	ae_e, ae_g, ae_s, ae_a, ae_z, ae_i, ae_sib, ae_ib
	dw	ae_iw, ae_j8, ae_j16, ae_ap, ae_o, ae_dx, ae_sh
	dw	ae_ctl, ae_ex, ae_gx, ae_r32
	dw	ae_st, ae_sti, ae_fm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_a
;
; A [addr] assembles instructions at addr (by default, after the last A, or
; CS:IP), prompting with each address, until an empty line.  A line that
; can't be assembled displays "^ Error" below where it went wrong, and the
; same address again.
;
DEFPROC	cmd_a
	push	ds
	pop	es
	mov	al,[a_mode]
	mov	[mem_mode],al		; (unless there's an address)
	mov	bp,[a_seg]
	mov	ax,[a_off]
	call	end_command		; an address?
	jnc	ca1			; no
	call	parse_addr		; BP:AX = address
	jc	ca9
	call	end_command
	jc	ca9
ca1:	mov	[a_seg],bp
	mov	[mem_seg],bp
	mov	dl,[mem_mode]
	mov	[a_mode],dl
ca2:	mov	[a_off],ax
	xchg	di,ax
	call	hex_addr
	mov	al,[col]
	push	ax			; AL = the prompt's width
	call	get_line
	mov	si,offset command
	call	end_command		; an empty line?
	pop	dx
	jnc	ca9			; yes, so we're done
	push	dx
	call	asm_line		; DI -> the next address
	pop	dx
	mov	[col],0			; (as get_line left it; see probe)
	xchg	ax,di
	jnc	ca2
	mov	ax,[a_err]
	sub	ax,offset command
	add	al,dl
	mov	ah,al			; AH = the column of the error
	call	pad
	mov	si,offset ERR_MSG
	call	put_string
	call	newline
	mov	ax,[a_off]
	jmp	ca2
ca9:	ret
ENDPROC	cmd_a

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; asm_line
;
; Assemble a line: any prefixes (LOCK, REP, REPZ, REPNZ, or a segment
; override, eg, ES:), each by itself or before an instruction, an
; instruction, or DB or DW and a list of values (and for DB, strings).
;
; Inputs:
;	SI -> line
;	a_off, mem_seg, and mem_mode: its address
;
; Outputs:
;	Carry clear if successful (DI = the next address), set if not
;	(a_err -> where it went wrong)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
DEFPROC	asm_line
	mov	[a_sp0],sp
	sub	ax,ax
	mov	word ptr [a_pfx],ax	; no prefixes (and no a_segp)
	mov	word ptr [a_sz],ax	; (and no a_swap)
al1:	call	skip_space
	mov	[a_err],si
	cmp	byte ptr [si],0		; only prefixes?
	je	al_pfx			; yes
	call	get_reg			; a segment override?
	jc	al2			; no
	call	set_seg
	jmp	al1
al2:	call	find_op
	jc	al_err
	mov	word ptr [a_mnem],ax	; (and a_isize)
	mov	ah,al
	sub	ah,M_LOCK
	cmp	ah,M_REPZ+1-M_LOCK	; LOCK, REPNZ, or REPZ?
	jae	al3			; no
	mov	al,0F0h
	cmp	ah,1
	cmc
	adc	al,ah			; F0h, F2h, or F3h
	mov	[a_pfx],al
	jmp	al1
al3:	cmp	al,M_DB
	je	al_db
	cmp	al,M_DW
	jne	al4
	mov	di,[a_off]		; DW
adw1:	call	skip_space
	lodsb
	cmp	al,','
	je	adw1
	test	al,al			; the end? (carry clear)
	jz	adw9			; yes
	dec	si
	call	get_num
	jc	al_err
	call	chk_hw			; 16 bits?
	jne	al_err			; no
	push	ax
	call	poke_b
	pop	ax
	jc	al_err
	mov	al,ah
	call	poke_b
	jnc	adw1
al_err:	jmp	asm_err
al_db:	mov	di,[a_off]
	call	store_list
	jc	al_err
adw9:	ret
al_pfx:	mov	di,offset a_best	; prefixes alone
	call	emit_pfx
	xchg	ax,di
	sub	ax,offset a_best
	jmp	al_wr

;
; FSTENV through FINIT are FNSTENV through FNINIT after a WAIT (which takes
; the place of any LOCK or REP prefix).
;
al4:	mov	ah,al
	sub	ah,M_FWAITS
	cmp	ah,8			; FSTENV through FINIT?
	jae	al4w			; no
	sub	al,M_FWAITS-M_FNSTENV
	mov	[a_mnem],al
	mov	[a_pfx],9Bh
al4w:	test	[a_isize],2		; a D suffix (eg, PUSHAD)?
	jz	al4a			; no
	or	[a_sz],SZ_OP
al4a:	mov	ah,al
	sub	ah,M_CWDE
	cmp	ah,M_JECXZ+1-M_CWDE	; CWDE, CDQ, or JECXZ?
	jae	al5			; no
	sub	al,M_CWDE-M_CBW		; yes, so CBW, CWD, or JCXZ
	mov	[a_mnem],al
	shr	ah,1
	inc	ah			; with SZ_OP (or for JECXZ, SZ_ADDR)
	or	[a_sz],ah
al5:	mov	di,offset a_ops
	mov	bx,di
	mov	cx,3*OP_LEN/2
	sub	ax,ax
	rep	stosw			; no operands yet
	call	end_command		; any?
	jnc	al7a			; no
al6:	call	parse_opnd
	add	bx,OP_LEN
	call	skip_space
	cmp	byte ptr [si],','	; another operand?
	jne	al7			; no
	inc	si
	cmp	bx,offset a_ops+3*OP_LEN
	jb	al6
al7:	call	end_command		; anything else?
	jc	al_err			; yes
;
; MOV with CRn, DRn, or TRn never has a 66h prefix (its other operand is
; always a 32-bit register), nor does an 80x87 instruction (DWORD PTR is
; just its memory's size), and otherwise, a 66h or 67h prefix needs an
; 80386.
;
al7a:	mov	al,[a_sz]
	mov	ah,[a_mnem]
	sub	ah,M_FADD
	cmp	ah,MNEM_CNT-M_FADD	; an 80x87 instruction?
	sbb	ah,ah
	mov	[a_fpu],ah		; (FFh if so)
	jz	al7c			; no
	and	al,SZ_ADDR
	jmp	short al7d
al7c:	cmp	al,SZ_CTL		; CRn, DRn, or TRn?
	jb	al7b			; no
	mov	al,0
al7d:	mov	[a_sz],al
al7b:	test	al,al			; a 66h or 67h prefix?
	jz	al8			; no
	cmp	byte ptr OPTAB[(66h-60h)*2+1],PFX_SIZE	; are there any here?
	je	al8			; yes
	jmp	asm_err			; no (see set_cpu)
;
; Try every opcode, from FFh down, and then (if this processor has them)
; every opcode after 0Fh.
;
al8:	mov	word ptr [a_len],00FFh	; no encoding yet (and no a_mask)
ae0:	mov	[a_page],0
	cmp	[a_fpu],0		; an 80x87 instruction?
	jne	af0			; yes
ae1:	mov	[a_op],0FFh
ae2:	cmp	[a_page],0
	jne	ae3
	mov	al,[a_op]
	cmp	al,0Fh			; (two-byte opcodes are tried later)
	je	ae8
	cmp	al,82h			; (an alias of 80h)
	je	ae8
ae3:	mov	[a_reg],0
	mov	al,[a_op]
	mov	ah,0
	call	probe
	jc	ae8			; it's a prefix
	cmp	[a_hm],0		; a ModRM?
	je	ae6			; no
	mov	dl,al
	mov	al,[a_op]
	mov	ah,4 SHL 3
	call	probe
	cmp	al,dl			; does ModRM reg change the mnemonic?
	je	ae6			; no
ae5:	mov	al,[a_op]		; yes, so it's a group: try each reg
	mov	ah,[a_reg]
	call	probe
	call	try_enc
	add	[a_reg],1 SHL 3
	cmp	[a_reg],8 SHL 3
	jb	ae5
	jmp	short ae8
ae6:	call	try_enc
ae8:	sub	[a_op],1
	jnc	ae2
	cmp	[a_page],0
	jne	ae9
	cmp	byte ptr [dc_0f+1],0Fh	; is 0Fh a two-byte opcode here?
	jne	ae9			; no (it's an 8086)
	inc	[a_page]
	jmp	ae1
;
; An 80x87 instruction is ESC (D8h-DFh) with a ModRM: with memory (each reg,
; with mod 0 and r/m 0), and with ST or ST(i), or no operands (each reg and
; r/m, with mod 3).
;
af0:	mov	[a_op],0DFh
af1:	mov	[a_reg],0
af2:	mov	al,[a_op]
	mov	ah,[a_reg]
	call	probe
	call	try_enc
	mov	al,1 SHL 3		; (the next reg, with mod 0)
	cmp	[a_reg],0C0h
	jb	af3
	mov	al,1			; (the next reg and r/m, with mod 3)
af3:	add	[a_reg],al
	jc	af4			; (past FFh)
	cmp	[a_reg],8 SHL 3		; past mod 0?
	jne	af2			; no
	mov	[a_reg],0C0h
	jmp	af2
af4:	dec	[a_op]
	cmp	[a_op],0D8h
	jae	af1
;
; XCHG and TEST accept their operands in either order (eg, XCHG [BX],AX),
; so they get a second try, with the first two swapped (eg, XCHG BX,AX is
; shorter that way).
;
ae9:	mov	al,[a_mnem]
	cmp	al,M_XCHG
	je	ae9a
	cmp	al,M_TEST
	jne	ae9b
ae9a:	xor	[a_swap],1		; swapped already?
	jz	ae9b			; yes
	mov	si,offset a_ops
	mov	cx,OP_LEN/2
ae9s:	mov	ax,[si]
	xchg	ax,[si+OP_LEN]
	mov	[si],ax
	inc	si
	inc	si
	loop	ae9s
	jmp	ae0
ae9b:	mov	al,[a_len]
	cmp	al,0FFh			; did any opcode fit?
	je	asm_err			; no
	mov	ah,[a_mask]
	mov	cl,ah
	dec	cl
	test	ah,cl			; did memory fit more than one size?
	jnz	asm_err			; yes (a size keyword is needed)
al_wr:	mov	di,[a_off]
	mov	si,offset a_best
	cbw
	xchg	cx,ax
al9:	lodsb
	call	poke_b
	jc	asm_err
	loop	al9
	ret
;
; Any error in a line comes here, from anywhere in it.
;
asm_err:
	mov	sp,[a_sp0]
	stc
	ret
ENDPROC	asm_line

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_opnd
;
; Parse an operand: a register (including EAX-EDI, and CRn, DRn, or TRn), an
; immediate value, segment:offset, or memory (eg, [BX+SI+10], or with 32-bit
; addressing, [EBX+ESI*4+10]), which may follow a size keyword (eg, BYTE PTR)
; and a segment override (eg, ES:).  A 32-bit register, DWORD PTR, or a value
; that doesn't fit in 16 bits means 32-bit operands (a 66h prefix), and a
; 32-bit register in memory means 32-bit addressing (a 67h prefix).
;
; Inputs:
;	SI -> text
;	BX -> operand (zeroed)
;
; Outputs:
;	SI -> the text after it (or it goes to asm_err)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	parse_opnd
	mov	byte ptr [bx+OP_SIZE],0FFh	; (no size given)
pp1:	call	skip_space
	mov	[a_err],si
	push	si
	call	find_mnem		; a keyword (eg, BYTE PTR)?
	pop	dx
	jc	pp2			; no
	sub	al,M_BYTE
	cmp	al,M_NEAR+1-M_BYTE
	jae	pp2			; no
	call	set_size
	jmp	pp1
pp2:	mov	si,dx
	call	get_reg			; a register?
	jc	pp4			; no
	cmp	al,16			; a segment register?
	jb	pp3			; no
	cmp	al,24
	jae	pp3			; no (a 32-bit register)
	cmp	byte ptr [si],':'	; an override?
	jne	pp2a			; no
	call	set_seg
	jmp	pp1
pp2a:	sub	al,16
	mov	ah,K_SREG
	jmp	short pp3a
pp3:	push	ax
	mov	cl,3
	shr	al,cl			; AL = 0 (8-bit), 1 (16-bit), or 3
	call	set_size
	pop	ax
	and	al,7
	mov	ah,K_REG
pp3a:	mov	[bx+OP_NUM],al
	mov	[bx+OP_KIND],ah
	ret
;
; CRn, DRn, or TRn (n is 0-7), whose size is the kind (as in op_sr).
;
pp4:	mov	ax,[si]
	cmp	ax,'T' SHL 8 + 'S'	; ST or ST(i)?
	je	pst			; yes
	cmp	ah,'R'			; CRn, DRn, or TRn?
	jne	pp4x			; no
	sub	al,'C'
	cmp	al,1			; CR or DR?
	jbe	pp4c			; yes
	cmp	al,'T'-'C'		; TR?
	jne	pp4x			; no
	mov	al,4
pp4c:	mov	ah,K_CTL
	xchg	al,ah
	mov	word ptr [bx+OP_KIND],ax	; (and OP_SIZE)
	lea	di,[si+3]
	mov	al,[si+2]
	sub	al,'0'
	cmp	al,8			; 0-7?
	jae	pp_err			; no
	mov	[bx+OP_NUM],al
	call	chk_end			; the whole name?
	jne	pp_err			; no
	mov	si,di
	or	[a_sz],SZ_CTL
	ret
;
; ST or ST(i) (i is 0-7, and ST is ST(0)).
;
pst:	lea	di,[si+2]
	mov	al,0
	cmp	byte ptr [di],'('	; ST(i)?
	jne	pst1			; no
	mov	ax,[di+1]		; AL = i, AH = ')'
	sub	al,'0'
	cmp	al,8			; 0-7?
	jae	pp_err			; no
	cmp	ah,')'
	jne	pp_err
	add	di,3
pst1:	mov	[bx+OP_NUM],al
	call	chk_end			; the whole name?
	jne	pp_err			; no
	mov	si,di
	mov	byte ptr [bx+OP_KIND],K_ST
	ret
pp4x:	cmp	byte ptr [si],'['	; memory?
	je	pp5			; yes
	call	get_num			; no, so a value
	jc	pp_err
	mov	byte ptr [bx+OP_KIND],K_IMM
	mov	[bx+OP_VAL],ax
	mov	[bx+OP_SEG],dx
	call	chk_hw			; 16 bits?
	je	pp4y			; yes
	or	[a_sz],SZ_OP		; no, so it's a dword
	ret
pp4y:	cmp	byte ptr [si],':'	; segment:offset?
	jne	pp9			; no
	inc	si
	mov	[bx+OP_SEG],ax
	call	get_num
	jc	pp_err
	call	chk_hw
	jne	pp_err
	mov	byte ptr [bx+OP_KIND],K_FAR
	mov	[bx+OP_VAL],ax
pp9:	ret
pp_err:	jmp	asm_err
;
; Memory is a base register (BX or BP), an index register (SI or DI), and
; displacements, in any order, separated by + (or - before a displacement);
; OP_NUM holds the registers (as in RMTAB) until the ].  With 32-bit
; registers, the first without a scale (*1, *2, *4, or *8) is the base, and
; the other is the index (which can't be ESP); OP_SIBB holds them (and the
; scale), and OP_DLEN has bit 0 set for a base, and bit 1 for an index.
;
pp5:	inc	si
	mov	byte ptr [bx+OP_KIND],K_MEM
pp6:	call	skip_space
	call	get_reg
	jc	pp7
	cmp	al,24			; a 32-bit register?
	jb	pp6b			; no
	jmp	pr1
pp6b:	test	[a_sz],SZ_ADDR		; after a 32-bit one?
	jnz	pp_err			; yes
	sub	al,11
	cmp	al,4			; BX, SP, BP, SI, or DI?
	ja	pp_err			; no
	cmp	al,1			; SP?
	je	pp_err			; yes
	add	al,11
	mov	ah,0Fh			; (a base is in bits 0-3)
	cmp	al,14			; SI or DI?
	jb	pp6a			; no
	mov	cl,4
	shl	al,cl
	mov	ah,0F0h			; (an index is in bits 4-7)
pp6a:	test	[bx+OP_NUM],ah		; a second base (or index)?
	jnz	pp_err			; yes
	or	[bx+OP_NUM],al
	jmp	short pp8
pp7m:	dec	si			; (get_num takes the minus sign)
pp7:	call	get_num
	jc	pp_err
	add	[bx+OP_VAL],ax
	adc	[bx+OP_SEG],dx
pp8:	call	skip_space
	lodsb
	cmp	al,'+'
	je	pp6
	cmp	al,'-'
	je	pp7m
	cmp	al,']'
	jne	pp_err
	test	[a_sz],SZ_ADDR		; 32-bit addressing?
	jz	pq16			; no
;
; 32-bit addressing: r/m 4 means a SIB follows, and a SIB with base 5 (with
; mod 0) means a disp32 and no base; ESP as a base needs a SIB (with index
; 4, meaning none), and EBP as a base needs a displacement (like BP).
;
	mov	ax,word ptr [bx+OP_DLEN]	; AL = 1 (base) + 2 (index)
	mov	cx,8004h		; (a SIB, and mod 2 means a disp32)
	test	al,1			; a base?
	jnz	pq6			; yes
	or	ah,5			; no
	mov	[bx+OP_SIBB],ah
	mov	ax,0404h		; mod 0, r/m 4 (and a disp32)
	jmp	short pq4
pq6:	test	al,2			; an index?
	mov	al,4			; (r/m 4: a SIB)
	jnz	pq7			; yes
	cmp	ah,al			; is the base ESP?
	jne	pq6a			; no
	or	ah,20h			; yes (so a SIB with no index)
	jmp	short pq7
pq6a:	mov	al,ah			; r/m is the base
	mov	ch,0			; (and no SIB)
pq7:	mov	[bx+OP_SIBB],ah
	and	ah,7
	cmp	ah,5			; is the base EBP?
	je	pq3			; yes, so it needs a displacement
	mov	dx,[bx+OP_VAL]
	or	dx,[bx+OP_SEG]		; a displacement?
	jnz	pq3			; yes
	mov	ah,0
	jmp	short pq4
pq16:	mov	dx,[bx+OP_SEG]
	call	chk_hw			; is the displacement 16 bits?
	jne	pq_err			; no
	mov	al,[bx+OP_NUM]
	test	al,0Fh			; a base?
	jnz	pq1			; yes
	mov	cl,4
	shr	al,cl			; (an index alone is in bits 0-3)
	jz	pq5			; no registers, so a direct address
pq1:	mov	di,offset RMTAB+8
pq2:	dec	di
	cmp	al,[di]
	jne	pq2
	sub	di,offset RMTAB
	xchg	ax,di			; AL = r/m (and AH = 0)
	mov	cx,2			; (no SIB, and mod 2 means a disp16)
	cmp	word ptr [bx+OP_VAL],0	; a displacement?
	jne	pq3			; yes
	cmp	al,6			; [BP]? (mod 0 means a direct address)
	jne	pq4			; no
;
; AL = ModRM (with mod 0), CH = 80h if a SIB follows (and 0 if not), and CL
; = the displacement's length with mod 2 (2 or 4).
;
pq3:	mov	ah,1
	or	al,40h			; mod 1 (an 8-bit displacement)
	push	ax
	mov	ax,[bx+OP_VAL]
	call	chk_sb			; a signed byte?
	jne	pq3a			; no
	test	[a_sz],SZ_ADDR		; in 32 bits, too (if 32-bit)?
	jz	pq3a			; (yes, if 16-bit)
	cwd
	cmp	dx,[bx+OP_SEG]
pq3a:	pop	ax
	je	pq4			; yes
	mov	ah,cl
	xor	al,0C0h			; mod 2 (a 16-bit or 32-bit one)
pq4:	or	ah,ch
	mov	[bx+OP_NUM],al
	mov	[bx+OP_DLEN],ah
	ret
pq5:	mov	ax,0206h		; mod 0, r/m 6 (and a disp16)
	mov	ch,0			; (no SIB)
	jmp	pq4
pq_err:	jmp	asm_err
;
; A 32-bit register in memory (see pp5): as a base, or as an index (with a
; scale).
;
pr1:	cmp	byte ptr [bx+OP_NUM],0	; after a 16-bit one?
	jne	pq_err			; yes
	or	[a_sz],SZ_ADDR
	and	al,7
	xchg	dx,ax			; DL = register
	call	skip_space
	mov	al,0			; AL = scale (as in SIB bits 6-7)
	cmp	byte ptr [si],'*'	; a scale?
	jne	pr4			; no
	inc	si
	call	skip_space
	lodsb
	sub	al,'1'			; AL = 0, 1, 3, or 7 (1, 2, 4, or 8)
	cmp	al,7
	ja	pq_err
	mov	ah,0
pr2:	shr	al,1
	jnc	pr3
	add	ah,40h
	jmp	pr2
pr3:	jnz	pq_err			; (not a power of 2)
	xchg	al,ah
	jmp	short pr5
pr4:	test	byte ptr [bx+OP_DLEN],1	; a base yet?
	jnz	pr5			; yes, so this is the index
	inc	byte ptr [bx+OP_DLEN]
	or	[bx+OP_SIBB],dl
	jmp	pp8
pr5:	test	byte ptr [bx+OP_DLEN],2	; an index yet?
	jnz	pq_err			; yes
	cmp	dl,4			; ESP?
	je	pq_err			; yes (it can't be one)
	or	byte ptr [bx+OP_DLEN],2
	mov	cl,3
	shl	dl,cl
	or	al,dl
	or	[bx+OP_SIBB],al
	jmp	pp8
;
; set_size sets the operand's size (AL), and 32-bit operands for a dword.
;
set_size:
	mov	[bx+OP_SIZE],al
	cmp	al,SZ_D			; a dword?
	jne	sz9			; no
	or	[a_sz],SZ_OP
sz9:	ret
ENDPROC	parse_opnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_seg
;
; Inputs:
;	AL = register (as in REGNAMES), which must be a segment register
;	SI -> the colon that must follow it
;
; Outputs:
;	a_segp = its override prefix (or it goes to asm_err); SI advanced
;
; Modifies:
;	AX, CL, SI
;
DEFPROC	set_seg
	sub	al,16
	cmp	al,6			; a segment register?
	jae	ss8			; no
	cmp	byte ptr [si],':'
	jne	ss8
	inc	si
	cmp	al,4			; FS or GS?
	jb	ss1			; no
	cmp	byte ptr OPTAB[(64h-60h)*2+1],PFX_SEG	; are there any here?
	jne	ss8			; no (see set_cpu)
	add	al,64h-4		; 64h or 65h
	jmp	short ss2
ss1:	mov	cl,3
	shl	al,cl
	add	al,26h			; 26h, 2Eh, 36h, or 3Eh
ss2:	mov	[a_segp],al
	ret
ss8:	jmp	asm_err
ENDPROC	set_seg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_reg
;
; Inputs:
;	SI -> text
;
; Outputs:
;	If carry clear, AL = register (as in REGNAMES, or 24-31 for EAX-EDI),
;	and SI advanced
;
; Modifies:
;	AX, DI
;
DEFPROC	get_reg
	call	gr0			; an 8-bit, 16-bit, or segment reg?
	jnc	gr9			; yes
	push	si
	lodsb
	cmp	al,'E'			; a 32-bit register (eg, EAX)?
	jne	gr8			; no
	call	gr0
	jc	gr8
	sub	al,8
	cmp	al,8			; EAX through EDI?
	jae	gr8			; no
	add	al,24			; (carry clear)
	pop	di
	ret
gr8:	pop	si
	stc
	ret
gr0:	lea	di,[si+2]
	call	chk_end			; are there just two letters?
	stc
	jne	gr9			; no
	push	bx
	mov	ax,[si]
	mov	bx,offset REGNAMES
gr1:	cmp	ax,[bx]
	je	gr2
	inc	bx
	inc	bx
	cmp	bx,offset REGNAMES+2*22	; (22 registers)
	jb	gr1
	stc
	jmp	short gr7
gr2:	mov	si,di
	sub	bx,offset REGNAMES
	xchg	ax,bx
	shr	al,1			; (carry clear)
gr7:	pop	bx
gr9:	ret
ENDPROC	get_reg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_num
;
; Parse a hex value of up to 8 digits, which may follow a minus sign.
;
; Inputs:
;	SI -> text
;
; Outputs:
;	If carry clear, DX:AX = value, and SI advanced
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	get_num
	call	skip_space
	cmp	byte ptr [si],'-'	; negative?
	pushf
	jne	gn1			; no
	inc	si
gn1:	sub	ax,ax
	cwd				; DX:AX = value
	push	si
gn2:	mov	cl,[si]
	sub	cl,'0'
	cmp	cl,10
	jb	gn3
	sub	cl,'A'-'0'-10
	cmp	cl,10
	jb	gn5
	cmp	cl,16
	jae	gn5
gn3:	test	dh,0F0h			; room for another digit?
	jnz	gn8			; no
	mov	ch,4
gn4:	shl	ax,1
	rcl	dx,1
	dec	ch
	jnz	gn4
	or	al,cl
	inc	si
	jmp	gn2
gn5:	pop	cx
	popf				; negative?
	jne	gn6			; no
	neg	dx
	neg	ax
	sbb	dx,0
gn6:	cmp	cx,si			; any digits?
	cmc				; (carry set if not)
	ret
gn8:	pop	cx
	popf
	stc
	ret
ENDPROC	get_num

;
; chk_hw
;
; Inputs:
;	DX = high word of a value
;
; Outputs:
;	ZF set if the value fits in 16 bits (DX is 0 or FFFFh)
;
DEFPROC	chk_hw
	push	dx
	inc	dx
	shr	dx,1
	pop	dx
	ret
ENDPROC	chk_hw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_op
;
; Find a mnemonic (see find_mnem), including SETcc, which is SET followed by
; any condition that Jcc accepts (eg, SETNE).
;
; Inputs:
;	SI -> text
;
; Outputs:
;	If carry clear, AL = mnemonic, AH = size suffix, and SI advanced
;
; Modifies:
;	AX, DI, SI
;
DEFPROC	find_op
	call	find_mnem
	jnc	fo9
	cmp	word ptr [si],'E' SHL 8 + 'S'	; SET?
	jne	fo8
	cmp	byte ptr [si+2],'T'
	jne	fo8
	inc	si
	inc	si
	mov	byte ptr [si],'J'	; so look up the Jcc for its condition
	call	find_mnem
	jc	fo9
	sub	al,M_JO
	cmp	al,16			; was it one?
	cmc
	jc	fo9			; no
	add	al,M_SETO		; yes, so it's SETcc (carry clear)
fo9:	ret
fo8:	stc
	ret
ENDPROC	find_op

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_mnem
;
; Find a name in MNEMS (or ALIASES), which PUSHA through OUTS may follow
; with a size suffix: B, W, or D (eg, MOVSB, or PUSHAD).
;
; Inputs:
;	SI -> text
;
; Outputs:
;	If carry clear, AL = index, and SI advanced, and AH = 0 (B), 1 (W),
;	3 (D), or 80h (no suffix)
;
; Modifies:
;	AX, DI, SI (only if found)
;
DEFPROC	find_mnem
	push	bx
	push	dx
	mov	bx,offset MNEMS
	mov	dl,0			; DL = index
fm1:	call	cmp_name
	jc	fm3
	call	chk_end			; the whole name?
	je	fm7			; yes
	mov	al,dl
	sub	al,M_PUSHA
	cmp	al,M_OUTS+1-M_PUSHA	; can it have a suffix?
	jae	fm3			; no
	mov	al,[di]
	inc	di
	mov	ah,0
	cmp	al,'B'
	je	fm2
	inc	ah
	cmp	al,'W'
	je	fm2
	mov	ah,3
	cmp	al,'D'
	jne	fm3
fm2:	call	chk_end
	je	fm8
fm3:	inc	dl
	cmp	dl,MNEM_CNT
	jb	fm1
	mov	bx,offset ALIASES
fm4:	mov	dl,[bx]			; DL = the index it means
	inc	bx
	call	cmp_name
	jc	fm5
	call	chk_end
	je	fm7
fm5:	cmp	bx,offset ALIASES_END
	jb	fm4
	stc
	jmp	short fm9
fm7:	mov	ah,80h			; (no suffix)
fm8:	mov	al,dl
	mov	si,di
	clc
fm9:	pop	dx
	pop	bx
	ret
ENDPROC	find_mnem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmp_name
;
; Inputs:
;	BX -> name (bit 7 set in its last character)
;	SI -> text
;
; Outputs:
;	BX -> after the name; carry clear if the text starts with it (DI ->
;	the text after it)
;
; Modifies:
;	AX, BX, DI
;
DEFPROC	cmp_name
	mov	di,si
	mov	ah,0			; AH = characters that differ
cn1:	mov	al,[bx]
	inc	bx
	xor	al,[di]
	inc	di
	test	al,7Fh			; the same?
	jz	cn2			; yes
	inc	ah
cn2:	test	al,al			; the name's last character?
	jns	cn1			; no
	neg	ah			; carry set if any differed
	ret
ENDPROC	cmp_name

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_end
;
; Inputs:
;	DI -> character
;
; Outputs:
;	ZF set if it ends a name (it isn't a letter or digit)
;
; Modifies:
;	AL
;
DEFPROC	chk_end
	mov	al,[di]
	sub	al,'0'
	cmp	al,10
	jb	ce9
	sub	al,'A'-'0'
	cmp	al,26
ce9:	sbb	al,al			; AL = 0 unless a letter or digit
	ret
ENDPROC	chk_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; probe
;
; Decode an opcode (or with a_page, 0Fh and an opcode) and a ModRM (with mod
; 0 and r/m 0, unless it's ESC), just far enough to get its mnemonic and
; operand types.
;
; Inputs:
;	AL = opcode, AH = ModRM
;
; Outputs:
;	If carry clear, AL = mnemonic, and a_hm = 1 if there's a ModRM (decode
;	has the rest; eg, opnds and wbit); carry set if it's a prefix
;
; Modifies:
;	AX, BX, CX, SI, DI
;
DEFPROC	probe
	push	dx
	mov	di,offset a_probe
	cmp	[a_page],0
	je	pb1
	mov	byte ptr [di],0Fh
	inc	di
pb1:	mov	[di],ax			; the opcode and ModRM
	mov	di,offset a_probe
	xor	[mute],MUTE_PROBE
	call	decode
	xor	[mute],MUTE_PROBE
	xchg	ax,di
	sub	ax,offset a_probe+1
	sub	al,[a_page]
	mov	[a_hm],al		; 1 if decode fetched a ModRM
	mov	al,[opcode]
	cmp	al,[a_probe]		; was the opcode a prefix?
	stc
	jne	pb9			; yes
	mov	al,[mnemonic]
	clc
pb9:	pop	dx
	ret
ENDPROC	probe

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; try_enc
;
; If the opcode that probe decoded has the mnemonic, and the operands fit
; its operand types, encode it, and keep it if it's the shortest so far.
; Memory without a size keyword can be a byte or a word, so the sizes it's
; given are recorded in a_mask, and if it fits both, it's an error (see
; asm_line).
;
; Inputs:
;	AL = mnemonic
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
DEFPROC	try_enc
	cmp	al,[a_mnem]		; the mnemonic we want?
	je	te0			; yes
	ret
te0:	mov	[a_sp],sp		; (see ae_fail)
	mov	[a_ms],0
	mov	al,[wbit]
	mov	ah,[opnds]
	and	ah,0F0h
	cmp	ah,50h			; a register in the opcode first?
	jne	te1			; no
	mov	al,[a_op]
	and	al,0F8h
	cmp	al,0B0h			; MOV reg8,imm8 (see op_z)?
	mov	al,0
	je	te1			; yes
	inc	ax
te1:	cmp	al,1			; words?
	jne	te1a			; no
	test	[a_sz],SZ_OP		; dwords?
	jz	te1a			; no
	mov	al,SZ_D
te1a:	mov	[a_w],al
	mov	ah,[a_mnem]
	sub	ah,M_MOVS
	cmp	ah,M_OUTS+1-M_MOVS	; a string op?
	jae	te2			; no
	mov	ah,[a_isize]
	and	ah,83h			; AH = 0 (B), 1 (W), 3 (D), or 80h
	cmp	ah,al			; the size we want?
	je	te2			; yes
	ret
te2:	mov	di,offset a_cand
	call	emit_pfx
	cmp	[a_page],0
	je	te3
	mov	al,0Fh
	stosb
te3:	mov	al,[a_op]
	stosb
	sub	bp,bp			; BP -> ModRM (or 0 if none)
	cmp	[a_hm],0
	je	te4
	mov	bp,di
	mov	al,[a_reg]
	stosb
te4:	mov	bx,offset a_ops
	mov	al,[opnds]
	mov	cl,4
	shr	al,cl
	call	te_opnd			; the first operand
	mov	al,[opnds]
	and	al,0Fh
	call	te_opnd			; the second
	mov	al,[opcode]
	xor	al,69h
	test	al,0FDh			; IMUL reg,r/m,imm (69h or 6Bh)?
	jnz	te5			; no
	shr	al,1
	add	al,6			; AL = 6 (imm) or 7 (signed imm8)
	call	te_opnd			; the third
te5:	cmp	byte ptr [bx+OP_KIND],0	; any operands left?
	jne	ae_fail			; yes
	mov	al,[a_ms]
	or	[a_mask],al
	xchg	ax,di
	sub	ax,offset a_cand	; AX = length
	cmp	al,[a_len]		; the shortest so far?
	jae	te9			; no
	mov	[a_len],al
	xchg	cx,ax
	mov	si,offset a_cand
	mov	di,offset a_best
	rep	movsb
te9:	ret
;
; Any operand that doesn't fit comes here, from anywhere in try_enc.
;
ae_fail:
	mov	sp,[a_sp]
	ret
ENDPROC	try_enc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; te_opnd
;
; Check and encode an operand, and advance to the next.
;
; Inputs:
;	AL = operand type (see ASM_TAB; 0 if none)
;	BX -> operand
;	DI -> encoding (BP -> its ModRM, if any)
;
; Outputs:
;	BX and DI advanced (or it goes to ae_fail)
;
; Modifies:
;	AX, CX, DX, SI
;
; Each ae_* procedure gets AL = number (OP_NUM), CL = kind, CH = size, and
; DX = value.
;
DEFPROC	te_opnd
	test	al,al			; an operand?
	jz	to9			; no
	call	fix_type
to1:	mov	cx,[bx+OP_KIND]		; CL = kind, CH = size
	mov	dx,[bx+OP_VAL]
	cmp	cl,K_IMM		; an immediate
	jne	to1a
	mov	si,[bx+OP_SEG]
	inc	si
	shr	si,1			; that fits in 16 bits?
	jz	to1a			; yes
	cmp	[a_w],SZ_D		; no, so it must be a dword's
	jne	to_no			; (imm or signed imm8)
	mov	ah,al
	sub	ah,6
	cmp	ah,1
	ja	to_no			; (ZF is clear)
to1a:	cmp	al,6			; an immediate (types 6-0Bh)?
	jb	to2			; no
	cmp	al,0Ch
	jae	to2			; no
	cmp	cl,K_IMM		; yes, so is it one?
to_no:	jne	ae_fail			; no
to2:	cbw
	xchg	si,ax
	shl	si,1
	mov	al,[bx+OP_NUM]
	call	ASM_TAB[si-2]
	add	bx,OP_LEN
to9:	ret

ae_ex:	mov	ah,[a_op]		; MOVZX or MOVSX r/m (whose size
	and	ah,1			; is bit 0 of the opcode)
	jmp	short ae_e2
ae_e:	mov	ah,[a_w]		; r/m
ae_e2:	cmp	cl,K_REG
	jne	ae_m
	cmp	ch,ah
	jne	ae_fail
	or	al,0C0h			; (mod 3)
ae_or:	or	ds:[bp],al
	ret
ae_m:	cmp	cl,K_MEM
ae_nm:	jne	ae_fail			; (see ae_s)
	call	chk_ms
	or	ds:[bp],al
	lea	si,[bx+OP_VAL]
	mov	cl,[bx+OP_DLEN]
	test	cl,cl			; a SIB?
	jns	am1			; no
	dec	si			; yes (it's just before OP_VAL)
	sub	cl,80h-1
am1:	mov	ch,0
	rep	movsb			; the SIB and displacement
	ret

ae_g:	call	chk_rw			; ModRM reg
ae_reg:	mov	cl,3
	shl	al,cl
	jmp	ae_or

ae_s:	cmp	cl,K_SREG		; segment register
	jne	ae_nm
	mov	dl,al
	test	bp,bp			; in ModRM reg?
	jz	as1			; no, in the opcode (see op_s)
	call	ae_reg
	mov	al,dl
	jmp	short as2
as1:	mov	al,[modrm]
	mov	cl,3
	shr	al,cl
as2:	and	al,byte ptr [op_sreg+1]	; (the ones there are; see set_cpu)
	jmp	short ae_num

ae_a:	mov	dl,0			; AL or AX
	jmp	short ae_z1
ae_z:	mov	dl,[a_op]		; register in the opcode
	and	dl,7
ae_z1:	call	chk_rw
ae_num:	cmp	al,dl
	jne	ae_no
	ret

ae_dx:	mov	dx,0102h		; DX (a word, register 2)
	jmp	short ae_rn
ae_cl:	mov	dx,0001h		; CL (a byte, register 1)
ae_rn:	mov	ah,dh
	call	chk_r
	jmp	ae_num
ae_sh:	test	[a_op],2		; 1 or CL: CL (D2h or D3h)?
	jnz	ae_cl			; yes
	cmp	cl,K_IMM
	jne	ae_no
	dec	dx			; 1?
	jnz	ae_no			; no
	ret

ae_gx:	call	ae_g			; SHLD and SHRD: reg,
	add	bx,OP_LEN
	mov	cx,[bx+OP_KIND]
	mov	dx,[bx+OP_VAL]
	mov	al,[bx+OP_NUM]
	test	[a_op],1		; and CL?
	jnz	ae_cl			; yes
	cmp	cl,K_IMM		; no, imm8
	jne	ae_no
	jmp	ae_ib

;
; chk_rw checks for a register of the operands' size (a_w), and chk_r of
; size AH, and chk_ms checks memory's size against AH, unless it has none,
; when it records the size it would be in a_ms (bit n for size n, as in
; OP_SIZE, or none for no size; FAR is never assumed).
;
chk_rw:	mov	ah,[a_w]
chk_r:	cmp	cl,K_REG
	jne	ae_no
	cmp	ch,ah
	jne	ae_no
	ret
chk_ms:	cmp	ch,0FFh			; no size?
	jne	cms1			; no
	cmp	ah,2			; FAR?
	je	ae_no			; yes
	mov	cl,ah
	mov	ah,1
	shl	ah,cl			; (0 for FFh, no size)
	mov	[a_ms],ah
	ret
cms1:	cmp	ch,ah
	jne	ae_no
	ret
;
; ae_no is ae_fail, for the jumps that can't reach it.
;
ae_no:	mov	sp,[a_sp]
	ret

ae_ctl:	mov	ah,[a_op]		; CRn, DRn, or TRn (ModRM reg)
	and	ah,5			; (as in op_sr)
	cmp	cl,K_CTL
	jne	ae_no
	cmp	ch,ah
	jne	ae_no
	jmp	ae_reg

ae_r32:	mov	ah,SZ_D			; 32-bit register (ModRM r/m)
	call	chk_r
	or	al,0C0h
	jmp	ae_or


ae_i:	xchg	ax,dx			; imm (byte, word, or dword)
	cmp	[a_w],0
	jne	ae_iv
	test	ah,ah			; 00h-FFh?
	jz	ae_b			; yes
	jmp	short ae_sb1		; no, so it must be -80h to -1
ae_j8:	cmp	ch,SZ_NEAR		; rel8 (unless NEAR)
	je	ae_no
	call	ae_rel
	dec	ax
	jmp	short ae_sb1
ae_sib:	xchg	ax,dx			; signed imm8
ae_sb1:	call	chk_sb
	jne	ae_no
	cmp	[a_w],SZ_D		; a dword's?
	jne	ae_b			; no
	cwd				; yes, so it's a signed byte in 32 bits
	cmp	dx,[bx+OP_SEG]		; too?
	jne	ae_no			; no
ae_b:	stosb
	ret
ae_iv:	stosw				; imm16 (or imm32)
	cmp	[a_w],SZ_D
	jne	ae_b9
	mov	ax,[bx+OP_SEG]
	stosw
ae_b9:	ret
ae_ib:	xchg	ax,dx			; imm8
	test	ah,ah
	jz	ae_b
	jmp	ae_no
ae_j16:	cmp	ch,SZ_SHORT		; rel16 (unless SHORT)
	je	ae_no
	call	ae_rel
	dec	ax
	dec	ax
	jmp	short ae_w
ae_o:	cmp	cl,K_MEM		; [addr]
	jne	ae_no
	cmp	word ptr [bx+OP_NUM],0206h	; a 16-bit direct address?
ae_on:	jne	ae_no			; no (and see ae_ap)
	mov	ah,[a_w]
	call	chk_ms
ae_iw:	xchg	ax,dx			; imm16
ae_w:	stosw
	ret

ae_ap:	cmp	cl,K_FAR		; segment:offset
	jne	ae_on
	test	[a_sz],SZ_OP		; (not with 32-bit offsets)
	jnz	ae_on
	xchg	ax,dx
	stosw
	mov	ax,[bx+OP_SEG]
	stosw
	ret

ae_rel:	test	[a_sz],SZ_OP		; (not with 32-bit offsets)
	jnz	ae_on
	xchg	ax,dx			; AX = the jump's distance from the
	sub	ax,[a_off]		; next byte
	sub	ax,di
	add	ax,offset a_cand
	ret

ae_st:	mov	ah,0			; ST
	jmp	short ast1
ae_sti:	mov	ah,[a_reg]		; ST(i), with i in ModRM r/m (see af0)
	and	ah,7
ast1:	cmp	cl,K_ST
	jne	ae_on
	cmp	al,ah
	jne	ae_on
	ret
ae_fm:	mov	ah,[a_w]		; 80x87 memory (sized by wbit)
	jmp	ae_m
ENDPROC	te_opnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; emit_pfx
;
; Inputs:
;	DI -> encoding
;
; Outputs:
;	DI advanced past any prefixes
;
; Modifies:
;	AX, DI
;
DEFPROC	emit_pfx
	mov	ax,word ptr [a_pfx]	; AL = LOCK or REP, AH = segment
	call	ep1
	mov	al,ah
	call	ep1
	mov	ah,[a_sz]
	mov	al,66h
ep0:	shr	ah,1			; SZ_OP (66h), then SZ_ADDR (67h)?
	jnc	ep2			; no
	stosb
ep2:	inc	ax
	cmp	al,68h
	jb	ep0
	ret
ep1:	test	al,al
	jz	ep9
	stosb
ep9:	ret
ENDPROC	emit_pfx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_sb
;
; Inputs:
;	AX = value
;
; Outputs:
;	ZF set if it's a signed byte (-80h to 7Fh)
;
DEFPROC	chk_sb
	push	ax
	add	al,80h
	adc	ah,0
	pop	ax
	ret
ENDPROC	chk_sb

CODE	ends

	end
