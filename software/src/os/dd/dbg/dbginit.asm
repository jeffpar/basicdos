;
; BASIC-DOS Loadable Serial Debugger (Initialization and Program Mode)
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This is the part of DEBUG.COM that a driver doesn't keep (see dbgdev.asm):
; INIT, which opens the COM port and installs the hooks, and program mode.
; LINK puts it after the resident code, at resident_end, and it's the only
; part that calls DOS (so dbgdev.asm can omit DOSFUNC).  Since the resident
; code is in another module, the jumps that we patch there are computed at
; run time (see set_jmp).
;
	DOSFUNC equ 1
	DOSHEAP equ 1
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc
	include	uart.inc
	include	version.inc

CODE	segment word public 'CODE'

	EXTNEAR	<arm,cg1,cpu_call,ct1v,ct2a,dbg_brk,dbg_fault,dbgdev_com>
	EXTNEAR	<cmd_help,cmd_l,disarm,ip_mem,peek_b,resume,skip_space,step>
	EXTNEAR	<chk_over,end_command,parse_addr,parse_hex,poke_b>
	EXTNEAR	<get_char,gl1,hex_digit,mon3a,mon4,mon4a,mon_sp,newline>
	EXTNEAR	<put_char,put_raw,put_string>
	EXTNEAR	<dc_0f>
	EXTBYTE	<CMD_LN,CMD_Q,CMD_VEC,HELP_MSG,OPTAB,bp_tab,com_flow,command>
	EXTBYTE	<HELP_END,brk_skip,mute,notstart,tracing>
	EXTWORD	<VEC_DRV,dump_seg,start_hook>
	EXTWORD	<com_port,dos_seg,mem_seg,vec_save>
	EXTLONG	<old_com,old_fault>
	EXTABS	<BP_SET,BP_GO>

CMD_TAIL	equ	80h	; PSP_CMDTAIL (see com_main)
SEC_BYTES	equ	512	; bytes per sector (see com_rd)

	DEFLBL	resident_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dbgdev_init
;
; Open the COM port exclusively, and then install the interrupt hooks; a
; failure closes the port and leaves no hooks.
;
; The arguments are the COM descriptor and then any switches (using the
; current switch char), each of which is a monitor command (eg, /BP 70:100).
; If there are any, our final RET becomes an INT 3, and get_line reads them
; from sw_get, as if they had been typed, followed by a G, so that booting
; continues with any breakpoints set; /H omits the G, so that the monitor
; prompts instead.  /G is ignored, since it would resume us before the end
; of the switches.
;
; Inputs:
;	ES:BX -> DDPI (DDPI_BUFPTR -> arguments)
;
; Outputs:
;	DDPI updated
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	dbgdev_init,far
	mov	ax,DOS_MSC_GETSWC
	int	21h			; DL = switch char
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	[sw_char],dl
	ASSUME	DS:NOTHING
	mov	di,bx			; ES:DI -> DDPI
	lds	si,es:[di].DDPI_BUFPTR	; DS:SI -> arguments
	mov	bx,si			; BX -> COM descriptor
din0:	lodsb
	cmp	al,' '			; end of the descriptor?
	ja	din0			; no
	mov	byte ptr [si-1],0
din0a:	test	al,al			; end of the arguments?
	jz	din0b			; yes
	lodsb
	cmp	al,dl			; a switch?
	jne	din0a			; no
	call	skip_h
	mov	ax,ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	[sw_ptr].OFF,si
	mov	[sw_ptr].SEG,ax
	push	ax
	push	bx
	mov	bx,offset gl1
	mov	ax,offset sw_get
	call	set_rel			; get_line calls sw_get
	pop	bx
	pop	ax
	mov	byte ptr [din7],0CCh	; INT 3
	mov	ds,ax
	ASSUME	DS:NOTHING
din0b:	mov	dx,bx			; DS:DX -> COM descriptor
	mov	ax,DOS_HDL_OPENRW OR MODE_DENY_RW
	int	21h			; open the port for exclusive access
	jnc	din0c
	jmp	din9
din0c:	xchg	bx,ax			; BX = handle
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_COMDEBUG
	int	21h
	jnc	din0d
	jmp	din8
din0d:	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	al,dl
	and	al,COMDBG_XON OR COMDBG_RTS
	mov	[com_flow],al
	xor	dl,al
	mov	[com_port],dx
