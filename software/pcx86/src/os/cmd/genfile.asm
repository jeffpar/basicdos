;
; BASIC-DOS Code Generator: File I/O
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for these sequential file I/O statements:
;
;	CLOSE				(genClose)
;	FIELD				(genField)
;	GET #, PUT #			(genGetFile, genPutFile, via genGet
;					and genPut)
;	INPUT [#]			(genInput)
;	LINE INPUT [#]			(genLineInput, via genLine)
;	LSET, RSET			(genLset, genRset)
;	OPEN				(genOpen)
;	PRINT #				(genPrintFile, via genPrint)
;	WRITE [#]			(genWrite)
;
; See gencmd.asm for an overview of all the gen*.asm files, and fileio.asm
; for the runtime functions.  Like gencmd.asm, these functions are called
; while generating code, with DS:BX -> TOKLETs and ES:DI -> code block.
;
	include	cmd.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<genExpr,getNextToken,genCallCS,genPushImm,genPushImmLong>
	EXTNEAR	<genPushImmByteAL,genPushImmByte,genCvtType,peekNextSymbol>
	EXTNEAR	<peekNextToken>
	EXTNEAR	<skipToken,genReadVars,genPrintArgs,genRedirEnd>
	EXTNEAR	<openFile,closeFile,fileOut,selectInput,fileItem>
	EXTNEAR	<writeValue,printArgs,inputLine,fieldVar,setField>
	EXTNEAR	<fileRecord,lsetStr,genArrayRef,addVar,genPushVarPtr>

TOK_FOR		equ	58		; keyword IDs (see KEYWORD_TOKENS)
TOK_INPUT	equ	89
TOK_AS		equ	209
TOK_OUTPUT	equ	210
TOK_APPEND	equ	211
TOK_RANDOM	equ	212
FIELD_MAX	equ	16		; max fields per FIELD statement

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genOpen
;
; Generate code for "OPEN file [FOR INPUT|OUTPUT|APPEND|RANDOM] AS [#]n
; [LEN=reclen]", where no FOR implies RANDOM, and the default record length
; is 128.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genOpen
	jmp	short go0
go8:	stc
go9:	ret
go0:	call	genExpr			; push the filename
	jbe	go8
	cmp	dl,VAR_STR		; is it a string?
	jne	go8			; no
	call	getKeyword		; FOR or AS?
	mov	dx,3			; DX = 3 for RANDOM
	cmp	al,TOK_AS		; AS (ie, no FOR)?
	je	go2			; yes
	cmp	al,TOK_FOR
	jne	go8
	call	getKeyword		; INPUT, OUTPUT, APPEND, or RANDOM?
	sub	dx,dx			; DX = 0 for INPUT
	cmp	al,TOK_INPUT
	je	go1
	inc	dx			; DX = 1 for OUTPUT
	cmp	al,TOK_OUTPUT
	je	go1
	inc	dx			; DX = 2 for APPEND
	cmp	al,TOK_APPEND
	je	go1
	inc	dx			; DX = 3 for RANDOM
	cmp	al,TOK_RANDOM
	jne	go8
go1:	call	getKeyword		; AS?
	cmp	al,TOK_AS
	jne	go8
go2:	GENPUSH	dx			; push the mode
	call	genFileNum		; push the file number
	jc	go9
	mov	al,CLS_VAR
	call	peekNextToken		; LEN?
	jbe	go4			; no
	cmp	cx,3
	jne	go8
	mov	ax,[si]
	and	ax,0DFDFh
	cmp	ax,'EL'
	jne	go8
	mov	al,[si+2]
	and	al,0DFh
	cmp	al,'N'
	jne	go8
	call	skipToken		; consume LEN
	mov	al,CLS_SYM
	call	getNextToken
	jbe	go8
	cmp	al,'='
	jne	go8
	call	genExpr			; push the record length
	jbe	go8
	mov	al,VAR_LONG
	call	genCvtType
	jc	go9
	jmp	short go5
go4:	GENPUSH	0,128			; push the default record length
go5:	GENCALL	openFile
	ret
ENDPROC	genOpen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genClose
;
; Generate code for "CLOSE [[#]n[,[#]n]...]", where no file number closes
; all files.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genClose
	mov	al,CLS_ANY
	call	peekNextToken		; any file numbers?
	jnz	gc1			; yes
	GENPUSH	0,0			; no, so push 0 (all files)
	GENCALL	closeFile
	clc
	ret
gc1:	call	genFileNum		; push the file number
	jc	gc9
	push	ax
	GENCALL	closeFile
	pop	ax
	cmp	al,','			; another file number?
	je	gc1			; yes
	clc
gc9:	ret
ENDPROC	genClose

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPrintFile
;
; Generate code for "PRINT #n[,args]" (genPrint calls us when PRINT is
; followed by '#'), which prints the args like PRINT, with the file as STDOUT.
;
; Inputs:
;	DS:BX -> TOKLETs (at the '#')
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genPrintFile
	call	genFileOut		; DX:CX -> redirection word
	jc	gpf9
	push	dx
	push	cx
	call	genPrintArgs		; generate the rest of PRINT
	jmp	short gw7
gpf9:	ret
ENDPROC	genPrintFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genWrite
;
; Generate code for "WRITE [#n,][expr[,expr]...]", which writes the values
; separated by commas, with strings in quotes (see writeValue).
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genWrite
	sub	cx,cx
	mov	dx,cx			; DX:CX = 0 (no file)
	call	peekNextSymbol
	jbe	gw1
	cmp	al,'#'			; WRITE #?
	jne	gw1			; no
	call	genFileOut		; DX:CX -> redirection word
	jc	gw9
gw1:	push	dx
	push	cx
	sub	cx,cx			; CX = # values
gw2:	push	cx
	call	genExpr			; push the next value
	pop	cx
	jnc	gw3
	test	dh,dh			; were there any tokens?
	stc
	jnz	gw7			; yes, so it's an error
gw3:	jz	gw6			; no value
	inc	cx
	push	cx
	push	ax
	mov	al,dl
	GENPUSHB al			; push its type
	pop	ax
	push	ax
	sub	al,','			; AL = 0 if a comma follows
	GENPUSHB al			; (ie, if it's not the last value)
	GENCALL	writeValue
	pop	ax
	pop	cx
	cmp	al,','			; another value?
	je	gw2			; yes
	jmp	short gw8
;
; If there are no values (or a comma ended the last one), end the line.
;
gw6:	GENPUSHB VAR_NONE
	GENCALL	printArgs
	clc
gw7:	jc	gw8a
;
; genPrintFile also ends here, with the redirection word on the stack.
;
gw8:	pop	cx
	pop	dx
	push	ax
	mov	ax,dx
	or	ax,cx			; was there a redirection word?
	pop	ax
	jz	gw9			; no
	jmp	genRedirEnd		; yes, so end the redirection
gw8a:	pop	cx
	pop	dx
gw9:	ret
ENDPROC	genWrite

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genInput
;
; Generate code for "INPUT #n,var[,var]...", which reads the next item
; from the file into each variable (see fileItem), or "INPUT [prompt;|,]var
; [,var]...", which reads a line from the keyboard (see inputLine) and then
; takes each item from it the same way.  As in MSBASIC, a semicolon after the
; prompt (or no prompt) displays "? ", but a comma doesn't.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genInput
	sub	dx,dx			; DX = 0 (items)
gi0:	call	peekNextSymbol
	jbe	gi1
	cmp	al,'#'			; INPUT #?
	jne	gi1			; no
	push	dx
	call	genFileNum		; push the file number
	pop	dx
	jc	gi9
	cmp	al,','			; is a comma next?
	jne	gi8			; no
	GENPUSH	dx			; push the item flag
	GENCALL	selectInput
	jmp	short gi6
;
; INPUT from the keyboard, with an optional prompt.
;
gi1:	push	dx
	mov	al,CLS_STR
	call	peekNextToken		; is there a prompt?
	pop	dx
	jbe	gi3			; no
	push	dx
	call	genExpr			; push the prompt
	pop	dx
	jbe	gi8
	mov	cl,1			; CL = 1 to display "? "
	cmp	al,';'
	je	gi4
	mov	cl,0
	cmp	al,','
	je	gi4
	jmp	short gi8
gi3:	push	dx
	GENPUSH	0,0			; push an empty prompt
	pop	dx
	mov	cl,1
gi4:	test	dx,dx			; LINE INPUT?
	jz	gi5			; no
	mov	cl,2			; yes (and no "? ")
gi5:	mov	ch,0
	GENPUSH	cx			; push the flags
	GENCALL	inputLine
gi6:	mov	cx,offset fileItem
	jmp	genReadVars		; read the variables
gi8:	stc
gi9:	ret
ENDPROC	genInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLineInput
;
; Generate code for "LINE INPUT #n,var$" or "LINE INPUT [prompt;]var$"
; (genLine calls us when LINE is followed by INPUT), which reads the next line
; from the file (or the keyboard) into var$.
;
; Inputs:
;	DS:BX -> TOKLETs (at INPUT)
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genLineInput
	call	skipToken		; consume INPUT
	mov	dx,1			; DX = 1 (lines)
	jmp	gi0
ENDPROC	genLineInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genField
;
; Generate code for "FIELD [#]n,width AS var$[,width AS var$]...", which
; reserves a FIELD table in the code (a count byte, followed by a 5-byte entry
; for each field), calls fieldVar to fill in each entry, and then calls
; setField to make it the file's FIELD table.  The fields are counted first
; (by counting the AS keywords), so that the table can be reserved.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genField
	push	bx
	sub	cx,cx			; CX = # fields
	mov	si,ds:[PSP_HEAP]
gf1:	cmp	bx,[si].TOKLET_END
	jae	gf2
	cmp	[bx].TOKLET_LEN,2
	jne	gf1a
	push	si
	mov	si,[bx].TOKLET_OFF
	mov	ax,[si]
	pop	si
	and	ax,0DFDFh
	cmp	ax,'SA'			; AS?
	jne	gf1a
	inc	cx
gf1a:	add	bx,size TOKLET
	jmp	gf1
gf2:	pop	bx
	jcxz	gf9
	cmp	cx,FIELD_MAX
	ja	gf9
	mov	ax,5
	mul	cx			; AX = size of the entries
	push	ax
	inc	ax
	xchg	dx,ax			; DX = size of the table
	mov	al,OP_JMP		; JMP over the table
	stosb
	xchg	ax,dx
	stosw
	pop	dx			; DX = size of the entries
	mov	al,cl
	stosb				; store the # fields
	push	es
	lea	ax,[di-1]
	push	ax			; save the pointer to the table
	push	di			; and to the 1st entry
	add	di,dx			; skip over the entries
	call	genFileNum		; push the file number
	jc	gfX
	cmp	al,','
	jne	gfX
gf3:	pop	cx
	pop	ax
	pop	dx			; DX:CX -> next entry
	push	dx
	push	ax
	push	cx
	GENPUSH	dx,cx			; push the pointer to the entry
	call	genExpr			; push the width
	jbe	gfX
	mov	al,VAR_LONG
	call	genCvtType
	jc	gfX
	call	getKeyword
	cmp	al,TOK_AS
	jne	gfX
	call	genStrVar		; push the pointer to the variable
	jc	gfX
	GENCALL	fieldVar
	pop	cx
	add	cx,5			; advance to the next entry
	push	cx
	call	peekNextSymbol
	jbe	gf4
	cmp	al,','			; another field?
	jne	gf4			; no
	call	skipToken
	jmp	gf3
gf4:	pop	cx			; discard the entry pointer
	pop	cx
	pop	dx			; DX:CX -> table
	GENPUSH	dx,cx			; push the pointer to the table
	GENCALL	setField
	clc
	ret
gfX:	add	sp,6
gf9:	stc
	ret
ENDPROC	genField

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLset
;
; Generate code for "LSET var$ = string" or (via genRset) "RSET var$ =
; string" (see lsetStr).
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genLset
	mov	dx,0			; DX = 0 for LSET
	jmp	short gls1
	DEFLBL	genRset,near
	mov	dx,1			; DX = 1 for RSET
gls1:	push	dx
	call	genStrVar		; push the pointer to the variable
	jc	gls8
	mov	al,CLS_SYM
	call	getNextToken
	jbe	gls8
	cmp	al,'='
	jne	gls8
	call	genExpr			; push the string
	jbe	gls8
	cmp	dl,VAR_STR
	jne	gls8
	pop	ax
	GENPUSHB al			; push the flag
	GENCALL	lsetStr
	clc
	ret
gls8:	pop	dx
	stc
	ret
ENDPROC	genLset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genGetFile
;
; Generate code for "GET #n[,rec]" or (via genPutFile) "PUT #n[,rec]" (see
; fileRecord); genGet and genPut call us when the next token is '#'.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genGetFile
	mov	dx,0			; DX = 0 for GET
	jmp	short grc1
	DEFLBL	genPutFile,near
	mov	dx,1			; DX = 1 for PUT
grc1:	push	dx
	call	genFileNum		; push the file number
	jc	grc8
	cmp	al,','			; record number?
	jne	grc2			; no
	call	genExpr			; push the record number
	jbe	grc8
	mov	al,VAR_LONG
	call	genCvtType
	jc	grc8
	jmp	short grc3
grc2:	GENPUSH	-1,-1			; push -1 for the next record
grc3:	pop	dx
	GENPUSH	dx			; push the flag
	GENCALL	fileRecord
	clc
	ret
grc8:	pop	dx
	stc
	ret
ENDPROC	genGetFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genStrVar
;
; Generate code to push a pointer to a string variable (or array element),
; for FIELD, LSET, and RSET.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genStrVar
	mov	al,CLS_VAR
	call	getNextToken
	jbe	gsv8
	and	ah,VAR_TYPE		; convert CLS_VAR_* to VAR_*
	cmp	ah,VAR_STR		; string variable?
	jne	gsv8			; no
	mov	al,1			; ARRAY_PTR
	call	genArrayRef		; array element?
	jc	gsv9			; error
	jnz	gsv9			; yes (and carry is clear)
	call	addVar			; DX:SI -> var data
	jc	gsv9
	mov	cx,cs
	cmp	dx,cx			; constants (in CS) can't be set
	je	gsv8
	call	genPushVarPtr
	clc
	ret
gsv8:	stc
gsv9:	ret
ENDPROC	genStrVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genFileOut
;
; Generate code for "#n" in PRINT # and WRITE #, which makes the file STDOUT
; until the end of the statement (see genRedir, which does the same thing for
; ":>"), along with the word in the code where fileOut records the previous
; STDOUT, which the caller must pass to genRedirEnd.
;
; Inputs:
;	DS:BX -> TOKLETs (at the '#')
;	ES:DI -> code block
;
; Outputs:
;	If carry clear, DX:CX -> redirection word
;
; Modifies:
;	Any
;
DEFPROC	genFileOut
	mov	ax,(2 SHL 8) OR OP_JMPS	; JMP over the redirection word
	stosw
	mov	cx,di			; CX = offset of redirection word
	sub	ax,ax
	stosw
	push	es
	push	cx
	call	genFileNum		; push the file number
	pop	cx
	pop	dx			; DX:CX -> redirection word
	jc	gfo9
	cmp	al,','			; a comma must follow
	je	gfo1			; unless there's nothing else
	test	al,al
	stc
	jnz	gfo9
gfo1:	push	dx
	push	cx
	GENPUSH	dx,cx			; push pointer to redirection word
	GENCALL	fileOut
	pop	cx
	pop	dx
	clc
gfo9:	ret
ENDPROC	genFileOut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genFileNum
;
; Generate code to push a file number (as a long), with an optional '#'.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	If carry clear, AL = the symbol that ended the number (eg, ','), if any
;
; Modifies:
;	Any
;
DEFPROC	genFileNum
	call	peekNextSymbol
	jbe	gfn1
	cmp	al,'#'			; '#' first?
	jne	gfn1			; no
	call	skipToken		; yes, so consume it
gfn1:	call	genExpr
	jbe	gfn8			; no number
	push	ax
	mov	al,VAR_LONG
	call	genCvtType		; the file number must be a long
	pop	ax
	jnc	gfn9
gfn8:	stc
gfn9:	ret
ENDPROC	genFileNum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getKeyword
;
; Inputs:
;	DS:BX -> TOKLETs
;
; Outputs:
;	AL = ID of the next token if it's a keyword (otherwise, AL = 0)
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	getKeyword
	mov	al,CLS_KEYWORD
	call	getNextToken
	jbe	gk8
	ret
gk8:	mov	al,0
	ret
ENDPROC	getKeyword

CODE	ENDS

	end
