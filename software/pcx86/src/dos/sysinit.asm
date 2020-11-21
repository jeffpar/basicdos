;
; BASIC-DOS System Initialization
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	disk.inc
	include	devapi.inc
	include	dos.inc

DOS	segment word public 'CODE'

	EXTBYTE	<bpb_total,sfh_debug,def_switchar>
	EXTWORD	<mcb_head,mcb_limit,buf_head,key_boot,scb_active>
	EXTLONG	<bpb_table,scb_table,sfb_table,clk_ptr>
	EXTNEAR	<dos_dverr,dos_sstep,dos_brkpt,dos_oferr,dos_opchk>
	EXTNEAR	<dos_term,dos_func,dos_exret,dos_ctrlc,dos_error,dos_default>
	EXTNEAR	<disk_read,disk_write,dos_tsr,dos_call5,dos_util>
	EXTNEAR	<dos_ddint_enter,dos_ddint_leave>

	DEFLBL	sysinit_start

	DEFWORD	bpb_off
	DEFWORD	dos_seg
	DEFWORD	top_seg
	DEFWORD	cfg_data
	DEFWORD	cfg_size

	DEFPTR	pCacheInt21
	DEFPTR	pCacheFile
	DEFPTR	pCacheData
	DEFWORD	cbCacheData
	DEFPTR	pCacheActive
	DEFWORD	cbCacheActive

	ASSUME	CS:DOS, DS:BIOS, ES:DOS, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; System initialization
;
; Everything after "sysinit_start" will be recycled.
;
; Entry:
;	AX = offset of initial BPB
;	DS:BX -> CFG_FILE data, if any
;	DX = size of CFG_FILE data, if any
;
DEFPROC	sysinit,far
	mov	[bpb_off],ax		; save boot BPB (BIOS offset)
	mov	ax,cs
	mov	[dos_seg],ax		; save the resident DOS segment
	mov	[cfg_data],bx		; offset of CFG data
	mov	[cfg_size],dx		; size of CFG data
;
; To simplify use of the CFG data, replace CRs with nulls (leave
; the LFs alone, because find_cfg uses those to find the next line).
;
	mov	di,bx
	mov	cx,dx
	mov	al,0Dh
si0:	repne	scasb
	jcxz	si1
	mov	byte ptr es:[di-1],0
	jmp	si0
;
; Move all the init code/data out of the way, to top of available memory.
;
; Size is in Kb (2^10 units), we need size in paragraphs (2^4 units), so
; shift left 6 bits.  Then calculate init code size in paras and subtract.
;
si1:	mov	ax,[MEMORY_SIZE]	; get available memory in Kb
	mov	cl,6
	shl	ax,cl			; available memory in paras
	mov	[top_seg],ax		; segment of end of memory
	mov	[mcb_limit],ax
	add	bx,dx			; add size of CFG data
	mov	si,offset sysinit_start	; SI = offset of init code
	sub	bx,si			; BX = number of bytes to move
	lea	dx,[bx+31]
	mov	cl,4
	shr	dx,cl			; max number of paras spanned
	sub	ax,dx			; target segment
	mov	dx,si
	shr	dx,cl			; DX = 1st paragraph of init code
	sub	ax,dx			; AX = target segment adjusted for ORG
	mov	es,ax			; begin the move
	ASSUME	ES:NOTHING
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	di,si
	mov	cx,bx
	shr	cx,1
	rep	movsw
	push	ax			; push new segment on stack
	mov	ax,offset sysinit_high
	push	ax			; push new offset on stack
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
	push	cs			; use all the space available
	pop	ss			; directly below the sysinit code
	mov	sp,offset sysinit_start
	mov	es,cx			; CX is zero from above
	ASSUME	ES:BIOS
	mov	si,offset INT_TABLES
si2:	lodsw
	test	ax,ax			; any more tables?
	jl	si3a			; no
	xchg	di,ax			; DI -> first vector for table
si3:	lodsw				; load vector offset
	test	ax,ax			; end of sub-table?
	jz	si2			; yes
	stosw				; store vector offset
	mov	ax,ds
	stosw				; store vector segment
	jmp	si3
