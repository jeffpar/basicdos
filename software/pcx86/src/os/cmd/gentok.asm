;
; BASIC-DOS Code Generator Token Helpers
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The line and token helpers that genCode (see gencmd.asm) and all the other
; gen*.asm files share (eg, getNextLine, getNextToken, and validateOp).
;
	include	cmd.inc
	include	gen.inc

CODE    SEGMENT

	EXTNEAR	<addLabel,printLine,genCallCS,genPushImmLong>
	EXTWORD	<KEYWORD_TOKENS,KEYOP_TOKENS>
	EXTBYTE	<OPDEFS,RELOPS>
	EXTLONG	<FPU_TABLE>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextLine
;
; Inputs:
;	DS = heap segment
;
; Outputs:
;	If carry clear, DS:BX -> TOKLET array (TOKLET_END set to end)
;
; Modifies:
;	Any
;
DEFPROC	getNextLine
	mov	bx,ds:[PSP_HEAP]	; DS:BX -> heap
	mov	cx,[bx].LINE_LEN
	lds	si,[bx].LINE_PTR
	ASSUME	DS:NOTHING

	mov	dx,ds
	mov	ax,ss
	cmp	ax,dx			; is LINE_PTR in the heap?
	jne	gnl0			; no
	test	cx,cx			; yes, we must be using INPUTBUF
	stc				; have we already processed it?
	jnz	gnl4x			; yes
	mov	cl,[si].INP_CNT		; CX = length
	lea	si,[si].INP_DATA	; DS:SI -> line
	jmp	short gnl4

gnl0:	add	si,cx			; advance to the next line
gnl1:	cmp	si,ds:[BLK_FREE]	; still working the same TBLK?
	jb	gnl2			; yes
	mov	dx,ds:[BLK_NEXT]	; no, advance to next TBLK in chain
	cmp	dx,1			; is there another segment?
	jb	gnl4x			; no
	mov	ds,dx
	mov	si,size TBLK		; DS:SI -> next line
gnl2:	inc	ss:[bx].LINE_NUM
	lodsw
	mov	ss:[bx].LINE_LBL,ax
	test	ax,ax			; is there a label #?
	jz	gnl3			; no
	call	addLabel		; yes, add it to the LBLREF table
gnl3:	lodsb				; AL = length byte
	mov	ah,0
	xchg	cx,ax			; CX = length of line
	jcxz	gnl1
;
; As a preliminary matter, if we're processing a BAT file, then generate
; code to print the line, unless it starts with a '@', in which case, skip
; over the '@'.
;
gnl4:	DPRINTF	'b',<"%.*ls\r\n">,cx,si,ds
	cmp	byte ptr [si],'@'
	jne	gnl5
	inc	si
	dec	cx
	jz	gnl1
	jmp	short gnl6
gnl4x:	jmp	short gnl9
;
; One of the annoying things about the ECHO state is that, since we can't
; be sure what the state of ECHO will be at runtime, we must inject printLine
; before every line.
;
gnl5:	test	ss:[bx].GEN_FLAGS,GEN_ECHO
	jz	gnl6
	push	cx
	lea	cx,[si-1]
	GENPUSH	ds,cx			; DS:CX -> string (at the length byte)
	GENCALL	printLine
	pop	cx
;
; Ready to process the line of code at DS:SI with length CX.
;
gnl6:	mov	ss:[bx].LINE_PTR.OFF,si
	mov	ss:[bx].LINE_PTR.SEG,ds
	mov	ss:[bx].LINE_LEN,cx

	push	es
	push	di			; save code gen pointer
	push	ss
	pop	es			; ES = heap
;
; Copy the line (at DS:SI with length CX) to LINEBUF, so that we can use a
; single segment (DS) to address both LINEBUF and TOKENBUF once ES has been
; restored to the code gen segment.
;
	push	cx
	push	es
	lea	di,[bx].LINEBUF		; ES:DI -> LINEBUF
	push	di
	rep	movsb
	xchg	ax,cx			; AL = 0
	stosb				; null-terminate for good measure
	pop	si
	pop	ds
	pop	cx			; DS:SI -> LINEBUF (with length CX)

	lea	di,[bx].TOKENBUF	; ES:DI -> TOKENBUF
	DOSUTIL	TOKEN2
	mov	bx,di
	add	bx,offset TOK_DATA	; DS:BX -> TOKLET array
	pop	di
	pop	es			; restore code gen pointer
	jc	gnl9

	add	ax,ax
	add	ax,ax
	add	ax,bx
	mov	si,ds:[PSP_HEAP]
	mov	[si].TOKLET_END,ax
