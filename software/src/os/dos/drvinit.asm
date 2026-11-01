;
; BASIC-DOS Installable Device Driver Initialization
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc

DOS	segment word public 'CODE'

	EXTNEAR	<find_cfg,set_ddint,dos_call5>
	EXTWORD	<dos_seg,call5_gate,mem_size,init_base,init_len,init_data>
	EXTLONG	<init_addr>
	EXTLONG	<dev_head>

	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; load_devices
;
; Load the driver in every "DEVICE=" setting, in CONFIG.SYS order.  Unlike
; the BASDEV drivers, these are single-header character device files (with
; no relocations), starting with a DDH whose REQUEST handler also handles
; DDC_INIT; DDH_NEXT_OFF must be FFFFh, or a JMP SHORT in a dual-mode .COM
; file.  DDPI_BUFPTR points to the ASCIIZ arguments after the filename, and
; if INIT fails, it must leave no hooks behind.  Each driver is added to the
; head of the driver list, and any failure is reported.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX, SI, DI
;
DEFPROC	load_devices
	push	bx
	push	cx
	push	bp
	push	ds
	push	es
	push	ss			; (our data; see sysinit_high)
	pop	ds
	ASSUME	DS:DOS
	jmp	short ld1

ld9:	pop	es
	pop	ds
	ASSUME	DS:NOTHING
	pop	bp
	pop	cx
	pop	bx
	ret

	ASSUME	DS:DOS
ld1:	mov	si,offset CFG_DEVICE
	call	find_cfg		; look for "DEVICE="
	jc	ld9			; no more
;
; Null-terminate the filename at DI, and set SI to its arguments, if any.
;
	mov	si,di
ld2:	lodsb
	cmp	al,' '			; space, tab, or null?
	ja	ld2			; no
	dec	si
	test	al,al
	jz	ld3a			; no arguments
	mov	byte ptr [si],0
ld3:	inc	si
	cmp	byte ptr [si],' '
	je	ld3
	cmp	byte ptr [si],CHR_TAB
	je	ld3
ld3a:
;
; Open the file, and allocate enough memory to read all of it.
;
	mov	dx,di
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jnc	ld3b
	jmp	ld8
ld3b:	xchg	bx,ax			; BX = handle
	sub	cx,cx
	sub	dx,dx
	mov	ax,DOS_HDL_SEEKEND
	int	21h			; DX:AX = file size
	jc	ld7
	test	dx,dx
	jnz	ld6
	cmp	ax,size DDH
	jb	ld6
	mov	cx,ax			; CX = file size
	add	ax,15
	rcr	ax,1			; (including any carry)
	shr	ax,1
	shr	ax,1
	shr	ax,1
	push	bx
	xchg	bx,ax			; BX = paras
	mov	ah,DOS_MEM_ALLOC
	int	21h
	pop	bx
	jc	ld7
	mov	es,ax			; ES = driver segment
	push	cx
	sub	cx,cx
	sub	dx,dx
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	pop	cx
	jc	ld4
	push	ds
	push	es
	pop	ds
	ASSUME	DS:NOTHING
	mov	ah,DOS_HDL_READ
	int	21h			; read CX bytes into ES:0
	pop	ds
	ASSUME	DS:DOS
ld4:	pushf
	push	ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	ax
	popf
	jc	ld5
	cmp	ax,cx			; did we read the entire file?
	jne	ld4a			; no
	cmp	es:[DDH_NEXT_OFF],-1	; a single header?
	je	ld4b			; yes
	cmp	byte ptr es:[DDH_NEXT_OFF],0EBh	; or a .COM's JMP SHORT?
	jne	ld4a			; no
ld4b:	test	es:[DDH_ATTR],DDATTR_CHAR
	jz	ld4a			; not a character device
	cmp	es:[DDH_REQUEST],cx	; request handler inside the file?
	jb	ld10			; yes
