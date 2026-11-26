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
	include	cpu.inc

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
; in CONFIG.SYS gives a COMMAND one (eg, COMMAND.COM PATH$="A:\;A:\EXT\CMD":X),
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
; Process "START [/B] program [arguments]" (or START alone, which lists the
; sessions; see below), which runs the program (a COM or EXE
; file, found the way an external command is; see findProgram) in a new
; session, whose console is a new one on our own console's device (we open
; CON with a descriptor; see chk_devname): for VKD$, a full-screen console,
; and for a COM port, another console on the same terminal.  It takes the
; focus, unless /B (background) comes before the program (any switches after
; the program are its own; see cmdDOS).  Like a session from CONFIG.SYS, it
; has its own LDT (see DOS_UTL_LOAD), but its program can end (eg, COMMAND's
; EXIT), which closes the session and its console, and the focus goes back to
; the console that had it.  On success with /B, we display the new session's
; number (eg, for KILL or "> @n").
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
	jc	lss0			; no program name
	jmp	st1
;
; There's no program name, so list every session with a program: its number
; (from 1, as used by KILL), how much memory it's using (in K), its program
; ("UNKNOWN" if DOS can't tell), and the BASIC program it's running, if any
; (eg, "COMMAND DONKEY"), marking the current session with "*".
;
lss0:	sub	sp,16
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> buffer for the names
	DOSUTIL	GETCSN			; CL = current session #
	mov	bl,cl			; BL = current session #
	sub	cx,cx			; CL = session # (from 0)
lss1:	DOSUTIL	QRYSCB,1		; AX = PSP, SI:DX = bytes, and names
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
	PRINTF	<"UNKNOWN">
	jmp	short lss5
lss4:	PRINTF	<"%.8ls">,di,es		; (padded with spaces)
;
; The BASIC program's name, if any (zeros if none), is as it was given (eg,
; LOAD donkey), so it's converted to upper case, like the program names.
;
lss5:	lea	si,[di+8]		; SI -> the BASIC program's name
	push	cx
	mov	cx,8
	DOSUTIL	STRUPR
	pop	cx
	PRINTF	<"%.8ls",13,10>,si,es
lss8:	inc	cx
	jmp	lss1
lss9:	add	sp,16
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
	mov	dx,offset CON_NAME
	TESTSW	<'B'>			; /B?
	jz	st2a			; no
	mov	dx,offset CON_BACK	; yes, so it doesn't take focus
st2a:	push	ds
	push	cs
	pop	ds			; DS:DX -> console name
	mov	ax,DOS_HDL_OPENRW
	int	21h			; AX = handle
	pop	ds
	pop	di			; DI -> the end of the name
	jc	st8			; (eg, no memory for another console)
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
	stosw				; SPB_CMDLINE._OFF
	mov	ax,ds
	stosw				; SPB_CMDLINE._SEG
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
	jc	st8
;
; Only a background session's number is displayed: otherwise, the new console
; has the focus, so the number would be seen only after the session ends.
;
	TESTSW	<'B'>			; /B?
	jz	st7			; no
	mov	ch,0
	inc	cx			; CX = session # (from 1)
	PRINTF	<"Started session %d",13,10>,cx
st7:	clc
	ret
st8:	mov	byte ptr [di],0		; the name alone, for openError
	jmp	openError		; report error AX for program SI
