;
; BASIC-DOS START Command
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; START, which runs a program in a new session, on a new console, or lists
; the sessions.
;
; This module is not part of COMMAND's core (see CMD.LRF and HEAP.ASM): when
; only the core is loaded, cmdDOS refuses START with "Not enough memory" (see
; genUpper).
;
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<getToken,findProgram,chkString,copyArgsTo,openError>
	EXTBYTE	<CMD_PATH>
	EXTSTR	<COM_EXT,EXE_EXT>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; addPath
;
; If the program is COMMAND or V86 (its name includes COMMAND.COM or V86.COM),
; append our PATH$ to its name, ahead of any arguments, the way a SHELL line
; in CONFIG.SYS gives a COMMAND one (eg, COMMAND.COM PATH$="A:\;A:\EXT":X.BAS),
; since a new session has no environment.
;
; Inputs:
;	BX -> CMDHEAP
;	DS:SI -> the program's name
;	ES:DI -> the null after it
;
; Outputs:
;	DI -> the end of the name and any PATH$
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	addPath
	push	di
	mov	dx,offset CMD_PATH+3	; DX -> "COMMAND.COM"
	call	chkString		; is the program COMMAND?
	jnc	ap1			; yes
	mov	dx,offset V86_COM
	call	chkString		; or V86?
ap1:	pop	di
	jc	ap9			; no
	mov	ax,('P' SHL 8) OR ' '
	stosw
	mov	ax,('T' SHL 8) OR 'A'
	stosw
	mov	ax,('$' SHL 8) OR 'H'
	stosw
	mov	ax,('"' SHL 8) OR '='
	stosw				; ' PATH$="'
	lea	si,[bx].PATH_BUF
	lodsb
	cbw
	xchg	cx,ax
	rep	movsb			; PATH$
	mov	ax,(':' SHL 8) OR '"'
	stosw				; '":'
ap9:	ret
ENDPROC	addPath

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdStartSes
;
; Process "START program [arguments]" (or START alone, which lists the
; sessions; see below), which runs the program (a COM or EXE
; file, found the way an external command is; see findProgram) in a new
; session, whose console is a new full-screen VKD$ console, which takes the
; focus.  Like a session from CONFIG.SYS, it has its own LDT (see
; DOS_UTL_LOAD), but its program can end (eg, COMMAND's EXIT), which closes
; the session and its console, and the focus goes back to the console that
; had it.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;	DS:SI -> program name (in LINEBUF, with length CX)
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	cmdStartSes
	push	si
	push	cx
	mov	dl,[bx].CMD_ARG
	call	getToken		; DS:SI -> program name, CX = length
	pushf
	add	si,cx
	xchg	ax,si			; AX -> the arguments that follow it
	popf
	pop	cx
	pop	si
	jnc	st1
;
; There's no program name, so list every session with a program: its number
; (from 1, as used by KILL), how much memory it's using (in K), and its
; program ("UNKNOWN" if DOS can't tell), marking the current session with "*".
;
	sub	sp,8
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> buffer for the name
	DOSUTIL	GETCSN			; CL = current session #
	mov	bl,cl			; BL = current session #
	sub	cx,cx			; CL = session # (from 0)
lss1:	DOSUTIL	QRYSCB			; AX = PSP, SI:DX = bytes, and name
	jc	lss9			; no more sessions
	test	ax,ax			; does the session have a program?
	jz	lss8			; no
	add	dx,1023
	adc	si,0			; (round up to the next K)
	push	cx
	mov	cl,10
	shr	dx,cl
	mov	cl,6
	shl	si,cl
	pop	cx
	or	si,dx			; SI = its memory (in K)
	mov	al,' '
	cmp	cl,bl			; is it the current session?
	jne	lss3			; no
	mov	al,'*'			; AL = marker
lss3:	mov	dx,cx
	inc	dx			; DX = session # (from 1)
	PRINTF	<"%c%2d %5dK ">,ax,dx,si
;
; The name is in our stack segment; unlike PSP-1, that's valid to address in
; protected mode (see scb_query).
;
	cmp	byte ptr es:[di],0	; is there a name?
	jne	lss4			; yes
	PRINTF	<"UNKNOWN",13,10>
	jmp	short lss8
lss4:	PRINTF	<"%.8ls",13,10>,di,es
lss8:	inc	cx
	jmp	lss1
lss9:	add	sp,8
	ret
st0:	jmp	openError
st1:	push	ax
	mov	dx,offset COM_EXT
	call	findProgram		; LINEBUF = the program's name
	pop	dx			; DX -> its arguments
	jc	st0
	push	dx
	mov	dx,offset COM_EXT
	call	chkString		; is it a COM file?
	jnc	st2			; yes
	mov	dx,offset EXE_EXT
	call	chkString		; or an EXE file?
st2:	pop	dx
	mov	ax,ERR_INVALID
	jc	st0			; no
	DOSUTIL	STRLEN			; AX = length of the name
	mov	di,si
	add	di,ax			; DI -> the null after the name
	push	di
	push	si
	lea	ax,[di+126]		; AX -> the end of the longest tail
	push	ax
	push	dx
	call	addPath			; add PATH$ for a new COMMAND
	pop	si			; SI -> the arguments
	pop	ax
	call	copyArgsTo		; append the arguments
	mov	al,0
	stosb
	pop	si			; DS:SI -> the command line
;
; Open the new console, give its handle to the new session as STDIN, STDOUT,
; and STDERR (along with our AUX and PRN), and then close our handle for it.
;
	push	ds
	push	cs
	pop	ds
	mov	dx,offset CON_NAME	; DS:DX -> CON_NAME
	mov	ax,DOS_HDL_OPENRW
	int	21h			; AX = handle
	jnc	st3
	mov	si,dx
	call	openError		; report error (AX) opening CON_NAME
st3:	pop	ds
	pop	di			; DI -> the end of the name
	jc	st9
	push	bx
	push	di
	xchg	bx,ax			; BX = handle
	mov	al,ds:[PSP_PFT][bx]	; AL = its SFH
	push	bx
	sub	sp,size SPB
	mov	di,sp			; ES:DI -> SPB on the stack
	push	ax
	sub	ax,ax
	stosw				; SPB_ENVSEG <- 0
	mov	ax,si
	stosw				; SPB_CMDLINE.OFF
	mov	ax,ds
	stosw				; SPB_CMDLINE.SEG
	pop	ax
	stosb				; SPB_SFHIN
	stosb				; SPB_SFHOUT
	stosb				; SPB_SFHERR
	mov	ax,word ptr ds:[PSP_PFT][STDAUX]
	stosw				; SPB_SFHAUX and SPB_SFHPRN
	mov	bx,sp			; ES:BX -> SPB
	sub	cx,cx			; CH = 0 (no programs follow)
	DOSUTIL	LOAD,1			; load it (into its own LDT)
	jc	st4
	DOSUTIL	START			; start the session (CL)
st4:	lea	sp,[bx + size SPB]
	pop	bx			; BX = handle
	pushf
	push	ax
	mov	ah,DOS_HDL_CLOSE
	int	21h			; close our handle for the console
	pop	ax
	popf
	pop	di			; DI -> the end of the name
	pop	bx			; BX -> CMDHEAP
	jnc	st9
	mov	byte ptr [di],0		; the name alone, for openError
	jmp	openError		; report error AX for program SI
st9:	ret
ENDPROC	cmdStartSes

	DEFSTR	CON_NAME,<"VKD$:80,25,0,0,1",0>	; (1 takes the focus)
	DEFSTR	V86_COM,<"V86.COM",0>

CODE	ENDS

	end
