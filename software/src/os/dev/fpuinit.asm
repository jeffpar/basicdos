;
; BASIC-DOS Floating-Point Unit Device Driver Initialization
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The FPU$ driver's initialization is linked after FPUDEV.ASM, whose segments
; it shares, and is in a module of its own because FPUDEV.ASM doesn't have
; room (MASM symbol space) for the definitions that calling CPU$ requires.
;
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	fpu.inc
	include	cpu.inc

	.8087

DEV	group	CODE,HWCODE,SWCODE,INIT,DATA

CODE	segment para public 'CODE'
	EXTERNS	<ddfpu_req,comAtoD,comDtoA>,far
	EXTWORD	<fpuSeg,fpuInfo>
	EXTLONG	<fpuToDec,fpuFromDec>
CODE	ends

HWCODE	segment para public 'CODE'
	EXTWORD	<hwTable>
	EXTLONG	<hwComAtoD>
HWCODE	ends

SWCODE	segment para public 'CODE'
	EXTWORD	<swTable>
	EXTNEAR	<swEnd>
SWCODE	ends

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; If an 8087 is present, we keep the HWCODE functions and discard everything
; from SWCODE onward; otherwise, we move the SWCODE functions down on top of
; the HWCODE functions and discard everything after that.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
; Modifies:
;	AX, CX, DX, SI, DI, BP, DS
;
INIT	segment para public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	ddfpu_init,far
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:DEV
	mov	ds:[0].DDH_REQUEST,offset DEV:ddfpu_req
;
; Detect the 8087: after FNINIT, the low byte of its status word must be
; zero and its control word must contain the FNINIT default bits (if there's
; no 8087, then FNSTSW and FNSTCW should not modify our test word at all).
;
	mov	ax,-1
	push	ax
	mov	bp,sp			; SS:BP -> test word
	fninit
	fnstsw	word ptr [bp]
	mov	dx,FPUTYPE_NONE SHL 8
	cmp	byte ptr [bp],0
	jne	ddi1
	fnstcw	word ptr [bp]
	mov	ax,[bp]
	and	ax,103Fh
	cmp	ax,003Fh
	jne	ddi1
	mov	dh,FPUTYPE_8087
ddi1:	pop	ax
	mov	dl,(size FPUTBL) SHR 1
	mov	[fpuInfo],dx

	mov	di,offset DEV:hwTable
	mov	ax,offset DEV:swTable	; AX = end of HWCODE
	test	dh,dh			; 8087 present?
	jnz	ddi9			; yes
	push	es
	mov	es,cs:[0].DDH_DATA
	mov	si,ax			; DS:SI -> SWCODE
	mov	cx,offset DEV:swEnd
	sub	cx,si
	inc	cx
	shr	cx,1			; CX = # of words in SWCODE
	rep	movsw			; move SWCODE down to HWCODE
	pop	es
	xchg	ax,di			; AX = end of moved SWCODE
ddi9:	mov	es:[bx].DDPI_END.OFF,ax
;
; The FPUTBL's offsets are relative to hwTable's paragraph, so its functions
; need a code segment of their own, which CPU_MAP (with MEMF_CODE) returns
; for the paragraph's address: in real mode, a segment, and in protected
; mode, a code selector for the functions we keep.  If there's no selector,
; we keep nothing.
;
	push	bx
	sub	ax,offset DEV:hwTable
	push	ax			; AX = length of the functions we keep
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU	; AH = CPUF_* flags
	mov	al,0
	test	ah,CPUF_PM		; is CS a selector?
	jz	ddi9a			; no
	mov	al,ADDR_SEL		; yes
ddi9a:	mov	ah,CPU_SEGINFO
	mov	bx,cs
	call	far ptr DDINT_CPU	; DX:CX = our address
	add	cx,offset DEV:hwTable
	adc	dx,0			; DX:CX = FPUTBL's address
	pop	di
	sub	si,si			; SI:DI = length
	mov	ax,(CPU_MAP SHL 8) OR MEMF_CODE
	call	far ptr DDINT_CPU	; AX = FPUTBL's segment (or selector)
	pop	bx
	jnc	ddi9b
	mov	es:[bx].DDPI_END.OFF,0	; keep nothing
ddi9b:	mov	[fpuSeg],ax		; FPUTBL is at fpuSeg:0
;
; Fill in the far pointers that follow the retained FPUTBL, so that its
; FPU_ATOD and FPU_DTOA functions can reach the shared code, and the far
; pointers that the shared code uses to reach FPU_TODEC and FPU_FROMDEC.
;
	mov	si,offset DEV:hwComAtoD
	mov	word ptr [si],offset DEV:comAtoD
	mov	[si+2],cs
	mov	word ptr [si+4],offset DEV:comDtoA
	mov	[si+6],cs
	mov	ax,[fpuSeg]
	mov	[fpuToDec].SEG,ax
	mov	[fpuFromDec].SEG,ax
	mov	ax,word ptr [hwTable+FPU_TODEC]
	mov	[fpuToDec].OFF,ax
	mov	ax,word ptr [hwTable+FPU_FROMDEC]
	mov	[fpuFromDec].OFF,ax
	ret
ENDPROC	ddfpu_init

INIT	ends

DATA	segment para public 'DATA'
DATA	ends

	end