si3a:	mov	al,0EAh			; DI -> INT_DOSCALL5 * 4
	stosb
	mov	ax,offset dos_call5
	stosw
	mov	ax,ds
	stosw
	add	di,3			; DI -> INT_DOSUTIL * 4
	mov	ax,offset dos_util
	stosw
	mov	ax,ds
	stosw
;
; Let users override the default switch character '/' (eg, "SWITCHAR=-").
;
	mov	si,offset CFG_SWITCHAR
	call	find_cfg		; look for "SWITCHAR="
	jc	si3b
	mov	al,[di]			; grab the character
	mov	[def_switchar],al	; and update the default for all SCBs
;
; Copy BOOT_KEY from the BIOS segment to key_boot in the DOS segment.
;
si3b:	mov	ax,[BOOT_KEY]		; copy the boot key
	cmp	al,CHR_RETURN		; unless it's just a RETURN
	je	si3c
	mov	[key_boot],ax
;
; For ease of configuration testing, allow MEMSIZE (eg, MEMSIZE=32) to set a
; new memory limit (Kb), assuming we have at least as much memory as specified.
;
si3c:	mov	si,offset CFG_MEMSIZE
	call	find_cfg		; look for "MEMSIZE="
	jc	si4
	xchg	si,di
	push	ds
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
	mov	cs:[top_seg],ax
;
; Now set ES to the first available paragraph for resident DOS tables.
;
si4:	mov	ax,offset sysinit_start
	test	al,0Fh			; started on a paragraph boundary?
	jz	si4a			; yes
	inc	dx			; no, so skip to next paragraph
si4a:	mov	ax,ds
	add	ax,dx
	mov	es,ax			; ES = first free (low) paragraph
	ASSUME	ES:NOTHING
	mov	ds,cx
	ASSUME	DS:BIOS
;
; The first resident table (bpb_table) contains all the system BPBs.
;
	mov	al,[FDC_UNITS]
	cbw
	mov	dx,size BPBEX
	mov	bx,offset bpb_table
	call	init_table		; initialize table, update ES
	mov	si,[bpb_off]		; get the BPB the boot sector used
;
; Note that when we copy the "boot" BPB into the table of system BPBs, we
; don't assume that it came from drive 0 (that will always be true on the IBM
; PC, but on, um, future machines, perhaps not).
;
	push	es
	mov	es,[dos_seg]
	ASSUME	ES:DOS
	mov	es:[bpb_total],al	; record # BPBs
	push	ax			; save # BPBs on stack
;
; Initialize the buffer chain while DS still points to the BIOS segment.
;
	mov	cl,4
	mov	ax,offset FAT_BUFHDR
	shr	ax,cl
	mov	es:[buf_head],ax
	mov	dx,offset DIR_BUFHDR
	shr	dx,cl

	DBGINIT	STRUCT,[FAT_BUFHDR],BUF
	mov	[FAT_BUFHDR].BUF_PREV,dx
	mov	[FAT_BUFHDR].BUF_NEXT,dx
	mov	[FAT_BUFHDR].BUF_SIZE,512

	DBGINIT	STRUCT,[DIR_BUFHDR],BUF
	mov	[DIR_BUFHDR].BUF_PREV,ax
	mov	[DIR_BUFHDR].BUF_NEXT,ax
	mov	[DIR_BUFHDR].BUF_SIZE,512

	push	[FDC_DEVICE].SEG	; save FDC pointer on stack
	push	[FDC_DEVICE].OFF
	mov	al,[si].BPB_DRIVE	; use the BPB's own BPB_DRIVE #
	mov	ah,size BPBEX		; to determine the system BPB to update
	mul	ah
	mov	di,es:[bpb_table].OFF
	add	di,ax
	cmp	di,es:[bpb_table].SEG
	jnb	si5
	mov	cx,(size BPB) SHR 1
	push	di
	rep	movsw
	pop	di
	push	es
	pop	ds
	ASSUME	DS:DOS
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is current tick count
	mov	[di].BPB_TIMESTAMP.OFF,dx
	mov	[di].BPB_TIMESTAMP.SEG,cx
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
	jnz	si4b			; make sure CLUSSECS is non-zero

sie0:	jmp	sysinit_error

si4b:	shr	al,1
	jc	si4c
	inc	cx
	jmp	si4b
