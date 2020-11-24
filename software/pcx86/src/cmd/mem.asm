;
; BASIC-DOS Memory Display Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc
	include	bios.inc
	include	dos.inc

CODE    SEGMENT

	EXTNEAR	<printCRLF>
	IFDEF	DEBUG
	EXTSTR	<SYS_MEM,DOS_MEM,FREE_MEM>
	ENDIF	; DEBUG

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdMem
;
; Prints memory usage.  Use /D to display memory blocks, /F to display open
; files, and /S to display active sessions.
;
; Inputs:
;	BX -> CMDHEAP (not used)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdMem
	LOCVAR	memFree,word	; free paras
	LOCVAR	memLimit,word	; max available paras
	ENTER
;
; Before we get into memory blocks, show the amount of memory reserved
; for the BIOS and disk buffers.
;
	sub	di,di
	mov	es,di
	ASSUME	ES:BIOS
	les	di,[DD_LIST]
	ASSUME	ES:NOTHING

	IFDEF	DEBUG
	TESTSW	<'D'>
	jz	mem0
	PRINTF	"Seg   Owner Paras    KB  Desc\r\n"
mem0:	sub	bx,bx
	mov	ax,es
	push	di
	mov	di,cs
	mov	si,offset SYS_MEM
	sub	dx,dx		; DX = owner (none)
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
	ENDIF	; DEBUG
;
; Next, dump the list of resident built-in device drivers.
;
mem1:	cmp	di,-1
	je	mem2

	IFDEF	DEBUG
	lea	si,[di].DDH_NAME
	mov	bx,es
	mov	cx,bx
	mov	ax,es:[di].DDH_NEXT_SEG
	sub	ax,cx		; AX = # paras
	push	di
	mov	di,bx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
	ENDIF	; DEBUG

	les	di,es:[di]
	jmp	mem1
;
; Next, dump the size of the operating system, which resides between the
; built-in device drivers and the first memory block.
;
mem2:	mov	ah,DOS_MSC_GETVARS
	int	21h
	sub	bx,2		; ES:BX -> DOSVARS
	mov	di,es:[bx].DV_MCB_LIMIT
	mov	[memLimit],di
	push	bx

	IFDEF	DEBUG
	mov	ax,es:[bx].DV_MCB_HEAD
	mov	bx,es		; BX = DOS data segment
	sub	ax,bx
	mov	di,cs
	mov	si,offset DOS_MEM
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	ENDIF	; DEBUG
;
; Next, examine all the memory blocks and display those that are used.
;
	sub	cx,cx
	mov	[memFree],cx

mem3:	mov	dl,0		; DL = 0 (query all memory blocks)

	IFDEF	DEBUG
	mov	di,cs		; DI:SI -> default owner name
	mov	si,offset SYS_MEM
	ENDIF	; DEBUG

	DOSUTIL	QRYMEM
	jc	mem9		; all done
	test	ax,ax		; free block (is OWNER zero?)
	jne	mem4		; no
	add	[memFree],dx	; yes, add to total free paras
;
; Let's include free blocks in the report now, too.
;
	IFDEF	DEBUG
	mov	si,offset FREE_MEM
	; jmp	short mem8
	ENDIF	; DEBUG

mem4:	IFDEF	DEBUG
	xchg	ax,dx		; AX = # paras, DX = owner
	push	cx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	cx
	ENDIF	; DEBUG

mem8:	inc	cx
	jmp	mem3

mem9:	call	printCRLF
	pop	bx
;
; ES:BX should point to DOSVARS once again.  We'll start by dumping open SFBs.
;
	IFDEF	DEBUG
	TESTSW	<'F'>		; files requested (/F)?
	jz	mem20
	sub	cx,cx
	mov	di,es:[bx].DV_SFB_TABLE.OFF
	PRINTF	"Address SFH Name       Refs\r\n"
