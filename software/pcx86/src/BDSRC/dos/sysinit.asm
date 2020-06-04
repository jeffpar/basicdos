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

	EXTERNS	<MCB_HEAD,SFB_SYSCON>,word
	EXTERNS	<BPB_TABLE,PCB_TABLE,SFB_TABLE>,dword
	EXTERNS	<dosexit,dosfunc,dos_return>,near
	EXTERNS	<sfb_open,sfb_write>,near

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
; To simplify use of the CFG data, replace all line endings with zeros.
;
	mov	di,bx
	mov	cx,dx
	mov	al,0Ah
si0:	repne	scasb
	jcxz	si1
	mov	byte ptr [di-1],0
	cmp	byte ptr [di-2],0Dh
	jne	si0
	cmp	byte ptr [di-2],0
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
	mov	si,offset int_tbl
	mov	di,INT_DOSEXIT * 4
si3:	lodsw				; load vector offset
	test	ax,ax
	jz	si4
	stosw				; store vector offset
	mov	ax,ds
	stosw				; store vector segment
	jmp	si3
;
; Now set ES to the first available paragraph for resident DOS tables,
; and set DS to the upper DOS segment.
;
si4:	mov	ax,offset sysinit_start
	test	al,0Fh			; started on a paragraph boundary?
	jz	si5			; yes
	inc	dx			; no, so skip to next paragraph
si4a:	mov	ax,ds
	add	ax,dx
	mov	es,ax			; ES = first free (low) paragraph
	ASSUME	ES:NOTHING
	push	cs
	pop	ds
;
; The first resident table (BPB_TABLE) contains all the system BPBs.
;
	mov	al,[FDC_UNITS]
	cbw
	mov	dx,size BPBEX
	mov	bx,offset BPB_TABLE
	call	init_table		; initialize table, update ES
	mov	si,[bpb_off]		; get the BPB the boot sector used
	push	es
	mov	es,[dos_seg]
	ASSUME	ES:DOS
	mov	al,ss:[si].BPB_DRIVE	; and copy to the appropriate BPB slot
	mov	ah,size BPBEX
	mul	ah
	mov	di,es:[BPB_TABLE].off
	add	di,ax
	cmp	di,es:[BPB_TABLE].seg
	jnb	si5
	mov	cx,(size BPB) SHR 1
	rep	movs word ptr es:[di],word ptr ss:[si]
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is current tick count
	mov	es:[di].BPB_TIMESTAMP.off,dx
	mov	es:[di].BPB_TIMESTAMP.seg,cx
	pop	es
	ASSUME	ES:NOTHING
;
; The next resident table (PCB_TABLE) contains our Process Control Blocks.
; Look for a "PCBS=" line in CFG_FILE.
;
si5:	mov	si,offset CFG_PCBS
	call	find_cfg		; look for "PCBS="
	jc	si6			; if not found, AX will be min value
	push	es
	push	ds
	pop	es			; ES:DI -> string, DS:SI -> validation
	mov	ax,DOSUTIL_DECIMAL
	int	INT_DOSFUNC		; AX = new value
	pop	es
si6:	mov	dx,size PCB
	mov	bx,offset PCB_TABLE
	call	init_table		; initialize table, update ES
;
; The next resident table (SFB_TABLE) contains our System File Blocks.
; Look for a "FILES=" line in CFG_FILE.
;
	mov	si,offset CFG_FILES
	call	find_cfg		; look for "FILES="
	jc	si7			; if not found, AX will be min value
	push	es
	push	ds
	pop	es			; ES:DI -> string, DS:SI -> validation
	mov	ax,DOSUTIL_DECIMAL
	int	INT_DOSFUNC		; AX = new value
	pop	es
si7:	mov	dx,size SFB
	mov	bx,offset SFB_TABLE
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

	mov	es,[dos_seg]		; MCB_HEAD is in resident DOS segment
	ASSUME	ES:DOS
	mov	es:[MCB_HEAD],bx
