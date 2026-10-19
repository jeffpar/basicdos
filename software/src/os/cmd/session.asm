;
; BASIC-DOS Session Commands
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; LIST SESSIONS and RESTART.
;
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<getToken>
	EXTWORD	<OPTION_TOKENS>
	EXTABS	<TOK_SYSTEM>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; listSessions
;
; Lists every session: its number (from 1, as used by RESTART), its console
; (the name of the device its output goes to), and its program (or "Unused"
; if it has none), marking the current session with "*".
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	listSessions
	DOSUTIL	GETCSN			; CL = current session #
	mov	dl,cl			; DL = current session #
	sub	cx,cx			; CL = session # (from 0)
lss1:	DOSUTIL	QRYSCB			; AX = PSP, ES:DI -> console name
	jc	lss9			; no more sessions
	mov	bl,' '
	cmp	cl,dl			; is it the current session?
	jne	lss2			; no
	mov	bl,'*'			; BL = marker
lss2:	test	di,di			; does the session have a console?
	jnz	lss3			; yes
	push	cs
	pop	es
	mov	di,offset NO_NAME	; ES:DI -> empty name
lss3:	mov	si,cx
	inc	si			; SI = session # (from 1)
	push	dx
	test	ax,ax			; does the session have a program?
	jz	lss4			; no
	dec	ax			; AX = program's MCB
	mov	dx,offset MCB_NAME	; AX:DX -> program's name
	PRINTF	<"%c%2d %-8.8ls %-8.8ls",13,10>,bx,si,di,es,dx,ax
	jmp	short lss8
lss4:	PRINTF	<"%c%2d %-8.8ls Unused",13,10>,bx,si,di,es
lss8:	pop	dx
	inc	cx
	jmp	lss1
lss9:	ret
ENDPROC	listSessions

NO_NAME	db	0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdRestart
;
; RESTART SYSTEM restarts the system, and RESTART *n* restarts session *n*
; (see LIST SESSIONS): its program is aborted, as when CTRL-ALT-DEL is
; pressed on its console, which also stops a program that never calls DOS
; (and if the program is the session's command processor, the abort is
; turned into a CTRLC, returning it to its prompt).
;
; Inputs:
;	BX -> CMDHEAP
;
; Outputs:
;	Carry set if error
;
; Modifies:
;	Any
;
DEFPROC	cmdRestart
	mov	dl,[bx].CMD_ARG
	call	getToken		; DS:SI -> argument, CX = length
	jc	rst8			; none
	push	si
	lea	dx,[OPTION_TOKENS]
	DOSUTIL	TOKID			; AX = option ID, if any
	pop	si
	jc	rst1			; not an option, so maybe a number
	cmp	ax,TOK_SYSTEM
	jne	rst7
	DOSUTIL	RESTART			; this shouldn't return
	ret				; but just in case...

rst1:	mov	bl,10			; BL = base 10
	mov	di,-1			; DI = -1 (no validation data)
	DOSUTIL	ATOI16			; AX = session # (from 1)
	jc	rst7
	dec	ax
	xchg	cx,ax			; CL = SCB #
	DOSUTIL	END			; abort the session's program
	jnc	rst9
rst7:	PRINTF	<"Invalid session",13,10,13,10>
	stc
	ret
rst8:	PRINTF	<"Specify a session or SYSTEM",13,10,13,10>
	stc
rst9:	ret
ENDPROC	cmdRestart

CODE	ENDS

	end