;
; Nothing else can fail, so install the hooks: INT 00h, INT 04h, INT 01h,
; INT 03h, INT 13h, INT 21h, and the port's hardware interrupt (chosen by port,
; as the COM driver does: IRQ4 for 3xxh, IRQ3 for 2xxh), and then have the UART
; interrupt us when data (or a BREAK) arrives, and have CPU$ give us any
; fatal exception, too (see CPU_SETFAULT), keeping the previous handler
; (DOS's), which gets the exceptions that VT doesn't trap (see dbg_fault).
;
	call	set_dos
	call	hook_vecs
	push	dx
	mov	bx,offset vec_save+4
	mov	al,04h
	call	sv1			; hook INT 04h, too
	mov	[vec_save+18],cs
	mov	[vec_save+22],cs
	mov	bx,offset vec_save+16
	mov	al,INT_FDC
	call	sv1			; and INT 13h
	mov	al,INT_DOSFUNC
	call	sv1			; and INT 21h
	pop	dx
	mov	al,INT_HW_COM1
	cmp	dh,03h			; port 3xxh?
	je	din1			; yes
	mov	al,INT_HW_COM2
din1:	push	dx
	mov	cx,offset dbgdev_com
	mov	dx,cs
	cli
	call	far ptr DDINT_SETVEC	; DX:CX = previous vector
	mov	[old_com].OFF,cx
	mov	[old_com].SEG,dx
	pop	dx
	inc	dx			; DX -> REG_IER (DLAB is clear)
	mov	al,IER_RBR_AVAIL OR IER_DELTA
	out	dx,al
	sti
	cld
	mov	cx,offset dbg_fault
	mov	dx,cs			; DX:CX -> dbg_fault
	mov	ah,CPU_SETFAULT
	call	cpu_call		; DX:CX = previous handler
	mov	[old_fault].OFF,cx
	mov	[old_fault].SEG,dx
	mov	si,offset BANNER
	call	put_string
	mov	es:[di].DDPI_END.OFF,offset resident_end
	mov	es:[di].DDPI_END.SEG,cs
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
din7:	nop				; (switches change this to INT 3)
;
; Unless /H was given, a DBGBRK doesn't stop us from now on (see brk_skip).
;
	cmp	[sw_halt],'H'		; was there a /H?
	je	din7a			; yes
	inc	[brk_skip]
din7a:	ret
din8:	mov	ah,DOS_HDL_CLOSE
	int	21h
din9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE + DDSTAT_ERROR + DDERR_GENFAIL
	ret
ENDPROC	dbgdev_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sw_get
;
; get_line's input (in place of get_char) while INIT performs its switches:
; the text of each switch is a line, ended by the next switch char or the
; end of the arguments.  Then we supply a G, or after a /H, read from the
; port; either way, get_line's get_char call is restored at the end of the
; last line (or immediately, if there were no lines), since we're not
; resident.
;
; Outputs:
;	AL = next byte
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	sw_get
	push	si
	push	ds
sg1:	lds	si,cs:[sw_ptr]
	ASSUME	DS:NOTHING
	lodsb
	cmp	al,cs:[sw_char]		; the next switch?
	jne	sg2			; no
	call	skip_h
	jmp	short sg4
sg2:	test	al,al			; end of the switches?
	jnz	sg5			; no
	dec	si			; (stay at the null)
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	cmp	[sw_halt],al		; was there a /H (or is this our G)?
	jne	sg3			; yes
	cmp	[sw_last],CHR_RETURN	; at the start of a line?
	jne	sg4			; no, so end it
	inc	[sw_halt]		; (so the G's end restores get_char)
	mov	[sw_ptr].OFF,offset G_CMD
	mov	[sw_ptr].SEG,cs
	jmp	sg1
sg3:	push	bx
	mov	bx,offset gl1
	mov	ax,offset get_char
	call	set_rel			; get_line calls get_char again
	pop	bx
	cmp	[sw_last],CHR_RETURN	; at the start of a line?
	jne	sg4			; no, so end it
	pop	ds
	pop	si
	jmp	get_char
sg4:	mov	al,CHR_RETURN
sg5:	pop	ds			; DS = our data again (see get_line)
	mov	[sw_ptr].OFF,si
	mov	[sw_last],al
	pop	si
	ret
ENDPROC	sw_get

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; skip_h
;
; Skip any /H switches (setting sw_halt) and /G switches, each up to the
; next switch char.
;
; Inputs:
;	DS:SI -> switch text (after the switch char)
;
; Outputs:
;	DS:SI -> switch text (or the null at the end of the arguments)
;
; Modifies:
;	AL
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	skip_h
sh1:	mov	al,[si]
	and	al,NOT 20h		; upper-case the switch letter
	cmp	al,'G'			; /G?
	je	sh2			; yes
	cmp	al,'H'			; /H?
	jne	sh9			; no
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	[sw_halt],al		; (nonzero)
	pop	ds
	ASSUME	DS:NOTHING
sh2:	lodsb
	test	al,al			; end of the arguments?
	jz	sh8			; yes
	cmp	al,cs:[sw_char]		; the next switch?
	jne	sh2			; no
	jmp	sh1
sh8:	dec	si
sh9:	ret
ENDPROC	skip_h

	DEFPTR	sw_ptr			; next switch text (see sw_get)
	DEFBYTE	sw_char,0		; switch char
	DEFBYTE	sw_halt,0		; nonzero after /H (or for our G)
	DEFBYTE	sw_last,CHR_RETURN	; last byte from sw_get
	DEFBYTE	com_r3,0		; nonzero at ring 3 (see com_sels)
	DEFLBL	G_CMD,byte
	db	"G",0

	DEFLBL	BANNER,byte
	db	"BASIC-DOS Debugger "
	VERSION_STR
	db	13,10,"CTRL-C or BREAK to stop, ? for help",13,10,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_jmp, set_rel
;
; Make the instruction at BX a JMP to AX (set_jmp), or change the target of
; the JMP or CALL at BX to AX (set_rel).
;
; Inputs:
;	AX = target, DS:BX -> instruction (DS = our data)
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	set_jmp
	mov	byte ptr [bx],0E9h	; JMP (near)
	DEFLBL	set_rel,near
	sub	ax,bx
	sub	ax,3			; AX = displacement
	mov	[bx+1],ax
	ret
ENDPROC	set_jmp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_dos
;
; Records DOS's segment (or selector), for DM (see md_sys), and then sets up
; the disassembler for the processor (see set_cpu).
;
; Inputs:
;	DS = our data (DDH_DATA)
;
; Modifies:
;	AX, BX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	set_dos
	push	es
	mov	ah,DOS_MSC_GETVARS
	int	21h			; ES = DOS's segment (or selector)
	mov	[dos_seg],es
	pop	es
ENDPROC	set_dos				; fall into set_cpu

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_cpu
;
; On an 8086 or 8088, opcodes 60h-6Fh are copies of 70h-7Fh, C0h-C1h of
; C2h-C3h, and C8h-C9h of CAh-CBh, and 0Fh is POP CS, so if CPU$ says that's
; the processor (with CPUF_HWTYPE, which a "CPU=8088" line doesn't change),
; we change the disassembler's OPTAB entries and 0Fh test to match.
;
; Inputs:
;	DS = our data (DDH_DATA)
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	set_cpu
	push	cx
	push	dx
	mov	ah,CPU_GETINFO
	call	cpu_call		; AH = CPUF_* flags
	test	ah,CPUF_HWTYPE		; an 8086 or 8088?
	jnz	sc9			; no
	push	si
	push	di
	push	es
	push	ds
	pop	es
	cld
	mov	si,offset OPTAB+(70h-60h)*2
	mov	di,offset OPTAB
	mov	cx,16
	rep	movsw			; 60h-6Fh = 70h-7Fh
	mov	si,offset OPTAB+(0C2h-60h)*2
	mov	di,offset OPTAB+(0C0h-60h)*2
	movsw
	movsw				; C0h-C1h = C2h-C3h
	add	si,(0CAh-0C4h)*2
	add	di,(0C8h-0C2h)*2
	movsw
	movsw				; C8h-C9h = CAh-CBh
	mov	byte ptr [dc_0f+1],0FFh	; (AL is below 20h there, so no 0Fh)
	pop	es
	pop	di
	pop	si
sc9:	pop	dx
	pop	cx
	ret
ENDPROC	set_cpu

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hook_vecs, swap_vecs
;
; Exchange the INT 00h, INT 01h, and INT 03h vectors with vec_save (in the
; resident code, since dbg_int0 and cmd_g use the previous INT 00h handler),
; which hook_vecs first points at our handlers.  INT 04h's entry is skipped,
; since only the driver hooks it (see dbgdev_init): DOS restores the others if
; a program ends with them hooked (see psp_restvec), but not INT 04h.
;
; At ring 3, DOS gets and sets them instead, which reflects an interrupt from
; ring 3 code in our session to our handler (see RVEC in ring3.asm), and gets
; us a stub in place of the previous handler (which chains to it); setting
; the stub again restores it.  INT 00h isn't hooked there, since only VT
; needs it.
;
; Inputs:
;	DS = our data (DDH_DATA)
;
; Modifies:
;	AX, BX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	hook_vecs
	mov	[vec_save+2],cs
	mov	[vec_save+6],cs
	mov	[vec_save+10],cs
	mov	[vec_save+14],cs
ENDPROC	hook_vecs			; fall into swap_vecs

DEFPROC	swap_vecs
	push	cx
	push	dx
	mov	bx,offset vec_save+8
	cmp	[com_r3],0		; at ring 3 (where there's no VT)?
	jne	sw1			; yes, so INT 00h isn't hooked
	mov	bx,offset vec_save
	mov	al,00h
	call	sv1
	add	bx,4			; (skip INT 04h)
sw1:	mov	al,01h
	call	sv1
	mov	al,03h
	call	sv1
	pop	dx
	pop	cx
	ret
sv1:	mov	cx,[bx].OFF
	mov	dx,[bx].SEG
	cmp	[com_r3],0		; at ring 3?
	jne	sv2			; yes
	call	far ptr DDINT_SETVEC	; DX:CX = previous vector
sv1a:	mov	[bx].OFF,cx
	mov	[bx].SEG,dx
	add	bx,4
	ret
sv2:	push	es
	push	bx
	push	ax
	mov	ah,DOS_MSC_GETVEC
	int	21h			; ES:BX = previous vector
	pop	ax
	push	es
	push	bx
	push	ds
	mov	ds,dx
	mov	dx,cx			; DS:DX = new vector
	mov	ah,DOS_MSC_SETVEC
	int	21h
	pop	ds
	pop	cx
	pop	dx			; DX:CX = previous vector
	pop	bx
	pop	es
	jmp	sv1a
ENDPROC	swap_vecs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; com_main
;
; Program entry (via the DDH and in_buf).  Rebase CS so that offset 0 is the
; start of the file, as it is for the driver (see com_sels), and DDH_DATA is
; a data segment (or selector) for the same memory,
; then patch put_char and get_char to use DOS console I/O, enable Q, hook
; INT 00h, 01h, and 03h (unless there's a switch), and run the monitor on our
; own stack (just below the frame) rather than its small one (DOS calls run
; on the caller's stack).
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
; interrupted, after storing a RET there (over the DDH's JMP, which is done),
; so G pops the zero that DOS pushed on our stack and runs the INT 20h at
; PSP:0000h (psp_restvec then restores INT 00h, 01h, and 03h).  That "program"
; shares our stack, so the monitor's stack leaves it 200h bytes (beyond the
; frame), enough for a stop inside a DOS call (and for resume's copy of the
; registers below it).
;
; A /H switch is skipped, since we halt at the prompt anyway (as a driver
; does only with /H; see dbgdev_init).  A tail that starts with any other
; switch (eg, /DB 40:0) is instead a command, which the monitor performs in
; place of displaying the registers, and then exits;
; INT 00h, 01h, and 03h aren't hooked, so that a dump shows their vectors as
; they are.
;
; We load a program with DOS_PSP_EXEC1 (load without starting), which fills
; in its initial SS:SP and CS:IP and leaves its PSP current, and enter the
; monitor as if the program's first instruction had been interrupted, so no
; breakpoint is needed to stop it there.
;
; The L command loads one that way after we've started (see com_l), and ?
; lists our commands with the monitor's (see com_help).  At ring 3 (see
; com_sels), we change some JMPs (see COM_JMPS): CPU$ calls go to r3_cpu, T
; steps over an INT n (see ct1v), and we don't disable interrupts (which ring
; 3 can't); DM, DS, GT, LN, VC, VL, and VT are invalid, as ? shows.
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	com_main,far
	mov	bp,cs			; BP = our PSP's code segment
	call	com_sels		; AX = code, DX = data (PSP:0100h)
	push	ax
	mov	ax,offset cm1
	push	ax
	ret				; (RETF, since this is a FAR proc)
cm1:	mov	ds,dx
	ASSUME	DS:CODE
	mov	ds:[0].DDH_DATA,dx
	mov	[com_sp],sp		; com_main's stack (see com_exec2)
	mov	[com_ss],ss
	mov	[com_cs],bp
	inc	[com_runs]
	mov	[CMD_Q],'Q'
	mov	[VEC_DRV],-1		; (we hook only INT 00h; see VEC_TAB)
	mov	[start_hook],offset com_exec2
	mov	word ptr [CMD_LN+1],offset com_l
	mov	si,offset COM_JMPS
	mov	cx,COM_NJMPS
	cmp	[com_r3],0		; at ring 3?
	jne	cm1a			; yes
	call	set_dos			; (which calls CPU$)
	jmp	short cm1r
cm1a:	mov	cl,COM_NJMPS + R3_NJMPS
	mov	word ptr [CMD_VEC+1],offset rc8	; (VC, VL, and VT fail)
cm1r:	lodsw
	xchg	bx,ax			; BX -> instruction
	lodsw				; AX = its new target
	call	set_jmp
	loop	cm1r
	mov	ax,sp
	sub	ax,330h			; leave the program room, and rebase
	mov	word ptr [mon_sp+1],ax
	DEFLBL	cm1t,near		; (com_l re-enters here; see com_l)
	mov	ax,DOS_MSC_GETSWC
	int	21h			; DL = switch char
	mov	si,CMD_TAIL+1		; ES:SI -> command tail (ES = PSP)
	mov	di,offset command
cm2:	mov	al,es:[si]
	inc	si
	cmp	al,' '			; skip leading spaces
	je	cm2
	cmp	al,dl			; a switch?
	jne	cm3			; no
	mov	al,es:[si]
	and	al,NOT 20h		; (upper-case the switch letter)
	cmp	al,'H'			; /H?
	jne	cm6			; no, so it's a command
	cmp	byte ptr es:[si+1],' '	; just /H (and not, eg, /HELP)?
	ja	cm6			; no
	inc	si			; yes, so skip it (we halt anyway)
	jmp	cm2
cm3:	cmp	al,' '			; space or CHR_RETURN ends the name
	jbe	cm4
	mov	[di],al
	inc	di
	mov	al,es:[si]
	inc	si
	jmp	cm3
;
; Copy the switch's command to command, in upper case (a long one spills
; into mon_stack, which program mode doesn't use), and change the monitor to
; perform it in place of displaying the registers (at mon3a), and to exit in
; place of prompting for another command (at mon4).  INT 00h, 01h, and 03h
; are never hooked, so the exit (at cm9c) skips swap_vecs.
;
cm6:	mov	al,es:[si]
	inc	si
	cmp	al,'a'
	jb	cm6a
	cmp	al,'z'
	ja	cm6a
	sub	al,'a'-'A'
cm6a:	cmp	al,CHR_RETURN		; end of the tail?
	je	cm6b			; yes
	mov	[di],al
	inc	di
	jmp	cm6
cm6b:	mov	byte ptr [di],0
	mov	bx,offset mon3a
	mov	ax,offset mon4a
	call	set_jmp
	mov	bx,offset mon4
	mov	ax,offset cm9c
	call	set_jmp
	jmp	cm5a
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
	call	hook_vecs
	push	ds
	pop	es
	mov	bx,offset epb		; ES:BX -> EPB
	mov	dx,offset command	; DS:DX -> program name
	mov	ax,DOS_PSP_EXEC1
	int	21h			; load it (termination returns here)
	mov	ds,cs:[0].DDH_DATA
	jc	cm7			; it couldn't be loaded
	cmp	[com_runs],1		; did we just load it (0 for L)?
	jbe	cm4c			; yes
	jmp	cm8			; no, it terminated
cm4c:	mov	[com_runs],2
	mov	[notstart],1		; stop at the entry; start it on resume
	mov	ah,DOS_PSP_GET
	int	21h			; BX = the program's PSP
	pushf
	pop	cx			; CX = flags (with interrupts enabled)
	cmp	[com_r3],0		; at ring 3 (where we can't CLI)?
	jne	cm4t			; yes (and interrupts land on SP0)
	cli
cm4t:	mov	ss,[epb_sp].SEG		; (MOV SS holds interrupts for MOV SP)
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
	jmp	short cm5c
	ASSUME	DS:CODE
cm5:	call	hook_vecs
cm5a:	mov	byte ptr es:[100h],0C3h	; RET
	push	[com_cs]		; (the PSP's code segment)
	push	es			; ES = PSP
	pop	ds
	ASSUME	DS:NOTHING
	pop	ax
	pushf
	push	ax
	mov	ax,100h
	push	ax
	sub	ax,ax			; (AX = 0 in the frame)
cm5c:	cli				; (a JMP to dbg_brk at ring 3)
	jmp	dbg_brk
	ASSUME	DS:CODE
cm7:	mov	si,offset FIND_MSG
	cmp	al,ERR_NOFILE		; file not found?
	je	cm7b			; yes
	cmp	al,ERR_NOPATH		; path not found?
	je	cm7b			; yes
	mov	si,offset LOAD_MSG
cm7b:	mov	bx,offset command	; BX -> the program name
	call	put_err
	jmp	short cm9r
cm8:	cmp	[com_runs],2		; did the program terminate itself?
	jne	cm9b			; no, Q did
	mov	ah,DOS_PSP_RETCODE
	int	21h			; AH = exit type
	test	ah,ah			; EXTYPE_NORMAL?
	jnz	cm9b			; no (eg, a divide error DOS reported)
	mov	si,offset TERM_MSG
	call	put_string
cm9a:	call	newline
cm9r:	cmp	[com_runs],1		; did an L command fail to load one?
	jae	cm9b			; no
	jmp	com_lf			; yes, so we keep running

;
; Exit (Q, or at cm9c, the end of a switch's command).  If a program is
; loaded, terminate it first, which brings us back to cm8, and then exit with
; its exit code.
;
cm9:	call	disarm
	cmp	[com_runs],2		; is a program loaded?
	jne	cm9b			; no
	inc	[com_runs]		; yes (and Q is terminating it)
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
cm9b:	call	swap_vecs
cm9c:	mov	ah,DOS_PSP_GET
	int	21h			; BX = our PSP
	mov	ah,DOS_PSP_RETCODE
	int	21h			; AL = the program's exit code (or 0)
	cmp	[com_r3],0		; at ring 3?
	jne	cm9e			; yes (DOS frees our copy)
;
; Free the segments (or selectors) from com_sels, after switching SS, DS,
; and ES to our PSP, and CS to the PSP's code segment, since reloading a
; freed selector would fault.
;
	mov	dx,cs
	mov	cx,cs:[0].DDH_DATA	; DX and CX to free
	cli
	mov	ss,bx
	add	sp,100h			; (the same stack, through our PSP)
	sti
	mov	ds,bx
	mov	es,bx
	push	cs:[com_cs]
	mov	bx,offset cm9d + 100h
	push	bx
	ret				; (RETF to PSP:cm9d)
cm9d:	push	ax
	mov	bx,dx
	call	com_free
	mov	bx,cx
	call	com_free
	pop	ax
cm9e:	mov	ah,DOS_PSP_RETURN
	int	21h
ENDPROC	com_main


	DEFLBL	UNABLE_MSG,byte
	db	"Unable to ",0
	DEFLBL	LOAD_MSG,byte
	db	"load ",0
	DEFLBL	FIND_MSG,byte
	db	"find ",0
	DEFLBL	READ_MSG,byte
	db	"read ",0
	DEFLBL	DRIVE_MSG,byte
	db	"Invalid drive",0
	IFDEF DEBUG
	DEFLBL	ERRNUM_MSG,byte
	db	" (",0
	ENDIF
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
	jc	cq9
	jmp	cm9
cq9:	ret
ENDPROC	com_quit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; com_exec2
;
; The monitor's first resume (G, T, or P) of a just-loaded program comes here
; (see resume and notstart in dbgdev.asm), to start the program, rather than
; IRET to it: we start it with DOS_PSP_EXEC2, which, unlike an IRET, blocks us
; as its parent, so that when it terminates, DOS returns here, and we go to
; cm8 (exactly as a program loaded on our command line does).  Breakpoints and
; single-steps stop it meanwhile (nested, as usual), and resume with an IRET.
;
; We run on com_main's stack (see cm1), not the monitor's small one, since the
; EXEC2 call (and, in real mode, the program it runs) needs the room; and if
; the monitor was tracing (T or P), we start the program single-stepping (its
; trap flag), which psp_exec keeps, so no breakpoint is written (eg, in an NE
; program's code).  A register the user changed before this first resume isn't
; applied (the program starts at its loaded entry).
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	com_exec2
	cmp	[com_r3],0		; at ring 3 (where we can't CLI)?
	jne	cx1			; yes
	cli
cx1:	mov	ss,[com_ss]		; (MOV SS holds interrupts for MOV SP)
	mov	sp,[com_sp]		; com_main's stack (see cm1)
	cmp	[com_r3],0
	jne	cx2			; (ring 3 keeps interrupts on)
	sti
cx2:	sub	dx,dx			; DX = 0 (no trap flag)
	cmp	[tracing],0		; a T or P (single-step the first)?
	jz	cx3			; no
	mov	dx,0100h		; yes, so ask psp_exec to set FL_TRAP
cx3:	push	ds
	pop	es
	mov	bx,offset epb		; ES:BX -> EPB
	mov	ax,DOS_PSP_EXEC2
	int	21h			; start it (termination returns here)
	mov	ds,cs:[0].DDH_DATA
	jmp	cm8
ENDPROC	com_exec2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; com_l
;
; Program mode's L command (in place of cmd_l): L file [arguments] loads a
; program, if none is loaded, as if our command line had named it.  The rest
; of the line becomes our PSP's command tail, and with the vectors unhooked
; (since com_main hooks them again), com_main parses it on its original
; stack; if the program can't be loaded, com_main comes back to com_lf, which
; stops again, as it does with no program.  LN is still cmd_l's, except at
; ring 3, where it needs CPU$.  With a drive in place of a file, L reads
; sectors instead (see com_rd), whether or not a program is loaded.
;
DEFPROC	com_l
	cmp	byte ptr [si],'N'	; LN?
	jne	ld1			; no
	cmp	[com_r3],0		; at ring 3?
	jne	ld9			; yes (no LN)
	jmp	cmd_l
ld1:	call	skip_space
	cmp	byte ptr [si+1],':'	; a drive letter and a colon?
	jne	ld1a			; no
	cmp	byte ptr [si+2],' '	; and no filename after them?
	jbe	com_rd			; right
ld1a:	cmp	[com_runs],1		; is a program loaded?
	jne	ld9			; yes
	mov	ax,DOS_MSC_GETSWC
	int	21h			; DL = switch char
	mov	al,[si]
	cmp	al,dl			; a switch?
	je	ld9			; yes (L takes only a program)
	cmp	al,1			; no program at all?
	jb	ld9			; no
	mov	ah,DOS_PSP_GET
	int	21h			; BX = our PSP
	mov	es,bx
	mov	di,CMD_TAIL+1
ld2:	lodsb
	stosb				; copy the rest of the line
	test	al,al
	jnz	ld2
	mov	byte ptr es:[di-1],CHR_RETURN
	xchg	ax,di
	sub	al,CMD_TAIL+2
	mov	es:[CMD_TAIL],al	; AL = its length
	call	swap_vecs		; (cm4 hooks them again)
	mov	[com_runs],0		; (an L command is loading it)
;
; Re-enter com_main's command parsing (cm2) to load the program as if we were
; invoked with it, on com_main's stack rather than the monitor's small one
; (see cm1 and com_exec2), with interrupts on, as com_main has them.
;
	cmp	[com_r3],0		; at ring 3 (where we can't CLI)?
	jne	ld3			; yes
	cli
ld3:	mov	ss,[com_ss]		; (MOV SS holds interrupts for MOV SP)
	mov	sp,[com_sp]		; com_main's stack (see cm1)
	cmp	[com_r3],0
	jne	ld4			; (ring 3 keeps interrupts on)
	sti
ld4:	jmp	cm1t
ld9:	stc
	ret
;
; com_lf
;
; com_main comes here when an L command's program couldn't be loaded, to stop
; with no program, as at cm5a (where the vectors are hooked).
;
	DEFLBL	com_lf,near
	inc	[com_runs]		; (running, with no program)
	mov	ah,DOS_PSP_GET
	int	21h			; BX = our PSP
	mov	es,bx
	jmp	cm5a
ENDPROC	com_l

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; com_rd
;
; L drive: sector count address reads sectors to memory, opening the drive as
; a volume (a filename that's only a drive), whose file offsets are sector
; numbers times SEC_BYTES (which all of our disk drivers assume), and closing
; it afterward.  The default segment is the same as E's, and each sector goes
; through sec_buf, so that it can be stored wherever E can store it.  A failure
; leaves any sectors already stored.
;
; Inputs:
;	SI -> drive letter, followed by a colon and then a space or null
;
; Outputs:
;	Carry set if the command or the memory is invalid; otherwise, carry
;	clear (after displaying any error)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
DEFPROC	com_rd
	mov	bx,si			; BX -> drive name
	inc	si
	inc	si
	call	parse_hex		; AX = first sector
	jc	ld9
	xchg	di,ax			; DI = first sector
	call	parse_hex		; AX = number of sectors
	jc	ld9
	push	ax
	mov	bp,[dump_seg]
	call	parse_addr		; BP:AX = address
	pop	cx			; CX = number of sectors
	jc	ld9
	mov	[mem_seg],bp
	xchg	bp,ax			; BP = offset
	call	end_command		; anything else on the line?
	jc	ld9			; yes
	jcxz	ld9			; (there must be at least one sector)
	mov	ax,SEC_BYTES
	mul	cx			; DX:AX = number of bytes
	add	ax,bp
	adc	dx,0
	sub	ax,1
	sbb	dx,0			; DX:AX = offset of the last byte
	jnz	ld9			; (it must be within the segment)
	mov	byte ptr [bx+2],0	; (end the drive name)
	mov	dx,bx			; DS:DX -> drive name
	mov	ax,DOS_HDL_OPENRO
	int	21h			; AX = handle
	mov	si,offset READ_MSG
	jc	put_err			; (eg, a file is open for writing)
	push	bx			; save the drive name
	xchg	bx,ax			; BX = handle
	xchg	ax,di			; AX = first sector
	mov	di,bp			; mem_seg:DI -> memory
	mov	bp,cx			; BP = number of sectors
	mov	cx,SEC_BYTES
	mul	cx
	xchg	cx,dx
	xchg	dx,ax			; CX:DX = offset of the first sector
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	jc	rd5
rd2:	mov	cx,SEC_BYTES
	mov	dx,offset sec_buf	; DS:DX -> sector buffer
	mov	ah,DOS_HDL_READ
	int	21h			; AX = bytes read
	jc	rd5
	cmp	ax,cx			; did the sector exist (read in full)?
	jne	rd5			; no (AX is displayed as an error code)
	mov	si,dx
rd3:	lodsb
	call	poke_b			; (carry set if the address is invalid)
	jc	rd4
	loop	rd3
	dec	bp
	jnz	rd2
rd4:	sbb	si,si			; SI = -1 if not valid, or zero
	jmp	short rd6
rd5:	mov	si,offset READ_MSG
rd6:	push	ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	ax
	pop	bx			; BX -> drive name
	test	si,si			; were they all stored?
	jz	rd9			; yes (carry clear)
	jns	put_err			; no, a sector couldn't be read
rd8:	stc				; no, the memory isn't valid
rd9:	ret
ENDPROC	com_rd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_err
;
; Displays "Unable to", a verb, and a name, plus the error in DEBUG builds, or
; if the error is ERR_BADDRIVE, simply "Invalid drive".
;
; Inputs:
;	AX = error code
;	SI -> verb (eg, LOAD_MSG)
;	BX -> name
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, SI (and CX and DX in DEBUG builds)
;
DEFPROC	put_err
	cmp	ax,ERR_BADDRIVE		; no such drive?
	jne	pe1			; no
	mov	si,offset DRIVE_MSG
	call	put_string
	jmp	short pe9
pe1:
	IFDEF DEBUG
	push	ax			; save the error code
	ENDIF
	push	si
	mov	si,offset UNABLE_MSG
	call	put_string
	pop	si
	call	put_string
	mov	si,bx
	call	put_string		; display the name
	IFDEF DEBUG
	mov	si,offset ERRNUM_MSG
	call	put_string
	pop	ax
	call	put_dec			; display the error code
	mov	al,')'
	call	put_char
	ENDIF
pe9:	call	newline
	clc
	ret
ENDPROC	put_err

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; com_help
;
; Program mode's ? command (in place of cmd_help): HELP_MSG's lines, merged in
; order with our own (com_lines, for L and Q), except at ring 3, the lines for
; the commands that we don't support there (R3_NOHELP), which are skipped.
;
DEFPROC	com_help
	push	ds
	pop	es
	cld
	mov	si,offset HELP_MSG
	mov	bx,offset com_lines	; BX -> our next line
ch1:	cmp	si,offset HELP_END	; the last line?
	je	ch5			; yes
	mov	al,[bx]
	cmp	al,[si]			; does our next line come first?
	ja	ch2			; no
	xchg	bx,si
	call	ch_line
	xchg	bx,si
	jmp	ch1
ch2:	cmp	[com_r3],0		; at ring 3?
	je	ch3			; no, so display the line
	mov	ax,[si]			; AX = the line's first two characters
	push	di
	mov	di,offset R3_NOHELP
	mov	cx,R3_NNOHELP
	repne	scasw			; one we don't support at ring 3?
	pop	di
	jne	ch3			; no, so display it
	inc	[mute]			; yes, so skip it
	call	ch_line
	dec	[mute]
	jmp	ch1
ch3:	call	ch_line			; display the line
	jmp	ch1
ch5:	jmp	put_string		; (which returns carry clear)
ch_line:lodsb				; display (unless muted) up to a LF
	call	put_char
	cmp	al,CHR_LINEFEED
	jne	ch_line
	ret
ENDPROC	com_help

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; com_sels
;
; Returns a code segment (or selector) and a data segment (or selector) for
; PSP:0100h, where our file starts: in real mode, CS+10h for both, and in
; protected mode, selectors from CPU$ (CPU_MAP), which com_main frees when we
; exit.  This runs before com_main switches to them (so it can't use any
; absolute addresses), and exits if CPU$ has no selectors.
;
; At ring 3 (only in protected mode, where CS is a code alias, not DS), we
; can't call CPU$, so we copy ourselves (from PSP:0100h up to our stack) to
; offset 0 of a block of our own instead, which DOS frees when we exit, and
; return its selector and code alias, with com_r3 set in the copy.
;
; Outputs:
;	AX = code segment, DX = data segment
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	com_sels
	mov	ax,cs
	mov	dx,ds
	cmp	ax,dx			; is CS our PSP (real mode)?
	je	csl0			; yes
	test	al,3			; ring 3?
	jnz	csl2			; yes
csl0:	mov	ah,CPU_GETINFO
	call	cpu_call		; AH = CPUF_* flags
	mov	al,0
	test	ah,CPUF_PM		; is CS a selector?
	jz	csl1			; no
	mov	al,ADDR_SEL		; yes
csl1:	mov	bx,cs
	mov	ah,CPU_SEGINFO
	call	cpu_call		; DX:CX = our PSP's address
	add	cx,100h
	adc	dx,0			; DX:CX = PSP:0100h
	mov	si,1
	sub	di,di			; SI:DI = 64K
	push	dx
	push	cx
	mov	ax,(CPU_MAP SHL 8) OR MEMF_CODE
	call	cpu_call		; AX = code segment
	pop	cx
	pop	dx
	jc	csl9
	push	ax
	mov	ax,CPU_MAP SHL 8	; (a data segment)
	call	cpu_call		; AX = data segment
	xchg	dx,ax
	pop	ax
	jc	csl9
	ret
csl2:	mov	bx,sp
	mov	cl,4
	shr	bx,cl			; BX = paras (up to our stack)
	mov	ah,DOS_MEM_ALLOC
	int	21h			; AX = the block's selector
	jc	csl9
	mov	es,ax
	mov	si,100h
	sub	di,di
	mov	cx,sp
	sub	cx,si
	shr	cx,1
	cld
	rep	movsw			; copy PSP:0100h up to our stack
	inc	es:[com_r3]
	push	ds
	pop	es			; (ES = PSP again)
	xchg	bx,ax			; BX = the copy's selector
	DOSUTIL	ALIAS,0			; AX = its code alias
	mov	dx,bx
	jnc	csl8
csl9:	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h			; (we can't run without them)
csl8:	ret
ENDPROC	com_sels

;
; com_free frees the segment (or selector) in BX (see com_sels); in real mode,
; there's nothing to free.  It runs at PSP:0000h (see cm9d), so it can't use
; any absolute addresses.
;
DEFPROC	com_free
	push	cx
	sub	cx,cx			; (one selector)
	mov	ah,CPU_UNMAP
	call	cpu_call
	pop	cx
	ret
ENDPROC	com_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_cpu
;
; At ring 3, CPU$ calls come here (see cpu_call), since ring 3 code can't call
; CPU$: CPU_RWMEM accesses the memory itself (see r3_rwmem), and CPU_SEGINFO
; returns a selector (with RPL 3) in place of its base, so that at_ip can
; still compare addresses; anything else fails (eg, CPU_SYSREGS, so that the
; monitor works as it does with the 8086 CPU$, and CPU_QUERY, so DM fails).
;
; Inputs and outputs:
;	The same as CPU$'s (but a failure leaves AX unchanged)
;
	.286p
DEFPROC	r3_cpu
	cmp	ah,CPU_RWMEM
	je	r3_rwmem
	cmp	ah,CPU_SEGINFO
	jne	rc8
	test	al,ADDR_PHYS OR ADDR_RIGHTS	; (which we can't tell)
	jnz	rc8
	mov	dx,bx
	or	dl,3
	sub	cx,cx			; DX:CX = the selector, as an address
	ret
rc8:	stc
	ret
ENDPROC	r3_cpu

;
; r3_rwmem copies CX bytes from BX:SI to ES:DI (or with ADDR_WRITE, from ES:DI
; to BX:SI), if LSL, VERR, and VERW say that the selector allows it (so that
; we don't fault).  A code selector isn't writable, so if it's the code alias
; of a block (eg, a COM program's CS, or an NE program's code segment, for a
; breakpoint or an E), we write through the block's own selector instead.  It
; preserves only DS (mem_io, the only caller, saves the rest).
;
DEFPROC	r3_rwmem
	push	ds
	mov	dx,cx
	dec	dx
	add	dx,si			; DX = offset of the last byte
	jc	rw8			; (it wraps)
	push	ax
	lsl	ax,bx			; AX = the segment's limit
	jnz	rw7			; (there's no such segment)
	cmp	dx,ax			; is the last byte within it?
	pop	ax
	ja	rw8			; no
	test	al,ADDR_WRITE		; a write?
	jnz	rw2			; yes
	verr	bx			; can we read it?
	jnz	rw8			; no
	mov	ds,bx			; DS:SI -> memory (ES:DI -> buffer)
	jmp	short rw4
rw2:	verw	bx			; can we write it?
	jz	rw3			; yes
	DOSUTIL	ALIAS,1			; AX = the block it's a code alias of
	jc	rw8			; (it's not)
	verw	ax			; can we write that?
	jnz	rw8			; no
	xchg	bx,ax			; BX = the block's selector
rw3:	push	es
	pop	ds			; DS:DI -> buffer
	mov	es,bx
	xchg	si,di			; DS:SI -> buffer, ES:DI -> memory
rw4:	rep	movsb
	clc
	jmp	short rw9
rw7:	pop	ax
rw8:	stc
rw9:	pop	ds
	ret
ENDPROC	r3_rwmem
	.8086

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_go
;
; At ring 3, G, P, and T resume through here (in place of cg1).  To go past a
; breakpoint at CS:IP, cg1 single-steps its instruction (with TF), but for an
; INT n, the single-step trap would come from the INT's ring 0 handler, where
; we can't see it (and where a debugger loaded as a driver would stop).  So
; at an INT n, if the temporary breakpoint is free, we put it after the INT
; (or after the string that follows it; see chk_over), with BP_GO, so that
; reaching it resumes (see mon1), and resume without TF, as we do if P put
; it there.
;
DEFPROC	r3_go
	call	ip_mem			; mem_seg:DI -> CS:IP
	call	peek_b			; AL = its opcode
	cmp	al,0CDh			; INT n?
	jne	rg8			; no
	call	chk_over		; mem_seg:DI -> the next instruction
	test	bp_tab[5],BP_SET	; is the temporary breakpoint free?
	jnz	rg1			; no
	mov	word ptr bp_tab[0],di
	mov	ax,[mem_seg]
	mov	word ptr bp_tab[2],ax
	mov	al,BP_SET
	or	al,BP_GO
	mov	bp_tab[5],al
rg1:	cmp	word ptr bp_tab[0],di	; is it after the INT (eg, for P)?
	jne	rg8			; no (eg, for G addr)
	mov	ax,[mem_seg]
	cmp	word ptr bp_tab[2],ax
	jne	rg8
	call	arm
	jmp	short rg9		; (with no TF)
rg8:	call	arm			; (as cg1 does)
	mov	al,2
	jnc	rg9
	jmp	step
rg9:	jmp	resume
ENDPROC	r3_go

	IFDEF DEBUG
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_dec (DEBUG builds only)
;
; Inputs:
;	AX = unsigned value (displayed in decimal)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	put_dec
	mov	cx,10
	sub	dx,dx
	div	cx			; AX = quotient, DX = remainder
	push	dx
	test	ax,ax			; any more digits?
	jz	pdec1			; no
	call	put_dec
pdec1:	pop	ax
	jmp	hex_digit		; display AL (0-9) as a digit
ENDPROC	put_dec
	ENDIF

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

	DEFBYTE	com_runs,0		; 0 L, 1 running, 2 program loaded, 3 Q
	DEFWORD	com_cs,0		; our PSP's code segment (see com_main)
	DEFWORD	com_ss,0		; com_main's stack (see com_exec2)
	DEFWORD	com_sp,0		; com_main's entry SP (see com_l)
;
; Program mode's own commands, in order, for com_help (0FFh comes after any
; other line), and the commands that need CPU$, which com_help skips at ring 3
; (each as two characters).
;
	DEFLBL	com_lines,byte
	db	"L file [args]",9,"load program",13,10
	db	"L drv: s n addr",9,"load sectors",13,10
	db	"Q",9,9,"quit",13,10,0FFh
	DEFLBL	R3_NOHELP,byte
	db	"DMDSGTLNVCVLVT"
R3_NNOHELP	equ	7
;
; The instructions that com_main makes JMPs (see set_jmp), each paired with
; its new target: COM_NJMPS of them in any mode, and R3_NJMPS more at ring 3.
;
	DEFWORD	COM_JMPS,<put_raw,dos_put,get_char,dos_get,cmd_help,com_help>
	dw	cpu_call,r3_cpu,ct1v,ct2a,cg1,r3_go,cm5c,dbg_brk
COM_NJMPS	equ	3
R3_NJMPS	equ	4
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
; The COMDATA tells the loader that we need only a small heap (for com_rd's
; sector buffer and the stack in program mode); without it, we'd get half of
; the available memory.  As a driver, everything past resident_end is discarded
; anyway.
;
	COMHEAP	<SEC_BYTES+2048>
sec_buf	equ	$

CODE	ends

	end