si4c:	jnz	sie0			; hmm, CLUSSECS wasn't a power-of-two
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

	pop	ax			; restore FDC pointer in DX:AX
	pop	dx
	pop	cx			; restore # BPBs in CL
	mov	di,[bpb_table].OFF	; DI -> first BPB
si4d:	DBGINIT	STRUCT,[di],BPB
	mov	[di].BPB_DEVICE.OFF,ax
	mov	[di].BPB_DEVICE.SEG,dx
	cmp	[di].BPB_SECBYTES,0	; is this BPB initialized?
	jne	si4e			; yes
	mov	[di].BPB_DRIVE,ch	; no, fill in the drive #
si4e:	add	di,size BPBEX
	inc	ch
	dec	cl
	jnz	si4d

	pop	es
	ASSUME	ES:NOTHING
	push	cs
	pop	ds
	ASSUME	DS:DOS
;
; The next resident table (scb_table) contains our Session Control Blocks.
; Look for a "SESSIONS=" line in CFG_FILE.
;
si5:	mov	si,offset CFG_SESSIONS
	call	find_cfg		; look for "SESSIONS="
	jc	si6			; if not found, AX will be min value
	xchg	si,di
	push	es
	push	ds
	pop	es
	mov	bl,10			; BL = base 10
	DOSUTIL	ATOI16			; DS:SI -> string, ES:DI -> validation
	pop	es			; AX = new value
si6:	mov	dx,size SCB
	mov	bx,offset scb_table
	call	init_table		; initialize table, update ES
;
; The next resident table (sfb_table) contains our System File Blocks.
; Look for a "FILES=" line in CFG_FILE.
;
	mov	si,offset CFG_FILES
	call	find_cfg		; look for "FILES="
	jc	si7			; if not found, AX will be min value
	xchg	si,di
	push	es
	push	ds
	pop	es
	mov	bl,10			; BL = base 10
	DOSUTIL	ATOI16			; DS:SI -> string, ES:DI -> validation
	pop	es			; AX = new value
si7:	mov	dx,size SFB
	mov	bx,offset sfb_table
	call	init_table		; initialize table, update ES
;
; After all the resident tables have been created, initialize the MCB chain.
;
	mov	bx,es
	sub	di,di
	mov	al,MCBSIG_LAST
	stosb				; mov es:[MCB_SIG],MCBSIG_LAST
	sub	ax,ax
	stosw				; mov es:[MCB_OWNER],0
	mov	ax,[top_seg]
	sub	ax,bx			; AX = top segment - ES
	dec	ax			; AX reduced by 1 para (for MCB)
	stosw
	mov	cl,size MCB_RESERVED + size MCB_NAME
	mov	al,0
	rep	stosb

	mov	es,[dos_seg]		; mcb_head is in resident DOS segment
	ASSUME	ES:DOS
	mov	es:[mcb_head],bx
;
; Pre-initialize all the SCBs, by assigning them unique SCB_NUM values
; and setting their default CON/AUX/PRN system file handles to SFH_NONE (-1).
;
	mov	ah,SFH_NONE
	dec	cx			; CL,CH = SFH_NONE
	mov	bx,es:[scb_table].OFF
	push	bx			; initialize the SCBs
si7a:	ASSERT	<SCB_NUM + 1>,EQ,<SCB_SFHIN>
	mov	word ptr es:[bx].SCB_NUM,ax
	mov	word ptr es:[bx].SCB_SFHOUT,cx
	mov	word ptr es:[bx].SCB_SFHAUX,cx
	DBGINIT	STRUCT,es:[bx],SCB
	inc	ax
	add	bx,size SCB
	cmp	bx,es:[scb_table].SEG
	jb	si7a
	pop	bx
;
; Before we create any sessions (and our first PSPs), we need to open all the
; devices required for the 5 STD handles.  And we open AUX first, purely for
; historical reasons.
;
; Since no PSP exists yet, DOS_HDL_OPEN will return system file handles, not
; process file handles.  Which is exactly what we want, because we're going to
; store each SFH in the SCB, so that every time a new program is loaded in the
; SCB, its PSP will receive the same SFHs.
;
; In addition, DOS_HDL_OPEN returns the device context in DX (again, only
; because no process handle table exists when these handles are being opened).
;
	mov	dx,offset AUX_DEVICE
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jc	open_error
	mov	es:[bx].SCB_SFHAUX,al
	mov	cl,al			; CL = SFH for AUX
