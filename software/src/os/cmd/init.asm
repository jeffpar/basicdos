;
; BASIC-DOS Command Processor: Startup
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This is the last module of COMMAND's core (see CMD.LRF), and it's the
; core's startup portion (from CORE_INIT to CORE_END): code that runs only
; when COMMAND starts.  When the loader loads only the core, main discards
; that portion once startup is done (see endInit).
;
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<ctrlc,bootTime>
	EXTBYTE	<CMD_PATH,MSG_DRIVE,RES_HEAP>
	EXTWORD	<CMD_REFS,CODE_DS>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

	DEFLBL	CORE_INIT,byte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdInit
;
; Called by main to set up a new copy of COMMAND.
;
; Inputs:
;	DS = ES = SS = our PSP
;
; Outputs:
;	BX -> CMDHEAP
;	AL = length of the startup command (in INPUTBUF), if any
;
; Modifies:
;	Any
;
DEFPROC	cmdInit
;
; If we're the copy that owns the shared code (ie, the code is in our memory
; block), the loader has already put our heap and stack in RES_HEAP (see
; COMHEAP), so we record what we need to reload the transient portion later
; (see runTransient in res.asm), and main releases what follows our code once
; we return (see endInit).  Any other copy's heap starts right after its PSP
; (see load_program), which is how we tell them apart without comparing CS
; and DS (which are different selectors in protected mode, even for the
; owner).
;
; At ring 3, no copy owns the code: it's in a code block that every copy can
; read but none can write (see r3_share in the kernel), so nothing here that
; changes can be the same for every copy; CODE_DS stays zero, and there's no
; transient portion to discard (see transParas).
;
; The core's COMDATA declares no shared code (see CORE_END), since another
; copy would run startup code that main has discarded, so the loader leaves
; PSP_CODESIZE zero when it loads only the core, and we set it to the end of
; the code that remains after startup (CORE_INIT).
;
	cmp	word ptr ds:[PSP_HEAP],size PSP
	je	ci2			; we don't own the shared code
	ASSUME	DS:CODE
	mov	[CODE_DS],ds		; (for every copy's writes to CODE)
	cmp	word ptr ds:[PSP_CODESIZE],0	; only the core loaded?
	jne	ci1				; no
	mov	word ptr ds:[PSP_CODESIZE],offset DGROUP:CORE_INIT
ci1:	mov	ax,DOS_MSC_GETPCH
	int	21h			; DL = path char, DH = system drive
	mov	[CMD_PATH],dh		; COMMAND.COM is in its root (see
	mov	[MSG_DRIVE],dh		; buildEnv, which every copy uses)
	mov	[CMD_PATH+2],dl
	ASSUME	DS:DATA
ci2:	mov	cx,cs:[CODE_DS]
	jcxz	ci3			; no copy owns the code (see above)
	push	ds
	mov	ds,cx
	ASSUME	DS:CODE
	inc	[CMD_REFS]
	pop	ds
	ASSUME	DS:DATA
ci3:
;
; Get the current session's screen dimensions (AL=cols, AH=rows).
;
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDIM
	mov	bx,STDOUT
	int	21h
	jnc	ci4			; carry clear if BASIC-DOS

;	mov	dx,offset WRONG_OS
;	mov	ah,DOS_TTY_PRINT	; use DOS_TTY_PRINT instead of PRINTF
;	int	21h			; since PC DOS wouldn't understand that
;	ret
;	DEFSTR	WRONG_OS,<"BASIC-DOS required",13,10,'$'>

	mov	dx,(25 SHL 8) OR 80	; STDOUT doesn't support GETDIM; use 80x25

ci4:	mov	bx,ds:[PSP_HEAP]
	DBGINIT	STRUCT,[bx],CMD
	mov	[bx].CON_COLS,dl
	mov	ax,word ptr ds:[PSP_PFT][STDIN]
	mov	word ptr [bx].SFH_STDIN,ax
	mov	ax,DOS_MSC_GETPCH
	int	21h			; DL = path char (fixed at boot)
	mov	[bx].PATH_CHAR,dl
	mov	ax,DOS_MSC_GETSWC
	int	21h			; DL = switch char (fixed at boot)
	mov	[bx].SWITCH_CHAR,dl
	call	initEnv			; set up the environment (and check /C)
;
; Install CTRLC handler.  DS = CS only for the first instance; additional
; instances of this processor will have their own DS but share a common CS.
;
	push	ds
	push	cs
	pop	ds
	mov	dx,offset ctrlc		; DS:DX -> CTRLC handler
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	int	21h
;
; Ask for exception signals, so that FPU$'s errors (a division by zero, an
; overflow, or an invalid result, which it reports with INT 00h and INT 04h)
; become runtime errors (see ctrlc).
;
	mov	ax,(DOS_MSC_CTRLC SHL 8) OR CTRLC_SETSIGS
	mov	dl,1
	int	21h
