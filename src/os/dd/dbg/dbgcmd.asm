;
; BASIC-DOS Loadable Serial Debugger (Command Input)
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; get_line, which reads a command line, and the functions that parse its
; registers, values, addresses, and ranges.  It's resident, and it's separate
; because dbgdev.asm has no symbol space for it.
;
	include	macros.inc
	include	devapi.inc
	include	cpu.inc

CODE	segment word public 'CODE'

	EXTNEAR	<chk_386,cpu_call,get_char,newline,put_char,space>
	EXTBYTE	<FLAG_NAMES,HI_TAB,REG_TABLE,REGNAMES,command,cpu_mode>
	EXTBYTE	<ip_mode,last_cmd,mem_mode>
	EXTWORD	<mem_seg,regs>
	EXTABS	<CMD_MAX,CPU_DUAL,R_IP>
	public	gl1			; (patched by dbginit.asm)

	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_line
;
; Read and echo a command (in upper case, except inside quotes); Ctrl-C
; cancels the line, and on an empty line, CTRL-A echoes the last command (see
; mon4a) and returns it.
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
	cmp	al,CHR_CTRLA		; the last command?
	je	gl5			; yes
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
gl5:	test	bx,bx			; is the line empty?
	jnz	gl1			; no (so ignore CTRL-A)
	push	si
	mov	si,offset last_cmd
gl6:	lodsb
	mov	command[bx],al
	inc	bx
	test	al,al
	jz	gl7
	call	put_char
	jmp	gl6
gl7:	pop	si
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
;	If carry clear, BX = offset of the register in regs (negative for FS
;	and GS; see X_REGS)
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
fr2:	push	ax
	mov	al,[bx+2]
	cbw
	xchg	bx,ax
	pop	ax			; (carry is clear)
	ret
ENDPROC	find_reg

;
; find_ereg finds a 32-bit register's name (EAX through EDI, or EIP), which
; only an 80386 has.
;
; Inputs:
;	SI -> text
;
; Outputs:
;	If carry clear, BX = the offset of its low word in regs, and DI =
;	its high word's
;
; Modifies:
;	AX, BX, DI
;
DEFPROC	find_ereg
	cmp	byte ptr [si],'E'
	jne	fe8
	call	chk_386			; an 80386?
	jc	fe9			; no
	mov	ax,[si+1]
	call	find_reg
	jc	fe9
	cmp	bx,R_IP			; a general register, or IP?
	ja	fe8			; no
	mov	di,bx
	shr	di,1
	mov	al,HI_TAB[di]
	cbw
	xchg	di,ax
	test	di,di			; does it have a high word?
	jnz	fe9			; yes (and carry is clear)
fe8:	stc
fe9:	ret
ENDPROC	find_ereg

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

;
; reg_val32 returns the 32-bit general register that includes 16-bit
; register AL, in DX:AX.
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	reg_val32
	call	reg_val
	push	ax
	shr	bx,1
	mov	al,HI_TAB[bx]
	cbw
	xchg	bx,ax
	mov	dx,regs[bx]
	pop	ax
	ret
ENDPROC	reg_val32

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_h32
;
; Parse a 32-bit value: a hex value of up to 8 digits, or a register's name
; (a 16-bit register's, or on an 80386, a 32-bit one's), and any terms added
; to it or subtracted from it, with + or - (and no spaces; eg, ESP+8).
;
; Inputs:
;	SI -> command text
;
; Outputs:
;	If carry clear, DX:AX = value, and SI -> next character
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	parse_h32
	call	h32_term
	jc	ph39
ph31:	mov	cl,[si]
	cmp	cl,'+'			; another term to add?
	je	ph32			; yes
	cmp	cl,'-'			; or to subtract?
	clc
	jne	ph39			; no
ph32:	inc	si
	push	dx
	push	ax
	push	cx
	call	h32_term		; DX:AX = the term
	pop	cx
	jc	ph38
	cmp	cl,'-'
	jne	ph33
	neg	dx
	neg	ax
	sbb	dx,0
ph33:	pop	cx
	add	ax,cx
	pop	cx
	adc	dx,cx
	jmp	ph31
ph38:	pop	cx
	pop	cx			; (carry is still set)
ph39:	ret
ENDPROC	parse_h32

DEFPROC	h32_term
	call	skip_space
	push	bx
	push	di
	call	find_ereg		; a 32-bit register?
	jc	ht1			; no
	add	si,3
	mov	ax,regs[bx]
	mov	dx,regs[di]
	jmp	short ht8
ht1:	mov	ax,[si]
	call	find_reg		; a 16-bit register?
	jc	ht2			; no
	inc	si
	inc	si
	mov	ax,regs[bx]
	sub	dx,dx			; (carry is clear)
	jmp	short ht8
ht2:	sub	ax,ax
	cwd				; DX:AX = value
	mov	cx,si			; CX -> first digit
ht3:	mov	bl,[si]
	sub	bl,'0'
	cmp	bl,10
	jb	ht4
	sub	bl,'A'-'0'-10
	cmp	bl,10
	jb	ht7
	cmp	bl,16
	jae	ht7
