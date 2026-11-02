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
	EXTWORD	<mcb_limit,buf_head,key_boot,scb_active,ivt_save,tbl_next>
	EXTWORD	<err_stack,dos_data>
	EXTLONG	<bpb_table,scb_table,sfb_table,cdir_table,clk_ptr,fpu_table>
	EXTLONG	<dev_head>
	EXTNEAR	<find_cfg,init_table,set_bpbtime,load_devices,sysinit_end>
	EXTNEAR	<move_init,dos_size,map_buf,map_dos>
	EXTNEAR	<set_call5,mem_total>
	EXTNEAR	<open_dev,open_warning,open_error>
	EXTNEAR	<sysinit_tail,fatal_error,set_ddint,set_fault>
	EXTWORD	<dos_seg,dos_code,cfg_data,cfg_size>
	EXTLONG	<pCacheInt21,con_fails>
	EXTBYTE	<con_count>
	EXTERNS	<cache_int21>,far
	EXTNEAR	<dos_dverr,dos_sstep,dos_brkpt,dos_oferr>
	EXTNEAR	<dos_term,dos_func,dos_exit,dos_ctrlc,dos_error,dos_default>
	EXTNEAR	<dos_fastcon>
	EXTNEAR	<disk_read,disk_write,dos_tsr,dos_util,dos_leave>
	EXTNEAR	<int_enter,int_leave,int_util>

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
;	segment 0), and our address; devinit pushes them before having CPU$
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
	mov	es:[dos_seg],es		; save the resident DOS data segment
	mov	es:[dos_data],es	; (where the kernel keeps it, too)
	mov	es:[dos_code],cs	; and its code segment
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
; units), so shift left 6 bits.  CPU$ has already applied any "MEMSIZE="
; line to MEMORY_SIZE (see ddcpu_init in 286dev.asm).  mem_total adds any
; extended memory to it, for the total memory (see DV_MEM_SIZE).
;
si1:	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,[MEMORY_SIZE]	; get available memory in Kb
	push	es
	pop	ds
	ASSUME	DS:DOS
	call	mem_total		; record the total memory
	mov	cl,6
	shl	ax,cl			; available memory in paras
	mov	[mcb_limit],ax
	mov	si,offset sysinit_start - 200h
	call	move_init		; AX = code selector, DX = data
	push	ax
	mov	ax,offset sysinit_high
	push	ax
	ret
;
; Initialize all the DOS vectors.  DS is dos_seg.
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
; Initialize all the DOS vectors with DDINT_SETVEC (which CPU$ provides).
;
	mov	si,offset INT_TABLES
si2:	lodsw
	test	ax,ax			; any more tables?
	jl	si2b			; no
	xchg	bx,ax			; BL = first vector of the table
si2a:	lodsw				; AX = offset of the next handler
	test	ax,ax			; end of the table?
	jz	si2			; yes
	xchg	cx,ax
	mov	dx,cs:[dos_code]	; DX:CX -> handler
	mov	al,bl
	call	far ptr DDINT_SETVEC
	inc	bx
	jmp	si2a
;
si2b:	call	set_call5
	mov	al,INT_DOSUTIL
	mov	cx,offset dos_util
	mov	dx,cs:[dos_code]
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
	mov	dx,cs:[dos_code]
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
	mov	dx,cs:[dos_code]
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
	call	set_ddint
	sti
;
; The current SP is sysinit_start, and relative to SS, that's safe place
; for our stack, whereas relative to DS, it's the start of DOS table space,
; and while the SCBs will be our first table, we have to temporarily set
; scb_active to that same region, so that any DOS or DOSUTIL calls we make
; will not barf due to the lack of an active SCB.  That region still holds
; the original copy of this init code, so zero it first (eg, SCB_INDOS must
; start at zero), starting at SP before the PUSH, since the resident code
; ends just below it (see dos_fault).
;
	mov	di,sp
	push	es
	push	ds
	pop	es
	ASSUME	ES:DOS
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
; Now grow the kernel's block (see dos_size) as much as possible; the hard
; error stack (see dev_error) goes in the next paragraph after our resident
; code (see set_fault) and stack, and the first resident table follows it
; (see init_table).
;
si3a:	sub	bx,bx
	call	dos_size
	call	set_fault		; AX = end of the resident code
	add	ax,15
	and	al,0F0h			; AX = DS-relative offset of the stack
	add	ax,ERR_STACK_SIZE
	mov	[err_stack],ax		; record the top of the stack
	mov	ss:[tbl_next],ax
;
; The first resident table (scb_table) contains our Session Control Blocks.
; Look for a "SESSIONS=" line in CFG_FILE.
;
si5:	mov	si,offset CFG_SESSIONS
	call	find_cfg		; look for "SESSIONS="
	jc	si5a			; if not found, AX will be min value
	xchg	si,di
	push	cs
	pop	es
	mov	bl,10			; BL = base 10
	DOSUTIL	ATOI16			; DS:SI -> string, ES:DI -> validation
