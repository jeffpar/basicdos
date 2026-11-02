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

	EXTNEAR	<dbg_brk,dbg_fault,dbgdev_com,disarm>
	EXTNEAR	<end_command>
	EXTNEAR	<get_char,gl1,hex_digit,mon3a,mon4,mon4a,mon_sp,newline>
	EXTNEAR	<put_char,put_raw,put_string>
	EXTNEAR	<dc_0f>
	EXTBYTE	<CMD_Q,OPTAB,com_flow,command,brk_skip>
	EXTWORD	<com_port,dos_seg,vec_save>
	EXTLONG	<old_com,old_fault>

CMD_TAIL	equ	80h	; PSP_CMDTAIL (see com_main)

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
	jc	din8
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	al,dl
	and	al,COMDBG_XON OR COMDBG_RTS
	mov	[com_flow],al
	xor	dl,al
	mov	[com_port],dx
;
; Nothing else can fail, so install the hooks: INT 00h, INT 04h, INT 01h,
; INT 03h, and the port's hardware interrupt (chosen by port, as the COM
; driver does: IRQ4 for 3xxh, IRQ3 for 2xxh), and then have the UART
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
	call	far ptr DDINT_CPU	; DX:CX = previous handler
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
	call	far ptr DDINT_CPU	; AH = CPUF_* flags
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
	mov	bx,offset vec_save
	mov	al,00h
	call	sv1
	add	bx,4			; (skip INT 04h)
	mov	al,01h
	call	sv1
	mov	al,03h
	call	sv1
	pop	dx
	pop	cx
	ret
sv1:	mov	cx,[bx].OFF
	mov	dx,[bx].SEG
	call	far ptr DDINT_SETVEC	; DX:CX = previous vector
	mov	[bx].OFF,cx
	mov	[bx].SEG,dx
	add	bx,4
	ret
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
	mov	[com_cs],bp
	inc	[com_runs]
	call	set_dos
	mov	bx,offset put_raw
	mov	ax,offset dos_put
	call	set_jmp
	mov	bx,offset get_char
	mov	ax,offset dos_get
	call	set_jmp
	mov	[CMD_Q],'Q'
	mov	ax,sp
	sub	ax,330h			; leave the program room, and rebase
	mov	word ptr [mon_sp+1],ax
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
	jmp	short cm5a
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
	cli
	jmp	dbg_brk
	ASSUME	DS:CODE
cm7:	mov	si,offset FIND_MSG
	cmp	al,ERR_NOFILE		; file not found?
	je	cm7b			; yes
	cmp	al,ERR_NOPATH		; path not found?
	je	cm7b			; yes
	mov	si,offset LOAD_MSG
cm7b:
	IFDEF DEBUG
	push	ax			; save the error code
	ENDIF
	call	put_string
	mov	si,offset command
	call	put_string		; display the program name
	IFDEF DEBUG
	mov	si,offset ERRNUM_MSG
	call	put_string
	pop	ax
	call	put_dec			; display the error code
	mov	al,')'
	call	put_char
	ENDIF
	jmp	short cm9a
cm8:	cmp	[com_runs],2		; did the program terminate itself?
	jne	cm9b			; no, Q did
	mov	ah,DOS_PSP_RETCODE
	int	21h			; AH = exit type
	test	ah,ah			; EXTYPE_NORMAL?
	jnz	cm9b			; no (eg, a divide error DOS reported)
	mov	si,offset TERM_MSG
	call	put_string
cm9a:	call	newline
	jmp	short cm9b
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
	mov	ah,DOS_PSP_RETURN
	int	21h
ENDPROC	com_main


	DEFLBL	LOAD_MSG,byte
	db	"Unable to load ",0
	DEFLBL	FIND_MSG,byte
	db	"Unable to find ",0
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
; com_sels
;
; Returns a code segment (or selector) and a data segment (or selector) for
; PSP:0100h, where our file starts: in real mode, CS+10h for both, and in
; protected mode, selectors from CPU$ (CPU_MAP), which com_main frees when we
; exit.  This runs before com_main switches to them (so it can't use any
; absolute addresses), and exits if CPU$ has no selectors.
;
; Outputs:
;	AX = code segment, DX = data segment
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	com_sels
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU	; AH = CPUF_* flags
	mov	al,0
	test	ah,CPUF_PM		; is CS a selector?
	jz	csl1			; no
	mov	al,ADDR_SEL		; yes
csl1:	mov	bx,cs
	mov	ah,CPU_SEGINFO
	call	far ptr DDINT_CPU	; DX:CX = our PSP's address
	add	cx,100h
	adc	dx,0			; DX:CX = PSP:0100h
	mov	si,1
	sub	di,di			; SI:DI = 64K
	push	dx
	push	cx
	mov	ax,(CPU_MAP SHL 8) OR MEMF_CODE
	call	far ptr DDINT_CPU	; AX = code segment
	pop	cx
	pop	dx
	jc	csl9
	push	ax
	mov	ax,CPU_MAP SHL 8	; (a data segment)
	call	far ptr DDINT_CPU	; AX = data segment
	xchg	dx,ax
	pop	ax
	jc	csl9
	ret
csl9:	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h			; (we can't run without them)
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
	call	far ptr DDINT_CPU
	pop	cx
	ret
ENDPROC	com_free

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

	DEFBYTE	com_runs,0		; 1 running, 2 program loaded, 3 Q
	DEFWORD	com_cs,0		; our PSP's code segment (see com_main)
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
