;
; BASIC-DOS Code Generator: File I/O
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for these file I/O statements:
;
;	CLOSE				(genClose)
;	FIELD				(genField)
;	GET #, PUT #			(genGetFile, genPutFile, via genGet
;					and genPut)
;	INPUT #, LINE INPUT #		(genInputFile, via genInput)
;	IOCTL #				(genIoctl)
;	LSET, RSET			(genLset, genRset)
;	OPEN				(genOpen)
;	PRINT #				(genPrintFile, via genPrint)
;	PRINTF #			(genPrintfFile, via genPrintf)
;	GET, PUT			(file or graphics generators)
;	WRITE #				(genWriteFile, via genWrite)
;
; This module is outside COMMAND's core (see CMD.LRF), so the core reaches it
; only through genCommands (eg, OPEN) or genUpper (eg, INPUT #; see gencon.asm
; for INPUT, LINE INPUT, PRINT, and WRITE).
;
; See gencmd.asm for an overview of all the gen*.asm files, and fileio.asm
; for the runtime functions.  Like gencmd.asm, these functions are called
; while generating code, with DS:BX -> TOKLETs and ES:DI -> code block.
;
	include	cmd.inc
	include	gen.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<genExpr,getNextToken,genCallCS,genPushImm,genPushImmLong>
	EXTNEAR	<genPushImmByteAL,genPushImmByte,genCvtType,peekNextSymbol>
	EXTNEAR	<peekNextToken>
	EXTNEAR	<skipToken,genReadVars,genPrintArgs,genPrintfArgs,genWriteEnd>
	EXTNEAR	<openFile,closeFile,fileOut,selectInput,fileItem,genWriteArgs>
	EXTNEAR	<fieldVar,setField,fileRecord,lsetStr,genVarRef,fileIoctl>
	EXTNEAR	<dosCall>
	EXTNEAR	<genGetGfx,genPutGfx,compError>

	EXTABS	<TOK_FOR,TOK_INPUT,TOK_AS,TOK_OUTPUT,TOK_APPEND,TOK_RANDOM>

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
	mov	al,VAR_STR
	call	genCvtType		; it must be a string
	jc	go9
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
	cmp	ah,CLS_KEYWORD		; (eg, the next statement)
	je	go4			; no
	cmp	cx,3
	jne	go4
	mov	ax,[si]
	and	ax,0DFDFh
	cmp	ax,'EL'
	jne	go4
	mov	al,[si+2]
	and	al,0DFh
	cmp	al,'N'
	jne	go4
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
	jmp	genWriteEnd
