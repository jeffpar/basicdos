;
; BASIC-DOS Library Console Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTERNS	<freeStr,parseSW>,near

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clearScreen
;
; Used by "CLS".
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX
;
DEFPROC	clearScreen,FAR
	mov	bx,STDOUT
	sub	cx,cx
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_SCROLL
	int	21h
	ret
ENDPROC	clearScreen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doCmd
;
; Process generic command generated by genCmd.
;
; Inputs:
;	[pHandler] -> offset of handler
;	[pCmdLine] -> seg:off of original command line
;	[cbCmdLine] -> length of original command line
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	doCmd,FAR
	ARGVAR	pHandler,word
	ARGVAR	pCmdLine,dword
	ARGVAR	cbCmdLine,word
	ENTER
	push	ds
	push	ss
	pop	es
	mov	bx,es:[PSP_HEAP]
	mov	cx,[cbCmdLine]
	lds	si,[pCmdLine]
	mov	dx,[pHandler]
	mov	bp,es:[bx].ORIG_BP	; can't access ARGVARs anymore
	lea	di,es:[bx].LINEBUF	; ES:DI -> LINEBUF
	push	cx
	push	di
	rep	movsb
	xchg	ax,cx			; AL = 0
	stosb				; ensure the line is null-terminated
	push	es
	pop	ds
	pop	si			; DS:SI -> LINEBUF
	pop	cx			; CX = length of line in LINEBUF
	lea	di,[bx].TOKENBUF	; ES:DI -> TOKENBUF
	mov	[di].TOK_MAX,(size TOK_BUF) / (size TOKLET)
	DOSUTIL	DOS_UTL_TOKIFY1
	ASSERT	NC
	push	dx			; save the handler address
	call	parseSW			; parse all switch arguments, if any
	pop	ax			; restore the handler address
	call	ax			; call the handler
	pop	ds
	LEAVE
	ret	8
ENDPROC	doCmd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printArgs
;
; Used by "PRINT [args]"
;
; Since expressions are evaluated left-to-right, their results are pushed
; left-to-right as well.  Since the number of parameters is variable, we
; walk the stacked parameters back to the beginning, pushing the offset of
; each as we go, and then popping and printing our way back to the end again.
;
; Inputs:
;	N pairs of variable types/values pushed on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	printArgs,FAR
	mov	bp,sp
	add	bp,4
	sub	bx,bx
	push	bx			; push end-of-args marker
	mov	bx,bp

pa1:	mov	al,[bp]			; AL = arg type
	test	al,al
	jz	pa3
pa2:	push	bp
	lea	bp,[bp+2]
	cmp	al,VAR_INT
	jb	pa1
	lea	bp,[bp+2]
	je	pa1
	lea	bp,[bp+2]
	cmp	al,VAR_DOUBLE
	jb	pa1
	ASSERT	Z			; if AL > VAR_DOUBLE that's trouble
	lea	bp,[bp+4]		; because we don't know how to print
	jmp	pa1			; VAR_FUNC or VAR_ARRAY variables

pa3:	mov	al,VAR_NEWLINE
	lea	bp,[bp+2]
	sub	bp,bx
	mov	bx,bp			; BX = # bytes to clean off stack

pa4:	pop	bp
	test	bp,bp			; end-of-args marker?
	jz	pa8			; yes

	mov	al,[bp]			; AL = arg type
	cmp	al,VAR_SEMI
	je	pa4a
	cmp	al,VAR_COMMA
	jne	pa5
	PRINTF	<CHR_TAB>
pa4a:	mov	al,VAR_NONE		; if we end on this, there's no NEWLINE
	jmp	pa4
;
; Check for numeric types first.  VAR_LONG is it for now.
;
pa5:	cmp	al,VAR_LONG
	jne	pa6
	mov	ax,[bp+2]
	mov	dx,[bp+4]
;
; As the itoa code in sprintf.asm explains, we use the '#' (hash) flag with
; decimal output to signify that a space should precede positive values.
;
	PRINTF	<"%#ld ">,ax,dx		; DX:AX = 32-bit value
	jmp	pa4
;
; Check for string types next.  VAR_STR is a normal string reference (eg,
; a string constant in a code block, or a string variable in a string block),
; whereas VAR_TSTR is a temporary string (eg, the result of some string
; operation) which we must free after printing.
;
pa6:	cmp	al,VAR_TSTR
	jbe	pa7
	ASSERT	NEVER			; more types may be supported someday
	jmp	pa4

pa7:	push	ax
	push	ds
	lds	si,[bp+2]
