;
; BASIC-DOS System Initialization
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<mcb_head,mcb_limit>,word
	EXTERNS	<bpb_table,scb_table,sfb_table,clk_ptr>,dword
	EXTERNS	<dos_dverr,dos_sstep,dos_brkpt,dos_oferr>,near
	EXTERNS	<dos_term,dos_func,dos_default>,near
	EXTERNS	<disk_read,disk_write,dos_tsr,dos_call5>,near

	DEFLBL	sysinit_start

	DEFWORD	bpb_off
	DEFWORD	dos_seg
	DEFWORD	top_seg
	DEFWORD	cfg_data
	DEFWORD	cfg_size

	ASSUME	CS:DOS, DS:BIOS, ES:DOS, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
; Initialize all the DOS vectors, while DS is still dos_seg and ES is BIOS.
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
	mov	es,cx
	ASSUME	ES:BIOS
	mov	si,offset INT_TABLES
si2:	lodsw
	test	ax,ax			; any more tables?
	jz	si3a			; no
	and	al,0FEh
	xchg	di,ax			; DI -> first vector for table
si3:	lodsw				; load vector offset
	test	ax,ax
	jz	si2
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
; TODO: At some point, we're going to want a buffer cache.  But for now,
; we at least need to make sure FAT_BUFHDR and DIR_BUFHDR are initialized
; enough to be usable.
;
	mov	[FAT_BUFHDR].BUF_SIZE,512
	mov	[DIR_BUFHDR].BUF_SIZE,512
;
; The first resident table (bpb_table) contains all the system BPBs.
;
	mov	al,[FDC_UNITS]
	cbw
	mov	dx,size BPBEX
	mov	bx,offset bpb_table
	call	init_table		; initialize table, update ES
	mov	si,[bpb_off]		; get the BPB the boot sector used

	push	es
	mov	es,[dos_seg]
	ASSUME	ES:DOS
	mov	al,[si].BPB_DRIVE	; and copy to the appropriate BPB slot
	mov	ah,size BPBEX
	mul	ah
	mov	di,es:[bpb_table].off
	add	di,ax
	cmp	di,es:[bpb_table].seg
	jnb	si5
	mov	cx,(size BPB) SHR 1
	push	di
	rep	movsw
	pop	di
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is current tick count
	mov	es:[di].BPB_TIMESTAMP.off,dx
	mov	es:[di].BPB_TIMESTAMP.seg,cx
;
; Initialize all the BPBEX fields, like BPB_DEVICE and BPB_UNIT, as well as
; pre-calculated values like BPB_CLOSLOG2 and BPB_CLUSBYTES.
;
; TODO: Move this BPB initialization code into a DOS function that we can call
; later, because even though we've allocated BPBs for all the FDC units, the
; only *real* BPB among them currently is the one we booted with.
;
	mov	ax,[FDC_DEVICE].off
	mov	dx,[FDC_DEVICE].seg
	mov	es:[di].BPB_DEVICE.off,ax
	mov	es:[di].BPB_DEVICE.seg,dx
	mov	al,es:[di].BPB_DRIVE
	mov	es:[di].BPB_UNIT,al
	sub	cx,cx
	mov	al,es:[di].BPB_CLUSSECS	; calculate LOG2 of CLUSSECS in CX
	test	al,al
	jnz	si4d			; make sure CLUSSECS is non-zero

sierr1:	jmp	sysinit_error

si4d:	shr	al,1
	jc	si4e
	inc	cx
	jmp	si4d
si4e:	jnz	sierr1			; hmm, CLUSSECS wasn't a power-of-two
	mov	es:[di].BPB_CLUSLOG2,cl
	mov	ax,es:[di].BPB_SECBYTES	; use that to also calculate CLUSBYTES
	shl	ax,cl
	mov	es:[di].BPB_CLUSBYTES,ax
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
	mov	ax,DOS_UTIL_ATOI	; DS:SI -> string, ES:DI -> validation
	int	21h			; AX = new value
	pop	es
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
	mov	ax,DOS_UTIL_ATOI	; DS:SI -> string, ES:DI -> validation
	int	21h			; AX = new value
	pop	es
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
	mov	cl,size MCB_RESERVED
	mov	al,0
	rep	stosb

	mov	es,[dos_seg]		; mcb_head is in resident DOS segment
	ASSUME	ES:DOS
	mov	es:[mcb_head],bx

	mov	bx,es:[scb_table].off
	or	es:[bx].SCB_STATUS,SCSTAT_INIT
