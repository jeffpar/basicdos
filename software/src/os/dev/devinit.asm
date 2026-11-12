;
; BASIC-DOS Device Driver Initialization Code
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	disk.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc

DV_BUFLEN	equ	1024		; scratch buffer size (see DDPI_BUFPTR)
DV_ROOM		equ	FDC_BUFSECS * 512 ; how far we move up (see chk_cpu)
DV_SLACK	equ	32		; after DOS_FILE and CFG_FILE (see i9a)

DEV	segment para public 'CODE'

;
; Because this is the last module appended to DEV_FILE, we must include
; a fake device header, so that the BOOT code will stop looking for drivers.
; It must also be a DWORD, because the BOOT code assumes that our entry
; point is CS:0004.
;
	DEFWORD	EOD,-1
	db	OP_IRET,OP_NOP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Device driver initialization
;
; Entry:
;	DS = ES = 0
;	DI = end of drivers (which start at BIOS_END)
;	DS:SI -> boot BPB, followed by DEV_FILE, DOS_FILE, and CFG_FILE info
;	BX = offset of the boot code's read_file (in segment 0)
;
; Exit:
;	None (we have CPU$ move DOS_FILE after the drivers and "return" to
;	it, in either mode; see i9)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	devinit,far
;
; Runtime driver ASSERTs (and DBGBRKs) execute INT 3s that we don't want to
; crash (the original IBM PC did NOT initialize all the low interrupt vectors),
; so install a temporary INT_BP handler; sysinit will initialize it properly.
;
	IFDEF	DEBUG
	mov	word ptr ds:[INT_BP*4].OFF,offset devinit - 2
	mov	word ptr ds:[INT_BP*4].SEG,cs
	ENDIF	; DEBUG
;
; Perform some preliminary BIOS data initialization; in particular, stubs for
; the DDINT_ENTER and DDINT_LEAVE entry points for hardware interrupt
; handlers, the DDINT_UTIL entry point for driver WAIT and ENDWAIT requests,
; and the DDINT_CPU, DDINT_GETVEC, and DDINT_SETVEC entry points, which CPU$
; sets when it initializes (or switches to protected mode), before any other
; driver initializes and reads or writes an interrupt vector.
;
	push	ds
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,(OP_RETF SHL 8) OR OP_STC
	mov	word ptr ds:[DDINT_ENTER],ax
	mov	byte ptr ds:[DDINT_LEAVE],OP_IRET
	mov	word ptr ds:[DDINT_UTIL],ax
	mov	word ptr ds:[DDINT_CPU],ax
	mov	word ptr ds:[DDINT_GETVEC],ax
	mov	word ptr ds:[DDINT_SETVEC],ax
	sub	ax,ax
	mov	[FDC_DEVICE].SEG,ax	; no FDC driver yet
	mov	[CLOCK_DEVICE].SEG,ax	; and no CLOCK$ driver yet
	mov	[FDC_UNITS],al
	mov	[HDC_UNITS],al		; and no HDC volumes yet
	pop	ds
	ASSUME	DS:NOTHING
;
; To honor any "SKIP=" line, we need CFG_FILE now, so we load it just beyond
; this code, using the boot code's read_file function; once CPU$ is loaded,
; we copy it to the end of DOS_FILE (see chk_cpu), for sysinit.  Drivers also
; get the CFG_FILE data (see DDP_PTR below), which is empty if there's no
; CFG_FILE.
;
	push	di
	push	cs
	pop	es
	ASSUME	ES:DEV			; (read_file preserves ES)
	mov	es:[rd_addr],bx		; (see rd_file)
	mov	es:[dv_data],cs		; our data segment (see chk_cpu)
	mov	es:[dv_addr],di		; and our address (end of drivers)
	mov	di,offset devinit_end	; DI -> CFG_FILE buffer
	lea	bx,[si+BOOT_CFGFILE]	; BX -> CFG_FILE DIR info
	mov	es:[cfg_info],bx
	cmp	byte ptr [bx],0		; was CFG_FILE found?
	jne	d1			; no, so leave it empty
	call	rd_file
d1:	mov	byte ptr es:[di],0	; null-terminate the CFG_FILE data
	mov	ax,di
	sub	ax,offset devinit_end
	mov	es:[cfg_size],ax
	inc	di
	mov	si,offset devinit_end	; look for "SKIP=" at the start of a line
