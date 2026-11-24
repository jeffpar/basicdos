;
; BASIC-DOS Memory Display Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<transParas>
	EXTWORD	<CORE_END>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdMem
;
; Prints memory usage: the total memory (all of it, including any extended
; memory; see SYSINFO) and the available memory (which includes COMMAND's
; transient portion, if it can be discarded; see transParas).  Then it prints
; a line for anything that's unavailable: floating-point, if the FPU$ driver
; isn't loaded (see PSP_FPUTBL), and the functions outside COMMAND's core, if
; only the core was loaded (see CORE_END and genUpper).
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
	sub	sp,size SYSINFO
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> SYSINFO (on the stack)
	mov	cl,-1
	DOSUTIL	QRYSCB			; get the system's SYSINFO
	ASSERT	SI_MEMSIZE,EQ,0
	pop	ax			; AX = total Kb
	add	sp,size SYSINFO - 2
	mov	dx,1024
	mul	dx			; DX:AX = total memory (in bytes)
	PRINTF	<"%8ld bytes total",13,10>,ax,dx
	sub	cx,cx			; CX = memory block #
	sub	di,di			; DI = free bytes (low word)
	push	cx			; and the high word is on the stack
mem1:	mov	dl,1			; DL = 1 (free blocks only)
	DOSUTIL	QRYMEM			; SI:DX = size (in bytes)
	jc	mem2
	add	di,dx
	pop	ax
	adc	ax,si
	push	ax
	inc	cx
	jmp	mem1
mem2:	pop	si			; SI:DI = free bytes
	call	transParas		; AX = paras of COMMAND's transient
	mov	cx,16
	mul	cx			; DX:AX = its size in bytes
	add	ax,di
	adc	dx,si			; DX:AX = free memory for EXEC
	PRINTF	<"%8ld bytes available",13,10>,ax,dx
	cmp	word ptr ss:[PSP_FPUTBL]._SEG,0; is the FPU$ driver loaded?
	jne	mem3			; yes
	PRINTF	<"Floating-point disabled",13,10>
mem3:	mov	ax,ss:[PSP_CODESIZE]	; was only COMMAND's core loaded?
	cmp	ax,offset DGROUP:CORE_END
	ja	mem4			; no
	PRINTF	<"Core features only (see HELP CORE)",13,10>
mem4:	clc
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
	call	memMsg
me9:	pop	bx
	stc
	ret
;
; memMsg just prints the message (eg, for fileError, when a program can't
; be loaded).
;
	DEFLBL	memMsg,near
	PRINTF	<"Not enough memory",13,10>
	ret
ENDPROC	memError

CODE	ENDS

	end
