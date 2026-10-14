;
; BASIC-DOS Loadable Serial Debugger
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage (in CONFIG.SYS): DEVICE=DEBUG.SYS COM2:9600,N,8,1,VT100
;
; Ctrl-C or a serial BREAK stops the machine at the next timer interrupt,
; and INT 1 and INT 3 also enter the monitor.  D and R are read-only, and G
; resumes.
;
; Only INIT calls DOS.  The monitor can interrupt DOS (or an IRQ handler),
; so it runs on a private stack with interrupts disabled, polling the UART
; of a COM port that INIT opened with MODE_DENY_RW.  For the same reason, it
; can't use the DOS utility functions (eg, SPRINTF), which enable
; interrupts and reenter the DOS dispatcher.
;
	include	macros.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	uart.inc

CODE	segment para public 'CODE'

DBGDEV	DDH	<-1,-1,DDATTR_CHAR,dbgdev_req,0,2020564544474244h>

	DEFPTR	old_clock		; original INT 08h handler
	DEFPTR	frame			; saved registers (see dbgdev_enter)
	DEFWORD	com_port,0		; UART base port
	DEFWORD	dump_seg,0		; segment of the next D command
	DEFWORD	dump_off,0		; offset of the next D command
	DEFBYTE	com_flow,0		; COMDBG_XON and/or COMDBG_RTS
	DEFBYTE	paused,0		; set by XOFF, cleared by XON
	DEFBYTE	from_clock,0		; set if entered from INT 08h
	DEFBYTE	in_head,0		; next byte to read from in_buf
	DEFBYTE	in_tail,0		; next byte to write in in_buf
;
; Register names, with offsets of the saved registers in the frame, in
; display order; FRAME_FL is the offset of the saved flags.
;
	DEFLBL	REG_TABLE,byte
	db	"AX",20,"BX",18,"CX",16,"DX",14,"SP",0,"BP",12,"SI",10,"DI",8
	DEFLBL	SEG_TABLE,byte
	db	"DS",6,"ES",4,"SS",2,"CS",24
	DEFLBL	SEG_END,byte
	db	"IP",22
FRAME_FL	equ	26
;
; Flag names (clear, set), for the flags in FLAG_MASK, from high to low;
; they must immediately follow REG_TABLE (see show_regs).
;
FLAG_MASK	equ	0ED5h	; OF, DF, IF, SF, ZF, AF, PF, and CF
	DEFLBL	FLAG_NAMES,byte
	db	"NVOV","UPDN","DIEI","PLNG","NZZR","NAAC","POPE","NCCY"

	DEFLBL	HELP_MSG,byte
	db	"D [[segment:]offset [end | L count]]  dump memory (hex)",13,10
	db	"R  display registers    G  resume    ?  help",13,10,0

IN_MASK		equ	127	; in_buf is a ring buffer, with one slot unused
	DEFBYTE	in_buf,0,IN_MASK+1
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
; dbgdev_clock (INT 08h)
;
; Enter the monitor if Ctrl-C (or BREAK) was received; otherwise, chain to
; the original handler.  Bytes received while running are otherwise ignored.
;
DEFPROC	dbgdev_clock,far
	push	ax
	push	dx
	push	ds
	push	cs
	pop	ds
	ASSUME	DS:CODE
	call	poll_rx
	jz	dbc9
	cmp	al,CHR_CTRLC
	jne	dbc9
	mov	[from_clock],al		; the monitor will chain on resume
	pop	ds
	pop	dx
	pop	ax
	jmp	short dbgdev_enter
dbc9:	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	pop	ax
	jmp	cs:[old_clock]
ENDPROC	dbgdev_clock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dbgdev_trap (INT 01h and INT 03h)
;
DEFPROC	dbgdev_trap,far
	mov	cs:[from_clock],0	; the monitor will IRET on resume