d1a:	cmp	word ptr cs:[si],'KS'
	jne	d1b
	cmp	word ptr cs:[si+2],'PI'
	jne	d1b
	cmp	byte ptr cs:[si+4],'='
	jne	d1b
	add	si,5
	mov	es:[skip_list],si	; CS:SI -> list of driver names
	jmp	short d2
d1b:	lods	byte ptr cs:[si]
	test	al,al			; end of CFG_FILE data?
	jz	d2			; yes
	cmp	al,CHR_LINEFEED
	jne	d1b
	jmp	d1a
d2:	mov	es:[buf_off],di		; scratch buffer follows CFG_FILE data
	pop	di			; DI = end of drivers again
	push	ds
	pop	es
	ASSUME	ES:NOTHING
;
; Initialize each device driver.
;
	mov	si,offset BIOS_END + BIOS_DATA
					; DS:SI -> first driver
;
; Create a DDPI packet on the stack.
;
	sub	sp,DDP_MAXSIZE
	mov	bp,sp
	DBGINIT	STRUCT,[bp],DDP
	mov	word ptr [bp].DDP_LEN,size DDP
	mov	[bp].DDP_CMD,DDC_INIT
	mov	[bp].DDP_STATUS,0
	mov	[bp].DDP_PTR.OFF,offset devinit_end
	mov	[bp].DDP_PTR.SEG,cs	; DDP_PTR -> CFG_FILE data

i1:	cmp	si,di		; reached the end of drivers?
	jb	i2		; no
	jmp	i9		; yes
i2:	call	chk_cpu		; claim our memory once CPU$ is loaded
	mov	[bp].DDPI_END.OFF,0