;
; Write AX bytes from DS:SI to STDOUT.  PRINTF would be simpler, but it's
; not a good idea, largely because the max length of string is greater than
; our default PRINTF buffer, and because it would be slower with no benefit.
;
	call	writeStr

	pop	ds
	pop	ax
	cmp	al,VAR_TSTR		; if it's not VAR_TSTR
	jne	pa4			; then we're done

	push	ds
	pop	es
	lea	di,[si-1]
	call	freeStr			; ES:DI -> string data to free
	jmp	pa4
;
; We've reached the end of arguments, wrap it up.
;
pa8:	test	al,al			; unless AL is zero
	jz	pa9			; we want to end on a new line
	PRINTF	<13,10>

pa9:	pop	dx			; remove return address
	pop	cx
	add	sp,bx			; clean the stack
	push	cx			; restore the return address
	push	dx
	ret
ENDPROC	printArgs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printEcho
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	printEcho,FAR
	mov	bx,ss:[PSP_HEAP]
	test	ss:[bx].CMD_FLAGS,CMD_ECHO
	jz	pe1
	PRINTF	<"Echo is ON",13,10>
	ret
pe1:	PRINTF	<"Echo is OFF",13,10>
	ret
ENDPROC	printEcho

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printLine
;
; Inputs:
;	Pointer to length-prefixed string pushed on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	printLine,FAR
	mov	bx,ss:[PSP_HEAP]
	test	ss:[bx].CMD_FLAGS,CMD_ECHO
	jnz	pl1
	ret	4
pl1:	PRINTF	<13,10>			; fall into printStr
ENDPROC	printLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printStr
;
; Inputs:
;	Pointer to length-prefixed string pushed on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	printStr,FAR
	ARGVAR	pStr,dword
	ENTER
	push	ds
	lds	si,[pStr]		; DS:SI -> length-prefixed string
	call	writeStrCRLF
	pop	ds
	LEAVE
	RETURN
ENDPROC	printStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeStr
;
; Inputs:
;	DS:SI -> length-prefixed string
;
; Outputs:
;	AX = # bytes printed
;	SI updated to end of string
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	writeStr
	push	bx
	lodsb				; AL = string length (255 max)
	mov	ah,0
	xchg	cx,ax			; CX = length
	mov	dx,si			; DS:DX -> data
	add	si,cx
	mov	bx,STDOUT
	mov	ah,DOS_HDL_WRITE
	int	21h
	pop	bx
	ret
ENDPROC	writeStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeStrCRLF
;
; Inputs:
;	DS:SI -> length-prefixed string
;
; Outputs:
;	AX = # bytes written
;	SI updated to end of string
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	writeStrCRLF
	call	writeStr
	PRINTF	<13,10>
	ret
ENDPROC	writeStrCRLF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setColor
;
; Used by "COLOR fgnd[,bgnd[,border]]"
;
; Inputs:
;	N numeric expressions pushed on stack (only 1st 3 are processed)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	setColor,FAR
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETCOLOR
	mov	bx,STDOUT
	int	21h
	xchg	dx,ax			; DX = current colors
	pop	si
	pop	di			; DI:SI = return address
	pop	cx			; CX = # args
sc1:	cmp	cl,4
	jb	sc2
	pop	ax
	pop	bx
	dec	cx
	jmp	sc1
sc2:	cmp	cl,3
	jne	sc3
	pop	ax
	pop	bx
	mov	dh,al
	dec	cx
sc3:	cmp	cl,2
	jne	sc4
	pop	ax
	pop	bx
	and	al,0Fh
	and	dl,0Fh
	shl	al,cl
	shl	al,cl
	or	dl,al
	dec	cx
sc4:	cmp	cl,1
	jne	sc5
	pop	ax
	pop	bx
	and	al,0Fh
	and	dl,0F0h
	or	dl,al
sc5:	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_SETCOLOR
	mov	bx,STDOUT
	mov	cx,dx			; CX = new colors
	int	21h
	push	di			; push return address back on stack
	push	si
	ret
ENDPROC	setColor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setFlags
;
; If AL contains a single bit, that bit will be set in CMD_FLAGS;
; otherwise, AL will be applied as a mask to CMD_FLAGS.
;
; Inputs:
;	AL = bit to set or clear in CMD_FLAGS
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	setFlags,FAR
	mov	bx,ss:[PSP_HEAP]
	mov	ah,al
	dec	ah			; AH = flags - 1
	and	ah,al			; if (flags - 1) AND flags is zero
	jz	sf1			; then AL contains a single bit to set
	and	ss:[bx].CMD_FLAGS,al
	xor	al,al
sf1:	or	ss:[bx].CMD_FLAGS,al
	ret
ENDPROC	setFlags

CODE	ENDS

	end
