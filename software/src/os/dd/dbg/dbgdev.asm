;
; BASIC-DOS Loadable Serial Debugger
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage (in CONFIG.SYS): DEVICE=EXT\DEBUG.COM COM2:9600,N,8,1,VT100 [/cmd...]
;
; Each switch is a monitor command, performed once the driver is installed
; (eg, /BP 70:100), and then booting continues, unless one of them is /H.
;
; DEBUG.COM can also be run as a program (DEBUG [program [arguments]]), with
; a monitor on the console.  It loads the program without starting it and
; displays the registers as of the program's start; G runs it, and Q (or the
; program's termination) exits.  Without a program, the registers are as of
; DEBUG's own start (PSP:0100h, where a RET makes G exit).  A switch performs
; one command and exits (eg, DEBUG /DB 40:0 or DEBUG /DM).  Any value may also
; be a 16-bit register name (eg, DB DS:DX).
;
; Ctrl-C or a serial BREAK stops the machine as soon as it arrives (via the
; port's hardware interrupt), as do breakpoints, single-steps (T and P), and
; any other INT 1 or INT 3.  Every exception is hooked (INT 00h and, in the
; driver, INT 04h, and in protected mode, the rest through CPU_SETFAULT), but
; one stops the machine only if VT traps its vector (VL lists them, and VC
; clears them); otherwise, it's passed on (eg, to DOS, which ends the
; program), as GT passes on a trapped one.  A fault that DOS declines (which
; would stop the machine; see CPU_SETFAULT) stops it here first, as if it
; were trapped, and GT then has CPU$ report it and offer us the halt, which
; we keep: we display the same "System halted" message and wait for CTRL-C
; (or BREAK).  G, P, and T then resume at CS:IP (eg, after a fix), and GT
; keeps it halted (displaying the same message and waiting again), so that we
; never give up control.  The monitor displays the registers and the
; current instruction, and then accepts commands (? lists them) until G, GT,
; P, or T.
;
; Memory is read and written through CPU$ (see CPU_RWMEM), which checks every
; address, and can store breakpoints in code segments (but not in the parts
; of CPU$ that we call, such as DDINT_CPU itself).  When CPU$ is the
; 80286 driver (see CPU_SYSREGS), we work in either mode: the prompt is #
; in protected mode (- in real mode), an address may start with & (real
; mode) or # (protected mode), and otherwise has the processor's current
; mode, every address is displayed with its prefix, and the registers include
; the MSW, GDTR, and IDTR, plus in protected mode, the LDTR, the TR, and each
; segment register's base and limit (see CPU_SEGINFO).
;
; The disassembler is in dbgdis.asm, which LINK puts after this module, and
; which is resident, too.  Only INIT calls DOS, and it's in dbginit.asm,
; which LINK puts after the resident code, along with program mode.  The
; monitor can interrupt DOS (or an IRQ handler), so it runs on a private
; stack with interrupts disabled, polling the UART of a COM port that INIT
; opened with MODE_DENY_RW.  For the same reason, it can't use the DOS
; utility functions (eg, SPRINTF), which enable interrupts and reenter the
; DOS dispatcher.
;
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	uart.inc
	include	cpu.inc

CODE	segment para public 'CODE'

	EXTNEAR	<com_main,com_quit,dbgdev_init>
	EXTNEAR	<chk_over,dis_line>
	public	gl1,mon3a,mon4,mon4a	; (patched by dbginit.asm)

;
; When run as a program, execution begins at the DDH, so DDH_NEXT_OFF holds a
; JMP SHORT to in_buf, which DOS accepts in place of FFFFh (see load_devices).
;
COM_JMP		equ	((size DDH - 2) SHL 8) OR 0EBh

