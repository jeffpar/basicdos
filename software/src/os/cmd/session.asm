;
; BASIC-DOS Session Commands
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; KILL, which ends a session or restarts the system.
;
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<askSure,getToken,syntaxError>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdKill
;
; KILL *n* ends session *n* (a number from START's list; see listSessions),
; by aborting each of its programs, as CTRL-ALT-DEL
; does on its console, which also stops a program that never calls DOS, and
; then closing the session (see scb_end).  KILL /A restarts the system (all
; sessions, hence the switch), after asking first.
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
	TESTSW	<'A'>			; /A?
	jz	kl1			; no
	call	getToken		; any argument?
	jnc	kl7			; yes, and /A doesn't take one
	call	askSure
	jnz	kl9			; no (and carry is clear)
	DOSUTIL	RESTART			; this shouldn't return
	ret				; but just in case...

kl1:	call	getToken		; DS:SI -> argument, CX = length
	jnc	kl2
	jmp	syntaxError		; there's no session number
kl2:	push	si
	inc	dx
	call	getToken		; any other argument?
	pop	si
	jnc	kl7			; yes
	push	bx
	mov	bl,10			; BL = base 10
	mov	di,-1			; DI = -1 (no validation data)
	DOSUTIL	ATOI16			; AX = session # (from 1)
	pop	bx
	jc	kl7
	cmp	byte ptr [si],' '	; anything after the digits (eg, 1X)?
	ja	kl7			; yes
	test	ah,ah			; could it be a session #?
	jnz	kl7			; no
	xchg	cx,ax			; CX = session # (from 1)
	jcxz	kl7			; (CL -1 would mean any free session)
	dec	cx			; CL = SCB #
	DOSUTIL	END,1			; end the session
	jnc	kl9
kl7:	PRINTF	<"Invalid session",13,10>
	stc
kl9:	ret
ENDPROC	cmdKill

CODE	ENDS

	end
