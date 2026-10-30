;
; BASIC-DOS System Initialization
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	disk.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc
	include	version.inc

DOS	segment word public 'CODE'

	EXTBYTE	<bpb_total,sfh_debug,def_drive,def_swchar,def_pathchar>
	EXTBYTE	<scb_locked>
	EXTWORD	<mcb_head,mcb_limit,buf_head,key_boot,scb_active,ivt_save>
	EXTWORD	<err_stack>
	EXTLONG	<bpb_table,scb_table,sfb_table,cdir_table,clk_ptr,fpu_table>
	EXTLONG	<dev_head>
	EXTNEAR	<find_cfg,init_table,set_bpbtime,load_devices,sysinit_end>
	EXTNEAR	<move_init,dos_size,init_free>
	EXTNEAR	<open_dev,open_warning,open_error>
	EXTERNS	<cache_int21>,far
	EXTNEAR	<dos_dverr,dos_sstep,dos_brkpt,dos_oferr>
	EXTNEAR	<dos_term,dos_func,dos_exit,dos_ctrlc,dos_error,dos_default>
	EXTNEAR	<dos_fastcon>
	EXTNEAR	<disk_read,disk_write,dos_tsr,dos_call5,dos_util,dos_leave>
	EXTNEAR	<int_enter,int_leave,int_util,int_getvec,int_setvec>

	DEFLBL	sysinit_start

	ASSUME	CS:DOS, DS:NOTHING, ES:DOS, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; System initialization
