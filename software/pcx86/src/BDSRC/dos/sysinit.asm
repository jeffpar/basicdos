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

	ASSUME	CS:DOS, DS:BIOS, ES:BIOS, SS:BIOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; System initialization
;
; Everything after "sysinit" will be recycled.
;
DEFPROC	sysinit,far
;
; First, let's move all our init code out of the way, to the top of
; available memory.
;
; Size is in Kb (2^10 units), we need size in paragraphs (2^4 units), so
; shift left 6 bits.  Then calculate init code size in paras and subtract.
;
; Example: if sysinit is 288h and sysinit_end is 2F4h, the code will
; span 8 paras (logical paras 28h through 2fh), and if we merely rounded
; their difference up to the next whole paragraph, that would amount to only
; 7 paras.  So we always round up 2 paras (+ 31 before shifting) to be safe.
;
; It would be preferable if sysinit started on a paragraph boundary, and one
; way to do that might be to put all "sysinit" code into its own para-aligned
; INIT segment, which could then be GROUP'ed with the DOS segment; however,
; my admittedly limited LINK experiments yielded unhelpful results (ie, the
; segments were still combined with word alignment).
;
	mov	ax,[MEMORY_SIZE]	; AX = available memory in Kb
	mov	cl,6
	shl	ax,cl			; AX = available memory in paras
	mov	dx,ax			; DX = paragraph of end of memory
	sub	ax,(offset sysinit_end - offset sysinit + 31) SHR 4
	mov	si,offset sysinit
	mov	bx,si
	mov	cl,4
	shr	bx,cl			; BX = paragraph of sysinit
	sub	ax,bx			; AX = segment adjusted for ORG addr
	push	es
	mov	es,ax
	ASSUME	ES:NOTHING
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	di,si
	mov	cx,(offset sysinit_end - offset sysinit) SHR 1
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
	IFDEF	TESTMEM
	int 3
	mov	ah,DOS_MALLOC
	mov	bx,200h
	int	21h
	xchg	cx,ax			; CX = 1st segment
	mov	ah,DOS_MALLOC
	mov	bx,200h
	int	21h
	xchg	dx,ax			; DX = 2nd segment
	mov	ah,DOS_MALLOC
	mov	bx,200h
	int	21h
	xchg	si,ax			; SI = 3rd segment
	mov	ah,DOS_MFREE
	mov	es,cx			; free the 1st
	int	21h
	mov	ah,DOS_MFREE
	mov	es,si
	int	21h			; free the 3rd
	mov	ah,DOS_MFREE
	mov	es,dx
	int	21h			; free the 2nd
	int 3
	ENDIF

i9:	jmp	i9
ENDPROC	sysinit

DEFTBL	int_tbl,<dosexit,doscall,0>

DEFLBL	sysinit_end

DOS	ends

	end
