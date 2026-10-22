;
; BASIC-DOS Code Generator: PRINTF
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for PRINTF (genPrintf; see genfile.asm for PRINTF #), and
; provides its runtime function (printfArgs).
;
; See gencmd.asm for an overview of all the gen*.asm files.  Like gencmd.asm,
; these functions are called while generating code, with DS:BX -> TOKLETs and
; ES:DI -> code block.
;
; This module is not part of COMMAND's core (see CMD.LRF and HEAP.ASM): when
; only the core is loaded, genCommands refuses PRINTF with "Not enough memory"
; (genPrintfFile is reached only through genPrintf).
;
	DOSFUNC equ 1
	include	cmd.inc
	include	gen.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<genExpr,getNextToken,peekNextSymbol,genPushImmByte>
	EXTNEAR	<genPrintVal,genPrintfFile,releaseStr>
	EXTABS	<TOK_USING>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPrintf
;
; Generate code for "PRINTF [#n,] USING format;[value[,value]...]", which
; prints the values using the format's specifiers (see sprintf.asm); since
; the values are typed, a specifier's size modifiers are ignored.  As with
; PRINT, a newline follows the output unless the list ends with a separator.
;
; The format is pushed like the first value, so the runtime function
; (printfArgs) finds it just above the end-of-args marker.
;
; Inputs:
;	BX = offset of next TOKLET
;	ES:DI -> next unused location in code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genPrintf
	call	peekNextSymbol
	jbe	genPrintfArgs
	cmp	al,'#'			; PRINTF #?
	jne	genPrintfArgs		; no
	jmp	genPrintfFile		; yes (see genfile.asm)
	DEFLBL	genPrintfArgs,near
	mov	al,CLS_KEYWORD
	call	getNextToken		; USING must follow
	jb	gpf9			; not a keyword
	stc
	jz	gpf9			; no more tokens
	cmp	al,TOK_USING
	stc
	jne	gpf9			; not USING
	mov	si,offset printfArgs	; SI = runtime function
	push	si
	GENPUSHB VAR_NONE		; push end-of-args marker
	call	genExpr			; generate the format expression
	jc	gpf8
	stc
	jz	gpf8			; no format
	cmp	dl,VAR_STR		; is the format a string?
	stc
	jne	gpf8			; no
	jmp	genPrintVal		; yes, continue with the values
gpf8:	pop	si
gpf9:	ret
ENDPROC	genPrintf

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printfArgs
;
; Used by "PRINTF [#n,] USING format;[value[,value]...]".  The values (with
; their types and separators) are pushed as for printArgs, preceded by the
; format (a VAR_STR), so it's just above the end-of-args marker.
;
; DOS_UTL_TPRINTF wants the format at DS:BX (null-terminated) and the values
; as typed parameters (a type word, then the 4-byte value) pushed right to
; left, so we copy the format to the stack and then push the values again,
; from the last to the first.  The output ends with a newline unless the list
; ends with a separator.
;
; Inputs:
;	format and values pushed as described above
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	printfArgs,FAR
	push	bp			; preserve BP (see genEnd)
	mov	bp,sp
	add	bp,6			; BP -> last item pushed
	push	ds			; [bp-8] = caller's DS
	push	ss
	pop	ds
	mov	al,[bp]			; AL = type of last item
	cmp	al,VAR_LONG		; is it a separator?
	sbb	ax,ax			; AX = -1 if so (no newline), 0 if not
	push	ax			; [bp-10] = newline flag
	mov	bx,bp			; BX -> first item
;
; Find the end-of-args marker, which the format precedes.
;
pfa1:	mov	al,[bx]
	test	al,al			; end-of-args marker?
	jz	pfa2			; yes
	add	bx,2
	cmp	al,VAR_LONG		; separator?
	jb	pfa1			; yes
	add	bx,4
	jmp	pfa1
pfa2:	push	bx			; [bp-12] = offset of marker
	mov	ax,sp
	push	ax			; [bp-14] = SP to restore afterward
	lds	si,[bx-4]		; DS:SI -> format string
	mov	cx,ds
	jcxz	pfa3			; null pointer (empty string)
	lodsb
	mov	cl,al
	mov	ch,0			; CX = length
;
; Reserve room for the format and its null, keeping SP even (an odd length
; would otherwise leave SP odd, which ENTER asserts against in DEBUG builds).
;
pfa3:	sub	sp,cx
	dec	sp
	and	sp,not 1
	mov	di,sp
	mov	bx,di			; SS:BX -> format copy on stack
	push	ss
	pop	es
	rep	movsb
	mov	al,0
	stosb				; null-terminate the copy
	push	ss
	pop	ds
	mov	dx,[bp-12]
	sub	dx,6			; DX -> format's type
	mov	si,bp			; SI -> first item
;
; Push the values as typed parameters, from the last to the first.
;
pfa4:	cmp	si,dx			; reached the format?
	jae	pfa6			; yes
	mov	al,[si]
	add	si,2
	cmp	al,VAR_LONG		; separator?
	jb	pfa4			; yes
	push	word ptr [si+2]		; push value (high word first)
	push	word ptr [si]
	push	ax			; push type (low byte)
	add	si,4
	jmp	pfa4
pfa6:	DOSUTIL	TPRINTF			; DS:BX -> format, typed parameters
	mov	sp,[bp-14]		; discard parameters and format copy
	pop	bx			; (BX -> marker, not needed)
	pop	dx			; DX = newline flag
	pop	ds
;
; Release any strings (including the format), then clean up the stack.
;
pfa7:	mov	al,[bp]
	test	al,al			; end-of-args marker?
	jz	pfa8			; yes
	add	bp,2
	cmp	al,VAR_LONG		; separator?
	jb	pfa7			; yes
	cmp	al,VAR_STR		; string?
	jne	pfa7a			; no
	les	di,[bp]
	call	releaseStr
pfa7a:	add	bp,4
	jmp	pfa7
pfa8:	test	dx,dx			; newline?
	jnz	pfa9			; no
	PRINTF	<13,10>
pfa9:	mov	bx,bp
	sub	bx,sp
	sub	bx,4			; BX = # bytes to clean off stack
	pop	bp			; restore BP
	pop	dx			; remove return address
	pop	cx
	add	sp,bx			; clean the stack
	push	cx			; restore the return address
	push	dx
	ret
ENDPROC	printfArgs

CODE	ENDS

	end