mem11:	mov	al,es:[di].SFB_REFS
	test	al,al
	jz	mem12
	lea	si,[di].SFB_NAME
	PRINTF	"%08lx %2bd %-11.11ls  %2bd\r\n",di,es,cx,si,es,ax
mem12:	inc	cx
	add	di,size SFB
	cmp	di,es:[bx].DV_SFB_TABLE.SEG
	jb	mem11
	call	printCRLF

mem20:	TESTSW	<'S'>		; sessions requested (/S)?
	jnz	mem21		; yes
	jmp	mem30
mem21:	mov	di,es:[bx].DV_SCB_TABLE.OFF
	PRINTF	"No Fl PSP  Ctx  WaitID   Stack\r\n"
mem22:	mov	ax,word ptr es:[di].SCB_STATUS
	test	al,SCSTAT_LOAD
	jz	mem23
	mov	cl,ah
	lds	si,es:[di].SCB_STACK
	ASSUME	DS:NOTHING
	PRINTF	"%2d %02bx %04x %04x %08lx %08lx\r\n",cx,ax,es:[di].SCB_PSP,es:[di].SCB_CONTEXT,es:[di].SCB_WAITID.LOW,es:[di].SCB_WAITID.HIW,si,ds
mem23:	add	di,size SCB
	cmp	di,es:[bx].DV_SCB_TABLE.SEG
	jb	mem22
	call	printCRLF
	ENDIF	; DEBUG
;
; Last but not least, dump the amount of free memory (ie, the sum of all the
; free blocks that we did NOT display above).
;
mem30:	mov	ax,[memFree]	; AX = free memory (paras)
	mov	cx,16
	mul	cx		; DX:AX = free memory (in bytes)
	xchg	si,ax
	mov	di,dx		; DI:SI = free memory
	mov	ax,[memLimit]
	mul	cx		; DX:AX = total memory (in bytes)
	PRINTF	<"%8ld bytes",13,10,"%8ld bytes free",13,10>,ax,dx,si,di

	LEAVE
	ret
ENDPROC	cmdMem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printKB
;
; Converts the paragraph size in AX to Kb, by calculating AX/64 (or AX >> 6);
; however, that's a bit too granular, so we include tenths of Kb as well.
;
; Using the paragraph remainder (R), we calculate tenths (N): R/64 = N/10, so
; N = (R*10)/64.
;
; Inputs:
;	AX = size in paragraphs
;	DX = owner (zero if none)
;	BX = segment of memory block
;	DI:SI -> "owner" name for memory block
;
; Outputs:
;	None
;
	IFDEF	DEBUG
DEFPROC	printKB
	TESTSW	<'D'>		; detail requested (/D)?
	jz	pkb9		; no
	push	bp
	push	ax
	push	bx
	push	dx
	mov	bx,64
	sub	dx,dx		; DX:AX = paragraphs
	div	bx		; AX = Kb
	xchg	cx,ax		; save Kb in CX
	xchg	ax,dx		; AX = paragraphs remainder
	mov	bl,10
	mul	bx		; DX:AX = remainder * 10
	mov	bl,64
	or	ax,31		; round up without adding
	div	bx		; AX = tenths of Kb
	ASSERT	NZ,<cmp ax,10>
	xchg	bp,ax		; save tenths in BP
	pop	dx
	pop	bx
	pop	ax
	PRINTF	<"%04x  %04x  %04x %3d.%1dK  %.8ls",13,10>,bx,dx,ax,cx,bp,si,di
	pop	bp
pkb9:	ret
ENDPROC	printKB
	ENDIF	; DEBUG

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; memError
;
; Inputs:
;	AX = error #
;
; Outputs:
;	Carry set
;
; Modifies:
;	AX
;
DEFPROC	memError
	PRINTF	<"Not enough memory (%#06x)",13,10>,ax
	stc
	ret
ENDPROC	memError

CODE	ENDS

	end
