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

	EXTERNS	<MCB_HEAD,PCB_TABLE,SFB_TABLE>,word
	EXTERNS	<dosexit,doscall>,near

	DEFLBL	sysinit_beg
	DEFWORD	dos_seg,word
	DEFWORD	top_seg,word
	DEFWORD	cfg_data,word
	DEFWORD	cfg_size,word

	ASSUME	CS:DOS, DS:BIOS, ES:BIOS, SS:BIOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; System initialization
;
; Everything after "sysinit_beg" will be recycled.
;
; Entry:
;	DS:BX -> CFG_FILE data, if any
;	DX = size of CFG_FILE data, if any
;
DEFPROC	sysinit,far
;
; Move all the init code/data out of the way, to top of available memory.
;
; Size is in Kb (2^10 units), we need size in paragraphs (2^4 units), so
; shift left 6 bits.  Then calculate init code size in paras and subtract.
;
	mov	ax,cs
	mov	[dos_seg],ax		; save the resident DOS segment
	mov	cl,4
	shl	ax,cl
	sub	bx,ax			; convert BX from BIOS to DOS offset
	cmp	bx,offset sysinit_end
	je	si1
	call	sysinit_error
si1:	mov	[cfg_data],bx		; offset of CFG data
	mov	[cfg_size],dx		; size of CFG data
	mov	ax,[MEMORY_SIZE]	; get available memory in Kb
	mov	cl,6
	shl	ax,cl			; available memory in paras
	mov	[top_seg],ax		; segment of end of memory
	add	bx,dx			; add size of CFG data
	mov	si,offset sysinit_beg	; SI = offset of init code
	sub	bx,si			; BX = number of bytes to move
	lea	dx,[bx+31]
	mov	cl,4
	shr	dx,cl			; max number of paras spanned
	sub	ax,dx			; target segment
	mov	dx,si
	shr	dx,cl			; DX = 1st paragraph of init code
	sub	ax,dx			; AX = target segment adjusted for ORG

	push	es			; begin move
	mov	es,ax
	ASSUME	ES:NOTHING
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	di,si
	mov	cx,bx
	shr	cx,1
	rep	movsw
	pop	es
	ASSUME	ES:BIOS
	push	ax			; push new segment on stack
	mov	ax,offset si2
	push	ax			; push new offset on stack
	ret				; far return to sysinit2
;
; Initialize all the DOS vectors, while DS is still dos_seg and ES is BIOS.
;
si2:	mov	si,offset int_tbl
	mov	di,INT_DOS_EXIT * 4
si3:	lodsw				; load vector offset
	test	ax,ax
	jz	si4
	stosw				; store vector offset
	mov	ax,ds
	stosw				; store vector segment
	jmp	si3
si4:	push	cs
	pop	ds			; DS is now the upper DOS segment
;
; Now set ES to the first available paragraph for resident DOS tables.
;
	mov	ax,offset sysinit_beg
	test	al,0Fh			; started on a paragraph boundary?
	jz	si5			; yes
	inc	dx			; no, so skip to the next paragraph
si5:	mov	es,dx
	ASSUME	ES:NOTHING
;
; The first resident table (PCB_TABLE) contains our Process Control Blocks.
; Look for a "PCBS=" line in CFG_FILE.
;
	mov	si,offset CFG_PCBS
	call	find_cfg		; look for "PCBS="
	jc	si6			; if not found, AX will be min value
	call	get_decimal		; AX = new value
si6:	mov	dx,size PCB
	mul	dx			; AX = length of table in bytes
	mov	bx,offset PCB_TABLE
	call	init_table
;
; The next resident table (SFB_TABLE) contains our System File Blocks.
; Look for a "FILES=" line in CFG_FILE.
;
	mov	si,offset CFG_FILES
	call	find_cfg		; look for "FILES="
	jc	si7			; if not found, AX will be min value
	call	get_decimal		; AX = new value