gnl9:	ret
ENDPROC	getNextLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextSymbol
;
; Call getNextToken with AL = CLS_SYM, updating BX and preserving CX, DX, SI.
;
DEFPROC	getNextSymbol
	push	cx
	push	si
	mov	al,CLS_SYM
	call	getNextToken
	pop	si
	pop	cx
	ret
ENDPROC	getNextSymbol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextToken
;
; Return the next token if it matches the criteria in AL (ignores whitespace).
;
; Inputs:
;	AL = CLS bits
;	DS:BX -> TOKLETs
;
; Outputs if next token matches:
;	AH = CLS of token
;	AL = 1st character of token (upper-cased)
;	CX = length of token
;	SI = offset of token (or offset of TOKDEF if CLS_KEYWORD)
;	BX = offset of next TOKLET
;	ZF and CF clear
;
; Outputs if NO matching next token:
;	ZF set if no more tokens (AX is zero)
;	CF set if no matching token (AH is CLS)
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	getNextToken
	push	dx
	push	di
gnt0:	mov	di,ds:[PSP_HEAP]
	cmp	bx,[di].TOKLET_END
	jb	gnt0a
	sub	ax,ax
	jmp	gnt9			; no more tokens (ZF set, CF clear)

gnt0a:	mov	ah,[bx].TOKLET_CLS
	test	ah,al
	jnz	gnt1
	cmp	ah,CLS_WHITE		; whitespace token?
gnt0b:	stc
	jne	gnt0c			; no (CF set)
	add	bx,size TOKLET		; yes, so ignore it
	jmp	gnt0
gnt0c:	jmp	gnt9

gnt1:	cmp	al,CLS_KEYWORD		; looking for keyword?
	jne	gnt1a			; no
	cmp	ah,CLS_VAR		; yes, undecorated CLS_VAR?
	jne	gnt0b			; no, can't be a keyword then

gnt1a:	mov	si,[bx].TOKLET_OFF
	mov	cl,[bx].TOKLET_LEN
	mov	ch,0
	add	bx,size TOKLET
	mov	dl,al			; DL = requested CLS
	mov	al,[si]			; AL = 1st character of token
	cmp	al,'a'			; ensure 1st character is upper-case
	jb	gnt2
	sub	al,20h