gpf9:	ret
ENDPROC	genPrintFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPrintfFile
;
; Generate code for "PRINTF #n,USING ..." (genPrintf calls us when PRINTF is
; followed by '#'), which prints the values like PRINTF, with the file as
; STDOUT.  Since only genPrintf calls us, genPrintfArgs (which, like
; genPrintf, is outside COMMAND's core) must be loaded.
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
DEFPROC	genPrintfFile
	call	genFileOut		; DX:CX -> redirection word
	jc	gpff9
	push	dx
	push	cx
	call	genPrintfArgs		; generate the rest of PRINTF
	jmp	genWriteEnd
gpff9:	ret
ENDPROC	genPrintfFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genInputFile
;
; Generate code for "INPUT #n,var[,var]..." or "LINE INPUT #n,var$" (genInput
; calls us via genUpper, at the '#'), which selects the file (see selectInput)
; and then reads the next item (or line) into each variable (see fileItem).
;
; Inputs:
;	CX = 0 for INPUT #, 1 for LINE INPUT #
;	DS:BX -> TOKLETs (at the '#')
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genInputFile
	push	cx
	call	genFileNum		; push the file number
	pop	dx
	jc	gif9
	cmp	al,','			; is a comma next?
	jne	gif8			; no
	GENPUSH	dx			; push the LINE INPUT flag
	GENCALL	selectInput
	mov	cx,offset fileItem
	jmp	genReadVars		; read the variables
gif8:	stc
gif9:	ret
ENDPROC	genInputFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genWriteFile
;
; Generate code for "WRITE #n,..." (genWrite calls us via genUpper, at the
; '#'), which makes the file STDOUT (see genFileOut) and then generates the
; rest of WRITE.
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
DEFPROC	genWriteFile
	call	genFileOut		; DX:CX -> redirection word
	jc	gwf9
	jmp	genWriteArgs
gwf9:	ret
ENDPROC	genWriteFile

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
	mov	al,VAR_STR
	call	genCvtType
	jc	gls8
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
; genIoctl
;
; Generate code for "IOCTL [#]n,code[,value|string[,value]]", which sends an
; IOCTL request to the device or volume open as file n: a numeric value is
; passed in CX, a string's data is passed in DS:SI (with its length in CX),
; and a second value is passed in DX (see fileIoctl).
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
DEFPROC	genIoctl
	call	genFileNum		; push the file number
	jc	gio9
	cmp	al,','			; a comma must follow
	jne	gio8
	call	genExpr			; push the code
	jbe	gio8
	push	ax
	mov	al,VAR_LONG
	call	genCvtType
	pop	ax
	jc	gio9
	mov	dl,VAR_NONE		; DL = type of the first value (none)
	cmp	al,','			; is there a value?
	jne	gio2			; no
	call	genExpr			; push the value (or string)
	jbe	gio8
	cmp	dl,VAR_STR		; is it a string?
	je	gio1			; yes
	push	ax
	mov	al,VAR_LONG
	call	genCvtType		; no, so it must be a long
	pop	ax
	jc	gio9
	mov	dl,VAR_LONG
gio1:	cmp	al,','			; is there a second value?
	jne	gio2			; no
	push	dx
	call	genExpr			; push the second value
	jbe	gio7
	mov	al,VAR_LONG
	call	genCvtType
	pop	dx
	jc	gio9
	jmp	short gio3
gio7:	pop	dx
	jmp	short gio8
gio2:	push	dx
	GENPUSH	0,0			; push a zero
	pop	dx
	cmp	dl,VAR_NONE		; was there a first value?
	jne	gio3			; yes
	push	dx
	GENPUSH	0,0			; no, so push a zero for it, too
	pop	dx
gio3:	mov	al,dl
	GENPUSHB al			; push the type of the first value
	GENCALL	fileIoctl
	clc
	ret
gio8:	stc
gio9:	ret
ENDPROC	genIoctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDosCall
;
; Generate code for "DOS ax[,bx[,cx[,dx|string]]]", which calls DOS (INT 21h)
; with the values in AX, BX, CX, and DX (omitted values are zero), or with
; DS:DX -> a string, which must be the last value (see dosCall).
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
DEFPROC	genDosCall
	mov	cx,4			; CX = # of values left
gds1:	push	cx
	call	genExpr			; push the next value
	pop	cx
	jbe	gds8
	cmp	dl,VAR_STR		; is it a string?
	jne	gds2			; no
	cmp	cl,1			; yes, so is it the last value (DX)?
	jne	gds2			; no (and genCvtType will refuse it)
	cmp	al,','			; is another value following it?
	jne	gds5			; no (DL = VAR_STR)
	jmp	short gds8
gds2:	push	cx
	push	ax
	mov	al,VAR_LONG
	call	genCvtType		; a numeric value must be a long
	pop	ax
	pop	cx
	jc	gds9
	mov	dl,VAR_LONG
	cmp	al,','			; is there another value?
	jne	gds3			; no
	loop	gds1			; yes, if there can be another
gds8:	stc
gds9:	ret
gds3:	dec	cx			; CX = # of values omitted
	jcxz	gds5
gds4:	push	cx
	push	dx
	GENPUSH	0,0			; push a zero for each one
	pop	dx
	pop	cx
	loop	gds4
gds5:	mov	al,dl
	GENPUSHB al			; push the type of the last value
	GENCALL	dosCall
	clc
	ret
ENDPROC	genDosCall

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
	call	genVarRef		; AH = variable type
	jc	gsv9
	cmp	ah,VAR_STR		; string variable?
	je	gsv9			; yes (and carry is clear)
	mov	al,13			; "Type mismatch"
	jmp	compError
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genGet, genPut
;
; GET and PUT are both file statements (GET # and PUT #) and graphics
; statements (see gengfx.asm), so these keywords come here, where we decide
; which kind of statement it is and then jump to its generator.
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
DEFPROC	genGet
	call	peekNextSymbol
	jbe	gge0			; not a symbol, so GET #
	cmp	al,'('			; graphics GET?
	jne	gge0			; no
	jmp	genGetGfx
gge0:	jmp	genGetFile
ENDPROC	genGet

DEFPROC	genPut
	call	peekNextSymbol
	jbe	gpe0			; not a symbol, so PUT #
	cmp	al,'('			; graphics PUT?
	jne	gpe0			; no
	jmp	genPutGfx
gpe0:	jmp	genPutFile
ENDPROC	genPut

CODE	ENDS

	end
