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
; hwNeg, hwAbs
;
; No FPU is required to flip or clear the sign bit, so we simply copy the
; double to ES:DI and modify the copy.
;
; Inputs:
;	1 double on stack
;	ES:DI -> result
;
; Outputs:
;	1 double on stack (negated, or absolute value)
;
; Modifies:
;	BX, CX, SI
;
DEFPROC	hwNeg,FAR
	call	hwCopyT
	xor	byte ptr es:[di+7],80h
	ret
	DEFLBL	hwAbs,near
	call	hwCopyT
	and	byte ptr es:[di+7],7Fh
	ret
ENDPROC	hwNeg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwCopyT
;
; Copies the top double on the stack to ES:DI, and replaces it with ES:DI.
;
; Inputs:
;	1 double on stack, followed by FAR and NEAR return addresses
;	ES:DI -> result
;
; Outputs:
;	ES:DI -> result
;
; Modifies:
;	BX, CX, SI
;
DEFPROC	hwCopyT
	mov	bx,sp
	push	ds
	lds	si,ss:[bx+6]		; DS:SI -> double
	mov	ss:[bx+6],di		; and replace it with ES:DI
	mov	ss:[bx+8],es
	mov	cx,4
	rep	movsw
	sub	di,8
	pop	ds
	ret
ENDPROC	hwCopyT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwMul, hwDiv, hwAdd, hwSub
;
; Inputs:
;	2 doubles on stack (A, then B on top)
;	ES:DI -> result
;
; Outputs:
;	1 double on stack (A*B, A/B, A+B, or A-B)
;
; Modifies:
;	AX, BX, SI
;
DEFPROC	hwMul,FAR
	call	hwLoad2			; ST(0) = A, ST(1) = B
	fmulp	st(1),st		; ST(0) = A * B
	jmp	short hwStore2
	DEFLBL	hwDiv,near
	call	hwLoad2
	fdivrp	st(1),st		; ST(0) = A / B
	jmp	short hwStore2
	DEFLBL	hwAdd,near
	call	hwLoad2
	faddp	st(1),st		; ST(0) = A + B
	jmp	short hwStore2
	DEFLBL	hwSub,near
	call	hwLoad2
	fsubrp	st(1),st		; ST(0) = A - B
	DEFLBL	hwStore2,near
	fstp	qword ptr es:[di]	; store ST(0) at ES:DI
	call	hwDone
	mov	ss:[bx+8],di		; replace A with ES:DI
	mov	ss:[bx+10],es
	ret	4			; and pop B
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
;	2 doubles on stack (A, then B on top)
;	ES:DI -> result
;
; Outputs:
;	1 double on stack (A^B)
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	hwExp,FAR
	call	hwLoad2			; ST(0) = A, ST(1) = B
	fxch				; ST(0) = B, ST(1) = A
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
he9:	jmp	hwStore2
ENDPROC	hwExp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwEQ, hwNE, hwLT, hwGT, hwLE, hwGE
;
; Each entry point loads CL with a mask of the comparison outcomes that make
; the relation true: 4 (A < B), 2 (A = B), and 1 (A > B).
;
; Inputs:
;	2 doubles on stack (A, then B on top)
;
; Outputs:
;	1 32-bit long on stack (-1 if true, 0 if false)
;
; Modifies:
;	AX, BX, CX, SI
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
hwCmp:	call	hwLoad2			; ST(0) = A, ST(1) = B
	fcompp				; compare A to B and pop both
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
	mov	ss:[bx+8],ax		; the result replaces A
	mov	ss:[bx+10],ax
	ret	4			; and B is popped
ENDPROC	hwEQ

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwCvtDL (FPU_CVT1DL and FPU_CVTD1L), hwCvtD2L (FPU_CVTD2L)
;
; Converts the top double (or for FPU_CVTD2L, the double underneath the long
; on top) to a long, rounding to the nearest integer (with ties rounded away
; from zero, like MSBASIC; see hwRound).
;
; Inputs:
;	1 double on stack (or 1 double and 1 long, with the long on top)
;
; Outputs:
;	1 32-bit long on stack (or 2 longs)
;
; Modifies:
;	AX, BX, SI
;
DEFPROC	hwCvtDL,FAR
	call	hwLoadT			; ST(0) = top double
	call	hwRound
	fistp	dword ptr ss:[bx+4]	; replace the top double with a long
	jmp	short hwCvtDone
	DEFLBL	hwCvtD2L,near
	call	hwLoadA			; ST(0) = double under the long
	call	hwRound
	fistp	dword ptr ss:[bx+8]	; replace that double with a long
	DEFLBL	hwCvtDone,near
	call	hwDone
	ret
ENDPROC	hwCvtDL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwCvt2DL (FPU_CVT2DL)
;
; Same as hwCvtDL, but for both doubles.
;
; Inputs:
;	2 doubles on stack (A, then B on top)
;
; Outputs:
;	2 32-bit longs on stack (A, then B on top)
;
; Modifies:
;	AX, BX, SI
;
DEFPROC	hwCvt2DL,FAR
	call	hwLoad2			; ST(0) = A, ST(1) = B
	call	hwRound
	fistp	dword ptr ss:[bx+8]
	call	hwRound			; ST(0) = B
	fistp	dword ptr ss:[bx+4]
	jmp	hwCvtDone
ENDPROC	hwCvt2DL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwRound
;
; Rounds ST(0) to the nearest integer, with ties rounded away from zero (eg,
; 2.5 becomes 3 and -2.5 becomes -3), which is what MSBASIC does when it
; converts a floating-point value to an integer.
;
; Simply adding 0.5 and truncating isn't exact (eg, 0.49999999999999994 + 0.5
; rounds to 1), so we truncate x to t, and since x - t is always exact, we can
; check whether |x - t| >= 0.5, in which case t is moved one away from zero.
;
; Inputs:
;	ST(0) = x
;
; Outputs:
;	ST(0) = x rounded
;
; Modifies:
;	AX
;
DEFPROC	hwRound
	fld	st(0)			; ST(0) = x, ST(1) = x
	fldcw	cs:[hwCWChop]
	frndint				; ST(0) = t (x truncated)
	fldcw	cs:[hwCWNear]
	fsub	st(1),st		; ST(0) = t, ST(1) = f (x - t)
	fld	st(1)
	fabs				; ST(0) = |f|, ST(1) = t, ST(2) = f
	fcomp	cs:[hwHalf]		; compare |f| to 0.5 and pop
	call	hwStat
	jb	hr8			; |f| < 0.5, so t is the answer
	fxch				; ST(0) = f, ST(1) = t
	ftst
	call	hwStat			; carry set if f < 0
	fstp	st(0)			; ST(0) = t
	fld1
	jae	hr1
	fchs				; ST(0) = -1
hr1:	faddp	st(1),st		; ST(0) = t + 1 (or t - 1)
	ret
hr8:	fstp	st(1)			; ST(0) = t
	ret
ENDPROC	hwRound

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwCvtLD (FPU_CVTL1D and FPU_CVT1LD), hwCvtL2D (FPU_CVTL2D)
;
; Converts the long on top of the stack (or for FPU_CVTL2D, the long underneath
; the double on top) to a double at ES:DI, and replaces the long with ES:DI.
;
; Inputs:
;	1 32-bit long on stack (or 1 long and 1 double, with the double on top)
;	ES:DI -> result
;
; Outputs:
;	1 double on stack (or 2 doubles)
;
; Modifies:
;	AX, BX
;
DEFPROC	hwCvtLD,FAR
	mov	bx,4
	jmp	short hwCvtL
	DEFLBL	hwCvtL2D,near
	mov	bx,8
hwCvtL:	add	bx,sp			; SS:BX -> long
	cli
	fild	dword ptr ss:[bx]
	fstp	qword ptr es:[di]
	call	hwDone
	mov	ss:[bx],di		; replace the long with ES:DI
	mov	ss:[bx+2],es
	ret
