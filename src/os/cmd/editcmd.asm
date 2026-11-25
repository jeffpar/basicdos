;
; BASIC-DOS Program Line Editing Commands
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; AUTO, DELETE, EDIT, and LLIST, and editPrompt, which the main loop calls
; when AUTO or EDIT has set a line to edit (see EDIT_STATE).  The program's
; text blocks and the other editing functions (eg, LIST) are in edit.asm.
; cmdPipe and runLine, which pipe the output of BASIC statements typed at the
; prompt, are here, too, as are showUsage, which displays a command's usage
; after a usage error (see cmdUsage), setName (see cmdLoad), and listVars,
; for LIST VARS (which cmdList reaches through genUpper).
;
; This module is not part of COMMAND's core (see CMD.LRF and HEAP.ASM): when
; only the core is loaded, cmdDOS refuses these commands with "Not enough
; memory" (see genUpper), so EDIT_STATE stays zero and the main loop never
; calls editPrompt, and parseCmd calls genCode instead of cmdPipe.
;
	DOSFUNC equ 1
	include	cmd.inc
	include	arr.inc

CODE    SEGMENT

	EXTNEAR	<chkProgram,getRange,usageError,freeCache,walkLines,delLine>
	EXTNEAR	<findLine,putNum,parseLine,storeLine,printCRLF,listLine>
	EXTNEAR	<chkOut,chkColon,genCode,parseDOS,callDOS,syntaxMsg>
	EXTNEAR	<getVarLen,writeStr>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

EDIT_LINE	equ	EDIT_STATE+0	; line # to edit at the next prompt
EDIT_INC	equ	EDIT_STATE+2	; AUTO increment (0 if not AUTO)
MAX_LINE	equ	65529		; largest line # (see edit.asm)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdLlist
;
; Process "LLIST [line][-[line]]", which lists lines like LIST, but to the
; printer (PRN), reporting any printer error afterward (see chkOut).  The
; range is parsed before PRN becomes STDOUT, so that errors aren't printed.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdLlist
	mov	al,'-'
	call	getRange		; AX = 1st line #, DX = last line #
	jc	ll9
	mov	cl,ds:[PSP_PFT][STDPRN]
	xchg	cl,ds:[PSP_PFT][STDOUT]	; make PRN STDOUT
	push	cx
	mov	si,offset listLine
	call	walkLines
	pop	cx
	mov	ds:[PSP_PFT][STDOUT],cl	; and restore STDOUT
	mov	bx,STDPRN
	jmp	chkOut
ll9:	ret
ENDPROC	cmdLlist

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdAuto
;
; Process "AUTO [line][,increment]", which prompts for program lines
; beginning with the given line # (default 10), which is advanced by the
; increment (default 10) after each line is entered (see editPrompt).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdAuto
	call	chkProgram
	jc	au9
	mov	al,','
	call	getRange		; AX = line #, DX = increment
	jc	au9
	jcxz	au1			; no comma, so use the default
	cmp	dx,-1			; was an increment specified?
	jne	au2			; yes
au1:	mov	dx,10
au2:	test	ax,ax			; was a line # specified?
	jnz	au3			; yes
	mov	ax,10
au3:	mov	[bx].EDIT_LINE,ax
	mov	[bx].EDIT_INC,dx
