;
; BASIC-DOS Command Interpreter
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

DGROUP	group	CODE,TOKDATA,STRDATA

CODE    SEGMENT word public 'CODE'
	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	lea	bx,[DGROUP:heap]
	mov	[bx].ORIG_SP.SEG,ss
	mov	[bx].ORIG_SP.OFF,sp
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	mov	dx,offset ctrlc
	int	21h

	PRINTF	<"BASIC-DOS Interpreter",13,10,13,10,"BASIC MATH library functions",13,10,"Copyright (c) Microsoft Corporation",13,10>
;
; Since all the command handlers loop back to this point, we should not
; assume that any registers (including BX) will still be set to anything.
;
m1:	lea	bx,[DGROUP:heap]
	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	al,'A'		; AL = current drive letter
	PRINTF	"%c>",ax

	mov	[bx].INPUT.INP_MAX,size INP_BUF
	lea	dx,[bx].INPUT
	mov	ah,DOS_TTY_INPUT
	int	21h

	mov	si,dx		; DS:SI -> input buffer
	lea	di,[bx].TOKENS
	mov	[di].TOK_MAX,size TOK_BUF SHR 1
	mov	ax,DOS_UTL_TOKIFY
	int	21h
	xchg	cx,ax		; CX = token count from AX
	jcxz	m1		; jump if no tokens
;
; Before trying to ID the token, let's copy it to the FILENAME buffer,
; upper-case it, and null-terminate it.
;
	GETTOKEN 1		; DS:SI -> token #1, CX = length
	lea	di,[bx].FILENAME
	push	cx
	push	di
	rep	movsb
	pop	si		; DS:SI -> copy of token in FILENAME
	pop	cx
	mov	ax,DOS_UTL_STRUPR
	int	21h		; DS:SI -> upper-case token, CX = length
	mov	ax,DOS_UTL_TOKID
	lea	di,[DGROUP:CMD_TOKENS]
	int	21h		; identify the token
	jc	m2
	jmp	m9		; token ID in AX, token data in DX
;
; First token is unrecognized, so we'll assume it's either a drive
; specification or a program name.
;
m2:	mov	dx,si		; DS:DX -> FILENAME
	cmp	cl,2		; two characters only?
	jne	m3		; no
	cmp	byte ptr [si+1],':'
	jne	m3		; not a valid drive specification
	mov	cl,[si]		; CL = drive letter
	mov	dl,cl
	sub	dl,'A'		; DL = drive number
	cmp	dl,26
	jae	m2a		; out of range
	mov	ah,DOS_DSK_SETDRV
	int	21h		; attempt to set the drive number in DL
	jnc	m2b		; success
m2a:	PRINTF	<"Drive %c: invalid",13,10>,cx
m2b:	jmp	m1

m3:	mov	di,dx		; ES:DI -> FILENAME
	mov	al,'.'
	push	cx
	push	di
	repne	scasb		; any periods in FILENAME?
	pop	di
	pop	cx
	je	m4		; yes
;
; First we're going to append .EXE, not because we prefer .EXE (we don't),
; but because if no .EXE exists, we want to revert to .COM.
;
	push	cx
	push	di
	add	di,cx		; append .EXE
	mov	si,offset EXE_EXT
	mov	cx,EXE_EXT_LEN
	rep	movsb
	pop	di
	mov	ah,DOS_DSK_FFIRST
	int	21h		; find file (DS:DX) with attributes (CX = 0)
	pop	cx
	jnc	m5

	push	cx
	add	di,cx		; append .COM
	mov	si,offset COM_EXT
	mov	cx,COM_EXT_LEN
	rep	movsb
	pop	cx
	jmp	m5
;
; The token contains a period, so let's verify the extension is valid
; (ie, .COM or .EXE); we don't want people running, say, "CONFIG.SYS".
;
m4:	mov	si,offset COM_EXT
	mov	di,dx
	mov	ax,DOS_UTL_STRSTR
	int	21h		; verify FILENAME contains either .COM
	jnc	m5
	mov	si,offset EXE_EXT
	int	21h		; or .EXE
	mov	ax,ERR_INVALID
	jc	m8		; looks like neither, so report an error