;
; Before we create the first PSP, open all the devices we need for the 5
; STD handles.  We open AUX first, purely for historical reasons.
;
; And note that since we have no PSP yet, DOS_HDL_OPEN will return system
; handles, not process handles.
;
	mov	dx,offset AUX_DEVICE
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	jc	open_error
	mov	es:[bx].SCB_SFHAUX,al
;
; Next, open CON, with optional context.  If there's a "CONSOLE=" setting in
; CFG_FILE, use that; otherwise, use CON_DEVICE.
;
si8:	mov	si,offset CFG_CONSOLE
	mov	dx,offset CON_DEVICE
	call	find_cfg		; look for "CONSOLE="
	jc	si9			; not found
	mov	dx,di
si9:	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	jc	open_error
	mov	es:[bx].SCB_SFHCON,al
	INIT_STRUC es:[bx],SCB

	mov	dx,offset PRN_DEVICE
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	jc	open_error
	mov	es:[bx].SCB_SFHPRN,al
;
; See if there are any more CONSOLE contexts defined; if so, then for each
; one, open an CON handle, and record it in the next available SCB.  If there
; aren't enough SCBs, then we've got a configuration error.
;
si10:	mov	si,offset CFG_CONSOLE
	call	find_cfg		; look for another "CONSOLE="
	jc	si12			; no more
	mov	dx,di
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	jc	open_error
	add	bx,size SCB
	cmp	bx,es:[scb_table].seg
	jb	si11
	mov	dx,offset CONERR
	jmp	print_error
si11:	or	es:[bx].SCB_STATUS,SCSTAT_INIT
	mov	es:[bx].SCB_SFHCON,al
	mov	word ptr es:[bx].SCB_SFHAUX,(SFH_NONE SHL 8) OR SFH_NONE
	ASSERT	<SCB_SFHAUX + 1>,EQ,<SCB_SFHPRN>
	INIT_STRUC es:[bx],SCB
	jmp	si10

	DEFLBL	open_error,near
	PRINTF	<"%s open error %d">,dx,ax
	jmp	fatal_error
;
; Utility functions like SLEEP need access to specific drivers, and while we
; could open them as system file handles, that would require utility functions
; to use SFB interfaces (get_sfb, sfb_read, etc) with absolutely no benefit.
;
si12:	push	es
	mov	dx,offset CLK_DEVICE
	mov	ax,DOS_UTIL_GETDEV
	int	21h
	mov	dx,es
	jc	si13
	mov	ax,DOS_UTIL_IOCTL	; inform the CLOCK driver we're ready
	mov	bx,(DDC_IOCTLIN SHL 8) OR CLKIO_INIT
	int	21h
si13:	pop	es
	jc	open_error
	mov	es:[clk_ptr].off,di
	mov	es:[clk_ptr].seg,dx

	mov	dx,offset SYS_MSG
	mov	ah,DOS_TTY_PRINT
	int	21h

	IFDEF	DEBUG
	mov	ah,DOS_MEM_ALLOC
	mov	bx,200h
	int	21h
	jc	dierr1
	xchg	cx,ax			; CX = 1st segment
	mov	es,cx
	mov	bx,400h			; make the 1st segment larger
	mov	ah,DOS_MEM_REALLOC
	int	21h
	jc	dierr1
	mov	ah,DOS_MEM_ALLOC
	mov	bx,200h
	int	21h
	jc	dierr1
	xchg	dx,ax			; DX = 2nd segment
	mov	es,dx
	mov	bx,100h			; make the 2nd segment smaller
	mov	ah,DOS_MEM_REALLOC
	int	21h
	jc	dierr1
	mov	ah,DOS_MEM_ALLOC
	mov	bx,200h
	int	21h
	jc	dierr1
	xchg	si,ax			; SI = 3rd segment
	mov	ah,DOS_MEM_FREE
	mov	es,cx			; free the 1st
	int	21h
