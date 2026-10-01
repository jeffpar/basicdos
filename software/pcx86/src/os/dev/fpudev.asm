;
; BASIC-DOS Floating-Point Unit Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This driver has no read/write interface; its only purpose is to provide
; the 64-bit floating-point ("double") functions that BASIC-DOS needs, by way
; of an FPU function table (FPUTBL) that callers obtain with IOCTL_GETFPU.
;
; The driver contains two sets of functions: one for systems with an 8087
; (HWCODE) and one for systems without (SWCODE).  Each set begins with its
; own FPUTBL, and each set is assembled in its own paragraph-aligned segment,
; so all its offsets (including the FPUTBL entries) are relative to the start
; of that set.  At init time, we detect whether an 8087 is present and either
; discard the SWCODE functions or move them down on top of the HWCODE
; functions.  Either way, the FPUTBL ends up at offset 0 of the paragraph that
; HWCODE originally started at, and no fixups are required, regardless of
; which set is retained.
;
; Since FPUTBL offsets are relative to that paragraph, callers must use the
; segment returned by IOCTL_GETFPU (not the driver's segment) when calling
; the functions.
;
; Code that doesn't depend on the FPU (eg, the parsing and formatting parts
; of FPU_ATOD and FPU_DTOA) lives in CODE, which is never moved, so it's shared
; by both sets of functions: their FPU_ATOD and FPU_DTOA entries are simply
; jumps to the shared code (via far pointers that follow each FPUTBL), and
; the shared code relies on two FPU-dependent primitives, FPU_TODEC and
; FPU_FROMDEC, to do the actual conversions.
;
	BIOSEQU equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	parser.inc
	include	fpu.inc

	.8087

DEV	group	CODE,HWCODE,SWCODE,INIT,DATA

CODE	segment para public 'CODE'

	public	FPU
FPU	DDH	<offset DEV:ddfpu_end+16,,DDATTR_CHAR+DDATTR_IOCTL,offset DEV:ddfpu_init,-1,2020202024555046h>

	DEFWORD	fpuSeg,0		; segment of the FPUTBL (at offset 0)
	DEFWORD	fpuInfo,0		; FPUTBL entries (low), FPUTYPE (high)
	DEFPTR	fpuToDec		; FPU_TODEC function (set by ddfpu_init)
	DEFPTR	fpuFromDec		; FPU_FROMDEC function (set by ddfpu_init)

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; The only requests we support are OPEN and CLOSE (which always succeed)
; and IOCTL_GETFPU.
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
; Modifies:
;	AX, DX, SI, DS
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddfpu_req,far
	mov	dx,DDSTAT_DONE
	mov	al,es:[bx].DDP_CMD
	cmp	al,DDC_OPEN
	je	ddq8
	cmp	al,DDC_CLOSE
	je	ddq8
	cmp	al,DDC_IOCTLIN
	jne	ddq7
	cmp	es:[bx].DDP_CODE,IOCTL_GETFPU
	jne	ddq7
	lds	si,es:[bx].DDPRW_ADDR	; DS:SI -> caller's far pointer
	mov	[si].OFF,0
	mov	ax,cs:[fpuSeg]
	mov	[si].SEG,ax
	mov	ax,cs:[fpuInfo]
	mov	es:[bx].DDP_CONTEXT,ax	; DDP_CONTEXT is returned in DX
	jmp	short ddq8
ddq7:	mov	dx,DDSTAT_ERROR + DDERR_UNKCMD
ddq8:	mov	es:[bx].DDP_STATUS,dx
	ret
ENDPROC	ddfpu_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; comAtoD (FPU_ATOD)
;
; Shared by both sets of functions; it parses the number into a series of
; significant digits (up to 19, which the 8087 can represent exactly, with any
; remaining digits affecting only the decimal exponent), and then calls
; FPU_FROMDEC.  Since multiple sessions may be converting numbers at the same
; time, all our variables are on the stack.
;
; Inputs:
;	DS:SI -> chars
;	ES:DI -> double
;
; Outputs:
;	Carry clear if successful, SI -> next char
;	Carry set if no digits (SI unchanged) or out of range
;
; Modifies:
;	AX, BX, CX, DX
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	comAtoD,FAR
	LOCVAR	atoStart,word		; original SI
	LOCVAR	atoDigits,byte,20	; significant digits
	ENTER
	push	di
	mov	[atoStart],si
	sub	bx,bx			; BL = flags: 01h digit, 02h point,
	sub	cx,cx			; 04h exponent digit, 40h negative
	sub	dx,dx			; exponent, 80h negative mantissa
	lodsb				; CX = # significant digits
	cmp	al,'-'			; DX = decimal exponent
	jne	ca1
	or	bl,80h
	jmp	short ca2
ca1:	cmp	al,'+'
	je	ca2
	dec	si
ca2:	lodsb
	cmp	al,'.'
	jne	ca3
	test	bl,02h			; decimal point already seen?
	jnz	ca6			; yes, so this ends the number
	or	bl,02h
	jmp	ca2
ca3:	sub	al,'0'
	cmp	al,9
	ja	ca6			; not a digit
	or	bl,01h
	test	al,al
	jnz	ca4
	jcxz	ca4b			; leading zero
ca4:	cmp	cx,19			; room for another digit?
	jae	ca5			; no
	mov	di,cx
	add	al,'0'
	mov	[atoDigits][di],al
	inc	cx
ca4b:	test	bl,02h			; after the decimal point?
	jz	ca2			; no
	dec	dx			; yes, so decrement the exponent
	jmp	ca2
ca5:	test	bl,02h			; ignoring a digit after the point?
	jnz	ca2			; yes
	inc	dx			; no, so increment the exponent
	jmp	ca2

ca6:	test	bl,01h			; any digits?
	jz	ca8			; no
	add	al,'0'
	or	al,20h
	cmp	al,'e'
	je	ca6a
	cmp	al,'d'
	jne	ca6x
ca6a:	push	si			; save pointer to char after 'E'
	sub	di,di			; DI = exponent value
	lodsb
	cmp	al,'-'
	jne	ca6b
	or	bl,40h
	jmp	short ca6c
ca6b:	cmp	al,'+'
	je	ca6c
	dec	si
