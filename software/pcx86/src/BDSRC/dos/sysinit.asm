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

	EXTERNS	<mcb_head,mcb_limit,scb_active,psp_active>,word
	EXTERNS	<bpb_table,scb_table,sfb_table>,dword
	EXTERNS	<dos_dverr,dos_sstep,dos_brkpt,dos_oferr>,near
	EXTERNS	<dos_term,dos_func,dos_default>,near
	EXTERNS	<disk_read,disk_write,dos_tsr,dos_call5>,near

	DEFLBL	sysinit_start

	DEFWORD	bpb_off
	DEFWORD	dos_seg
	DEFWORD	top_seg
	DEFWORD	cfg_data
	DEFWORD	cfg_size

	ASSUME	CS:DOS, DS:BIOS, ES:DOS, SS:BIOS

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
	mov	ax,offset si2
	push	ax			; push new offset on stack
	ret
;
; Initialize all the DOS vectors, while DS is still dos_seg and ES is BIOS.
;
si2:	push	ss
	pop	es
	ASSUME	ES:BIOS
	mov	si,offset INT_TABLES
si2a:	lodsw
	test	ax,ax			; any more tables?
	jz	si3a			; no
	and	al,0FEh
	xchg	di,ax			; DI -> first vector for table
si3:	lodsw				; load vector offset
	test	ax,ax
	jz	si2a
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
; TODO: At some point, we're going to want a buffer cache.  But for now,
; we at least need to make sure FAT_BUFHDR and DIR_BUFHDR are initialized
; enough to be usable.
;
	mov	[FAT_BUFHDR].BUF_SIZE,512
	mov	[DIR_BUFHDR].BUF_SIZE,512
;
; Now set ES to the first available paragraph for resident DOS tables,
; and set DS to the upper DOS segment.
;
si4:	mov	ax,offset sysinit_start
	test	al,0Fh			; started on a paragraph boundary?
	jz	si4a			; yes
	inc	dx			; no, so skip to next paragraph
si4a:	mov	ax,ds
	add	ax,dx
	mov	es,ax			; ES = first free (low) paragraph
	ASSUME	ES:NOTHING
	push	cs
	pop	ds
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
	mov	al,ss:[si].BPB_DRIVE	; and copy to the appropriate BPB slot
	mov	ah,size BPBEX
	mul	ah
	mov	di,es:[bpb_table].off
	add	di,ax
	cmp	di,es:[bpb_table].seg
	jnb	si5
	mov	cx,(size BPB) SHR 1
	push	di
	rep	movs word ptr es:[di],word ptr ss:[si]
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
si4c:	jmp	sysinit_error
si4d:	shr	al,1
	jc	si4e
	inc	cx
	jmp	si4d
si4e:	jnz	si4c			; hmm, CLUSSECS wasn't a power-of-two
	mov	es:[di].BPB_CLUSLOG2,cl
	mov	ax,es:[di].BPB_SECBYTES	; use that to also calculate CLUSBYTES
	shl	ax,cl
	mov	es:[di].BPB_CLUSBYTES,ax
	pop	es
	ASSUME	ES:NOTHING
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
	mov	es:[scb_active],bx	; BX = 1st SCB (and now the active SCB)
;
; Before we create the first PSP, open all the devices we need for the 5
; STD handles.  We open AUX first, purely for historical reasons.
;
; And note that since we have no PSP yet, DOS_HDL_OPEN will be returning system
; handles, not process handles.
;
	mov	dx,offset AUX_DEFAULT
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	jc	dierr
	mov	es:[bx].SCB_SFHAUX,al
;
; Next, open CON, with optional context.  If there's a "CONSOLE=" setting in
; CFG_FILE, use that; otherwise, use CON_DEFAULT.
;
si8:	mov	si,offset CFG_CONSOLE
	mov	dx,offset CON_DEFAULT
	call	find_cfg		; look for "CONSOLE="
	jc	si8a			; not found
	mov	dx,di
si8a:	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	jnc	si9
dierr:	mov	si,dx
	mov	ax,DOS_UTIL_STRLEN
	int	21h
	xchg	bx,ax
	mov	byte ptr [si+bx],'$'
	mov	dx,si
	call	print_error
	mov	dx,offset DEVERR
	jmp	fatal_error
sierr:	jmp	sysinit_error

si9:	mov	es:[bx].SCB_SFHCON,al

	mov	dx,offset PRN_DEFAULT
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	jc	dierr
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
	jc	dierr
	add	bx,size SCB
	cmp	bx,es:[scb_table].seg
	jb	si11
	mov	dx,offset CONERR
	jmp	fatal_error