;
; Everything after "sysinit_start" will be recycled.
;
; Entry:
;	Stack (from the top): offset of CFG_FILE data (if any), our data
;	segment, size of CFG_FILE data (if any), offset of initial BPB (in
;	segment 0), and our address; DEVINIT pushes them before having CPU$
;	move us after the drivers, which then "returns" here (see devinit's i9)
;
DEFPROC	sysinit,far
	pop	bx			; ES:BX -> CFG_FILE data
	pop	es
	pop	dx			; DX = size of CFG_FILE data
	pop	ax			; AX = offset of initial BPB
	pop	bp			; BP = our address (see move_init)
	sub	ax,BIOS_DATA
	mov	es:[bpb_off],ax		; save boot BPB (BIOS offset)
	mov	ax,cs
	mov	es:[dos_seg],ax		; save the resident DOS segment
	mov	es:[cfg_size],dx	; size of CFG data
;
; The CFG data follows our image (see devinit's chk_cpu), and we copy it to
; sysinit_end, so that it's relocated along with us.
;
; To simplify use of the CFG data, replace CRs and LFs with nulls (so that
; every value is null-terminated, even if lines end with only LFs); find_cfg
; uses the nulls to find the next line.  We use "$" jumps here to save symbols.
;
	mov	si,bx
	mov	di,offset sysinit_end
	mov	es:[cfg_data],di	; offset of CFG data
	mov	cx,dx
	jcxz	si1
si0:	lods	byte ptr es:[si]
	cmp	al,0Dh
	je	$+6			; replace CR
	cmp	al,0Ah
	jne	$+4			; leave everything else (except LF)
	mov	al,0
	stosb
	loop	si0
;
; Move all the init code/data out of the way, to the top of available memory
; (see move_init), along with 512 bytes below it for our stack.
;
; MEMORY_SIZE is in Kb (2^10 units), and mcb_limit is in paragraphs (2^4
; units), so shift left 6 bits.
;
si1:	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,[MEMORY_SIZE]	; get available memory in Kb
	mov	cl,6
	shl	ax,cl			; available memory in paras
	mov	[mcb_limit],ax
	push	es
	pop	ds
	ASSUME	DS:DOS
	mov	si,offset sysinit_start - 200h
	call	move_init		; AX = code selector, DX = data
	push	ax
	mov	ax,offset sysinit_high
	push	ax
	ret
;
; Initialize all the DOS vectors.  DS is dos_seg; set ES to BIOS.
;
	EVEN
	DEFLBL	sysinit_high,near
;
; This is also a good time (actually, a long overdue time) to switch off
; of whatever stack the BIOS set up for booting (the IBM PC uses 30h:100h).
; There just weren't any particularly known good safe places, until now.
;
	cli				; guard against early 8088 errata
	mov	ss,dx			; use the space below the sysinit code
	mov	sp,offset sysinit_start
	sti
;
; "Revector" DDINT_GETVEC and DDINT_SETVEC to int_getvec and int_setvec
; (DEVINIT's versions are gone), and then use them to initialize all the DOS
; vectors.
;
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	mov	di,offset DDINT_GETVEC + DDINT_BIAS
	mov	ax,offset int_getvec
	call	sto_jmpf
	mov	ax,offset int_setvec
	call	sto_jmpf		; (DDINT_SETVEC follows DDINT_GETVEC)
	mov	si,offset INT_TABLES
si2:	lodsw
	test	ax,ax			; any more tables?
	jl	si2b			; no
	xchg	bx,ax			; BL = first vector of the table
si2a:	lodsw				; AX = offset of the next handler
	test	ax,ax			; end of the table?
	jz	si2			; yes
	xchg	cx,ax
	mov	dx,ds			; DX:CX -> handler
	mov	al,bl
	call	far ptr DDINT_SETVEC
	inc	bx
	jmp	si2a
;
; INT_DOSCALL5 * 4 holds a far jump rather than a vector (a PSP's CALL 5
; reaches it by wrapping around at 1Mb), so it's stored directly.
;
si2b:	sub	ax,ax
	mov	es,ax
	ASSUME	ES:NOTHING
	mov	di,INT_DOSCALL5 * 4
	mov	ax,offset dos_call5
	call	sto_jmpf
	mov	al,INT_DOSUTIL
	mov	cx,offset dos_util
	mov	dx,ds
	call	far ptr DDINT_SETVEC
;
; Unless a driver (eg, VKD$) has installed an INT 29h handler (ie, one in RAM),
; point INT 29h at dos_fastcon, so that write_handle's fallback never calls a
; null vector (or a BIOS stub) when there's no valid handle (eg, here).
;
	mov	al,INT_FASTCON
	call	far ptr DDINT_GETVEC	; DX:CX = INT 29h vector
	dec	dx
	cmp	dx,0A000h-1		; is the vector in RAM (1h-9FFFh)?
	jb	si2c			; yes, so leave it alone
	mov	cx,offset dos_fastcon
	mov	dx,ds
	call	far ptr DDINT_SETVEC
;
; Unless a mouse driver has installed an INT 33h handler (ie, one in RAM;
; see ddmou_init), point INT 33h at an IRET, because programs like WOLF3D.EXE
; treat any other non-null vector (eg, a BIOS stub) as a mouse driver.
;
si2c:	mov	al,INT_MOUSE
	call	far ptr DDINT_GETVEC	; DX:CX = INT 33h vector
	dec	dx
	cmp	dx,0A000h-1		; is the vector in RAM (1h-9FFFh)?
	jb	si2d			; yes, so leave it alone
	mov	cx,offset dos_default
	mov	dx,ds
	call	far ptr DDINT_SETVEC
;
; "Revector" DDINT_UTIL to int_util as soon as INT_DOSUTIL is available,
; since drivers use it in place of some DOSUTIL functions (eg, LOCK, which
; VKD$'s INT 10h handler uses).
;
si2d:	cli
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	mov	di,offset DDINT_UTIL + DDINT_BIAS
	mov	ax,offset int_util
	call	sto_jmpf
	sti
;
; The current SP is sysinit_start, and relative to SS, that's safe place
; for our stack, whereas relative to DS, it's the start of DOS table space,
; and while the SCBs will be our first table, we have to temporarily set
; scb_active to that same region, so that any DOS or DOSUTIL calls we make
; will not barf due to the lack of an active SCB.  That region still holds
; the original copy of this init code, so zero it first (eg, SCB_INDOS must
; start at zero).
;
	push	es
	push	ds
	pop	es
	ASSUME	ES:DOS
	mov	di,sp
	mov	cx,size SCB
	mov	al,0
	rep	stosb
	pop	es
	ASSUME	ES:BIOS
	mov	bx,sp
	DBGINIT	STRUCT,[bx],SCB
	mov	[scb_active],bx		; set temporary SCB
;
; The path character defaults to '\' and the switch character to '/', but
; PATHCHAR=/ changes the path character to '/' and therefore the switch
; character to '-', so that they never conflict.  Any other setting (which
; should be PATHCHAR=\, the default) is ignored.  SWITCHAR is checked later,
; once a console is open for reporting a conflict.
;
	mov	si,offset CFG_PATHCHAR
	call	find_cfg		; look for "PATHCHAR="
	jc	si3
	cmp	byte ptr [di],'/'	; PATHCHAR=/?
	jne	si3			; no (def_pathchar follows def_swchar)
	mov	word ptr [def_swchar],'-' OR ('/' SHL 8)
;
; Copy DD_LIST from the BIOS segment to dev_head in the DOS segment, for
; DOS_MSC_GETVARS (see DV_DD_LIST), since all the device drivers are linked
; by now, and BOOT_KEY to key_boot.
;
si3:	mov	ax,[DD_LIST].OFF	; copy the device driver list head
	mov	[dev_head].OFF,ax
	mov	ax,[DD_LIST].SEG
	mov	[dev_head].SEG,ax
	mov	ax,[BOOT_KEY]		; copy the boot key
	cmp	al,CHR_RETURN		; unless it's just a RETURN
	je	si3a
	mov	[key_boot],ax
;
; For ease of configuration testing, allow MEMSIZE (eg, MEMSIZE=32) to set a
; new memory limit (Kb), assuming we have at least as much memory as specified.
;
si3a:	mov	si,offset CFG_MEMSIZE
	call	find_cfg		; look for "MEMSIZE="
	jc	si4
	xchg	si,di
	push	cs
	pop	es
	ASSUME	ES:NOTHING		; ES:DI -> validation data
	mov	bl,10			; BL = base 10
	DOSUTIL	ATOI16			; DS:SI -> string
	jc	si4			; AX = value
	push	cx
	mov	cl,6
	shl	ax,cl
	pop	cx
	cmp	ax,[mcb_limit]		; is MEMSIZE too large?
	jae	si4			; yes
	mov	[mcb_limit],ax
;
; Now grow the kernel's block (see dos_size) as much as possible, and set ES
; to the first available paragraph for resident DOS tables.
;
si4:	sub	bx,bx
	call	dos_size
	mov	ax,sp
	ASSERT	Z,<cmp ax,offset sysinit_start>
	add	ax,15
	mov	cl,4
	shr	ax,cl
	mov	dx,ds
	add	ax,dx
;
; Reserve the hard error stack (see dev_error) ahead of the first table.
;
	add	ax,ERR_STACK_SIZE SHR 4
	mov	es,ax			; ES = first free (low) paragraph
	ASSUME	ES:NOTHING
	mov	ax,offset sysinit_start + 15
	and	al,0F0h			; AX = DS-relative offset of the stack
	add	ax,ERR_STACK_SIZE
	mov	[err_stack],ax		; record the top of the stack
;
; The first resident table (scb_table) contains our Session Control Blocks.
; Look for a "SESSIONS=" line in CFG_FILE.
;
si5:	mov	si,offset CFG_SESSIONS
	call	find_cfg		; look for "SESSIONS="
	jc	si5a			; if not found, AX will be min value
	xchg	si,di
	push	es
	push	cs
	pop	es
	mov	bl,10			; BL = base 10
	DOSUTIL	ATOI16			; DS:SI -> string, ES:DI -> validation
	pop	es			; AX = new value
si5a:	mov	dx,size SCB
	mov	bx,offset scb_table
	call	init_table		; initialize table, update ES
;
; Initialize all the SCBs, by assigning them unique SCB_NUM values and
; setting their default console, AUX, and PRN system file handles to
; SFH_NONE (-1).
;
	mov	ax,SFH_NONE SHL 8	; AL = 0, AH = SFH_NONE
	cwd				; DL = SFH_NONE, DH = SFH_NONE
	mov	bx,[scb_table].OFF
	mov	[scb_active],bx		; make the first SCB active

si5b	label	near
	ASSERT	<SCB_NUM + 1>,EQ,<SCB_SFHIN>
	mov	word ptr [bx].SCB_NUM,ax
	mov	word ptr [bx].SCB_SFHOUT,dx
	mov	word ptr [bx].SCB_SFHAUX,dx
	DBGINIT	STRUCT,[bx],SCB
	inc	ax
	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	jb	si5b
;
; The next resident table (bpb_table) contains all the system BPBs.
;
; Diskette drives come first, followed by any hard disk volumes (in which
; case, like PC DOS, drives A: and B: are always reserved for diskettes).
;
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	al,[FDC_UNITS]		; AL = # diskette drives
	mov	ah,[HDC_UNITS]		; AH = # hard disk volumes
	test	ah,ah
	jz	si5c
	cmp	al,2
	jae	si5c
	mov	al,2
si5c:	mov	[FDC_UNITS],al		; (updated to include reserved drives)
	add	al,ah
	mov	ah,0			; AX = # drives
	mov	dx,size BPBEX
	mov	bx,offset bpb_table
	call	init_table		; initialize table, update ES
	mov	si,cs:[bpb_off]		; get the BPB the boot sector used
;
; Note that when we copy the "boot" BPB into the table of system BPBs, we
; don't assume that it came from drive 0 (that will always be true on the IBM
; PC, but on, um, future machines, perhaps not).
;
	push	es
	mov	es,cs:[dos_seg]
	ASSUME	ES:DOS
	mov	es:[bpb_total],al	; record # BPBs
	mov	ah,[FDC_UNITS]		; AH = # diskette drives
	push	ax			; save # BPBs on stack
;
; Initialize the buffer chain while DS still points to the BIOS segment.
;
	mov	cl,4
	mov	ax,offset FAT_BUFHDR + BIOS_DATA
	shr	ax,cl
	mov	es:[buf_head],ax
	mov	dx,offset DIR_BUFHDR + BIOS_DATA
	shr	dx,cl

	DBGINIT	STRUCT,[FAT_BUFHDR],BUF
	mov	[FAT_BUFHDR].BUF_PREV,dx
	mov	[FAT_BUFHDR].BUF_NEXT,dx
	mov	[FAT_BUFHDR].BUF_SIZE,512
	mov	dl,[si].BPB_DRIVE
	mov	[FAT_BUFHDR].BUF_DRIVE,dl

	DBGINIT	STRUCT,[DIR_BUFHDR],BUF
	mov	[DIR_BUFHDR].BUF_PREV,ax
	mov	[DIR_BUFHDR].BUF_NEXT,ax
	mov	[DIR_BUFHDR].BUF_SIZE,512

	mov	bp,[HDC_SEG]		; BP = HDC driver segment
	push	[FDC_DEVICE].SEG	; save FDC pointer on stack
	push	[FDC_DEVICE].OFF
	mov	al,[si].BPB_DRIVE	; use the BPB's own BPB_DRIVE #
	test	al,al			; to determine the system BPB to update
	jns	si5d
;
; We booted from a hard disk (eg, 80h), whose first volume follows the
; diskette drives; the HDC driver will build its BPB, so we don't copy the
; boot BPB, but FAT_BUF's data (from the boot code) is for that volume.
;
	mov	al,[FDC_UNITS]		; AL = drive # of 1st hard disk volume
	mov	es:[def_drive],al
	mov	[FAT_BUFHDR].BUF_DRIVE,al
	mov	bx,es:[scb_active]
	mov	es:[bx].SCB_CURDRV,al
	jmp	short si6b
si5d:	mov	ah,size BPBEX
	mul	ah
	mov	di,es:[bpb_table].OFF
	add	di,ax
	cmp	di,es:[bpb_table].SEG
	ASSERT	B
	jnb	si6b
	mov	cx,(size BPB) SHR 1
	push	di
	rep	movsw
	pop	di
	mov	es:[di].BPB_LARGESECS.LOW,0 ; discard boot loader's scratch cluster count
	push	es
	pop	ds
	ASSUME	DS:DOS
	call	set_bpbtime		; set BPB_TIMESTAMP to the tick count
;
; Calculate BPBEX values like BPB_CLUSLOG2 and BPB_CLUSBYTES for the "boot"
; BPB, and then initialize other BPBEX values (eg, BPB_DEVICE) for all BPBs.
;
; TODO: It would be nicer to leverage the FDC's buildbpb function to do some
; of this work, but that would have to be preceded by a call to the mediachk
; function to avoid hitting the disk(s) unnecessarily, and all of that would
; require access to the dev_request interface, which is awkward at the moment.
; So we'll live with a bit of redundant code here.
;
	sub	cx,cx
	mov	al,[di].BPB_CLUSSECS	; calculate LOG2 of CLUSSECS in CX
	test	al,al
	jnz	si6			; make sure CLUSSECS is non-zero

sie0:	jmp	sysinit_error

si6:	shr	al,1
	jc	si6a
	inc	cx
	jmp	si6
si6a:	jnz	sie0			; hmm, CLUSSECS wasn't a power-of-two
	mov	[di].BPB_CLUSLOG2,cl
	mov	ax,[di].BPB_SECBYTES	; use that to also calculate CLUSBYTES
	shl	ax,cl
	mov	[di].BPB_CLUSBYTES,ax
;
; Finally, calculate total clusters on the disk (total data sectors
; divided by sectors per cluster, or just another shift using CLUSLOG2).
;
	mov	ax,[di].BPB_DISKSECS
	sub	ax,[di].BPB_LBADATA	; AX = DISKSECS-LBADATA (data sectors)
	shr	ax,cl			; AX = data clusters
	mov	[di].BPB_CLUSTERS,ax

si6b:	push	es
	pop	ds
	ASSUME	DS:DOS
	pop	ax			; restore FDC pointer in DX:AX
	pop	dx
	pop	cx			; restore # BPBs in CL
	mov	bl,ch			; BL = # diskette drives
	mov	ch,0			; CH = drive #

	mov	di,[bpb_table].OFF	; DI -> first BPB
si6c:	DBGINIT	STRUCT,[di],BPB
	mov	[di].BPB_FREECLNS,-1
	mov	[di].BPB_FIXED,0
	cmp	ch,bl			; diskette drive?
	jb	si6e			; yes
	mov	[di].BPB_FIXED,1
	sub	ax,ax			; no, so the device is the HDC driver
	mov	dx,bp			; DX:AX -> HDC driver
si6e:	mov	[di].BPB_DEVICE.OFF,ax
	mov	[di].BPB_DEVICE.SEG,dx
	cmp	[di].BPB_SECBYTES,0	; is this BPB initialized?
	jne	si6d			; yes
	mov	[di].BPB_DRIVE,ch	; no, fill in the drive #
si6d:	add	di,size BPBEX
	inc	ch
	dec	cl
	jnz	si6c

	pop	es
	ASSUME	ES:NOTHING
;
; The next resident table (cdir_table) contains every session's current
; directory (1st cluster, or 0 for the root) for every drive.
;
	mov	ax,[scb_table].SEG
	sub	ax,[scb_table].OFF
	mov	dl,size SCB
	div	dl			; AL = # SCBs
	mul	[bpb_total]		; AX = # SCBs * # drives
	mov	dx,2
	mov	bx,offset cdir_table
	call	init_table		; initialize table, update ES
;
; The next resident table (sfb_table) contains our System File Blocks.
; Look for a "FILES=" line in CFG_FILE.
;
si7:	mov	si,offset CFG_FILES
	call	find_cfg		; look for "FILES="
	jc	si7a			; if not found, AX will be min value
	xchg	si,di
	push	es
	push	cs
	pop	es
	mov	bl,10			; BL = base 10
	DOSUTIL	ATOI16			; DS:SI -> string, ES:DI -> validation
	pop	es			; AX = new value
si7a:	mov	dx,size SFB
	mov	bx,offset sfb_table
	call	init_table		; initialize table, update ES
;
; Any disk buffers beyond the two in low memory (see "BUFFERS=") come next,
; each a BUFHDR followed by a 512-byte sector, added to the end of the chain.
;
	mov	si,offset CFG_BUFFERS
	call	find_cfg		; look for "BUFFERS="
	jc	sb1			; if not found, AX will be min value
	xchg	si,di
	push	es
	push	cs
	pop	es
	mov	bl,10			; BL = base 10
	DOSUTIL	ATOI16			; DS:SI -> string, ES:DI -> validation
	pop	es			; AX = new value
sb1:	sub	ax,2
	jbe	sb3
	push	ax			; save # extra buffers
	mov	cl,4
	mov	ax,offset DIR_BUFHDR + BIOS_DATA
	shr	ax,cl
	xchg	dx,ax			; DX = last buffer in the chain
	mov	ax,offset FAT_BUFHDR + BIOS_DATA
	shr	ax,cl
	xchg	bx,ax			; BX = head
	pop	cx			; CX = # extra buffers
sb2:	push	cx
	sub	di,di
	mov	ax,dx
	stosw				; BUF_PREV = last buffer
	mov	ax,bx
	stosw				; BUF_NEXT = head
	mov	ax,512
	stosw				; BUF_SIZE
	sub	ax,ax
	mov	cx,(size BUFHDR - 6) SHR 1
	rep	stosw			; zero the rest of the BUFHDR
	mov	ax,es
	push	ds
	mov	ds,dx
	mov	ds:[BUF_NEXT],ax	; link the last buffer to this one
	mov	ds,bx
	mov	ds:[BUF_PREV],ax	; and the head back to this one
	pop	ds
	xchg	dx,ax			; DX = new last buffer
	mov	ax,dx
	add	ax,(size BUFHDR + 512) SHR 4
	mov	es,ax			; ES = next available paragraph
	pop	cx
	loop	sb2
sb3:
;
; After all the resident tables have been created, the kernel's block ends at
; ES, so we give the rest back (see dos_size), and the MCB chain starts there
; (with the 8086 CPU$, the free block at ES follows the kernel's block in its
; MCB chain).
;
; The memory after it ends below our own code and stack (allowing 512 bytes
; for the stack, which peaks at 256-384 bytes, in a BIOS diskette interrupt),
; since loading a SHELL can use all available memory (eg, on a 64K machine);
; we give back the code below sysinit_tail before loading the first SHELL, and
; the rest after the last SHELL has been loaded (see init_free).
;
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	bx,es
	mov	es,[dos_seg]		; mcb_head is in resident DOS segment
	ASSUME	ES:DOS
	mov	es:[mcb_head],bx
	sub	bx,[dos_seg]		; BX = paragraphs in the kernel's block
	call	dos_size
;
; Before we create any sessions (and our first PSPs), we need to open all the
; devices required for the 5 STD handles: the console (CON) first, so that
; errors can be reported, and then AUX and PRN (after any DEVICE= drivers).
;
; Since no PSP exists yet, DOS_HDL_OPEN will return system file handles, not
; process file handles.  Which is exactly what we want, because we're going to
; store each SFH in the SCB, so that every time a new program is loaded in the
; SCB, its PSP will receive the same SFHs.
;
; Until a PSP exists, STDOUT is SFH 1 (see utl_printf), so the console must be
; SFH 1.  NUL holds SFH 0 until just before AUX is opened, so that AUX (if it
; exists) is SFH 0, as in PC DOS.  If NUL was skipped, the console is SFH 0,
; and messages are lost until the first session starts.
;
	mov	dx,offset NUL_DEVICE
	mov	ax,DOS_HDL_OPENRW
	int	21h			; AX = SFH 0 (if successful)
;
; Open the console, with optional context.  If there's a "CON=" setting in
; CFG_FILE, use that; otherwise, use CON_DEVICE.  If the setting can't be
; opened (eg, its adapter or serial port doesn't exist), fall back to
; CON_DEVICE, and report the failure once the console is open.
;
	mov	bx,es:[scb_active]	; BX -> SCB
si8:	mov	si,offset CFG_CON
	mov	dx,offset CON_DEVICE
	call	find_cfg		; look for "CON="
	jc	si9			; not found
	mov	dx,di
si9:	sub	si,si			; SI = 0 (no error yet)
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jnc	si9a
	xchg	si,ax			; SI = error code
	mov	di,dx			; DI -> failed setting
	mov	dx,offset CON_DEVICE
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jnc	si9a
	jmp	open_error
si9a:	mov	es:[bx].SCB_SFHIN,al	; AL = SFH (not PFH)
	mov	es:[bx].SCB_SFHOUT,al	; AL = SFH (not PFH)
	mov	es:[bx].SCB_SFHERR,al	; AL = SFH (not PFH)
	test	si,si			; did the setting fail?
	jz	si9b			; no
	xchg	ax,si			; AX = error code
	mov	dx,di			; DX -> failed setting
	call	open_warning
si9b:
;
; SWITCHAR=- (or /) changes the switch character, unless it's the same as
; the path character (eg, SWITCHAR=/ with PATHCHAR=/), in which case we
; report the conflict and leave the switch character alone.  Any other
; setting is ignored.  A '-' boot key acts like SWITCHAR=- (which never
; conflicts), so that it can be chosen at the boot prompt.
;
	mov	al,'-'
	cmp	byte ptr es:[key_boot],al; was the boot key '-'?
	je	si9c			; yes
	mov	si,offset CFG_SWITCHAR
	call	find_cfg		; look for "SWITCHAR="
	jc	si9e
	mov	al,[di]
	cmp	al,es:[def_pathchar]	; same as the path character?
	je	si9d			; yes
	cmp	al,'-'
	je	si9c
	cmp	al,'/'
	jne	si9e
si9c:	mov	es:[def_swchar],al	; update the default for all SCBs
	jmp	short si9e
si9d:	PRINTF	<"Warning: SWITCHAR conflicts with PATHCHAR",13,10>
si9e:
;
; Now that a console is open (for reporting errors), load any DEVICE= drivers,
; before opening any other consoles (which can't use devices they've reserved).
; Since there's no PSP yet, the SCB needs these settings for parsing paths.
;
	mov	ax,word ptr es:[def_drive]
	mov	word ptr es:[bx].SCB_CURDRV,ax
	ASSERT	<SCB_CURDRV+1>,EQ,<SCB_SWCHAR>
	mov	al,es:[def_pathchar]
	mov	es:[bx].SCB_PATHCHAR,al
	call	load_devices
;
; Next, open AUX and PRN, after the DEVICE= drivers, so that they don't take
; a port that a driver needs for itself (eg, DEBUG$).  Every session shares
; the same AUX and PRN devices.  Closing NUL first frees SFH 0 for AUX.
;
	cmp	es:[bx].SCB_SFHOUT,0	; is the console SFH 0 (ie, no NUL)?
	je	si9f			; yes, so leave it open
	push	bx
	sub	bx,bx			; BX = SFH 0 (NUL)
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	bx
si9f:	mov	si,offset CFG_AUX
	mov	dx,offset AUX_DEVICE
	call	open_dev
	xchg	cx,ax			; CL = SFH for AUX
	mov	si,offset CFG_PRN
	mov	dx,offset PRN_DEVICE
	call	open_dev
	mov	ch,al			; CH = SFH for PRN
	mov	word ptr es:[bx].SCB_SFHAUX,cx
	ASSERT	<SCB_SFHAUX + 1>,EQ,<SCB_SFHPRN>
;
; See if there are any more CON settings; if so, then for each one, open the
; console, and record it in the next available SCB.  If there aren't enough
; SCBs or SFBs, then we've got a configuration error.  If one can't be opened,
; we report it, reuse its SCB for the next one, and record its bit in
; con_fails, so that its SHELL is skipped.
;
si10:	mov	si,offset CFG_CON
	call	find_cfg		; look for another "CON="
	jnc	si10a
	jmp	si12			; no more
si10a:	shl	[con_bit].OFF,1
	rcl	[con_bit].SEG,1
	add	bx,size SCB
	cmp	bx,es:[scb_table].SEG
	jb	si11
	mov	dx,offset CONERR
	jmp	print_error
si11:	mov	es:[scb_active],bx	; make the next SCB active
	mov	dx,di
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jnc	si11a
	sub	bx,size SCB		; reuse this SCB
	mov	es:[scb_active],bx
	call	open_warning
	mov	ax,[con_bit].OFF
	or	[con_fails].OFF,ax
	mov	ax,[con_bit].SEG
	or	[con_fails].SEG,ax
	jmp	si10
si11a:	inc	[con_count]
	mov	es:[bx].SCB_SFHIN,al
	mov	es:[bx].SCB_SFHOUT,al
	mov	es:[bx].SCB_SFHERR,al
	mov	word ptr es:[bx].SCB_SFHAUX,cx
	ASSERT	<SCB_SFHAUX + 1>,EQ,<SCB_SFHPRN>
	jmp	si10

;
; Get the address of the FPU$ driver's function table (FPUTBL), if any, for
; sprintf's %f formatter.
;
si12:	mov	dx,offset FPU_DEVICE
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	si12a
	xchg	bx,ax			; BX = SFH
	push	ds
	push	es
	pop	ds
	mov	si,offset fpu_table	; DS:SI -> fpu_table
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETFPU
	int	21h
	pop	ds
	mov	ah,DOS_HDL_CLOSE
	int	21h

;
; If the DEBUG.COM driver is installed, open its DEBUG$ device for DPRINTF
; (see utl_dprintf).
;
si12a:	mov	dx,offset DBG_DEVICE
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jc	si14
	mov	es:[sfh_debug],al	; save SFH for DEBUG$ device
;
; Good time to print a "System ready" message, or something to that effect.
;
si14:	mov	dx,offset SYS_MSG
	mov	ah,DOS_TTY_PRINT
	int	21h
;
; Before we start loading SHELL definitions, we're going to hook INT 21h
; with a handler that looks for duplicate opens and returns a cached copy
; of the data for any load after the first.
;
	mov	ax,(DOS_MSC_GETVEC SHL 8) OR 21h
	int	21h
	mov	[pCacheInt21].OFF,bx
	mov	[pCacheInt21].SEG,es
	mov	dx,offset cache_int21
	push	cs
	pop	ds
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 21h
	int	21h
;
; For each SHELL definition, load the corresponding file into the next
; available SCB.  The first time through, CFG_SHELL is used as a fallback,
; so even if there are no SHELL definitions, at least one will be loaded.
;
; None of our code before this point will run again, so first we move our
; stack up to sysinit_tail and give back the memory below it (see init_free),
; so that the SHELLs can use that memory too.
;
	ASSERT	Z,<cmp sp,offset sysinit_start - 2>	; (after PUSHF)
	mov	sp,offset sysinit_tail
	DEFLBL	sysinit_tail,near
	mov	ax,offset sysinit_tail - 200h
	call	init_free

	sub	sp,size SPB		; alloc SPB from the stack

	mov	es,[dos_seg]
	ASSUME	ES:DOS
;
; Lock the SCB until we're done: once a SHELL has been started, a yield in
; any DOS call we make (eg, a deferred yield on a full unlock) would switch to
; it, saving our stack in the active SCB, which could later resume it after
; we're gone.  Waits still end normally, since locked yields simply return.
;
	inc	es:[scb_locked]		; LOCK_SCB (see the end of sysinit)
	mov	al,es:[def_drive]
	mov	[boot_drive],al
	sub	dx,dx			; DX = SCB load count
	mov	bx,offset SHELL_FILE	; BX = default shell
si15:	mov	si,offset CFG_SHELL
	call	find_cfg		; look for "SHELL="
	jc	si16			; not found
	mov	bx,di
si16:	test	bx,bx			; do we still have a default?
	jnz	si16b			; yes
	jmp	si20			; no, done loading
;
; A SHELL whose file includes a drive (eg, "C:/COMMAND.COM") starts on that
; drive; otherwise, it starts on the boot drive (see init_scb).
;
si16b:	mov	es,[dos_seg]
	ASSUME	ES:DOS
	mov	al,[boot_drive]
	cmp	byte ptr [bx+1],':'	; does the SHELL specify a drive?
	jne	si16c			; no
	mov	al,[bx]
	and	al,0DFh			; upper-case the drive letter
	sub	al,'A'			; AL = drive #
si16c:	mov	es:[def_drive],al
;
; Note that during the LOAD process, the SCB is locked and active, so that
; the program file can be opened and read using the SCB's PSP.  It's unlocked
; when the load finishes, but it won't start running until after START is set.
;
	push	ss
	pop	es
	mov	di,sp			; ES:DI -> SPB on stack
	mov	ax,-1
	stosw				; SPB_ENVSEG <- -1
	xchg	ax,bx
	stosw				; SPB_CMDLINE.OFF <- BX
	mov	ax,ds
	stosw				; SPB_CMDLINE.OFF <- DS
	xchg	ax,bx			; AX = -1 again (aka SFH_NONE)
	stosb				; SPB_SFHIN  <- SFH_NONE
	stosb				; SPB_SFHOUT <- SFH_NONE
	stosb				; SPB_SFHERR <- SFH_NONE
	stosb				; SPB_SFHAUX <- SFH_NONE
	stosb				; SPB_SFHPRN <- SFH_NONE
	mov	bx,sp			; ES:BX -> SPB on stack
	mov	cx,0FFh			; CL = invalid SCB # (in case of error),
					; CH = no programs follow
;
; Skip the SHELL of a CONSOLE that couldn't be opened (see si11), and reject
; any SHELL beyond the last console, since its session would have none.
;
	shr	[con_fails].SEG,1
	rcr	[con_fails].OFF,1
	jc	si17			; its CONSOLE failed
	mov	ax,ERR_NOSESSION
	cmp	dl,[con_count]
	jae	si18
	DOSUTIL	LOAD			; load specified SHELL into an SCB
	jc	si18
	test	ax,ax
	jz	si16a
	mov	[cbCacheData],ax
	mov	[pCacheData].OFF,bx
	mov	[pCacheData].SEG,es
si16a:	DOSUTIL	START			; CL = SCB # (from the LOAD call)
	inc	dx			; must be valid, so no error checking

si17:	sub	bx,bx			; no default shell now
	jmp	si15

si18:	mov	si,sp			; SS:SI -> SPB
	mov	si,ss:[si].SPB_CMDLINE.OFF
;
; Print the error on the console of the session we tried to load (CL), if
; any; since there's no PSP yet, PRINTF would always use SFH 1 (ie, the first
; session's console), so we use HPRINTF with that session's SFHOUT instead.
;
	push	ax			; save error code
	mov	al,size SCB
	mul	cl
	push	es
	mov	es,[dos_seg]
	ASSUME	ES:DOS
	add	ax,es:[scb_table].OFF
	xchg	bx,ax			; BX -> SCB
	mov	al,1			; default to SFH 1
	cmp	bx,es:[scb_table].SEG	; valid SCB?
	jae	$+6			; no
	mov	al,es:[bx].SCB_SFHOUT	; (4 bytes)
	pop	es
	ASSUME	ES:NOTHING
	xchg	bx,ax			; BL = SFH
	pop	ax			; AX = error code
;
; The only ERR_BADFORMAT that loading a SHELL returns is load_command's
; "tail too long" error, which leaves the whole SHELL line intact, so show
; the start of it.
;
	cmp	ax,ERR_BADFORMAT	; SHELL line too long?
	jne	si19			; no
	ECCALL	DOS_UTL_HPRINTF,<"SHELL line too long: %.40s...">,<13,10>,ax,si
	jmp	si17
si19:	ECCALL	DOS_UTL_HPRINTF,<"Unable to load %s">,<13,10>,ax,si
	jmp	si17
;
; Although it may appear every SCB was started immediately after loading,
; nothing can ACTUALLY run until we obtain access to the CLOCK$ device and
; re-vector all the hardware interrupt handlers that drive our scheduler.
;
si20:	add	sp,size SPB		; free SPB on the stack
					; (somewhat moot, but let's stay tidy)
	mov	cx,dx			; CX = SCB load count
	lds	dx,[pCacheInt21]	; restore INT 21h vector
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 21h
	int	21h
	push	cs
	pop	ds

	test	cx,cx			; if no SCBs loaded, that's not good
	jnz	si20a
	mov	dx,offset HALTED+2	; (the errors were reported; see si18)
	jmp	fe1
si20a:
;
; Utility functions like SLEEP need access to the clock device, so we save
; its address in clk_ptr.  While we could open the device normally and obtain
; a system file handle, that would require the utility functions to use SFB
; interfaces (sfb_get, sfb_read, etc) with no benefit.
;
	mov	dx,offset CLK_DEVICE
	DOSUTIL	GETDEV
	jnc	$+5
	jmp	open_error
	mov	ds,[dos_seg]
	mov	[clk_ptr].OFF,di
	mov	[clk_ptr].SEG,es
;
; "Revector" DDINT_ENTER and DDINT_LEAVE to int_enter and int_leave.
;
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	cli
	mov	di,offset DDINT_ENTER + DDINT_BIAS
	mov	ax,offset int_enter
	call	sto_jmpf
	mov	ax,offset int_leave
	call	sto_jmpf
	ASSUME	ES:NOTHING
;
; Now that every SHELL has been loaded, free the memory containing our code
; and stack (which CPU$ merges with the free block before it, if any).
; Interrupts are off, and nothing will allocate memory until we're gone.
;
	sub	ax,ax
	call	init_free
;
; Save the vectors that programs commonly hook directly (01h, 03h, 08h, 09h,
; 1Bh, and 1Ch), now that the drivers have hooked theirs (see psp_restvec).
;
	mov	si,offset ivt_save	; DS:SI -> vector #s and saved vectors
iv1:	lodsb				; AL = vector #
	test	al,al			; end of the list?
	jz	iv2			; yes
	call	far ptr DDINT_GETVEC	; DX:CX = vector
	mov	[si].OFF,cx
	mov	[si].SEG,dx
	add	si,4
	jmp	iv1
iv2:
;
; Activate and start running the first session.  We must mimic scb_switch
; rather than calling it, because we're not switching SCBs (sysinit is not
; a session).
;
; The end of sysinit used to just turn on interrupts and spin, knowing that
; the first scb_yield would never return here, but that required us to also
; zero scb_active and include "null SCB" tests in scb_yield and scb_switch;
; this approach eliminates the need for those special tests.
;
; Interrupts are still off, so we can release our SCB lock (see si15) without
; scb_release; any deferred yield will occur on the session's next unlock.
;
	dec	[scb_locked]
	mov	bx,[scb_table].OFF	; BX -> the first SCB
	mov	[scb_active],bx		; make it active (for consistency)
	mov	ss,[bx].SCB_STACK.SEG
	mov	sp,[bx].SCB_STACK.OFF
	push	ds
	mov	ax,offset dos_leave
	push	ax
	ret				; we let dos_leave turn interrupts on
ENDPROC	sysinit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sysinit_error (print generic error message and halt)
;
; Inputs:
;	None
;
; Outputs:
;	None (system halted)
;
	DEFLBL	sysinit_error,near
	mov	dx,offset SYSERR

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; print_error (print error message and halt)
;
; Inputs:
;	DX -> message
;
; Modifies:
;	AX, DS
;
	DEFLBL	print_error,near
	push	cs
	pop	ds
	mov	ah,DOS_TTY_PRINT
	int	21h

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fatal_error (print halt message and halt)
;
; Inputs:
;	None
;
; Outputs:
;	None (system halted)
;
	DEFLBL	fatal_error,near
	mov	dx,offset HALTED
fe1:	mov	ah,DOS_TTY_PRINT
	int	21h
	sti				; (so that a COM console can finish)
	jmp	$			; "halt"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sto_jmpf
;
; Inputs:
;	DS:AX -> target
;	ES:DI -> where to store a far jump to it
;
; Outputs:
;	ES:DI -> just past the far jump
;
; Modifies:
;	AX, DI
;
DEFPROC	sto_jmpf
	push	ax
	mov	al,OP_JMPF
	stosb
	pop	ax
	stosw
	mov	ax,ds
	stosw
	ret
ENDPROC	sto_jmpf

;
; Initialization variables (these follow sysinit_tail, since they're used
; until we're done).
;
	DEFWORD	bpb_off
	DEFWORD	dos_seg
	DEFWORD	cfg_data
	DEFWORD	cfg_size

	DEFPTR	pCacheInt21
	DEFPTR	pCacheData
	DEFWORD	cbCacheData

	DEFLONG	con_bit,1		; bit for the current CONSOLE line
	DEFLONG	con_fails,0		; bits for CONSOLE lines that failed
	DEFBYTE	con_count,1		; number of consoles opened
	DEFBYTE	boot_drive		; default drive for each SHELL
;
; Initialization data
;
; Labels are capitalized to indicate that the data is R/O, not R/W.
;
	DEFLBL	INT_TABLES,word
	dw	INT_DV			; 00h: diverr and single-step vectors
	dw	dos_dverr,dos_sstep,0
	dw	INT_BP			; 03h: breakpoint and overflow vectors
	dw	dos_brkpt,dos_oferr,0
	dw	INT_DOSTERM		; 20h: initialize all the DOS vectors
	dw	dos_term,dos_func,dos_exit,dos_ctrlc
	dw	dos_error,disk_read,disk_write,dos_tsr,dos_default,0
	dw	INT_DOSNET		; 2Ah
	dw	dos_default,dos_default,dos_default
	dw	dos_default,dos_default,dos_default,0
	dw	-1			; end of tables
	DEFLBL	INT_TABLES_END

CFG_CON		db	4,"CON="
CON_DEVICE	db	"VKD$:80,25",0	; default CON configuration
CFG_AUX		db	4,"AUX="
CFG_PRN		db	4,"PRN="
CFG_BUFFERS	db	8,"BUFFERS="
		dw	2,2,32
;
; FILES can't exceed 254, since SFH 0FEh is SFH_NODEV.
;
CFG_FILES	db	6,"FILES="
		dw	20,8,254
CFG_MEMSIZE	db	8,"MEMSIZE="
		dw	640,16,640
CFG_SESSIONS	db	9,"SESSIONS="
		dw	4,1,32		; TODO: Decide if 32 session limit OK
CFG_SHELL	db	6,"SHELL="
CFG_PATHCHAR	db	9,"PATHCHAR="
CFG_SWITCHAR	db	9,"SWITCHAR="

NUL_DEVICE	db	"NUL",0
AUX_DEVICE	db	"COM1",0	; default AUX device
PRN_DEVICE	db	"LPT1",0	; default PRN device
CLK_DEVICE	db	"CLOCK$",0
FPU_DEVICE	db	"FPU$",0
DBG_DEVICE	db	"DEBUG$",0
SHELL_FILE	db	"COMMAND.COM",0	; default SHELL file

SYS_MSG		db	"BASIC-DOS "
		VERSION_STR
		db	13,10
		db	"Copyright (c) PCJS.ORG 1981-2026",13,10,13,10,'$'

SYSERR		db	"System initialization error$"
CONERR		db	"More consoles than SESSIONS$"
HALTED		db	13,10,"System halted",13,10,'$'


DOS	ends

	end