dierr1:	jc	dierr2
	mov	ah,DOS_MEM_FREE
	mov	es,si
	int	21h			; free the 3rd
	jc	dierr2
	mov	ah,DOS_MEM_FREE
	mov	es,dx
	int	21h			; free the 2nd
	jc	dierr2
	mov	dx,offset COM1_DEVICE
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	jc	dierr2
	mov	dx,offset COM2_DEVICE
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	jc	dierr2
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is tick count
	mov	bx,offset hello
	PRINTF	<"%ls, the time is [%6ld]",13,10>,bx,cs,dx,cx
	jmp	short si14
hello	db	"hello world",0
dierr2:	jmp	sysinit_error

	ENDIF
;
; For each SHELL definition, load the corresponding file into the next
; available SCB.  The first time through, CFG_SHELL is used as a fallback,
; so even if there are no SHELL definitions, at least one will be loaded.
;
si14:	sub	cx,cx			; CL = SCB #
	mov	dx,offset SHELL_FILE
si16:	mov	si,offset CFG_SHELL
	call	find_cfg		; look for "SHELL="
	jc	si17			; not found
	mov	dx,di
si17:	test	dx,dx
	jz	si20
	mov	ax,DOS_UTIL_LOAD	; load SHELL DS:DX into specified SCB
	int	21h
	jnc	si18
	PRINTF	<'Error loading SHELL "%ls": %d',13,10>,dx,ds,ax
	jmp	short sierr2
si18:	inc	cx			; advance SCB #
	sub	dx,dx
	jmp	si16
;
; Start the first SCB; this should not return
;
si20:	sub	cx,cx
	mov	ax,DOS_UTIL_START
	int	21h

sierr2:	jmp	sysinit_error

ENDPROC	sysinit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Search for length-prefixed string at SI in CFG_FILE.
;
; Returns:
;	Carry clear on success (DI -> 1st character after match)
;	Carry set on failure (AX = minimum value from SI)
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
; Initialize table with AX entries of length DX at ES:0, store DS-relative
; table offset at [BX], table limit at [BX+2], and finally, adjust ES.
;
; Returns: Nothing
;
; Modifies: AX, CX, DX, DI
;
DEFPROC	init_table
	ASSUME	DS:NOTHING, ES:NOTHING
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
	mov	[bx].off,ax		; save DS-relative offset
	add	ax,di
	mov	[bx].seg,ax		; save DS-relative limit
	pop	ds
	add	di,15
	mov	cl,4
	shr	di,cl			; DI = length of table in paras
	add	dx,di			; check for DS overflow
	cmp	dx,1000h		; have we exceeded the DS 64K limit?
	ja	sysinit_error		; yes, sadly
	mov	ax,es
	add	ax,di
	mov	es,ax			; ES = next available paragraph
	ret
ENDPROC	init_table

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
	dw	(INT_DV * 4) + 1	; add 1 to avoid end-of-tables signal
	dw	dos_dverr,dos_sstep,0
	dw	(INT_BP * 4)		; a few more low vectors
	dw	dos_brkpt,dos_oferr,0
	dw	(INT_DOSTERM * 4)	; next, all the DOS vectors
	dw	dos_term,dos_func,dos_default,dos_default
	dw	dos_default,disk_read,disk_write,dos_tsr,dos_default,0
	dw	(INT_DOSNET * 4)
	dw	dos_default,dos_default,dos_default,dos_default,dos_default,dos_default,0
	dw	0			; end of tables (should end at INT 30h)
	DEFLBL	INT_TABLES_END

CFG_SESSIONS	db	9,"SESSIONS="
		dw	4,16
CFG_FILES	db	6,"FILES="
		dw	20,256
CFG_CONSOLE	db	8,"CONSOLE=",
		dw	16,80, 4,25	; default CONSOLE parameters
CFG_SHELL	db	6,"SHELL=",

AUX_DEVICE	db	"AUX",0
CON_DEVICE	db	"CON:80,25",0	; default CONSOLE configuration
PRN_DEVICE	db	"PRN",0
CLK_DEVICE	db	"CLOCK$",0
SHELL_FILE	db	"COMMAND.COM",0	; default SHELL file

	IFDEF	DEBUG
COM1_DEVICE	db	"COM1:9600,N,8,1",0
COM2_DEVICE	db	"COM2:9600,N,8,1",0
SYS_MSG		db	"System ready",13,10,'$'
	ENDIF

SYSERR		db	"System initialization error$"
CONERR		db	"More CONSOLES than SESSIONS$"
HALTED		db	"; halted$"

	DEFLBL	sysinit_end

DOS	ends

	end