si5a:	mov	dx,size SCB		; AX = new value
	mov	bx,offset scb_table
	call	init_table
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
	call	init_table
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
; Initialize the buffer chain while DS still points to the BIOS segment, with
; segments (or selectors) from CPU$ for the two buffers in low memory.
;
	mov	cx,offset DIR_BUFHDR + BIOS_DATA
	call	map_buf
	push	ax			; save DIR_BUFHDR's segment
	mov	cx,offset FAT_BUFHDR + BIOS_DATA
	call	map_buf			; AX = FAT_BUFHDR's segment
	pop	dx			; DX = DIR_BUFHDR's segment
	mov	es:[buf_head],ax

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
	call	init_table
;
; The next resident table (sfb_table) contains our System File Blocks.
; Look for a "FILES=" line in CFG_FILE.
;
si7:	mov	si,offset CFG_FILES
	call	find_cfg		; look for "FILES="
	jc	si7a			; if not found, AX will be min value
	xchg	si,di
	push	cs
	pop	es
	mov	bl,10			; BL = base 10
	DOSUTIL	ATOI16			; DS:SI -> string, ES:DI -> validation
si7a:	mov	dx,size SFB		; AX = new value
	mov	bx,offset sfb_table
	call	init_table
;
; Any disk buffers beyond the two in low memory (see "BUFFERS=") come next,
; each a BUFHDR followed by a 512-byte sector, added to the end of the chain,
; with a segment (or selector) from CPU$.
;
	mov	si,offset CFG_BUFFERS
	call	find_cfg		; look for "BUFFERS="
	jc	sb1			; if not found, AX will be min value
	xchg	si,di
	push	cs
	pop	es
	mov	bl,10			; BL = base 10
	DOSUTIL	ATOI16			; DS:SI -> string, ES:DI -> validation
sb1:	sub	ax,2			; AX = new value
	jbe	sb3
	xchg	cx,ax			; CX = # extra buffers
	mov	bx,[buf_head]		; BX = head
	push	ds
	mov	ds,bx
	mov	dx,ds:[BUF_PREV]	; DX = last buffer in the chain
	pop	ds
sb2:	push	cx
	mov	di,ss:[tbl_next]	; DI = offset of this buffer
	mov	ax,di
	add	ax,size BUFHDR + 512
	jnc	$+5
	jmp	sysinit_error		; (it doesn't fit in the segment)
	mov	ss:[tbl_next],ax
	push	di
	push	ds
	pop	es			; ES:DI -> this buffer
	mov	ax,dx
	stosw				; BUF_PREV = last buffer
	mov	ax,bx
	stosw				; BUF_NEXT = head
	mov	ax,512
	stosw				; BUF_SIZE
	sub	ax,ax
	mov	cx,(size BUFHDR - 6) SHR 1
	rep	stosw			; zero the rest of the BUFHDR
	pop	ax			; AX = offset of this buffer
	push	dx
	call	map_dos			; AX = its segment (or selector)
	pop	dx
	push	ds
	mov	ds,dx
	mov	ds:[BUF_NEXT],ax	; link the last buffer to this one
	mov	ds,bx
	mov	ds:[BUF_PREV],ax	; and the head back to this one
	pop	ds
	xchg	dx,ax			; DX = new last buffer
	pop	cx
	loop	sb2
sb3:
;
; After all the resident tables have been created, the kernel's block ends at
; tbl_next, so we give the rest back (see dos_size).
;
; The memory after it ends below our own code and stack (allowing 512 bytes
; for the stack, which peaks at 256-384 bytes, in a BIOS diskette interrupt),
; since loading a SHELL can use all available memory (eg, on a 64K machine);
; we give back the code below sysinit_tail before loading the first SHELL, and
; the rest after the last SHELL has been loaded (see init_free).
;
	push	ss			; (our data; CS is our code)
	pop	ds
	ASSUME	DS:DOS
	mov	bx,ss:[tbl_next]	; BX = length of the kernel's block
	call	dos_size
	mov	es,[dos_seg]
	ASSUME	ES:DOS
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
	pop	ds			; DS:DX -> cache_int21
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 21h
	int	21h
	push	ss
	pop	ds			; DS = our data again
;
; Everything that sysinit still needs while it loads the SHELLs follows
; sysinit_tail (see systail.asm), so that it can give back the rest first.
;
	ASSERT	Z,<cmp sp,offset sysinit_start - 2>	; (after PUSHF)
	jmp	sysinit_tail
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
	jmp	fatal_error

;
; Initialization variables
;
	DEFWORD	bpb_off
	DEFLONG	con_bit,1		; bit for the current CONSOLE line
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
CFG_SESSIONS	db	9,"SESSIONS="
		dw	4,1,32		; TODO: Decide if 32 session limit OK
CFG_PATHCHAR	db	9,"PATHCHAR="
CFG_SWITCHAR	db	9,"SWITCHAR="

NUL_DEVICE	db	"NUL",0
AUX_DEVICE	db	"COM1",0	; default AUX device
PRN_DEVICE	db	"LPT1",0	; default PRN device
FPU_DEVICE	db	"FPU$",0
DBG_DEVICE	db	"DEBUG$",0

SYS_MSG		db	"BASIC-DOS "
		VERSION_STR
		db	13,10
		db	"Copyright (c) PCJS.ORG 1981-2026",13,10,13,10,'$'

SYSERR		db	"System initialization error$"
CONERR		db	"More consoles than SESSIONS$"


DOS	ends

	end