au9:	ret
ENDPROC	cmdAuto

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDelete
;
; Process "DELETE [line][-[line]]", which deletes the specified range of
; lines (at least one line # must be specified).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDelete
	call	chkProgram
	jc	de9
	mov	al,'-'
	call	getRange		; AX = 1st line #, DX = last line #
	jc	de9
	inc	dx			; was a last line # specified?
	jnz	de1			; yes
	test	ax,ax			; was a 1st line # specified?
	jnz	de1			; yes
	jmp	usageError		; no
de1:	dec	dx
	call	freeCache		; (the program must be recompiled)
	mov	si,offset delLine
	jmp	walkLines
de9:	ret
ENDPROC	cmdDelete

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdEdit
;
; Process "EDIT line", which displays the line for editing at the next prompt
; (see editPrompt).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdEdit
	call	chkProgram
	jc	ed9
	mov	al,'-'
	call	getRange		; AX = line #
	jc	ed9
	xchg	dx,ax			; DX = line #
	call	findLine
	jc	ed8			; not found
	jne	ed8			; not found
	mov	[bx].EDIT_LINE,dx
	mov	word ptr [bx].EDIT_INC,0
	ret
ed8:	PRINTF	<"Undefined line number",13,10>
	stc
ed9:	ret
ENDPROC	cmdEdit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; editPrompt
;
; Called by the main loop instead of prompting for a command when there's a
; line to edit (see cmdAuto and cmdEdit): the input buffer is filled with the
; line # and the line's text (if any), and displayed for editing.  If AUTO is
; active, a numbered line is added to the program and the next line # is set;
; anything else (including a numbered line with no text) ends AUTO.
;
; Inputs:
;	AX = line # to edit
;	BX -> CMDHEAP
;	DS = ES = SS
;
; Outputs:
;	Carry set if the input was processed; otherwise, carry clear (and the
;	input in INPUTBUF should be processed as usual)
;
; Modifies:
;	Any but BX
;
DEFPROC	editPrompt
	xchg	dx,ax			; DX = line #
	call	findLine		; ES:DI -> line, if any
	mov	si,di
	jc	ep1			; not found
	je	ep2			; found (CX = length)
ep1:	sub	cx,cx			; no text
ep2:	push	ds
	push	es
	push	ds
	pop	es
	lea	di,[bx].INPUTBUF.INP_DATA
	xchg	ax,dx
	call	putNum			; store the line # and a space
	pop	ds
	add	si,3			; DS:SI -> line's text
	lea	ax,[bx].INPUTBUF.INP_DATA + 254
	sub	ax,di			; AX = room left (INP_CNT max is 254)
	cmp	cx,ax
	jbe	ep3
	xchg	cx,ax
ep3:	rep	movsb
	pop	ds
	lea	ax,[bx].INPUTBUF.INP_DATA
	sub	di,ax
	xchg	ax,di
	mov	[bx].INPUTBUF.INP_CNT,al
	lea	dx,[bx].INPUTBUF
	mov	[bx].INPUT_BUF,dx
	sub	ax,ax
	mov	[bx].EDIT_LINE,ax	; (so that CTRLC ends any editing)
	xchg	ax,[bx].EDIT_INC	; AX = AUTO increment, if any
	push	ax
	DOSUTIL	EDITLN,2		; display and edit the line
	call	printCRLF
	pop	dx			; DX = AUTO increment
	test	dx,dx			; AUTO?
	jz	ep9			; no (carry clear)
	lea	si,[bx].INPUTBUF.INP_DATA
	mov	cl,[bx].INPUTBUF.INP_CNT
	push	dx
	call	parseLine		; AX = line #, CX = length of text
	pop	dx
	jc	ep8			; not a numbered line, so AUTO is done
	jcxz	ep7			; no text, so AUTO is done
	push	ax
	push	dx
	call	storeLine
	pop	dx
	pop	ax
	jc	ep7
	add	ax,dx			; AX = next line #
	jc	ep7
	cmp	ax,MAX_LINE
	ja	ep7
	mov	[bx].EDIT_LINE,ax
	mov	[bx].EDIT_INC,dx
ep7:	stc
	jmp	short ep9
ep8:	clc
ep9:	push	ss
	pop	es
	ret
ENDPROC	editPrompt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdPipe
;
; Runs a line typed at the prompt that genCode would run (see parseCmd).  If
; a pipe symbol (outside quotes) follows the line's last command-ending colon
; (see chkColon), as in "FOR I=1 TO 9:PRINT I:NEXT | MORE", then parseDOS runs
; the line as a pipeline whose first command is everything before the pipe
; symbol, which it defers until the rest of the pipeline is running (see
; runLine); otherwise, genCode runs the line as usual.
;
; TOKENBUF has the line's DOS tokens (where '<' and '>' are symbols, too), so
; we replace all the tokens before the pipe symbol with one token, which we
; mark CLS_KEYWORD for parseDOS.
;
; Inputs:
;	BX -> CMDHEAP
;	SI -> input buffer (see INPUT_BUF)
;	DI -> TOKENBUF
;
; Outputs:
;	Same as genCode (or parseDOS)
;
; Modifies:
;	Any
;
DEFPROC	cmdPipe
	push	bx
	mov	cl,[si].INP_CNT		; CL = # chars in the line
	mov	ch,0			; CH = quote flag
	lea	bx,[si].INP_DATA
	mov	dx,bx			; DX -> start of the line
	sub	si,si			; SI -> pipe symbol (none yet)
cp1:	mov	al,[bx]
	cmp	al,'"'
	jne	cp2
	not	ch
cp2:	test	ch,ch			; inside quotes?
	jnz	cp4			; yes
	cmp	al,'|'			; pipe symbol?
	jne	cp3			; no
	test	si,si			; the first since the last colon?
	jnz	cp4			; no
	mov	si,bx			; yes
cp3:	cmp	al,':'
	jne	cp4
	call	chkColon		; does the colon end a command?
	jc	cp4			; no
	sub	si,si			; yes, so forget any pipe symbol
cp4:	inc	bx
	dec	cl
	jnz	cp1
	xchg	ax,si			; AX -> pipe symbol, if any
	pop	bx
	test	ax,ax
	jz	cp9			; no pipe symbol
;
; Find the pipe symbol's TOKLET, and move it (and the rest) after the first
; TOKLET, which becomes everything before the pipe symbol.  The pipe symbol
; must be within TOK_MAX tokens of the line's start; if not, it remains a
; syntax error.
;
	mov	cl,[di].TOK_CNT
	mov	ch,0
	lea	si,[di].TOK_DATA
cp5:	cmp	[si].TOKLET_OFF,ax	; the pipe symbol's TOKLET?
	je	cp6			; yes
	add	si,size TOKLET
	loop	cp5
	jmp	short cp9		; not found
cp6:	push	di
	inc	cx
	mov	[di].TOK_CNT,cl		; CL = # TOKLETs that remain
	dec	cx
	add	cx,cx			; CX = # words to move
	lea	di,[di].TOK_DATA[size TOKLET]
	rep	movsw
	pop	di
	sub	ax,[di].TOK_DATA[0].TOKLET_OFF
	mov	[di].TOK_DATA[0].TOKLET_LEN,al
	mov	[di].TOK_DATA[0].TOKLET_CLS,CLS_KEYWORD
	jmp	parseDOS		; (AH is zero, as parseDOS requires)
cp9:	mov	al,GEN_IMM
	mov	si,[bx].INPUT_BUF
	jmp	genCode
ENDPROC	cmdPipe

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; runLine
;
; Runs the BASIC statements before the pipe symbol of a line that cmdPipe
; gave to parseDOS, which calls us like a deferred internal command (see
; pd9e), once the rest of the pipeline is running and STDOUT is the pipe.
;
; Inputs:
;	BX -> CMDHEAP
;	SI -> statements (ie, the first token; see cmdPipe)
;	CX = length of statements
;
; Outputs:
;	Same as genCode
;
; Modifies:
;	Any
;
DEFPROC	runLine
	add	cx,si			; CX -> pipe symbol
	mov	si,[bx].INPUT_BUF
	lea	ax,[si].INP_DATA
	sub	cx,ax			; CL = # chars before the pipe symbol
	xchg	cl,[si].INP_CNT		; end the line there (for now)
	push	cx
	push	si
	mov	al,GEN_IMM
	call	genCode
	pop	si
	pop	cx
	mov	[si].INP_CNT,cl		; restore the line's length
	ret
ENDPROC	runLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; showUsage
;
; Displays the usage of a command with a usage error (see cmdUsage) by
; running "HELP name", which displays the command's help (starting with its
; usage line), where name is the command's name without any path or extension
; (eg, LS for A:\EXT\BAS\LS.BAS), or if HELP can't display it, "Syntax error".
;
; Inputs:
;	DS:SI -> command (may be preceded by whitespace)
;	CX = length of command
;
; Outputs:
;	Carry set
;
; Modifies:
;	Any but BX
;
SU_NAMELEN	equ	12		; longest name we give HELP
SU_BUFLEN	equ	6 + SU_NAMELEN	; room for "HELP ", the name, and a pad
					; byte (to keep the stack word-aligned)