;
; Next, open CON, with optional context.  If there's a "CONSOLE=" setting in
; CFG_FILE, use that; otherwise, use CON_DEVICE.
;
si8:	mov	si,offset CFG_CONSOLE
	mov	dx,offset CON_DEVICE
	call	find_cfg		; look for "CONSOLE="
	jc	si9			; not found
	mov	dx,di
si9:	mov	ax,DOS_HDL_OPENRW
	int	21h
	jc	open_error
	mov	es:[bx].SCB_SFHIN,al	; AL = SFH (not PFH)
	mov	es:[bx].SCB_SFHOUT,al	; AL = SFH (not PFH)
	mov	es:[bx].SCB_SFHERR,al	; AL = SFH (not PFH)
;
; Last but not least, open PRN.
;
	mov	dx,offset PRN_DEVICE
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jc	open_error
	mov	es:[bx].SCB_SFHPRN,al	; AL = SFH
	mov	ch,al			; CH = SFH for PRN
;
; See if there are any more CONSOLE contexts defined; if so, then for each
; one, open an CON handle, and record it in the next available SCB.  If there
; aren't enough SCBs or SFBs, then we've got a configuration error.
;
si10:	mov	si,offset CFG_CONSOLE
	call	find_cfg		; look for another "CONSOLE="
	jc	si12			; no more
	mov	dx,di
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jc	open_error
	add	bx,size SCB
	cmp	bx,es:[scb_table].SEG
	jb	si11
	mov	dx,offset CONERR
	jmp	print_error
si11:	mov	es:[bx].SCB_SFHIN,al
	mov	es:[bx].SCB_SFHOUT,al
	mov	es:[bx].SCB_SFHERR,al
	mov	word ptr es:[bx].SCB_SFHAUX,cx
	ASSERT	<SCB_SFHAUX + 1>,EQ,<SCB_SFHPRN>
	jmp	si10

	DEFLBL	open_error,near
	PRINTF	<"Error opening %s: %d">,dx,ax
	jmp	fatal_error

si12:	mov	si,offset CFG_DEBUG
	call	find_cfg		; look for "DEBUG="
	jc	si13			; not found
	mov	dx,di
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jc	si13
	mov	es:[sfh_debug],al	; save SFH for DEBUG device

si13:	cmp	word ptr es:[key_boot],0
	jne	si14			; skip if key_boot is already set
	mov	si,offset CFG_BOOTKEY
	call	find_cfg		; look for "BOOTKEY="
	jc	si14
	mov	al,[di]
	mov	byte ptr es:[key_boot],al
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
	sub	sp,size SPB		; alloc SPB from the stack

	sub	dx,dx			; DX = SCB load count
	mov	bx,offset SHELL_FILE	; BX = default shell
si15:	mov	si,offset CFG_SHELL
	call	find_cfg		; look for "SHELL="
	jc	si16			; not found
	mov	bx,di
si16:	test	bx,bx			; do we still have a default?
	jz	si20			; no, done loading
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

si18:	PRINTF	<"Error loading %s: %d",13,10>,dx,ax
	jmp	si17