ENDPROC	hwCvtLD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwCvt2LD (FPU_CVT2LD)
;
; Inputs:
;	2 32-bit longs on stack (A, then B on top)
;	ES:DI -> results (A at ES:DI and B at ES:DI+8)
;
; Outputs:
;	2 doubles on stack (A, then B on top)
;
; Modifies:
;	AX, BX
;
DEFPROC	hwCvt2LD,FAR
	mov	bx,sp
	cli
	fild	dword ptr ss:[bx+8]	; ST(0) = A
	fstp	qword ptr es:[di]
	fild	dword ptr ss:[bx+4]	; ST(0) = B
	fstp	qword ptr es:[di+8]
	call	hwDone
	mov	ss:[bx+8],di		; replace A with ES:DI
	mov	ss:[bx+10],es
	lea	ax,[di+8]
	mov	ss:[bx+4],ax		; and B with ES:DI+8
	mov	ss:[bx+6],es
	ret
ENDPROC	hwCvt2LD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwInt, hwFix, hwSqr
;
; Inputs:
;	1 double on stack
;	ES:DI -> result
;
; Outputs:
;	1 double on stack (INT, FIX, or SQR of the input)
;
; Modifies:
;	AX, BX, SI
;
DEFPROC	hwInt,FAR
	mov	ax,offset hwCWDown	; INT rounds down
	jmp	short hwRnd
	DEFLBL	hwFix,near
	mov	ax,offset hwCWChop	; FIX rounds toward zero
hwRnd:	call	hwLoadT			; ST(0) = top double
	xchg	si,ax
	fldcw	word ptr cs:[si]
	frndint
	fldcw	cs:[hwCWNear]
	jmp	short hwStoreT
	DEFLBL	hwSqr,near
	call	hwLoadT
	fsqrt
	DEFLBL	hwStoreT,near
	fstp	qword ptr es:[di]	; store ST(0) at ES:DI
	call	hwDone
	mov	ss:[bx+4],di		; and replace the top double with ES:DI
	mov	ss:[bx+6],es
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
; hwLoad2, hwLoadA, hwLoadT
;
; Disables interrupts and loads doubles (by way of the far pointers on the
; stack): hwLoad2 loads both doubles (B, and then A), hwLoadA loads only the
; 2nd (deeper) entry (A), and hwLoadT loads only the top entry.
;
; Inputs:
;	2 stack entries (or 1 for hwLoadT), followed by FAR and NEAR return
;	addresses
;
; Outputs:
;	ST(0) = A (or the top double), ST(1) = B (for hwLoad2)
;	BX -> FAR return address (so A is at SS:[BX+8] and B at SS:[BX+4])
;
; Modifies:
;	BX, SI
;
DEFPROC	hwLoad2
	mov	bx,sp
	push	ds
	cli
	lds	si,ss:[bx+6]		; DS:SI -> B
	fld	qword ptr [si]
	jmp	short hwLdA
	DEFLBL	hwLoadA,near
	mov	bx,sp
	push	ds
	cli
hwLdA:	lds	si,ss:[bx+10]		; DS:SI -> A
	jmp	short hwLd
	DEFLBL	hwLoadT,near
	mov	bx,sp
	push	ds
	cli
	lds	si,ss:[bx+6]		; DS:SI -> top double
hwLd:	fld	qword ptr [si]
	pop	ds
	inc	bx
	inc	bx
	ret
ENDPROC	hwLoad2

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
; These implement the same functions (and conventions) as the HWCODE functions,
; using an internal "unpacked extended" (UX) format with a 64-bit mantissa, the
; same precision that the 8087 uses internally.  Results are rounded to the
; nearest double (ties to even) when they're stored, and exceptions (divide by
; zero, overflow, and invalid operations) are signaled the same way hwDone
; signals them.
;
; Each function allocates a frame (see SX_SIZE) containing several UX values
; and work buffers, all addressed relative to BP (and therefore SS), so the
; functions don't rely on any static data and can safely be used by multiple
; sessions at once.  The internal functions (xLoad, xAdd, etc) take the
; frame offsets of their UX operands in SI and DI.
;
; TODO: FPU_EXP supports only integer exponents (from -32768 to 32767); any
; other exponent signals an invalid operation (unless the base is zero).
;
UX	struc
UX_M0	dw	?		; mantissa (UX_M3 bit 15 is set if non-zero)
UX_M1	dw	?
UX_M2	dw	?
UX_M3	dw	?
UX_EXP	dw	?		; exponent (value is 1.xxx * 2^UX_EXP)
UX_SGN	db	?		; 80h if negative
UX_CLS	db	?		; class (UXC_*)
UX	ends

UXC_FIN	equ	0		; finite (zero if UX_M3 is zero)
UXC_INF	equ	1		; infinity
UXC_NAN	equ	2		; NaN

XF_ZE	equ	01h		; divide by zero
XF_OE	equ	02h		; overflow
XF_IE	equ	04h		; invalid operation