;
; Memory beyond the end of this code (and our copy of CFG_FILE) is free until
; we return, so it serves as a scratch buffer for any driver that needs one
; (eg, to read a hard disk's MBR).  Note that the end of all the drivers (DI)
; is where this code begins.
;
	mov	cx,cs:[buf_off]
	mov	[bp].DDPI_BUFPTR.OFF,cx
	push	cs:[dv_data]
	pop	[bp].DDPI_BUFPTR.SEG
;
; A driver that's skipped gets no selectors; any other gets a code selector
; and a data selector (or its segment), which fit_sels fits to whatever the
; driver keeps (or frees, if it keeps nothing) when its INIT returns.
;
	call	chk_skip	; is this driver on the SKIP list?
	mov	ax,0
	cwd			; AX = DX = 0 (no selectors)
	jc	i2s		; yes (and DDPI_END is zero)
	call	get_sels	; AX = code selector, DX = data selector
	mov	[si].DDH_DATA,dx	; the driver's data segment/selector
	mov	[bp].DDPI_END.SEG,dx
i2s:	push	dx		; save the data selector
	push	ax		; and the code selector (or segment)
	mov	dx,[si]		; DX = original size of this driver
	test	ax,ax		; was it skipped?
	jz	i2a		; yes
	push	ss
	pop	es
	ASSUME	ES:NOTHING
	mov	bx,bp		; ES:BX -> packet
	push	[si].DDH_REQUEST
;
; Just as in dev_request, we no longer force drivers to preserve all registers.
;
	push	dx
	push	si
	push	di
	push	bp
	push	ds
	DEFLBL	dv_init,near	; (a breakpoint here precedes each INIT)
	call	dword ptr [bp-6]; far call to DDH_REQUEST

	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	ax		; toss DDH_REQUEST address

i2a:	mov	bx,[bp].DDPI_END.OFF
	add	bx,15
	and	bx,0FFF0h
;
; Whereas SI was the original (paragraph-aligned) address of the driver,
; and SI+DX was the end of the driver, SI+BX is the new end of driver. So,
; if DX == BX, there's nothing to move; otherwise, we have CPU$ move
; everything from SI+DX through DI to SI+BX (CPU_MOVE handles overlap, in
; case the driver *increased* its footprint), and update DX and DI (new end
; of drivers).
;
	cmp	dx,bx
	je	i4
	push	bx
	mov	es,cs:[dv_data]
	ASSUME	ES:DEV
	lea	ax,[si+bx]
	mov	es:[mv_pkt].MV_DST.LOW,ax
	add	dx,si
	mov	es:[mv_pkt].MV_SRC.LOW,dx
	sub	di,dx
	mov	es:[mv_pkt].MV_LEN.LOW,di
	add	di,ax			; DI = new end of drivers
	mov	bx,offset mv_pkt	; ES:BX -> MOVEPKT
	mov	ah,CPU_MOVE
	call	far ptr DDINT_CPU
	ASSUME	ES:NOTHING
	jnc	i3
;
; If CPU$ isn't loaded yet, the first driver (the 80386 CPU$) just unloaded
; itself, and the 8086 CPU$ is next, so we move the drivers down ourselves;
; this is the only memory we move without CPU$.
;
	push	si
	push	di
	mov	si,cs:[mv_pkt].MV_SRC.LOW
	mov	di,cs:[mv_pkt].MV_DST.LOW
	mov	cx,cs:[mv_pkt].MV_LEN.LOW
	push	ds
	pop	es
	rep	movsb			; (moving down, so forward is fine)
	pop	di
	pop	si
i3:	pop	bx
	mov	dx,bx

i4:	pop	ax		; recover the driver's code selector
	pop	bx		; and its data selector
	call	fit_sels
	test	dx,dx
	jz	i8		; jump if driver not required
	mov	cx,BIOS
	mov	es,cx
	ASSUME	ES:BIOS
	sub	cx,cx		; AX:CX -> driver header
;
; If this is the FDC driver (ie, the first block device), then we need to
; extract DDPI_UNITS from the request packet and update FDC_UNITS and
; FDC_DEVICE in the BIOS segment.  Similarly, the HDC driver (ie, the next
; block device) updates HDC_UNITS and HDC_SEG.
;
	test	[si].DDH_ATTR,DDATTR_CHAR
	jnz	i7
	push	ax
	cmp	[FDC_DEVICE].SEG,0	; FDC driver already found?
	jne	i5			; yes
	mov	[FDC_DEVICE].OFF,cx
	mov	[FDC_DEVICE].SEG,ax
	mov	al,[bp].DDPI_UNITS
	mov	[FDC_UNITS],al
	jmp	short i6
i5:	mov	[HDC_SEG],ax
	mov	al,[bp].DDPI_UNITS
	mov	[HDC_UNITS],al
i6:	pop	ax
;
; Link the driver into the chain.  I originally chained them in reverse:
;
;	xchg	[DD_LIST].OFF,cx
;	mov	[si].DDH_NEXT_OFF,cx
;	xchg	[DD_LIST].SEG,ax
;	mov	[si].DDH_NEXT_SEG,ax
;
; because it's simpler, but later decided to keep the list in memory order.
;
i7:	test	[si].DDH_ATTR,DDATTR_CLOCK
	jz	i7c
	mov	[CLOCK_DEVICE].OFF,cx	; record the CLOCK$ driver (see CLKX)
	mov	[CLOCK_DEVICE].SEG,ax
i7c:	push	di
	lea	di,[DD_LIST]
i7a:	cmp	es:[di].DDH_NEXT_OFF,-1
	je	i7b
	les	di,es:[di]
	mov	es,es:[di].DDH_DATA	; (so that we can update the link)
	jmp	i7a
i7b:	mov	es:[di].DDH_NEXT_OFF,cx
	mov	es:[di].DDH_NEXT_SEG,ax
	mov	[si].DDH_NEXT_OFF,-1
	pop	di

i8:	add	si,dx		; SI -> next driver, after adding original size
	jmp	i1

i9:	add	sp,DDP_MAXSIZE
;
; Every driver is initialized, and they end at DI.  We shrink the drivers'
; block to fit them, free our own block and the block we loaded DOS_FILE into
; (see chk_cpu), and allocate DOS_FILE's new home, which is the first free
; block, right after the drivers.
;
; That home overlaps our block, and the 8086 CPU$ puts a free MCB at the end of
; it, so the block must reach devinit_end at least, or that MCB could land on
; code or data we still need.  We allocate that much first, to learn the
; block's address, and then lengthen it to hold DOS_FILE (see i9a).
;
	mov	ax,cs:[dv_addr]
	add	ax,offset devinit_end
	sub	ax,di
	push	ax			; AX = length through devinit_end
	mov	cx,cs:[drv_addr]
	sub	di,cx			; DI = length of the drivers
	mov	ah,CPU_REALLOC
	call	cpu_blk
	mov	cx,cs:[dv_addr]
	mov	ah,CPU_FREE
	call	cpu_blk
	mov	cx,cs:[dos_pkt].MV_SRC.LOW
	mov	dx,cs:[dos_pkt].MV_SRC.HIW
	mov	ah,CPU_FREE
	call	cpu_chk
	pop	di			; DI = length through devinit_end
	mov	ax,(CPU_ALLOC SHL 8) OR MEMF_LOW OR MEMF_NONE
	call	cpu_blk			; DX:CX = address (in the first 64K)
;
; With little memory (eg, 64K), DOS_FILE's new home overlaps the block we
; loaded it into, and a free MCB at the end of its home would land inside the
; data we're about to move, and be moved with it.  So if the two overlap (or
; nearly do), the home extends past the end of that data instead, where the
; MCB lands in the slack that chk_cpu left; sysinit resizes the block before
; it needs the memory (see dos_size).
;
	mov	bx,cs:[dos_pkt].MV_LEN.LOW
	mov	ax,cs:[dos_pkt].MV_SRC.LOW
	mov	dx,cs:[dos_pkt].MV_SRC.HIW
	sub	ax,cx
	sbb	dx,0			; DX:AX = how far DOS_FILE moves
	jnz	i9a			; too far to overlap
	lea	si,[bx+DV_SLACK]
	cmp	ax,si			; does the MCB land before the data?
	jae	i9a			; yes
	add	bx,ax			; no, so BX = length through the data
