;
; BASIC-DOS MEM Debugging Displays
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The displays of open files (MEM /F) and active sessions (MEM /S) that DEBUG
; builds of MEM add (see mem.asm), which are the only parts of MEM that need
; the kernel's internal structures (see dos.inc).
;
; Include only the definitions used here, to leave room in MASM's symbol table
; for the kernel structures as well as the debugging displays.
;
	include	macros.inc
	include	dosapi.inc
	include	parser.inc
	IFDEF	DEBUG
	include	dos.inc		; (only the DEBUG displays need it)
	ENDIF

CODE    SEGMENT word public 'CODE'

	EXTNEAR	<printCRLF>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; memDebug
;
; Displays the open SFBs (if /F) and the active SCBs (if /S); in non-DEBUG
; builds, this does nothing.
;
; Inputs:
;	ES:BX -> DOSVARS
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	memDebug
	IFDEF	DEBUG
	TESTSW	<'F'>		; files requested (/F)?
	jz	md20
	sub	cx,cx
	mov	di,es:[bx].DV_SFB_TABLE.OFF
	PRINTF	"Address SFH Name       Refs\r\n"
md11:	mov	al,es:[di].SFB_REFS
	test	al,al
	jz	md12
	lea	si,[di].SFB_NAME
	PRINTF	"%08lx %2bd %-11.11ls  %2bd\r\n",di,es,cx,si,es,ax
md12:	inc	cx
	add	di,size SFB
	cmp	di,es:[bx].DV_SFB_TABLE.SEG
	jb	md11
	call	printCRLF

md20:	TESTSW	<'S'>		; sessions requested (/S)?
	jnz	md21		; keep the conditional jump within short range
	ret
md21:	mov	di,es:[bx].DV_SCB_TABLE.OFF
	PRINTF	"No Fl PSP  Ctx  WaitID   Stack\r\n"
md22:	mov	ax,word ptr es:[di].SCB_STATUS
	test	al,SCSTAT_LOAD
	jz	md23
	mov	cl,ah
	push	ds
	lds	si,es:[di].SCB_STACK
	PRINTF	"%2d %02bx %04x %04x %08lx %08lx\r\n",cx,ax,es:[di].SCB_PSP,es:[di].SCB_CONTEXT,es:[di].SCB_WAITID,:2,si,ds
	pop	ds
md23:	add	di,size SCB
	cmp	di,es:[bx].DV_SCB_TABLE.SEG
	jb	md22
	call	printCRLF
	ENDIF	; DEBUG
md99:	ret
ENDPROC	memDebug

CODE	ENDS

	end