ld4a:	mov	ax,ERR_BADFORMAT
ld5:	push	ax
	mov	ah,DOS_MEM_FREE
	int	21h
	pop	ax
	jmp	short ld8
ld6:	mov	ax,ERR_BADFORMAT
ld7:	push	ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	ax
ld8:	mov	dx,offset VERB_FIND
	cmp	ax,ERR_NOFILE		; file not found?
	je	ld8a			; yes
	cmp	ax,ERR_NOPATH		; path not found?
	je	ld8a			; yes
	mov	dx,offset VERB_LOAD
ld8a:	EPRINTF	<"Warning: unable to %ls device %s">,<13,10>,ax,dx,cs,di
	jmp	ld1
;
; Initialize the driver, with a DDPI on the stack.  DDPI_END defaults to the
; end of the file, in case the driver doesn't set it.  The driver's block is
; its data segment (or selector), and we call it (and link it) through a code
; alias from CPU$ (see CPU_ALIAS), which in real mode is the same segment.
;
ld10:	sub	sp,size DDPI
	mov	bp,sp			; SS:BP -> DDPI
	DBGINIT	STRUCT,[bp],DDP
	mov	[bp].DDP_LEN,size DDPI
	mov	[bp].DDP_CMD,DDC_INIT
	mov	[bp].DDP_STATUS,0
	mov	[bp].DDPI_END.OFF,cx
	mov	[bp].DDPI_BUFPTR.OFF,si
	mov	[bp].DDPI_BUFPTR.SEG,ds
	mov	es:[DDH_DATA],es	; the driver's data segment
	push	cx			; save the file size
	push	es			; and the driver's data segment
	mov	bx,es
	mov	ax,(CPU_ALIAS SHL 8) OR MEMF_CODE
	call	far ptr DDINT_CPU	; AX = code selector (or segment)
	ASSERT	NC
	push	ax			; create far pointer to DDH_REQUEST
	push	es:[DDH_REQUEST]	; at [bp-8]
	push	ss
	pop	es
	mov	bx,bp			; ES:BX -> DDPI
	push	bp
	push	di
	push	ds
	call	dword ptr [bp-8]
	pop	ds
	pop	di
	pop	bp
	pop	ax			; toss DDH_REQUEST offset
	pop	dx			; DX = code selector (or segment)
	pop	es			; ES = driver's data segment
	pop	cx			; CX = file size
	mov	ax,[bp].DDP_STATUS
	mov	bx,[bp].DDPI_END.OFF
	add	sp,size DDPI
	test	ax,DDSTAT_ERROR
	jz	ld10a
	mov	ax,ERR_GENFAIL		; (freeing the block frees the alias)
	jmp	ld5
;
; Release any memory beyond the driver's end, and add it to the driver list
; (with its code selector, in DX).
;
ld10a:	cmp	bx,cx
	jae	ld11
	add	bx,15
	mov	cl,4
	shr	bx,cl
	mov	ah,DOS_MEM_REALLOC
	int	21h
;
; Name the driver's memory block after the device, and have the block own
; itself (like a resident program), so that MEM lists it by name.
;
ld11:	push	dx
	mov	cx,es
	mov	bx,cx			; BX = owner (the block itself)
	mov	dx,-1			; DX:CX = block
	mov	si,DDH_NAME		; ES:SI -> name
	mov	ax,(CPU_SETBLK SHL 8) OR MCBTYPE_NONE
	call	far ptr DDINT_CPU
	pop	dx			; DX = code selector (or segment)
	push	ds
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,dx
	xchg	ax,[DD_LIST].SEG
	mov	es:[DDH_NEXT_SEG],ax
	sub	ax,ax
	xchg	ax,[DD_LIST].OFF
	mov	es:[DDH_NEXT_OFF],ax
	pop	ds
	ASSUME	DS:DOS
	mov	es,[dos_seg]
	ASSUME	ES:DOS
	mov	es:[dev_head].OFF,0	; keep dev_head in sync with DD_LIST
	mov	es:[dev_head].SEG,dx
	ASSUME	ES:NOTHING
	jmp	ld1
