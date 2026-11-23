;
; BASIC-DOS Multiple Session Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSPSP equ 1
	include	macros.inc
	include	8086.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<get_scb,read_psp,put_name>
	EXTNEAR	<chk_devlist,chk_devsfh,chk_devret,ms_parent,ms_done>

;
; A machine with 64K or less has only one console, and a second session only
; for a pipeline's filter (see def_sessions), so it doesn't keep this module,
; which follows fcb_code (see basdos.lrf), and set_fault makes each jump to it
; fall through instead: in chk_devname, so that a name like "@2" is an
; ordinary name, and in mem_session, so that a BASIC program's name stays
; zero.
;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ses_con
;
; Checks a name that begins with "@" for a session's CON (see chk_devname):
; if only digits follow, it's a session number (1 or 2 digits, since
; MAX_SESSIONS is 32), and the name is that session's CON; otherwise, it's an
; ordinary name (eg, "@X").
;
; Inputs:
;	DS:SI -> name (in SCB_FILENAME)
;	BX, and the stack, as chk_devname has them
;
; Outputs:
;	Continues in chk_devname
;
DEFPROC	ses_con,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	push	bx
	push	si
	inc	si			; SI -> 1st digit
	sub	cx,cx			; CL = session #, CH = # of digits
sc1:	lodsb
	sub	al,'0'
	cmp	al,10			; a digit?
	jae	sc2			; no
	mov	ah,cl
	aad				; AL = session # * 10 + digit
	mov	cl,al
	inc	ch
	jmp	sc1
sc2:	cmp	al,-'0'			; did the name end after the digits?
	jne	sc9			; no
	pop	ax			; (discard the saved SI)
	cmp	ch,2			; more digits than a session # has?
	ja	sc8			; yes
	dec	cl			; CL = SCB #
	js	sc8			; "@0" (or "@") isn't a session
	call	get_scb			; BX -> SCB
	jc	sc8			; there's no such session
	sub	si,4			; [SI+3] = null (no descriptor)
	mov	al,SCB_SFHOUT		; AL = SCB offset of the SFH
	jmp	chk_devsfh
sc8:	mov	cx,-1			; CX = -1 (no such device)
	jmp	chk_devret
sc9:	pop	si
	pop	bx
	jmp	chk_devlist
ENDPROC	ses_con

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; bas_name
;
; With REG_AL = 1, the caller's buffer has room for the name of the BASIC
; program that the session's program is running, if any (see mem_session and
; PSP_BASIC).
;
; Inputs:
;	DS:DI -> the PSP block's PMB, and everything else as mem_session has it
;
; Outputs:
;	Continues in mem_session
;
DEFPROC	bas_name,DOS
	cmp	byte ptr [bp].REG_AL,1
	jne	bn9
	mov	ax,PSP_BASIC
	mov	cx,PSP_FCB1 + 9 - PSP_BASIC
	call	read_psp		; DS:SI -> PSP_BASIC through its name
	jc	bn8
	cmp	byte ptr [si],0		; is it running a BASIC program?
	je	bn9			; no
	add	si,PSP_FCB1 + 1 - PSP_BASIC
	mov	bx,8
	call	put_name
bn9:	jmp	ms_parent
bn8:	jmp	ms_done
ENDPROC	bas_name

DOS	ends

	end