;
; It looks like we have a valid program name, so prepare to exec.
;
m5:	lea	si,[bx].INPUT.INP_BUF
	add	si,cx		; DS:SI -> cmd tail after filename
	lea	bx,[bx].EXECDATA
	mov	[bx].EPB_ENVSEG,0
	mov	di,PSP_CMDTAIL
	push	di
	mov	[bx].EPB_CMDTAIL.OFF,di
	mov	[bx].EPB_CMDTAIL.SEG,es
	inc	di		; use our cmd tail space to build a new tail
	mov	cx,-1
m6:	lodsb
	stosb
	inc	cx
	cmp	al,CHR_RETURN
	jne	m6
	pop	di
	mov	[di],cl		; set the cmd tail length
	mov	[bx].EPB_FCB1.OFF,PSP_FCB1
	mov	[bx].EPB_FCB1.SEG,es
	mov	[bx].EPB_FCB2.OFF,PSP_FCB2
	mov	[bx].EPB_FCB2.SEG,es

	mov	ax,DOS_PSP_EXEC
	int	21h		; exec program at DS:DX
	jc	m8
	mov	ah,DOS_PSP_RETCODE
	int	21h
	mov	dl,ah
	mov	ah,0
	mov	dh,0
	PRINTF	<13,10,"Return code: %d (%d)",13,10>,ax,dx
	jmp	m1
m8:	PRINTF	<"Error loading %s: %d",13,10>,dx,ax
	jmp	m1
;
; We arrive here if the token was recognized, but before we invoke the
; corresponding handler, we prep the 2nd token, if any, for convenience.
;
m9:	lea	di,[bx].TOKENS
	mov	cx,DIR_DEF_LEN - 1
	mov	si,offset DIR_DEF
	GETTOKEN 2		; DS:SI -> token #2, CX = length
	lea	di,[bx].FILENAME
	push	cx
	push	di
	rep	movsb
	mov	byte ptr es:[di],0
	pop	si		; DS:SI -> copy of token in FILENAME
	pop	cx
	mov	ax,DOS_UTL_STRUPR
	int	21h		; DS:SI -> upper-case token, CX = length
	call	dx		; call token handler
	jmp	m1
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ctrlc
;
; CTRLC handler; resets the program stack and jumps to the start address
;
; Inputs:
;	DS:SI -> user-defined token
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	ctrlc,FAR
	lea	bx,[DGROUP:heap]
	cli
	mov	ss,[bx].ORIG_SP.SEG
	mov	sp,[bx].ORIG_SP.OFF
	sti
	jmp	m1
ENDPROC	ctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDate
;
; TBD
;
; Inputs:
;	DS:SI -> user-defined token
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDate
	ret
ENDPROC	cmdDate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDir
;
; Print a directory listing for the specified filespec
;
; Inputs:
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDir
	mov	dx,si		; DS:DX -> filespec
;
; If filespec ends with ":", then append DIR_DEF ("*.*")
;
	mov	di,si
	add	di,cx
	cmp	byte ptr [di-1],':'
	jne	dir0
	mov	cx,DIR_DEF_LEN
	mov	si,offset DIR_DEF
	rep	movsb

dir0:	sub	cx,cx		; CX = attributes
	mov	ah,DOS_DSK_FFIRST
	int	21h
	jnc	dir1
	PRINTF	<"Unable to find %s: %d",13,10>,dx,ax
	jmp	dir9
dir1:	lea	si,ds:[PSP_DTA].FFB_NAME
;
; Beginning of "stupid" code to break filename into two separate parts....
;
	mov	ax,DOS_UTL_STRLEN
	int	21h
	xchg	cx,ax		; CX = total length
	mov	di,si
	push	si
	mov	si,offset PERIOD
	mov	ax,DOS_UTL_STRSTR
	int	21h		; if carry clear, DI is updated
	pop	si
	jc	dir2
	mov	ax,di
	sub	ax,si		; AX = partial filename length
	inc	di		; DI -> character after period
	jmp	short dir3
dir2:	mov	ax,cx		; AX = complete filename length
	mov	di,si
	add	di,ax