si11:	mov	es:[bx].SCB_SFHCON,al
	jmp	si10
;
; Create the first PSP.  Until we have the ability to create a process from
; a COM or EXE file, this will serve as our "shell" process.
;
si12:	mov	bx,100h			; we'll start with a safe 4K for now
	mov	ah,DOS_MEM_ALLOC
	int	21h
	jc	sierr			; hmmm, guess it wasn't safe after all

	xchg	dx,ax			; DX = segment for new PSP
	mov	ah,DOS_PSP_CREATE
	int	21h

	mov	bx,dx			; and of course, this PSP function
	mov	ah,DOS_PSP_SET		; wants the segment in BX, not DX....
	int	21h			; active PSP updated

	IFDEF	DEBUG
	;
	; Perform some simple console I/O tests
	;
	mov	si,offset CON_TEST
	mov	ax,DOS_UTIL_STRLEN
	int	21h
	xchg	cx,ax			; CX = length of CON_TEST
	mov	dx,si			; DS:DX -> CON_TEST
	mov	bx,STDOUT		; BX = handle
	mov	ah,DOS_HDL_WRITE
	int	21h			; write the string to STDOUT
	mov	dx,offset PRINT_TEST
	mov	ah,DOS_TTY_PRINT
	int	21h
	;
	; Perform a few simple memory ALLOC/FREE "confidence" tests
	;
	push	es
	mov	ah,DOS_MEM_ALLOC
	mov	bx,200h
	int	21h
	jc	dsierr
	xchg	cx,ax			; CX = 1st segment
	mov	ah,DOS_MEM_ALLOC
	mov	bx,200h
	int	21h
	jc	dsierr
	xchg	dx,ax			; DX = 2nd segment
	mov	ah,DOS_MEM_ALLOC
	mov	bx,200h
	int	21h
	jc	dsierr
	xchg	si,ax			; SI = 3rd segment
	mov	ah,DOS_MEM_FREE
	mov	es,cx			; free the 1st
	int	21h
	jc	dsierr
	mov	ah,DOS_MEM_FREE
	mov	es,si
	int	21h			; free the 3rd
	jc	dsierr
	mov	ah,DOS_MEM_FREE
	mov	es,dx
	int	21h			; free the 2nd
	jc	dsierr
	pop	es
	mov	dx,offset COM1_DEFAULT
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	jc	dsierr
	mov	dx,offset COM2_DEFAULT
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	mov	dx,offset TEST_FILE
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h
	jc	dsierr
	xchg	bx,ax
	mov	dx,offset INT_TABLES
	mov	cx,offset INT_TABLES_END - offset INT_TABLES
	mov	ah,DOS_HDL_READ
	int	21h
	jnc	si99
dsierr:	jmp	sysinit_error
	ENDIF

si99:	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is tick count
	PRINTF	<"hello world, the time is %ld",13,10>,dx,cx

si199:	jmp	si199
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
; table offset at [BX], number of entries at [BX], and adjust ES.
;
; Returns: Nothing
;
; Modifies: AX, CX, DX, DI
;
DEFPROC	init_table
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
; print_error (print generic error message)
;
; Inputs:
;	DX -> message
;
; Modifies:
;	AX, DS
;
DEFPROC	print_error
	mov	ah,DOS_TTY_PRINT
	int	21h
	ret
ENDPROC	print_error

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
; fatal_error (print specified error message and halt)
;
; Inputs:
;	DX -> message
;
; Outputs:
;	None (system halted)
;
DEFPROC	fatal_error,near
	push	cs
	pop	ds
	call	print_error
	mov	dx,offset HALTED
	call	print_error
	jmp	$			; "halt"
ENDPROC	fatal_error

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
AUX_DEFAULT	db	"AUX",0
CON_DEFAULT	db	"CON:80,25",0	; default CONSOLE configuration
PRN_DEFAULT	db	"PRN",0

	IFDEF	DEBUG
COM1_DEFAULT	db	"COM1:9600,N,8,1",0
COM2_DEFAULT	db	"COM2:9600,N,8,1",0
CON_TEST	db	"CONSOLE ready",13,10,0
PRINT_TEST	db	"DOS interface ready",13,10,'$'
TEST_FILE	db	"A:HANDLE.ASM",0
	ENDIF

SYSERR		db	"System initialization error$"
DEVERR		db	" device error$"
HALTED		db	"; halted$"
CONERR		db	"More CONSOLES than SESSIONS$"

	DEFLBL	sysinit_end

DOS	ends

	end