;
; Although it may appear every SCB was started immediately after loading,
; nothing can ACTUALLY run until we obtain access to the CLOCK$ device and
; re-vector all the hardware interrupt handlers that drive our scheduler.
;
si20:	add	sp,size SPB		; free SPB on the stack
					; (somewhat moot, but let's stay tidy)

	lds	dx,[pCacheInt21]	; restore INT 21h vector
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 21h
	int	21h
	push	cs
	pop	ds

	test	dx,dx
	jz	sie2			; if no SCBs loaded, that's not good
;
; Functions like SLEEP need access to the clock device, so we save its
; address in clk_ptr.  While we could open the device normally and obtain a
; system file handle, that would require the utility functions to use SFB
; interfaces (sfb_get, sfb_read, etc) with absolutely no benefit.
;
	mov	dx,offset CLK_DEVICE
	DOSUTIL	GETDEV
	jc	sie1
	mov	ds,[dos_seg]
	mov	[clk_ptr].OFF,di
	mov	[clk_ptr].SEG,es
;
; Last but not least, "revector" the DDINT_ENTER and DDINT_LEAVE handlers to
; dos_ddint_enter and dos_ddint_leave.
;
	sub	ax,ax
	mov	es,ax
	ASSUME	ES:BIOS
	cli
	mov	di,offset DDINT_ENTER
	mov	al,OP_JMPF
	stosb
	mov	ax,offset dos_ddint_enter
	stosw
	mov	ax,ds
	stosw
	mov	al,OP_JMPF
	stosb
	mov	ax,offset dos_ddint_leave
	stosw
	mov	ax,ds
	stosw
	sti
;
; We're done.  On the next clock tick, scb_yield will switch to one of the
; SCBs we started, and it will never return here, because sysinit has no SCB.
;
si99:	jmp	si99

sie1:	jmp	open_error

sie2:	jmp	sysinit_error

ENDPROC	sysinit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_cfg
;
; Search for length-prefixed string at SI in CFG_FILE, and if found,
; set DI to 1st character after match.
;
; Outputs:
;	Carry clear on success (DI -> 1st character after match)
;	Carry set on failure (AX = default value following string at SI)
;
; Modifies:
;	AX, SI, DI
;
DEFPROC	find_cfg
	ASSUME	DS:DOS, ES:NOTHING
	push	bx
	push	cx
	push	dx
	push	es
	push	ds
	pop	es
	ASSUME	ES:DOS
	mov	bx,si
	mov	di,[cfg_data]		; DI points to CFG_FILE data
	mov	dx,di
	add	dx,[cfg_size]		; DX points to end of CFG_FILE data
fc1:	lodsb				; 1st byte at SI is length
	cbw
	xchg	cx,ax			; CX = length of string to find
	repe	cmpsb
	jne	fc2
	mov	es:[di-1],cl		; zap the CFG match to prevent reuse
	jmp	short fc9		; found it!
fc2:	add	si,cx			; move SI forward to the minimum value
	mov	al,0Ah			; LINEFEED
	mov	cx,dx
	sub	cx,di			; CX = bytes left to search
	jb	fc8			; ran out
	repne	scasb
	stc
	jne	fc8			; couldn't find another LINEFEED
	mov	si,bx
	jmp	fc1
fc8:	mov	ax,[si]			; return the minimum value at SI
fc9:	pop	es
	ASSUME	ES:NOTHING
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	find_cfg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_table
;
; Initializes table with AX entries of length DX at ES:0, stores DS-relative
; table offset at [BX], table limit at [BX+2], and finally, adjusts ES.
;
; Outputs:
;	Nothing
;
; Modifies: CX, DX, DI
;
DEFPROC	init_table
	ASSUME	DS:NOTHING, ES:NOTHING
	push	ax
	mul	dx			; AX = length of table in bytes
	xchg	cx,ax			; CX = length
	sub	di,di
	mov	ax,di
	rep	stosb			; zero the table
	push	ds
	mov	ds,[dos_seg]
	mov	ax,es
	mov	dx,ds
	sub	ax,dx			; AX = distance from DS:0 in paras
	mov	dx,ax			; save for DS overflow check
	mov	cl,4
	shl	ax,cl			; AX = DS-relative offset
	mov	[bx].OFF,ax		; save DS-relative offset
	add	ax,di
	mov	[bx].SEG,ax		; save DS-relative limit
	pop	ds
	add	di,15
	mov	cl,4
	shr	di,cl			; DI = length of table in paras
	add	dx,di			; check for DS overflow
	cmp	dx,1000h		; have we exceeded the DS 64K limit?
	ja	sie2			; yes, sadly
	mov	ax,es
	add	ax,di
	mov	es,ax			; ES = next available paragraph
	pop	ax
	ret
ENDPROC	init_table

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cache_int21
;
; The sole purpose of this function is to intercept OPEN and READ requests
; that occur during our DOSUTIL LOAD operations, which we also know will be
; completely sequential (and therefore our caching logic can be very simple).
;
; This allows us to preload multiple copies of COMMAND.COM into memory without
; having to reread the file from disk every time.
;
; Inputs:
;	AH = DOS function #
;
; Outputs:
;	Varies (function-specific)
;
DEFPROC	cache_int21,FAR
	cmp	ah,DOS_HDL_OPEN
	jne	ci2

	push	ax
	push	cx
	push	si
	push	di
	push	es
	mov	si,dx
	sub	ax,ax
	mov	[pCacheActive].OFF,ax	; no active cache data yet
	DOSUTIL	STRLEN			; AX = length of string at DS:SI
	xchg	cx,ax			; CX = length
	les	di,[pCacheFile]		; ES:DI -> previous filename, if any
	test	di,di			; is there a previous filename?
	jz	ci1			; no
	repe	cmpsb			; does previous filename match current?
	jne	ci1			; no
	mov	ax,[pCacheData].OFF	; yes, init active cache data
	mov	[pCacheActive].OFF,ax
	mov	ax,[pCacheData].SEG
	mov	[pCacheActive].SEG,ax
	mov	ax,[cbCacheData]
	mov	[cbCacheActive],ax
ci1:	mov	[pCacheFile].OFF,dx	; in any case, remember this filename
	mov	[pCacheFile].SEG,ds
	pop	es
	pop	di
	pop	si
	pop	cx
	pop	ax
	jmp	short ci9

ci2:	cmp	ah,DOS_HDL_READ
	jne	ci9

	push	cx
	push	si
	push	di
	push	ds
	push	es
	push	ds
	pop	es
	mov	di,dx			; ES:DI -> destination
	lds	si,[pCacheActive]	; DS:SI -> source data
	test	si,si			; does any source data exist?
	stc
	jz	ci8			; no
	mov	ax,cx			; AX = # bytes to copy
	cmp	ax,[cbCacheActive]	; do we have as much data as requested?
	jbe	ci3			; yes
	mov	ax,[cbCacheActive]	; no
ci3:	mov	cx,ax
	rep	movsb
	sub	[cbCacheActive],ax
	add	[pCacheActive].OFF,ax
	ASSERT	NC
ci8:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	cx
	jnc	ci10

ci9:	pushf
	call	[pCacheInt21]
ci10:	ret	2
ENDPROC	cache_int21

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
	mov	ah,DOS_TTY_PRINT
	int	21h
	jmp	$			; "halt"
;
; Initialization data
;
; Labels are capitalized to indicate their static (constant) nature.
;
	DEFLBL	INT_TABLES,word
	dw	(INT_DV * 4)		; set diverr and single-step vectors
	dw	dos_dverr,dos_sstep,0
	dw	(INT_BP * 4)		; set breakpoint and overflow vectors
	dw	dos_brkpt,dos_oferr,0
	dw	(INT_UD * 4)		; initialize the INT_UD vector
	dw	dos_opchk,0		; in case the OPCHECK macro is enabled
	dw	(INT_DOSTERM * 4)	; next, set all the DOS vectors
	dw	dos_term,dos_func,dos_exret,dos_ctrlc
	dw	dos_error,disk_read,disk_write,dos_tsr,dos_default,0
	dw	(INT_DOSNET * 4)
	dw	dos_default,dos_default,dos_default
	dw	dos_default,dos_default,dos_default,0
	dw	-1			; end of tables (should end at INT 30h)
	DEFLBL	INT_TABLES_END

CFG_BOOTKEY	db	8,"BOOTKEY="
CFG_CONSOLE	db	8,"CONSOLE="
CON_DEVICE	db	"CON:80,25",0	; default CONSOLE configuration
CFG_DEBUG	db	6,"DEBUG="	; used to specify DEBUG device
CFG_FILES	db	6,"FILES="
		dw	20,8,255
CFG_MEMSIZE	db	8,"MEMSIZE="
		dw	640,16,640
CFG_SESSIONS	db	9,"SESSIONS="
		dw	4,1,32		; TODO: Decide if 32 session limit OK
CFG_SHELL	db	6,"SHELL="
CFG_SWITCHAR	db	9,"SWITCHAR="

AUX_DEVICE	db	"AUX",0
PRN_DEVICE	db	"PRN",0
CLK_DEVICE	db	"CLOCK$",0
SHELL_FILE	db	"COMMAND.COM",0	; default SHELL file

SYS_MSG		db	"BASIC-DOS "
		VERSION_STR
		db	" for the IBM PC",13,10
		db	"Copyright (c) PCJS.ORG 1981-2021",13,10,13,10,'$'

SYSERR		db	"System initialization error$"
CONERR		db	"More CONSOLES than SESSIONS$"
HALTED		db	"; halted$"

	DEFLBL	sysinit_end

DOS	ends

	end
