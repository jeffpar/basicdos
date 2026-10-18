;
; BASIC-DOS Memory Display Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc
	include	dosfunc.inc

CODE    SEGMENT

	EXTNEAR	<transParas>
	EXTWORD	<CORE_END>
	EXTLONG	<FPU_TABLE>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdMem
;
; Prints memory usage: the total memory, the free memory available for an
; EXEC (which includes COMMAND's transient portion, if it can be discarded;
; see transParas), and the free memory available for BASIC programs, followed
; by a line for anything that's unavailable: the statements outside COMMAND's
; core, if only the core was loaded (see CORE_END and genUpper), and
; floating-point, if the FPU$ driver isn't loaded (see FPU_TABLE).
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
	mov	ah,DOS_MSC_GETVARS
	int	21h			; ES:BX -> DOSVARS + 2
	mov	ax,es:[bx-2].DV_MCB_LIMIT
	call	toBytes			; DX:AX = total memory (in bytes)
	PRINTF	<"%8ld bytes total",13,10>,ax,dx
	sub	cx,cx			; CX = memory block #
	sub	si,si			; SI = free paragraphs
mem1:	mov	dl,1			; DL = 1 (free blocks only)
	DOSUTIL	QRYMEM
	jc	mem2
	add	si,dx
	inc	cx
	jmp	mem1
mem2:	call	transParas		; AX = paras of COMMAND's transient
	test	ax,ax			; can it be discarded?
	jz	mem3			; no, so EXEC and BASIC have the same
	add	ax,si			; AX = free memory for EXEC (paras)
	call	toBytes
	PRINTF	<"%8ld bytes free for EXEC",13,10>,ax,dx
	xchg	ax,si			; AX = free memory for BASIC (paras)
	call	toBytes
	PRINTF	<"%8ld bytes free for BASIC",13,10>,ax,dx
	jmp	short mem9
mem3:	xchg	ax,si
	call	toBytes
	PRINTF	<"%8ld bytes free",13,10>,ax,dx
mem9:	mov	ax,ss:[PSP_CODESIZE]	; was only COMMAND's core loaded?
	cmp	ax,offset DGROUP:CORE_END
	ja	mem10			; no
	PRINTF	<"Not enough memory for graphics and sound",13,10>
mem10:	cmp	word ptr cs:[FPU_TABLE].SEG,0; is the FPU$ driver loaded?
	jne	mem11			; yes
	PRINTF	<"No floating-point (FPU$ driver not loaded)",13,10>
mem11:	clc
	ret
	DEFLBL	toBytes,near	; converts paras in AX to bytes in DX:AX
	mov	cx,16
	mul	cx
	ret
ENDPROC	cmdMem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; memError
;
; Reports a memory error, unless genCode has already reported one (ERR_CODE),
; since a program that runs out of memory will usually do so repeatedly.
;
; Inputs:
;	None
;
; Outputs:
;	Carry set
;
; Modifies:
;	AX
;
DEFPROC	memError
	push	bx
	mov	bx,ss:[PSP_HEAP]
	mov	al,ERR_NOMEMORY
	xchg	ss:[bx].ERR_CODE,al
	test	al,al			; already reported?
	jnz	me9			; yes
	PRINTF	<"Not enough memory",13,10>
me9:	pop	bx
	stc
	ret
ENDPROC	memError

CODE	ENDS

	end