DEFPROC	showUsage
	push	bx
	sub	sp,SU_BUFLEN
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> buffer
	mov	ax,('E' SHL 8) OR 'H'
	stosw
	mov	ax,('P' SHL 8) OR 'L'
	stosw
	mov	al,' '
	stosb				; "HELP "
	mov	bx,di			; BX -> name
su1:	lodsb
	cmp	al,CHR_SPACE		; whitespace?
	jbe	su1			; yes
	dec	si
	mov	dx,SU_NAMELEN		; DL = room left, DH = 0 (no extension)
su2:	lodsb
	cmp	al,'\'			; a path separator?
	je	su3			; yes
	cmp	al,'/'
	je	su3
	cmp	al,':'			; or a drive?
	jne	su4			; no
su3:	mov	di,bx			; yes, so the name starts after it
	mov	dx,SU_NAMELEN
	jmp	short su6
su4:	cmp	al,'.'			; an extension?
	jne	su5			; no
	inc	dh			; yes, so the name ends here
su5:	test	dh,dh			; in the extension?
	jnz	su6			; yes
	test	dl,dl			; any room left?
	jz	su6			; no
	dec	dx
	stosb
su6:	loop	su2
	cmp	di,bx			; is there a name?
	je	su8			; no
	mov	cx,di
	mov	di,sp
	sub	cx,di			; CX = length of the command
	sub	ax,ax
	push	ax			; no handler
	push	ax			; or keyword ID
	push	cx
	push	ss
	push	di
	push	cs
	call	callDOS			; run "HELP name"
	mov	bx,ss:[PSP_HEAP]
	mov	al,1			; a usage error sets ERRORLEVEL to 1
	xchg	al,ss:[bx].EXIT_CODE
	test	al,al			; did HELP display the usage?
	jz	su9			; yes