;
; Any CLS_VAR with additional bits specifying the variable type (eg,
; CLS_VAR_LONG, CLS_VAR_STR) is done, once we remove the type suffix from
; its length (the type is part of a variable's identity, not its name).
; Any vanilla CLS_VAR, however, must be further identified.  We now check for
; keyword operators (like NOT) and all other keywords.  Failing that, we
; assume it's a variable, so we look up the variable's implicit type and
; update the CLS bits accordingly.
;
gnt2:	cmp	ah,CLS_VAR
	je	gnt2v
	test	ah,CLS_VAR		; decorated CLS_VAR (eg, CLS_VAR_LONG)?
	jz	gnt7			; no
	dec	cx			; yes, so drop the type suffix
	jmp	short gnt8
gnt2v:

	push	ax
	push	dx
	cmp	cx,3			; KEYOPs are 2 or 3 characters
	ja	gnt2a			; so skip them if it's longer
	mov	dx,offset KEYOP_TOKENS	; see if token is a KEYOP
	DOSUTIL	TOKID			; CS:DX -> TOKTBL
	jc	gnt2a
	mov	ah,CLS_SYM		; AL = TOKDEF_ID, SI -> TOKDEF
	jnc	gnt2b
;
; The names of DOS commands (eg, DIR) are keywords only where a keyword was
; requested (eg, at the start of a command); anywhere else (eg, in an
; expression), they're variable names, as in MSBASIC (eg, PRINT DIR+1).
;
gnt2a:	push	si			; save the token offset
	mov	dx,offset KEYWORD_TOKENS; see if token is a KEYWORD
	DOSUTIL	TOKID			; CS:DX -> TOKTBL
	jc	gnt2d			; not a keyword
	cmp	al,KEYWORD_BASIC	; BASIC keyword?
	jae	gnt2e			; yes
	push	bp
	mov	bp,sp
	cmp	byte ptr [bp+4],CLS_KEYWORD; DOS command, but was CLS_KEYWORD
	pop	bp			; (in the saved DL) requested?
	jne	gnt2d			; no, so it's a variable name
gnt2e:	pop	dx			; discard the token offset
	mov	ah,CLS_KEYWORD		; AL = TOKDEF_ID, SI -> TOKDEF
gnt2b:	pop	dx
	pop	dx
	jmp	short gnt8
gnt2d:	pop	si			; restore the token offset
gnt2c:	pop	dx			; neither KEYOP nor KEYWORD
	pop	ax
	cmp	dl,CLS_KEYWORD		; and did we request a KEYWORD?
	stc
	je	gnt9			; yes, return error

	push	bx
	push	ax
	lea	bx,[di].DEFVARS
	sub	al,'A'			; convert 1st letter to DEFVARS index
	xlat				; look up the default VAR type
	test	al,al			; has a default been set?
	jnz	gnt4			; yes
	mov	al,VAR_LONG		; no, default to VAR_LONG
	cmp	word ptr cs:[FPU_TABLE].SEG,0
	je	gnt4			; if there's no FPU$ driver
	mov	al,VAR_DOUBLE		; otherwise, VAR_DOUBLE
gnt4:	mov	ah,al
	or	ah,CLS_VAR
	pop	bx			; we're really popping AX
	mov	al,bl			; and restoring AL
	pop	bx
	jmp	short gnt8
;
; If we're about to return a CLS_SYM that happens to be a colon, then return
; ZF set (but not carry) to end the caller's token scan.
;
gnt7:	cmp	ah,CLS_SYM
	jne	gnt8

	cmp	al,':'
	je	gnt9

gnt8:	or	ah,0			; return both ZF and CF clear
gnt9:	pop	di
	pop	dx
	ret
ENDPROC	getNextToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peekNextSymbol
;
; Peek and return the next symbol, if any.
;
; Inputs and outputs are the same as getNextSymbol, but we also save the
; offset of the next TOKLET, in case the caller wants to consume the token.
;
; Modifies:
;	AX
;
DEFPROC	peekNextSymbol
	push	bx
	call	getNextSymbol
	jmp	short peekReturn
ENDPROC	peekNextSymbol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peekNextToken
;
; Peek and return the next token, if it matches the criteria in AL.
;
; Inputs and outputs are the same as getNextToken, but we also save the
; offset of the next TOKLET, in case the caller wants to consume the token.
;
; Modifies:
;	AX, CX, SI
;
DEFPROC	peekNextToken
	push	bx
	call	getNextToken
	DEFLBL	peekReturn,near
	push	bx
	mov	bx,ds:[PSP_HEAP]
	pop	ds:[bx].TOKLET_NEXT	; save BX in TOKLET_NEXT in case the
	pop	bx			; caller wants to advance after peeking
	ret
ENDPROC	peekNextToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; validateOp
;
; This must also check for operators that are multi-character.  It must remap
; "<>" and "><" to 'U', "<=" and "=<" to 'L', and ">=" and "=>" to 'G'.
;
; See RELOPS for the complete list of multi-character operators we remap.
;
; Inputs:
;	AL = operator
;
; Outputs:
;	If carry clear:
;		AL = operator
;		AH = precedence
;		CX = # args
;		DX = operator index
;
; Modifies:
;	AH, CX, DX
;
DEFPROC	validateOp
	push	si
	xchg	dx,ax			; DL = operator to validate
	mov	al,CLS_SYM
	call	peekNextToken
	jbe	vo2

	mov	dh,al			; DX = potential 2-character operator
	mov	si,offset RELOPS
vo1:	lods	word ptr cs:[si]
	test	al,al
	jz	vo2
	cmp	ax,dx			; match?
	lods	byte ptr cs:[si]
	jne	vo1
	mov	bx,ds:[PSP_HEAP]
	mov	bx,[bx].TOKLET_NEXT	; load TOKLET saved by peekNextToken
	xchg	dx,ax			; DL = (new) operator to validate

vo2:	mov	ah,dl			; AH = operator to validate
	mov	si,offset OPDEFS
vo3:	lods	byte ptr cs:[si]
	test	al,al
	stc
	jz	vo9			; not valid
	cmp	al,ah			; match?
	je	vo7			; yes
	add	si,size OPDEF - 1
	jmp	vo3

vo7:	lods	byte ptr cs:[si]	; AL = precedence, AH = operator
	sub	cx,cx			; default to 0 args
	cmp	al,2			; precedence <= 2?
	jbe	vo8			; yes
	inc	cx			; no, so op requires at least 1 arg
	test	al,1			; odd precedence?
	jnz	vo8			; yes, just 1 arg
	inc	cx			; no, op requires 2 args
vo8:	xchg	dx,ax
	lods	byte ptr cs:[si]	; AL = operator index
	cbw
	xchg	dx,ax			; DX = operator index, AX = op/prec
vo9:	xchg	al,ah			; AL = operator, AH = precedence
	pop	si
	ret
ENDPROC	validateOp

CODE	ENDS

	end
