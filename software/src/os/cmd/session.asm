;
; BASIC-DOS Session Commands
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; KILL, which also lists the sessions.
;
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<askSure,getToken>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; listSessions
;
; Used by KILL with no argument to list every session: its number (from 1,
; as used by KILL), its console (the name of the device its output goes
; to), and its program (or "Unused" if it has none), marking the current
; session with "*".
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
	sub	sp,16
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> buffer for the names
	DOSUTIL	GETCSN			; CL = current session #
	mov	dl,cl			; DL = current session #
	sub	cx,cx			; CL = session # (from 0)
lss1:	DOSUTIL	QRYSCB			; AX = PSP, buffer = console + program
	jc	lss9			; no more sessions
	mov	bl,' '
	cmp	cl,dl			; is it the current session?
	jne	lss3			; no
	mov	bl,'*'			; BL = marker
lss3:	mov	si,cx
	inc	si			; SI = session # (from 1)
	push	dx
	test	ax,ax			; does the session have a program?
	jz	lss4			; no
;
; The console name is at the buffer (ES:DI) and the program name follows it,
; both in our stack segment; unlike PSP-1, those are valid to address in
; protected mode (see scb_query).
;
	lea	dx,[di+8]		; ES:DX -> the program's name
	PRINTF	<"%c%2d %-8.8ls %-8.8ls",13,10>,bx,si,di,es,dx,es
	jmp	short lss8
lss4:	PRINTF	<"%c%2d %-8.8ls Unused",13,10>,bx,si,di,es
lss8:	pop	dx
	inc	cx
	jmp	lss1
lss9:	add	sp,16
	ret
ENDPROC	listSessions

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdKill
;
; KILL alone lists the sessions (see listSessions).  KILL *n* ends session *n*
; (a number from that list), by aborting each of its programs, as CTRL-ALT-DEL
; does on its console, which also stops a program that never calls DOS, and
; then closing the session (see scb_end).  KILL 0 restarts the system, after
; asking first.
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
DEFPROC	cmdKill
	mov	dl,[bx].CMD_ARG
	call	getToken		; DS:SI -> argument, CX = length
	jnc	kl0
	jmp	listSessions		; none, so list the sessions
kl0:	push	si
	inc	dx
	call	getToken		; any other argument?
	pop	si
	jnc	kl7			; yes
	push	bx
	mov	bl,10			; BL = base 10
	mov	di,-1			; DI = -1 (no validation data)
	DOSUTIL	ATOI16			; AX = session # (from 1), or 0
	pop	bx
	jc	kl7
	cmp	byte ptr [si],' '	; anything after the digits (eg, 1X)?
	ja	kl7			; yes
	test	ah,ah			; could it be a session #?
	jnz	kl7			; no
	xchg	cx,ax			; CX = session # (from 1), or 0
	jcxz	kl5			; 0 means the system
	dec	cx			; CL = SCB #
	DOSUTIL	END,1			; end the session
	jnc	kl9
kl7:	PRINTF	<"Invalid session",13,10>
	stc
kl9:	ret

kl5:	call	askSure
	jnz	kl9			; no (and carry is clear)
	DOSUTIL	RESTART			; this shouldn't return
	ret				; but just in case...
ENDPROC	cmdKill

CODE	ENDS

	end