ca6c:	lodsb
	sub	al,'0'
	cmp	al,9
	ja	ca6d
	or	bl,04h
	cmp	di,1000			; ignore digits that won't matter
	jae	ca6c
	mov	ah,0			; DI = DI * 10 + AX
	shl	di,1
	add	ax,di
	shl	di,1
	shl	di,1
	add	di,ax
	jmp	ca6c
ca6d:	pop	ax			; AX -> char after 'E'
	test	bl,04h			; any exponent digits?
	jnz	ca6e			; yes
	xchg	si,ax			; no, so the number ended at the 'E'
	jmp	short ca6x
ca6e:	test	bl,40h
	jz	ca6f
	neg	di
ca6f:	add	dx,di
ca6x:	dec	si			; SI -> first char after the number
	pop	di			; ES:DI -> double
	push	si
	push	ds
	push	ss
	pop	ds
	lea	si,[atoDigits]		; DS:SI -> digits
	xchg	ax,dx			; AX = decimal exponent
	call	cs:[fpuFromDec]
	pop	ds
	pop	si
	jmp	short ca9
ca8:	pop	di
	mov	si,[atoStart]
	stc
ca9:	LEAVE
	ret
ENDPROC	comAtoD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; comDtoA (FPU_DTOA)
;
; Shared by both sets of functions; it calls FPU_TODEC for the digits, and
; then formats them.  Without a precision, the format is BASIC-style: up to
; FPU_DIGITS significant digits, using fixed-point notation (without a leading
; zero) for decimal exponents from -4 to FPU_DIGITS-1, and exponential notation
; otherwise (eg, ".25", "1E+20").  With a precision, the format is fixed-point
; with that many fractional digits (eg, "0.25" for a precision of 2).
;
; The flags (see PF_* in parser.inc) work the same as they do in sprintf:
; PF_LEFT for left alignment, PF_ZERO for zero padding, and PF_HASH for a space
; in lieu of a minus sign for non-negative values (as BASIC's PRINT does).
;
; Every number is generated twice: first to count the characters, so we know
; how much padding to add, and then to store them.  Since multiple sessions
; may be formatting numbers at the same time, all our variables are on the
; stack.
;
; Inputs:
;	DS:SI -> double
;	ES:DI -> buffer
;	CX = buffer length
;	DX = width (minimum # of chars)
;	AL = precision (0FFh if none)
;	AH = flags (PF_LEFT, PF_ZERO, PF_HASH)
;
; Outputs:
;	DI -> first byte after the last character
;
; Modifies:
;	AX, BX, CX, DX, SI
;
FMT_FIX		equ	0		; fixed-point notation
FMT_EXP		equ	1		; exponential notation
FMT_STR		equ	2		; string (eg, "INF")

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	comDtoA,FAR
	LOCVAR	fmtLimit,word		; buffer limit
	LOCVAR	fmtWidth,word		; minimum # of chars
	LOCVAR	fmtCount,word		; # of chars generated
	LOCVAR	fmtExp,word		; decimal exponent of first digit
	LOCVAR	fmtNum,word		; # of digits
	LOCVAR	fmtZeros,word		; # of zeros to pad after the sign
	LOCVAR	fmtPrecis,byte		; precision (0FFh if none)
	LOCVAR	fmtFlags,byte		; PF_* flags
	LOCVAR	fmtSign,byte		; sign char (0 if none)
	LOCVAR	fmtMode,byte		; FMT_* mode
	LOCVAR	fmtEmit,byte		; 0 to count chars, 1 to store them
	LOCVAR	fmtDigits,byte,FPU_DIGITS	; (keep total LOCVAR bytes even)
	ENTER
	push	es
	push	di
	add	cx,di
	mov	[fmtLimit],cx
	mov	[fmtWidth],dx
	mov	[fmtPrecis],al
	mov	[fmtFlags],ah
	sub	ax,ax
	mov	[fmtExp],ax
	mov	[fmtNum],ax
	mov	[fmtSign],al
	mov	[fmtMode],al
	test	byte ptr [si+7],80h	; negative?
	jz	cd1			; no
	mov	[fmtSign],'-'
	jmp	short cd2
cd1:	test	[fmtFlags],PF_HASH
	jz	cd2
	mov	[fmtSign],' '
;
; Infinities are displayed as "INF" and NaNs as "NAN".
;
cd2:	mov	ax,[si+6]
	and	ax,7FF0h
	cmp	ax,7FF0h		; infinity or NaN?
	jne	cd3			; no
	mov	[fmtMode],FMT_STR
	mov	[fmtNum],3
	mov	ax,[si+6]
	and	ax,000Fh
	or	ax,[si+4]
	or	ax,[si+2]
	or	ax,[si]
	mov	ax,'AN'
	mov	dl,'N'
	jnz	cd2a			; NaN
	mov	ax,'NI'
	mov	dl,'F'
cd2a:	lea	bx,[fmtDigits]
	mov	ss:[bx],ax
	mov	ss:[bx+2],dl
	jmp	short cd8

cd3:	push	ss
	pop	es
	lea	di,[fmtDigits]		; ES:DI -> digits
	mov	cl,FPU_DIGITS
	call	cs:[fpuToDec]		; CX = # digits, AX = exponent
	mov	[fmtExp],ax
	mov	[fmtNum],cx
	mov	al,[fmtPrecis]
	cmp	al,0FFh			; precision specified?
	je	cd5			; no
	jcxz	cd8			; zero is zero
	mov	ah,0
	add	ax,[fmtExp]
	inc	ax			; AX = # digits required by precision
	cmp	ax,FPU_DIGITS		; more than we already have?
	jge	cd8			; yes (so the rest will be zeros)
	mov	[fmtNum],0
	test	ax,ax			; any digits at all?
	jl	cd8			; no
	xchg	cx,ax			; CL = # digits
	lea	di,[fmtDigits]
	call	cs:[fpuToDec]		; CX = # digits, AX = exponent
	mov	[fmtExp],ax
	mov	[fmtNum],cx
	jmp	short cd8
;
; For BASIC-style formatting, strip the trailing zeros, and choose a notation.
;
cd5:	jcxz	cd8			; zero is zero
	lea	bx,[fmtDigits]
	add	bx,cx
cd5a:	dec	bx
	cmp	byte ptr ss:[bx],'0'
	jne	cd5b
	loop	cd5a			; (there's always a non-zero digit)
cd5b:	mov	[fmtNum],cx
	mov	ax,[fmtExp]
	cmp	ax,-4
	jl	cd5c
	cmp	ax,FPU_DIGITS
	jl	cd8
cd5c:	mov	[fmtMode],FMT_EXP
;
; Count the chars, calculate the padding, and then store the chars.
;
cd8:	pop	di
	pop	es			; ES:DI -> buffer again
	sub	ax,ax
	mov	[fmtEmit],al
	mov	[fmtCount],ax
	mov	[fmtZeros],ax
	call	fmtBody
	mov	cx,[fmtWidth]
	sub	cx,[fmtCount]		; CX = padding, if positive
	jg	cd9
	sub	cx,cx
cd9:	inc	[fmtEmit]
	mov	al,' '
	test	[fmtFlags],PF_LEFT	; left alignment?
	jnz	cd11			; yes
	test	[fmtFlags],PF_ZERO	; zero padding?
	jz	cd10			; no
	mov	[fmtZeros],cx		; yes
	sub	cx,cx
cd10:	call	fmtFill			; store leading spaces, if any
	call	fmtBody			; and then the number
	jmp	short cd12
cd11:	push	cx
	call	fmtBody			; store the number
	pop	cx
	mov	al,' '
	call	fmtFill			; and then trailing spaces, if any
cd12:	LEAVE
	ret
ENDPROC	comDtoA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fmtBody (comDtoA helper)
;
; Generates the sign, any zero padding, and the number.
;
; Inputs:
;	BP -> comDtoA variables
;	ES:DI -> next char in buffer
;
; Outputs:
;	DI advanced (if fmtEmit is set) and fmtCount updated
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	fmtBody
	mov	al,[fmtSign]
	test	al,al
	jz	fb1
	call	fmtPut
fb1:	mov	al,'0'
	mov	cx,[fmtZeros]
	call	fmtFill
	sub	si,si			; SI = digit index
	mov	cx,[fmtNum]
	mov	al,[fmtMode]
	cmp	al,FMT_FIX
	je	fb2
	cmp	al,FMT_EXP
	je	fb6
fb1a:	mov	al,[fmtDigits][si]	; FMT_STR
	call	fmtPut
	inc	si
	loop	fb1a
	ret
;
; Fixed-point notation: the integer digits (if any), followed by the
; fractional digits (if any).  Without a precision, the fractional digits
; are the remaining significant digits; otherwise, it's precision digits.
;
fb2:	mov	dx,[fmtExp]
	test	dx,dx			; any integer digits?
	jge	fb3			; yes
	cmp	[fmtPrecis],0FFh	; BASIC-style?
	je	fb4			; yes, so no leading zero
	mov	al,'0'
	call	fmtPut
	jmp	short fb4
fb3:	call	fmtDigit
	inc	si
	cmp	si,dx
	jle	fb3
fb4:	mov	si,dx
	inc	si			; SI = index of first fractional digit
	cmp	[fmtPrecis],0FFh	; BASIC-style?
	jne	fb4a			; no
	sub	cx,si			; CX = # remaining significant digits
	jmp	short fb4b
fb4a:	mov	cl,[fmtPrecis]
	mov	ch,0
fb4b:	test	cx,cx			; any fractional digits?
	jle	fb9			; no
	mov	al,'.'
	call	fmtPut
fb5:	call	fmtDigit
	inc	si
	loop	fb5
	ret
;
; Exponential notation: the first digit, followed by a decimal point and any
; remaining digits, followed by "E", a sign, and at least 2 exponent digits.
;
fb6:	call	fmtDigit
	dec	cx			; any remaining digits?
	jz	fb7			; no
	mov	al,'.'
	call	fmtPut
fb6a:	inc	si
	call	fmtDigit
	loop	fb6a
fb7:	mov	al,'E'
	call	fmtPut
	mov	dx,[fmtExp]
	mov	al,'+'
	test	dx,dx
	jge	fb7a
	mov	al,'-'
	neg	dx
fb7a:	call	fmtPut
	xchg	ax,dx			; AX = abs(exponent)
	mov	cl,100
	div	cl			; AL = hundreds, AH = remainder
	test	al,al
	jz	fb8
	add	al,'0'
	call	fmtPut
fb8:	mov	al,ah
	aam				; AH = tens, AL = ones
	add	ax,'00'
	xchg	al,ah
	call	fmtPut			; store tens
	mov	al,ah
	call	fmtPut			; store ones
fb9:	ret
ENDPROC	fmtBody

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fmtDigit, fmtFill, fmtPut (comDtoA helpers)
;
; fmtDigit generates the digit at index SI ('0' if there's no such digit),
; fmtFill generates CX copies of AL, and fmtPut generates AL.  Chars are
; stored only if fmtEmit is set, and only if there's room in the buffer.
;
; Inputs:
;	SI = digit index (fmtDigit)
;	AL = char (fmtFill, fmtPut)
;	CX = count (fmtFill)
;	BP -> comDtoA variables
;	ES:DI -> next char in buffer
;
; Outputs:
;	DI advanced (if fmtEmit is set) and fmtCount updated
;
; Modifies:
;	AL (fmtDigit), CX (fmtFill)
;
DEFPROC	fmtDigit
	mov	al,'0'
	cmp	si,[fmtNum]		; (negative indexes are also out of range)
	jae	fmtPut
	mov	al,[fmtDigits][si]
	jmp	short fmtPut
	DEFLBL	fmtFill,near
	jcxz	fp9
fp1:	call	fmtPut
	loop	fp1
	ret
	DEFLBL	fmtPut,near
	inc	[fmtCount]
	cmp	[fmtEmit],0		; storing chars?
	je	fp9			; no
	cmp	di,[fmtLimit]		; room in the buffer?
	jae	fp9			; no
	stosb
fp9:	ret
ENDPROC	fmtDigit

CODE	ends

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; 8087 (hardware) functions
;
; Since multiple sessions may be using the FPU, and there's currently no
; FPU state saved or restored on context switches, every function disables
; interrupts while it has values on the FPU stack.  The functions are also
; designed to leave the FPU stack empty and all its exceptions cleared.
;
; Most of these functions run with BX -> the caller's return address
; (on the SS stack), so the top operand is at SS:[BX+4].
;
; TODO: The control word we use (the FNINIT default) masks all exceptions,
; so we check for divide-by-zero (ZE), overflow (OE), and invalid operation
; (IE) exceptions after each operation, and convert ZE to a divide error and
; the others to an overflow error.  BASIC errors like "Illegal function call"
; may be more appropriate for some invalid operations (eg, SQR of a negative
; number), but they will require a better error interface.
;
SW_IE		equ	01h		; invalid operation
SW_DE		equ	02h		; denormalized operand
SW_ZE		equ	04h		; zero divide
SW_OE		equ	08h		; overflow
SW_UE		equ	10h		; underflow
SW_PE		equ	20h		; precision

CW_NEAR		equ	037Fh		; FNINIT default (round to nearest)
CW_DOWN		equ	077Fh		; round down (toward -infinity)
CW_CHOP		equ	0F7Fh		; round toward zero

HWCODE	segment para public 'CODE'

        ASSUME	CS:HWCODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

	DEFLBL	hwTable,word
	dw	hwNeg, hwExp, hwMul, hwDiv, hwAdd, hwSub
	dw	hwEQ,  hwNE,  hwLT,  hwGT,  hwLE,  hwGE
	dw	hwCvtDL, hwCvt2DL, hwCvtLD, hwCvtL2D, hwCvtDL, hwCvtD2L
	dw	hwCvtLD, hwCvt2LD
	dw	hwAbs, hwInt, hwFix, hwSqr, hwAtoD, hwDtoA
	dw	hwToDec, hwFromDec
	IF	($ - hwTable) NE size FPUTBL
	ERROR	<hwTable does not match FPUTBL>
	ENDIF
	DEFPTR	hwComAtoD		; comAtoD (set by ddfpu_init)
	DEFPTR	hwComDtoA		; comDtoA (set by ddfpu_init)

	DEFWORD	hwStatus,0		; status word (used with interrupts off)
	DEFWORD	hwTemp,0		; temp word (used with interrupts off)
	DEFWORD	hwCWNear,CW_NEAR
	DEFWORD	hwCWDown,CW_DOWN
	DEFWORD	hwCWChop,CW_CHOP
	DEFQUAD	hwHalf,3FE0000000000000h; 0.5
	DEFQUAD	hwOne,3FF0000000000000h	; 1.0
	DEFQUAD	hwTen,4024000000000000h	; 10.0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwNeg
;
; Inputs:
;	1 64-bit double on stack
;
; Outputs:
;	1 64-bit double on stack (negated)
;
; Modifies:
;	BX
;
DEFPROC	hwNeg,FAR
	mov	bx,sp
	xor	byte ptr ss:[bx+11],80h	; no FPU required to flip the sign bit
	ret
ENDPROC	hwNeg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwAbs
;
; Inputs:
;	1 64-bit double on stack
;
; Outputs:
;	1 64-bit double on stack (absolute value)
;
; Modifies:
;	BX
;
DEFPROC	hwAbs,FAR
	mov	bx,sp
	and	byte ptr ss:[bx+11],7Fh	; no FPU required to clear the sign bit
	ret
ENDPROC	hwAbs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwMul, hwDiv, hwAdd, hwSub
;
; Inputs:
;	2 64-bit doubles on stack (A, then B on top)
;
; Outputs:
;	1 64-bit double on stack (A*B, A/B, A+B, or A-B)
;
; Modifies:
;	AX, BX
;
DEFPROC	hwMul,FAR
	call	hwLoadA			; ST(0) = A
	fmul	qword ptr ss:[bx+4]	; ST(0) = A * B
	jmp	short hwStoreA
	DEFLBL	hwDiv,near
	call	hwLoadA
	fdiv	qword ptr ss:[bx+4]	; ST(0) = A / B
	jmp	short hwStoreA
	DEFLBL	hwAdd,near
	call	hwLoadA
	fadd	qword ptr ss:[bx+4]	; ST(0) = A + B
	jmp	short hwStoreA
	DEFLBL	hwSub,near
	call	hwLoadA
	fsub	qword ptr ss:[bx+4]	; ST(0) = A - B
	DEFLBL	hwStoreA,near
	fstp	qword ptr ss:[bx+12]	; replace A with ST(0)
	call	hwDone
	ret	8			; and pop B
ENDPROC	hwMul

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwExp
;
; Integer exponents (from -32768 to 32767) are handled by repeated squaring,
; so they're exact whenever possible and negative bases are allowed; all other
; exponents are calculated as 2^(B * log2(A)), so negative bases are invalid.
;
; Inputs:
;	2 64-bit doubles on stack (A, then B on top)
;
; Outputs:
;	1 64-bit double on stack (A^B)
;
; Modifies:
;	AX, BX, CX
;
DEFPROC	hwExp,FAR
	call	hwLoadA			; ST(0) = A
	fld	qword ptr ss:[bx+4]	; ST(0) = B, ST(1) = A
	fist	cs:[hwTemp]		; store B as a 16-bit integer
	ficom	cs:[hwTemp]		; and compare it to B
	call	hwStat
	jne	he5			; B is not a 16-bit integer
	fstp	st(0)			; ST(0) = A
	mov	cx,cs:[hwTemp]
	test	cx,cx
	jns	he1
	neg	cx			; CX = abs(B) (where 8000h is 32768)
he1:	call	hwPowInt		; ST(0) = A^abs(B)
	cmp	cs:[hwTemp],0		; was B negative?
	jge	he9			; no
	fdivr	cs:[hwOne]		; yes, so result = 1 / result
	jmp	short he9
he5:	fclex				; clear any exception from FIST
	fxch				; ST(0) = A, ST(1) = B
	ftst
	call	hwStat
	jne	he6			; A is non-zero
	fstp	st(1)			; zero raised to any power is zero
	jmp	short he9
he6:	fyl2x				; ST(0) = B * log2(A)
	call	hwPow2			; ST(0) = 2^(B * log2(A))
he9:	jmp	hwStoreA
ENDPROC	hwExp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwEQ, hwNE, hwLT, hwGT, hwLE, hwGE
;
; Each entry point loads CL with a mask of the comparison outcomes that make
; the relation true: 4 (A < B), 2 (A = B), and 1 (A > B).
;
; Inputs:
;	2 64-bit doubles on stack (A, then B on top)
;
; Outputs:
;	1 32-bit long on stack (-1 if true, 0 if false)
;
; Modifies:
;	AX, BX, CX
;
DEFPROC	hwEQ,FAR
	mov	cl,2
	jmp	short hwCmp
	DEFLBL	hwNE,near
	mov	cl,4+1
	jmp	short hwCmp
	DEFLBL	hwLT,near
	mov	cl,4
	jmp	short hwCmp
	DEFLBL	hwGT,near
	mov	cl,1
	jmp	short hwCmp
	DEFLBL	hwLE,near
	mov	cl,4+2
	jmp	short hwCmp
	DEFLBL	hwGE,near
	mov	cl,2+1
hwCmp:	call	hwLoadA			; ST(0) = A
	fcomp	qword ptr ss:[bx+4]	; compare A to B and pop
	call	hwDone			; AH = high byte of status
	sahf				; CF = C0 and ZF = C3
	mov	al,1
	ja	hc1			; A > B
	mov	al,2
	je	hc1			; A = B
	mov	al,4			; A < B
hc1:	and	al,cl			; is the relation true?
	neg	al			; carry set if so
	sbb	ax,ax			; AX = -1 if true, 0 if false
	mov	ss:[bx+16],ax		; the result replaces the top half of A
	mov	ss:[bx+18],ax
	ret	12			; and the rest of A and B are popped
ENDPROC	hwEQ

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwCvtDL (FPU_CVT1DL and FPU_CVTD1L)
;
; Converts the double on top of the stack to a long, rounding to the nearest
; integer (with ties rounded to even).
;
; Inputs:
;	1 64-bit double on stack
;
; Outputs:
;	1 32-bit long on stack
;
; Modifies:
;	AX, BX
;
DEFPROC	hwCvtDL,FAR
	call	hwLoadT			; ST(0) = top double
	fistp	dword ptr ss:[bx+8]	; replace top half of double with long
	call	hwDone
	ret	4
ENDPROC	hwCvtDL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwCvt2DL (FPU_CVT2DL)
;
; Inputs:
;	2 64-bit doubles on stack (A, then B on top)
;
; Outputs:
;	2 32-bit longs on stack (A, then B on top)
;
; Modifies:
;	AX, BX
;
DEFPROC	hwCvt2DL,FAR
	call	hwLoadA			; ST(0) = A
	fld	qword ptr ss:[bx+4]	; ST(0) = B, ST(1) = A
	fistp	dword ptr ss:[bx+12]
	fistp	dword ptr ss:[bx+16]
	call	hwDone
	ret	8
ENDPROC	hwCvt2DL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwCvtD2L (FPU_CVTD2L)
;
; Inputs:
;	1 64-bit double and 1 32-bit long on stack (long on top)
;
; Outputs:
;	2 32-bit longs on stack
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	hwCvtD2L,FAR
	mov	bx,sp
	cli
	fld	qword ptr ss:[bx+8]	; ST(0) = double
	fwait				; make sure the 8087 is done reading it
	mov	ax,ss:[bx+4]
	mov	dx,ss:[bx+6]
	mov	ss:[bx+8],ax		; move the long up 4 bytes
	mov	ss:[bx+10],dx
	fistp	dword ptr ss:[bx+12]	; and store the converted double above it
	call	hwDone
	ret	4
ENDPROC	hwCvtD2L

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwCvtLD (FPU_CVTL1D and FPU_CVT1LD)
;
; Converts the long on top of the stack to a double, so the stack grows by
; 4 bytes, which means we must pop the return address and push it back.
;
; Inputs:
;	1 32-bit long on stack
;
; Outputs:
;	1 64-bit double on stack
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	hwCvtLD,FAR
	pop	cx
	pop	dx			; DX:CX = return address
	mov	bx,sp
	cli
	fild	dword ptr ss:[bx]
	fstp	qword ptr ss:[bx-4]
	sub	sp,4
	DEFLBL	hwCvtRet,near
	push	dx
	push	cx
	call	hwDone
	ret
ENDPROC	hwCvtLD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwCvtL2D (FPU_CVTL2D)
;
; Inputs:
;	1 32-bit long and 1 64-bit double on stack (double on top)
;
; Outputs:
;	2 64-bit doubles on stack
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	hwCvtL2D,FAR
	pop	cx
	pop	dx			; DX:CX = return address
	mov	bx,sp
	cli
	fild	dword ptr ss:[bx+8]	; ST(0) = long
	fld	qword ptr ss:[bx]	; ST(0) = double, ST(1) = long
	fstp	qword ptr ss:[bx-4]	; move the double down 4 bytes
	fstp	qword ptr ss:[bx+4]	; and store the converted long above it
	sub	sp,4
	jmp	hwCvtRet
ENDPROC	hwCvtL2D

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwCvt2LD (FPU_CVT2LD)
;
; Inputs:
;	2 32-bit longs on stack (A, then B on top)
;
; Outputs:
;	2 64-bit doubles on stack (A, then B on top)
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	hwCvt2LD,FAR
	pop	cx
	pop	dx			; DX:CX = return address
	mov	bx,sp
	cli
	fild	dword ptr ss:[bx+4]	; ST(0) = A
	fild	dword ptr ss:[bx]	; ST(0) = B, ST(1) = A
	fstp	qword ptr ss:[bx-8]
	fstp	qword ptr ss:[bx]
	sub	sp,8
	jmp	hwCvtRet
ENDPROC	hwCvt2LD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwInt, hwFix, hwSqr
;
; Inputs:
;	1 64-bit double on stack
;
; Outputs:
;	1 64-bit double on stack (INT, FIX, or SQR of the input)
;
; Modifies:
;	AX, BX, SI
;
DEFPROC	hwInt,FAR
	mov	si,offset hwCWDown	; INT rounds down
	jmp	short hwRnd
	DEFLBL	hwFix,near
	mov	si,offset hwCWChop	; FIX rounds toward zero
hwRnd:	call	hwLoadT			; ST(0) = top double
	fldcw	word ptr cs:[si]
	frndint
	fldcw	cs:[hwCWNear]
	jmp	short hwStoreT
	DEFLBL	hwSqr,near
	call	hwLoadT
	fsqrt
	DEFLBL	hwStoreT,near
	fstp	qword ptr ss:[bx+4]	; replace top double with ST(0)
	call	hwDone
	ret
ENDPROC	hwInt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwAtoD, hwDtoA
;
; These simply jump to the shared code (see comAtoD and comDtoA).
;
DEFPROC	hwAtoD,FAR
	jmp	cs:[hwComAtoD]
	DEFLBL	hwDtoA,near
	jmp	cs:[hwComDtoA]
ENDPROC	hwAtoD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwToDec (FPU_TODEC)
;
; We determine the decimal exponent (e) of the absolute value (x), scale x by
; 10^(N-1-e) so that it's an integer from 10^(N-1) to 10^N - 1, and convert
; that to BCD with FBSTP.  When N is zero, x is scaled to a value from 0.1 to
; 1, so it rounds to either 0 or 1 (in which case, we return 1 digit for e+1).
;
; Inputs:
;	DS:SI -> double (which must be finite)
;	CL = N (# of significant digits, from 0 to FPU_DIGITS)
;	ES:DI -> buffer (for N digits)
;
; Outputs:
;	CX = # of digits stored (normally N; zero if the value is zero)
;	AX = decimal exponent of the first digit
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	hwToDec,FAR
	sub	sp,10			; room for BCD
	mov	bx,sp			; SS:BX -> BCD
	mov	ch,0			; CX = N
	cli
	fld	qword ptr [si]
	fabs				; ST(0) = x
	ftst
	call	hwStat
	jne	ht1
	fstp	st(0)			; x is zero
	sti
	sub	ax,ax
	sub	cx,cx
	jmp	ht9
ht1:	fldlg2				; ST(0) = log10(2), ST(1) = x
	fld	st(1)			; ST(0) = x
	fyl2x				; ST(0) = log10(x), ST(1) = x
	fldcw	cs:[hwCWDown]
	fistp	cs:[hwTemp]		; e = floor(log10(x))
	fldcw	cs:[hwCWNear]
	fwait
	mov	dx,cs:[hwTemp]		; DX = e
	mov	ax,cx
	dec	ax
	sub	ax,dx
	call	hwScale10		; ST(0) = y = x * 10^(N-1-e)
	push	cx
	fld	cs:[hwTen]
	call	hwPowInt		; ST(0) = 10^N, ST(1) = y
	pop	cx
;
; Since e is only an estimate, it may be off by one, so make sure y is in
; the desired range, both before and after rounding.
;
	fld	st(0)
	fdiv	cs:[hwTen]		; ST(0) = 10^(N-1)
	fcomp	st(2)			; compare 10^(N-1) to y
	call	hwStat
	jbe	ht2			; y is not too small
	fxch
	fmul	cs:[hwTen]		; y is too small, so multiply by 10
	fxch
	dec	dx
ht2:	fxch				; ST(0) = y, ST(1) = 10^N
	frndint
	jcxz	ht3			; (N = 0 is handled below)
	fcom	st(1)
	call	hwStat
	jb	ht3			; y is not too large
	fdiv	cs:[hwTen]		; y rounded up to 10^N, so divide by 10
	inc	dx
ht3:	fstp	st(1)			; ST(0) = y
	fbstp	tbyte ptr ss:[bx]
	fwait
	fclex
	sti
	xchg	ax,dx			; AX = e
	jcxz	ht7
;
; Unpack the CX digits from the BCD, starting with the most significant.
;
ht4:	push	ax
	push	di
	mov	dx,cx
ht5:	dec	dx			; DX = digit index
	push	bx
	mov	ax,dx
	shr	ax,1
	add	bx,ax
	mov	al,ss:[bx]		; AL = BCD byte containing the digit
	pop	bx
	test	dl,1
	jz	ht6
	push	cx
	mov	cl,4
	shr	al,cl
	pop	cx
ht6:	and	al,0Fh
	add	al,'0'
	stosb
	test	dx,dx
	jnz	ht5
	pop	di
	pop	ax
	jmp	short ht9
ht7:	cmp	byte ptr ss:[bx],cl	; when N is zero, did the value round up?
	je	ht9			; no (so CX is zero)
	inc	ax			; yes, so return 1 digit at e+1
	inc	cx
	jmp	ht4
ht9:	add	sp,10
	ret
ENDPROC	hwToDec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwFromDec (FPU_FROMDEC)
;
; Inputs:
;	DS:SI -> digits (up to 19, which the 8087 can represent exactly)
;	CX = # of digits
;	AX = decimal exponent (the value is digits * 10^AX)
;	BL = 80h if negative, 0 if not
;	ES:DI -> double
;
; Outputs:
;	Carry set if out of range
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	hwFromDec,FAR
	xchg	dx,ax			; DX = exponent
	cli
	fldz				; ST(0) = mantissa
	jcxz	hf2
hf1:	lodsb
	sub	al,'0'
	cbw
	mov	cs:[hwTemp],ax
	fmul	cs:[hwTen]
	fiadd	cs:[hwTemp]		; mantissa = mantissa * 10 + digit
	loop	hf1
hf2:	xchg	ax,dx
	call	hwScale10		; ST(0) = mantissa * 10^exponent
	test	bl,80h
	jz	hf3
	fchs
hf3:	fstp	qword ptr es:[di]
	call	hwStat
	fclex
	sti
	test	al,SW_IE OR SW_OE OR SW_ZE
	jz	hf9			; carry clear
	stc
hf9:	ret
ENDPROC	hwFromDec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwLoadA
;
; Disables interrupts and loads the 2nd (deeper) of two doubles on the stack.
;
; Inputs:
;	2 64-bit doubles on stack, followed by FAR and NEAR return addresses
;
; Outputs:
;	ST(0) = 2nd double (A)
;	BX -> FAR return address (so A is at SS:[BX+12] and B at SS:[BX+4])
;
; Modifies:
;	BX
;
DEFPROC	hwLoadA
	mov	bx,sp
	inc	bx
	inc	bx
	cli
	fld	qword ptr ss:[bx+12]
	ret
ENDPROC	hwLoadA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwLoadT
;
; Disables interrupts and loads the top double on the stack.
;
; Inputs:
;	1 64-bit double on stack, followed by FAR and NEAR return addresses
;
; Outputs:
;	ST(0) = top double
;	BX -> FAR return address (so the double is at SS:[BX+4])
;
; Modifies:
;	BX
;
DEFPROC	hwLoadT
	mov	bx,sp
	inc	bx
	inc	bx
	cli
	fld	qword ptr ss:[bx+4]
	ret
ENDPROC	hwLoadT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwStat
;
; Inputs:
;	None
;
; Outputs:
;	AX = FPU status word
;	CF = C0, PF = C2, ZF = C3 (eg, from FCOM or FTST)
;
; Modifies:
;	AX
;
DEFPROC	hwStat
	fstsw	cs:[hwStatus]
	fwait
	mov	ax,cs:[hwStatus]
	sahf
	ret
ENDPROC	hwStat

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwDone
;
; Re-enables interrupts and checks for exceptions, signaling a divide error
; or overflow error as appropriate.
;
; Inputs:
;	None
;
; Outputs:
;	AX = FPU status word
;
; Modifies:
;	AX
;
DEFPROC	hwDone
	call	hwStat
	sti
	test	al,SW_ZE
	jnz	hdn1
	test	al,SW_IE OR SW_OE
	jnz	hdn2
	ret
hdn1:	fclex
	int	INT_DV
	ret
hdn2:	fclex
	int	INT_OF
	ret
ENDPROC	hwDone

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwScale10
;
; Multiplies (or for negative exponents, divides) by an exact power of ten
; (or as exact as the FPU allows), which is critical for decimal conversions.
; Large exponents are applied in steps of no more than 10^256, so that very
; small numbers can be scaled up without the power itself overflowing.
;
; Inputs:
;	ST(0) = x
;	AX = n
;
; Outputs:
;	ST(0) = x * 10^n
;
; Modifies:
;	AX
;
DEFPROC	hwScale10
	push	bx
	push	cx
	xchg	bx,ax			; BX = n
hs1:	mov	ax,bx
	test	ax,ax
	jz	hs9
	jns	hs2
	neg	ax			; AX = abs(n)
hs2:	cmp	ax,256
	jbe	hs3
	mov	ax,256
hs3:	mov	cx,ax			; CX = abs(n) for this step
	fld	cs:[hwTen]		; ST(0) = 10, ST(1) = x
	call	hwPowInt		; ST(0) = 10^CX
	test	bx,bx
	js	hs4
	fmul				; ST(0) = x * 10^CX
	sub	bx,ax
	jmp	hs1
hs4:	fdivr	st,st(1)		; ST(0) = x / 10^CX
	fstp	st(1)
	add	bx,ax
	jmp	hs1
hs9:	pop	cx
	pop	bx
	ret
ENDPROC	hwScale10

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwPowInt
;
; Raises ST(0) to an unsigned integer power by repeated squaring.
;
; Inputs:
;	ST(0) = b
;	CX = n
;
; Outputs:
;	ST(0) = b^n
;
; Modifies:
;	CX
;
DEFPROC	hwPowInt
	fld1				; ST(0) = result, ST(1) = b
	jcxz	hpi9
hpi1:	shr	cx,1
	jnc	hpi2
	fmul	st,st(1)		; multiply result by current power of b
hpi2:	jz	hpi9			; (ZF still set by SHR)
	fxch
	fmul	st,st(0)		; square the current power of b
	fxch
	jmp	hpi1
hpi9:	fstp	st(1)			; ST(0) = result
	ret
ENDPROC	hwPowInt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwPow2
;
; The 8087's F2XM1 requires an input from 0 to 0.5, so we split t into an
; integer i (rounded down) and a fraction f (from 0 to 1), and then calculate
; 2^t as (2^(f/2))^2 * 2^i.
;
; Inputs:
;	ST(0) = t
;
; Outputs:
;	ST(0) = 2^t
;
; Modifies:
;	None
;
DEFPROC	hwPow2
	fld	st(0)			; ST(0) = t, ST(1) = t
	fldcw	cs:[hwCWDown]
	frndint				; ST(0) = i
	fldcw	cs:[hwCWNear]
	fxch				; ST(0) = t, ST(1) = i
	fsub	st,st(1)		; ST(0) = f
	fmul	cs:[hwHalf]		; ST(0) = f/2
	f2xm1				; ST(0) = 2^(f/2) - 1
	fld1
	fadd				; ST(0) = 2^(f/2)
	fmul	st,st(0)		; ST(0) = 2^f
	fscale				; ST(0) = 2^f * 2^i
	fstp	st(1)			; ST(0) = 2^t
	ret
ENDPROC	hwPow2

	DEFLBL	hwEnd

HWCODE	ends

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Software (FPU emulation) functions
;
; TODO: Other than swNeg and swAbs, these are all stubs that simply adjust
; the stack and return zeros (or, in the case of swAtoD, an error).
;
SWCODE	segment para public 'CODE'

        ASSUME	CS:SWCODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

	DEFLBL	swTable,word
	dw	swNeg, swExp, swMul, swDiv, swAdd, swSub
	dw	swEQ,  swNE,  swLT,  swGT,  swLE,  swGE
	dw	swCvt1DL, swCvt2DL, swCvtL1D, swCvtL2D, swCvtD1L, swCvtD2L
	dw	swCvt1LD, swCvt2LD
	dw	swAbs, swInt, swFix, swSqr, swAtoD, swDtoA
	dw	swToDec, swFromDec
	IF	($ - swTable) NE size FPUTBL
	ERROR	<swTable does not match FPUTBL>
	ENDIF
	DEFPTR	swComAtoD		; comAtoD (set by ddfpu_init)
	DEFPTR	swComDtoA		; comDtoA (set by ddfpu_init)
	IF	(swComAtoD - swTable) NE (hwComAtoD - hwTable)
	ERROR	<swTable and hwTable layouts differ>
	ENDIF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swNeg
;
; Inputs:
;	1 64-bit double on stack
;
; Outputs:
;	1 64-bit double on stack (negated)
;
; Modifies:
;	BX
;
DEFPROC	swNeg,FAR
	mov	bx,sp
	xor	byte ptr ss:[bx+11],80h
	ret
ENDPROC	swNeg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swAbs
;
; Inputs:
;	1 64-bit double on stack
;
; Outputs:
;	1 64-bit double on stack (absolute value)
;
; Modifies:
;	BX
;
DEFPROC	swAbs,FAR
	mov	bx,sp
	and	byte ptr ss:[bx+11],7Fh
	ret
ENDPROC	swAbs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Stack function stubs
;
; Each stub loads BL with the (signed) number of bytes to pop and BH with
; the number of result bytes to zero, signals an assertion failure (in DEBUG
; builds), and then jumps to swStub.
;
; Inputs:
;	Varies
;
; Outputs:
;	Varies
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFSTUB	macro	name,npop,nzero,fn
	DEFLBL	name,near
	mov	bx,(nzero SHL 8) OR (npop AND 0FFh)
	IFDEF	DEBUG
	ASSERT	FALSE,,,<"FPE &fn not implemented">
	jmp	swStub
	ELSE
	jmp	short swStub
	ENDIF
	endm

DEFPROC	swStubs,FAR
	DEFSTUB	swExp,8,8,EXP
	DEFSTUB	swMul,8,8,MUL
	DEFSTUB	swDiv,8,8,DIV
	DEFSTUB	swAdd,8,8,ADD
	DEFSTUB	swSub,8,8,SUB
	DEFSTUB	swEQ,12,4,EQ
	DEFSTUB	swNE,12,4,NE
	DEFSTUB	swLT,12,4,LT
	DEFSTUB	swGT,12,4,GT
	DEFSTUB	swLE,12,4,LE
	DEFSTUB	swGE,12,4,GE
	DEFSTUB	swCvt1DL,4,4,CVT1DL
	DEFSTUB	swCvt2DL,8,8,CVT2DL
	DEFSTUB	swCvtL1D,-4,8,CVTL1D
	DEFSTUB	swCvtL2D,-4,16,CVTL2D
	DEFSTUB	swCvtD1L,4,4,CVTD1L
	DEFSTUB	swCvtD2L,4,8,CVTD2L
	DEFSTUB	swCvt1LD,-4,8,CVT1LD
	DEFSTUB	swCvt2LD,-8,16,CVT2LD
	DEFSTUB	swInt,0,0,INT
	DEFSTUB	swFix,0,0,FIX
	DEFLBL	swSqr,near
	sub	bx,bx
	ASSERT	FALSE,,,<"FPE SQR not implemented">
swStub:	pop	cx
	pop	dx			; DX:CX = return address
	mov	al,bl
	cbw
	add	sp,ax			; pop (or push) the specified # bytes
	push	dx
	push	cx
	mov	di,sp
	add	di,4
	push	ss
	pop	es			; ES:DI -> result
	mov	cl,bh
	mov	ch,0
	mov	al,0
	rep	stosb			; zero the specified # bytes
	ret
ENDPROC	swStubs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swAtoD, swDtoA
;
; These simply jump to the shared code (see comAtoD and comDtoA).
;
DEFPROC	swAtoD,FAR
	jmp	cs:[swComAtoD]
	DEFLBL	swDtoA,near
	jmp	cs:[swComDtoA]
ENDPROC	swAtoD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swToDec (stub), swFromDec (stub)
;
; swToDec returns no digits (as if the value is zero), and swFromDec returns
; carry set (as if the value is out of range).
;
DEFPROC	swToDec,FAR
	ASSERT	FALSE,,,<"FPE TODEC not implemented">
	sub	ax,ax
	sub	cx,cx
	ret
	DEFLBL	swFromDec,near
	ASSERT	FALSE,,,<"FPE FROMDEC not implemented">
	stc
	ret
ENDPROC	swToDec

	DEFLBL	swEnd

SWCODE	ends

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; If an 8087 is present, we keep the HWCODE functions and discard everything
; from SWCODE onward; otherwise, we move the SWCODE functions down on top of
; the HWCODE functions and discard everything after that.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
; Modifies:
;	AX, CX, DX, SI, DI, BP, DS
;
INIT	segment para public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	ddfpu_init,far
	mov	cs:[0].DDH_REQUEST,offset DEV:ddfpu_req
;
; Detect the 8087: after FNINIT, the low byte of its status word must be
; zero and its control word must contain the FNINIT default bits (if there's
; no 8087, then FNSTSW and FNSTCW should not modify our test word at all).
;
	mov	ax,-1
	push	ax
	mov	bp,sp			; SS:BP -> test word
	fninit
	fnstsw	word ptr [bp]
	mov	dx,FPUTYPE_NONE SHL 8
	cmp	byte ptr [bp],0
	jne	ddi1
	fnstcw	word ptr [bp]
	mov	ax,[bp]
	and	ax,103Fh
	cmp	ax,003Fh
	jne	ddi1
	mov	dh,FPUTYPE_8087
ddi1:	pop	ax
	mov	dl,(size FPUTBL) SHR 1
	mov	cs:[fpuInfo],dx

	mov	di,offset DEV:hwTable
	mov	ax,di
	mov	cl,4
	shr	ax,cl
	mov	si,cs
	add	ax,si
	mov	cs:[fpuSeg],ax		; FPUTBL is at fpuSeg:0

	mov	ax,offset DEV:swTable	; AX = end of HWCODE
	test	dh,dh			; 8087 present?
	jnz	ddi9			; yes
	push	es
	push	cs
	pop	ds
	push	cs
	pop	es
	mov	si,ax			; DS:SI -> SWCODE
	mov	cx,((offset swEnd - offset swTable) + 1) SHR 1
	rep	movsw			; move SWCODE down to HWCODE
	pop	es
	xchg	ax,di			; AX = end of moved SWCODE
ddi9:	mov	es:[bx].DDPI_END.OFF,ax
;
; Fill in the far pointers that follow the retained FPUTBL, so that its
; FPU_ATOD and FPU_DTOA functions can reach the shared code, and the far
; pointers that the shared code uses to reach FPU_TODEC and FPU_FROMDEC.
;
	mov	si,offset DEV:hwComAtoD
	mov	word ptr cs:[si],offset DEV:comAtoD
	mov	cs:[si+2],cs
	mov	word ptr cs:[si+4],offset DEV:comDtoA
	mov	cs:[si+6],cs
	mov	ax,cs:[fpuSeg]
	mov	cs:[fpuToDec].SEG,ax
	mov	cs:[fpuFromDec].SEG,ax
	mov	ax,word ptr cs:[hwTable+FPU_TODEC]
	mov	cs:[fpuToDec].OFF,ax
	mov	ax,word ptr cs:[hwTable+FPU_FROMDEC]
	mov	cs:[fpuFromDec].OFF,ax
;
; For now, we also display whether or not an 8087 was detected.
;
	push	bx
	push	cs
	pop	ds
	ASSUME	DS:DEV
	mov	si,offset DEV:msgNoFPU
	cmp	byte ptr [fpuInfo+1],FPUTYPE_NONE
	je	ddi10
	add	si,3			; skip "No " for the 8087 message
ddi10:	lodsb
	test	al,al
	jz	ddi19
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	jmp	ddi10
ddi19:	pop	bx
	ret
ENDPROC	ddfpu_init

msgNoFPU	db	"No 8087 detected",13,10,0

INIT	ends

DATA	segment para public 'DATA'

ddfpu_end	db	16 dup(0)

DATA	ends

	end