;
; Get the address of the FPU$ driver's function table (FPUTBL), which the
; code generator uses for all floating-point operations; each copy keeps its
; own pointer, in its PSP (PSP_FPUTBL), since shared code can't be written.
; If there's no FPU$ driver, PSP_FPUTBL remains zero, which also disables
; doubles (see getNextToken and genExpr).
;
	push	bx
	mov	dx,offset FPU_NAME	; DS:DX -> FPU_NAME (DS = CS)
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	ci5
	xchg	bx,ax			; BX = handle
	push	ss
	pop	ds
	mov	si,PSP_FPUTBL		; DS:SI -> PSP_FPUTBL
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETFPU
	int	21h			; DH = FPU type
	mov	ah,DOS_HDL_CLOSE
	int	21h
ci5:	pop	bx
	pop	ds

	test	[bx].CMD_FLAGS,CMD_SINGLE
	jz	ci5a
	jmp	ci7			; no banner for COMMAND /C
ci5a:	PRINTF	<"BASIC-DOS Command Shell",13,10>
;
; If this is one of several VKD$ consoles, and the one with focus, mention how
; to switch between them (IOCTL_GETMODE with CL = 2 returns the number of VKD$
; consoles in DL, and DH = 1 if this one has focus): SHIFT-TAB, unless there's
; a HOTKEY= setting (see SYSINFO).
;
	push	bx
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETMODE
	mov	bx,STDOUT
	mov	cl,2
	int	21h			; DL = consoles, DH = 1 if focus
	pop	bx
	jc	ci6			; (STDOUT isn't VKD$)
	cmp	dx,0102h		; focus and more than one console?
	jb	ci6			; no
	sub	sp,size SYSINFO
	mov	di,sp			; ES:DI -> SYSINFO (on the stack)
	mov	cl,-1
	DOSUTIL	QRYSCB			; get the system's SYSINFO
	mov	al,es:[di].SI_HOTKEY
	add	sp,size SYSINFO
	test	al,al			; is there a HOTKEY= setting?
	jz	ci5b			; no
	add	al,'@'			; AL = its letter
	PRINTF	<"Press Ctrl-%c to switch sessions",13,10>,ax
	jmp	short ci6
ci5b:	PRINTF	<"Press Shift-Tab to switch sessions",13,10>
ci6:	PRINTF	<13,10>
ci7:
	call	bootTime		; remove any /Q, and prompt if needed
;
; NOTE: The original plan was to use Microsoft's MBF (Microsoft Binary Format)
; floating-point code from GW-BASIC, but BASIC-DOS will instead implement its
; own IEEE 754 64-bit floating-point support, so no MBF-related code (or MSLIB
; option) is used.  Until then, BASIC-DOS is just an "Integer BASIC".
;
; Check the PSP_CMDTAIL for a startup command.  Startup commands must be
; explicitly provided; there is no support for a global AUTOEXEC.BAT, since
; 1) it's likely each session will want its own startup command(s), and 2)
; it's easy enough to specify the name of any desired BAT file on any or all
; of the SHELL= lines in CONFIG.SYS.
;
; If a tail exists, we copy it (with its length byte and CHR_RETURN) into
; INPUTBUF, and then jump into the command-processing code below.  It isn't
; processed in place, because PSP_CMDTAIL is also the default DTA, so a
; command that uses the DTA (eg, TYPE or COPY) would overwrite the rest of it.
; We skip its leading spaces (eg, the separator after the program name), since
; INPUTBUF is also what the first prompt's line editor recalls.  The tail
; always ends with a CHR_RETURN (see load_args), which ends the scan if it's
; all spaces.
;
	lea	di,[bx].INPUTBUF
	mov	[bx].INPUT_BUF,di
	mov	al,size INP_DATA - 1
	stosb				; set INP_MAX
	mov	si,PSP_CMDTAIL
	lodsb
	cbw
	xchg	cx,ax			; CX = length of tail