ENDPROC	load_devices

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; move_init
;
; Moves sysinit's code and data (everything from SI, rounded down to a
; paragraph, through DI, which includes the stack below sysinit_start) to a
; block that CPU$ allocates at the top of conventional memory, and returns
; selectors for it, with the same offsets.
;
; Inputs:
;	SI = offset of the start, DI = offset of the end
;	BP = address of the kernel (from devinit)
;	DS = kernel's data segment (or selector)
;
; Outputs:
;	AX = code selector (or segment), DX = data selector (or segment)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	DS:DOS
DEFPROC	move_init
	and	si,0FFF0h
	mov	[init_base],si
	mov	[dos_addr],bp
	sub	di,si
	mov	[init_len],di
	mov	[init_pkt].MV_LEN.LOW,di
	add	bp,si
	mov	[init_pkt].MV_SRC.LOW,bp
	adc	[init_pkt].MV_SRC.HIW,0
	push	si
	sub	si,si			; SI:DI = length
	mov	bx,MCBOWNER_SYSTEM
	mov	ax,(CPU_ALLOC SHL 8) OR MEMF_LOW OR MEMF_HIGH OR MEMF_NONE
	call	far ptr DDINT_CPU	; DX:CX = address
	ASSERT	NC
	mov	[init_addr].LOW,cx
	mov	[init_addr].HIW,dx
	mov	[init_pkt].MV_DST.LOW,cx
	mov	[init_pkt].MV_DST.HIW,dx
	push	ds
	pop	es
	mov	bx,offset init_pkt	; ES:BX -> MOVEPKT
	mov	ah,CPU_MOVE
	call	far ptr DDINT_CPU
	pop	si
	mov	cx,[init_addr].LOW
	mov	dx,[init_addr].HIW
	sub	cx,si
	sbb	dx,0			; DX:CX = address of offset 0
	mov	si,1
	sub	di,di			; SI:DI = 64K
	mov	ax,CPU_MAP SHL 8	; AL = 0 (a GDT data selector)
	call	far ptr DDINT_CPU	; AX = data selector
	ASSERT	NC
	mov	es,ax
	mov	es:[init_data],ax	; (in the new copy)
	push	ax
	xchg	bx,ax
	mov	ax,(CPU_ALIAS SHL 8) OR MEMF_CODE
	call	far ptr DDINT_CPU	; AX = code selector
	ASSERT	NC
	pop	dx
	ret
ENDPROC	move_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_total
;
; Records the total memory in mem_size (see DV_MEM_SIZE): the conventional
; memory in AX, plus all the memory that CPU$ describes above 1Mb.
;
; Inputs:
;	AX = Kb of conventional memory
;
; Modifies:
;	CX, DX
;
	ASSUME	DS:DOS
DEFPROC	mem_total
	push	ax
	push	bx
	push	si
	push	di
	push	es
	sub	sp,size PMB
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> PMB buffer
	xchg	si,ax			; SI = Kb so far
	sub	bx,bx			; BX = PMB #
mt1:	mov	ah,CPU_QUERY
	call	far ptr DDINT_CPU
	jc	mt9			; no more
	cmp	es:[di].PMB_ADDR.HIW,10h; is the block above 1Mb?
	jb	mt2			; no
	mov	ax,es:[di].PMB_LEN.LOW
	mov	dx,es:[di].PMB_LEN.HIW
	mov	cx,1024
	div	cx
	add	si,ax			; add its Kb
mt2:	inc	bx
	jmp	mt1
mt9:	mov	[mem_size],si
	add	sp,size PMB
	pop	es
	pop	di
	pop	si
	pop	bx
	pop	ax
	ret
ENDPROC	mem_total

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_size
;
; Changes the length of the kernel's block (from devinit) to BX bytes (ie,
; the offset where its tables end), or with BX = 0, to as much as possible,
; so that sysinit can build its tables after the kernel and then give the
; rest back.
;
; Inputs:
;	BX = length (or zero)
;
; Modifies:
;	AX
;
	ASSUME	DS:NOTHING
