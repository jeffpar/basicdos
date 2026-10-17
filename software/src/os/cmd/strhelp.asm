;
; BASIC-DOS String Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The BASIC string functions (eg, LEFT$, MID$, and STR$) moved here from
; STR.ASM, which keeps the string pool and string comparison support; the
; functions that don't extract, search, or convert strings (HEX$, OCT$,
; UCASE$, LCASE$, INKEY$, DATE$, TIME$, and FRE) are in STRMISC.ASM, since
; this module reached MASM's symbol space limit.
;
	include	cmd.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<allocStr,compactStrs,isTempStr,releaseStr,newStr>
	EXTNEAR	<getByteArg,getStrLen,getSubStr,strIllegal>
	EXTLONG	<FPU_TABLE>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; callFPUFunc
;
; Calls the FPU$ driver's function at the specified FPUTBL offset, passing
; all other registers through (unlike callFPU, which uses CX).
;
; Inputs:
;	BX = FPUTBL offset (eg, FPU_DTOA)
;	Other registers as required by the function
;
; Outputs:
;	As returned by the function, or carry set if there's no FPUTBL
;
; Modifies:
;	BX, plus whatever the function modifies
;
DEFPROC	callFPUFunc
	cmp	word ptr cs:[FPU_TABLE+2],0
	stc
	je	cff9			; no FPUTBL
	push	ds
	push	si
	lds	si,cs:[FPU_TABLE]
	push	ds
	push	word ptr [si+bx]	; push the FPUTBL function address
	mov	bx,sp
	lds	si,ss:[bx+4]		; restore SI and DS
	call	dword ptr ss:[bx]
	pop	bx			; (POPs don't modify flags)
	pop	bx
	pop	si
	pop	ds
cff9:	ret
ENDPROC	callFPUFunc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strToChar
;
; Converts a string value on the stack to the code of its first character
; (zero if empty), for functions that accept either (eg, STRING$).
;
; Input stack:
;	string value
;
; Output stack:
;	32-bit character code
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	strToChar,FAR
	RETVAR	pStrChr,dword
	ENTER
	les	di,[pStrChr]
	sub	ax,ax
	test	di,di
	jz	stc8
	mov	al,es:[di+1]
	call	releaseStr
stc8:	mov	[pStrChr].LOW,ax
	mov	[pStrChr].HIW,0
	LEAVE
	RETURN
ENDPROC	strToChar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strLen (LEN)
;
; Inputs:
;	32-bit return value
;	string value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	strLen,FAR
	RETVAR	retLen,dword
	ARGVAR	pLenStr,dword
	ENTER
	lea	si,[pLenStr]
	call	getStrLen
	les	di,[pLenStr]
	call	releaseStr
	mov	[retLen].LOW,cx
	mov	[retLen].HIW,0
	LEAVE
	RETURN
ENDPROC	strLen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strArg (ARG$)
;
; Returns an argument from the command line that ran the current BAS or BAT
; file: ARG$(0) is the file's name (as typed), ARG$(1) is the first argument,
; and so on, and ARG$ without a number returns all the arguments.  Arguments
; are separated by whitespace, and a quoted argument (whose quotes are
; removed) can contain whitespace.  The result is empty if there's no such
; argument (or no BAS or BAT file is running).
;
; Inputs:
;	32-bit return value
;	32-bit argument # (popped; negative for all the arguments)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strArg,FAR
	RETVAR	retArg,dword
	ARGVAR	argNum,dword
	ENTER
	sub	cx,cx			; CX = length of result (none yet)
	mov	bx,ss:[PSP_HEAP]
	mov	si,ss:[bx].CMD_CHAINS	; SS:SI -> CHAINS frame, if any
	test	si,si			; is a BAS or BAT file running?
	jz	ag9			; no
	mov	si,ss:[si]		; SS:SI -> command line (CH_ARGS)
	lods	byte ptr ss:[si]
	cbw
	mov	di,si
	add	di,ax			; DI -> end of command line
	mov	dx,[argNum].LOW		; DX = argument #
	test	byte ptr [argNum].HIW.HIB,80h
	jz	ag1			; not negative
	mov	dx,1			; negative, so find the 1st argument
ag1:	sub	cx,cx
	cmp	si,di			; skip whitespace
	jae	ag9			; no (more) arguments
	cmp	byte ptr ss:[si],' '
	ja	ag2
	inc	si
	jmp	ag1
ag2:	push	si
	call	argToken		; SS:SI -> token, CX = length
	pop	ax			; AX -> start of token
	test	dx,dx			; is this the argument we want?
	jz	ag3			; yes
	mov	si,bx			; no, so skip it
	dec	dx
	jmp	ag1
ag3:	test	byte ptr [argNum].HIW.HIB,80h
	jz	ag9			; return just this argument
	xchg	si,ax			; return all the arguments
	mov	cx,di
	sub	cx,si
ag4:	mov	bx,si			; (without trailing whitespace)
	add	bx,cx
	cmp	byte ptr ss:[bx-1],' '
	ja	ag9
	loop	ag4
ag9:	call	newStr
	mov	[retArg].OFF,ax
	mov	[retArg].SEG,dx
	LEAVE
	RETURN
ENDPROC	strArg

;
; argToken returns the token at SS:SI (up to DI) for strArg: if the token is
; quoted, SI is advanced past the opening quote, and the length in CX stops
; before the closing quote; BX -> character after the token.
;
DEFPROC	argToken
	mov	al,' '			; AL = terminator (whitespace)
	cmp	byte ptr ss:[si],'"'	; quoted?
	jne	at1			; no
	mov	al,'"'			; yes, so the terminator is a quote
	inc	si
at1:	mov	bx,si
at2:	cmp	bx,di			; end of command line?
	jae	at4			; yes
	mov	ah,ss:[bx]
	cmp	al,'"'
	je	at3
	cmp	ah,al			; whitespace?
	jbe	at4			; yes
	jmp	short at3a
at3:	cmp	ah,al			; closing quote?
	je	at4			; yes
at3a:	inc	bx
	jmp	at2
at4:	mov	cx,bx
	sub	cx,si			; CX = length of token
	cmp	al,'"'			; quoted?
	jne	at9			; no
	cmp	bx,di			; did we stop at a closing quote?
	jae	at9			; no
	inc	bx			; yes, so skip it
at9:	ret
ENDPROC	argToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strAsc (ASC)
;
; Inputs:
;	32-bit return value
;	string value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	strAsc,FAR
	RETVAR	retAsc,dword
	ARGVAR	pAscStr,dword
	ENTER
	les	di,[pAscStr]
	test	di,di
	jz	sa9
	mov	al,es:[di+1]
	mov	ah,0
	call	releaseStr
	mov	[retAsc].LOW,ax
	mov	[retAsc].HIW,0
	LEAVE
	RETURN
sa9:	jmp	strIllegal
ENDPROC	strAsc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strChr (CHR$)
;
; Inputs:
;	32-bit return value
;	32-bit character code (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	strChr,FAR
	RETVAR	retChr,dword
	ARGVAR	chrCode,dword
	ENTER
	mov	ax,[chrCode].LOW
	mov	dx,[chrCode].HIW
	call	getByteArg
	xchg	dx,ax			; DL = character code
	mov	cx,1
	call	allocStr
	mov	es:[di+1],dl
	mov	[retChr].OFF,di
	mov	[retChr].SEG,es
	LEAVE
	RETURN
ENDPROC	strChr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strLeft (LEFT$)
;
; Inputs:
;	32-bit return value
;	string value (popped)
;	32-bit length (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strLeft,FAR
	RETVAR	retLeft,dword
	ARGVAR	pLeftStr,dword
	ARGVAR	leftLen,dword
	ENTER
	mov	ax,[leftLen].LOW
	mov	dx,[leftLen].HIW
	call	getByteArg		; AX = requested length
	lea	si,[pLeftStr]
	call	getStrLen		; CX = string length
	cmp	cx,ax
	jb	sl1
	xchg	cx,ax			; CX = substring length
sl1:	sub	ax,ax			; AX = substring offset
	call	getSubStr
	mov	[retLeft].OFF,ax
	mov	[retLeft].SEG,dx
	LEAVE
	RETURN
ENDPROC	strLeft

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strRight (RIGHT$)
;
; Inputs:
;	32-bit return value
;	string value (popped)
;	32-bit length (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strRight,FAR
	RETVAR	retRight,dword
	ARGVAR	pRightStr,dword
	ARGVAR	rightLen,dword
	ENTER
	mov	ax,[rightLen].LOW
	mov	dx,[rightLen].HIW
	call	getByteArg		; AX = requested length
	lea	si,[pRightStr]
	call	getStrLen		; CX = string length
	cmp	ax,cx
	jb	sr1
	mov	ax,cx
sr1:	sub	cx,ax			; CX = substring offset
	xchg	cx,ax			; AX = offset, CX = length
	call	getSubStr
	mov	[retRight].OFF,ax
	mov	[retRight].SEG,dx
	LEAVE
	RETURN
ENDPROC	strRight

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strMid (MID$)
;
; The length is optional; PARM_OPT_REST (ie, -2) means the rest of the string.
;
; Inputs:
;	32-bit return value
;	string value (popped)
;	32-bit position (1-based, popped)
;	32-bit length (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strMid,FAR
	RETVAR	retMid,dword
	ARGVAR	pMidStr,dword
	ARGVAR	midPos,dword
	ARGVAR	midLen,dword
	ENTER
	mov	ax,[midPos].LOW
	mov	dx,[midPos].HIW
	call	getByteArg
	dec	ax			; AX = offset
	jl	sm9			; position must be 1 or more
	xchg	bx,ax			; BX = offset
	mov	ax,[midLen].LOW
	mov	dx,[midLen].HIW
	cmp	ax,-2			; PARM_OPT_REST (sign-extended)?
	jne	sm1
	cmp	dx,-1
	jne	sm1
	mov	ax,255			; use the rest of the string
	sub	dx,dx
sm1:	call	getByteArg		; AX = requested length
	lea	si,[pMidStr]
	call	getStrLen		; CX = string length
	sub	cx,bx			; CX = # chars from offset to end
	ja	sm2
	sub	cx,cx			; offset is past the end
sm2:	cmp	cx,ax
	jb	sm3
	xchg	cx,ax			; CX = substring length
sm3:	xchg	ax,bx			; AX = offset
	call	getSubStr
	mov	[retMid].OFF,ax
	mov	[retMid].SEG,dx
	LEAVE
	RETURN
sm9:	jmp	strIllegal
ENDPROC	strMid

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strInstr (INSTR)
;
; Returns the position (1-based) of string B in string A, starting at the
; given position, or zero if not found.  Like MSBASIC, if B is empty, the
; result is the starting position (unless A is empty or the starting position
; is past the end of A).
;
; Inputs:
;	32-bit return value
;	32-bit starting position (popped)
;	string value A (popped)
;	string value B (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strInstr,FAR
	RETVAR	retInstr,dword
	ARGVAR	instrPos,dword
	ARGVAR	pInstrA,dword
	ARGVAR	pInstrB,dword
	ENTER
	push	ds
	mov	ax,[instrPos].LOW
	mov	dx,[instrPos].HIW
	call	getByteArg
	dec	ax			; AX = offset
	jl	si10			; position must be 1 or more
	xchg	bx,ax			; BX = offset
	lea	si,[pInstrB]
	call	getStrLen
	mov	dx,cx			; DX = length of B
	lea	si,[pInstrA]
	call	getStrLen		; CX = length of A
	sub	ax,ax			; AX = result (zero)
	cmp	bx,cx			; offset within A?
	jae	si8			; no
	inc	bx			; BX = position
	test	dx,dx			; is B empty?
	jz	si7			; yes, result is the position
	dec	bx			; BX = offset
	sub	cx,bx			; CX = # chars from offset to end
	sub	cx,dx			; CX = # positions to try - 1
	jb	si8			; B is longer than the rest of A
	inc	cx
	lds	si,[pInstrA]
	lea	si,[si+bx+1]		; DS:SI -> 1st char to try
	les	di,[pInstrB]
	inc	di			; ES:DI -> 1st char of B
si1:	push	cx
	push	si
	push	di
	mov	cx,dx
	repe	cmpsb
	pop	di
	pop	si
	pop	cx
	je	si6			; match
	inc	si
	inc	bx
	loop	si1
	jmp	short si8		; no match
si6:	inc	bx			; BX = position
si7:	xchg	ax,bx			; AX = result
si8:	push	ax
	les	di,[pInstrA]
	call	releaseStr
	les	di,[pInstrB]
	call	releaseStr
	pop	ax
	mov	[retInstr].LOW,ax
	mov	[retInstr].HIW,0
	pop	ds
	LEAVE
	RETURN
si10:	jmp	strIllegal
ENDPROC	strInstr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strStr (STR$)
;
; Inputs:
;	32-bit return value
;	pointer to double (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strStr,FAR
	RETVAR	retStr,dword
	ARGVAR	pStrNum,dword
	LOCVAR	strBuf,byte,32
	ENTER
	push	ds
	push	ss
	pop	es
;
; If the double is an integer that fits in 32 bits (eg, STR$(I)), we format
; it with ITOA, which is much faster than FPU_DTOA.  Such a double is zero or
; has an exponent from 0 to 30, and no fraction bits are shifted out when its
; mantissa is shifted right by 52-exponent.
;
	lds	si,[pStrNum]		; DS:SI -> double
	mov	dx,[si+6]
	mov	ax,dx
	add	ax,ax			; AX = double without its sign
	or	ax,[si+4]
	or	ax,[si+2]
	or	ax,[si]
	mov	bx,ax			; BX:AX = zero if the double is zero
	jz	sst4
	mov	ax,dx
	and	ax,7FF0h
	mov	cl,4
	shr	ax,cl			; AX = biased exponent
	neg	ax
	add	ax,1075			; AX = # bits to shift (52-exponent)
	cmp	ax,22
	jb	sst8			; too large
	cmp	ax,52
	ja	sst8			; too small
	xchg	di,ax
	mov	ax,[si]
	mov	bx,[si+2]
	mov	cx,[si+4]
	and	dx,000Fh
	or	dl,10h			; DX:CX:BX:AX = mantissa
	sub	si,si			; SI = fraction bits
sst2:	shr	dx,1
	rcr	cx,1
	rcr	bx,1
	rcr	ax,1
	adc	si,0
	dec	di
	jnz	sst2
	test	si,si			; any fraction bits?
	jnz	sst8			; yes
	lds	si,[pStrNum]
	test	byte ptr [si+7],80h
	jz	sst4
	neg	bx
	neg	ax
	sbb	bx,0			; BX:AX = negative value
sst4:	xchg	si,ax
	mov	dx,bx			; DX:SI = value
	lea	di,[strBuf]		; ES:DI -> buffer
	mov	bx,((PF_LONG OR PF_SIGN OR PF_HASH) SHL 8) OR 10
	sub	cx,cx
	DOSUTIL	ITOA			; AX = # of characters
	xchg	cx,ax
	jmp	short sst9

sst8:	lds	si,[pStrNum]		; DS:SI -> double
	lea	di,[strBuf]		; ES:DI -> buffer
	mov	cx,32			; CX = size of buffer
	sub	dx,dx			; DX = width (none)
	mov	ax,(PF_HASH SHL 8) OR 0FFh
	mov	bx,FPU_DTOA		; AL = precision (none)
	call	callFPUFunc		; AH = flags (PF_HASH)
	lea	cx,[strBuf]
	sub	di,cx			; DI = # chars
	xchg	cx,di
sst9:	lea	si,[strBuf]
	call	newStr
	mov	[retStr].OFF,ax
	mov	[retStr].SEG,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	strStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strVal (VAL)
;
; Like MSBASIC, blanks (spaces, tabs, and linefeeds) are ignored, and if the
; string doesn't begin with a number, the result is zero.  The &H (hex) and
; &O (octal) prefixes are supported too (as is & alone, for octal); such a
; value is converted to decimal digits for FPU_ATOD.
;
; Inputs:
;	pointer to double result (in a slot)
;	string value (popped)
;
; Outputs:
;	double result updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strVal,FAR
	RETVAR	pValNum,dword
	ARGVAR	pValStr,dword
	LOCVAR	valBuf,byte,256
	ENTER
	push	ds
	push	ss
	pop	es
	lea	di,[valBuf]		; ES:DI -> buffer
	lds	si,[pValStr]
	sub	cx,cx
	test	si,si
	jz	sv3
	lodsb
	mov	cl,al
sv1:	lodsb
	cmp	al,' '
	je	sv2
	cmp	al,CHR_TAB
	je	sv2
	cmp	al,CHR_LINEFEED
	je	sv2
	stosb
sv2:	loop	sv1
sv3:	mov	al,0
	stosb				; null-terminate the buffer
	les	di,[pValStr]
	call	releaseStr
	push	ss
	pop	ds
	lea	si,[valBuf]		; DS:SI -> buffer
	cmp	byte ptr [si],'&'	; hex or octal prefix?
	jne	sv5			; no
	inc	si
	lodsb
	and	al,NOT 20h		; upper-case the prefix letter
	mov	bl,16
	cmp	al,'H'
	je	sv4
	mov	bl,8
	cmp	al,'O'
	je	sv4
	dec	si			; no letter, so it's octal
sv4:	mov	cx,-1			; CX = length (buffer is null-terminated)
	DOSUTIL	ATOI32			; DX:AX = value
	xchg	si,ax			; DX:SI = value
	push	ss
	pop	es
	lea	di,[valBuf]		; ES:DI -> buffer
	mov	bx,((PF_LONG OR PF_SIGN) SHL 8) OR 10
	sub	cx,cx
	DOSUTIL	ITOA			; AL = # of characters
	mov	ah,0
	add	di,ax
	mov	byte ptr es:[di],0	; null-terminate the decimal digits
	lea	si,[valBuf]		; DS:SI -> buffer
sv5:	les	di,[pValNum]		; ES:DI -> result
	mov	bx,FPU_ATOD
	call	callFPUFunc
	jnc	sv9
	les	di,[pValNum]		; no number, so the result is zero
	sub	ax,ax
	mov	cx,4
	rep	stosw
sv9:	pop	ds
	LEAVE
	RETURN
ENDPROC	strVal

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strSpace (SPACE$)
;
; Inputs:
;	32-bit return value
;	32-bit length (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	strSpace,FAR
	RETVAR	retSpace,dword
	ARGVAR	spaceLen,dword
	ENTER
	mov	bl,' '
	mov	ax,[spaceLen].LOW
	mov	dx,[spaceLen].HIW
	call	fillStr
	mov	[retSpace].OFF,ax
	mov	[retSpace].SEG,dx
	LEAVE
	RETURN
ENDPROC	strSpace

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strString (STRING$)
;
; Inputs:
;	32-bit return value
;	32-bit length (popped)
;	32-bit character code (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	strString,FAR
	RETVAR	retString,dword
	ARGVAR	stringLen,dword
	ARGVAR	stringChr,dword
	ENTER
	mov	ax,[stringChr].LOW
	mov	dx,[stringChr].HIW
	call	getByteArg
	xchg	bx,ax			; BL = character code
	mov	ax,[stringLen].LOW
	mov	dx,[stringLen].HIW
	call	fillStr
	mov	[retString].OFF,ax
	mov	[retString].SEG,dx
	LEAVE
	RETURN
ENDPROC	strString

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fillStr
;
; Inputs:
;	DX:AX = length
;	BL = character
;
; Outputs:
;	DX:AX = new string value, filled with the character
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	fillStr
	call	getByteArg
	xchg	cx,ax			; CX = length
	sub	ax,ax
	cwd
	jcxz	fl9
	call	allocStr		; ES:DI -> new string
	push	di
	inc	di
	mov	al,bl
	rep	stosb
	pop	ax
	mov	dx,es
fl9:	ret
ENDPROC	fillStr

CODE	ENDS

	end