ENDPROC	cmdStartSes

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; startV86
;
; When cmdFile can't load a real-mode program in protected mode (ERR_BADMODE),
; and the processor has V86 mode, we run it as "START V86 program [arguments]"
; would: in a new session and console, whose V86 machine (and so the session)
; ends when the program does.  If its STDIN or STDOUT is redirected (eg, to a
; pipe), which a new console would replace, we report the error instead.
;
; Inputs:
;	BP -> CMDHEAP
;	DS:SI -> the program's name (in LINEBUF)
;	CMD_ARGPTR and CMD_ARGLEN -> the name as given (the arguments follow)
;
; Outputs:
;	Carry clear if successful, set if error (reported)
;
; Modifies:
;	Any
;
DEFPROC	startV86
	mov	bx,bp			; BX -> CMDHEAP
	mov	ax,word ptr [bx].SFH_STDIN
	xchg	ax,word ptr ds:[PSP_PFT][STDIN]	; (for openError; see cf8)
	cmp	ax,word ptr [bx].SFH_STDIN	; STDIN or STDOUT redirected?
	jne	sv8			; yes
	call	chkV86			; V86 mode?
	jc	sv8			; no
;
; Switches are parsed only for internal commands, so clear any /B left over
; from one (eg, COPY /B), which would keep the new console from taking the
; focus (see cmdStartSes).
;
	and	byte ptr ds:[PSP_LETTERS],0FDh
;
; V86's arguments are the program's name and arguments, which we copy to the
; stack, since finding V86 reuses LINEBUF.
;
	mov	di,[bx].CMD_ARGPTR
	add	di,[bx].CMD_ARGLEN	; DI -> the arguments
	mov	dx,di
sv1:	mov	al,[di]
	inc	di
	cmp	al,CHR_RETURN		; the end of the arguments?
	ja	sv1			; no
	sub	di,dx			; DI = their length (with the end)
	DOSUTIL	STRLEN			; AX = the name's length
	xchg	cx,ax			; CX = the name's length
	lea	ax,[di+1]
	add	ax,cx
	and	al,0FEh			; AX = length of both (even)
	mov	bp,sp			; BP = SP to restore
	sub	sp,ax
	xchg	ax,di			; AX = the arguments' length
	mov	di,sp			; ES:DI -> the copy
	rep	movsb			; copy the name
	xchg	cx,ax			; CX = the arguments' length
	mov	si,dx
	rep	movsb			; and the arguments
	lea	si,[bx].LINEBUF
	mov	word ptr [si],('8' SHL 8) OR 'V'
	mov	word ptr [si+2],'6'	; DS:SI -> "V86"
	mov	cl,3			; CX = its length
	mov	ax,sp			; AX -> its arguments
	call	st1			; START it
	mov	sp,bp
	ret
sv8:	mov	ax,ERR_BADMODE		; report the error after all
	jmp	openError
ENDPROC	startV86

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86Hint
;
; After fileError reports a real-mode program that protected mode can't load
; (ERR_BADMODE), add how to run it, if the processor has V86 mode.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	v86Hint
	push	ax
	call	chkV86			; V86 mode?
	jc	vh9			; no
	PRINTF	<"Run START V86 first",13,10>
vh9:	pop	ax
	ret
ENDPROC	v86Hint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkV86
;
; Checks whether the processor has V86 mode (the same test that V86.COM
; makes).
;
; Inputs:
;	None
;
; Outputs:
;	Carry clear if so, set if not
;
; Modifies:
;	AX
;
DEFPROC	chkV86
	push	cx
	push	di
	push	es
	push	ss
	pop	es
	sub	sp,size SYSINFO
	mov	di,sp			; ES:DI -> SYSINFO (on the stack)
	mov	cl,-1
	DOSUTIL	QRYSCB			; get the system's SYSINFO
	mov	al,es:[di].SI_CPUTYPE
	add	sp,size SYSINFO
	cmp	al,CPUTYPE_80386	; 80386 features (so V86 mode)?
	pop	es
	pop	di
	pop	cx
	ret
ENDPROC	chkV86

;
; For VKD$, an adapter of 2 is the adapter of our own console (see ddcon_open).
;
	DEFSTR	CON_NAME,<"CON:80,25,0,2,1",0>	; (1 takes the focus)
	DEFSTR	CON_BACK,<"CON:80,25,0,2",0>	; (by default, it doesn't)
	DEFSTR	V86_COM,<"V86.COM",0>

CODE	ENDS

	end