DEFPROC	dos_size
	push	cx
	push	dx
	push	si
	push	di
	mov	di,bx
	sub	si,si			; SI:DI = length
	test	bx,bx
	jnz	dz1
	dec	si			; (more than there could be)
dz1:	mov	cx,cs:[dos_addr]
	sub	dx,dx			; DX:CX = address of the kernel
	mov	ah,CPU_REALLOC
	call	far ptr DDINT_CPU
	jnc	dz9
	mov	si,dx
	mov	di,cx			; SI:DI = the longest it could be
	mov	cx,cs:[dos_addr]
	sub	dx,dx
	mov	ah,CPU_REALLOC
	call	far ptr DDINT_CPU
	ASSERT	NC
dz9:	pop	di
	pop	si
	pop	dx
	pop	cx
	ret
ENDPROC	dos_size

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; map_buf
;
; Returns a segment (or selector) for a disk buffer (a BUFHDR followed by a
; sector) from CPU$ (see CPU_MAP), so that the BUFHDR is at offset 0; with
; map_dos, the buffer is at offset AX in the kernel's block.
;
; Inputs:
;	CX = address of the buffer (in the first 64K), or AX = offset (map_dos)
;
; Outputs:
;	AX = segment (or selector)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	map_dos
	mov	cx,cs:[dos_addr]
	sub	dx,dx
	add	cx,ax
	adc	dx,dx			; DX:CX = address of the buffer
	jmp	short mb1
	DEFLBL	map_buf,near
	sub	dx,dx			; DX:CX = address of the buffer
mb1:	push	si
	push	di
	sub	si,si
	mov	di,size BUFHDR + 512	; SI:DI = length
	mov	ax,CPU_MAP SHL 8	; AL = 0 (a GDT data selector)
	call	far ptr DDINT_CPU	; AX = selector
	ASSERT	NC
	pop	di
	pop	si
	ret
ENDPROC	map_dos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_call5
;
; INT_DOSCALL5 * 4 holds a far jump to dos_call5 rather than a vector (a
; PSP's CALL 5 reaches it by wrapping around at 1Mb), so we store it through
; a segment (or selector) for the first 64K from CPU$ (see CPU_MAP), which we
; then give back (CPU_UNMAP).
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	set_call5
	push	bx
	push	si
	sub	cx,cx
	sub	dx,dx			; DX:CX = address 0
	mov	si,1
	sub	di,di			; SI:DI = 64K
	mov	ax,CPU_MAP SHL 8	; AL = 0 (a GDT data selector)
	call	far ptr DDINT_CPU	; AX = selector, CX = # of selectors
	ASSERT	NC
	mov	es,ax
	mov	di,INT_DOSCALL5 * 4
	mov	ax,offset dos_call5
	call	set_ddint
	mov	bx,es			; BX = selector to free
	push	ds
	pop	es			; (ES can't hold the selector we free)
	test	bx,bx			; protected mode?
	jz	sc9			; no (segment 0 needs no CPU_UNMAP)
	mov	ah,CPU_UNMAP
	call	far ptr DDINT_CPU
	ASSERT	NC
;
; In protected mode, a PSP's CALL 5 goes through the SEL_CALL5 call gate to
; the jump we just stored (see psp_setmem).
;
	ASSUME	DS:DOS
	mov	es,[dos_seg]
	ASSUME	ES:DOS
	mov	es:[call5_gate],SEL_CALL5
	ASSUME	DS:NOTHING, ES:NOTHING
sc9:	pop	si
	pop	bx
	ret
ENDPROC	set_call5

	DEFWORD	dos_addr,0		; kernel's address (see move_init)
init_pkt	MOVEPKT	<0,0,0>

CFG_DEVICE	db	7,"DEVICE="
VERB_FIND	db	"find",0
VERB_LOAD	db	"load",0

DOS	ends

	end
