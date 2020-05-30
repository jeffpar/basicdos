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
	mov	[cfg_size],dx
	mov	ax,[MEMORY_SIZE]	; AX = available memory in Kb
	mov	cl,6
	shl	ax,cl			; AX = available memory in paras

	mov	bx,offset sysinit_end
	add	bx,dx			; add size of CFG_FILE data
	mov	si,offset sysinit_beg
	sub	bx,si			; BX = number of bytes to move
	lea	dx,[bx+31]
	mov	cl,4
	shr	dx,cl			; DX = number of paras to move
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
; Initialize all the DOS vectors.
;
; NOTE: We have to be very careful with CS and DS references now.
; CS is high, valid only for init code/data, and DS is low, valid only
; for resident code/data.
;
sysinit2:				; now running in upper memory
	mov	si,offset int_tbl
	mov	di,INT_DOS_EXIT * 4
i1:	lods	word ptr cs:[si]
	test	ax,ax
	jz	i2
	stosw
	mov	ax,ds
	stosw
	jmp	i1
;
; Initialize the MCB chain.
;
i2:	mov	ax,ds
	add	bx,ax
	mov	[MCB_HEAD],bx
	mov	es,bx
	ASSUME	ES:NOTHING
	sub	di,di
	mov	al,MCB_LAST
	stosb				; mov es:[MCB_SIG],MCB_LAST
	sub	ax,ax
	stosw				; mov es:[MCB_OWNER],0
	sub	dx,bx			; DX = top para minus sysinit para
	xchg	ax,dx			; AX is now DX
	dec	ax			; AX reduced by 1 para (for MCB_HDR)
	stosw				; mov es:[MCB_PARAS],ax
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
	jc	printError
	xchg	cx,ax			; CX = 1st segment
	mov	ah,DOS_MALLOC
	mov	bx,200h
	int	21h
	jc	printError
	xchg	dx,ax			; DX = 2nd segment
	mov	ah,DOS_MALLOC
	mov	bx,200h
	int	21h
	jc	printError
	xchg	si,ax			; SI = 3rd segment
	mov	ah,DOS_MFREE
	mov	es,cx			; free the 1st
	int	21h
	jc	printError
	mov	ah,DOS_MFREE
	mov	es,si
	int	21h			; free the 3rd
	jc	printError
	mov	ah,DOS_MFREE
	mov	es,dx
	int	21h			; free the 2nd
	jc	printError
	ENDIF

i9:	jmp	i9
ENDPROC	sysinit

DEFTBL	int_tbl,<dosexit,doscall,0>

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

syserr	db	"System initialization error, halted",0

DEFLBL	sysinit_end

DOS	ends

	end
