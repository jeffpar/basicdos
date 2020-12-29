;
; BASIC-DOS Memory Display Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc
	include	bios.inc
	include	dos.inc

CODE    SEGMENT

	EXTNEAR	<countLine,printCRLF>
	IFDEF	DEBUG
	EXTSTR	<SYS_MEM,DOS_MEM,FREE_MEM,BLK_NAMES>
	EXTABS	<BLK_WORDS>
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
mem0:	sub	di,di
	mov	es,di
	ASSUME	ES:BIOS
	les	di,[DD_LIST]
	ASSUME	ES:NOTHING

	IFDEF	DEBUG
	TESTSW	<'D'>
	jz	mem1
	PRINTF	"Seg   Owner Paras    KB  Desc\r\n"
	call	countLine
mem1:	sub	bx,bx
	mov	ax,es
	push	di
	push	es
	push	cs
	pop	es
	mov	di,offset SYS_MEM
	sub	dx,dx		; DX = owner (none)
	call	printKB		; BX = seg, AX = # paras, ES:DI -> name
	pop	es
	pop	di
	ENDIF	; DEBUG
;
; Next, dump the list of resident built-in device drivers.
;
mem2:	cmp	di,-1
	je	mem3

	IFDEF	DEBUG
	mov	bx,es
	mov	ax,es:[di].DDH_NEXT_SEG
	sub	ax,bx		; AX = # paras
	push	di
	lea	di,[di].DDH_NAME
	call	printKB		; BX = seg, AX = # paras, ES:DI -> name
	pop	di
	ENDIF	; DEBUG

	les	di,es:[di]
	jmp	mem2
;
; Next, dump the size of the operating system, which resides between the
; built-in device drivers and the first memory block.
;
mem3:	mov	ah,DOS_MSC_GETVARS
	int	21h
	sub	bx,2		; ES:BX -> DOSVARS
	mov	di,es:[bx].DV_MCB_LIMIT
	mov	[memLimit],di

	push	bx
	push	es

	IFDEF	DEBUG
	mov	ax,es:[bx].DV_MCB_HEAD
	mov	bx,es		; BX = DOS data segment
	sub	ax,bx
	push	cs
	pop	es
	mov	di,offset DOS_MEM
	call	printKB		; BX = seg, AX = # paras, ES:DI -> name
	ENDIF	; DEBUG
;
; Next, examine all the memory blocks and display those that are used.
;
	sub	cx,cx
	mov	[memFree],cx

mem4:	mov	dl,0		; DL = 0 (query all memory blocks)

	IFDEF	DEBUG
	push	cs
	pop	es		; ES:DI -> default owner name
	mov	di,offset SYS_MEM
	ENDIF	; DEBUG

	DOSUTIL	QRYMEM
	jc	mem9		; all done
	test	ax,ax		; free block (is OWNER zero?)
	jne	mem5		; no
	add	[memFree],dx	; yes, add to total free paras
;
; Let's include free blocks in the report now, too.
;
	IFDEF	DEBUG
	mov	di,offset FREE_MEM
	; jmp	short mem8
	ENDIF	; DEBUG

mem5:	IFDEF	DEBUG
	xchg	ax,dx		; AX = # paras, DX = owner
	call	printKB		; BX = seg, AX = # paras, ES:DI -> name
	ENDIF	; DEBUG

mem8:	inc	cx
	jmp	mem4

mem9:	pop	es
	pop	bx

	IFDEF	DEBUG
	TESTSW	<'D'>
	jz	mem10
	call	printCRLF
	ENDIF
;
; ES:BX should point to DOSVARS once again.  We'll start by dumping open SFBs.
;
mem10:	IFDEF	DEBUG
	TESTSW	<'F'>		; files requested (/F)?
	jz	mem20
	sub	cx,cx
	mov	di,es:[bx].DV_SFB_TABLE.OFF
	PRINTF	"Address SFH Name       Refs\r\n"
	call	countLine
mem11:	mov	al,es:[di].SFB_REFS
	test	al,al
	jz	mem12
	lea	si,[di].SFB_NAME
	PRINTF	"%08lx %2bd %-11.11ls  %2bd\r\n",di,es,cx,si,es,ax
	call	countLine
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
	call	countLine
mem22:	mov	ax,word ptr es:[di].SCB_STATUS
	test	al,SCSTAT_LOAD
	jz	mem23
	mov	cl,ah
	push	ds
	lds	si,es:[di].SCB_STACK
	PRINTF	"%2d %02bx %04x %04x %08lx %08lx\r\n",cx,ax,es:[di].SCB_PSP,es:[di].SCB_CONTEXT,es:[di].SCB_WAITID.LOW,es:[di].SCB_WAITID.HIW,si,ds
	pop	ds
	call	countLine
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
	PRINTF	<"%8ld bytes",13,10>,ax,dx
	call	countLine
	PRINTF	<"%8ld bytes free",13,10>,si,di
	call	countLine

	IFDEF	DEBUG
	TESTSW	<'L'>
	jz	mem99
	call	printCRLF
	jmp	mem0
	ENDIF	; DEBUG

mem99:	LEAVE
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
;	ES:DI -> "owner" name for memory block
;
; Outputs:
;	None
;
; Modifies:
;	AX, SI, DI, ES
;
	IFDEF	DEBUG
DEFPROC	printKB
	TESTSW	<'D'>		; detail requested (/D)?
	jz	pkb9		; no
	push	bp
	push	cx

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

	cmp	di,5		; DI = offset MCB_TYPE?
	jne	pkb8		; no
	mov	al,'<'
	mov	ah,es:[di]	; AH = MCB_TYPE
	push	cs
	pop	es
	mov	di,offset BLK_NAMES
	mov	cx,BLK_WORDS
	repne	scasw
	jne	pkb8
	dec	di
	dec	di

pkb8:	PRINTF	<"%04x  %04x  %04x %3d.%1dK  %.8ls",13,10>,bx,dx,ax,cx,bp,di,es
	call	countLine

	pop	cx
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
