;
; BASIC-DOS Loadable Serial Debugger
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage (in CONFIG.SYS): DEVICE=BIN\DEBUG.COM COM2:9600,N,8,1,VT100
;
; DEBUG.COM can also be run as a program (DEBUG [program [arguments]]), with
; a monitor on the console.  It loads the program without starting it and
; displays the registers as of the program's start; G runs it, and Q (or the
; program's termination) exits.  Without a program, the registers are as of
; DEBUG's own start (PSP:0100h), and G exits.
;
; Ctrl-C or a serial BREAK stops the machine as soon as it arrives (via the
; port's hardware interrupt), as do breakpoints, single-steps (T), and any
; other INT 1 or INT 3.  The monitor displays the registers and the current
; instruction, and then accepts commands (? lists them) until G or T.
;
; Only INIT calls DOS.  The monitor can interrupt DOS (or an IRQ handler),
; so it runs on a private stack with interrupts disabled, polling the UART
; of a COM port that INIT opened with MODE_DENY_RW.  For the same reason, it
; can't use the DOS utility functions (eg, SPRINTF), which enable
; interrupts and reenter the DOS dispatcher.
;
	DOSFUNC equ 1
	DOSHEAP equ 1
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	uart.inc
	include	version.inc

CODE	segment para public 'CODE'

;
; When run as a program, execution begins at the DDH, so DDH_NEXT_OFF holds a
; JMP SHORT to in_buf, which DOS accepts in place of FFFFh (see load_devices).
;
COM_JMP		equ	((size DDH - 2) SHL 8) OR 0EBh

DBGDEV	DDH	<COM_JMP,-1,DDATTR_CHAR,dbgdev_req,0,2020244755424544h>
;
; in_buf must follow the DDH: its initial contents (which don't matter to the
; driver) are a JMP to com_main, which (like everything that runs only as a
; program) follows resident_end, so a driver doesn't keep it.
;
IN_MASK		equ	127	; in_buf is a ring buffer, with one slot unused
	ASSUME	CS:CODE
	DEFLBL	in_buf,byte
	jmp	near ptr com_main
	db	IN_MASK+1-3 dup (0)
;
; The interrupted registers are copied from the interrupted stack to regs,
; where the monitor can change them (even SS:SP), and then copied back (see
; resume).  These are their offsets, in the order they're pushed, from last
; to first; SP and SS are saved as they were before the interrupt.
;
R_SP		equ	0
R_SS		equ	2
R_DS		equ	6
R_IP		equ	22
R_CS		equ	24
R_FL		equ	26
REGS_LEN	equ	28
;
; Each breakpoint (BP_TAB entry) has an offset, segment, original byte, and
; state; entry 0 is the temporary breakpoint for G addr.
;
BP_SET		equ	01h	; breakpoint is set
BP_ARMED	equ	02h	; breakpoint's INT 3 is in memory
BP_SIZE		equ	6
NUM_BPS		equ	10
CMD_TAIL	equ	80h	; PSP_CMDTAIL (see com_main)

	DEFPTR	old_com			; original COM interrupt handler
	DEFPTR	dos_vars		; DOSVARS + 2 (see hook_vecs)
	DEFWORD	com_port,0		; UART base port
	DEFWORD	dump_off,0		; offset of the next D command
	DEFWORD	dump_seg,0		; segment of the next D command
	DEFBYTE	dump_size,1		; 1 (DB) or 2 (DW), for the next D
	DEFWORD	u_off,0			; offset of the next U command
	DEFWORD	u_seg,0			; segment of the next U command
	DEFWORD	trace_cnt,0		; T steps remaining
	DEFWORD	regs,0,REGS_LEN/2	; saved registers
	DEFBYTE	bp_tab,0,BP_SIZE*NUM_BPS
	DEFLBL	bp_end
	DEFBYTE	com_flow,0		; COMDBG_XON and/or COMDBG_RTS
	DEFBYTE	paused,0		; set by XOFF, cleared by XON
	DEFBYTE	in_head,0		; next byte to read from in_buf
	DEFBYTE	in_tail,0		; next byte to write in in_buf
	DEFBYTE	why,0			; 1 (INT 1), 3 (INT 3), else 0
	DEFBYTE	tracing,0		; 1 for T, 2 for G past a breakpoint
	DEFBYTE	col,0			; output column (see pad)
	DEFBYTE	mute,0			; nonzero to discard output
;
; Disassembler state (see decode).
;
	DEFBYTE	opcode,0
	DEFBYTE	modrm,0			; ModRM byte (or opcode, if none)
	DEFBYTE	wbit,0			; 0 (byte), 1 (word), or 2 (far)
	DEFBYTE	opnds,0			; operand types (see OPND_TAB)
	DEFBYTE	seg_ovr,0		; segment override (as in REGNAMES)
;
; Register names, with offsets of the saved registers in regs, in display
; order.
;
	DEFLBL	REG_TABLE,byte
	db	"AX",20,"BX",18,"CX",16,"DX",14,"SP",0,"BP",12,"SI",10,"DI",8
	DEFLBL	SEG_TABLE,byte
	db	"DS",6,"ES",4,"SS",2,"CS",24,"IP",22
;
; Flag names (clear, set), for the flags in FLAG_MASK, from high to low;
; they must immediately follow REG_TABLE (see show_regs).
;
FLAG_MASK	equ	0ED5h	; OF, DF, IF, SF, ZF, AF, PF, and CF
	DEFLBL	FLAG_NAMES,byte
	db	"NVOV","UPDN","DIEI","PLNG","NZZR","NAAC","POPE","NCCY"
	DEFLBL	FLAG_END,byte

	DEFLBL	HELP_MSG,byte
	db	"BC n|*",9,9,"clear breakpoint(s)",13,10
	db	"BL",9,9,"list breakpoints",13,10
	db	"BP [n] addr",9,"set breakpoint",13,10
	db	"DB [range]",9,"dump bytes",13,10
	db	"DW [range]",9,"dump words",13,10
	db	"DM",9,9,"dump memory arena",13,10
	db	"E addr [list]",9,"edit memory",13,10
	db	"G [addr]",9,"go (to address)",13,10
	db	"R [reg | F]",9,"display or edit registers",13,10
	db	"T [count]",9,"trace",13,10
	db	"U [range]",9,"unassemble",13,10,0

;
; Commands, and the procedures that perform them (with SI -> the text after
; the command letter); each returns carry set if the command was invalid.
;
	DEFLBL	CMD_TABLE,byte
	db	'B'
	dw	cmd_b
	db	'D'
	dw	dump_memory
	db	'E'
	dw	cmd_e
	db	'G'
	dw	cmd_g
	db	'R'
	dw	cmd_r
	db	'T'
	dw	cmd_t
	db	'U'
	dw	cmd_u
	db	'?'
	dw	cmd_help
	DEFLBL	CMD_Q,byte
	db	0			; program mode changes this to 'Q'
	dw	com_quit
	db	0
;
; Mnemonics, each with bit 7 set in its last character, and an M_ equate
; with its index (see put_mnem); bit 7 of an index in OPTAB means "word"
; and indexes 78h-7Ch are groups (see decode), so there can be only 120.
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
	MNEM	MOVS			; 28h-2Ch: B or W is appended
	MNEM	CMPS
	MNEM	STOS
	MNEM	LODS
	MNEM	SCAS
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
	MNEM	CALL
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
	MNEM	<INT 3>,INT3
	MNEM	INT
	MNEM	INTO
	MNEM	IRET
	MNEM	AAM
	MNEM	AAD
	MNEM	XLAT
	MNEM	ESC
	MNEM	LOOPNZ
	MNEM	LOOPZ
	MNEM	LOOP
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
; Groups 3, 4, and 5 (mnemonics for each ModRM reg); bit 7 means "far".
;
	DEFLBL	GRPS,byte
	db	M_TEST,M_BAD,M_NOT,M_NEG,M_MUL,M_IMUL,M_DIV,M_IDIV
	db	M_INC,M_DEC,M_BAD,M_BAD,M_BAD,M_BAD,M_BAD,M_BAD
	db	M_INC,M_DEC,M_CALL,M_CALL+80h,M_JMP,M_JMP+80h,M_PUSH,M_BAD
;
; Opcodes 80h-FFh: mnemonic (or group) and operand types; operand type FFh
; marks a prefix.
;
G1	equ	78h
G2	equ	79h
G3	equ	7Ah
G4	equ	7Bh
G5	equ	7Ch
	DEFLBL	OPTAB,byte
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
	db	M_BAD,0, M_BAD,0, M_RET,90h, M_RET,0		; C0h
	db	M_LES+80h,21h, M_LDS,21h, M_MOV,16h, M_MOV,16h
	db	M_BAD,0, M_BAD,0, M_RETF,90h, M_RETF,0		; C8h
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

	DEFLBL	ALU_OPS,byte		; operands of ALU opcodes 00h-3Fh
	db	12h,21h,46h
;
; ModRM r/m (when mod isn't 3): base and index register names (as in
; REGNAMES, with index 0 meaning none).
;
	DEFLBL	RMTAB,byte
	db	0EBh,0FBh,0EDh,0FDh,0Eh,0Fh,0Dh,0Bh

	DEFLBL	REGNAMES,byte
	db	"ALCLDLBLAHCHDHBHAXCXDXBXSPBPSIDIESCSSSDS"

CMD_MAX		equ	79
	DEFBYTE	command,0,CMD_MAX+1
	DEFWORD	mon_stack,0,128
	DEFLBL	mon_stack_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dbgdev_req
;
; Only INIT is supported.
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;	DDP_STATUS updated
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	dbgdev_req,far
	cmp	es:[bx].DDP_CMD,DDC_INIT
	jne	drq8
	jmp	near ptr dbgdev_init
drq8:	mov	es:[bx].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	ret
ENDPROC	dbgdev_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dbgdev_com (COM hardware interrupt)
;
; Enter the monitor if Ctrl-C (or BREAK) was received; other input is
; discarded.  If our UART isn't interrupting, chain to the original handler
; (eg, for another port that shares the IRQ).
;
DEFPROC	dbgdev_com,far
	push	ax
	push	dx
	push	ds
	push	cs
	pop	ds
	ASSUME	DS:CODE
	mov	dx,[com_port]
	add	dx,REG_IIR
	in	al,dx
	test	al,IIR_NO_INT		; is our UART interrupting?
	jnz	dcm8			; no
dcm1:	call	poll_rx
	jz	dcm2
	cmp	al,CHR_CTRLC		; Ctrl-C (or BREAK)?
	je	dcm3			; yes (ZF set)
dcm2:	mov	dx,[com_port]
	add	dx,REG_IIR
	in	al,dx
	test	al,IIR_NO_INT		; anything else pending?
	jz	dcm1			; yes (otherwise, ZF clear)
dcm3:	mov	al,20h
	out	20h,al			; EOI the interrupt
	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	pop	ax
	jz	dbg_brk			; enter the monitor on Ctrl-C
	iret
dcm8:	pop	ds
	pop	dx
	pop	ax
	jmp	cs:[old_com]
ENDPROC	dbgdev_com

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dbgdev_enter (dbg_int1, dbg_int3, and dbg_brk)
;
; Save the interrupted registers on the interrupted stack, copy them to regs,
; and run the monitor on our own stack.
;
; Inputs:
;	Interrupt frame on SS:SP (with interrupts disabled)
;
DEFPROC	dbgdev_enter,far
	DEFLBL	dbg_int1,near
	push	ax
	mov	al,1
	jmp	short de1
	DEFLBL	dbg_int3,near
	push	ax
	mov	al,3
	jmp	short de1
	DEFLBL	dbg_brk,near
	push	ax
	mov	al,0
de1:	mov	cs:[why],al
	push	bx
	push	cx
	push	dx
	push	bp
	push	si
	push	di
	push	ds
	push	es
	push	ss
	mov	bp,sp
	lea	ax,[bp+REGS_LEN-2]	; AX = SP before the interrupt
	push	ax
	mov	si,sp
	push	ss
	pop	ds
	push	cs
	pop	es
	mov	di,offset regs
	mov	cx,REGS_LEN/2
	cld
	rep	movsw
	push	cs
	pop	ds
	ASSUME	DS:CODE
	push	cs
	pop	ss
	DEFLBL	mon_sp			; (com_main changes this stack)
	mov	sp,offset mon_stack_end
	jmp	monitor
ENDPROC	dbgdev_enter

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; monitor
;
; Remove breakpoints, finish any G past a breakpoint (or T with a count), and
; process commands.
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	monitor
	call	disarm
	mov	al,0
	xchg	al,[tracing]
	test	al,al			; were we tracing?
	jz	mon2			; no
	and	byte ptr regs[R_FL+1],0FEh
	cmp	[why],1			; did a step finish?
	jne	mon2			; no
	dec	al			; was it T?
	jz	mon3			; yes
	call	arm			; no, G past a breakpoint
	jc	mon1			; but we're at another one
	jmp	resume
mon1:	call	disarm
mon2:	mov	[trace_cnt],0
	mov	al,[in_tail]		; discard any buffered input
	mov	[in_head],al
	mov	[paused],0
mon3:	mov	byte ptr bp_tab[5],0	; clear the temporary breakpoint
	mov	ax,regs[R_IP]
	mov	[u_off],ax		; U defaults to CS:IP
	mov	ax,regs[R_CS]
	mov	[u_seg],ax
	mov	ax,regs[R_DS]
	mov	[dump_seg],ax		; D defaults to DS
	call	show_regs
	cmp	[trace_cnt],0		; more T steps?
	je	mon4			; no
	call	do_trace		; (which never returns)

mon4:	mov	al,'-'
	call	put_char
	call	get_line
	mov	si,offset command
	call	skip_space
	lodsb
	test	al,al			; empty line?
	jz	mon4			; yes
	mov	bx,offset CMD_TABLE
mon5:	cmp	al,[bx]
	je	mon6
	add	bx,3
	cmp	byte ptr [bx],0
	jne	mon5
	jmp	short mon8
mon6:	call	word ptr [bx+1]
	jnc	mon4
mon8:	mov	al,'?'
	call	put_char
	call	newline
	jmp	mon4
ENDPROC	monitor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resume
;
; Copy regs to the (possibly new) stack, below the saved SS:SP, and then
; restore them all and IRET.
;
DEFPROC	resume
	les	di,dword ptr regs[R_SP]
	sub	di,REGS_LEN
	push	di
	mov	si,offset regs
	mov	cx,REGS_LEN/2
	rep	movsw
	pop	di
	mov	ax,es
	mov	ss,ax
	lea	sp,[di+4]		; skip the saved SP and SS
	pop	es
	pop	ds
	ASSUME	DS:NOTHING
	pop	di
	pop	si
	pop	bp
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	iret
ENDPROC	resume

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Commands (DS = CS and interrupts disabled; DF clear for strings).
;
; cmd_b
;
; BP[n] addr sets breakpoint n (1-9), or the first free one; BC clears the
; listed breakpoints (or * for all); BL lists them.
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	cmd_b
	lodsb
	cmp	al,'L'
	je	cmd_bl
	cmp	al,'C'
	je	cmd_bc
	cmp	al,'P'
	stc
	jne	cb9
	call	skip_space
	mov	ax,[si]
	cmp	ah,' '			; is this an index?
	jne	cb2			; no
	call	get_slot
	jc	cb2
	inc	si
	jmp	short set_bp
cb2:	mov	bx,offset bp_tab+BP_SIZE
cb3:	test	byte ptr [bx+5],BP_SET	; free?
	jz	set_bp			; yes
	add	bx,BP_SIZE
	cmp	bx,offset bp_end
	jb	cb3
	stc
cb9:	ret

cmd_bc:	call	skip_space
	lodsb
	test	al,al
	jz	cb9
	cmp	al,'*'
	jne	bc2
	mov	bx,offset bp_tab+BP_SIZE+5
	mov	cx,NUM_BPS-1
bc1:	mov	byte ptr [bx],0
	add	bx,BP_SIZE
	loop	bc1
	jmp	cmd_bc
bc2:	call	get_slot
	jc	cb9
	mov	byte ptr [bx+5],0
	jmp	cmd_bc

cmd_bl:	call	end_command
	jc	cb9
	mov	bx,offset bp_tab+BP_SIZE
	mov	dl,'1'
bl1:	test	byte ptr [bx+5],BP_SET
	jz	bl2
	mov	al,dl
	call	put_char
	call	space
	les	di,dword ptr [bx]
	call	dis_line
bl2:	add	bx,BP_SIZE
	inc	dx
	cmp	dl,'9'
	jbe	bl1
	ret
ENDPROC	cmd_b

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_bp
;
; Inputs:
;	BX -> BP_TAB entry
;	SI -> address (the default segment is CS)
;
; Outputs:
;	Carry clear if successful, set if invalid
;
DEFPROC	set_bp
	mov	bp,regs[R_CS]
	push	bx
	call	parse_addr
	pop	bx
	jc	sb9
	call	end_command
	jc	sb9
	mov	[bx],ax
	mov	[bx+2],bp
	mov	byte ptr [bx+5],BP_SET
sb9:	ret
ENDPROC	set_bp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_slot
;
; Inputs:
;	AL = breakpoint number ('1'-'9')
;
; Outputs:
;	If carry clear, BX -> BP_TAB entry
;
; Modifies:
;	AX, BX
;
DEFPROC	get_slot
	sub	al,'1'
	cmp	al,9			; '1'-'9'?
	cmc
	jc	gs9			; no
	inc	ax
	mov	ah,BP_SIZE
	mul	ah
	add	ax,offset bp_tab
	xchg	bx,ax
gs9:	ret
ENDPROC	get_slot

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_e
;
; E addr [list] stores the list of bytes and quoted strings at addr, or if
; there's no list, displays each byte and prompts for a list to replace it;
; an empty line ends.
;
DEFPROC	cmd_e
	mov	bp,[dump_seg]
	call	parse_addr
	jc	ce9
	xchg	di,ax
	mov	es,bp			; ES:DI -> memory
	call	end_command
	jnc	ce1
	jmp	short store_list
ce1:	mov	ax,es
	call	hex_addr
	mov	al,es:[di]
	call	hex_byte
	mov	al,'.'
	call	put_char
	call	get_line
	mov	si,offset command
	call	end_command		; empty line?
	jnc	ce9			; yes
	call	store_list
	jnc	ce1
ce9:	ret
ENDPROC	cmd_e

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; store_list
;
; Inputs:
;	SI -> list of bytes and quoted strings
;	ES:DI -> memory
;
; Outputs:
;	Carry clear if successful (DI updated), set if invalid
;
DEFPROC	store_list
sl1:	call	skip_space
	lodsb
	test	al,al
	jz	sl9
	cmp	al,'"'
	je	sl2
	cmp	al,"'"
	je	sl2
	dec	si
	call	parse_hex
	jc	sl9
	test	ah,ah			; a byte?
	jnz	sl8			; no
	stosb
	jmp	sl1
sl2:	mov	ah,al			; AH = quote
sl3:	lodsb
	test	al,al			; missing the closing quote?
	jz	sl8			; yes
	cmp	al,ah
	je	sl1
	stosb
	jmp	sl3
sl8:	stc
sl9:	ret
ENDPROC	store_list

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_g
;
; G [addr] removes any breakpoint at CS:IP, steps past it, and then sets all
; the breakpoints (including one at addr) and resumes.
;
DEFPROC	cmd_g
	call	end_command
	jnc	cg1
	mov	bx,offset bp_tab
	call	set_bp
	jc	cg9
cg1:	call	arm
	mov	al,2
	jc	step
	jmp	resume
cg9:	ret
ENDPROC	cmd_g

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_t
;
; T [count] executes count (default 1) instructions, displaying the
; registers after each.  Like DEBUG, it steps into an INT (other than one
; that we handle) by simulating it.
;
DEFPROC	cmd_t
	mov	ax,1
	call	end_command
	jnc	ct1
	call	parse_hex
	jc	ct9
	test	ax,ax
	stc
	jz	ct9
	call	end_command
	jc	ct9
ct1:	mov	[trace_cnt],ax
	DEFLBL	do_trace,near
	dec	[trace_cnt]
	les	di,dword ptr regs[R_IP]
	cmp	byte ptr es:[di],0CDh	; INT n?
	jne	ct2			; no
	mov	bl,es:[di+1]
	mov	bh,0
	shl	bx,1
	shl	bx,1
	sub	ax,ax
	mov	es,ax
	les	ax,dword ptr es:[bx]	; ES:AX = vector
	mov	cx,es
	mov	dx,cs
	cmp	cx,dx			; is it one of ours?
	je	ct2			; yes, so let it run
	les	bx,dword ptr regs[R_SP]
	sub	bx,6
	mov	regs[R_SP],bx
	inc	di
	inc	di
	mov	es:[bx],di		; push the return address
	mov	dx,regs[R_CS]
	mov	es:[bx+2],dx
	mov	dx,regs[R_FL]		; and the flags
	mov	es:[bx+4],dx
	and	byte ptr regs[R_FL+1],0FCh	; and clear IF and TF
	mov	regs[R_IP],ax
	mov	regs[R_CS],cx
	pop	ax			; discard our return address
	jmp	mon3
ct2:	mov	al,1
	DEFLBL	step,near
	mov	[tracing],al
	or	byte ptr regs[R_FL+1],01h	; set TF
	jmp	resume
ct9:	ret
ENDPROC	cmd_t

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_r
;
; R displays the registers; R reg displays one and prompts for a new value
; (unless one follows), and R F displays the flags and prompts for new ones.
;
DEFPROC	cmd_r
	call	end_command
	jc	cr1
	call	show_regs
	clc
	ret
cr1:	mov	ax,[si]
	cmp	al,'F'
	jne	cr2
	cmp	ah,' '			; just F?
	ja	cr2			; no
	inc	si
	call	end_command
	jnc	rf0
	ret
cr2:	call	find_reg
	jc	cr9
	inc	si
	inc	si
	cmp	byte ptr [si],' '	; is the name longer?
	ja	cr8			; yes
	call	end_command		; is there a value?
	jc	cr5			; yes
	call	put_2ch
	call	space
	mov	ax,regs[bx]
	call	hex_word
	call	newline
	mov	al,':'
	call	put_char
	push	bx
	call	get_line
	pop	bx
	mov	si,offset command
	call	end_command		; empty line?
	jnc	cr9			; yes
cr5:	call	parse_hex
	jc	cr9
	call	end_command
	jc	cr9
	mov	regs[bx],ax
	ret
cr8:	stc
cr9:	ret

rf0:	call	show_flags
	mov	al,'-'
	call	put_char
	call	get_line
	mov	si,offset command
rf1:	call	skip_space
	lodsw
	test	al,al
	jz	cr9
	mov	bx,offset FLAG_NAMES
	mov	dx,FLAG_MASK
	mov	cx,8000h
rf2:	test	dx,cx			; CX = next flag bit
	jnz	rf3
rf2a:	shr	cx,1
	jmp	rf2
rf3:	cmp	ax,[bx]
	je	rf4
	cmp	ax,[bx+2]
	je	rf5
	add	bx,4
	cmp	bx,offset FLAG_END
	jb	rf2a
	stc
	ret
rf4:	not	cx
	and	regs[R_FL],cx
	jmp	rf1
rf5:	or	regs[R_FL],cx
	jmp	rf1
ENDPROC	cmd_r

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_u
;
; U [range] disassembles 20h bytes (or the range), continuing from the last
; U (or CS:IP).
;
DEFPROC	cmd_u
	mov	bp,[u_seg]
	mov	di,[u_off]
	mov	bx,20h
	call	parse_range
	jc	cu9
	mov	es,bp
	mov	dx,di
cu1:	call	dis_line
	mov	ax,di
	sub	ax,dx
	cmp	ax,bx
	jb	cu1
	mov	[u_off],di
	mov	[u_seg],es
cu9:	ret
ENDPROC	cmd_u

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dump_arena
;
; DM displays memory in address order, as MEM /D once did: the system area
; (from 0000 to the first built-in driver), each built-in driver, DOS, and
; then every memory block in the arena.  Each row has the segment, owner, and
; size (in paragraphs), and a name (or type).  The arena walk stops at an
; invalid MCB, which is reported as an error.
;
DEFPROC	dump_arena
	call	end_command
	jnc	ma0
	ret
ma0:	mov	si,offset MA_HDR
	call	put_string
	les	bx,[dos_vars]
	mov	cx,es			; CX = DOS segment
	les	di,es:[bx-2].DV_DD_LIST	; ES:DI -> first driver
;
; Skip any installed drivers (DEVICE= puts them at the head of the list);
; they're above DOS, in memory blocks of their own, so the arena walk lists
; them.
;
mb1:	mov	bx,es
	cmp	bx,cx			; installed driver?
	jb	mb2			; no
	les	di,es:[di]
	jmp	mb1
mb2:	sub	ax,ax			; AX = segment 0
	cwd				; DX = owner (none)
	call	ma_row			; BX = paras (up to the first driver)
	mov	dl,MCBOWNER_SYSTEM
	call	put_type
;
; Each built-in driver ends where the next one begins; the last one's next
; pointer has an offset of -1 and the next available segment.
;
mb3:	mov	ax,es
	mov	bx,es:[di].DDH_NEXT_SEG
	sub	bx,ax			; BX = paras
	sub	dx,dx			; DX = owner (none)
	call	ma_row
	lea	si,[di].DDH_NAME
	call	put_name
	cmp	es:[di].DDH_NEXT_OFF,-1	; last built-in driver?
	les	di,es:[di]		; (flags unchanged)
	jne	mb3			; no
;
; DOS resides between the built-in drivers and the first memory block.
;
	les	bx,[dos_vars]
	mov	bp,es:[bx-2].DV_MCB_HEAD
	mov	ax,es
	mov	bx,bp
	sub	bx,ax			; BX = paras
	sub	dx,dx			; DX = owner (none)
	call	ma_row
	mov	dl,MA_DOS
	call	put_type
ma1:	mov	es,bp
	mov	al,es:[MCB_SIG]
	cmp	al,MCBSIG_NEXT		; valid MCB?
	je	ma2			; yes
	cmp	al,MCBSIG_LAST		; valid last MCB?
	jne	ma8			; no
ma2:	lea	ax,[bp+1]
	mov	dx,es:[MCB_OWNER]
	mov	bx,es:[MCB_PARAS]
	call	ma_row
	mov	si,MCB_NAME
	cmp	dx,MCBOWNER_SYSTEM	; owned by a process (or driver)?
	jbe	ma3			; no, so DL is the type
	cmp	byte ptr es:[si],0	; named?
	jne	ma5			; yes
	mov	dl,es:[MCB_TYPE]
ma3:	call	put_type
	jmp	short ma6
ma5:	call	put_name
ma6:	mov	es,bp
	cmp	byte ptr es:[MCB_SIG],MCBSIG_LAST
	je	ma9			; (carry clear)
	add	bp,es:[MCB_PARAS]
	inc	bp
	jmp	ma1
ma8:	stc
ma9:	ret
ENDPROC	dump_arena

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ma_row
;
; Inputs:
;	AX = segment
;	DX = owner
;	BX = size (in paragraphs)
;
; Modifies:
;	AX
;
DEFPROC	ma_row
	call	hex_word
	call	space
	mov	ax,dx
	call	hex_word
	call	space
	mov	ax,bx
	call	hex_word
	jmp	space
ENDPROC	ma_row

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_type, put_name
;
; Display the name of block type DL (put_type), or the 8-character name at
; ES:SI (put_name), followed by a newline; put_type displays nothing but the
; newline for an unknown type.
;
; Modifies:
;	AL, CX, SI
;
DEFPROC	put_type
	push	es
	push	cs
	pop	es
	mov	si,offset MA_TYPES
pt1:	lodsb
	cmp	al,dl			; matching type?
	je	pt2			; yes
	add	si,4
	cmp	si,offset MA_END
	jb	pt1
	jmp	short pt3		; no name or type
pt2:	mov	al,'<'
	call	put_char
	mov	cx,4
	call	put_n
	mov	al,'>'
	call	put_char
pt3:	pop	es
	jmp	newline
ENDPROC	put_type

DEFPROC	put_name
	mov	cx,8
	call	put_n
	jmp	newline
ENDPROC	put_name

	DEFLBL	MA_HDR,byte
	db	"Seg  Own  Size Name",13,10,0
;
; Memory block types (as owner or MCB_TYPE), each followed by a 4-character
; name (zero-padded).  MA_DOS is a pseudo-type for the DOS row, since no
; owner or MCB_TYPE is 1.
;
MA_DOS	equ	1
	DEFLBL	MA_TYPES,byte
	db	MCBOWNER_NONE,"FREE",MCBOWNER_SYSTEM,"SYS",0
	db	MA_DOS,"DOS",0
	db	MCBTYPE_ABLK,"ARR",0,MCBTYPE_CBLK,"CODE"
	db	MCBTYPE_FBLK,"FUNC",MCBTYPE_SBLK,"STR",0
	db	MCBTYPE_TBLK,"TEXT",MCBTYPE_VBLK,"VAR",0
	DEFLBL	MA_END,byte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_n
;
; Inputs:
;	ES:SI -> characters to display, up to CX (or a null)
;
; Modifies:
;	AL, CX, SI
;
DEFPROC	put_n
pn1:	lods	byte ptr es:[si]
	test	al,al
	jz	pn9
	call	put_char
	loop	pn1
pn9:	ret
ENDPROC	put_n

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_help
;
DEFPROC	cmd_help
	mov	si,offset HELP_MSG
	jmp	put_string		; (which returns carry clear)
ENDPROC	cmd_help

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; arm
;
; Write an INT 3 at every breakpoint except any at CS:IP.
;
; Outputs:
;	Carry set if a breakpoint is at CS:IP
;
; Modifies:
;	AX, BX, DX, DI, ES
;
DEFPROC	arm
	mov	bx,offset bp_tab
	mov	dl,0
ar1:	test	byte ptr [bx+5],BP_SET
	jz	ar3
	les	di,dword ptr [bx]
	call	at_ip
	jne	ar2
	mov	dl,1
	jmp	short ar3
ar2:	mov	al,0CCh
	xchg	al,es:[di]
	mov	[bx+4],al
	or	byte ptr [bx+5],BP_ARMED
ar3:	add	bx,BP_SIZE
	cmp	bx,offset bp_end
	jb	ar1
	shr	dl,1
	ret
ENDPROC	arm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; disarm
;
; Restore the original bytes at all the breakpoints, in reverse order (in
; case two share an address); if INT 3 stopped at one, back up IP to it.
;
; Modifies:
;	AX, BX, DI, ES
;
DEFPROC	disarm
	mov	bx,offset bp_end
da1:	sub	bx,BP_SIZE
	test	byte ptr [bx+5],BP_ARMED
	jz	da2
	and	byte ptr [bx+5],0FFh XOR BP_ARMED
	les	di,dword ptr [bx]
	mov	al,[bx+4]
	mov	es:[di],al
	cmp	[why],3			; INT 3?
	jne	da2			; no
	inc	di
	call	at_ip			; did it stop here?
	jne	da2			; no
	dec	regs[R_IP]
	mov	[why],0			; (only once)
da2:	cmp	bx,offset bp_tab
	ja	da1
	ret
ENDPROC	disarm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; at_ip
;
; Inputs:
;	ES:DI = address
;
; Outputs:
;	ZF set if ES:DI is CS:IP
;
; Modifies:
;	AX
;
DEFPROC	at_ip
	cmp	di,regs[R_IP]
	jne	ai9
	mov	ax,es
	cmp	ax,regs[R_CS]
ai9:	ret
ENDPROC	at_ip

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Monitor helpers.
;
; poll_rx
;
; Read a byte from the UART, if one has arrived; a BREAK is returned as
; Ctrl-C, and if XON/XOFF is enabled, XON and XOFF update paused instead.
;
; Outputs:
;	ZF clear if a byte was returned in AL
;
; Modifies:
;	AX, DX
;
DEFPROC	poll_rx
	mov	dx,[com_port]
	add	dx,REG_LSR
	in	al,dx
	test	al,LSR_BI		; BREAK?
	jnz	pr8			; yes
	and	al,LSR_DR		; data ready?
	jz	pr9			; no
	sub	dx,REG_LSR - REG_RBR
	in	al,dx			; AL = data
	test	[com_flow],COMDBG_XON
	jz	pr7
	mov	ah,0
	cmp	al,CHR_CTRLQ		; XON?
	je	pr1			; yes
	inc	ah
	cmp	al,CHR_CTRLS		; XOFF?
	jne	pr7			; no
pr1:	mov	[paused],ah
	cmp	al,al			; set ZF (nothing returned)
	ret
pr8:	mov	al,CHR_CTRLC
pr7:	test	al,al			; (NUL is ignored)
pr9:	ret
ENDPROC	poll_rx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; space, put_char
;
; Transmit a space (or AL), honoring XON/XOFF and RTS/CTS flow control;
; while waiting, received bytes are buffered for get_char (eg, so that
; pasted commands aren't lost during long dumps).  Nothing is transmitted
; while mute is set, but col is always updated.
;
; Inputs:
;	AL = byte to send (put_char)
;
; Modifies:
;	AL (space only)
;
DEFPROC	space
	mov	al,' '
ENDPROC	space				; fall into put_char

DEFPROC	put_char
	inc	[col]
	cmp	[mute],0
	jne	pc9
	DEFLBL	put_raw			; (com_main changes this)
	push	dx
	push	ax
pc1:	call	poll_rx
	jz	pc2
	push	bx
	mov	bl,[in_tail]
	mov	bh,0
	mov	in_buf[bx],al
	inc	bx
	and	bl,IN_MASK
	cmp	bl,[in_head]		; buffer full?
	je	pc1a			; yes (discard the byte)
	mov	[in_tail],bl
pc1a:	pop	bx
pc2:	cmp	[paused],0
	jne	pc1
	mov	dx,[com_port]
	test	[com_flow],COMDBG_RTS
	jz	pc3
	add	dx,REG_MSR
	in	al,dx
	sub	dx,REG_MSR
	test	al,MSR_CTS
	jz	pc1
pc3:	add	dx,REG_LSR
	in	al,dx
	test	al,LSR_THRE
	jz	pc1
	sub	dx,REG_LSR - REG_THR
	pop	ax
	out	dx,al
	pop	dx
pc9:	ret
ENDPROC	put_char

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pad
;
; Transmit at least one space, and more until col reaches AH.
;
; Modifies:
;	AL
;
DEFPROC	pad
pd1:	call	space
	cmp	[col],ah
	jb	pd1
	ret
ENDPROC	pad

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_char
;
; Outputs:
;	AL = next byte (buffered or received)
;
; Modifies:
;	AX, DX
;
DEFPROC	get_char
	push	bx
	mov	bl,[in_head]
	cmp	bl,[in_tail]		; anything buffered?
	jne	gc2			; yes
gc1:	call	poll_rx
	jz	gc1
	jmp	short gc9
gc2:	mov	bh,0
	mov	al,in_buf[bx]
	inc	bx
	and	bl,IN_MASK
	mov	[in_head],bl
gc9:	pop	bx
	ret
ENDPROC	get_char

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_string
;
; Inputs:
;	SI -> null-terminated string
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AL, SI
;
DEFPROC	put_string
ps1:	lodsb
	test	al,al
	jz	ps9
	call	put_char
	jmp	ps1
ps9:	ret
ENDPROC	put_string

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; newline
;
; Modifies:
;	AL
;
DEFPROC	newline
	mov	al,CHR_RETURN
	call	put_char
	mov	al,CHR_LINEFEED
	call	put_char
	mov	[col],0
	ret
ENDPROC	newline

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hex_addr, hex_word, hex_byte, hex_digit
;
; Inputs:
;	AX:DI (hex_addr), AX (hex_word), AL (hex_byte), or AL = 0-15
;
; Modifies:
;	AX
;
DEFPROC	hex_addr
	call	hex_word
	mov	al,':'
	call	put_char
	mov	ax,di
	call	hex_word
	jmp	space
ENDPROC	hex_addr

DEFPROC	hex_word
	push	ax
	mov	al,ah
	call	hex_byte
	pop	ax
ENDPROC	hex_word			; fall into hex_byte

DEFPROC	hex_byte
	push	ax
	push	cx
	mov	cl,4
	shr	al,cl
	pop	cx
	call	hex_digit
	pop	ax
	and	al,0Fh
ENDPROC	hex_byte			; fall into hex_digit

DEFPROC	hex_digit
	add	al,90h			; convert AL to '0'-'9' or 'A'-'F'
	daa
	adc	al,40h
	daa
	jmp	put_char
ENDPROC	hex_digit

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
; put_reg, put_2ch
;
; Inputs:
;	AL = register (as in REGNAMES), or AX = 2 characters (put_2ch)
;
; Modifies:
;	AX, BX (put_reg only)
;
DEFPROC	put_reg
	cbw
	xchg	bx,ax
	shl	bx,1
	mov	ax,word ptr REGNAMES[bx]
ENDPROC	put_reg				; fall into put_2ch

DEFPROC	put_2ch
	call	put_char
	mov	al,ah
	jmp	put_char
ENDPROC	put_2ch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; show_regs
;
; Display the saved registers and flags, in the same format as DEBUG,
; followed by the instruction at CS:IP.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	show_regs
	mov	si,offset REG_TABLE
sr1:	cmp	si,offset SEG_TABLE	; start of the second line?
	jne	sr2			; no
	call	newline
sr2:	lodsw
	call	put_2ch
	mov	al,'='
	call	put_char
	lodsb
	cbw
	xchg	bx,ax
	mov	ax,regs[bx]
	call	hex_word
	call	space
	cmp	si,offset FLAG_NAMES
	jb	sr1
	call	show_flags
	call	newline
	les	di,dword ptr regs[R_IP]
	jmp	dis_line
ENDPROC	show_regs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; show_flags
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	show_flags
	mov	si,offset FLAG_NAMES
	mov	dx,regs[R_FL]
	mov	cl,4
	shl	dx,cl			; DX = flags, with OF in bit 15
	mov	bx,FLAG_MASK SHL 4	; BX = flags to display, likewise
sf1:	shl	bx,1			; display the next flag?
	jnc	sf3			; no
	lodsw
	xchg	cx,ax			; CX = name if clear
	lodsw				; AX = name if set
	test	dh,80h			; is the flag set?
	jnz	sf2			; yes
	xchg	cx,ax
sf2:	call	put_2ch
	call	space
sf3:	shl	dx,1
	test	bx,bx
	jnz	sf1
	ret
ENDPROC	show_flags

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_line
;
; Read and echo a command (in upper case, except inside quotes); Ctrl-C
; cancels the line.
;
; Outputs:
;	command contains a null-terminated line
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	get_line
	sub	bx,bx
	mov	cl,bl			; CL = 1 inside quotes
gl1:	call	get_char
	cmp	al,CHR_RETURN
	je	gl9
	cmp	al,CHR_BACKSPACE
	je	gl3
	cmp	al,CHR_DEL
	je	gl3
	cmp	al,CHR_CTRLC
	je	gl4
	cmp	al,' '			; ignore any other control characters
	jb	gl1
	cmp	bx,CMD_MAX
	jae	gl1
	call	put_char
	call	quote
	test	cl,cl			; inside quotes?
	jnz	gl2			; yes
	cmp	al,'a'
	jb	gl2
	cmp	al,'z'
	ja	gl2
	sub	al,'a'-'A'
gl2:	mov	command[bx],al
	inc	bx
	jmp	gl1
gl3:	test	bx,bx
	jz	gl1
	dec	bx
	mov	al,command[bx]
	call	quote
	mov	al,CHR_BACKSPACE
	call	put_char
	call	space
	mov	al,CHR_BACKSPACE
	call	put_char
	jmp	gl1
gl4:	sub	bx,bx
gl9:	mov	command[bx],0
	jmp	newline
ENDPROC	get_line

DEFPROC	quote				; toggle CL if AL is a quote
	cmp	al,'"'
	je	qt1
	cmp	al,"'"
	jne	qt9
qt1:	xor	cl,1
qt9:	ret
ENDPROC	quote

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; skip_space
;
; Inputs:
;	SI -> command text (which never contains tabs; see get_line)
;
; Outputs:
;	SI -> first non-space
;
DEFPROC	skip_space
ss1:	cmp	byte ptr [si],' '
	jne	ss9
	inc	si
	jmp	ss1
ss9:	ret
ENDPROC	skip_space

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; end_command
;
; Inputs:
;	SI -> command text
;
; Outputs:
;	Carry clear if only spaces remain, set otherwise (SI -> non-space)
;
DEFPROC	end_command
	call	skip_space
	cmp	byte ptr [si],1		; CF set if null
	cmc
	ret
ENDPROC	end_command

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_reg
;
; Inputs:
;	AX = register name (2 characters)
;
; Outputs:
;	If carry clear, BX = offset of the register in regs
;
DEFPROC	find_reg
	mov	bx,offset REG_TABLE
fr1:	cmp	ax,[bx]
	je	fr2
	add	bx,3
	cmp	bx,offset FLAG_NAMES
	jb	fr1
	stc
	ret
fr2:	mov	bl,[bx+2]		; (carry is clear)
	mov	bh,0
	ret
ENDPROC	find_reg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_hex
;
; Inputs:
;	SI -> command text
;
; Outputs:
;	If carry clear, AX = value, and SI -> next character
;	If carry set, no digits or too many
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	parse_hex
	call	skip_space
	sub	ax,ax
	mov	cx,si			; CX -> first digit
ph1:	mov	dl,[si]
	sub	dl,'0'
	cmp	dl,10
	jb	ph2
	sub	dl,'A'-'0'-10
	cmp	dl,10
	jb	ph3
	cmp	dl,16
	jae	ph3
ph2:	test	ah,0F0h			; room for another digit?
	jnz	ph8			; no
	shl	ax,1
	shl	ax,1
	shl	ax,1
	shl	ax,1
	or	al,dl
	inc	si
	jmp	ph1
ph3:	cmp	cx,si			; CF set if any digits
	cmc
	ret
ph8:	stc
	ret
ENDPROC	parse_hex

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_addr
;
; Parse [segment:]offset, where segment may also be a register name.
;
; Inputs:
;	SI -> command text
;	BP = default segment
;
; Outputs:
;	If carry clear, BP:AX = address, and SI -> next character
;
; Modifies:
;	AX, BX, CX, DX, SI, BP
;
DEFPROC	parse_addr
	call	skip_space
	cmp	byte ptr [si+2],':'
	jne	pa1
	mov	ax,[si]
	call	find_reg
	jc	pa1
	mov	bp,regs[bx]
	add	si,3
	jmp	parse_hex
pa1:	call	parse_hex
	jc	pa9
	cmp	byte ptr [si],':'
	jne	pa8
	xchg	bp,ax			; BP = segment
	inc	si
	jmp	parse_hex
pa8:	clc
pa9:	ret
ENDPROC	parse_addr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_range
;
; Parse [address [end | L count]] and the end of the command.
;
; Inputs:
;	SI -> command text
;	BP:DI = default address
;	BX = default count
;
; Outputs:
;	If carry clear, BP:DI = address, and BX = count
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
DEFPROC	parse_range
	call	end_command
	jnc	prg9
	push	bx
	call	parse_addr
	pop	bx
	jc	prg9
	xchg	di,ax			; DI = offset
	call	skip_space
	cmp	byte ptr [si],'L'
	jne	prg2
	inc	si
	call	parse_hex
	jc	prg9
	test	ax,ax
	jz	prg8
	jmp	short prg3
prg2:	cmp	byte ptr [si],0
	je	prg9
	call	parse_hex		; AX = end offset
	jc	prg9
	sub	ax,di
	jb	prg9
	inc	ax
	jz	prg8
prg3:	xchg	bx,ax			; BX = count
	jmp	end_command
prg8:	stc
prg9:	ret
ENDPROC	parse_range

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dump_memory
;
; Parse D[B|W] [range] and dump memory as bytes or words (128 bytes by
; default, continuing from the last D, in the last format).  Rows are 16
; bytes, with ASCII at the right; byte rows are aligned on 16 bytes, with a
; dash after the 8th byte, and word rows are aligned on 16 bytes or 16 bytes
; plus 1, so that each word is whole.
;
; Inputs:
;	SI -> command text after D
;
; Outputs:
;	Carry clear if successful, set if invalid (dump state unchanged)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, ES
;
DEFPROC	dump_memory
	mov	ah,1
	lodsb
	cmp	al,'B'			; DB?
	je	dm0			; yes
	inc	ah
	cmp	al,'W'			; DW?
	je	dm0			; yes
	cmp	al,'M'			; DM?
	jne	dm0a			; no
	jmp	dump_arena
dm0a:	dec	si
	mov	ah,[dump_size]		; no, so use the last format
dm0:	push	ax
	mov	bp,[dump_seg]
	mov	di,[dump_off]
	mov	bx,128
	call	parse_range
	pop	ax
	jnc	dm1
	ret
dm1:	mov	[dump_size],ah
	mov	[dump_seg],bp
	mov	es,bp
	mov	cx,bx			; CX = bytes remaining
	mov	al,10h
	sub	al,ah
	cbw				; AX = 0Fh (bytes) or 0Eh (words)
	and	ax,di
	mov	si,di
	sub	si,ax			; SI = start of the first row
;
; For each row, DL and DH are the first and last+1 columns to display.
;
dm6:	mov	ax,es
	call	hex_word
	mov	al,':'
	call	put_char
	mov	ax,si
	call	hex_word
	call	space
	mov	ax,di
	sub	ax,si
	mov	dl,al
	mov	ax,16
	sub	al,dl
	cmp	ax,cx
	jbe	dm6a
	mov	ax,cx
	cmp	[dump_size],1		; bytes?
	je	dm6a			; yes
	inc	ax			; no, so include any odd byte's word
	and	al,0FEh
dm6a:	add	al,dl
	mov	dh,al
	sub	bx,bx
dm6b:	cmp	bl,dl
	jb	dm6c
	cmp	bl,dh
	jae	dm6c
	mov	ax,es:[si+bx]
	cmp	[dump_size],1		; bytes?
	je	dm6x			; yes
	call	hex_word
	jmp	short dm6d
dm6x:	call	hex_byte
	jmp	short dm6d
dm6c:	call	space
	call	space
	cmp	[dump_size],1		; bytes?
	je	dm6d			; yes
	call	space
	call	space
dm6d:	mov	al,' '
	cmp	bl,7			; (never true for words)
	jne	dm6e
	mov	al,'-'
dm6e:	call	put_char
	add	bl,[dump_size]
	cmp	bl,16
	jb	dm6b
	call	space
	sub	bx,bx
dm7:	mov	al,' '
	cmp	bl,dl
	jb	dm7b
	cmp	bl,dh
	jae	dm7b
	mov	al,es:[si+bx]
	cmp	al,' '
	jb	dm7a
	cmp	al,7Fh
	jb	dm7b
dm7a:	mov	al,'.'
dm7b:	call	put_char
	inc	bx
	cmp	bl,16
	jb	dm7
	call	newline
	mov	al,dh
	sub	al,dl
	cbw				; AX = bytes displayed
	add	di,ax			; (the offset wraps within the segment)
	add	si,16
	sub	cx,ax			; (a word may overshoot the count)
	jbe	dm7c
	jmp	dm6
dm7c:	mov	[dump_off],di
	clc
	ret
ENDPROC	dump_memory

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dis_line
;
; Display the address, bytes, and disassembly of an instruction.  The first
; decode is muted, to find the instruction's length.
;
; Inputs:
;	ES:DI -> instruction
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
	mov	al,[col]
	push	ax
	push	di
	inc	[mute]
	call	decode
	dec	[mute]
	pop	si			; SI -> instruction
	pop	ax
	mov	[col],al
	mov	cx,di
	sub	cx,si			; CX = length
	mov	di,si
	mov	ax,es
	call	hex_addr
dl1:	lods	byte ptr es:[si]
	call	hex_byte
	loop	dl1
	mov	ah,24
	call	pad
	call	decode
	pop	dx
	pop	bx
	jmp	newline
ENDPROC	dis_line

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; decode
;
; Display an 8086 instruction (prefixes, mnemonic, and operands).  A segment
; override is displayed with the memory operand (or after the instruction,
; if there isn't one).
;
; Inputs:
;	ES:DI -> instruction
;
; Outputs:
;	DI -> next instruction
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	decode
	mov	[seg_ovr],0
dc1:	call	fetch
	mov	[opcode],al
	mov	[modrm],al		; (see op_s and op_z)
	mov	ah,al
	and	ah,1
	mov	[wbit],ah
	test	al,al
	jns	dc2
	mov	bl,al
	mov	bh,0
	shl	bx,1
	mov	dx,word ptr OPTAB[bx-100h]
	cmp	dh,0FFh			; prefix?
	jne	dc6			; no
	mov	al,dl
	call	put_mnem
	call	space
	jmp	dc1
;
; Opcodes 00h-7Fh are decoded from their bits.
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
dc4:	and	ah,3
	mov	dx,5000h+M_INC
	add	dl,ah
	cmp	al,60h			; INC, DEC, PUSH, or POP?
	jb	dc6			; yes
	mov	dx,M_BAD
	cmp	al,70h			; Jcc?
	jb	dc6			; no
	and	al,0Fh
	add	al,M_JO
	mov	dl,al
	mov	dh,0A0h
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
	call	put_mnem
	sub	dl,M_MOVS		; string instruction?
	cmp	dl,5
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
	push	ax
	mov	al,','
	call	put_char
	pop	ax
	call	put_opnd
dc10:	cmp	[seg_ovr],0		; unused segment override?
	je	dc11			; no
	call	space
	jmp	put_seg
dc11:	ret
ENDPROC	decode

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
; Display the segment override, if any, and clear it.
;
; Modifies:
;	AX, BX
;
DEFPROC	put_seg
	mov	al,0
	xchg	al,[seg_ovr]
	test	al,al
	jz	psg9
	call	put_reg
	mov	al,':'
	jmp	put_char
psg9:	ret
ENDPROC	put_seg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fetch, fetch_word
;
; Inputs:
;	ES:DI -> next instruction byte
;
; Outputs:
;	AL (or AX) = next instruction byte (or word); DI advanced
;
DEFPROC	fetch
	mov	al,es:[di]
	inc	di
	ret
ENDPROC	fetch

DEFPROC	fetch_word
	mov	ax,es:[di]
	inc	di
	inc	di
	ret
ENDPROC	fetch_word

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
	and	al,0F8h
	cmp	al,0D8h			; ESC?
	je	oe2			; yes
	mov	al,M_BYTE
	add	al,[wbit]
	call	put_mnem
	call	space
oe2:	call	put_seg
	mov	al,'['
	call	put_char
	mov	al,[modrm]
	and	al,0C7h
	cmp	al,06h			; direct address?
	je	oe_dir			; yes
	and	ax,7
	xchg	bx,ax
	mov	al,RMTAB[bx]
	push	ax
	and	al,0Fh
	call	put_reg			; base register
	pop	ax
	mov	cl,4
	shr	al,cl
	jz	oe3
	push	ax
	mov	al,'+'
	call	put_char
	pop	ax
	call	put_reg			; index register
oe3:	mov	al,[modrm]
	test	al,40h			; 8-bit displacement?
	jnz	oe4			; yes
	test	al,al			; 16-bit displacement?
	jns	oe_end			; no
	mov	al,'+'
	call	put_char
	jmp	short oe_dir
oe4:	call	fetch
	call	put_sbyte
	jmp	short oe_end

op_o:	call	put_seg
	mov	al,'['
	call	put_char
oe_dir:	call	fetch_word
	call	hex_word
oe_end:	mov	al,']'
	jmp	put_char

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

	DEFLBL	resident_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dbgdev_init
;
; Open the COM port exclusively, and then install the interrupt hooks; a
; failure closes the port and leaves no hooks.
;
; Inputs:
;	ES:BX -> DDPI (DDPI_BUFPTR -> COM descriptor)
;
; Outputs:
;	DDPI updated
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	dbgdev_init,far
	mov	di,bx			; ES:DI -> DDPI
	lds	dx,es:[di].DDPI_BUFPTR	; DS:DX -> COM descriptor
	mov	ax,DOS_HDL_OPENRW OR MODE_DENY_RW
	int	21h			; open the port for exclusive access
	jc	din9
	xchg	bx,ax			; BX = handle
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_COMDEBUG
	int	21h
	jc	din8
	push	cs
	pop	ds
	ASSUME	DS:CODE
	mov	al,dl
	and	al,COMDBG_XON OR COMDBG_RTS
	mov	[com_flow],al
	xor	dl,al
	mov	[com_port],dx
;
; Nothing else can fail, so install the hooks: INT 01h, INT 03h, and the
; port's hardware interrupt (chosen by port, as the COM driver does: IRQ4
; for 3xxh, IRQ3 for 2xxh), and then have the UART interrupt us when data
; (or a BREAK) arrives.
;
	call	hook_vecs
	mov	bx,INT_HW_COM1 * 4
	cmp	dh,03h			; port 3xxh?
	je	din1			; yes
	mov	bx,INT_HW_COM2 * 4
din1:	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:NOTHING
	cli
	mov	ax,offset dbgdev_com
	xchg	ax,[bx]
	mov	cs:[old_com].OFF,ax
	mov	ax,cs
	xchg	ax,[bx+2]
	mov	cs:[old_com].SEG,ax
	inc	dx			; DX -> REG_IER (DLAB is clear)
	mov	al,IER_RBR_AVAIL OR IER_DELTA
	out	dx,al
	sti
	push	cs
	pop	ds
	ASSUME	DS:CODE
	cld
	mov	si,offset BANNER
	call	put_string
	mov	es:[di].DDPI_END.OFF,offset resident_end
	mov	es:[di].DDPI_END.SEG,cs
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
din8:	mov	ah,DOS_HDL_CLOSE
	int	21h
din9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE + DDSTAT_ERROR + DDERR_GENFAIL
	ret
ENDPROC	dbgdev_init

	DEFLBL	BANNER,byte
	db	"BASIC-DOS Debugger "
	VERSION_STR
	db	13,10,"CTRL-C or BREAK to stop, ? for help",13,10,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hook_vecs, swap_vecs
;
; Exchange the INT 01h and INT 03h vectors with vec_save, which hook_vecs
; first points at our handlers (after saving the DOSVARS pointer for DM).
;
; Inputs:
;	DS = CS
;
; Modifies:
;	AX, BX, SI
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	hook_vecs
	mov	[vec_save+2],cs
	mov	[vec_save+6],cs
	push	es
	mov	ah,DOS_MSC_GETVARS
	int	21h			; ES:BX -> DOSVARS + 2
	mov	[dos_vars].OFF,bx
	mov	[dos_vars].SEG,es
	pop	es
ENDPROC	hook_vecs			; fall into swap_vecs

DEFPROC	swap_vecs
	push	es
	sub	ax,ax
	mov	es,ax
	mov	bx,offset vec_save
	mov	si,01h*4
	call	sv1
	mov	si,03h*4
	call	sv1
	pop	es
	ret
sv1:	call	sv2			; (swap 2 words)
sv2:	mov	ax,[bx]
	xchg	ax,es:[si]
	mov	[bx],ax
	inc	bx
	inc	bx
	inc	si
	inc	si
	ret
ENDPROC	swap_vecs

	DEFWORD	vec_save,<dbg_int1,0,dbg_int3,0>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; com_main
;
; Program entry (via the DDH and in_buf).  Rebase CS so that offset 0 is the
; start of the file, as it is for the driver, then patch put_char and get_char
; to use DOS console I/O, enable Q, hook INT 01h and INT 03h, and run the
; monitor on our own stack (just below the frame) rather than its small one
; (DOS calls run on the caller's stack).
;
; If the command tail names a program, copy the name to command (as a string)
; and load the program with DOS_PSP_EXEC1, which returns its initial SS:SP
; (with AX on top) and CS:IP in the EPB, and leaves its PSP current; the rest
; of the tail (from the space after the name) becomes the program's command
; tail, with its length stored in the name's last byte.  We then enter the
; monitor as if the program's first instruction had been interrupted.  When
; the program terminates (or Q terminates it), DOS returns here as well, to
; the instruction after the EXEC1 call (see PSP_EXIT), with our stack as it
; was and the other registers unknown, so com_runs tells the two apart.
;
; Without a program, we enter the monitor as if PSP:0100h had been
; interrupted.  G resumes there, which brings us back here, so we exit.
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	com_main,far
	mov	ax,cs
	add	ax,10h
	push	ax
	mov	ax,offset cm1
	push	ax
	ret				; (RETF, since this is a FAR proc)
cm1:	push	cs
	pop	ds
	ASSUME	DS:CODE
	cmp	[com_runs],0		; resumed by G?
	je	cm1a			; no
	jmp	cm9			; yes
cm1a:	inc	[com_runs]
	mov	byte ptr [put_raw],0E9h
	mov	word ptr [put_raw+1],offset dos_put - offset put_raw - 3
	mov	byte ptr [get_char],0E9h
	mov	word ptr [get_char+1],offset dos_get - offset get_char - 3
	mov	[CMD_Q],'Q'
	call	hook_vecs
	mov	ax,sp
	sub	ax,130h			; leave room for the frame, and rebase
	mov	word ptr [mon_sp+1],ax
	mov	si,CMD_TAIL+1		; ES:SI -> command tail (ES = PSP)
	mov	di,offset command
cm2:	mov	al,es:[si]
	inc	si
	cmp	al,' '			; skip leading spaces
	je	cm2
cm3:	cmp	al,' '			; space or CHR_RETURN ends the name
	jbe	cm4
	mov	[di],al
	inc	di
	mov	al,es:[si]
	inc	si
	jmp	cm3
cm4:	mov	byte ptr [di],0
	cmp	di,offset command	; was there a name?
	je	cm5			; no
	dec	si			; ES:SI -> the rest of the tail
	mov	cx,si
	mov	al,es:[CMD_TAIL]
	add	al,CMD_TAIL+1
	sub	al,cl			; AL = its length (tail length - name)
	dec	si
	mov	es:[si],al		; stored just before it
	mov	[epb_tail].OFF,si
	mov	[epb_tail].SEG,es
	mov	[epb_fcb1].OFF,-1	; let DOS build the FCBs from the tail
	push	ds
	pop	es
	mov	bx,offset epb		; ES:BX -> EPB
	mov	dx,offset command	; DS:DX -> program name
	mov	ch,0			; no programs follow
	mov	ax,DOS_PSP_EXEC1
	int	21h			; load it (termination returns here)
	push	cs
	pop	ds
	jc	cm7			; it couldn't be loaded
	cmp	[com_runs],1		; did we just load it?
	jne	cm8			; no, it terminated
	inc	[com_runs]
	mov	ah,DOS_PSP_GET
	int	21h			; BX = the program's PSP
	pushf
	pop	cx			; CX = flags (with interrupts enabled)
	cli
	mov	ss,[epb_sp].SEG
	mov	sp,[epb_sp].OFF
	pop	ax			; AX = the program's initial AX
	push	cx
	push	[epb_ip].SEG
	push	[epb_ip].OFF		; its CS:IP (as if interrupted there)
	mov	ds,bx
	mov	es,bx			; DS = ES = PSP, and the rest are zero
	sub	bx,bx
	mov	cx,bx
	mov	dx,bx
	mov	si,bx
	mov	di,bx
	mov	bp,bx
	jmp	dbg_brk
	ASSUME	DS:CODE
cm5:	push	es			; ES = PSP
	pop	ds
	ASSUME	DS:NOTHING
	pushf
	push	es
	mov	ax,100h
	push	ax
	sub	ax,ax			; (AX = 0 in the frame)
	cli
	jmp	dbg_brk
	ASSUME	DS:CODE
cm7:	push	ax
	mov	si,offset LOAD_MSG
	call	put_string
	pop	ax
	call	hex_word		; display the error code
	jmp	short cm9a
cm8:	cmp	[com_runs],2		; did the program terminate itself?
	jne	cm9b			; no, Q did
	mov	si,offset TERM_MSG
	call	put_string
cm9a:	call	newline
	jmp	short cm9b
;
; Exit (G without a program, or Q).  If a program is loaded, terminate it
; first, which brings us back to cm8, and then exit with its exit code.
;
cm9:	call	disarm
	cmp	[com_runs],2		; is a program loaded?
	jne	cm9b			; no
	inc	[com_runs]		; yes (and Q is terminating it)
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
cm9b:	call	swap_vecs
	mov	ah,DOS_PSP_RETCODE
	int	21h			; AL = the program's exit code (or 0)
	mov	ah,DOS_PSP_RETURN
	int	21h
ENDPROC	com_main

	DEFLBL	LOAD_MSG,byte
	db	"Unable to load program, error ",0
	DEFLBL	TERM_MSG,byte
	db	"Program terminated normally",0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; com_quit
;
; Program mode's Q command.
;
DEFPROC	com_quit
	call	end_command
	jnc	cm9
	ret
ENDPROC	com_quit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_put, dos_get
;
; Program versions of put_char (which preserves all registers) and get_char
; (which returns the next byte in AL and modifies AX and DX); get_char reads
; without checking for Ctrl-C, so that Ctrl-C cancels a line, as it does on
; the serial port.
;
DEFPROC	dos_put
	push	dx
	push	ax
	mov	dl,al
	mov	ah,DOS_TTY_WRITE
	int	21h
	pop	ax
	pop	dx
	ret
ENDPROC	dos_put

DEFPROC	dos_get
	mov	ah,DOS_TTY_IN
	int	21h
	ret
ENDPROC	dos_get

	DEFBYTE	com_runs,0		; 1 running, 2 program loaded, 3 Q
;
; The EPB for DOS_PSP_EXEC1 (we define DOSHEAP, not DOSPSP, so this is laid
; out by hand, and CMD_TAIL is PSP_CMDTAIL).
;
	DEFWORD	epb,0			; EPB_ENVSEG (0 = the parent's)
	DEFPTR	epb_tail		; EPB_CMDTAIL
	DEFPTR	epb_fcb1		; EPB_FCB1 (-1 to build from the tail)
	DEFPTR	epb_fcb2		; EPB_FCB2
	DEFPTR	epb_sp			; EPB_INIT_SP (returned)
	DEFPTR	epb_ip			; EPB_INIT_IP (returned)
;
; The COMDATA tells the loader that we need only a small heap (for the stack
; in program mode); without it, we'd get half of the available memory.  As a
; driver, everything past resident_end is discarded anyway.
;
	COMHEAP	2048

CODE	ends

	end