i9a:	cmp	bx,di			; is the block long enough already?
	jbe	i9b			; yes
	mov	di,bx
	push	cx
	mov	ah,CPU_REALLOC
	call	cpu_blk
	pop	cx			; CX = address of the block again
i9b:	mov	es,cs:[dv_data]
	ASSUME	ES:DEV
	mov	es:[dos_pkt].MV_DST.LOW,cx
	mov	si,cx
	push	si			; address of DOS_FILE
	call	get_sels		; AX = code selector, DX = data
;
; Then we push sysinit's inputs (see sysinit, which also gets DOS_FILE's
; address, pushed above) and its entry point, and jump to CPU_MOVE, so that
; CPU$ moves DOS_FILE (over this code) and "returns" to it.
;
	mov	bx,cs:[cfg_info]
	sub	bx,BOOT_CFGFILE
	push	bx			; offset of the BPB
	push	cs:[cfg_size]		; size of CFG_FILE data
	push	dx			; DOS_FILE's data selector
	push	cs:[dos_end]		; offset of CFG_FILE data
	push	ax
	mov	ax,2			; (skip DOS_FILE's fake INT 20h)
	push	ax			; far "return" address -> DOS_FILE
	mov	bx,offset dos_pkt	; ES:BX -> MOVEPKT
	mov	ah,CPU_MOVE
	DEFLBL	dv_jump,near		; (a breakpoint here precedes sysinit)
	jmp	far ptr DDINT_CPU
ENDPROC	devinit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_cpu
;
; Once CPU$ has initialized, it manages all memory, so we claim what we're
; using: a block for the drivers that remain (SI through DI), and a block for
; our code, CFG_FILE data, and scratch buffer.  Then, while we're still in
; real mode and can use the boot code's read_file, we load DOS_FILE into a
; block at the top of conventional memory, followed by a copy of the CFG_FILE
; data, for sysinit (see i9).
;
; If protected mode is available, the FDC driver will grow by up to a track
; (see ddfdc_init), moving the drivers after it up, so we move up first, and
; include the room in the drivers' block (which i9 shrinks to fit).  If not,
; the 80386 CPU$ unloaded itself and the drivers after it moved down, so we
; move down to the end of the drivers (plus a paragraph for our MCB), rather
; than leave a gap below us.
;
; Finally, if protected mode is available, we switch to it for good (see
; CPU_PMODE): our CS, DS, ES, and SS become selectors, and we give the link to
; each driver initialized so far (ie, CPU$) one, too; the rest get selectors
; as they're initialized (see get_sels).  In real mode, they're relinked the
; same way, with their own segments.
;
; Inputs:
;	DS = ES = SS = the first 64K
;	DS:SI -> next driver, DI = end of drivers
;	SS:BP -> DDPI
;
; Modifies:
;	AX, BX, CX, DX, ES
;
DEFPROC	chk_cpu
	cmp	cs:[drv_addr],0		; did we claim our memory already?
	jne	cu0			; yes
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU	; AH = CPUF_* flags
	jnc	cu1			; CPU$ is loaded
cu0:	ret
cu1:	push	si
	push	di
	push	ax
	push	bp
	push	cs
	pop	es
	ASSUME	ES:DEV
	mov	es:[drv_addr],si
	test	ah,CPUF_PMOK		; is protected mode available?
	jz	cu1b			; no
	add	di,DV_ROOM		; yes, so the drivers need more room
cu1b:	mov	cx,es:[dv_addr]
	mov	es:[mv_pkt].MV_SRC.LOW,cx
	lea	cx,[di+16]		; (the 8086 CPU$ puts our MCB at DI)
	mov	es:[mv_pkt].MV_DST.LOW,cx
	mov	es:[dv_addr],cx		; (the copy has our new address)
	mov	cx,es:[buf_off]		; CX = our code and CFG_FILE length
	mov	es:[mv_pkt].MV_LEN.LOW,cx
	mov	bx,offset mv_pkt	; ES:BX -> MOVEPKT
	mov	ah,CPU_MOVE
	call	cpu_chk
	mov	ax,es:[dv_addr]
	mov	cl,4
	shr	ax,cl
	push	ax
	mov	ax,offset cu1a
	push	ax
	db	OP_RETF			; continue with the copy
cu1a:	push	cs
	pop	es
	mov	es:[dv_data],cs		; (protected mode replaces these two)
	mov	[bp].DDP_PTR.SEG,cs
	mov	cx,si
	sub	di,si			; DI = length of the drivers left
	call	claim
	mov	cx,es:[dv_addr]
	mov	di,es:[buf_off]
	add	di,DV_BUFLEN		; DI = length of our block
	call	claim
	mov	si,es:[cfg_info]
	lea	bx,[si-(size DIR_NAME)]	; DS:BX -> DOS_FILE DIR info
	sub	si,BOOT_CFGFILE		; DS:SI -> BPB
	mov	al,[si].BPB_CLUSSECS
	mov	ah,0
	mul	[si].BPB_SECBYTES
	dec	ax			; AX = bytes per cluster - 1
	mov	di,[bx+4]
	add	di,ax
	not	ax
	and	di,ax			; DI = DOS_FILE size, in whole clusters
	add	di,es:[cfg_size]	; plus CFG_FILE data
	add	di,DV_SLACK		; and room for a free MCB (see i9a)
	push	bx
	push	si
	sub	si,si			; SI:DI = length
	mov	bx,MCBOWNER_SYSTEM
	mov	ax,(CPU_ALLOC SHL 8) OR MEMF_LOW OR MEMF_HIGH
	call	cpu_chk			; AX = segment, DX:CX = address
	mov	es:[dos_pkt].MV_SRC.LOW,cx
	mov	es:[dos_pkt].MV_SRC.HIW,dx
	pop	si
	pop	bx
	mov	es,ax
	ASSUME	ES:NOTHING
	sub	di,di			; ES:DI -> DOS_FILE's block
	call	rd_file			; ES:DI -> end of DOS_FILE
	mov	dx,di
	mov	si,offset devinit_end
	mov	cx,cs:[cfg_size]
	push	ds
	push	cs
	pop	ds
	rep	movsb			; copy CFG_FILE data after it
	pop	ds
	push	cs
	pop	es
	ASSUME	ES:DEV
	mov	es:[dos_end],dx
	mov	es:[dos_pkt].MV_LEN.LOW,di
	pop	bp
	pop	ax			; AH = CPUF_* flags
	test	ah,CPUF_PMOK		; is protected mode available?
	jz	cu5			; no
	push	ds
	pop	es
	ASSUME	ES:NOTHING
	mov	ah,CPU_PMODE
	call	far ptr DDINT_CPU	; AX = data selector for our CS
;
; The 80386 CPU$ stays only if it can switch to protected mode, and it fills
; DDINT_GETVEC and DDINT_SETVEC only when it does, so a failure is fatal.
;
	jc	$			; halt
	mov	es,ax
	ASSUME	ES:DEV
	mov	es:[dv_data],ax
	mov	[bp].DDP_PTR.SEG,ax	; DDP_PTR -> CFG_FILE data
;
; The only driver initialized so far is CPU$ (see get_sels), so we relink it.
;
cu5:	mov	si,offset BIOS_END + BIOS_DATA
	call	get_sels		; AX = code selector, DX = data
	mov	[si].DDH_DATA,dx
	mov	bx,dx
	mov	dx,cs:[drv_addr]
	sub	dx,si			; DX = length of CPU$ (ie, up to us)
	call	fit_sels
	mov	dx,BIOS
	mov	es,dx
	ASSUME	ES:BIOS
	mov	es:[DD_LIST].SEG,ax
	pop	di
	pop	si
	ret
ENDPROC	chk_cpu

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_sels
;
; Returns a code selector and a data selector (with 64K limits) for a driver
; (or DOS_FILE) at the given address, from CPU$ (see CPU_MAP and CPU_ALIAS);
; in real mode, they're its segment.  Until CPU$ is loaded, the only driver
; is CPU$ itself, at BIOS_END, so we return its segment.
;
; Inputs:
;	SI = address (a multiple of 16, in the first 64K)
;
; Outputs:
;	AX = code selector (or segment), DX = data selector (or segment)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	get_sels
	mov	ax,(BIOS_END - RS232_BASE + BIOS_DATA) SHR 4
	mov	dx,ax
	cmp	cs:[drv_addr],0		; is CPU$ loaded yet?
	jne	gs1			; yes
	ASSERT	Z,<cmp si,offset BIOS_END + BIOS_DATA>
	ret
gs1:	push	bx
	push	si
	push	di
	mov	cx,si
	sub	dx,dx			; DX:CX = address
	mov	si,1
	sub	di,di			; SI:DI = 64K
	mov	ax,CPU_MAP SHL 8	; AL = 0 (a GDT data selector)
	call	cpu_chk			; AX = data selector
	push	ax
	xchg	bx,ax
	mov	ax,(CPU_ALIAS SHL 8) OR MEMF_CODE
	call	cpu_chk			; AX = code selector
	pop	dx
	pop	di
	pop	si
	pop	bx
	ret
ENDPROC	get_sels

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fit_sels
;
; Fits the selectors that get_sels returned for a driver to the length that
; it keeps (CPU_SETLIM), or frees them if it keeps nothing (CPU_UNMAP); in
; real mode, CPU$ has nothing to do.  Until CPU$ is loaded, the only driver
; is CPU$ itself, whose selectors chk_cpu fits.
;
; Inputs:
;	AX = code selector (zero if none), BX = data selector, DX = length
;
; Modifies:
;	BX, CX
;
DEFPROC	fit_sels
	test	ax,ax			; any selectors?
	jz	fs9			; no
	cmp	cs:[drv_addr],0		; is CPU$ loaded yet?
	je	fs9			; no
	push	ax
	push	dx
	push	si
	push	di
	push	bx			; save the data selector
	xchg	bx,ax			; BX = code selector
	mov	di,dx
	sub	si,si			; SI:DI = length
	sub	cx,cx			; CX = 0 (one selector, for CPU_UNMAP)
	mov	ah,CPU_SETLIM
	test	di,di			; does the driver keep anything?
	jnz	fs1			; yes
	mov	ah,CPU_UNMAP		; no, so free its selectors
fs1:	push	ax
	call	cpu_chk			; the code selector
	pop	ax
	pop	bx			; and the data selector
	sub	cx,cx
	call	cpu_chk
	pop	di
	pop	si
	pop	dx
	pop	ax
fs9:	ret
ENDPROC	fit_sels

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; claim, cpu_blk, and cpu_chk
;
; claim allocates the block at CX (in the first 64K) of length DI from CPU$,
; for the system; cpu_blk calls CPU$ function AH with that block, and cpu_chk
; calls CPU$ function AH with any inputs.  Failures shouldn't happen, but an
; INT 3 stops the machine in protected mode (see cpu_fatal).
;
; Outputs:
;	As for the CPU$ function (see cpu.inc)
;
; Modifies:
;	AX, BX, CX, DX, SI (except cpu_chk), DI (as for the CPU$ function)
;
DEFPROC	claim
	mov	ax,(CPU_ALLOC SHL 8) OR MEMF_AT OR MEMF_NONE
	DEFLBL	cpu_blk,near
	sub	dx,dx			; DX:CX = address
	sub	si,si			; SI:DI = length
	mov	bx,MCBOWNER_SYSTEM	; BX = owner (for CPU_ALLOC)
	DEFLBL	cpu_chk,near
	call	far ptr DDINT_CPU
	jnc	cm9
	int	3
cm9:	ret
ENDPROC	claim

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; rd_file
;
; "Calls" the boot code's read_file, in segment 0, which returns with a near
; RET, so we give it a near return address that holds a RETF (the second
; byte of DDINT_ENTER's stub).
;
; Inputs:
;	DS:BX -> file's DIR info, DS:SI -> BPB (DS = 0), ES:DI -> buffer
;
; Outputs:
;	ES:DI -> end of the file's data
;
; Modifies:
;	AX, CX, DX, BP, DI
;
DEFPROC	rd_file
	push	cs
	mov	ax,offset rf9
	push	ax			; far return address -> rf9
	mov	ax,offset DDINT_ENTER + 1 + DDINT_BIAS + BIOS_DATA
	push	ax			; near return address -> RETF
	push	ds			; DS = segment of boot code (zero)
	push	cs:[rd_addr]
	db	OP_RETF			; "call" read_file
rf9:	ret
ENDPROC	rd_file

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_skip
;
; Checks the driver's name against the "SKIP=" list (eg, "SKIP=VKD$,FPU$"),
; which is a list of driver names separated by commas.
;
; Inputs:
;	DS:SI -> driver header
;
; Outputs:
;	Carry set if the driver should be skipped, clear if not
;
; Modifies:
;	AX, BX, CX
;
DEFPROC	chk_skip
	push	di
	mov	di,cs:[skip_list]	; CS:DI -> list of names (zero if none)
	test	di,di
	jz	ck9			; no list (and carry is clear)
;
; CPU$ (either of them) manages memory, so it can't be skipped.
;
	cmp	word ptr [si].DDH_NAME,'PC'
	jne	ck1
	cmp	word ptr [si].DDH_NAME+2,'$U'
	je	ck9			; (and carry is clear)
ck1:	push	si
	add	si,DDH_NAME		; DS:SI -> driver name
	mov	cx,size DDH_NAME
	mov	bl,0			; BL is zero as long as the names match
ck2:	mov	al,cs:[di]
	cmp	al,','
	je	ck4			; end of name
	cmp	al,' '
	jbe	ck4			; end of list (eg, space, CR, or null)
	inc	di
	jcxz	ck3			; listed name is too long
	dec	cx
	cmp	al,[si]
	je	ck2a
ck3:	mov	bl,1			; names don't match
ck2a:	inc	si
	jmp	ck2
ck4:	jcxz	ck5
ck4a:	cmp	byte ptr [si],' '	; rest of driver name must be blank
	je	ck4b
	mov	bl,1
ck4b:	inc	si
	loop	ck4a
ck5:	pop	si
	cmp	bl,1			; carry set if BL is zero (a match)
	jb	ck9
	inc	di			; skip the delimiter
	cmp	al,','			; more names?
	je	ck1			; yes
	clc
ck9:	pop	di
	ret
ENDPROC	chk_skip

	DEFWORD	skip_list,0		; offset of "SKIP=" list, if any
	DEFWORD	buf_off,0		; offset of scratch buffer
	DEFWORD	cfg_info,0		; offset of CFG_FILE DIR info
	DEFWORD	cfg_size,0		; size of CFG_FILE (zero if none)
	DEFWORD	rd_addr,0		; offset of read_file (see rd_file)
	DEFWORD	dv_addr,0		; our address
	DEFWORD	dv_data,0		; our data segment (or selector)
	DEFWORD	drv_addr,0		; drivers' block (see chk_cpu)
	DEFWORD	dos_end,0		; offset of the end of DOS_FILE

mv_pkt	MOVEPKT	<0,0,0>			; for moving drivers
dos_pkt	MOVEPKT	<0,0,0>			; for moving DOS_FILE (see i9)

devinit_end	label	byte

DEV	ends

	end