su8:	call	syntaxMsg
su9:	add	sp,SU_BUFLEN
	pop	bx
	stc
	ret
ENDPROC	showUsage

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setName
;
; Record the name of the program being loaded (eg, DONKEY for a filespec of
; C:\DEMOS\DONKEY.BAS) in our PSP_FCB1, padded with spaces, which DOS reports
; (eg, in START's list) while PSP_BASIC is set (see cmdRunFlags).  It's not
; part of COMMAND's core, so if only the core was loaded, cmdLoad skips it,
; and the name stays zero (see init.asm).  A BAS or BAT file run by another
; restores its caller's name when it ends (see saveChains).
;
; Inputs:
;	BX -> CMDHEAP
;	DS:SI -> filespec (ending with a null)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DI, ES
;
DEFPROC	setName
	push	si
	mov	di,si			; DI -> name (so far)
sn1:	lodsb
	cmp	al,':'			; the end of a drive?
	je	sn2			; yes
	cmp	al,[bx].PATH_CHAR	; or of a directory?
	jne	sn3			; no
sn2:	mov	di,si			; DI -> name after it
sn3:	test	al,al
	jnz	sn1
	mov	si,di
	push	ss
	pop	es
	mov	di,PSP_FCB1 + 1		; ES:DI -> name in PSP_FCB1
	mov	cx,8
sn4:	lodsb
	cmp	al,'.'			; the end of the name?
	je	sn5			; yes
	test	al,al			; or of the filespec?
	jz	sn5			; yes
	stosb
	loop	sn4
sn5:	mov	al,' '
	rep	stosb			; pad the rest with spaces
	pop	si
	ret
ENDPROC	setName

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; listVars
;
; List preserved strings, then live scalar variables, array dimensions, and
; functions in allocation order.
; Dead bytes and temporary parameters are skipped.
; Type suffixes distinguish variables with the same name but different types.
;
; Inputs:
;	DS:BX -> CMDHEAP
;
; Outputs:
;	Variable names and values written to STDOUT
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	listVars
	push	bx
	call	listKeep
	mov	ax,[bx].VBLKDEF.BDEF_NEXT
lv0:	test	ax,ax
	jnz	lv0a
	pop	bx
	clc
	ret
lv0a:	mov	es,ax
	mov	di,size VBLK
lv1:	cmp	di,es:[BLK_FREE]	; end of used space?
	jb	lv1a
	jmp	lv8
lv1a:	mov	al,es:[di]
	inc	di
	cmp	al,VAR_DEAD
	je	lv1			; deleted variable byte
	ja	lv1b			; live variable
	jmp	lv8
lv1b:	mov	ah,al
	and	ah,VAR_TYPE
	and	al,VAR_NAMELEN
	mov	cl,al
	mov	ch,0
	mov	si,di			; ES:SI -> name
	add	di,cx			; ES:DI -> value
	mov	bl,ah
	call	getVarLen
	add	ax,di			; AX -> next variable
	push	ax
	cmp	bl,VAR_PARM
	jne	lv1d
	jmp	lv7
lv1d:	PRINTF	<"%.*ls">,cx,si,es
	cmp	bl,VAR_ARRAY
	jne	lv1e
	push	es
	call	listDims
	pop	es
	jmp	short lv3a
;
; A function is listed with its return type's suffix and its parameter
; count (eg, ADD%(2) = function), since its parameter names aren't kept.
;
lv1e:	cmp	bl,VAR_FUNC
	jne	lv2
	mov	bx,es:[di]		; BL = return type, BH = parm count
	sub	di,di			; DI = 0 for a function (see lv3)
lv2:	mov	al,'%'
	cmp	bl,VAR_LONG
	je	lv3
	mov	al,'$'
	cmp	bl,VAR_STR
	je	lv3
	mov	al,'#'
lv3:	test	di,di			; a function?
	jnz	lv3b			; no
	mov	bl,bh
	mov	bh,0			; BX = parm count
	PRINTF	<"%c(%u) = function",13,10>,ax,bx
lv3a:	jmp	short lv7
lv3b:	PRINTF	<"%c = ">,ax
	cmp	bl,VAR_LONG
	jne	lv4
	mov	ax,es:[di].LW
	mov	dx,es:[di].HW
	PRINTF	<"%ld">,ax,dx
	jmp	short lv6
lv4:	cmp	bl,VAR_DOUBLE
	jne	lv5
	PRINTF	<"%f">,di,es
	jmp	short lv6
lv5:	PRINTF	<34>
	push	ds
	lds	si,es:[di]
	mov	ax,ds
	test	ax,ax
	jz	lv5a			; empty string has a null pointer
	call	writeStr		; do not release the owned string
lv5a:	pop	ds
	PRINTF	<34>
lv6:	call	printCRLF
lv7:	pop	di			; next variable
	jmp	lv1
lv8:	mov	ax,es:[BLK_NEXT]
	jmp	lv0
ENDPROC	listVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; listKeep
;
; List strings stored in CMDHEAP that survive loads and variable resets.
; Each keepStr entry contains a buffer offset and a null-terminated name;
; a zero offset ends the table.  Add future preserved strings here.
;
; Inputs:
;	DS:BX -> CMDHEAP
;
; Outputs:
;	Preserved string names and quoted values written to STDOUT
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	listKeep
	mov	si,offset keepStr
lk0:	mov	di,cs:[si]
	test	di,di
	jz	lk9
	add	di,bx			; DS:DI -> length-prefixed value
	add	si,2			; CS:SI -> variable name
	PRINTF	<"%ls = ",34>,si,cs
	push	si
	mov	si,di
	call	writeStr
	pop	si
	PRINTF	<34,13,10>
lk1:	cmp	byte ptr cs:[si],0
	lea	si,[si+1]		; advance without changing flags
	jne	lk1
	jmp	lk0
lk9:	ret
ENDPROC	listKeep

keepStr	label	word
	dw	PATH_BUF
	db	'PATH$',0
	dw	PROMPT_BUF
	db	'PROMPT$',0
	dw	0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; listDims
;
; Display array bounds without expanding or changing its elements.
;
; Inputs:
;	ES:DI -> array variable's far pointer
;
; Outputs:
;	Parenthesized lower and upper bounds written to STDOUT
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	listDims
	mov	ax,es:[di]._SEG
	test	ax,ax
	jnz	ld0
	PRINTF	<"() = undimensioned",13,10>
	ret
ld0:	les	di,es:[di]
	mov	cl,es:[ABLK_DIMS]
	mov	ch,0
	mov	dx,es:[ABLK_BASE]
	mov	di,size ABLK
	PRINTF	<"(">
ld1:	mov	ax,es:[di]
	add	ax,dx
	dec	ax			; upper bound = base + count - 1
	PRINTF	<"%u TO %u">,dx,ax
	add	di,2
	loop	ld2
	PRINTF	<")",13,10>
	ret
ld2:	PRINTF	<", ">
	jmp	ld1
ENDPROC	listDims

CODE	ENDS

	end