ht4:	test	dh,0F0h			; room for another digit?
	stc
	jnz	ht8			; no
	mov	bh,4
ht5:	shl	ax,1
	rcl	dx,1
	dec	bh
	jnz	ht5
	or	al,bl
	inc	si
	jmp	ht3
ht7:	cmp	cx,si			; CF set if any digits
	cmc
ht8:	pop	di
	pop	bx
	ret
ENDPROC	h32_term

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sel_lin
;
; Makes the linear address of selector:offset the memory to access.
;
; Inputs:
;	AX = selector, CX:DI = offset
;
; Outputs:
;	Carry clear if the selector is valid: mem_seg:DI = linear address,
;	and mem_mode = ADDR_LIN
;
; Modifies:
;	AX, CX, DI
;
DEFPROC	sel_lin
	push	bx
	push	dx
	push	cx
	xchg	bx,ax
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_SEL OR ADDR_LIN
	call	cpu_call		; DX:CX = its base (a linear address)
	pop	ax
	jc	sn9
	add	di,cx
	adc	ax,dx
	mov	[mem_seg],ax
	mov	[mem_mode],ADDR_LIN	; (carry is clear)
	clc
sn9:	pop	dx
	pop	bx
	ret
ENDPROC	sel_lin

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_hex
;
; Parse a hex value, or a 16-bit register name (for the register's value);
; no register name is also a hex value.  Terms can be added or subtracted,
; with + or - (and no spaces; eg, IP+2).
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
	call	hex_term
	jc	px9
px1:	mov	cl,[si]
	cmp	cl,'+'			; another term to add?
	je	px2			; yes
	cmp	cl,'-'			; or to subtract?
	clc
	jne	px9			; no
px2:	inc	si
	push	ax
	push	cx
	call	hex_term		; AX = the term
	pop	cx
	pop	dx
	jc	px9
	cmp	cl,'-'
	jne	px3
	neg	ax
px3:	add	ax,dx
	jmp	px1
px9:	ret
ENDPROC	parse_hex

DEFPROC	hex_term
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
ENDPROC	hex_term

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_addr
;
; Parse [&|#][segment:]offset, where either may be a register name (see
; parse_hex); & means real mode (in protected mode, the active session's V86
; machine, if any; see ADDR_V86), and # protected mode (if CPU$ is the 80286
; driver), and otherwise the address has the current mode; or parse %address,
; a linear address (see ADDR_LIN), or %%address, a physical one (ADDR_PHYS),
; of up to 8 hex digits, whose "segment" is bits 16-31 (see parse_h32, for
; what else it may be).  In a flat machine (see get_v86), an address with no
; prefix is a linear address, too.
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
	mov	al,[ip_mode]		; AL = current mode
	cmp	byte ptr [si],'&'	; real mode?
	jne	pa1			; no
	test	al,al			; while in protected mode?
	jz	pa2			; no
;
; In protected mode, a real-mode address is in the active session's V86
; machine, if it has one.
;
	push	bx
	push	si
	sub	bx,bx
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_V86
	call	cpu_call		; is there a machine?
	pop	si
	pop	bx
	cmc
	sbb	al,al
	and	al,ADDR_V86		; AL = ADDR_V86 if so, else 0
	jmp	short pa2
pa1:	cmp	byte ptr [si],'#'	; protected mode?
	jne	pa3			; no
	test	[cpu_mode],CPU_DUAL	; is it available?
	stc
	jz	pa9			; no
	mov	al,ADDR_SEL
pa2:	inc	si
pa3:	test	al,ADDR_LIN		; in a flat machine (see get_v86)?
	jz	pa3a			; no
	mov	al,ADDR_LIN		; yes, so it's a linear address
	jmp	short pa4a
pa3a:	mov	[mem_mode],al
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
	mov	al,ADDR_LIN
	cmp	byte ptr [si],'%'	; %% (a physical address)?
	jne	pa4a			; no
	inc	si
	mov	al,ADDR_PHYS
pa4a:	mov	[mem_mode],al
	call	parse_h32		; DX:AX = address
	jc	pa7
;
; A linear address can also be selector:offset (eg, ES:80, or CS:EIP in a
; flat machine), which is the selector's base plus the offset.
;
	cmp	byte ptr [si],':'
	jne	pa6
	cmp	[mem_mode],ADDR_LIN
	stc
	jne	pa7
	inc	si
	push	ax
	call	parse_h32		; DX:AX = offset
	pop	bp			; BP = selector
	jc	pa7
	push	di
	xchg	di,ax
	mov	cx,dx
	xchg	ax,bp
	call	sel_lin			; mem_seg:DI = linear address
	xchg	ax,di			; AX = bits 0-15
	pop	di
	mov	dx,[mem_seg]
	jc	pa7
pa6:	mov	bp,dx			; BP = bits 16-31
	clc
pa7:	ret
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

CODE	ends

	end