DBGDEV	DDH	<COM_JMP,-1,DDATTR_CHAR,dbgdev_req,0,2020244755424544h>
;
; in_buf must follow the DDH: its initial contents (which don't matter to the
; driver) are a JMP to com_main, which (like everything that runs only as a
; program) is in dbginit.asm, after resident_end, so a driver doesn't keep it.
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
; to first; SP and SS are saved as they were before the interrupt, which for
; code interrupted at another ring (ie, a ring 3 program, while we're at ring
; 0) are in the interrupt frame (see chk_ring).
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
; state (BP_* flags, plus ADDR_SEL if the segment is a selector); entry 0 is
; the temporary breakpoint (for G addr, P, and BP 0), which is cleared when
; CS:IP reaches it.
;
BP_SET		equ	02h	; breakpoint is set
BP_ARMED	equ	04h	; breakpoint's INT 3 is in memory
BP_STEP		equ	08h	; temporary breakpoint ends a P step
CPU_DUAL	equ	80h	; cpu_mode: CPU$ is the 80286 driver
BP_SIZE		equ	6
NUM_BPS		equ	10
;
; trace_mode flags, for the T or P command in progress (see cmd_t).
;
TRACE_BRIEF	equ	01h	; display only the instruction (no R)
TRACE_OVER	equ	02h	; step over CALL, INT, LOOP, and REP (P)
;
; vec_save holds our INT 00h, 04h, 01h, and 03h handlers, which dbginit.asm's
; swap_vecs (or for INT 04h, which only the driver hooks, dbgdev_init)
; exchanges with the vectors, so once they're hooked, it holds the previous
; handlers (eg, DOS's INT 00h handler, for GT), and the offset of INT 00h's
; and INT 04h's is the vector (see dbg_int0 and cmd_gt).
;
	DEFWORD	vec_save,<dbg_int0,0,dbg_int4,0,dbg_int1,0,dbg_int3,0>
	DEFPTR	old_fault		; previous fault handler (DOS's)
	DEFPTR	fault_ret		; CPU$'s return address for a fault
	DEFBYTE	trap_vecs,0,4		; a bit for each vector that VT traps
	DEFPTR	old_com			; original COM interrupt handler
	DEFWORD	com_port,0		; UART base port
	DEFWORD	dos_seg,0		; DOS's segment (see hook_vecs)
	DEFWORD	dump_off,0		; offset of the next D command
	DEFWORD	dump_seg,0		; segment of the next D command
	DEFBYTE	dump_size,1		; 1 (DB) or 2 (DW), for the next D
	DEFWORD	u_off,0			; offset of the next U command
	DEFWORD	u_seg,0			; segment of the next U command
	DEFWORD	mem_seg,0		; segment of the memory to access
	DEFWORD	mem_val,0		; bytes read or written (see mem_io)
	DEFBYTE	mem_mode,0		; ADDR_SEL if mem_seg is a selector
	DEFBYTE	dump_mode,0		; ADDR_SEL if dump_seg is a selector
	DEFBYTE	u_mode,0		; ADDR_SEL if u_seg is a selector
	DEFBYTE	cpu_mode,0		; CPU_DUAL, plus ADDR_SEL if in PM
;
; sys_regs holds what CPU_SYSREGS returns: the GDTR and IDTR (6 bytes each),
; and then the MSW, LDTR, and TR.
;
	DEFWORD	sys_regs,0,9
	DEFWORD	trace_cnt,0		; T or P steps remaining
	DEFWORD	regs,0,REGS_LEN/2	; saved registers
	DEFPTR	frame_ptr		; end of the interrupt frame's FLAGS
	DEFBYTE	bp_tab,0,BP_SIZE*NUM_BPS
	DEFLBL	bp_end
	DEFBYTE	com_flow,0		; COMDBG_XON and/or COMDBG_RTS
	DEFBYTE	paused,0		; set by XOFF, cleared by XON
	DEFBYTE	in_head,0		; next byte to read from in_buf
	DEFBYTE	in_tail,0		; next byte to write in in_buf
	DEFBYTE	why,0			; 1, 3 (INT 1, INT 3), -1 (trapped
					; fault), -2 (declined fault; see
					; dbg_fatal), -3 (halted; see
					; FAULT_HALTED), -4 (INT 0 or INT 4),
					; or 0
	DEFBYTE	fault_vec,0		; the vector of a fault (or INT 0 or 4)
	DEFBYTE	brk_skip,0		; nonzero to resume past a DBGBRK
	DEFWORD	fault_ec,0		; and its error code
	DEFBYTE	tracing,0		; 1 for T or P, 2 for G past a BP
	DEFBYTE	trace_mode,0		; TRACE_* flags (0 after other stops)
	DEFBYTE	col,0			; output column (see pad)
	DEFBYTE	mute,0			; nonzero to discard output
	DEFBYTE	ln_find,0		; 1 while put_name looks, 2 to name
	DEFLONG	ln_addr,0		; the address that put_name looks for
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
	db	"DM",9,9,"dump memory blocks",13,10
	db	"DS sel",9,9,"dump selector",13,10
	db	"E addr [list]",9,"edit memory",13,10
	db	"G [addr]",9,"go (to address)",13,10
	db	"GT",9,9,"go, passing on the trap",13,10
	db	"LN [addr]",9,"list nearest block",13,10
	db	"P[R] [count]",9,"step over (R: registers)",13,10
	db	"R [reg | F]",9,"display or edit registers",13,10
	db	"T[R] [count]",9,"trace (R: registers)",13,10
	db	"U [range]",9,"unassemble",13,10
	db	"VC n|*",9,9,"clear vector trap(s)",13,10
	db	"VL",9,9,"list vector traps",13,10
	db	"VT n",9,9,"trap vector (n. = decimal)",13,10,0

	DEFLBL	ASSERT_MSG,byte
	db	"Assertion failure",0
	DEFLBL	DIV_MSG,byte
	db	"Division error",0
	DEFLBL	OVF_MSG,byte
	db	"Overflow error",0
	DEFLBL	FAULT_MSG,byte
	db	"CPU fault ",0," (EC=",0,") at ",0	; (consecutive strings)
	db	"System halted",0
;
; The names of the registers that show_regs displays in protected mode after
; SS, in order (A20 is always enabled then), and the flags' letters there.
;
	DEFLBL	SYS_NAMES,byte
	db	"A20=ON ",0,"LD=",0
	DEFLBL	SYS_GD,byte
	db	" GD=",0," ID=",0,"TR=",0
	DEFLBL	SYS_MS,byte
	db	" MS=",0," PS=",0
	DEFLBL	PM_FLAGS,byte
	db	"VDITSZAPC"
PM_FLAG_MASK	equ	0FD5h	; OF, DF, IF, TF, SF, ZF, AF, PF, and CF

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
	db	'L'
	dw	cmd_l
	db	'P'
	dw	cmd_p
	db	'R'
	dw	cmd_r
	db	'T'
	dw	cmd_t
	db	'U'
	dw	cmd_u
	db	'V'
	dw	cmd_v
	db	'?'
	dw	cmd_help
	DEFLBL	CMD_Q,byte
	db	0			; program mode changes this to 'Q'
	dw	com_quit
	db	0

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
; Besides INIT, OPEN and CLOSE (which do nothing) and WRITE are supported, so
; that DOS can send DPRINTF output to the debugger's port (see sysinit).
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;	DDP_STATUS updated
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	dbgdev_req,far
	mov	al,es:[bx].DDP_CMD
	cmp	al,DDC_INIT
	jne	drq1
	jmp	near ptr dbgdev_init
drq1:	mov	dx,DDSTAT_DONE
	cmp	al,DDC_OPEN
	je	drq9
	cmp	al,DDC_CLOSE
	je	drq9
	cmp	al,DDC_WRITE
	jne	drq8
	mov	cx,es:[bx].DDPRW_LENGTH
	jcxz	drq9
	lds	si,es:[bx].DDPRW_ADDR	; DS:SI -> data
drq2:	lodsb
	push	ds
	mov	ds,cs:[0].DDH_DATA
	call	put_char
	pop	ds
	loop	drq2
	mov	es:[bx].DDPRW_LENGTH,cx	; zero bytes remaining
	jmp	short drq9
drq8:	mov	dx,DDSTAT_ERROR + DDERR_UNKCMD
drq9:	mov	es:[bx].DDP_STATUS,dx
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
	mov	ds,cs:[0].DDH_DATA
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
; dbgdev_enter (dbg_int0, dbg_int1, dbg_int3, dbg_fault, and dbg_brk)
;
; Save the interrupted registers on the interrupted stack, copy them to regs,
; and run the monitor on our own stack, with DS, ES, and SS all addressing
; our data (DDH_DATA, which in protected mode is a data alias of CS).
;
; Inputs:
;	Interrupt frame on SS:SP (with interrupts disabled), which for
;	dbg_fault (see CPU_SETFAULT) follows a return address, the vector,
;	and the error code (and for dbg_fatal, just the vector and error code)
;
; An exception (dbg_fault, dbg_int0, or dbg_int4) whose vector VT doesn't
; trap (see chk_trap) goes to the previous handler instead, as it was, except
; that a fault's return address is replaced with dbg_fatal.
;
DEFPROC	dbgdev_enter,far
	DEFLBL	dbg_int0,near
	push	ax
	mov	al,0
	jmp	short di1
	DEFLBL	dbg_int4,near
	push	ax
	mov	al,4
di1:	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	cbw				; AX = vector
	call	chk_trap		; is it trapped?
	mov	[fault_vec],al
	pop	ds
	ASSUME	DS:NOTHING
	jc	di3			; yes
	test	al,al			; INT 00h?
	pop	ax
	jnz	di2			; no
	jmp	dword ptr cs:[vec_save]	; pass it on
di2:	jmp	dword ptr cs:[vec_save+4]
di3:	mov	al,-4			; (INT 00h or INT 04h)
	jmp	short de1
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
	jmp	short de1
	DEFLBL	dbg_fault,near
	push	bp
	mov	bp,sp
	push	ax
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	ax,offset dbg_fatal
	xchg	ax,[bp+2]
	mov	[fault_ret].OFF,ax
	mov	ax,cs
	xchg	ax,[bp+4]
	mov	[fault_ret].SEG,ax	; (see cmd_gt)
	mov	ax,[bp+6]		; AX = vector
	call	chk_trap		; is it trapped?
	mov	al,-1			; (a trapped fault)
	jc	df1			; yes
	test	ah,FAULT_HALTED		; is CPU$ offering us its halt?
	mov	al,-3			; (a halt)
	jnz	df1			; yes, so we keep control
	pop	ds
	ASSUME	DS:NOTHING
	pop	ax
	pop	bp
	jmp	cs:[old_fault]		; no, so pass it on
;
; A fault that the previous handler declines returns here (which would stop
; the machine; see CPU_SETFAULT), so we stop for it, as if it were trapped.
;
	DEFLBL	dbg_fatal,near
	sub	sp,4			; (where the return address was)
	push	bp
	mov	bp,sp
	push	ax
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	al,-2			; (a declined fault)
df1:	mov	ah,[bp+6]
	mov	[fault_vec],ah
	push	word ptr [bp+8]
	pop	[fault_ec]
	pop	ds
	ASSUME	DS:NOTHING
	pop	word ptr [bp+8]		; (the interrupted AX, for de1)
	pop	bp
	add	sp,6			; discard the return address and vector
de1:	push	bx
	push	cx
	push	dx
	push	bp
	push	si
	push	di
	push	ds
	push	es
	push	ss
	mov	bp,sp
	xchg	dx,ax			; DL = why
	lea	ax,[bp+REGS_LEN-2]	; AX = SP before the interrupt
	push	ax
	mov	si,sp
	push	ss
	pop	ds
	mov	es,cs:[0].DDH_DATA
	mov	di,offset regs
	mov	cx,REGS_LEN/2
	cld
	rep	movsw
	push	es
	pop	ds
	ASSUME	DS:CODE
	mov	[why],dl
	mov	[frame_ptr].OFF,ax
	mov	[frame_ptr].SEG,ss
	push	es
	pop	ss
	DEFLBL	mon_sp,near		; (com_main changes this stack)
	mov	sp,offset mon_stack_end
	jmp	monitor
ENDPROC	dbgdev_enter

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; monitor
;
; Get the processor's mode (and system registers, if CPU$ is the 80286
; driver), remove breakpoints, finish any G past a breakpoint (or T or P with
; a count), and process commands.
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	monitor
	push	ds
	pop	es
	mov	di,offset sys_regs	; ES:DI -> GDTR and IDTR buffer
	mov	ah,CPU_SYSREGS
	call	far ptr DDINT_CPU	; AX = MSW, CX = LDTR, DX = TR
	mov	bl,0
	jc	mon0			; it's not the 80286 driver
	mov	sys_regs[12],ax
	mov	sys_regs[14],cx
	mov	sys_regs[16],dx
	and	al,ADDR_SEL		; (the MSW's PE bit)
	or	al,CPU_DUAL
	mov	bl,al
mon0:	mov	[cpu_mode],bl
	call	chk_ring		; interrupted at another ring?
	jz	mon0d			; no
	les	bx,[frame_ptr]
	les	ax,es:[bx]
	mov	regs[R_SP],ax
	mov	regs[R_SS],es		; yes, so get its SS:SP from the frame
mon0d:	call	disarm
	mov	dl,0			; DL = nonzero if a T or P step is done
	mov	al,0
	xchg	al,[tracing]
;
; A step's TF can be saved (eg, by a PUSHF, or on an 8086, by a hardware
; interrupt, which takes priority over the step's trap) and restored later,
; so TF is always cleared, and a single-step trap with TF set when we weren't
; tracing resumes, as G past a breakpoint does.
;
	mov	ah,byte ptr regs[R_FL+1]
	and	byte ptr regs[R_FL+1],0FEh
	cmp	[why],1			; a single-step trap?
	jne	mon1			; no
	test	al,al			; were we tracing?
	jnz	mon0a			; yes
	test	ah,01h			; was TF set?
	jz	mon1			; no (it was an INT 1)
	mov	al,2			; yes, so resume
mon0a:	dec	al			; was it T or P?
	jnz	mon0b			; no
	inc	dx			; yes, so the step is done
	jmp	short mon1
mon0b:	call	arm			; no, G past a breakpoint
	jc	mon0c			; but we're at another one
	jmp	resume
mon0c:	call	disarm			; (DL is zero, since arm zeroes it)
;
; Reaching the temporary breakpoint, however we got there, clears it, and if
; P set it, the P step is done.
;
mon1:	mov	bx,offset bp_tab
	call	bp_mem
	call	at_ip			; is it at CS:IP?
	jne	mon1a			; no
	mov	al,0
	xchg	al,[bx+5]		; yes, so clear it
	and	al,BP_STEP
	or	dl,al
mon1a:	test	dl,dl			; is a T or P step done?
	jz	mon2			; no
	jmp	mon3			; yes
mon2:	sub	ax,ax
	mov	[trace_cnt],ax		; no more steps
	mov	[trace_mode],al		; (and show_step shows the registers)
	mov	al,[in_tail]		; discard any buffered input
	mov	[in_head],al
	mov	[paused],0
;
; A fault (see dbg_fault) gets the same message that CPU$ displays, including
; "System halted" for a halt.
;
	mov	al,[why]
	cmp	al,-3			; a fault (trapped, declined, or halt)?
	jb	mon2a			; no
	mov	si,offset FAULT_MSG
	call	put_string
	mov	al,[fault_vec]
	call	hex_byte
	call	put_string		; (SI -> the next string)
	mov	ax,[fault_ec]
	call	hex_word
	call	put_string
	mov	ax,regs[R_CS]
	call	hex_word
	mov	al,':'
	call	put_char
	mov	ax,regs[R_IP]
	call	hex_word
	call	newline
	cmp	[why],-3		; a halt?
	jne	mon3			; no
	call	put_string		; "System halted"
	call	newline
;
; A halt then waits, as a halted machine would, until CTRL-C (or BREAK) brings
; back the monitor (polling the port, since interrupts are still disabled).
;
mon2h:	call	poll_rx
	jz	mon2h
	cmp	al,CHR_CTRLC		; CTRL-C (or BREAK)?
	jne	mon2h			; no
	jmp	short mon3
;
; A trapped INT 00h or INT 04h gets the same message that DOS displays.
;
mon2a:	mov	si,offset DIV_MSG
	cmp	al,-4			; INT 00h or INT 04h?
	jne	mon2d			; no
	cmp	[fault_vec],0		; INT 00h (a divide error)?
	je	mon2c			; yes
	mov	si,offset OVF_MSG
	jmp	short mon2c
;
; An INT 3 that isn't a breakpoint (disarm clears why for those) and follows
; a NOP is an ASSERT, so say so; any other is a DBGBRK, which a driver loaded
; without /H resumes past, as G would (see dbgdev_init).
;
mon2d:	cmp	al,3			; INT 3 other than a breakpoint?
	jne	mon3			; no
	call	ip_mem			; DI -> byte after the INT 3
	dec	di
	dec	di
	call	peek_b
	cmp	al,90h			; NOP (OP_NOP in 8086.inc)?
	je	mon2b			; yes, so it's an ASSERT
	cmp	[brk_skip],0		; should a DBGBRK stop us?
	je	mon3			; yes
	jmp	cg1			; no, so resume
mon2b:	mov	si,offset ASSERT_MSG
mon2c:	call	put_string
	call	newline
mon3:	mov	ax,regs[R_IP]
	mov	[u_off],ax		; U defaults to CS:IP
	mov	ax,regs[R_CS]
	mov	[u_seg],ax
	mov	ax,regs[R_DS]
	mov	[dump_seg],ax		; D defaults to DS
	mov	al,[cpu_mode]
	and	al,ADDR_SEL
	mov	[u_mode],al		; in the current mode
	mov	[dump_mode],al
mon3a:	call	show_step		; (com_main changes this, and mon4)
	cmp	[trace_cnt],0		; more T or P steps?
	je	mon4			; no
	call	do_trace		; (which never returns)

mon4:	call	put_prompt
	call	get_line
mon4a:	mov	si,offset command
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
; restore them all and IRET; to resume another ring, they go below its SS:SP
; in the interrupt frame instead, since the IRET pops those, too.
;
DEFPROC	resume
	les	di,dword ptr regs[R_SP]
	call	chk_ring		; resuming another ring?
	jz	rs1			; no
	call	put_sssp		; yes, ES:BX -> its SS:SP in the frame
	mov	di,bx
rs1:	sub	di,REGS_LEN
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
; chk_ring
;
; In protected mode, an interrupt from code at another ring than ours (ie, a
; ring 3 program, while we're a driver at ring 0) switched stacks, and pushed
; the interrupted SS:SP before the FLAGS, CS, and IP (see frame_ptr), and an
; IRET to that ring pops them again.
;
; Outputs:
;	ZF clear if regs are from another ring
;
; Modifies:
;	AX
;
DEFPROC	chk_ring
	test	[cpu_mode],ADDR_SEL	; protected mode?
	jz	ck9			; no
	mov	ax,cs
	xor	al,byte ptr regs[R_CS]
	test	al,3			; is it our ring?
ck9:	ret
ENDPROC	chk_ring

;
; put_sssp
;
; Stores regs' SS:SP in the interrupt frame (see chk_ring).
;
; Outputs:
;	ES:BX -> SS:SP in the frame
;
; Modifies:
;	AX, BX, ES
;
DEFPROC	put_sssp
	les	bx,[frame_ptr]
	mov	ax,regs[R_SP]
	mov	es:[bx],ax
	mov	ax,regs[R_SS]
	mov	es:[bx+2],ax
	ret
ENDPROC	put_sssp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Commands (DS = CS and interrupts disabled; DF clear for strings).
;
; cmd_b
;
; BP[n] addr sets breakpoint n (1-9, or 0 for the temporary one), or the
; first free one (1-9); BC clears the listed breakpoints (or * for all); BL
; lists them.
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
	mov	bx,offset bp_tab+5
	mov	cx,NUM_BPS
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
	mov	bx,offset bp_tab
	mov	dl,'0'
bl1:	test	byte ptr [bx+5],BP_SET
	jz	bl2
	mov	al,dl
	call	put_char
	call	space
	call	bp_mem
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
	call	parse_addr
	jc	sb9
	test	[mem_mode],ADDR_PHYS	; (a breakpoint needs a segment)
	stc
	jnz	sb9
	call	end_command
	jc	sb9
	mov	[bx],ax
	mov	[bx+2],bp
	mov	al,[mem_mode]
	or	al,BP_SET
	mov	[bx+5],al
sb9:	ret
ENDPROC	set_bp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_slot
;
; Inputs:
;	AL = breakpoint number ('0'-'9')
;
; Outputs:
;	If carry clear, BX -> BP_TAB entry
;
; Modifies:
;	AX, BX
;
DEFPROC	get_slot
	sub	al,'0'
	cmp	al,NUM_BPS		; '0'-'9'?
	cmc
	jc	gs9			; no
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
	mov	[mem_seg],bp		; mem_seg:DI -> memory
	call	end_command
	jnc	ce1
	jmp	short store_list
ce1:	call	peek_b
	jc	ce9
	push	ax
	call	hex_addr
	pop	ax
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
;	mem_seg:DI -> memory
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
	call	poke_b
	jc	sl9
	jmp	sl1
sl2:	mov	ah,al			; AH = quote
sl3:	lodsb
	test	al,al			; missing the closing quote?
	jz	sl8			; yes
	cmp	al,ah
	je	sl1
	push	ax
	call	poke_b
	pop	ax
	jc	sl9
	jmp	sl3
sl8:	stc
sl9:	ret
ENDPROC	store_list

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_g
;
; G [addr] removes any breakpoint at CS:IP, steps past it, and then sets all
; the breakpoints (including the temporary one, which addr replaces) and
; resumes.  GT instead passes the trapped exception that stopped us (see VT)
; on to its previous handler (eg, DOS's, which ends the program), as if it
; hadn't been trapped, since resuming would only run the instruction again
; (eg, an 80286 or later reports a DIV's address, not the next one); for a
; fault, the handler returns to dbg_fatal if it declines it.  GT after a
; declined fault returns it to CPU$, which reports it and offers us the halt,
; after which GT just keeps it halted (see mon2h), so that we never give up
; control.
;
DEFPROC	cmd_g
	lodsb
	cmp	al,'T'			; GT?
	je	cmd_gt			; yes
	dec	si
	call	end_command
	jnc	cg1
	mov	bx,offset bp_tab
	call	set_bp
	jc	cg9
cg1:	call	arm
	mov	al,2
	jnc	cg8
	DEFLBL	step,near
	mov	[tracing],al
	or	byte ptr regs[R_FL+1],01h	; set TF
cg8:	jmp	resume
cg9:	ret
cmd_gt:	call	end_command
	jc	cg9
	mov	al,[why]
	cmp	al,-4			; INT 00h or INT 04h?
	je	gt1			; yes
	cmp	al,-3			; a halt?
	jb	cg9			; not a fault (nothing to pass on)
	jne	gt0			; no
	jmp	mon_sp			; yes, so we stay halted
gt0:	call	arm			; (one at CS:IP isn't needed)
	mov	di,regs[R_IP]
	mov	cx,[old_fault].OFF
	mov	dx,[old_fault].SEG	; DX:CX = previous handler
	mov	si,offset dbg_fatal	; SI = its return address
	cmp	[why],-1		; a trapped fault?
	je	gt0a			; yes
	mov	cx,[fault_ret].OFF
	mov	dx,[fault_ret].SEG	; DX:CX = CPU$
	sub	si,si			; (which needs no return address)
gt0a:	call	sim_int			; ES:BX -> the frame it pushed
	sub	bx,4
	mov	al,[fault_vec]
	cbw
	mov	es:[bx],ax		; push the vector
	mov	ax,[fault_ec]
	mov	es:[bx+2],ax		; and the error code
	test	si,si			; and a return address?
	jz	gt0b			; no
	sub	bx,4
	mov	es:[bx],si
	mov	es:[bx+2],cs
gt0b:	mov	regs[R_SP],bx
	jmp	resume
gt1:	call	arm
	mov	bl,[fault_vec]
	mov	bh,0			; BX = vector (0 or 4)
	mov	di,regs[R_IP]
	mov	cx,vec_save[bx]
	mov	dx,vec_save[bx+2]	; DX:CX = previous handler
	call	sim_int
	jmp	resume
ENDPROC	cmd_g

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_v
;
; VT traps the listed vectors (00h-1Fh), so that their exceptions stop the
; machine instead of being passed on (see dbgdev_enter); VC clears the listed
; traps (or * for all); VL lists the trapped vectors.  A vector is hex, or
; decimal with a trailing period (eg, 0D or 13.).  Single-steps (01h) and
; breakpoints (03h) always stop the machine.
;
DEFPROC	cmd_v
	lodsb
	cmp	al,'L'
	je	cmd_vl
	xchg	dx,ax			; DL = 'T' or 'C'
	cmp	dl,'T'
	je	cv1
	cmp	dl,'C'
	stc
	jne	cv9
cv1:	call	skip_space
	lodsb
	test	al,al			; end of the list?
	jz	cv9			; yes (carry clear)
	cmp	al,'*'			; all of them?
	jne	cv2			; no
	cmp	dl,'C'			; (only VC accepts *)
	stc
	jne	cv9
	sub	ax,ax
	mov	word ptr [trap_vecs],ax
	mov	word ptr [trap_vecs+2],ax
	jmp	cv1
cv2:	dec	si
	push	dx
	call	parse_vec		; AX = vector
	pop	dx
	jc	cv9
	call	vec_bit			; BX = byte, AL = bit
	or	trap_vecs[bx],al
	cmp	dl,'T'			; VT?
	je	cv1			; yes
	xor	trap_vecs[bx],al	; no, so clear it
	jmp	cv1
cmd_vl:	call	end_command
	jc	cv9
	sub	ax,ax
cv3:	call	chk_trap		; is this vector trapped?
	jnc	cv3a			; no
	push	ax
	call	hex_byte
	call	space
	pop	ax
cv3a:	inc	ax
	cmp	al,32
	jb	cv3
	call	newline
	clc
cv9:	ret
ENDPROC	cmd_v

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_vec
;
; Parses a vector that VT can trap (00h-1Fh): hex, or decimal with a
; trailing period (eg, 13.), as FAULT.COM numbers them.
;
; Inputs:
;	SI -> command text
;
; Outputs:
;	If carry clear, AX = vector, and SI -> next character
;	If carry set, it's invalid
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	parse_vec
	call	parse_hex		; AX = value (as hex)
	jc	vp9
	cmp	byte ptr [si],'.'	; decimal?
	jne	vp8			; no
	inc	si
	cmp	ax,32h			; more than two digits, or 32 or more?
	jae	vp7			; yes
	mov	cl,4
	mov	ah,al
	shr	ah,cl			; AH = tens digit
	and	al,0Fh			; AL = ones digit
	cmp	al,10			; is it a decimal digit?
	jae	vp7			; no
	aad				; AX = AH * 10 + AL
vp8:	cmp	ax,32			; can it be trapped?
	cmc				; (carry set if not)
vp9:	ret
vp7:	stc
	ret
ENDPROC	parse_vec

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
	cmp	ax,32			; can VT trap it?
	jae	ctr9			; no (carry clear)
	push	ax
	push	bx
	push	cx
	call	vec_bit
	test	trap_vecs[bx],al	; (clears carry)
	jz	ctr8
	stc
ctr8:	pop	cx
	pop	bx
	pop	ax
ctr9:	ret
ENDPROC	chk_trap

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; vec_bit
;
; Inputs:
;	AX = vector (00h-1Fh)
;
; Outputs:
;	BX = offset of its byte in trap_vecs, AL = its bit
;
; Modifies:
;	AL, BX, CL
;
DEFPROC	vec_bit
	mov	bx,ax
	mov	cl,3
	shr	bx,cl
	mov	cl,al
	and	cl,7
	mov	al,1
	shl	al,cl
	ret
ENDPROC	vec_bit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_p, cmd_t
;
; T [count] executes count (default 1) instructions, displaying the next
; instruction after each (TR displays the registers, too).  Like DEBUG, it
; steps into an INT (other than one that we handle) by simulating it.  P (or
; PR) is the same, except that it steps over a CALL, INT, LOOP, or REP string
; instruction, by setting the temporary breakpoint after it (with BP_STEP)
; and resuming, as G does.
;
DEFPROC	cmd_p
	mov	bl,TRACE_BRIEF OR TRACE_OVER
	jmp	short ct0
	DEFLBL	cmd_t,near
	mov	bl,TRACE_BRIEF
ct0:	cmp	byte ptr [si],'R'	; TR or PR?
	jne	ct0a			; no
	inc	si
	dec	bx			; (clearing TRACE_BRIEF)
ct0a:	mov	ax,1
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
	mov	[trace_mode],bl
	DEFLBL	do_trace,near
	dec	[trace_cnt]
	call	ip_mem
	call	peek_w			; AX = first two bytes at CS:IP
	cmp	al,0CCh			; INT 3 (one byte)?
	je	ct1b			; yes, so skip it
	cmp	al,0CDh			; INT n?
	jne	ct2			; no
	mov	al,ah
	call	far ptr DDINT_GETVEC	; DX:CX = vector
	jc	ct2			; there's none (eg, in protected mode)
	mov	ax,cs
	cmp	dx,ax			; is it one of ours (eg, INT 3)?
	jne	ct1c			; no
;
; Tracing into one of our own handlers would only stop at its first
; instruction, so skip the INT instead, as if it had just returned.
;
	inc	di
ct1b:	inc	di
	mov	regs[R_IP],di
	jmp	short ct1d
ct1c:	test	[trace_mode],TRACE_OVER	; P?
	jnz	ct2a			; yes, so step over the INT
	inc	di
	inc	di			; DI = offset after the INT
	call	sim_int
ct1d:	pop	ax			; discard our return address
	mov	dl,1			; (the step is done)
	jmp	mon1
ct2:	test	[trace_mode],TRACE_OVER	; P?
	jz	ct3			; no
ct2a:	call	chk_over		; DI -> next instruction
	jnc	ct3			; but trace this one
	mov	word ptr bp_tab[0],di
	mov	ax,[mem_seg]
	mov	word ptr bp_tab[2],ax
	mov	al,[mem_mode]
	or	al,BP_SET OR BP_STEP
	mov	bp_tab[5],al		; (replacing any temporary breakpoint)
	jmp	cg1
ct3:	mov	al,1
	jmp	step
ct9:	ret
ENDPROC	cmd_p

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sim_int
;
; Simulate an interrupt into DX:CX, as the processor would, by pushing an
; interrupt frame (CS:DI and the flags) on the interrupted stack and clearing
; IF and TF; from another ring, the frame goes below its SS:SP in the
; original frame (see chk_ring), and the handler runs on that stack.
;
; Inputs:
;	DX:CX = handler, DI = return offset (in the interrupted CS)
;
; Modifies:
;	AX, BX, ES
;
DEFPROC	sim_int
	les	bx,dword ptr regs[R_SP]
	call	chk_ring		; from another ring?
	jz	si1			; no
	call	put_sssp		; yes, ES:BX -> its SS:SP in the frame
	mov	regs[R_SS],es
si1:	sub	bx,6
	mov	regs[R_SP],bx
	mov	es:[bx],di		; push the return address
	mov	ax,regs[R_CS]
	mov	es:[bx+2],ax
	mov	ax,regs[R_FL]		; and the flags
	mov	es:[bx+4],ax
	and	byte ptr regs[R_FL+1],0FCh	; and clear IF and TF
	mov	regs[R_IP],cx
	mov	regs[R_CS],dx
	ret
ENDPROC	sim_int

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
	call	put_prompt
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
	mov	al,[u_mode]
	mov	[mem_mode],al		; (unless there's an address)
	mov	bx,20h
	call	parse_range
	jc	cu9
	mov	[mem_seg],bp
	mov	dx,di
cu1:	call	dis_line
	mov	ax,di
	sub	ax,dx
	cmp	ax,bx
	jb	cu1
	mov	[u_off],di
	mov	ax,[mem_seg]
	mov	[u_seg],ax
	mov	al,[mem_mode]
	mov	[u_mode],al
cu9:	ret
ENDPROC	cmd_u

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmd_l
;
; LN [address] ("list near") displays an address (CS:IP by default), its
; linear address, and the name of the memory it's in, as DM would show it.
;
DEFPROC	cmd_l
	lodsb
	cmp	al,'N'
	jne	cl8
	call	ip_mem			; mem_seg:DI = CS:IP (the default)
	call	end_command
	jnc	cl1			; no address
	mov	bp,[mem_seg]
	call	parse_addr		; BP:AX = address
	jc	cl9
	mov	[mem_seg],bp
	xchg	di,ax
	call	end_command
	jc	cl9			; there's more
cl1:	mov	bx,[mem_seg]
	mov	al,[mem_mode]
	call	lin_addr		; DX:CX = linear address
	jc	cl9
	call	hex_addr		; (with its mode's prefix)
	mov	ax,cx
	call	hex_addr6
	call	put_name
	call	newline
	clc
	ret
cl8:	stc
cl9:	ret
ENDPROC	cmd_l

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dump_blocks
;
; DM displays memory in address order, as CPU$ describes it (see CPU_QUERY):
; each block's address, length, owner, and name (or type), after any memory
; below the first block (see ma_low), with each of the system's blocks shown
; as the drivers in it (see ma_drvs).
;
DEFPROC	dump_blocks
	call	end_command
	jnc	ma0
	ret
ma0:	mov	si,offset MA_HDR
	call	put_string
	DEFLBL	ma_walk,near		; (see put_name)
	sub	sp,size PMB
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> PMB buffer
	sub	bx,bx			; BX = PMB #
ma1:	mov	ah,CPU_QUERY
	call	far ptr DDINT_CPU
	jc	ma9			; no more blocks
	test	bx,bx			; the first block?
	jnz	ma2			; no
	call	ma_low
ma2:	call	ma_sys			; a block of the system's?
	jnc	ma6			; yes (and it's displayed)
	mov	ax,es:[di].PMB_ADDR.LOW
	mov	dl,byte ptr es:[di].PMB_ADDR.HIW
	call	hex_addr6
	mov	ax,es:[di].PMB_LEN.LOW
	mov	dl,byte ptr es:[di].PMB_LEN.HIW
	call	hex_addr6
	mov	ax,es:[di].PMB_OWNER
	lea	si,[di].PMB_NAME
	cmp	byte ptr es:[si],0	; named?
	jne	ma5			; yes
	mov	dl,es:[di].PMB_TYPE
	cmp	dl,PMBTYPE_USED		; allocated?
	jne	ma3			; no (eg, free)
	mov	dl,al			; DL = owner (eg, the system)
	cmp	ax,MCBOWNER_SYSTEM	; owned by a process (or driver)?
	jbe	ma3			; no
	mov	dl,es:[di].PMB_MCBTYPE	; yes, so DL is its type, if any
	test	dl,dl
	jnz	ma3
	dec	dx			; (no type, so MA_DATA)
ma3:	call	ma_type
	jmp	short ma6
ma5:	call	ma_name
ma6:	inc	bx
	jmp	ma1
ma9:	add	sp,size PMB
	clc
	ret
ENDPROC	dump_blocks

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ma_low, ma_sys
;
; The 8086 CPU$'s blocks start after its own code (and the first block's MCB),
; so if the first block doesn't start at zero, ma_low displays the memory below
; it (up to that MCB) as the system's.  ma_sys displays a block if it's the
; system's (and has no name), and otherwise returns carry set (after checking
; the block for put_name; see ln_span).
;
; Inputs:
;	ES:DI -> PMB
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	ma_low
	mov	cx,es:[di].PMB_ADDR.LOW
	jcxz	ml9			; the first block starts at zero
	sub	cx,size MCB
	sub	ax,ax
	cwd				; DX:AX = zero
	mov	si,dx			; SI:CX = end
	jmp	short ma_drvs
ml9:	ret
ENDPROC	ma_low

DEFPROC	ma_sys
	mov	ax,es:[di].PMB_ADDR.LOW
	mov	dx,es:[di].PMB_ADDR.HIW	; DX:AX = address
	mov	cx,es:[di].PMB_LEN.LOW
	mov	si,es:[di].PMB_LEN.HIW
	add	cx,ax
	adc	si,dx			; SI:CX = end
	cmp	es:[di].PMB_TYPE,PMBTYPE_USED
	jne	ms8
	cmp	es:[di].PMB_OWNER,MCBOWNER_SYSTEM
	jne	ms8
	cmp	byte ptr es:[di].PMB_NAME,0
	je	ma_drvs
ms8:	call	ln_span
	stc
	ret
ENDPROC	ma_sys

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ma_drvs
;
; Displays memory of the system's as a row for each driver in it, from the
; driver chain (which devinit keeps in memory order), with any other memory
; as SYS (or DOS, for the memory DOS is in).  A driver ends where the next
; one begins (or at the end of the memory); the chain's links are segments in
; real mode and selectors in protected mode, so we read them through CPU$
; (see mem_io and lin_addr).
;
; Inputs:
;	DX:AX = address, SI:CX = end
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	ma_drvs
	LOCVAR	mrCur,dword
	LOCVAR	mrEnd,dword
	LOCVAR	mrNext,dword
	ENTER
	push	bx
	push	di
	mov	[mrCur].LOW,ax
	mov	[mrCur].HIW,dx
	mov	[mrEnd].LOW,cx
	mov	[mrEnd].HIW,si
	mov	al,[cpu_mode]
	and	al,ADDR_SEL
	mov	[mem_mode],al		; links are selectors in protected mode
	mov	[mem_seg],BIOS
	mov	di,offset DD_LIST	; mem_seg:DI -> head of the chain
md1:	call	fetch_word
	xchg	cx,ax			; CX = offset of the next driver
	call	fetch_word		; AX = its segment (or selector)
	cmp	cx,-1			; end of the chain?
	jne	md2			; no
md8:	mov	cx,[mrEnd].LOW
	mov	dx,[mrEnd].HIW
	call	md_sys			; display any memory that's left
	pop	di
	pop	bx
	clc
	LEAVE
	ret
md2:	mov	[mem_seg],ax
	mov	di,cx			; mem_seg:DI -> driver
	call	md_addr			; DX:CX = its address
	jc	md8
	mov	ax,cx
	sub	ax,[mrCur].LOW
	mov	ax,dx
	sbb	ax,[mrCur].HIW
	jb	md1			; it's before the rest of the memory
	mov	ax,cx
	sub	ax,[mrEnd].LOW
	mov	ax,dx
	sbb	ax,[mrEnd].HIW
	jnb	md1			; it's after the memory
	call	md_sys			; display any memory before it
	push	di
	call	fetch_word
	xchg	cx,ax			; CX = offset of the next driver
	call	fetch_word		; AX = its segment (or selector)
	mov	di,cx
	inc	cx			; end of the chain?
	jz	md5			; yes
	push	[mem_seg]
	mov	[mem_seg],ax
	call	md_addr			; DX:CX = next driver's address
	pop	[mem_seg]
	jc	md5
	mov	ax,[mrEnd].LOW
	sub	ax,cx
	mov	ax,[mrEnd].HIW
	sbb	ax,dx
	jb	md5			; it's after the memory
	mov	ax,[mrCur].LOW
	sub	ax,cx
	mov	ax,[mrCur].HIW
	sbb	ax,dx
	jb	md6			; it's after this driver
md5:	mov	cx,[mrEnd].LOW
	mov	dx,[mrEnd].HIW
md6:	pop	di
	call	md_span			; AX = owner
	call	hex_word
	call	space
	add	di,DDH_NAME		; mem_seg:DI -> driver's name
	mov	cx,size DDH_NAME
	call	ln_on
md7:	call	peek_b
	call	put_char
	inc	di
	loop	md7
	call	ln_off
	call	newline
	sub	di,DDH_NAME + size DDH_NAME
	jmp	md1
ENDPROC	ma_drvs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; md_addr, md_sys, md_span
;
; For ma_drvs (whose frame they use): md_addr returns the address of the
; driver at mem_seg:DI in DX:CX (carry set if it's not valid); md_sys displays
; the memory from mrCur to DX:CX, if any, as SYS (or DOS, if DOS's segment is
; in it); md_span displays the address and length of the memory from mrCur to
; DX:CX, advances mrCur to DX:CX, and returns the owner (the system) in AX
; (after checking the memory for put_name; see ln_span).
;
; Modifies:
;	AX, BX (md_addr and md_sys), CX, DX, SI (md_sys and md_span)
;
DEFPROC	md_addr
	mov	bx,[mem_seg]
	mov	al,[mem_mode]
	jmp	lin_addr
ENDPROC	md_addr

DEFPROC	md_sys
	cmp	cx,[mrCur].LOW
	jne	ds1
	cmp	dx,[mrCur].HIW
	je	ds9
ds1:	mov	[mrNext].LOW,cx
	mov	[mrNext].HIW,dx
	push	di
	mov	bx,[dos_seg]
	sub	di,di
	mov	al,[cpu_mode]
	call	lin_addr		; DX:CX = DOS's address
	pop	di
	mov	bl,MCBOWNER_SYSTEM	; BL = SYS
	jc	ds2
	mov	ax,cx
	sub	ax,[mrCur].LOW
	mov	ax,dx
	sbb	ax,[mrCur].HIW
	jb	ds2			; DOS is before this memory
	sub	cx,[mrNext].LOW
	sbb	dx,[mrNext].HIW
	jnb	ds2			; or after it
	mov	bl,MA_DOS
ds2:	mov	cx,[mrNext].LOW
	mov	dx,[mrNext].HIW
	call	md_span
	mov	dl,bl
	jmp	ma_type
ds9:	ret
ENDPROC	md_sys

DEFPROC	md_span
	mov	ax,[mrCur].LOW
	push	dx
	mov	si,dx
	mov	dx,[mrCur].HIW		; DX:AX = address, SI:CX = end
	call	ln_span
	call	hex_addr6		; the address
	pop	dx
	mov	ax,cx
	sub	ax,[mrCur].LOW
	push	dx
	sbb	dx,[mrCur].HIW
	call	hex_addr6		; and the length
	pop	dx
	mov	[mrCur].LOW,cx
	mov	[mrCur].HIW,dx
	mov	ax,MCBOWNER_SYSTEM
	ret
ENDPROC	md_span

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hex_addr6
;
; Displays DL:AX as 6 hex digits (an address or length), and a space.
;
; Modifies:
;	AX
;
DEFPROC	hex_addr6
	push	ax
	mov	al,dl
	call	hex_byte
	pop	ax
	call	hex_word
	jmp	space
ENDPROC	hex_addr6

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ma_type, put_type, ma_name
;
; ma_type displays the owner in AX and then the name of block type DL; put_type
; displays the name of block type DL; ma_name displays the owner in AX and then
; the 8-character name at ES:SI.  Each is followed by a newline, and put_type
; displays nothing but the newline for an unknown type.
;
; Modifies:
;	AL, CX, SI
;
DEFPROC	ma_type
	call	hex_word
	call	space
ENDPROC	ma_type				; fall into put_type

DEFPROC	put_type
	call	ln_on
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
	call	ln_off
	jmp	newline
ENDPROC	put_type

DEFPROC	ma_name
	call	hex_word
	call	space
	call	ln_on
	mov	cx,8
	call	put_n
	call	ln_off
	jmp	newline
ENDPROC	ma_name

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_name
;
; Displays the name of the memory at linear address DX:CX, as DM would show
; it (or nothing, if no block has it), by walking the blocks as DM does, with
; the output muted except for that name (see ln_span, ln_on, and ln_off).
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	put_name
	push	bx
	push	si
	push	di
	push	bp
	push	es
	push	[mem_seg]
	mov	al,[mem_mode]
	push	ax
	mov	[ln_addr].LOW,cx
	mov	[ln_addr].HIW,dx
	mov	[ln_find],1
	inc	[mute]
	call	ma_walk
	dec	[mute]
	mov	[ln_find],0
	pop	ax
	mov	[mem_mode],al
	pop	[mem_seg]
	pop	es
	pop	bp
	pop	di
	pop	si
	pop	bx
	ret
ENDPROC	put_name

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ln_span, ln_on, ln_off
;
; While put_name looks for ln_addr, ln_span marks the memory from DX:AX up to
; SI:CX as the memory to name, if it contains that address; then ln_on unmutes
; the output for that memory's name, and ln_off mutes it again.
;
; Modifies:
;	Nothing
;
DEFPROC	ln_span
	cmp	[ln_find],1		; looking?
	jne	lsp9			; no
	push	bx
	mov	bx,[ln_addr].LOW
	sub	bx,ax
	mov	bx,[ln_addr].HIW
	sbb	bx,dx			; is the address below the start?
	jb	lsp8			; yes
	mov	bx,[ln_addr].LOW
	sub	bx,cx
	mov	bx,[ln_addr].HIW
	sbb	bx,si			; is it below the end?
	jnb	lsp8			; no
	inc	[ln_find]		; yes, so name this memory
lsp8:	pop	bx
lsp9:	ret
ENDPROC	ln_span

DEFPROC	ln_on
	cmp	[ln_find],2		; naming this memory?
	jne	lo9			; no
	dec	[mute]
lo9:	ret
ENDPROC	ln_on

DEFPROC	ln_off
	cmp	[ln_find],2		; was this memory named?
	jne	lf9			; no
	inc	[mute]
	dec	[ln_find]		; (and we're done)
lf9:	ret
ENDPROC	ln_off

	DEFLBL	MA_HDR,byte
	db	"Addr   Length Own  Name",13,10,0
;
; Memory block types (as owner, PMB_TYPE, or PMB_MCBTYPE), each followed by a
; 4-character name (zero-padded).  MA_DATA and MA_DOS are pseudo-types, for
; a program's memory with no type and for the memory DOS is in (see md_sys).
;
MA_DATA	equ	MCBTYPE_NONE-1
MA_DOS	equ	MCBTYPE_NONE-2

	DEFLBL	MA_TYPES,byte
	db	MCBOWNER_NONE,"FREE",MCBOWNER_SYSTEM,"SYS",0
	db	PMBTYPE_SYS,"CPU$",PMBTYPE_RSVD,"RSVD"
	db	MCBTYPE_ABLK,"ARR",0,MCBTYPE_CBLK,"CODE"
	db	MCBTYPE_EBLK,"ENV",0,MA_DATA,"DATA",MA_DOS,"DOS",0
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
;	Carry set if a breakpoint is at CS:IP (and DL zero, either way)
;
; Modifies:
;	AX, BX, DX, DI
;
DEFPROC	arm
	mov	bx,offset bp_tab
	mov	dl,0
ar1:	test	byte ptr [bx+5],BP_SET
	jz	ar3
	call	bp_mem
	call	at_ip
	jne	ar2
	mov	dl,1
	jmp	short ar3
ar2:	call	peek_b			; AL = original byte
	jc	ar3			; (the address isn't valid)
	mov	[bx+4],al
	mov	al,0CCh
	call	poke_b
	jc	ar3
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
;	AX, BX, DI
;
DEFPROC	disarm
	mov	bx,offset bp_end
da1:	sub	bx,BP_SIZE
	test	byte ptr [bx+5],BP_ARMED
	jz	da2
	and	byte ptr [bx+5],0FFh XOR BP_ARMED
	call	bp_mem
	mov	al,[bx+4]
	call	poke_b			; (which advances DI)
	cmp	[why],3			; INT 3?
	jne	da2			; no
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
; Compares physical addresses, so that a breakpoint matches CS:IP even if
; it was set in the other mode (eg, &F000:E05B and #F000:E05B).
;
; Inputs:
;	mem_seg:DI = address (in mem_mode)
;
; Outputs:
;	ZF set if it's CS:IP (in the current mode)
;
; Modifies:
;	AX
;
DEFPROC	at_ip
	push	bx
	push	cx
	push	dx
	push	si
	mov	al,[mem_mode]
	mov	bx,[mem_seg]
	call	lin_addr		; DX:CX = address of mem_seg:DI
	jc	ai8
	mov	si,cx
	push	dx
	push	di
	mov	di,regs[R_IP]
	mov	bx,regs[R_CS]
	mov	al,[cpu_mode]
	call	lin_addr		; DX:CX = address of CS:IP
	pop	di
	pop	bx			; BX:SI = address of mem_seg:DI
	jc	ai8
	cmp	cx,si
	jne	ai9
	cmp	dx,bx
	jmp	short ai9
ai8:	test	sp,sp			; (ZF clear, since SP isn't zero)
ai9:	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	at_ip

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; lin_addr
;
; Inputs:
;	AL = mode (ADDR_SEL, plus any other bits), BX:DI = address
;
; Outputs:
;	Carry clear if valid: DX:CX = physical address (see CPU_SEGINFO)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	lin_addr
	and	al,ADDR_SEL OR ADDR_PHYS
	mov	ah,CPU_SEGINFO
	call	far ptr DDINT_CPU	; DX:CX = base address
	jc	la9
	add	cx,di
	adc	dx,0			; (carry is clear)
la9:	ret
ENDPROC	lin_addr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ip_mem, bp_mem
;
; Make CS:IP (in the current mode), or the breakpoint at BX, the memory to
; access (mem_seg and mem_mode), with its offset in DI.
;
; Modifies:
;	AX, DI
;
DEFPROC	ip_mem
	mov	di,regs[R_IP]
	mov	ax,regs[R_CS]
	mov	[mem_seg],ax
	mov	al,[cpu_mode]
	jmp	short bm1
ENDPROC	ip_mem

DEFPROC	bp_mem
	mov	di,[bx]
	mov	ax,[bx+2]
	mov	[mem_seg],ax
	mov	al,[bx+5]
bm1:	and	al,ADDR_SEL
	mov	[mem_mode],al
	ret
ENDPROC	bp_mem

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
;	mem_seg:DI (hex_addr, which displays its mode's prefix if CPU$ is the
;	80286 driver), AX (hex_word), AL (hex_byte), or AL = 0-15
;
; Modifies:
;	AX
;
DEFPROC	hex_addr
	test	[mem_mode],ADDR_PHYS	; a physical address?
	jz	ha0			; no
	mov	al,'%'
	call	put_char
	mov	ax,[mem_seg]
	call	hex_byte		; (bits 16-23)
	jmp	short ha2
ha0:	test	[cpu_mode],CPU_DUAL	; does the mode matter?
	jz	ha1			; no
	mov	al,'&'
	test	[mem_mode],ADDR_SEL	; protected mode?
	jz	ha0a			; no
	mov	al,'#'
ha0a:	call	put_char
ha1:	mov	ax,[mem_seg]
	call	hex_word
	mov	al,':'
	call	put_char
ha2:	mov	ax,di
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
; show_step
;
; After a T or P step (without R), display only the instruction at CS:IP;
; otherwise, display the registers, too.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	show_step
	test	[trace_mode],TRACE_BRIEF
	jnz	sr9
ENDPROC	show_step			; fall into show_regs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; show_regs
;
; Display the saved registers and flags, followed by the instruction at CS:IP.
; In real mode, they're in the same format as DEBUG, with a line for the MSW,
; GDTR, and IDTR if CPU$ is the 80286 driver; in protected mode, they're in
; the PCjs Debugger's format, with each segment register's [base,limit], the
; system registers, and the flags as 0 or 1 (and no IP, which the instruction
; shows).
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	show_regs
	mov	si,offset REG_TABLE
	test	[cpu_mode],ADDR_SEL	; protected mode?
	jnz	srp			; yes
sr1:	cmp	si,offset SEG_TABLE	; start of the second line?
	jne	sr2			; no
	call	newline
sr2:	call	put_regval
	cmp	si,offset FLAG_NAMES
	jb	sr1
	call	show_flags
	call	newline
	test	[cpu_mode],CPU_DUAL	; is CPU$ the 80286 driver?
	jz	sr9			; no
	mov	si,offset SYS_MS+1
	call	put_string		; "MS="
	mov	ax,sys_regs[12]
	call	hex_word
	mov	si,offset SYS_GD
	call	put_string		; " GD="
	mov	bx,offset sys_regs
	call	put_dtr
	call	put_string		; " ID="
	mov	bx,offset sys_regs+6
	call	put_dtr
sr8:	call	newline
sr9:	call	ip_mem
	jmp	dis_line

srp:	call	put_regval		; AX through DI
	cmp	si,offset SEG_TABLE
	jb	srp
	call	newline
sp2:	call	put_regval		; DS, ES, and SS
	cmp	si,offset SEG_TABLE+9	; CS's entry?
	jb	sp2
	push	si
	mov	si,offset SYS_NAMES
	call	put_string		; "A20=ON "
	call	newline
	pop	ax
	push	si			; (SI -> "LD=")
	xchg	si,ax			; SI -> CS's entry
	call	put_regval		; CS
	pop	si
	call	put_string		; "LD="
	mov	ax,sys_regs[14]
	push	ax
	call	hex_word
	pop	ax
	call	put_desc
	call	put_string		; " GD="
	mov	bx,offset sys_regs
	call	put_dtr
	call	put_string		; " ID="
	mov	bx,offset sys_regs+6
	call	put_dtr
	call	space
	call	newline
	call	put_string		; "TR="
	mov	ax,sys_regs[16]
	call	hex_word
	call	put_string		; " MS="
	mov	ax,sys_regs[12]
	call	hex_word
	call	put_string		; " PS="
	mov	ax,regs[R_FL]
	mov	dx,ax
	call	hex_word
	call	space
	mov	cl,4
	shl	dx,cl			; DX = flags, with OF in bit 15
	mov	bx,PM_FLAG_MASK SHL 4	; BX = flags to display, likewise
spf1:	shl	bx,1			; display the next flag?
	jnc	spf3			; no
	lodsb
	call	put_char		; its letter
	mov	al,'0'
	test	dh,80h			; is it set?
	jz	spf2			; no
	inc	ax
spf2:	call	put_char		; and 0 or 1
	test	bx,bx			; any more?
	jz	spf9			; no
	call	space
spf3:	shl	dx,1
	jmp	spf1
spf9:	jmp	sr8
ENDPROC	show_regs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_regval
;
; Display the register whose name (2 characters) and offset in regs are at
; SI as NAME=VALUE, followed in protected mode by a segment register's
; [base,limit], and then a space.
;
; Modifies:
;	AX, BX, CX, DX, SI (advanced to the next register)
;
DEFPROC	put_regval
	lodsw
	call	put_2ch
	mov	al,'='
	call	put_char
	lodsb
	cbw
	xchg	bx,ax
	mov	ax,regs[bx]
	call	hex_word
	cmp	si,offset SEG_TABLE	; a segment register (or IP)?
	jbe	pv9			; no
	test	[cpu_mode],ADDR_SEL	; protected mode (with no IP)?
	jz	pv9			; no
	mov	ax,regs[bx]		; (hex_word changed AX)
	call	put_desc
pv9:	jmp	space
ENDPROC	put_regval

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_dtr, put_desc
;
; Display [base,limit] for the GDTR or IDTR at BX, or for the selector in AX
; (see CPU_SEGINFO; nothing is displayed if it isn't valid).
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	put_dtr
	mov	ax,[bx]			; AX = limit
	mov	cx,[bx+2]
	mov	dl,[bx+4]		; DL:CX = base
	jmp	short put_bl
ENDPROC	put_dtr

DEFPROC	put_desc
	xchg	bx,ax
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_SEL
	call	far ptr DDINT_CPU	; DX:CX = base, AX = limit
	jc	pd9
	DEFLBL	put_bl,near
	push	ax
	mov	al,'['
	call	put_char
	mov	al,dl
	call	hex_byte
	mov	ax,cx
	call	hex_word
	mov	al,','
	call	put_char
	pop	ax
	call	hex_word
	mov	al,']'
	jmp	put_char
pd9:	ret
ENDPROC	put_desc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_prompt
;
; Display the prompt (-), in either mode, since addresses show their mode.
;
; Modifies:
;	AL
;
DEFPROC	put_prompt
	mov	al,'-'
	jmp	put_char
ENDPROC	put_prompt

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
	sub	cx,cx			; CL = 1 inside quotes, CH = 1 to skip
gl1:	call	get_char		; (dbgdev_init changes this)
;
; A non-ASCII key (eg, a cursor key) is a null followed by its scan code,
; which must be skipped, too.
;
	shr	ch,1			; skipping a scan code?
	jc	gl1			; yes
	test	al,al			; non-ASCII key?
	jnz	gl1a			; no
	inc	ch			; yes, so skip its scan code next
	jmp	gl1
gl1a:	cmp	al,CHR_RETURN
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
; reg_val
;
; Inputs:
;	AL = 16-bit register (as in REGNAMES)
;
; Outputs:
;	AX = its saved value
;
; Modifies:
;	AX, BX
;
DEFPROC	reg_val
	cbw
	xchg	bx,ax
	shl	bx,1
	mov	ax,word ptr REGNAMES[bx]
	call	find_reg		; BX = its offset in regs
	mov	ax,regs[bx]
	ret
ENDPROC	reg_val

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_hex
;
; Parse a hex value, or a 16-bit register name (for the register's value);
; no register name is also a hex value.
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
	push	bx
	mov	ax,[si]
	call	find_reg		; a register name?
	jc	ph0			; no
	inc	si
	inc	si
	mov	ax,regs[bx]		; (carry is clear)
	pop	bx
	ret
ph0:	pop	bx
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
; Parse [&|#][segment:]offset, where either may be a register name (see
; parse_hex); & means real mode, and # protected mode (if CPU$ is the 80286
; driver), and otherwise the address has the current mode; or parse %address,
; a physical address of up to 6 hex digits, whose "segment" is bits 16-23
; (see ADDR_PHYS).
;
; Inputs:
;	SI -> command text
;	BP = default segment
;
; Outputs:
;	If carry clear, BP:AX = address (in mem_mode), and SI -> next character
;
; Modifies:
;	AX, CX, DX, SI, BP
;
DEFPROC	parse_addr
	call	skip_space
	cmp	byte ptr [si],'%'	; a physical address?
	je	pa4			; yes
	mov	al,[cpu_mode]
	and	al,ADDR_SEL		; AL = current mode
	cmp	byte ptr [si],'&'	; real mode?
	jne	pa1			; no
	mov	al,0
	jmp	short pa2
pa1:	cmp	byte ptr [si],'#'	; protected mode?
	jne	pa3			; no
	test	[cpu_mode],CPU_DUAL	; is it available?
	stc
	jz	pa9			; no
	mov	al,ADDR_SEL
pa2:	inc	si
pa3:	mov	[mem_mode],al
	call	parse_hex
	jc	pa9
	cmp	byte ptr [si],':'
	jne	pa8
	xchg	bp,ax			; BP = segment
	inc	si
	jmp	parse_hex
pa8:	clc
pa9:	ret
pa4:	inc	si
	mov	[mem_mode],ADDR_PHYS
	push	bx
	sub	ax,ax
	cwd				; DX:AX = address
	mov	cx,si			; CX -> first digit
pa5:	mov	bl,[si]
	sub	bl,'0'
	cmp	bl,10
	jb	pa6
	sub	bl,'A'-'0'-10
	cmp	bl,10
	jb	pa7
	cmp	bl,16
	jae	pa7
pa6:	test	dl,0F0h			; room for another digit?
	stc
	jnz	pa7a			; no
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	or	al,bl
	inc	si
	jmp	pa5
pa7:	cmp	cx,si			; CF set if any digits
	cmc
pa7a:	mov	bp,dx			; BP = bits 16-23
	pop	bx
	ret
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
	call	parse_addr
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
; plus 1, so that each word is whole.  Bytes that can't be read (see mem_io)
; are displayed as ?? (and . at the right).
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
	cmp	al,'S'			; DS?
	jne	dm0b			; no
	jmp	dump_sel
dm0b:	cmp	al,'M'			; DM?
	jne	dm0a			; no
	jmp	dump_blocks
dm0a:	dec	si
	mov	ah,[dump_size]		; no, so use the last format
dm0:	push	ax
	mov	bp,[dump_seg]
	mov	di,[dump_off]
	mov	al,[dump_mode]
	mov	[mem_mode],al		; (unless there's an address)
	mov	bx,128
	call	parse_range
	pop	ax
	jnc	dm1
	ret
dm1:	mov	[dump_size],ah
	mov	[dump_seg],bp
	mov	[mem_seg],bp
	mov	al,[mem_mode]
	mov	[dump_mode],al
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
dm6:	push	di
	mov	di,si
	call	hex_addr
	pop	di
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
	push	di
	lea	di,[si+bx]
	mov	ah,[dump_size]
	mov	al,0
	call	mem_io			; AX = byte or word
	pop	di
	jnc	dm6w
	mov	al,'?'
	call	put_char
	call	put_char
	cmp	[dump_size],1		; bytes?
	je	dm6d			; yes
	call	put_char
	call	put_char
	jmp	short dm6d
dm6w:	cmp	[dump_size],1		; bytes?
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
	push	di
	lea	di,[si+bx]
	call	peek_b
	pop	di
	jc	dm7a
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
; dump_sel
;
; Parse DS selector (or a register name) and display what its descriptor
; holds, as the PCjs Debugger's DS command does: its base and limit (or for a
; gate, its selector and offset), its type and what that means, its extended
; byte's 80386 flags, and its DPL (see CPU_SEGINFO).  In real mode (or with
; the 8086 CPU$), a segment has only a base and a limit.
;
; Inputs:
;	SI -> command text after DS
;
; Outputs:
;	Carry clear if successful, set if invalid
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	dump_sel
	call	parse_hex		; AX = selector (or segment)
	jc	dsl0
	push	ax
	call	end_command
	pop	bx			; BX = selector (or segment)
	jc	dsl0
	mov	al,[cpu_mode]
	and	al,ADDR_SEL		; (a selector, in protected mode)
	push	ax
	or	al,ADDR_RIGHTS
	mov	ah,CPU_SEGINFO
	call	far ptr DDINT_CPU	; AX = access rights (zero if none)
	pop	si
	jnc	dsl0a
dsl0:	ret
dsl0a:	xchg	si,ax			; SI = rights, AL = mode
	mov	ah,CPU_SEGINFO
	call	far ptr DDINT_CPU	; DX:CX = base, AX = limit
	mov	bx,si			; BL = access rights, BH = extended
	push	ax			; save the limit (or offset)
	mov	si,offset SELS_BASE	; "base=" and " limit="
	test	bl,10h			; a code or data segment?
	jnz	dsl1			; yes
	test	bl,04h			; a gate (types 4-7 and 0Ch-0Fh)?
	jz	dsl1			; no
	mov	si,offset SELS_GATE	; "seg=" and " off="
	call	put_string
	jmp	short dsl2
dsl1:	call	put_string
	mov	al,dl
	call	hex_byte		; (bits 16-23 of the base)
dsl2:	xchg	ax,cx
	call	hex_word
	call	put_string		; " limit=" or " off="
	pop	ax
	call	hex_word
	test	bx,bx			; a descriptor?
	jz	dsl8			; no
	mov	si,offset SELS_TYPE
	call	put_string		; " type="
	mov	al,bl
	and	al,1Fh
	call	hex_byte
	call	put_string		; " ("
	push	si
	call	sel_type
	pop	si
	call	put_string		; ") ext="
	mov	al,bh
	and	ax,0F0h			; (just the 80386 flags)
	call	hex_word
	call	put_string		; " dpl="
	mov	al,bl
	mov	cl,5
	shr	al,cl
	and	al,3
	call	hex_byte
dsl8:	call	newline
	clc
	ret
ENDPROC	dump_sel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sel_type
;
; Displays what the type in a descriptor's access rights (BL) means, using
; the PCjs Debugger's names (eg, "code,readable,accessed").
;
; Modifies:
;	AX, SI
;
DEFPROC	sel_type
	mov	al,bl
	and	al,0Fh			; AL = type
	test	bl,10h			; a code or data segment?
	jnz	st1			; yes
	cmp	al,8			; a type that we have a name for?
	jae	st9			; no
	mov	si,offset SDT_NAMES
	jmp	short put_nth
st1:	mov	ah,al
	and	ah,08h			; AH = 8 for code, 0 for data
	mov	al,ah
	shr	al,1
	shr	al,1
	shr	al,1			; AL = 1 for code, 0 for data
	call	st8			; "code" or "data"
	mov	al,bl
	and	al,02h			; readable (or writable)?
	shr	al,1
	add	al,2			; AL = 2 or 3 (data)
	test	ah,ah
	jz	st2
	add	al,2			; AL = 4 or 5 (code)
st2:	call	st8
	test	bl,04h			; conforming (or expand-down)?
	jz	st3
	mov	al,6
	test	ah,ah
	jz	st2a
	inc	ax
st2a:	call	st8
st3:	test	bl,01h			; accessed?
	jz	st9
	mov	al,8
st8:	mov	si,offset SEG_NAMES
	DEFLBL	put_nth,near		; display string AL in the list at SI
	push	cx
	mov	cl,al
sn1:	dec	cl
	js	sn3
sn2:	lodsb
	test	al,al
	jnz	sn2
	jmp	sn1
sn3:	pop	cx
	jmp	put_string
st9:	ret
ENDPROC	sel_type

	DEFLBL	SELS_BASE,byte
	db	"base=",0," limit=",0
	DEFLBL	SELS_GATE,byte
	db	"seg=",0," off=",0
	DEFLBL	SELS_TYPE,byte
	db	" type=",0," (",0,") ext=",0," dpl=",0
	DEFLBL	SEG_NAMES,byte
	db	"data",0,"code",0,",readonly",0,",writable",0
	db	",execonly",0,",readable",0,",expdown",0
	db	",conforming",0,",accessed",0
	DEFLBL	SDT_NAMES,byte
	db	"?",0,"tss286",0,"ldt",0,"busy tss286",0
	db	"call gate",0,"task gate",0,"int gate286",0
	db	"trap gate286",0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fetch, fetch_word
;
; Inputs:
;	mem_seg:DI -> next instruction byte
;
; Outputs:
;	AL (or AX) = next instruction byte (or word); DI advanced
;
DEFPROC	fetch
	call	peek_b
	inc	di
	ret
ENDPROC	fetch

DEFPROC	fetch_word
	call	peek_w
	inc	di
	inc	di
	ret
ENDPROC	fetch_word

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peek_w, peek_b, poke_b, mem_io
;
; Read a word (or a byte) at mem_seg:DI, or write AL there (and advance DI),
; through CPU$ (see CPU_RWMEM), which checks the address; mem_io reads (or
; writes) AH bytes (1 or 2) of mem_val, with AL = 0 (or ADDR_WRITE).
;
; Outputs:
;	Carry clear if successful: AX (or AL) = mem_val
;	Carry set if the address isn't valid: AX = FFFFh
;
; Modifies:
;	AX
;
DEFPROC	peek_w
	mov	ax,200h
	jmp	short mem_io
ENDPROC	peek_w

DEFPROC	peek_b
	mov	ax,100h
	jmp	short mem_io
ENDPROC	peek_b

DEFPROC	poke_b
	mov	byte ptr [mem_val],al
	mov	ax,100h OR ADDR_WRITE
	call	mem_io
	inc	di
	ret
ENDPROC	poke_b

DEFPROC	mem_io
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es
	mov	cl,ah
	mov	ch,0			; CX = length
	or	al,[mem_mode]		; AL = ADDR_* flags
	mov	si,di
	mov	bx,[mem_seg]		; BX:SI -> memory
	push	ds
	pop	es
	mov	di,offset mem_val	; ES:DI -> mem_val
	mov	ah,CPU_RWMEM
	call	far ptr DDINT_CPU
	mov	ax,[mem_val]
	jnc	mi9
	mov	ax,-1
mi9:	pop	es
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	mem_io

CODE	ends

	end