ci8:	cmp	byte ptr [si],CHR_SPACE
	jne	ci9
	inc	si
	loop	ci8
ci9:	mov	al,cl
	stosb				; set INP_CNT
	inc	cx			; include the CHR_RETURN
	rep	movsb			; copy INP_DATA
	and	[bx].CMD_FLAGS,NOT CMD_NOECHO
	ret
ENDPROC	cmdInit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; initEnv
;
; Sets PATH$ from our own environment's PATH, if any (eg, when MAKE runs
; "COMMAND /C"), and checks the command tail for /C, which runs the rest of
; the tail as a command and then exits.
;
; Inputs:
;	BX -> CMDHEAP
;	DS = ES = SS
;
; Outputs:
;	CMD_SINGLE set in CMD_FLAGS if /C was specified
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	initEnv
	mov	[bx].EXECDATA.EPB_ENVSEG,0; no environment yet (see buildEnv)
	push	ds
	mov	ds,ds:[PSP_ENVSEG]
	mov	ax,ds
	test	ax,ax			; do we have an environment?
	jz	ie6			; no
	sub	si,si			; DS:SI -> environment
ie2:	cmp	byte ptr [si],0		; end of the environment?
	je	ie6			; yes
	cmp	word ptr [si],'AP'	; "PATH="?
	jne	ie3
	cmp	word ptr [si+2],'HT'
	jne	ie3
	cmp	byte ptr [si+4],'='
	je	ie4			; yes
ie3:	lodsb				; no, so skip to the next variable
	test	al,al
	jnz	ie3
	jmp	ie2
ie4:	add	si,5
	lea	di,[bx].PATH_BUF+1	; ES:DI -> PATH_BUF characters
	mov	dx,di
	mov	cx,120
ie5:	lodsb
	test	al,al
	jz	ie5a
	stosb
	loop	ie5
ie5a:	mov	byte ptr es:[di],0
	sub	di,dx
	xchg	ax,di			; AL = length
	mov	es:[bx].PATH_BUF,al
ie6:	pop	ds
	mov	si,PSP_CMDTAIL
	lodsb
	cbw
	xchg	cx,ax			; CX = length of tail
	jcxz	ie9
ie7:	lodsb
	cmp	al,CHR_SPACE		; skip leading whitespace
	ja	ie8
	loop	ie7
	ret
ie8:	cmp	al,'/'			; "/C" (as the C runtime uses)?
	je	ie8a
	cmp	al,[bx].SWITCH_CHAR	; or the switch char?
	jne	ie9
ie8a:	mov	al,[si]
	or	al,20h
	cmp	al,'c'
	jne	ie9
	cmp	byte ptr [si+1],CHR_SPACE
	ja	ie9
	mov	word ptr [si-1],(CHR_SPACE SHL 8) OR CHR_SPACE
	or	[bx].CMD_FLAGS,CMD_SINGLE; blank the switch and set the flag
ie9:	ret
ENDPROC	initEnv

	DEFSTR	FPU_NAME,<"FPU$",0>
;
; This is the end of COMMAND's core.  The modules linked after this one (see
; CMD.LRF) are omitted when there isn't enough memory for the entire image,
; and CORE_END tells the loader how much to load then (see CD_CORESIZE in
; dosapi.inc).  The core's own COMDATA keeps the heap in RES_HEAP but declares
; no shared code (see cmdInit), so unlike the entire image (see HEAP.ASM), it
; needs no heap template for other copies.
;
hparas	equ	(size CMDHEAP + 15) SHR 4
	COMDATA	<offset DGROUP:RES_HEAP,0,hparas,0,SIG_BASICDOS>
	DEFLBL	CORE_END,word

CODE	ENDS

	end