si7:	mov	dx,size SFB
	mul	dx			; AX = length of table in bytes
	mov	bx,offset SFB_TABLE
	call	init_table
;
; After all the resident tables have been created, initialize the MCB chain.
;
	push	ds
	mov	bx,es
	mov	ds,[dos_seg]		; MCB_HEAD is in resident DOS segment
	mov	[MCB_HEAD],bx
	pop	ds
	sub	di,di
	mov	al,MCB_LAST
	stosb				; mov es:[MCB_SIG],MCB_LAST
	sub	ax,ax
	stosw				; mov es:[MCB_OWNER],0
	mov	ax,[top_seg]
	sub	ax,bx			; AX = top segment - ES
	dec	ax			; AX reduced by 1 para (for MCB)
	stosw
	mov	cl,size MCB_RESERVED
	mov	al,0
	rep	stosb
;
; Allocate some memory for an initial (test) process
;
	IFDEF	DEBUG
	mov	ah,DOS_MALLOC
	mov	bx,200h
	int	21h
	jc	dsierr
	xchg	cx,ax			; CX = 1st segment
	mov	ah,DOS_MALLOC
	mov	bx,200h
	int	21h
	jc	dsierr
	xchg	dx,ax			; DX = 2nd segment
	mov	ah,DOS_MALLOC
	mov	bx,200h
	int	21h
	jc	dsierr
	xchg	si,ax			; SI = 3rd segment
	mov	ah,DOS_MFREE
	mov	es,cx			; free the 1st
	int	21h
	jc	dsierr
	mov	ah,DOS_MFREE
	mov	es,si
	int	21h			; free the 3rd
	jc	dsierr
	mov	ah,DOS_MFREE
	mov	es,dx
	int	21h			; free the 2nd
	jnc	si8
dsierr:	jmp	sysinit_error
	ENDIF

si8:	jmp	si8
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
; Convert string at DI to decimal, then validate using values at SI.
;
; Returns:
;	AX = value, DI -> 1st non-decimal digit
;	Carry will be set if there's an error, but AX will ALWAYS be valid
;
; Modifies:
;	AX, DI
;
DEFPROC	get_decimal
	push	cx
	push	dx
	sub	ax,ax
	cwd
	mov	cx,10
gd1:	mov	dl,[di]
	sub	dl,'0'
	jb	gd7
	cmp	dl,cl
	jae	gd7
	inc	di
	push	dx
	mul	cx
	pop	dx
	add	ax,dx
	jmp	gd1
gd7:	cmp	ax,[si]			; too small?
	jae	gd8			; no
	mov	ax,[si]
	jmp	short gd9
gd8:	cmp	[si+2],ax		; too large?
	jae	gd9			; no
	mov	ax,[si+2]
gd9:	pop	dx
	pop	cx
	ret
ENDPROC get_decimal

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Initialize table with length AX at ES:0, store ES at table segment address BX,
; and then adjust ES.
;
; Returns: Nothing
;
; Modifies: AX, DX, DI
;
DEFPROC	init_table
	xchg	cx,ax			; CX = length
	sub	di,di
	mov	ax,di
	rep	stosb			; initialize the table
	add	di,15
	mov	cl,4
	shr	di,cl			; DI = length of table in paras
	mov	ax,es
	push	ds
	mov	ds,[dos_seg]
	mov	[bx],ax			; save table segment
	pop	ds
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
	lodsb
	test	al,al
	jz	sp9
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	jmp	sysinit_print
sp9:	ret
ENDPROC	sysinit_print

;
; Initialization data
;
	DEFTBL	int_tbl,<dosexit,doscall,0>

CFG_PCBS	db	5,"PCBS="
		dw	4, 16

CFG_FILES	db	6,"FILES="
		dw	20, 256

syserr	db	"System initialization error, halted",0

	DEFLBL	sysinit_end

DOS	ends

	end