SX_A	equ	-12		; UX A (1st operand and result)
SX_B	equ	-24		; UX B (2nd operand, or temp)
SX_C	equ	-36		; UX C (temp)
SX_D	equ	-48		; UX D (temp)
SX_P	equ	-64		; 16-byte product/remainder buffer
SX_MA	equ	-72		; 8-byte mantissa (or quotient) buffer
SX_MB	equ	-80		; 8-byte mantissa (or divisor) buffer
SX_FL	equ	-82		; XF_* flags (and relation mask in high byte)
SX_N	equ	-84		; misc word (eg, # digits or operation)
SX_E	equ	-86		; misc word (eg, decimal exponent)
SX_DST	equ	-90		; caller's ES:DI
SX_SIZE	equ	90

SWENTER	macro
	push	bp
	mov	bp,sp
	sub	sp,SX_SIZE
	mov	[bp+SX_DST].OFF,di
	mov	[bp+SX_DST].SEG,es
	mov	word ptr [bp+SX_FL],0
	endm

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
; swNeg, swAbs
;
; Same as hwNeg and hwAbs (which are inaccessible after ddfpu_init moves
; SWCODE on top of HWCODE).
;
; Inputs:
;	1 double on stack
;	ES:DI -> result
;
; Outputs:
;	1 double on stack (negated, or absolute value)
;
; Modifies:
;	BX, CX, SI
;
DEFPROC	swNeg,FAR
	call	swCopyT
	xor	byte ptr es:[di+7],80h
	ret
	DEFLBL	swAbs,near
	call	swCopyT
	and	byte ptr es:[di+7],7Fh
	ret
ENDPROC	swNeg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swCopyT
;
; Same as hwCopyT.
;
DEFPROC	swCopyT
	mov	bx,sp
	push	ds
	lds	si,ss:[bx+6]		; DS:SI -> double
	mov	ss:[bx+6],di		; and replace it with ES:DI
	mov	ss:[bx+8],es
	mov	cx,4
	rep	movsw
	sub	di,8
	pop	ds
	ret
ENDPROC	swCopyT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Stack functions
;
; See the corresponding HWCODE functions for inputs and outputs.  All of them
; may modify AX, BX, CX, DX, SI, DI, and ES.
;
DEFPROC	swFuncs,FAR
;
; swMul, swDiv, swAdd, swSub (2 doubles -> 1 double at ES:DI)
;
	DEFLBL	swMul,near
	mov	al,0
	jmp	short swArith
	DEFLBL	swDiv,near
	mov	al,1
	jmp	short swArith
	DEFLBL	swAdd,near
	mov	al,2
	jmp	short swArith
	DEFLBL	swSub,near
	mov	al,3
swArith:
	SWENTER
	mov	byte ptr [bp+SX_N],al
	call	swLoad2
	mov	al,byte ptr [bp+SX_N]
	cmp	al,1
	jb	sar1
	je	sar2
	cmp	al,3
	jne	sar3
	xor	[bp+SX_B].UX_SGN,80h	; A-B is A+(-B)
sar3:	call	xAdd
	jmp	short swStoreA4
sar1:	call	xMul
	jmp	short swStoreA4
sar2:	call	xDiv
;
; Store A (the result) at ES:DI, replace A with ES:DI, and pop B.
;
swStoreA4:
	les	di,[bp+SX_DST]
	mov	si,SX_A
	call	xStore
	mov	[bp+10],di
	mov	[bp+12],es
	DEFLBL	swExit4,near
	call	swRaise
	mov	sp,bp
	pop	bp
	ret	4
;
; swExp (2 doubles -> 1 double at ES:DI)
;
	DEFLBL	swExp,near
	SWENTER
	call	swLoad2
	mov	al,[bp+SX_A].UX_CLS
	or	al,[bp+SX_B].UX_CLS
	test	al,UXC_NAN		; either operand NaN?
	jz	sxp1			; no
	mov	[bp+SX_A].UX_CLS,UXC_NAN
	jmp	swStoreA4
sxp1:	cmp	[bp+SX_B].UX_CLS,UXC_FIN
	jne	sxp7			; B is infinite
	mov	si,SX_C
	mov	di,SX_B
	call	xCopy
	mov	al,3
	call	xRndInt			; C = B truncated
	call	xCmpMag
	test	al,al			; is B an integer?
	jnz	sxp7			; no
	cmp	[bp+SX_C].UX_M3,0
	je	sxp2			; B is zero
	cmp	[bp+SX_C].UX_EXP,14
	jg	sxp7			; B is too large
sxp2:	call	xToLong			; AX = n
	push	ax
	mov	bx,ax
	test	bx,bx
	jns	sxp3
	neg	bx			; BX = abs(n)
sxp3:	mov	si,SX_D
	mov	di,SX_A
	call	xCopy			; D = A
	mov	si,SX_C
	mov	di,SX_D
	call	xPowInt			; C = A^abs(n)
	pop	ax
	mov	si,SX_A
	mov	di,SX_C
	test	ax,ax
	js	sxp4
	call	xCopy			; A = A^n
	jmp	swStoreA4
sxp4:	mov	ax,1
	cwd
	call	xFromLong
	call	xDiv			; A = 1 / A^abs(n)
	jmp	swStoreA4
sxp7:	mov	si,SX_A
	call	xIsZero			; zero raised to any power is zero
	jz	sxp9
	ASSERT	FALSE,,,<"FPE EXP of non-integer not implemented">
	call	xInvalid
sxp9:	jmp	swStoreA4
;
; swEQ, swNE, swLT, swGT, swLE, swGE (2 doubles -> 1 long)
;
; As with hwCmp, CL is a mask of the outcomes that make the relation true:
; 4 (A < B), 2 (A = B), and 1 (A > B).
;
	DEFLBL	swEQ,near
	mov	cl,2
	jmp	short swCmp
	DEFLBL	swNE,near
	mov	cl,4+1
	jmp	short swCmp
	DEFLBL	swLT,near
	mov	cl,4
	jmp	short swCmp
	DEFLBL	swGT,near
	mov	cl,1
	jmp	short swCmp
	DEFLBL	swLE,near
	mov	cl,4+2
	jmp	short swCmp
	DEFLBL	swGE,near
	mov	cl,2+1
swCmp:
	SWENTER
	mov	byte ptr [bp+SX_FL+1],cl
	call	swLoad2
	mov	al,[bp+SX_A].UX_CLS
	or	al,[bp+SX_B].UX_CLS
	test	al,UXC_NAN		; either operand NaN?
	jz	scp1			; no
	or	byte ptr [bp+SX_FL],XF_IE
	jmp	short scp4		; treat as equal (like the 8087)
scp1:	call	xIsZero
	jnz	scp2
	xchg	si,di
	call	xIsZero
	jz	scp4			; both zero, so they're equal
	xchg	si,di
scp2:	mov	al,[bp+SX_A].UX_SGN
	cmp	al,[bp+SX_B].UX_SGN
	je	scp3
	mov	al,4			; signs differ, so A < B if A is negative
	test	byte ptr [bp+SX_A].UX_SGN,80h
	jnz	scp8
	mov	al,1
	jmp	short scp8
scp3:	call	xCmpMag			; AL = -1, 0, or 1 (|A| vs |B|)
	test	byte ptr [bp+SX_A].UX_SGN,80h
	jz	scp3a
	neg	al
scp3a:	test	al,al
	jz	scp4
	mov	al,1
	jg	scp8
	mov	al,4
	jmp	short scp8
scp4:	mov	al,2
scp8:	and	al,byte ptr [bp+SX_FL+1]; is the relation true?
	neg	al			; carry set if so
	sbb	ax,ax			; AX = -1 if true, 0 if false
	mov	[bp+10],ax		; the result replaces A
	mov	[bp+12],ax
	jmp	swExit4			; and B is popped
;
; swCvt1DL and swCvtD1L (top double -> long), swCvtD2L (next double -> long),
; and swCvt2DL (both doubles -> longs)
;
	DEFLBL	swCvt1DL,near
	DEFLBL	swCvtD1L,near
	mov	ax,6
	jmp	short swCvtDL
	DEFLBL	swCvtD2L,near
	mov	ax,10
swCvtDL:
	SWENTER
	mov	[bp+SX_N],ax
	call	swDL
	jmp	swExit0
	DEFLBL	swCvt2DL,near
	SWENTER
	mov	word ptr [bp+SX_N],10
	call	swDL
	mov	word ptr [bp+SX_N],6
	call	swDL
	jmp	swExit0
;
; swCvtL1D and swCvt1LD (top long -> double), swCvtL2D (next long -> double),
; and swCvt2LD (both longs -> doubles at ES:DI and ES:DI+8)
;
	DEFLBL	swCvtL1D,near
	DEFLBL	swCvt1LD,near
	mov	ax,6
	jmp	short swCvtLD
	DEFLBL	swCvtL2D,near
	mov	ax,10
swCvtLD:
	SWENTER
	mov	[bp+SX_N],ax
	mov	word ptr [bp+SX_E],0
	call	swLD
	jmp	swExit0
	DEFLBL	swCvt2LD,near
	SWENTER
	mov	word ptr [bp+SX_N],10
	mov	word ptr [bp+SX_E],0
	call	swLD
	mov	word ptr [bp+SX_N],6
	mov	word ptr [bp+SX_E],8
	call	swLD
	jmp	swExit0
;
; swInt, swFix, swSqr (1 double -> 1 double at ES:DI)
;
	DEFLBL	swInt,near
	mov	al,2			; INT rounds down
	jmp	short swRnd
	DEFLBL	swFix,near
	mov	al,3			; FIX rounds toward zero
swRnd:
	SWENTER
	mov	byte ptr [bp+SX_N],al
	call	swLoadT
	mov	al,byte ptr [bp+SX_N]
	call	xRndInt
	jmp	short swStoreT
	DEFLBL	swSqr,near
	SWENTER
	call	swLoadT
	call	xSqrt
swStoreT:
	les	di,[bp+SX_DST]
	mov	si,SX_A
	call	xStore
	mov	[bp+6],di		; replace the top double with ES:DI
	mov	[bp+8],es
	DEFLBL	swExit0,near
	call	swRaise
	mov	sp,bp
	pop	bp
	ret
ENDPROC	swFuncs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swLoad2, swLoadT
;
; swLoad2 loads both doubles on the stack (A into SX_A and B into SX_B), and
; swLoadT loads the top double into SX_A.
;
; Outputs:
;	SI = SX_A, DI = SX_B
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	swLoad2
	les	bx,[bp+6]
	mov	si,SX_B
	call	xLoad
	les	bx,[bp+10]
	jmp	short swLdA
	DEFLBL	swLoadT,near
	les	bx,[bp+6]
swLdA:	mov	si,SX_A
	call	xLoad
	mov	di,SX_B
	ret
ENDPROC	swLoad2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swDL
;
; Converts the double at [BP+SX_N] (on the stack) to a long, rounding to the
; nearest integer (with ties rounded away from zero, like hwRound).
;
; Modifies:
;	AX, BX, CX, DX, SI, ES
;
DEFPROC	swDL
	mov	si,[bp+SX_N]
	les	bx,[bp+si]
	mov	si,SX_A
	call	xLoad
	mov	al,1
	call	xToLong
	mov	si,[bp+SX_N]
	mov	[bp+si],ax
	mov	[bp+si+2],dx
	ret
ENDPROC	swDL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swLD
;
; Converts the long at [BP+SX_N] (on the stack) to a double at ES:DI+SX_E,
; and replaces the long with that address.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	swLD
	mov	si,[bp+SX_N]
	mov	ax,[bp+si]
	mov	dx,[bp+si+2]
	mov	si,SX_A
	call	xFromLong
	les	di,[bp+SX_DST]
	add	di,[bp+SX_E]
	call	xStore
	mov	si,[bp+SX_N]
	mov	[bp+si],di
	mov	[bp+si+2],es
	ret
ENDPROC	swLD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swRaise
;
; Signals any exceptions recorded in the frame's flags, the same way hwDone
; does: a divide error for XF_ZE, and an overflow error for XF_OE or XF_IE.
;
; Modifies:
;	AX
;
DEFPROC	swRaise
	mov	al,[bp+SX_FL]
	test	al,XF_ZE
	jz	srs1
	int	INT_DV
	ret
srs1:	test	al,XF_OE OR XF_IE
	jz	srs9
	int	INT_OF
srs9:	ret
ENDPROC	swRaise

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swToDec (FPU_TODEC)
;
; Same as hwToDec: we determine the decimal exponent (e) of the absolute value
; (x), scale x by 10^(N-1-e) so that it's an integer from 10^(N-1) to 10^N - 1,
; and convert that to N digits.  When N is zero, the value is rounded to either
; 0 or 1 (in which case, we return 1 digit for e+1).
;
; We estimate e from the binary exponent (as floor(exp * log10(2)), where
; 19728/65536 approximates log10(2)), and then adjust it until the scaled value
; is in range.
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
DEFPROC	swToDec,FAR
	push	bp
	mov	bp,sp
	sub	sp,SX_SIZE
	push	si
	push	di
	push	es
	mov	[bp+SX_DST].OFF,di
	mov	[bp+SX_DST].SEG,es
	mov	ch,0
	mov	[bp+SX_N],cx
	push	ds
	pop	es
	mov	bx,si			; ES:BX -> double
	mov	si,SX_D
	call	xLoad			; D = x
	mov	[bp+SX_D].UX_SGN,0
	sub	ax,ax
	sub	cx,cx
	cmp	[bp+SX_D].UX_M3,ax
	jne	std1
	jmp	std9			; x is zero
std1:	mov	ax,[bp+SX_D].UX_EXP
	mov	dx,19728
	imul	dx
	mov	[bp+SX_E],dx		; e = floor(exp * log10(2))
;
; Scale A = x * 10^(M-1-e), where M = max(N,1), and make sure that A is from
; 10^(M-1) to 10^M (exclusive), adjusting e if not.
;
std2:	mov	si,SX_A
	mov	di,SX_D
	call	xCopy			; A = x
	mov	ax,[bp+SX_N]
	test	ax,ax
	jnz	std3
	inc	ax
std3:	dec	ax			; AX = M-1
	push	ax
	sub	ax,[bp+SX_E]
	call	xScale10		; A = x * 10^(M-1-e)
	pop	bx
	mov	si,SX_B
	mov	ax,10
	cwd
	call	xFromLong
	mov	si,SX_C
	mov	di,SX_B
	call	xPowInt			; C = 10^(M-1)
	mov	si,SX_A
	mov	di,SX_C
	call	xCmpMag
	test	al,al
	jge	std4
	dec	word ptr [bp+SX_E]	; A is too small
	jmp	std2
std4:	mov	si,SX_B
	mov	ax,10
	cwd
	call	xFromLong
	mov	di,SX_C
	call	xMul			; B = 10^M
	mov	si,SX_A
	mov	di,SX_B
	call	xCmpMag
	test	al,al
	jl	std5
	inc	word ptr [bp+SX_E]	; A is too large
	jmp	std2
std5:	cmp	word ptr [bp+SX_N],0
	jne	std6
;
; When N is zero, A is from 1 to 10, so the result is 1 if A > 5 (ties are
; rounded to even, so 5 rounds to 0), and nothing otherwise.
;
	mov	si,SX_B
	mov	ax,5
	cwd
	call	xFromLong
	mov	si,SX_A
	call	xCmpMag
	mov	bl,al
	sub	cx,cx
	mov	ax,[bp+SX_E]
	test	bl,bl
	jle	std9
	inc	ax
	inc	cx
	les	di,[bp+SX_DST]
	mov	byte ptr es:[di],'1'
	jmp	short std9
;
; Round A to an integer (ties to even) and convert it to N digits.
;
std6:	sub	al,al
	call	xRndInt
	mov	cx,63
	sub	cx,[bp+SX_A].UX_EXP
	call	xShrN			; A's mantissa = the integer
	les	di,[bp+SX_DST]
	mov	cx,[bp+SX_N]
	add	di,cx
	mov	bx,10
std7:	dec	di
	sub	dx,dx
	mov	ax,[bp+SX_A].UX_M3
	div	bx
	mov	[bp+SX_A].UX_M3,ax
	mov	ax,[bp+SX_A].UX_M2
	div	bx
	mov	[bp+SX_A].UX_M2,ax
	mov	ax,[bp+SX_A].UX_M1
	div	bx
	mov	[bp+SX_A].UX_M1,ax
	mov	ax,[bp+SX_A].UX_M0
	div	bx
	mov	[bp+SX_A].UX_M0,ax
	add	dl,'0'
	mov	es:[di],dl
	loop	std7
;
; If anything remains, then A was rounded up to 10^N, so the digits must be
; "1" followed by zeros, at the next higher decimal exponent.
;
	or	ax,[bp+SX_A].UX_M1
	or	ax,[bp+SX_A].UX_M2
	or	ax,[bp+SX_A].UX_M3
	jz	std8
	inc	word ptr [bp+SX_E]
	mov	cx,[bp+SX_N]
	mov	al,'0'
	push	di
	rep	stosb
	pop	di
	mov	byte ptr es:[di],'1'
std8:	mov	cx,[bp+SX_N]
	mov	ax,[bp+SX_E]
std9:	pop	es
	pop	di
	pop	si
	mov	sp,bp
	pop	bp
	ret
ENDPROC	swToDec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swFromDec (FPU_FROMDEC)
;
; The digits (up to 19) are accumulated as a 64-bit integer, which is exact,
; and then scaled by the specified power of ten.
;
; Inputs:
;	DS:SI -> digits (up to 19)
;	CX = # of digits
;	AX = decimal exponent (the value is digits * 10^AX)
;	BL = 80h if negative (only bit 7 is significant)
;	ES:DI -> double
;
; Outputs:
;	Carry set if out of range
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	swFromDec,FAR
	push	bp
	mov	bp,sp
	sub	sp,SX_SIZE
	push	bx
	push	di
	mov	word ptr [bp+SX_FL],0
	mov	[bp+SX_E],ax
	mov	[bp+SX_N],cx
	and	bl,80h			; (other bits of BL may be set)
	mov	[bp+SX_A].UX_SGN,bl
	mov	[bp+SX_A].UX_CLS,UXC_FIN
	sub	ax,ax
	mov	[bp+SX_A].UX_M0,ax
	mov	[bp+SX_A].UX_M1,ax
	mov	[bp+SX_A].UX_M2,ax
	mov	[bp+SX_A].UX_M3,ax
	mov	cx,10
sfd1:	dec	word ptr [bp+SX_N]
	js	sfd3
	lodsb
	sub	al,'0'
	cbw
	xchg	bx,ax			; BX = digit (the initial carry)
	sub	di,di
sfd2:	mov	ax,[bp+SX_A+di]
	mul	cx
	add	ax,bx
	adc	dx,0
	mov	[bp+SX_A+di],ax		; mantissa = mantissa * 10 + digit
	mov	bx,dx
	inc	di
	inc	di
	cmp	di,8
	jb	sfd2
	jmp	sfd1
sfd3:	mov	[bp+SX_A].UX_EXP,63
	mov	si,SX_A
	call	xNorm
	mov	ax,[bp+SX_E]
	call	xScale10
	pop	di
	push	di
	call	xStore
	test	byte ptr [bp+SX_FL],XF_ZE OR XF_OE OR XF_IE
	pop	di
	pop	bx
	mov	sp,bp
	pop	bp
	jz	sfd9			; carry clear
	stc
sfd9:	ret
ENDPROC	swFromDec

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
; xLoad
;
; Inputs:
;	ES:BX -> double
;	SI = UX
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	xLoad
	mov	ax,es:[bx]
	mov	[bp+si].UX_M0,ax
	mov	ax,es:[bx+2]
	mov	[bp+si].UX_M1,ax
	mov	ax,es:[bx+4]
	mov	[bp+si].UX_M2,ax
	mov	ax,es:[bx+6]
	mov	dl,ah
	and	dl,80h
	mov	[bp+si].UX_SGN,dl
	mov	[bp+si].UX_CLS,UXC_FIN
	mov	dx,ax
	and	ax,000Fh
	mov	[bp+si].UX_M3,ax
	mov	cl,4
	shr	dx,cl
	and	dx,07FFh		; DX = biased exponent
	cmp	dx,07FFh
	je	xld7			; infinity or NaN
	test	dx,dx
	jz	xld2			; zero or denormal
	or	byte ptr [bp+si].UX_M3,10h; set the implicit bit
	jmp	short xld3
xld2:	inc	dx			; denormals have the same scale as 1
xld3:	sub	dx,1023
	mov	[bp+si].UX_EXP,dx
	mov	cx,11
xld4:	call	xShl1			; move the implicit bit to bit 63
	loop	xld4
	jmp	xNorm
xld7:	mov	al,UXC_INF
	mov	dx,[bp+si].UX_M3
	or	dx,[bp+si].UX_M2
	or	dx,[bp+si].UX_M1
	or	dx,[bp+si].UX_M0
	jz	xld8
	mov	al,UXC_NAN
xld8:	mov	[bp+si].UX_CLS,al
	ret
ENDPROC	xLoad

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xStore
;
; Rounds the UX to the nearest double (ties to even), recording XF_OE if it
; overflows; underflows produce denormals (or zero).  NaNs are stored as the
; 8087's "indefinite" value.
;
; Inputs:
;	SI = UX (which is modified)
;	ES:DI -> double
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	xStore
	mov	al,[bp+si].UX_CLS
	cmp	al,UXC_NAN
	je	xst7
	cmp	al,UXC_INF
	je	xst6
	sub	ax,ax
	cmp	[bp+si].UX_M3,ax
	je	xst6a			; zero
	mov	bx,[bp+si].UX_EXP
	add	bx,1023			; BX = biased exponent
	jg	xst2
	mov	cx,1
	sub	cx,bx			; CX = # bits to denormalize
	call	xShrN
	or	dl,dh
	jz	xst1
	or	byte ptr [bp+si].UX_M0,1
xst1:	sub	bx,bx
xst2:	mov	ax,[bp+si].UX_M0	; round at bit 11
	test	ax,0400h
	jz	xst3
	test	ax,0BFFh
	jz	xst3
	add	[bp+si].UX_M0,0800h
	adc	[bp+si].UX_M1,0
	adc	[bp+si].UX_M2,0
	adc	[bp+si].UX_M3,0
	jnc	xst3
	mov	[bp+si].UX_M3,8000h	; rounding carried out of bit 63
	inc	bx
xst3:	test	bx,bx
	jnz	xst4
	test	byte ptr [bp+si].UX_M3+1,80h
	jz	xst4
	inc	bx			; denormal rounded up to a normal
xst4:	cmp	bx,07FFh
	jge	xst5
	mov	cx,11
	call	xShrN
	mov	ax,[bp+si].UX_M3
	and	ax,000Fh
	mov	cl,4
	shl	bx,cl
	or	ax,bx
	jmp	short xst8
xst5:	or	byte ptr [bp+SX_FL],XF_OE
xst6:	mov	ax,7FF0h		; infinity
xst6a:	or	ah,[bp+si].UX_SGN
	jmp	short xst7a
xst7:	mov	ax,0FFF8h		; indefinite
xst7a:	sub	cx,cx
	mov	[bp+si].UX_M0,cx
	mov	[bp+si].UX_M1,cx
	mov	[bp+si].UX_M2,cx
	jmp	short xst9
xst8:	or	ah,[bp+si].UX_SGN
xst9:	mov	es:[di+6],ax
	mov	ax,[bp+si].UX_M0
	mov	es:[di],ax
	mov	ax,[bp+si].UX_M1
	mov	es:[di+2],ax
	mov	ax,[bp+si].UX_M2
	mov	es:[di+4],ax
	ret
ENDPROC	xStore

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xShl1
;
; Shifts the mantissa of the UX at SI left 1 bit.
;
; Outputs:
;	Carry = bit shifted out
;
DEFPROC	xShl1
	shl	[bp+si].UX_M0,1
	rcl	[bp+si].UX_M1,1
	rcl	[bp+si].UX_M2,1
	rcl	[bp+si].UX_M3,1
	ret
ENDPROC	xShl1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xShrN
;
; Shifts the mantissa of the UX at SI right CX bits (any count over 66 is
; treated as 66, which has the same effect).
;
; Outputs:
;	DL = last bit shifted out ("half"), DH = 1 if any other bits shifted
;	out were set ("rest")
;
; Modifies:
;	CX, DX
;
DEFPROC	xShrN
	sub	dx,dx
	jcxz	xsr9
	cmp	cx,66
	jbe	xsr1
	mov	cx,66
xsr1:	or	dh,dl
	shr	[bp+si].UX_M3,1
	rcr	[bp+si].UX_M2,1
	rcr	[bp+si].UX_M1,1
	rcr	[bp+si].UX_M0,1
	mov	dl,0
	adc	dl,0
	loop	xsr1
xsr9:	ret
ENDPROC	xShrN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xNorm
;
; Normalizes the UX at SI (so that bit 63 of the mantissa is set), or sets
; its exponent to zero if the mantissa is zero.
;
; Modifies:
;	AX
;
DEFPROC	xNorm
	mov	ax,[bp+si].UX_M3
	or	ax,[bp+si].UX_M2
	or	ax,[bp+si].UX_M1
	or	ax,[bp+si].UX_M0
	jnz	xn1
	mov	[bp+si].UX_EXP,ax
	ret
xn1:	cmp	[bp+si].UX_M3,0
	jne	xn2
	mov	ax,[bp+si].UX_M2	; shift left 16 bits at a time
	mov	[bp+si].UX_M3,ax
	mov	ax,[bp+si].UX_M1
	mov	[bp+si].UX_M2,ax
	mov	ax,[bp+si].UX_M0
	mov	[bp+si].UX_M1,ax
	mov	[bp+si].UX_M0,0
	sub	[bp+si].UX_EXP,16
	jmp	xn1
xn2:	test	byte ptr [bp+si].UX_M3+1,80h
	jnz	xn9
	call	xShl1
	dec	[bp+si].UX_EXP
	jmp	xn2
xn9:	ret
ENDPROC	xNorm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xCopy, xSwap
;
; xCopy copies the UX at DI to the UX at SI, and xSwap swaps them.
;
; Modifies:
;	AX, CX
;
DEFPROC	xCopy
	push	si
	push	di
	mov	cx,(size UX) SHR 1
xcp1:	mov	ax,[bp+di]
	mov	[bp+si],ax
	inc	si
	inc	si
	inc	di
	inc	di
	loop	xcp1
	pop	di
	pop	si
	ret
ENDPROC	xCopy

DEFPROC	xSwap
	push	si
	push	di
	mov	cx,(size UX) SHR 1
xsw1:	mov	ax,[bp+di]
	xchg	ax,[bp+si]
	mov	[bp+di],ax
	inc	si
	inc	si
	inc	di
	inc	di
	loop	xsw1
	pop	di
	pop	si
	ret
ENDPROC	xSwap

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xIsZero
;
; Outputs:
;	ZF set if the UX at SI is zero
;
DEFPROC	xIsZero
	cmp	[bp+si].UX_CLS,UXC_FIN
	jne	xiz9
	cmp	[bp+si].UX_M3,0
xiz9:	ret
ENDPROC	xIsZero

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xInvalid, xSetZero
;
; xInvalid sets the UX at SI to NaN and records XF_IE, and xSetZero sets it
; to zero (preserving its sign).
;
; Modifies:
;	AX
;
DEFPROC	xInvalid
	mov	[bp+si].UX_CLS,UXC_NAN
	or	byte ptr [bp+SX_FL],XF_IE
	ret
ENDPROC	xInvalid

DEFPROC	xSetZero
	sub	ax,ax
	mov	[bp+si].UX_CLS,al
	mov	[bp+si].UX_M0,ax
	mov	[bp+si].UX_M1,ax
	mov	[bp+si].UX_M2,ax
	mov	[bp+si].UX_M3,ax
	mov	[bp+si].UX_EXP,ax
	ret
ENDPROC	xSetZero

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xAdd
;
; Adds the UX at DI (which may be modified) to the UX at SI.
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	xAdd
	mov	al,[bp+si].UX_CLS
	mov	ah,[bp+di].UX_CLS
	cmp	al,UXC_NAN
	je	xad9
	cmp	ah,UXC_NAN
	je	xad2
	cmp	al,UXC_INF
	jne	xad1
	cmp	ah,UXC_INF
	jne	xad9
	mov	al,[bp+si].UX_SGN
	cmp	al,[bp+di].UX_SGN
	je	xad9
	jmp	xInvalid		; infinities with opposite signs
xad1:	cmp	ah,UXC_INF
	je	xad2
	cmp	[bp+di].UX_M3,0		; is B zero?
	jne	xad1a			; no
	cmp	[bp+si].UX_M3,0		; is A zero, too?
	jne	xad9			; no
	mov	al,[bp+di].UX_SGN
	and	[bp+si].UX_SGN,al	; -0 + -0 is -0, otherwise +0
xad9:	ret
xad1a:	cmp	[bp+si].UX_M3,0		; is A zero?
	jne	xad3			; no
xad2:	jmp	xCopy			; A = B
xad3:	mov	cx,[bp+si].UX_EXP
	sub	cx,[bp+di].UX_EXP
	jge	xad4
	call	xSwap			; make A the larger exponent
	mov	cx,[bp+si].UX_EXP
	sub	cx,[bp+di].UX_EXP
xad4:	push	si
	mov	si,di
	call	xShrN			; align B with A
	or	dl,dh
	jz	xad4a
	or	byte ptr [bp+si].UX_M0,1
xad4a:	pop	si
	mov	al,[bp+si].UX_SGN
	cmp	al,[bp+di].UX_SGN
	jne	xad6
	mov	ax,[bp+di].UX_M0
	add	[bp+si].UX_M0,ax
	mov	ax,[bp+di].UX_M1
	adc	[bp+si].UX_M1,ax
	mov	ax,[bp+di].UX_M2
	adc	[bp+si].UX_M2,ax
	mov	ax,[bp+di].UX_M3
	adc	[bp+si].UX_M3,ax
	jnc	xad5
	rcr	[bp+si].UX_M3,1		; shift the carry back in
	rcr	[bp+si].UX_M2,1
	rcr	[bp+si].UX_M1,1
	rcr	[bp+si].UX_M0,1
	jnc	xad4b
	or	byte ptr [bp+si].UX_M0,1
xad4b:	inc	[bp+si].UX_EXP
xad5:	ret
xad6:	mov	ax,[bp+di].UX_M0
	sub	[bp+si].UX_M0,ax
	mov	ax,[bp+di].UX_M1
	sbb	[bp+si].UX_M1,ax
	mov	ax,[bp+di].UX_M2
	sbb	[bp+si].UX_M2,ax
	mov	ax,[bp+di].UX_M3
	sbb	[bp+si].UX_M3,ax
	jnc	xad7
	not	[bp+si].UX_M0		; B was larger, so negate the result
	not	[bp+si].UX_M1
	not	[bp+si].UX_M2
	not	[bp+si].UX_M3
	add	[bp+si].UX_M0,1
	adc	[bp+si].UX_M1,0
	adc	[bp+si].UX_M2,0
	adc	[bp+si].UX_M3,0
	xor	[bp+si].UX_SGN,80h
xad7:	call	xNorm
	cmp	[bp+si].UX_M3,0
	jne	xad5
	mov	[bp+si].UX_SGN,0	; x - x is +0
	ret
ENDPROC	xAdd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xMul
;
; Multiplies the UX at SI by the UX at DI (which may be the same UX); the
; 128-bit product of the mantissas is formed in the SX_P buffer.
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	xMul
	mov	al,[bp+di].UX_SGN
	xor	[bp+si].UX_SGN,al
	mov	al,[bp+si].UX_CLS
	mov	ah,[bp+di].UX_CLS
	cmp	al,UXC_NAN
	je	xmu0a
	mov	al,UXC_NAN
	cmp	ah,al
	je	xmu0
	mov	al,[bp+si].UX_CLS
	or	al,ah			; either operand infinite?
	jz	xmu2			; no
	call	xIsZero
	jz	xmu1			; infinity times zero is invalid
	xchg	si,di
	call	xIsZero
	xchg	si,di
	jz	xmu1
	mov	al,UXC_INF
xmu0:	mov	[bp+si].UX_CLS,al
xmu0a:	ret
xmu1:	jmp	xInvalid
xmu2:	cmp	[bp+si].UX_M3,0		; is A zero?
	je	xmu0a			; yes
	cmp	[bp+di].UX_M3,0		; is B zero?
	jne	xmu3			; no
	jmp	xSetZero
xmu3:	mov	ax,[bp+di].UX_EXP
	add	[bp+si].UX_EXP,ax
	push	si
	push	di
	mov	ax,[bp+si].UX_M0	; copy the mantissas to SX_MA and SX_MB
	mov	[bp+SX_MA],ax
	mov	ax,[bp+si].UX_M1
	mov	[bp+SX_MA+2],ax
	mov	ax,[bp+si].UX_M2
	mov	[bp+SX_MA+4],ax
	mov	ax,[bp+si].UX_M3
	mov	[bp+SX_MA+6],ax
	mov	ax,[bp+di].UX_M0
	mov	[bp+SX_MB],ax
	mov	ax,[bp+di].UX_M1
	mov	[bp+SX_MB+2],ax
	mov	ax,[bp+di].UX_M2
	mov	[bp+SX_MB+4],ax
	mov	ax,[bp+di].UX_M3
	mov	[bp+SX_MB+6],ax
	lea	bx,[bp+SX_P]
	mov	cx,8
	sub	ax,ax
xmu3a:	mov	ss:[bx],ax		; and zero SX_P
	inc	bx
	inc	bx
	loop	xmu3a
	sub	di,di			; DI = index of B word
xmu4:	mov	cx,[bp+SX_MB+di]
	sub	si,si			; SI = index of A word
xmu5:	mov	ax,[bp+SX_MA+si]
	mul	cx
	lea	bx,[bp+SX_P]
	add	bx,si
	add	bx,di			; SS:BX -> product word
	add	ss:[bx],ax
	adc	ss:[bx+2],dx
	jnc	xmu7
xmu6:	inc	bx
	inc	bx
	add	word ptr ss:[bx+2],1	; propagate the carry
	jc	xmu6
xmu7:	inc	si
	inc	si
	cmp	si,8
	jb	xmu5
	inc	di
	inc	di
	cmp	di,8
	jb	xmu4
	pop	di
	pop	si
	test	byte ptr [bp+SX_P+15],80h
	jnz	xmu8			; product is from 2^127 to 2^128
	lea	bx,[bp+SX_P]
	mov	cx,8
	clc
xmu7a:	rcl	word ptr ss:[bx],1	; product is from 2^126 to 2^127,
	inc	bx			; so shift it left 1 bit
	inc	bx
	loop	xmu7a
	dec	[bp+si].UX_EXP
xmu8:	inc	[bp+si].UX_EXP
	mov	ax,[bp+SX_P+8]		; the mantissa is the upper 64 bits
	mov	[bp+si].UX_M0,ax
	mov	ax,[bp+SX_P+10]
	mov	[bp+si].UX_M1,ax
	mov	ax,[bp+SX_P+12]
	mov	[bp+si].UX_M2,ax
	mov	ax,[bp+SX_P+14]
	mov	[bp+si].UX_M3,ax
	mov	ax,[bp+SX_P]		; and the lower 64 bits are "sticky"
	or	ax,[bp+SX_P+2]
	or	ax,[bp+SX_P+4]
	or	ax,[bp+SX_P+6]
	jz	xmu9
	or	byte ptr [bp+si].UX_M0,1
xmu9:	ret
ENDPROC	xMul

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xDiv
;
; Divides the UX at SI by the UX at DI, using restoring division to produce
; a 64-bit quotient (in SX_MA), with the remainder in SX_P (plus an extra top
; bit in BL) and the divisor in SX_MB.
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	xDiv
	mov	al,[bp+di].UX_SGN
	xor	[bp+si].UX_SGN,al
	mov	al,[bp+si].UX_CLS
	mov	ah,[bp+di].UX_CLS
	cmp	al,UXC_NAN
	je	xdv9
	cmp	ah,UXC_NAN
	je	xdv0
	cmp	al,UXC_INF
	jne	xdv1
	cmp	ah,UXC_INF
	jne	xdv9			; infinity divided by finite is infinity
xdv0a:	jmp	xInvalid
xdv0:	mov	[bp+si].UX_CLS,ah
xdv9:	ret
xdv1:	cmp	ah,UXC_INF
	jne	xdv2
	jmp	xSetZero		; finite divided by infinity is zero
xdv2:	cmp	[bp+di].UX_M3,0		; is B zero?
	jne	xdv3			; no
	cmp	[bp+si].UX_M3,0		; is A zero, too?
	je	xdv0a			; yes, which is invalid
	or	byte ptr [bp+SX_FL],XF_ZE
	mov	[bp+si].UX_CLS,UXC_INF
	ret
xdv3:	cmp	[bp+si].UX_M3,0		; is A zero?
	je	xdv9			; yes
	mov	ax,[bp+di].UX_EXP
	sub	[bp+si].UX_EXP,ax
	mov	ax,[bp+si].UX_M0	; copy A's mantissa to SX_P
	mov	[bp+SX_P],ax
	mov	ax,[bp+si].UX_M1
	mov	[bp+SX_P+2],ax
	mov	ax,[bp+si].UX_M2
	mov	[bp+SX_P+4],ax
	mov	ax,[bp+si].UX_M3
	mov	[bp+SX_P+6],ax
	mov	ax,[bp+di].UX_M0	; and B's mantissa to SX_MB
	mov	[bp+SX_MB],ax
	mov	ax,[bp+di].UX_M1
	mov	[bp+SX_MB+2],ax
	mov	ax,[bp+di].UX_M2
	mov	[bp+SX_MB+4],ax
	mov	ax,[bp+di].UX_M3
	mov	[bp+SX_MB+6],ax
	sub	bl,bl			; BL = extra top bit of remainder
	call	xdvCmp
	jnc	xdv4
	dec	[bp+si].UX_EXP		; A's mantissa < B's mantissa
	call	xdvShl
xdv4:	mov	cx,64
xdv5:	test	bl,bl
	jnz	xdv6
	call	xdvCmp
	jc	xdv7			; remainder < divisor
xdv6:	mov	ax,[bp+SX_MB]		; subtract the divisor
	sub	[bp+SX_P],ax
	mov	ax,[bp+SX_MB+2]
	sbb	[bp+SX_P+2],ax
	mov	ax,[bp+SX_MB+4]
	sbb	[bp+SX_P+4],ax
	mov	ax,[bp+SX_MB+6]
	sbb	[bp+SX_P+6],ax
	sub	bl,bl
	stc				; and shift a 1 into the quotient
	jmp	short xdv8
xdv7:	clc				; otherwise, shift a 0
xdv8:	rcl	word ptr [bp+SX_MA],1
	rcl	word ptr [bp+SX_MA+2],1
	rcl	word ptr [bp+SX_MA+4],1
	rcl	word ptr [bp+SX_MA+6],1
	call	xdvShl
	loop	xdv5
	mov	ax,[bp+SX_MA]
	mov	[bp+si].UX_M0,ax
	mov	ax,[bp+SX_MA+2]
	mov	[bp+si].UX_M1,ax
	mov	ax,[bp+SX_MA+4]
	mov	[bp+si].UX_M2,ax
	mov	ax,[bp+SX_MA+6]
	mov	[bp+si].UX_M3,ax
	mov	ax,[bp+SX_P]		; any remainder is "sticky"
	or	ax,[bp+SX_P+2]
	or	ax,[bp+SX_P+4]
	or	ax,[bp+SX_P+6]
	or	al,bl
	jz	xdv10
	or	byte ptr [bp+si].UX_M0,1
xdv10:	ret

xdvCmp:	mov	ax,[bp+SX_P+6]		; carry set if remainder < divisor
	cmp	ax,[bp+SX_MB+6]
	jne	xdc9
	mov	ax,[bp+SX_P+4]
	cmp	ax,[bp+SX_MB+4]
	jne	xdc9
	mov	ax,[bp+SX_P+2]
	cmp	ax,[bp+SX_MB+2]
	jne	xdc9
	mov	ax,[bp+SX_P]
	cmp	ax,[bp+SX_MB]
xdc9:	ret

xdvShl:	shl	word ptr [bp+SX_P],1	; shift remainder left 1 bit
	rcl	word ptr [bp+SX_P+2],1
	rcl	word ptr [bp+SX_P+4],1
	rcl	word ptr [bp+SX_P+6],1
	mov	bl,0
	adc	bl,0
	ret
ENDPROC	xDiv

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xCmpMag
;
; Compares the magnitudes of the UX values at SI and DI (neither can be NaN).
;
; Outputs:
;	AL = 1 if |SI| > |DI|, 0 if equal, -1 if less
;
; Modifies:
;	AX, DX
;
DEFPROC	xCmpMag
	mov	al,[bp+si].UX_CLS
	mov	ah,[bp+di].UX_CLS
	cmp	al,ah
	jne	xcm8			; infinity is larger than finite
	test	al,al
	jnz	xcm6			; both infinite
	mov	ax,[bp+si].UX_M3
	mov	dx,[bp+di].UX_M3
	test	ax,ax
	jnz	xcm1
	test	dx,dx
	jz	xcm6			; both zero
	jmp	short xcm7		; only A is zero
xcm1:	test	dx,dx
	jz	xcm5			; only B is zero
	mov	ax,[bp+si].UX_EXP
	cmp	ax,[bp+di].UX_EXP
	jne	xcm4
	mov	ax,[bp+si].UX_M3
	cmp	ax,[bp+di].UX_M3
	jne	xcm8
	mov	ax,[bp+si].UX_M2
	cmp	ax,[bp+di].UX_M2
	jne	xcm8
	mov	ax,[bp+si].UX_M1
	cmp	ax,[bp+di].UX_M1
	jne	xcm8
	mov	ax,[bp+si].UX_M0
	cmp	ax,[bp+di].UX_M0
	jne	xcm8
xcm6:	mov	al,0
	ret
xcm4:	jg	xcm5			; signed exponent comparison
xcm7:	mov	al,-1
	ret
xcm8:	jb	xcm7			; unsigned comparison
xcm5:	mov	al,1
	ret
ENDPROC	xCmpMag

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xRndInt
;
; Rounds the UX at SI to an integer, according to the mode in AL: 0 for
; nearest (ties to even), 1 for nearest (ties away from zero), 2 for down
; (toward -infinity), or 3 for toward zero.
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	xRndInt
	call	xIsZero
	jz	xri9			; zero (or not finite)
	cmp	[bp+si].UX_CLS,UXC_FIN
	jne	xri9
	mov	cx,63
	sub	cx,[bp+si].UX_EXP
	jle	xri9			; it's already an integer
	push	ax
	call	xShrN			; DL = half, DH = rest
	pop	ax
	cmp	al,1
	jb	xri2
	je	xri4
	cmp	al,3
	je	xri6
	test	byte ptr [bp+si].UX_SGN,80h
	jz	xri6			; rounding down a positive value
	or	dl,dh			; rounding down a negative value
	jmp	short xri4
xri2:	test	dl,dl
	jz	xri6
	mov	al,byte ptr [bp+si].UX_M0
	and	al,1			; a tie is rounded up only if the
	or	dh,al			; integer is odd
	mov	dl,dh
xri4:	test	dl,dl
	jz	xri6
	add	[bp+si].UX_M0,1
	adc	[bp+si].UX_M1,0
	adc	[bp+si].UX_M2,0
	adc	[bp+si].UX_M3,0
xri6:	mov	[bp+si].UX_EXP,63
	jmp	xNorm
xri9:	ret
ENDPROC	xRndInt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xToLong
;
; Rounds the UX at SI (see xRndInt for the modes in AL) and converts it to a
; long, recording XF_IE (and returning 80000000h) if it doesn't fit.
;
; Outputs:
;	DX:AX = long
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	xToLong
	call	xRndInt
	cmp	[bp+si].UX_CLS,UXC_FIN
	jne	xtl8
	sub	ax,ax
	cwd
	cmp	[bp+si].UX_M3,ax
	je	xtl9			; zero
	mov	cx,31
	sub	cx,[bp+si].UX_EXP
	jl	xtl8			; too large
	mov	dx,[bp+si].UX_M3
	mov	ax,[bp+si].UX_M2
	jcxz	xtl3
xtl1:	shr	dx,1
	rcr	ax,1
	loop	xtl1
	test	byte ptr [bp+si].UX_SGN,80h
	jz	xtl9
	neg	dx
	neg	ax
	sbb	dx,0
	ret
xtl3:	test	byte ptr [bp+si].UX_SGN,80h
	jz	xtl8			; only -2^31 has an exponent of 31
	test	ax,ax
	jnz	xtl8
	cmp	dx,8000h
	je	xtl9
xtl8:	or	byte ptr [bp+SX_FL],XF_IE
	mov	dx,8000h
	sub	ax,ax
xtl9:	ret
ENDPROC	xToLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xFromLong
;
; Sets the UX at SI to the long in DX:AX.
;
; Modifies:
;	AX, DX
;
DEFPROC	xFromLong
	mov	[bp+si].UX_CLS,UXC_FIN
	mov	[bp+si].UX_SGN,0
	test	dx,dx
	jns	xfl1
	mov	[bp+si].UX_SGN,80h
	neg	dx
	neg	ax
	sbb	dx,0
xfl1:	mov	[bp+si].UX_M3,dx
	mov	[bp+si].UX_M2,ax
	sub	ax,ax
	mov	[bp+si].UX_M1,ax
	mov	[bp+si].UX_M0,ax
	mov	[bp+si].UX_EXP,31
	jmp	xNorm
ENDPROC	xFromLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xPowInt
;
; Sets the UX at SI to the UX at DI (which is modified) raised to the BX power
; (unsigned), by repeated squaring.
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	xPowInt
	mov	ax,1
	cwd
	call	xFromLong
xpi1:	shr	bx,1
	jnc	xpi2
	push	bx
	call	xMul			; multiply result by current power
	pop	bx
xpi2:	test	bx,bx
	jz	xpi9
	push	bx
	push	si
	mov	si,di
	call	xMul			; square the current power
	pop	si
	pop	bx
	jmp	xpi1
xpi9:	ret
ENDPROC	xPowInt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xScale10
;
; Multiplies (or for negative exponents, divides) the UX at SI (which must
; not be SX_B or SX_C) by 10^AX.
;
; Modifies:
;	AX, BX, CX, DX, DI, SX_B, SX_C
;
DEFPROC	xScale10
	test	ax,ax
	jz	xsc9
	push	si
	push	ax
	mov	bx,ax
	test	bx,bx
	jns	xsc1
	neg	bx			; BX = abs(n)
xsc1:	mov	si,SX_B
	mov	ax,10
	cwd
	call	xFromLong
	mov	si,SX_C
	mov	di,SX_B
	call	xPowInt			; C = 10^abs(n)
	pop	ax
	pop	si
	mov	di,SX_C
	test	ax,ax
	js	xsc2
	jmp	xMul
xsc2:	jmp	xDiv
xsc9:	ret
ENDPROC	xScale10

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xSqrt
;
; Sets the UX at SX_A to its square root, using Newton's method: starting with
; an estimate y (x with its exponent halved), y = (y + x/y) / 2 is repeated
; until it's as precise as 64 bits allow (6 iterations).
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, SX_C, SX_D
;
DEFPROC	xSqrt
	mov	si,SX_A
	cmp	[bp+si].UX_CLS,UXC_NAN
	je	xsq9
	call	xIsZero
	jz	xsq9			; the square root of +/-0 is +/-0
	test	[bp+si].UX_SGN,80h
	jz	xsq1
	jmp	xInvalid		; negative values are invalid
xsq1:	cmp	[bp+si].UX_CLS,UXC_INF
	je	xsq9
	mov	si,SX_D
	mov	di,SX_A
	call	xCopy			; D = x
	sar	[bp+SX_A].UX_EXP,1	; A = y
	mov	cx,6
xsq2:	push	cx
	mov	si,SX_C
	mov	di,SX_D
	call	xCopy
	mov	di,SX_A
	call	xDiv			; C = x / y
	mov	si,SX_A
	mov	di,SX_C
	call	xAdd			; A = y + x/y
	dec	[bp+SX_A].UX_EXP	; A = (y + x/y) / 2
	pop	cx
	loop	xsq2
xsq9:	ret
ENDPROC	xSqrt

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