ENDPROC	dbgdev_trap			; fall into dbgdev_enter

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dbgdev_enter
;
; Save the interrupted registers on the interrupted stack (that's the frame),
; and run the monitor on our own stack until G.
;
; Inputs:
;	Interrupt frame on SS:SP (with interrupts disabled)
;
DEFPROC	dbgdev_enter,far
	push	ax
	push	bx
	push	cx
	push	dx
	push	bp
	push	si
	push	di
	push	ds
	push	es
	push	ss			; SS and SP are saved for display only
	mov	bp,sp
	lea	ax,[bp+26]		; AX = SP before the interrupt
	push	ax
	mov	cs:[frame].OFF,sp
	mov	cs:[frame].SEG,ss
	mov	ax,[bp+4]
	mov	cs:[dump_seg],ax	; D defaults to the interrupted DS
	push	cs
	pop	ds
	ASSUME	DS:CODE
	push	cs
	pop	ss
	mov	sp,offset mon_stack_end
	cld
	mov	al,[in_tail]		; discard any buffered input
	mov	[in_head],al
	mov	[paused],0
	call	newline
	call	show_regs

mon0:	mov	al,'-'
	call	put_char
	call	get_line
	mov	si,offset command
	call	skip_space
	lodsb
	test	al,al			; empty line?
	jz	mon0			; yes
	cmp	al,'D'
	jne	mon1
	call	dump_memory
	jmp	short mon7
mon1:	call	end_command
	jc	mon8
	cmp	al,'R'
	jne	mon2
	call	show_regs
	jmp	mon0
mon2:	cmp	al,'?'
	jne	mon3
	mov	si,offset HELP_MSG
	call	put_string
	jmp	mon0
mon3:	cmp	al,'G'
	jne	mon8
;
; Restore the interrupted stack and registers, and then IRET (or chain to
; the original INT 08h handler, which still owes the PIC its EOI).
;
	mov	ss,[frame].SEG
	mov	sp,[frame].OFF
	add	sp,4			; discard the saved SP and SS
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
	cmp	cs:[from_clock],0
	je	mon9
	jmp	cs:[old_clock]
mon9:	iret

	ASSUME	DS:CODE
mon7:	jnc	mon0
mon8:	mov	al,'?'
	call	put_char
	call	newline
	jmp	mon0
ENDPROC	dbgdev_enter

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Monitor helpers (DS = CS and interrupts disabled; DF clear for strings).
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
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
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
; pasted commands aren't lost during long dumps).
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
	ret
ENDPROC	put_char

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
	jmp	put_char
ENDPROC	newline

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hex_word, hex_byte, hex_digit
;
; Inputs:
;	AX (hex_word), AL (hex_byte), or AL = 0-15 (hex_digit)
;
; Modifies:
;	AX
;
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
; get_reg
;
; Inputs:
;	AL = offset of a saved register in the frame
;
; Outputs:
;	AX = saved register
;
DEFPROC	get_reg
	push	bx
	push	es
	les	bx,[frame]
	cbw
	add	bx,ax
	mov	ax,es:[bx]
	pop	es
	pop	bx
	ret
ENDPROC	get_reg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; show_regs
;
; Display the saved registers and flags, in the same format as DEBUG.
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	show_regs
	mov	si,offset REG_TABLE
sr1:	cmp	si,offset SEG_TABLE	; start of the second line?
	jne	sr2			; no
	call	newline
sr2:	lodsw
	call	put_char
	mov	al,ah
	call	put_char
	mov	al,'='
	call	put_char
	lodsb
	call	get_reg
	call	hex_word
	call	space
	cmp	si,offset FLAG_NAMES
	jb	sr1			; SI -> FLAG_NAMES when done

	mov	al,FRAME_FL
	call	get_reg
	mov	cl,4
	shl	ax,cl
	xchg	dx,ax			; DX = flags, with OF in bit 15
	mov	bx,FLAG_MASK SHL 4	; BX = flags to display, likewise
sr3:	shl	bx,1			; display the next flag?
	jnc	sr5			; no
	lodsw
	xchg	cx,ax			; CX = name if clear
	lodsw				; AX = name if set
	test	dh,80h			; is the flag set?
	jnz	sr4			; yes
	xchg	cx,ax
sr4:	call	put_char
	mov	al,ah
	call	put_char
	call	space
sr5:	shl	dx,1
	test	bx,bx
	jnz	sr3
	jmp	newline
ENDPROC	show_regs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_line
;
; Read and echo a command (in upper case); Ctrl-C cancels the line.
;
; Outputs:
;	command contains a null-terminated line
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	get_line
	sub	bx,bx
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
;	Carry clear if only spaces remain, set otherwise
;
DEFPROC	end_command
	call	skip_space
	cmp	byte ptr [si],1		; CF set if null
	cmc
	ret
ENDPROC	end_command

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
; dump_memory
;
; Parse D [[segment:]offset [end | L count]] and dump memory, where segment
; may also be DS, ES, SS, or CS.  Rows are aligned on 16 bytes, with a dash
; after the 8th byte and ASCII at the right.
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
	mov	bp,[dump_seg]
	mov	di,[dump_off]
	mov	bx,128			; BX = default count
	call	skip_space
	cmp	byte ptr [si],0
	je	dm5
	mov	ax,[si]
	cmp	byte ptr [si+2],':'
	jne	dm1
	mov	dx,si
	mov	si,offset SEG_TABLE
dm0:	cmp	ax,[si]			; segment register name?
	je	dm0a			; yes
	add	si,3
	cmp	si,offset SEG_END
	jb	dm0
	mov	si,dx
	jmp	short dm1
dm0a:	mov	al,[si+2]
	call	get_reg
	xchg	bp,ax			; BP = segment
	mov	si,dx
	add	si,3
	jmp	short dm2
dm1:	call	parse_hex
	jc	dm9
	cmp	byte ptr [si],':'
	jne	dm3
	xchg	bp,ax			; BP = segment
	inc	si
dm2:	call	parse_hex
	jc	dm9
dm3:	xchg	di,ax			; DI = offset
	call	skip_space
	cmp	byte ptr [si],0
	je	dm5
	cmp	byte ptr [si],'L'
	jne	dm4
	inc	si
	call	parse_hex
	jc	dm9
	test	ax,ax
	jz	dm8
	jmp	short dm4a
dm4:	call	parse_hex		; AX = end offset
	jc	dm9
	sub	ax,di
	jb	dm9
	inc	ax
	jz	dm8
dm4a:	xchg	bx,ax			; BX = count
dm5:	call	end_command
	jnc	dm5a
dm8:	stc
dm9:	ret
dm5a:	mov	[dump_seg],bp
	mov	es,bp
	mov	cx,bx			; CX = bytes remaining
	mov	si,di
	and	si,0FFF0h		; SI = start of the first row
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
dm6a:	add	al,dl
	mov	dh,al
	sub	bx,bx
dm6b:	cmp	bl,dl
	jb	dm6c
	cmp	bl,dh
	jae	dm6c
	mov	al,es:[si+bx]
	call	hex_byte
	jmp	short dm6d
dm6c:	call	space
	call	space
dm6d:	mov	al,' '
	cmp	bl,7
	jne	dm6e
	mov	al,'-'
dm6e:	call	put_char
	inc	bx
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
	sub	cx,ax
	jz	dm7c
	jmp	dm6
dm7c:	mov	[dump_off],di		; (and carry is clear)
	ret
ENDPROC	dump_memory

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
; Nothing else can fail, so install the hooks.
;
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:NOTHING
	cli
	mov	ax,offset dbgdev_clock
	xchg	ax,ds:[08h*4]
	mov	cs:[old_clock].OFF,ax
	mov	ax,cs
	xchg	ax,ds:[08h*4+2]
	mov	cs:[old_clock].SEG,ax
	mov	word ptr ds:[01h*4],offset dbgdev_trap
	mov	ds:[01h*4+2],cs
	mov	word ptr ds:[03h*4],offset dbgdev_trap
	mov	ds:[03h*4+2],cs
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
	db	"BASIC-DOS serial debugger: "
	db	"Ctrl-C or BREAK to stop; ? for help",13,10,0

CODE	ends

	end