;
; End of "stupid" code (which I'm tempted to eliminate, but since it's done....)
;
dir3:	mov	dx,ds:[PSP_DTA].FFB_DATE
	mov	cx,ds:[PSP_DTA].FFB_TIME
	ASSERT	Z,<cmp ds:[PSP_DTA].FFB_SIZE.SEG,0>
	PRINTF	<"%-8.*s %-3s %7ld %2M-%02D-%02X %2G:%02N%A",13,10>,ax,si,di,ds:[PSP_DTA].FFB_SIZE.OFF,ds:[PSP_DTA].FFB_SIZE.SEG,dx,dx,dx,cx,cx,cx
	mov	ah,DOS_DSK_FNEXT
	int	21h
	jc	dir9
	jmp	dir1

dir9:	ret
ENDPROC	cmdDir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdExit
;
; Inputs:
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdExit
	int 3
	int	20h		; terminate
	ret			; unless we can't (ie, if no parent)
ENDPROC	cmdExit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdLoop
;
; Calls cmdDir in a loop (for "stress testing" purposes only)
;
; Inputs:
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdLoop
	push	cx
	push	si
	call	cmdDir
	pop	si
	pop	cx
	jmp	cmdLoop
ENDPROC	cmdLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdMem
;
; Prints memory usage
;
; Inputs:
;	DS:SI -> user-defined token (not used)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdMem
;
; Before we get into memory blocks, show the amount of memory reserved
; for the BIOS and disk buffers.
;
	push	bp
	push	es
	sub	di,di
	mov	es,di
	ASSUME	ES:BIOS
	les	di,[DD_LIST]
	ASSUME	ES:NOTHING
	mov	bx,es
	mov	ax,bx
	push	di
	mov	di,ds
	mov	si,offset RES_MEM
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
;
; Next, dump the list of resident built-in device drivers.
;
drv1:	cmp	di,-1
	je	drv9
	lea	si,[di].DDH_NAME
	mov	bx,es
	mov	cx,bx
	mov	ax,es:[di].DDH_NEXT_SEG
	sub	ax,cx		; AX = # paras
	push	di
	mov	di,bx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
	les	di,es:[di]
	jmp	drv1
;
; Next, dump the size of the operating system, which resides between the
; built-in device drivers and the first memory block.
;
drv9:	mov	bx,es		; ES = DOS data segment
	mov	ax,es:[0]	; ES:[0] is mcb_head
	mov	bp,es:[2]	; ES:[2] is mcb_limit
	sub	ax,bx
	mov	di,ds
	mov	si,offset DOS_MEM
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	es
	ASSUME	ES:CODE
;
; Next, examine all the memory blocks and display those that are used.
;
	push	bp
	sub	cx,cx
	sub	bp,bp		; BP = free memory
mem1:	mov	dl,0		; DL = 0 (query all memory blocks)
	mov	di,ds		; DI:SI -> default owner name
	mov	si,offset SYS_MEM
	mov	ax,DOS_UTL_QRYMEM
	int	21h
	jc	mem9		; all done
	test	ax,ax		; free block (is OWNER zero?)
	jne	mem2		; no
	add	bp,dx		; yes, add to total free paras
	jmp	short mem8
mem2:	mov	ax,dx		; AX = # paras
	push	cx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	cx
mem8:	inc	cx
	jmp	mem1
mem9:	xchg	ax,bp		; AX = free memory (paras)
	pop	bp		; BP = total memory (paras)
;
; Last but not least, dump the amount of free memory.
;
	mov	cx,16
	mul	cx		; DX:AX = free memory (in bytes)
	xchg	si,ax
	mov	di,dx		; DI:SI = free memory
	xchg	ax,bp
	mul	cx		; DX:AX = total memory (in bytes)
	PRINTF	<"%8ld bytes total",13,10,"%8ld bytes free",13,10>,ax,dx,si,di
	pop	bp
	ret
ENDPROC	cmdMem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdPrint
;
; Prints the specified value, in both decimal and hex (for test purposes only)
;
; Inputs:
;	DS:SI -> user-defined token
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdPrint
	mov	bl,10		; default to base 10
	mov	cx,si		; check for "0x" prefix (upper-cased)
	cmp	word ptr [si],"X0"
	jne	pr1
	mov	bl,16		; the prefix is present, so switch to base 16
	add	si,2		; and skip the prefix