;
; Allocate some memory for an initial (test) process
;
	IFDEF	DEBUG
	push	es
	mov	ah,DOS_ALLOC
	mov	bx,200h
	int	INT_DOSFUNC
	jc	dsierr
	xchg	cx,ax			; CX = 1st segment
	mov	ah,DOS_ALLOC
	mov	bx,200h
	int	INT_DOSFUNC
	jc	dsierr
	xchg	dx,ax			; DX = 2nd segment
	mov	ah,DOS_ALLOC
	mov	bx,200h
	int	INT_DOSFUNC
	jc	dsierr
	xchg	si,ax			; SI = 3rd segment
	mov	ah,DOS_FREE
	mov	es,cx			; free the 1st
	int	INT_DOSFUNC
	jc	dsierr
	mov	ah,DOS_FREE
	mov	es,si
	int	INT_DOSFUNC		; free the 3rd
	jc	dsierr
	mov	ah,DOS_FREE
	mov	es,dx
	int	INT_DOSFUNC		; free the 2nd
	jnc	dsiend
dsierr:	jmp	sysinit_error
dsiend:	pop	es
	ENDIF
;
; Open CON with context.  If there's a "CONSOLE=" setting in CFG_FILE,
; use that; otherwise, use CON_DEFAULT.
;
si8:	mov	si,offset CFG_CONSOLE
	mov	dx,offset CON_DEFAULT
	call	find_cfg		; look for "CONSOLE="
	jc	si9			; not found
	mov	dx,di
si9:	mov	bl,MODE_ACC_BOTH
	mov	si,dx
	mov	ax,offset sfb_open
	call	dos_call
	jnc	si10
	mov	si,offset conerr
	jmp	fatal_error
si10:	mov	es:[SFB_SYSCON],bx

	IFDEF	DEBUG
	mov	bl,MODE_ACC_BOTH
	mov	si,offset COM1_DEFAULT
	mov	ax,offset sfb_open
	call	dos_call
	mov	bl,MODE_ACC_BOTH
	mov	si,offset COM2_DEFAULT
	mov	ax,offset sfb_open
	call	dos_call
	mov	bx,es:[SFB_SYSCON]
	mov	si,offset con_test
	mov	ax,DOSUTIL_STRLEN
	int	INT_DOSFUNC
	xchg	cx,ax
	mov	ax,offset sfb_write
	call	dos_call
	ENDIF

si99:	jmp	si99
ENDPROC	sysinit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Call resident DOS procedure at AX.
;
DEFPROC	dos_call
	push	bp
	push	es
	push	cs
	mov	bp,offset dc9
	push	bp
	mov	bp,offset dos_return
	push	bp
	push	[dos_seg]
	push	ax
	mov	es,[dos_seg]
	db	0CBh			; RETF
dc9:	pop	es
	pop	bp
	ret
ENDPROC	dos_call

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
	je	fc9			; found it!
	add	si,cx			; move SI forward to the minimum value
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
; Print the null-terminated string at SI and halt
;
; Returns: Nothing
;
; Modifies: AX, BX, SI
;
DEFPROC	sysinit_error
	mov	si,offset syserr
DEFLBL	fatal_error,near
	call	sysinit_print
	mov	si,offset halted
	call	sysinit_print
	jmp	$
ENDPROC	sysinit_error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Print the null-terminated string at SI
;
; Returns: Nothing
;
; Modifies: AX, BX, SI
;
DEFPROC	sysinit_print
	lods	byte ptr cs:[si]
	test	al,al
	jz	sip9
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	jmp	sysinit_print
sip9:	ret
ENDPROC	sysinit_print

;
; Initialization data
;
	DEFWORD	int_tbl,<dosexit,dosfunc,0>

CFG_PCBS	db	5,"PCBS="
		dw	4,16
CFG_FILES	db	6,"FILES="
		dw	20,256
CFG_CONSOLE	db	8,"CONSOLE=",
		dw	4,25, 16,80
CON_DEFAULT	db	"CON:25,80",0

	IFDEF	DEBUG
COM1_DEFAULT	db	"COM1:9600,N,8,1",0
COM2_DEFAULT	db	"COM2:9600,N,8,1",0
con_test	db	"This is a test of the CON device driver",13,10,0
	ENDIF

syserr	db	"System initialization error",0
conerr	db	"Unable to initialize console",0
halted	db	", halted",0

	DEFLBL	sysinit_end

DOS	ends

	end
