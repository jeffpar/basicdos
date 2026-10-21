;
; BASIC-DOS Shared Filespec Procedures
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Included in the code segment by COMMAND (dir.asm) and by the FIND and WC
; utilities (utilproc.inc).  The includer must define DOSFFB (before including
; dosapi.inc), and UTIL_PCH as the operand that holds the path char (eg,
; byte ptr ss:[bx].PATH_CHAR).  DS and ES must equal SS.
;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; walkFiles
;
; Call a function for every file matching a filespec with wildcards (for
; COPY, DEL, and TYPE, and the FIND and WC utilities).  Since the DTA may
; contain the command line (or file data, for COPY), we use a DTA on the stack,
; along with a buffer for the name of each match (the filespec's drive and
; path, if any, followed by the name).  Only normal files match (not hidden,
; system, or directory entries).
;
; Inputs:
;	BX = data for the includer (eg, CMDHEAP), unused here
;	SS:SI -> filespec (null-terminated)
;	SS:DI -> filename portion of filespec
;	CX = data for the function
;	DX = function (called with SS:SI -> name of match, CX = data, and
;	BX unchanged; it must preserve BX and BP, and return carry set to stop,
;	with AX = error #)
;
; Outputs:
;	Carry clear if successful, set if error (AX = error #)
;
; Modifies:
;	AX, CX, DX, DI, ES (and whatever the function modifies)
;
WF_NAME	equ	(size FFB + 1) AND 0FFFEh
WF_END	equ	WF_NAME + 80		; end of the drive and path in WF_NAME
WF_DATA	equ	WF_END + 2		; data for the function
WF_FUNC	equ	WF_DATA + 2		; function
WF_SIZE	equ	WF_FUNC + 2

DEFPROC	walkFiles
	push	bp
	push	si
	sub	sp,WF_SIZE
	mov	bp,sp
	mov	[bp+WF_DATA],cx
	mov	[bp+WF_FUNC],dx
	push	ss
	pop	es
	mov	cx,di
	sub	cx,si			; CX = length of drive and path
	lea	di,[bp+WF_NAME]
	rep	movsb			; copy them to the name buffer
	mov	[bp+WF_END],di
	mov	dx,bp			; DS:DX -> temporary DTA
	mov	ah,DOS_DSK_SETDTA
	int	21h
	mov	dx,[bp+WF_SIZE]
	mov	ah,DOS_DSK_FFIRST	; DS:DX -> filespec (CX is zero)
	int	21h
	jc	wf8
wf1:	lea	si,[bp].FFB_NAME
	mov	di,[bp+WF_END]
wf2:	lodsb				; append the matching name
	stosb
	test	al,al
	jnz	wf2
	lea	si,[bp+WF_NAME]		; SS:SI -> name of match
	mov	cx,[bp+WF_DATA]
	call	word ptr [bp+WF_FUNC]
	jc	wf8
	mov	ah,DOS_DSK_FNEXT
	int	21h
	jnc	wf1
	clc				; no more matches
wf8:	pushf
	push	ax
	mov	dx,PSP_DTA
	mov	ah,DOS_DSK_SETDTA
	int	21h			; restore the DTA
	pop	ax
	popf
	lea	sp,[bp+WF_SIZE]
	pop	si
	pop	bp
	ret
ENDPROC	walkFiles

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scanSpec
;
; Find the filename portion of a filespec (ie, after any drive or path), and
; check the filespec for wildcards.
;
; Inputs:
;	UTIL_PCH = path char
;	DS:SI -> filespec (null-terminated)
;
; Outputs:
;	DI -> filename portion of filespec
;	AH = non-zero if the filespec contains wildcards
;
; Modifies:
;	AX, DI
;
DEFPROC	scanSpec
	push	si
	mov	di,si
	mov	ah,0
ss1:	lodsb
	cmp	al,'*'
	je	ss2
	cmp	al,'?'
	jne	ss3
ss2:	mov	ah,al
ss3:	cmp	al,':'
	je	ss4
	cmp	al,UTIL_PCH
	jne	ss5
ss4:	mov	di,si
ss5:	test	al,al
	jnz	ss1
	pop	si
	ret
ENDPROC	scanSpec