pr1:	mov	ax,DOS_UTL_ATOI32
	int	21h
	jc	pr8		; apparently not a number
	PRINTF	<"Value is %ld (%#lx)",13,10>,ax,dx,ax,dx
	jmp	short pr9
pr8:	PRINTF	<"Invalid number: %s",13,10>,cx
pr9:	ret
ENDPROC	cmdPrint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdTime
;
; TBD
;
; Inputs:
;	DS:SI -> user-defined token
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdTime
	ret
ENDPROC	cmdTime

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdType
;
; Reads the specified file and writes it to STDOUT
;
; Inputs:
;	DS:SI -> user-defined token
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdType
	mov	dx,si		; DS:DX -> filename
	mov	ax,DOS_HDL_OPEN SHL 8
	int	21h
	jnc	ty1		; AX = file handle if successful, else error
	PRINTF	<"Unable to open %s: %d",13,10>,dx,ax
	jmp	short ty9
ty1:	xchg	bx,ax		; BX = file handle
	mov	dx,PSP_DTA	; DS:DX -> DTA (as good a place as any)
ty2:	mov	cx,size PSP_DTA	; CX = number of bytes to read
	mov	ah,DOS_HDL_READ
	int	21h
	jc	ty8		; silently fail (for now)
	test	ax,ax		; anything read?
	jz	ty8		; no
	push	bx
	mov	bx,STDOUT
	xchg	cx,ax		; CX = number of bytes to write
	mov	ah,DOS_HDL_WRITE
	int	21h
	pop	bx
	jmp	ty2
ty8:	mov	ah,DOS_HDL_CLOSE
	int	21h
ty9:	ret
ENDPROC	cmdType

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printKB
;
; Calculates AX/64 (or AX >> 6) as the size in Kb; however, that's a bit too
; granular, so we include tenths of Kb as well.  Using the paragraph remainder
; (R), we calculate tenths (N) like so:
;
;	R/64 = N/10, or N = (R*10)/64
;
; Inputs:
;	AX = size in paragraphs
;	BX = segment of memory block
;	DI:SI -> "owner" name for memory block
;
; Outputs:
;	None
;
DEFPROC	printKB
	push	ax
	push	bx
	mov	bx,64
	sub	dx,dx		; DX:AX = paragraphs
	div	bx		; AX = Kb
	xchg	cx,ax		; save Kb in CX
	xchg	ax,dx		; AX = paragraphs remainder
	mov	bl,10
	mul	bx		; DX:AX = remainder * 10
	mov	bl,64
	or	ax,31		; round up without adding
	div	bx		; AX = tenths of Kb
	ASSERT	NZ,<cmp ax,10>
	xchg	dx,ax		; save tenths in DX
	pop	bx
	pop	ax
	PRINTF	<"%#06x: %#06x %3d.%1dK %.8ls",13,10>,bx,ax,cx,dx,si,di
	ret
ENDPROC	printKB

	DEFSTR	COM_EXT,<".COM",0>
	DEFSTR	EXE_EXT,<".EXE",0>
	DEFSTR	DIR_DEF,<"*.*",0>
	DEFSTR	PERIOD,<".",0>
	DEFSTR	RES_MEM,<"RESERVED",0>
	DEFSTR	SYS_MEM,<"SYSTEM",0>
	DEFSTR	DOS_MEM,<"DOS",0>

	DEFTOKENS CMD_TOKENS,NUM_TOKENS
	DEFTOK	TOK_DATE,  0, "DATE",	cmdDate
	DEFTOK	TOK_DIR,   1, "DIR",	cmdDir
	DEFTOK	TOK_EXIT,  2, "EXIT",	cmdExit
	DEFTOK	TOK_LOOP,  3, "LOOP",	cmdLoop
	DEFTOK	TOK_MEM,   4, "MEM",	cmdMem
	DEFTOK	TOK_PRINT, 5, "PRINT",	cmdPrint
	DEFTOK	TOK_TIME,  6, "TIME",	cmdTime
	DEFTOK	TOK_TYPE,  7, "TYPE",	cmdType
	NUMTOKENS CMD_TOKENS,NUM_TOKENS

STRDATA SEGMENT
	COMHEAP	<size CMD_WS>	; COMHEAP (heap size) must be the last item
STRDATA	ENDS

CODE	ENDS

	end	main
