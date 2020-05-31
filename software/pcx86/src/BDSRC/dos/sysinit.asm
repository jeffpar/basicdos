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

	EXTERNS	<MCB_HEAD>,word
	EXTERNS	<dosexit,doscall>,near

	DEFLBL	sysinit_beg
	DEFWORD	dos_seg,word		; the *real* DOS segment
	DEFWORD	top_seg,word
	DEFWORD	cfg_data,word
	DEFWORD	cfg_size,word

	ASSUME	CS:DOS, DS:BIOS, ES:BIOS, SS:BIOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; System initialization
;
; Everything after "sysinit" will be recycled.
;
; Entry:
;	BX -> CFG_FILE data, if any
;	DX = size of CFG_FILE data, if any
;
DEFPROC	sysinit,far
;
; Let's verify that the CFG_DATA data aligns with sysinit_end.
;
	IFDEF	DEBUG
	mov	ax,cs
	mov	cl,4
	shl	ax,cl
	add	ax,offset sysinit_end
	cmp	ax,bx
	je	i0
	call	printError
	jmp	$
i0:
	ENDIF
;
; Move all the init code out of the way, to the top of available memory.
;
; Size is in Kb (2^10 units), we need size in paragraphs (2^4 units), so
; shift left 6 bits.  Then calculate init code size in paras and subtract.
;
	mov	[dos_seg],cs
	mov	[cfg_size],dx
	mov	ax,[MEMORY_SIZE]	; AX = available memory in Kb
	mov	cl,6
	shl	ax,cl			; AX = available memory in paras
	mov	[top_seg],ax

	mov	bx,offset sysinit_end
	mov	[cfg_data],bx
	add	bx,dx			; add size of CFG_FILE data
	mov	si,offset sysinit_beg
	sub	bx,si			; BX = number of bytes to move
	lea	dx,[bx+31]
	mov	cl,4
	shr	dx,cl			; DX = max number of paras spanned
	sub	ax,dx			; AX = target segment

	mov	dx,si
	shr	dx,cl			; DX = paragraph of sysinit_beg
	sub	ax,dx			; AX = segment adjusted for ORG addr
	push	es
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
	mov	ax,offset sysinit2
	push	ax			; push new offset on stack
	ret				; far return to sysinit2
;
; Initialize all the DOS vectors, while ES still points to BIOS.
;
sysinit2:
	push	cs
	pop	ds
	mov	si,offset int_tbl
	mov	di,INT_DOS_EXIT * 4
i1:	lodsw				; load vector offset
	test	ax,ax
	jz	i2
	stosw				; store vector offset
	mov	ax,[dos_seg]
	stosw				; store vector segment
	jmp	i1
i2:
;
; Now set ES to the first available paragraph for resident DOS tables.
;
	mov	ax,offset sysinit_beg
	test	al,0Fh			; do we begin on a paragraph boundary?
	jz	i3			; yes
	inc	dx			; no, so skip to the next paragraph
i3:	mov	es,dx
	ASSUME	ES:NOTHING
;
; The first such table will be a System File Table.  Look for a "FILES="
; line in CFG_DATA.
;
	mov	si,offset FILES
	call	find_cfg		; look for "FILES="
	jc	i4
	call	get_decimal		; AX = new value
i4:	mov	dx,size SFT_ENTRY
	mul	dx			; AX = length of table in bytes
	call	init_table
;
; Initialize the MCB chain.
;
	push	ds
	mov	bx,es
	mov	ds,[dos_seg]		; MCB_HEAD is in the *real* DOS segment
	mov	[MCB_HEAD],bx		; not this relocated sysinit portion
	pop	ds
	sub	di,di
	mov	al,MCB_LAST
	stosb				; mov es:[MCB_SIG],MCB_LAST
	sub	ax,ax
	stosw				; mov es:[MCB_OWNER],0
	mov	ax,[top_seg]
	sub	ax,bx			; AX = top segment - ES
	dec	ax			; AX reduced by 1 para (for MCB_HDR)
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
	jc	i8
	xchg	cx,ax			; CX = 1st segment
	mov	ah,DOS_MALLOC
	mov	bx,200h
	int	21h
	jc	i8
	xchg	dx,ax			; DX = 2nd segment
	mov	ah,DOS_MALLOC
	mov	bx,200h
	int	21h
	jc	i8
	xchg	si,ax			; SI = 3rd segment
	mov	ah,DOS_MFREE
	mov	es,cx			; free the 1st
	int	21h
	jc	i8
	mov	ah,DOS_MFREE
	mov	es,si
	int	21h			; free the 3rd
	jc	i8
	mov	ah,DOS_MFREE
	mov	es,dx
	int	21h			; free the 2nd
	jnc	i9
i8:	jmp	printError
	ENDIF

i9:	jmp	i9
ENDPROC	sysinit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Search for length-prefixed string at SI in CFG_DATA.
;
; Returns:
;	Carry clear if success (DI -> 1st character after match)
;
; Modifies:
;	SI, DI
;
DEFPROC	find_cfg
	push	ax
	push	bx
	push	cx
	push	dx
	push	es
	push	ds
	pop	es
	ASSUME	ES:DOS
	mov	bx,si
	mov	di,[cfg_data]		; DI points to CFG_DATA
	mov	dx,di
	add	dx,[cfg_size]		; DX points to end of CFG_DATA
fc1:	lodsb				; 1st byte must be length
	cbw
	xchg	cx,ax			; CX = length of string to find
	repe	cmpsb
	je	fc9
	add	si,cx
	mov	al,0Ah			; LINEFEED
	mov	cx,dx
	sub	cx,di			; CX = bytes left to search
	jb	fc8			; ran out
	repne	scasb
	stc
	jne	fc8			; couldn't find another LINEFEED
	mov	si,bx
	jmp	fc1
fc8:	mov	ax,[si]			; return the default value
fc9:	pop	es
	ASSUME	ES:NOTHING
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	find_cfg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Convert string at DI to decimal, then validate using values at SI.
;
; Returns:
;	Carry clear if success (AX = value, DI -> 1st non-decimal digit)
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
; Initialize a table with length AX at ES:0, and then adjust ES.
;
; Modifies: AX, DX, DI
;
; Returns: Nothing
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
	add	ax,di
	mov	es,ax			; ES = next available paragraph
	ret
ENDPROC	init_table

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Print the null-terminated string at SI
;
; Modifies: AX, BX, SI
;
; Returns: Nothing
;
DEFPROC	printError
	mov	si,offset syserr
print:	lodsb
	test	al,al
	jz	p9
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	jmp	print
p9:	ret
ENDPROC	printError

FILES	db	6,"FILES="
	dw	20, 256

syserr	db	"System initialization error, halted",0

DEFTBL	int_tbl,<dosexit,doscall,0>

DEFLBL	sysinit_end

DOS	ends

	end
