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
;	AL = precision (0FFh if none, or 80h+n for n significant digits)
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
	mov	al,[fmtPrecis]
	sub	al,80h			; precision 80h+n (n <= FPU_DIGITS)?
	cmp	al,cl
	ja	cd3a			; no
	mov	cl,al			; yes, use n significant digits
	mov	[fmtPrecis],0FFh	; in the BASIC-style format
cd3a:	call	cs:[fpuToDec]		; CX = # digits, AX = exponent
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
	dw	hwSin, hwCos, hwTan, hwAtn, hwLog, hwEtoX
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
	DEFQUAD	hwQuarter,3FD0000000000000h; 0.25
	DEFQUAD	hwHalf,3FE0000000000000h; 0.5
	DEFQUAD	hwOne,3FF0000000000000h	; 1.0
	DEFQUAD	hwTen,4024000000000000h	; 10.0
	DEFQUAD	hwBig,43F0000000000000h	; 2^64

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
; hwSin, hwCos, hwTan
;
; The argument is reduced modulo pi/4 with FPREM, which also provides the
; octant (q, the low 3 bits of the quotient), and since the 8087's FPTAN
; requires an argument from 0 to pi/4 (exclusive), the reduced argument r is
; replaced with pi/4 - r in odd octants.  FPTAN produces y and x such that
; tan(r) = y/x, so sin(r) = y/h and cos(r) = x/h, where h = sqrt(x^2 + y^2).
;
; The sine uses cos(r) in octants 1, 2, 5, and 6, and is negative in octants
; 4 through 7; the cosine uses sin(r) in octants 1, 2, 5, and 6, and is
; negative in octants 2 through 5.  The tangent is the ratio of the two.
;
; Inputs:
;	1 double on stack
;	ES:DI -> result
;
; Outputs:
;	1 double on stack (SIN, COS, or TAN of the input)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	hwSin,FAR
	mov	cl,0
	jmp	short hwTrig
	DEFLBL	hwCos,near
	mov	cl,1
	jmp	short hwTrig
	DEFLBL	hwTan,near
	mov	cl,2
hwTrig:	call	hwLoadT			; ST(0) = x
	sub	ch,ch			; CH = 1 to negate the result
	ftst
	call	hwStat
	jae	htg1
	fchs				; ST(0) = abs(x)
	cmp	cl,1
	je	htg1			; the cosine is an even function
	inc	ch			; but the sine and tangent are odd
htg1:	fldpi
	fmul	cs:[hwQuarter]		; ST(0) = pi/4, ST(1) = abs(x)
	fxch
htg2:	fprem				; ST(0) = r (abs(x) modulo pi/4)
	call	hwStat
	test	ah,04h			; C2 set if reduction is incomplete
	jnz	htg2
	sub	dl,dl			; DL = q (C0 = Q2, C3 = Q1, C1 = Q0)
	test	ah,01h
	jz	htg3
	or	dl,4
htg3:	test	ah,40h
	jz	htg4
	or	dl,2
htg4:	test	ah,02h
	jz	htg5
	or	dl,1
htg5:	test	dl,1			; odd octant?
	jz	htg7			; no
	ftst
	call	hwStat
	jne	htg6
	fstp	st(0)			; r is zero, so pi/4 - r is pi/4,
	fstp	st(0)			; whose tangent is 1/1
	fld1
	fld1
	jmp	short htg8
htg6:	fsubp	st(1),st		; ST(0) = pi/4 - r
	jmp	short htg7a
htg7:	fstp	st(1)			; ST(0) = r
htg7a:	fptan				; ST(0) = x, ST(1) = y
htg8:	mov	al,dl
	inc	al
	and	al,2			; AL = 2 if sin and cos are swapped
	mov	ah,dl
	add	ah,2
	xor	ah,dl
	and	ah,4			; AH = 4 if sin and cos signs differ
	test	dl,4
	jz	htg9
	xor	ah,4			; AH = 4 if cos is negative
	xor	ch,1			; (and sin is negative)
htg9:	cmp	cl,1
	jb	htg11			; sine
	je	htg10			; cosine
	test	ah,4			; tangent: negate if the signs differ
	jz	htg9a
	xor	ch,1
htg9a:	test	al,al			; swapped?
	jz	ht9b			; no
	fdiv	st,st(1)		; ST(0) = x/y
	jmp	short htg13
ht9b:	fdivr	st,st(1)		; ST(0) = y/x
	jmp	short htg13
htg10:	xor	al,2			; the cosine wants x unless swapped
	test	dl,4
	jz	htg10a
	xor	ch,1			; (undo the sine's sign)
htg10a:	test	ah,4
	jz	htg11
	xor	ch,1
htg11:	fld	st(0)
	fmul	st,st(0)		; ST(0) = x^2, ST(1) = x, ST(2) = y
	fld	st(2)
	fmul	st,st(0)		; ST(0) = y^2
	faddp	st(1),st
	fsqrt				; ST(0) = h, ST(1) = x, ST(2) = y
	test	al,al			; does this function want x?
	jnz	htg12			; yes
	fdivr	st,st(2)		; ST(0) = y/h
	jmp	short htg12a
htg12:	fdivr	st,st(1)		; ST(0) = x/h
htg12a:	fstp	st(1)
htg13:	fstp	st(1)			; ST(0) = result
	test	ch,1
	jz	htg14
	fchs
htg14:	jmp	hwStoreT
ENDPROC	hwSin

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwAtn
;
; The 8087's FPATAN calculates atan(y/x) only when 0 < y < x, so for abs(x)
; < 1, we calculate atan(abs(x)/1), and for abs(x) > 1, pi/2 - atan(1/abs(x));
; abs(x) = 1 is simply pi/4, and anything 2^64 or larger is simply pi/2.
;
; Inputs:
;	1 double on stack
;	ES:DI -> result
;
; Outputs:
;	1 double on stack (ATN of the input)
;
; Modifies:
;	AX, BX, CH, SI
;
DEFPROC	hwAtn,FAR
	call	hwLoadT			; ST(0) = x
	sub	ch,ch
	ftst
	call	hwStat
	je	ha9			; atan(0) is 0
	jae	ha1
	fchs				; ST(0) = abs(x)
	inc	ch
ha1:	fcom	cs:[hwBig]
	call	hwStat
	jb	ha2
	fstp	st(0)			; abs(x) >= 2^64
	fldpi
	fmul	cs:[hwHalf]		; so the result is pi/2
	jmp	short ha8
ha2:	fld1				; ST(0) = 1, ST(1) = abs(x)
	fcom	st(1)
	call	hwStat
	jb	ha4			; abs(x) > 1
	jne	ha3			; abs(x) < 1
	fstp	st(0)			; abs(x) = 1
	fstp	st(0)
	fldpi
	fmul	cs:[hwQuarter]		; so the result is pi/4
	jmp	short ha8
ha3:	fpatan				; ST(0) = atan(abs(x)/1)
	jmp	short ha8
ha4:	fxch				; ST(0) = abs(x), ST(1) = 1
	fpatan				; ST(0) = atan(1/abs(x))
	fldpi
	fmul	cs:[hwHalf]
	fsubrp	st(1),st		; ST(0) = pi/2 - atan(1/abs(x))
ha8:	test	ch,ch
	jz	ha9
	fchs
ha9:	jmp	hwStoreT
ENDPROC	hwAtn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hwLog, hwEtoX
;
; LOG(x) is ln(2) * log2(x), and EXP(x) is 2^(x * log2(e)).
;
; Inputs:
;	1 double on stack
;	ES:DI -> result
;
; Outputs:
;	1 double on stack (LOG or EXP of the input)
;
; Modifies:
;	AX, BX, SI
;
DEFPROC	hwLog,FAR
	call	hwLoadT			; ST(0) = x
	fldln2
	fxch
	fyl2x				; ST(0) = ln(2) * log2(x)
	jmp	hwStoreT
	DEFLBL	hwEtoX,near
	call	hwLoadT
	fldl2e
	fmul				; ST(0) = x * log2(e)
	call	hwPow2
	jmp	hwStoreT
ENDPROC	hwLog

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
; FPU_EXP uses repeated multiplication for integer exponents (from -32768 to
; 32767), so that results like 2^10 are exact, and e^(B*ln(A)) otherwise.
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
SX_SIZE	equ	90		; frame size for most functions
SX_F	equ	-102		; UX F (temp for transcendental functions)
SX_G	equ	-114		; UX G (temp for transcendental functions)
SX_H	equ	-126		; UX H (temp for transcendental functions)
SX_XSIZE equ	126		; frame size for transcendental functions

SWENTER	macro	size
	push	bp
	mov	bp,sp
	IFB	<size>
	sub	sp,SX_SIZE
	ELSE
	sub	sp,size
	ENDIF
	mov	[bp+SX_DST].OFF,di
	mov	[bp+SX_DST].SEG,es
	mov	word ptr [bp+SX_FL],0
	endm

;
; Script definitions for xScript (see below)
;
XI_A	equ	0
XI_B	equ	1
XI_C	equ	2
XI_D	equ	3
XI_F	equ	4
XI_G	equ	5
XI_H	equ	6

XO_COPY	equ	1		; SI = DI
XO_MUL	equ	2		; SI = SI * DI
XO_DIV	equ	3		; SI = SI / DI
XO_ADD	equ	4		; SI = SI + DI (DI may be modified)
XO_SUB	equ	5		; SI = SI - DI (DI may be modified)
XO_NEG	equ	6		; SI = -SI
XO_INT	equ	7		; SI = small integer
XO_K	equ	8		; SI = constant (eg, KI_PIBY2)
XO_SQRT	equ	9		; A = sqrt(A)
XO_MULT	equ	10		; SI = SI * DI (truncated; see xMulT)

XRUN	macro
	call	xScript
	endm

XS	macro	op,a,b
	db	op,((a) SHL 4) OR (b)
	endm

XEND	macro
	db	0,0
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
	dw	swSin, swCos, swTan, swAtn, swLog, swEtoX
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
	SWENTER	SX_XSIZE
	call	swLoad2
	mov	al,[bp+SX_A].UX_CLS
	or	al,[bp+SX_B].UX_CLS
	test	al,UXC_NAN		; either operand NaN?
	jz	sxp1			; no
	mov	[bp+SX_A].UX_CLS,UXC_NAN
	jmp	swStoreA4
sxp1:	cmp	[bp+SX_B].UX_CLS,UXC_FIN
	jne	sxp7			; B is infinite
	XRUN
	XS	XO_COPY,XI_C,XI_B	; (and SI -> C, DI -> B)
	XEND
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
	XRUN
	XS	XO_COPY,XI_D,XI_A	; D = A
	XEND
	pop	bx
	push	bx
	test	bx,bx
	jns	sxp3
	neg	bx			; BX = abs(n)
sxp3:	mov	si,SX_C
	mov	di,SX_D
	call	xPowInt			; C = A^abs(n)
	pop	ax
	test	ax,ax
	js	sxp4
	XRUN
	XS	XO_COPY,XI_A,XI_C	; A = A^n
	XEND
	jmp	swStoreA4
sxp4:	XRUN
	XS	XO_INT,XI_A,1
	XS	XO_DIV,XI_A,XI_C	; A = 1 / A^abs(n)
	XEND
	jmp	swStoreA4
sxp7:	mov	si,SX_A
	call	xIsZero			; zero raised to any power is zero
	jz	sxp9
	test	[bp+si].UX_SGN,80h	; a negative base requires an integer
	jz	sxp8			; exponent
	call	xInvalid
	jmp	short sxp9
sxp8:	XRUN
	XS	XO_COPY,XI_G,XI_B	; G = B
	XEND
	call	xLn			; A = ln(A)
	XRUN
	XS	XO_MUL,XI_A,XI_G	; A = B*ln(A)
	XEND
	call	xExp			; A = e^(B*ln(A))
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
	mov	al,4			; signs differ, so A < B if A < 0
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
	jmp	swStoreT
	DEFLBL	swSin,near
	mov	al,0
	jmp	short swTrg
	DEFLBL	swCos,near
	mov	al,1
	jmp	short swTrg
	DEFLBL	swTan,near
	mov	al,2
swTrg:
	SWENTER	SX_XSIZE
	mov	byte ptr [bp+SX_FL+1],al
	call	swLoadT
	mov	al,byte ptr [bp+SX_FL+1]
	call	xTrig
	jmp	swStoreT
	DEFLBL	swAtn,near
	SWENTER	SX_XSIZE
	call	swLoadT
	call	xAtn
	jmp	short swStoreT
	DEFLBL	swLog,near
	SWENTER	SX_XSIZE
	call	swLoadT
	call	xLn
	jmp	short swStoreT
	DEFLBL	swEtoX,near
	SWENTER	SX_XSIZE
	call	swLoadT
	call	xExp
	jmp	short swStoreT
	DEFLBL	swSqr,near
	SWENTER	SX_XSIZE
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
std2:	XRUN
	XS	XO_COPY,XI_A,XI_D	; A = x (and SI -> A)
	XEND
	mov	ax,[bp+SX_N]
	test	ax,ax
	jnz	std3
	inc	ax
std3:	dec	ax			; AX = M-1
	push	ax
	sub	ax,[bp+SX_E]
	call	xScale10		; A = x * 10^(M-1-e)
	XRUN
	XS	XO_INT,XI_B,10
	XEND
	pop	bx
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
std4:	XRUN
	XS	XO_INT,XI_B,10
	XS	XO_MUL,XI_B,XI_C	; B = 10^M
	XEND
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
	XRUN
	XS	XO_INT,XI_B,5
	XEND
	mov	si,SX_A
	mov	di,SX_B
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
	mov	ax,es:[bx+6]
	mov	dl,ah
	and	dl,80h
	mov	[bp+si].UX_SGN,dl
	mov	[bp+si].UX_CLS,UXC_FIN
	mov	dx,ax
	mov	cl,4
	shr	dx,cl
	and	dx,07FFh		; DX = biased exponent
	and	ax,000Fh		; AX = top 4 bits of the mantissa
	cmp	dx,07FFh
	jne	xld1
	jmp	xld7			; infinity or NaN
xld1:	test	dx,dx
	jz	xld2			; zero or denormal
	or	al,10h			; set the implicit bit
	jmp	short xld3
xld2:	inc	dx			; denormals have the same scale as 1
xld3:	sub	dx,1023
	mov	[bp+si].UX_EXP,dx
	xchg	dx,ax
	mov	cx,es:[bx+4]
	mov	ax,es:[bx]
	mov	bx,es:[bx+2]		; DX:CX:BX:AX = mantissa
	mov	dh,dl			; shift it left 8 bits
	mov	dl,ch
	mov	ch,cl
	mov	cl,bh
	mov	bh,bl
	mov	bl,ah
	mov	ah,al
	mov	al,0
	REPT	3			; and then 3 more bits, which moves
	shl	ax,1			; the implicit bit to bit 63
	rcl	bx,1
	rcl	cx,1
	rcl	dx,1
	ENDM
	mov	[bp+si].UX_M0,ax
	mov	[bp+si].UX_M1,bx
	mov	[bp+si].UX_M2,cx
	mov	[bp+si].UX_M3,dx
	jmp	xNorm
xld7:	or	ax,es:[bx]
	or	ax,es:[bx+2]
	or	ax,es:[bx+4]
	mov	al,UXC_INF
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
	jmp	short xst0
xst5:	or	byte ptr [bp+SX_FL],XF_OE
xst6:	mov	ax,7FF0h		; infinity
xst6a:	or	ah,[bp+si].UX_SGN
	jmp	short xst7a
xst7:	mov	ax,0FFF8h		; indefinite
xst7a:	mov	es:[di+6],ax
	sub	ax,ax
	mov	es:[di],ax
	mov	es:[di+2],ax
	mov	es:[di+4],ax
	ret
xst0:	mov	bx,[bp+si].UX_EXP
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
	jl	xst4a
	jmp	xst5
xst4a:	mov	cl,4
	shl	bx,cl
	or	bh,[bp+si].UX_SGN
	push	bx			; save the sign and exponent
	mov	ax,[bp+si].UX_M0
	mov	bx,[bp+si].UX_M1
	mov	cx,[bp+si].UX_M2
	mov	dx,[bp+si].UX_M3	; DX:CX:BX:AX = mantissa
	mov	al,ah			; shift it right 8 bits
	mov	ah,bl
	mov	bl,bh
	mov	bh,cl
	mov	cl,ch
	mov	ch,dl
	mov	dl,dh
	REPT	3			; and then 3 more bits (the bits
	shr	dx,1			; shifted out were rounded above)
	rcr	cx,1
	rcr	bx,1
	rcr	ax,1
	ENDM
	mov	es:[di],ax
	mov	es:[di+2],bx
	mov	es:[di+4],cx
	pop	ax
	and	dx,000Fh
	or	ax,dx
	mov	es:[di+6],ax
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
; xMantPut, xMantGet
;
; xMantPut copies the mantissa of the UX at SI to the 8 bytes at SS:BX, and
; xMantGet copies the 8 bytes at SS:BX to the mantissa of the UX at SI.
;
; Modifies:
;	AX
;
DEFPROC	xMantPut
	IRP	w,<UX_M0,UX_M1,UX_M2,UX_M3>
	mov	ax,[bp+si+w]
	mov	ss:[bx+w-UX_M0],ax
	ENDM
	ret
ENDPROC	xMantPut

DEFPROC	xMantGet
	IRP	w,<UX_M0,UX_M1,UX_M2,UX_M3>
	mov	ax,ss:[bx+w-UX_M0]
	mov	[bp+si+w],ax
	ENDM
	ret
ENDPROC	xMantGet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xShrN
;
; Shifts the mantissa of the UX at SI right CX bits (any count over 66 is
; treated as 66, which has the same effect), 16 bits at a time when possible.
;
; Outputs:
;	DL = last bit shifted out ("half"), DH = 1 if any other bits shifted
;	out were set ("rest")
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	xShrN
	sub	dx,dx
	cmp	cx,66
	jbe	xsr0
	mov	cx,66
xsr0:	cmp	cx,16
	jb	xsr1a
	or	dh,dl			; the previous "half" is part of "rest"
	mov	ax,[bp+si].UX_M0
	shl	ax,1			; CF = the last bit shifted out
	mov	dl,0
	adc	dl,0			; DL = "half"
	test	ax,ax
	jz	xsr0a
	or	dh,1			; any other bits are part of "rest"
xsr0a:	mov	ax,[bp+si].UX_M1
	mov	[bp+si].UX_M0,ax
	mov	ax,[bp+si].UX_M2
	mov	[bp+si].UX_M1,ax
	mov	ax,[bp+si].UX_M3
	mov	[bp+si].UX_M2,ax
	mov	[bp+si].UX_M3,0
	sub	cx,16
	jmp	xsr0
xsr1a:	jcxz	xsr9
	push	bx
	mov	ch,cl			; CH = # bits to shift (1-15)
	mov	cl,16
	sub	cl,ch			; CL = 16 - # bits
	or	dh,dl			; the previous "half" is part of "rest"
	mov	ax,[bp+si].UX_M0
	shl	ax,cl			; AX = the bits shifted out
	shl	ax,1
	mov	dl,0
	adc	dl,0			; DL = "half"
	test	ax,ax
	jz	xsr2
	or	dh,1			; any other bits are part of "rest"
xsr2:	IRP	w,<UX_M0,UX_M1,UX_M2>
	mov	ax,[bp+si+w+2]
	shl	ax,cl			; AX = bits from the next word
	xchg	cl,ch
	mov	bx,[bp+si+w]
	shr	bx,cl
	or	bx,ax
	mov	[bp+si+w],bx
	xchg	cl,ch
	ENDM
	xchg	cl,ch
	shr	[bp+si].UX_M3,cl
	pop	bx
xsr9:	ret
ENDPROC	xShrN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
	test	byte ptr [bp+si].UX_M3+1,80h
	jnz	xn9			; already normalized
	mov	ax,[bp+si].UX_M3
	or	ax,[bp+si].UX_M2
	or	ax,[bp+si].UX_M1
	or	ax,[bp+si].UX_M0
	jnz	xn1
	mov	[bp+si].UX_EXP,ax
	ret
xn1:	push	bx
	push	cx
	push	dx
	mov	ax,[bp+si].UX_M0
	mov	bx,[bp+si].UX_M1
	mov	cx,[bp+si].UX_M2
	mov	dx,[bp+si].UX_M3	; DX:CX:BX:AX = mantissa
xn2:	test	dx,dx
	jnz	xn3
	mov	dx,cx			; shift left 16 bits at a time
	mov	cx,bx
	mov	bx,ax
	sub	ax,ax
	sub	[bp+si].UX_EXP,16
	jmp	xn2
xn3:	test	dh,dh
	jnz	xn4
	mov	dh,dl			; then 8 bits
	mov	dl,ch
	mov	ch,cl
	mov	cl,bh
	mov	bh,bl
	mov	bl,ah
	mov	ah,al
	mov	al,0
	sub	[bp+si].UX_EXP,8
xn4:	test	dh,80h
	jnz	xn5
	shl	ax,1			; and then 1 bit at a time
	rcl	bx,1
	rcl	cx,1
	rcl	dx,1
	dec	[bp+si].UX_EXP
	jmp	xn4
xn5:	mov	[bp+si].UX_M0,ax
	mov	[bp+si].UX_M1,bx
	mov	[bp+si].UX_M2,cx
	mov	[bp+si].UX_M3,dx
	pop	dx
	pop	cx
	pop	bx
xn9:	ret
ENDPROC	xNorm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xCopy
;
; Copies the UX at DI to the UX at SI.
;
; Modifies:
;	AX, CX
;
DEFPROC	xCopy
	IRP	w,<0,2,4,6,8,10>
	mov	ax,[bp+di+w]
	mov	[bp+si+w],ax
	ENDM
	ret
ENDPROC	xCopy


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
	je	xad0x
	cmp	ah,UXC_NAN
	je	xad2
	cmp	al,UXC_INF
	jne	xad1
	cmp	ah,UXC_INF
	jne	xad0x
	mov	al,[bp+si].UX_SGN
	cmp	al,[bp+di].UX_SGN
	je	xad0x
	jmp	xInvalid		; infinities with opposite signs
xad1:	cmp	ah,UXC_INF
	je	xad2
	cmp	[bp+di].UX_M3,0		; is B zero?
	jne	xad1a			; no
	cmp	[bp+si].UX_M3,0		; is A zero, too?
	jne	xad0x			; no
	mov	al,[bp+di].UX_SGN
	and	[bp+si].UX_SGN,al	; -0 + -0 is -0, otherwise +0
xad0x:	ret
xad1a:	cmp	[bp+si].UX_M3,0		; is A zero?
	jne	xad3			; no
xad2:	jmp	xCopy			; A = B
xad3:	push	bx
	push	di
	push	si			; save the result UX
	mov	cx,[bp+si].UX_EXP
	sub	cx,[bp+di].UX_EXP
	jge	xad4
	xchg	si,di			; SI = the UX with the larger exponent
	neg	cx			; CX = difference in exponents
xad4:	mov	al,[bp+si].UX_SGN
	xor	al,[bp+di].UX_SGN
	push	ax			; AL = 80h if the signs differ
	cmp	cx,66
	jbe	xad4a
	mov	cx,66
xad4a:	mov	ax,[bp+di].UX_M0
	mov	bx,[bp+di].UX_M1
	mov	dx,[bp+di].UX_M2
	mov	di,[bp+di].UX_M3	; DI:DX:BX:AX = smaller mantissa
	mov	ch,0			; CH = # of set bits shifted out
xad5:	cmp	cl,16			; align it 16 bits at a time
	jb	xad6
	cmp	ax,1
	cmc
	adc	ch,0			; (any bits in AX are lost)
	mov	ax,bx
	mov	bx,dx
	mov	dx,di
	sub	di,di
	sub	cl,16
	jmp	xad5
xad6:	test	cl,cl			; and then 1 bit at a time
	jz	xad7
xad6a:	shr	di,1
	rcr	dx,1
	rcr	bx,1
	rcr	ax,1
	adc	ch,0
	dec	cl
	jnz	xad6a
xad7:	test	ch,ch
	jz	xad7a
	or	al,1			; any lost bits are "sticky"
xad7a:	pop	cx			; CL = 80h if the signs differ
	test	cl,80h
	jnz	xad8
	add	ax,[bp+si].UX_M0	; add the larger mantissa
	adc	bx,[bp+si].UX_M1
	adc	dx,[bp+si].UX_M2
	adc	di,[bp+si].UX_M3
	mov	ch,0			; CH = 1 to increment the exponent
	jnc	xad9
	rcr	di,1			; shift the carry back in
	rcr	dx,1
	rcr	bx,1
	rcr	ax,1
	jnc	xad7b
	or	al,1
xad7b:	inc	ch
	jmp	short xad9
xad8:	not	ax			; subtract it from the larger mantissa
	not	bx
	not	dx
	not	di
	stc
	adc	ax,[bp+si].UX_M0
	adc	bx,[bp+si].UX_M1
	adc	dx,[bp+si].UX_M2
	adc	di,[bp+si].UX_M3
	mov	ch,0
	jc	xad9			; no borrow
	not	ax			; the smaller mantissa was larger,
	not	bx			; so negate the result
	not	dx
	not	di
	add	ax,1
	adc	bx,0
	adc	dx,0
	adc	di,0
	mov	ch,80h			; CH = 80h to flip the sign
xad9:	mov	[bp+si].UX_M0,ax
	mov	[bp+si].UX_M1,bx
	mov	[bp+si].UX_M2,dx
	mov	[bp+si].UX_M3,di
	test	ch,ch
	jz	xad9b
	js	xad9a
	inc	[bp+si].UX_EXP
	jmp	short xad9b
xad9a:	xor	[bp+si].UX_SGN,80h
xad9b:	test	cl,80h			; was it a subtraction?
	jz	xad10			; no
	call	xNorm
	cmp	[bp+si].UX_M3,0
	jne	xad10
	mov	[bp+si].UX_SGN,0	; x - x is +0
xad10:	mov	di,si
	pop	si			; SI = the result UX
	cmp	si,di
	je	xad11
	call	xCopy			; copy the result if it's not there
xad11:	pop	di
	pop	bx
	ret
ENDPROC	xAdd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xMul
;
; Multiplies the UX at SI by the UX at DI (which may be the same UX); the
; 128-bit product of the mantissas is formed one 16-bit column at a time (the
; sum of the partial products whose word indexes add up to that column), in
; a 48-bit accumulator (CX:BX plus SX_MA), with the lower 64 bits stored in
; the SX_P buffer.
;
; xMulT is the same, except that it skips the 6 lowest partial products
; (columns 0-2, which occupy bits 0-65 of the product), so they can only
; affect the lowest bit or two of the 64-bit result (well beyond a double's
; 53 bits), making it suitable only for intermediate results (eg, in xPoly
; and the transcendental functions).
;
; Modifies:
;	AX, BX, CX, DX
;
XMULP	macro	i,j			;; add a(i)*b(j) to the accumulator
	mov	ax,[bp+si+UX_M0+(i)*2]
	mul	word ptr [bp+di+UX_M0+(j)*2]
	add	bx,ax
	adc	cx,dx
	adc	word ptr [bp+SX_MA],0
	endm

XMULC	macro	k			;; store column k and shift it out
	mov	[bp+SX_P+(k)*2],bx
	mov	bx,cx
	mov	cx,[bp+SX_MA]
	mov	word ptr [bp+SX_MA],0
	endm

DEFPROC	xMul
	mov	dl,0			; DL = 0 for an exact product
	jmp	short xmu
	DEFLBL	xMulT,near
	mov	dl,1			; DL = 1 for a truncated product
xmu:	mov	al,[bp+di].UX_SGN
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
	sub	bx,bx
	sub	cx,cx			; CX:BX = low 32 bits of accumulator
	mov	[bp+SX_MA],bx		; SX_MA = high word of accumulator
	test	dl,dl
	jz	xmu4
	mov	[bp+SX_P],bx		; for a truncated product, columns
	mov	[bp+SX_P+2],bx		; 0-2 are skipped
	mov	[bp+SX_P+4],bx
	jmp	xmu5
xmu4:	XMULP	0,0
	XMULC	0
	XMULP	0,1
	XMULP	1,0
	XMULC	1
	XMULP	0,2
	XMULP	1,1
	XMULP	2,0
	XMULC	2
xmu5:	XMULP	0,3
	XMULP	1,2
	XMULP	2,1
	XMULP	3,0
	XMULC	3
	XMULP	1,3
	XMULP	2,2
	XMULP	3,1
	XMULC	4
	XMULP	2,3
	XMULP	3,2
	XMULC	5
	XMULP	3,3
	mov	dx,cx			; DX:CX:BX:AX = the upper 64 bits
	mov	cx,bx
	mov	bx,[bp+SX_P+10]
	mov	ax,[bp+SX_P+8]
	test	dh,80h
	jnz	xmu6			; product is from 2^127 to 2^128
	shl	word ptr [bp+SX_P+6],1	; product is from 2^126 to 2^127,
	rcl	ax,1			; so shift it left 1 bit
	rcl	bx,1
	rcl	cx,1
	rcl	dx,1
	dec	[bp+si].UX_EXP
xmu6:	inc	[bp+si].UX_EXP
	mov	[bp+si].UX_M0,ax
	mov	[bp+si].UX_M1,bx
	mov	[bp+si].UX_M2,cx
	mov	[bp+si].UX_M3,dx
	mov	ax,[bp+SX_P]		; the lower 64 bits are "sticky"
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
; Divides the UX at SI by the UX at DI, producing a 64-bit quotient (in SX_MA)
; from the dividend (in SX_P) and the divisor (in SX_MB).
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
	jne	xdv9			; infinity / finite = infinity
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
	push	di
	push	si
	mov	si,di
	lea	bx,[bp+SX_MB]
	call	xMantPut		; SX_MB = v = B's mantissa (divisor)
	pop	si
	lea	bx,[bp+SX_P+8]
	call	xMantPut		; SX_P = u = A's mantissa * 2^64
	sub	ax,ax
	mov	[bp+SX_P],ax
	mov	[bp+SX_P+2],ax
	mov	[bp+SX_P+4],ax
	mov	[bp+SX_P+6],ax
	push	si
;
; If A's mantissa >= B's, then u = A's mantissa * 2^63 instead, so that the
; quotient is from 2^63 to 2^64; otherwise, the quotient is half as large, so
; we decrement the exponent.
;
	mov	di,6
xdv3a:	mov	ax,[bp+SX_P+8+di]
	cmp	ax,[bp+SX_MB+di]
	jne	xdv3b
	sub	di,2
	jnc	xdv3a
	jmp	short xdv3c		; the mantissas are equal
xdv3b:	jae	xdv3c
	dec	[bp+si].UX_EXP
	jmp	short xdv3d
xdv3c:	shr	word ptr [bp+SX_P+14],1
	rcr	word ptr [bp+SX_P+12],1
	rcr	word ptr [bp+SX_P+10],1
	rcr	word ptr [bp+SX_P+8],1
	rcr	word ptr [bp+SX_P+6],1
;
; Divide u by v, one 16-bit quotient digit at a time (Knuth's Algorithm D):
; for each digit j (from 3 down to 0), estimate qhat from the top two words of
; the current remainder and the top word of v, correct it with the next word
; of v, and then subtract qhat * v from the remainder, adding v back (and
; decrementing qhat) in the rare case that qhat was still one too large.
;
xdv3d:	mov	si,6			; SI = offset of u[j]
xdv4:	mov	dx,[bp+SX_P+si+8]	; DX:AX = u[j+4]:u[j+3]
	mov	ax,[bp+SX_P+si+6]
	mov	cx,[bp+SX_MB+6]		; CX = v[3]
	cmp	dx,cx
	jb	xdv4a
	mov	di,0FFFFh		; qhat = 0FFFFh
	add	ax,cx			; rhat = u[j+3] + v[3]
	jc	xdv5			; rhat is too large to matter
	jmp	short xdv4b
xdv4a:	div	cx
	xchg	di,ax			; DI = qhat
	xchg	ax,dx			; AX = rhat
xdv4b:	xchg	bx,ax			; BX = rhat
xdv4c:	mov	ax,[bp+SX_MB+4]
	mul	di			; DX:AX = qhat * v[2]
	cmp	dx,bx
	jb	xdv5
	ja	xdv4d
	cmp	ax,[bp+SX_P+si+4]
	jbe	xdv5
xdv4d:	dec	di			; qhat is too large
	add	bx,cx
	jnc	xdv4c
xdv5:	sub	bx,bx			; BX = carry
	IRP	k,<0,2,4,6>
	mov	ax,[bp+SX_MB+k]
	mul	di
	add	ax,bx
	adc	dx,0
	sub	[bp+SX_P+si+k],ax
	adc	dx,0
	mov	bx,dx
	ENDM
	sub	[bp+SX_P+si+8],bx
	jnc	xdv6
	dec	di			; qhat was one too large
	mov	ax,[bp+SX_MB]
	add	[bp+SX_P+si],ax
	mov	ax,[bp+SX_MB+2]
	adc	[bp+SX_P+si+2],ax
	mov	ax,[bp+SX_MB+4]
	adc	[bp+SX_P+si+4],ax
	mov	ax,[bp+SX_MB+6]
	adc	[bp+SX_P+si+6],ax
	adc	word ptr [bp+SX_P+si+8],0
xdv6:	mov	[bp+SX_MA+si],di	; q[j] = qhat
	sub	si,2
	jc	xdv7
	jmp	xdv4
xdv7:	pop	si
	lea	bx,[bp+SX_MA]
	call	xMantGet		; A's mantissa = the quotient
	mov	ax,[bp+SX_P]		; and any remainder is "sticky"
	or	ax,[bp+SX_P+2]
	or	ax,[bp+SX_P+4]
	or	ax,[bp+SX_P+6]
	pop	di
	jz	xdv10
	or	byte ptr [bp+si].UX_M0,1
xdv10:	ret
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
; Sets the UX at SX_A to its square root, using Newton's method: the initial
; estimate y is the 16-bit integer square root of the top 32 bits of x (which
; a few 16-bit divisions produce), refined to 32 bits with one more step using
; the top 48 bits, and then y = (y + x/y) / 2 makes it as precise as 64 bits
; allow (since each step doubles the number of correct bits).
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, SX_G, SX_H
;
DEFPROC	xSqrt
	mov	si,SX_A
	cmp	[bp+si].UX_CLS,UXC_NAN
	je	xsq0
	call	xIsZero
	jz	xsq0			; the square root of +/-0 is +/-0
	test	[bp+si].UX_SGN,80h
	jz	xsq1
	jmp	xInvalid		; negative values are invalid
xsq0:	ret
xsq1:	cmp	[bp+si].UX_CLS,UXC_INF
	je	xsq0
	XRUN
	XS	XO_COPY,XI_G,XI_A	; G = x
	XEND
	mov	si,SX_A
	mov	di,[bp+si].UX_M3
	mov	bx,[bp+si].UX_M2	; DI:BX = top 32 bits of the mantissa
	mov	dx,[bp+si].UX_M1	; DX = the next 16 bits
	mov	ax,[bp+si].UX_EXP
	sar	ax,1			; AX = exponent / 2 (rounded down)
	mov	[bp+si].UX_EXP,ax
	jc	xsq2			; the exponent is odd
	shr	di,1			; the exponent is even, so halve the
	rcr	bx,1			; mantissa
	rcr	dx,1
xsq2:	push	dx
	mov	cx,0FFFFh		; CX = y (an overestimate to start)
	cmp	di,cx
	je	xsq4
xsq3:	mov	dx,di
	mov	ax,bx
	div	cx			; AX = n / y
	add	ax,cx
	rcr	ax,1			; AX = (y + n/y) / 2
	cmp	ax,cx
	jae	xsq4			; it's no longer decreasing
	xchg	cx,ax
	jmp	xsq3
;
; CX is now the square root of the top 32 bits, accurate to 16 bits, so one
; more step, y = (y*2^16 + n/y) / 2, using the top 48 bits, makes it accurate
; to 32 bits.
;
xsq4:	sub	dx,dx
	mov	ax,di
	div	cx
	xchg	di,ax			; DI = top word of n/y
	mov	ax,bx
	div	cx
	xchg	bx,ax			; BX = next word of n/y
	pop	ax
	div	cx			; AX = last word of n/y
	add	bx,cx
	adc	di,0			; DI:BX:AX = n/y + y*2^16
	shr	di,1
	rcr	bx,1
	rcr	ax,1			; BX:AX = y
	test	di,di
	jz	xsq4a
	mov	bx,0FFFFh		; (in case y overflowed)
	mov	ax,bx
xsq4a:	mov	[bp+si].UX_M3,bx
	mov	[bp+si].UX_M2,ax
	sub	ax,ax
	mov	[bp+si].UX_M1,ax
	mov	[bp+si].UX_M0,ax	; A = y
	mov	cx,1
xsq5:	push	cx
	XRUN
	XS	XO_COPY,XI_H,XI_G
	XS	XO_DIV,XI_H,XI_A	; H = x / y
	XS	XO_ADD,XI_A,XI_H	; A = y + x/y
	XEND
	dec	[bp+SX_A].UX_EXP	; A = (y + x/y) / 2
	pop	cx
	loop	xsq5
xsq9:	ret
ENDPROC	xSqrt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xScript (see XRUN)
;
; Runs the "script" that follows the call, which is a series of 2-byte steps
; (see XS), ending with XEND.  Each step consists of an operation (XO_*) and
; a byte containing two UX indexes (XI_*): the high nibble selects the UX for
; SI and the low nibble selects the UX for DI.  For XO_INT and XO_K, the low
; nibble is a small integer (0-15) or a constant index (KI_*) instead (so DI is
; meaningless after those steps).
;
; This saves a lot of space, since each step would otherwise require 9 bytes
; of "MOV SI,offset; MOV DI,offset; CALL function".
;
; Modifies:
;	AX, BX, CX, DX, SI, DI (and anything the operations modify)
;

DEFPROC	xScript
	pop	bx			; BX -> script
xrn1:	mov	dx,cs:[bx]		; DL = operation, DH = UX indexes
	inc	bx
	inc	bx
	test	dl,dl
	jz	xrn9
	push	bx
	mov	bl,dh
	and	bx,0Fh
	mov	al,cs:[xUXOff+bx]
	cbw
	xchg	di,ax			; DI = UX selected by the low nibble
	mov	bl,dh
	mov	cl,4
	shr	bl,cl
	mov	al,cs:[xUXOff+bx]
	cbw
	xchg	si,ax			; SI = UX selected by the high nibble
	mov	bl,dl
	add	bx,bx
	call	cs:[xOpTbl-2+bx]
	pop	bx
	jmp	xrn1
xrn9:	jmp	bx

xNeg:	xor	[bp+si].UX_SGN,80h
	ret
xSub:	xor	[bp+di].UX_SGN,80h
	jmp	xAdd
xIntK:	mov	al,dh
	and	ax,0Fh
	cwd
	jmp	xFromLong
xConstK:mov	al,dh
	and	ax,0Fh
	mov	cl,size UX
	mul	cl
	add	ax,offset kConsts
	xchg	bx,ax
	jmp	xLoadK
ENDPROC	xScript

xUXOff	db	SX_A,SX_B,SX_C,SX_D,SX_F,SX_G,SX_H
	even
xOpTbl	dw	xCopy,xMul,xDiv,xAdd,xSub,xNeg,xIntK,xConstK,xSqrt
	dw	xMulT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xLoadK
;
; Loads the UX at SI with the UX constant at CS:BX (eg, kPiBy2).
;
; Modifies:
;	AX, BX, CX
;
DEFPROC	xLoadK
	push	si
	mov	cx,(size UX) SHR 1
xlk1:	mov	ax,cs:[bx]
	mov	[bp+si],ax
	inc	bx
	inc	bx
	inc	si
	inc	si
	loop	xlk1
	pop	si
	ret
ENDPROC	xLoadK

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xPoly
;
; Evaluates a polynomial in z (SX_D) using Horner's rule: C = c[0], and then
; C = C*z + c[i] for each remaining coefficient (alternating the accumulator
; between C and B, since xAdd's result lands in c[i], which is usually the
; larger term, without having to be copied).  The coefficients are doubles
; (see kSin, etc), highest degree first.
;
; Inputs:
;	CS:BX -> coefficients
;	CX = # of coefficients
;
; Outputs:
;	SX_C = result
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, SX_B
;
DEFPROC	xPoly
	mov	si,SX_C
	call	xLoadCS			; C = c[0]
	dec	cx
	mov	di,si			; DI = the accumulator (C or B)
xpl1:	push	cx
	push	bx
	mov	si,di
	mov	di,SX_D
	call	xMulT			; accumulator = accumulator * z
	mov	di,si
	xor	si,SX_C XOR SX_B	; SI = the other UX (B or C)
	pop	bx
	call	xLoadCS			; SI = c[i]
	call	xAdd			; SI = accumulator * z + c[i]
	mov	di,si			; which is the new accumulator
	pop	cx
	loop	xpl1
	cmp	di,SX_C
	je	xpl9
	mov	si,SX_C
	call	xCopy			; C = the accumulator
xpl9:	ret
ENDPROC	xPoly

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xLoadCS
;
; Loads the UX at SI with the double at CS:BX, and advances BX to the next.
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	xLoadCS
	push	cx
	push	es
	push	cs
	pop	es
	push	bx
	call	xLoad
	pop	bx
	add	bx,8
	pop	es
	pop	cx
	ret
ENDPROC	xLoadCS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xTrig
;
; Sets the UX at SX_A to its sine (AL = 0), cosine (AL = 1), or tangent
; (AL = 2).  The argument x is reduced to r = x - k*pi/2 (see below for
; how we keep this precise), where k is x/(pi/2)
; rounded to the nearest integer, so that abs(r) <= pi/4, and the quadrant
; q = k mod 4 determines whether sin(r) or cos(r) is used, and the sign:
; sin(x) is sin(r), cos(r), -sin(r), or -cos(r) for quadrants 0 through 3,
; and cos(x) is the same as sin(x) one quadrant later.  The tangent is
; sin(r)/cos(r) in even quadrants and -cos(r)/sin(r) in odd quadrants.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, SX_B, SX_C, SX_D, SX_F, SX_G, SX_H
;
DEFPROC	xTrig
	push	ax			; save the function (AL)
	mov	si,SX_A
	cmp	[bp+si].UX_CLS,UXC_NAN
	je	xtr0
	cmp	[bp+si].UX_CLS,UXC_INF
	jne	xtr1
	call	xInvalid		; infinity has no sine or cosine
xtr0:	pop	ax
	ret
xtr1:	XRUN
	XS	XO_COPY,XI_F,XI_A	; F = x
	XS	XO_K,XI_B,KI_2BYPI	; B = 2/pi
	XS	XO_MULT,XI_A,XI_B	; A = x / (pi/2)
	XEND
	mov	si,SX_A
	sub	al,al
	call	xRndInt			; A = k
	sub	dl,dl			; DL = q (k mod 4)
	call	xIsZero
	jz	xtr2
	XRUN
	XS	XO_COPY,XI_H,XI_A	; H = k (and SI -> H)
	XEND
	mov	dl,0			; (XRUN modified DL)
	mov	cx,63
	sub	cx,[bp+SX_A].UX_EXP
	jl	xtr2			; k is huge (and a multiple of 4)
	call	xShrN			; H's mantissa = abs(k)
	mov	dl,byte ptr [bp+SX_H].UX_M0
	and	dl,3
	test	[bp+SX_A].UX_SGN,80h
	jz	xtr2
	neg	dl			; k is negative
	and	dl,3
xtr2:	push	dx
;
; Since pi/2 is only accurate to 64 bits, we calculate r = x - k*pi/2 as
; (x - k*P1) - k*P2, where P1 is pi/2 truncated to 32 bits (so k*P1 is exact)
; and P2 is the next 64 bits of pi/2.
;
	XRUN
	XS	XO_COPY,XI_G,XI_A	; G = k
	XS	XO_K,XI_B,KI_PIBY2A	; B = P1
	XS	XO_MULT,XI_A,XI_B	; A = k*P1
	XS	XO_SUB,XI_F,XI_A	; F = x - k*P1
	XS	XO_K,XI_B,KI_PIBY2B	; B = P2
	XS	XO_MULT,XI_G,XI_B	; G = k*P2
	XS	XO_SUB,XI_F,XI_G	; F = r = (x - k*P1) - k*P2
	XS	XO_COPY,XI_D,XI_F
	XS	XO_MULT,XI_D,XI_D	; D = r^2
	XEND
	pop	dx
	pop	ax
	cmp	al,1
	jb	xtr4			; sine
	je	xtr3			; cosine
	push	dx			; tangent
	call	xSinSer
	XRUN
	XS	XO_COPY,XI_G,XI_A	; G = sin(r)
	XEND
	call	xCosSer			; A = cos(r)
	pop	dx
	test	dl,1
	jnz	xtr2a
	XRUN
	XS	XO_COPY,XI_B,XI_A	; B = cos(r)
	XS	XO_COPY,XI_A,XI_G	; A = sin(r)
	XS	XO_DIV,XI_A,XI_B	; A = sin(r)/cos(r)
	XEND
	ret
xtr2a:	XRUN
	XS	XO_DIV,XI_A,XI_G	; A = cos(r)/sin(r)
	XEND
	jmp	short xtr6
xtr3:	inc	dl			; cos(x) = sin(x) one quadrant later
xtr4:	push	dx
	test	dl,1
	jz	xtr5
	call	xCosSer
	jmp	short xtr5a
xtr5:	call	xSinSer
xtr5a:	pop	dx
	test	dl,2
	jz	xtr9
xtr6:	xor	[bp+SX_A].UX_SGN,80h
xtr9:	ret
;
; xSinSer and xCosSer evaluate the sine and cosine of r (in SX_F), with
; z = r^2 (in SX_D), using fdlibm's minimax polynomials (see kSin and kCos):
; sin(r) = r + r*z*P(z), and cos(r) = 1 - z/2 + z^2*Q(z).
;
xSinSer:mov	bx,offset kSin
	mov	cx,6
	call	xPoly			; C = P(z)
	XRUN
	XS	XO_MULT,XI_C,XI_D
	XS	XO_MULT,XI_C,XI_F	; C = r*z*P(z)
	XS	XO_COPY,XI_A,XI_F
	XS	XO_ADD,XI_A,XI_C	; A = r + r*z*P(z)
	XEND
	ret
xCosSer:mov	bx,offset kCos
	mov	cx,6
	call	xPoly			; C = Q(z)
	XRUN
	XS	XO_MULT,XI_C,XI_D
	XS	XO_MULT,XI_C,XI_D	; C = z^2*Q(z)
	XS	XO_COPY,XI_B,XI_D
	XEND
	dec	[bp+SX_B].UX_EXP	; B = z/2
	XRUN
	XS	XO_INT,XI_A,1
	XS	XO_SUB,XI_A,XI_B	; A = 1 - z/2
	XS	XO_ADD,XI_A,XI_C	; A = 1 - z/2 + z^2*Q(z)
	XEND
	ret
ENDPROC	xTrig

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xAtn
;
; Sets the UX at SX_A to its arctangent, using fdlibm's method: abs(x) is
; reduced (with id = 0 to 3) to t = (2x-1)/(2+x), (x-1)/(x+1),
; (x-1.5)/(1+1.5x), or -1/x, depending on whether it's below 11/16, 19/16,
; 39/16, or above, so that abs(t) < 7/16, and atan(x) = atan(c) + atan(t),
; where atan(c) is from kAtnHL (unless abs(x) < 7/16, which needs no
; reduction), and atan(t) is t - t*z*P(z), where z = t^2 (see kAtn).
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, SX_B, SX_C, SX_D, SX_F, SX_G
;
DEFPROC	xAtn
	mov	si,SX_A
	cmp	[bp+si].UX_CLS,UXC_NAN
	jne	xat0
	ret
xat0:	mov	al,0
	xchg	al,[bp+si].UX_SGN
	push	ax			; save the sign (and use abs(x))
	call	xIsZero
	jz	xat0a			; atan(0) is 0
	cmp	[bp+si].UX_CLS,UXC_INF
	jne	xat1
	mov	bx,offset kPiBy2
	call	xLoadK			; atan(infinity) is pi/2
xat0a:	jmp	xat8
xat1:	XRUN
	XS	XO_COPY,XI_F,XI_A	; F = x
	XS	XO_INT,XI_B,1		; B = 1
	XEND
	mov	si,SX_A
	mov	ax,[bp+si].UX_EXP
	mov	dx,[bp+si].UX_M3
	mov	bx,-1			; BX = id
	mov	di,offset kAtnT
xat2:	cmp	ax,cs:[di]		; is x below the next threshold?
	jl	xat3			; yes
	jg	xat2a
	cmp	dx,cs:[di+2]
	jb	xat3			; yes
xat2a:	inc	bx
	add	di,4
	cmp	bx,3
	jb	xat2
xat3:	push	bx
	test	bx,bx
	jl	xat5
	jg	xat3a
	inc	[bp+SX_A].UX_EXP	; id 0: A = 2x
	XRUN
	XS	XO_SUB,XI_A,XI_B	; A = 2x - 1
	XS	XO_INT,XI_B,2
	XS	XO_ADD,XI_F,XI_B	; F = 2 + x
	XEND
	jmp	short xat4
xat3a:	cmp	bx,2
	jae	xat3b
	XRUN				; id 1
	XS	XO_SUB,XI_A,XI_B	; A = x - 1
	XS	XO_INT,XI_B,1
	XS	XO_ADD,XI_F,XI_B	; F = x + 1
	XEND
	jmp	short xat4
xat3b:	ja	xat3c
	XRUN				; id 2
	XS	XO_INT,XI_B,3
	XEND
	dec	[bp+SX_B].UX_EXP	; B = 1.5
	XRUN
	XS	XO_COPY,XI_C,XI_B
	XS	XO_SUB,XI_A,XI_C	; A = x - 1.5
	XS	XO_MULT,XI_F,XI_B	; F = 1.5x
	XS	XO_INT,XI_B,1
	XS	XO_ADD,XI_F,XI_B	; F = 1 + 1.5x
	XEND
	jmp	short xat4
xat3c:	XRUN				; id 3
	XS	XO_NEG,XI_B,XI_B	; A = -1
	XS	XO_COPY,XI_A,XI_B
	XEND
xat4:	XRUN
	XS	XO_DIV,XI_A,XI_F	; A = t
	XEND
xat5:	XRUN
	XS	XO_COPY,XI_F,XI_A	; F = t
	XS	XO_COPY,XI_D,XI_A
	XS	XO_MULT,XI_D,XI_D	; D = z
	XEND
	mov	bx,offset kAtn
	mov	cx,11
	call	xPoly			; C = P(z)
	XRUN
	XS	XO_MULT,XI_C,XI_D
	XS	XO_MULT,XI_C,XI_F	; C = t*z*P(z)
	XS	XO_COPY,XI_A,XI_F
	XS	XO_SUB,XI_A,XI_C	; A = atan(t)
	XEND
	pop	bx
	test	bx,bx
	jl	xat8
	mov	cl,4
	shl	bx,cl
	add	bx,offset kAtnHL
	mov	si,SX_G
	call	xLoadCS			; G = atan(c) (high part)
	mov	si,SX_B
	call	xLoadCS			; B = atan(c) (low part)
	XRUN
	XS	XO_ADD,XI_A,XI_B
	XS	XO_ADD,XI_A,XI_G	; A = atan(c) + atan(t)
	XEND
xat8:	pop	ax
	xor	[bp+SX_A].UX_SGN,al	; restore the sign
	ret
ENDPROC	xAtn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xLn
;
; Sets the UX at SX_A to its natural logarithm.  With x = m * 2^e, where m is
; from sqrt(2)/2 to sqrt(2), ln(x) = e*ln(2) + 2s + s*z*P(z), where
; s = (m - 1)/(m + 1) and z = s^2, using fdlibm's minimax polynomial P
; (see kLog), which approximates 2/3 + 2z/5 + 2z^2/7 + ...  Zero produces
; -infinity (and a divide error, like the 8087), and negative values are
; invalid.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, SX_B, SX_C, SX_D, SX_F, SX_H
;
DEFPROC	xLn
	mov	si,SX_A
	cmp	[bp+si].UX_CLS,UXC_NAN
	jne	xln0
	ret
xln0:	call	xIsZero
	jnz	xln1
	or	byte ptr [bp+SX_FL],XF_ZE
	mov	[bp+si].UX_CLS,UXC_INF
	mov	[bp+si].UX_SGN,80h
	ret
xln1:	test	[bp+si].UX_SGN,80h
	jz	xln2
	jmp	xInvalid
xln2:	cmp	[bp+si].UX_CLS,UXC_INF
	je	xln9
	sub	ax,ax
	xchg	ax,[bp+si].UX_EXP	; AX = e, and A = m (from 1 to 2)
	cmp	[bp+si].UX_M3,0B505h	; m > sqrt(2)?
	jb	xln3			; no
	dec	[bp+si].UX_EXP		; yes, so use m/2
	inc	ax			; and e+1
xln3:	push	ax
	XRUN
	XS	XO_COPY,XI_F,XI_A	; F = m
	XS	XO_INT,XI_B,1
	XS	XO_ADD,XI_A,XI_B	; A = m + 1
	XS	XO_INT,XI_B,1
	XS	XO_SUB,XI_F,XI_B	; F = m - 1
	XS	XO_DIV,XI_F,XI_A	; F = s
	XS	XO_COPY,XI_D,XI_F
	XS	XO_MULT,XI_D,XI_D	; D = z = s^2
	XEND
	mov	bx,offset kLog
	mov	cx,7
	call	xPoly			; C = P(z)
	XRUN
	XS	XO_MULT,XI_C,XI_D
	XS	XO_MULT,XI_C,XI_F	; C = s*z*P(z)
	XS	XO_COPY,XI_A,XI_F
	XEND
	inc	[bp+SX_A].UX_EXP	; A = 2s
	XRUN
	XS	XO_ADD,XI_A,XI_C	; A = 2s + s*z*P(z)
	XEND
	pop	ax
	cwd
	mov	si,SX_B
	call	xFromLong		; B = e
	XRUN
	XS	XO_K,XI_C,KI_LN2
	XS	XO_MULT,XI_B,XI_C	; B = e*ln(2)
	XS	XO_ADD,XI_A,XI_B
	XEND
	ret
xln9:	ret
ENDPROC	xLn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; xExp
;
; Sets the UX at SX_A to e raised to its value.  With k = x/ln(2) rounded to
; the nearest integer, and r = x - k*ln(2) (so that abs(r) <= ln(2)/2), e^x is
; e^r * 2^k, where e^r = 1 + r + r*c/(2 - c), and c = r - z*P(z), with z = r^2
; and fdlibm's minimax polynomial P (see kExp).
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, SX_B, SX_C, SX_D, SX_F, SX_G
;
DEFPROC	xExp
	mov	si,SX_A
	cmp	[bp+si].UX_CLS,UXC_NAN
	je	xex9
	cmp	[bp+si].UX_CLS,UXC_INF
	je	xex1
	call	xIsZero
	jnz	xex2
	mov	ax,1			; e^0 is 1
	cwd
	jmp	xFromLong
xex1:	test	[bp+si].UX_SGN,80h	; e^infinity is infinity
	jz	xex9
xex1a:	mov	[bp+si].UX_SGN,0	; and e^-infinity is zero
	jmp	xSetZero
xex2:	cmp	[bp+si].UX_EXP,11	; abs(x) >= 2048?
	jl	xex3			; no
	test	[bp+si].UX_SGN,80h
	jnz	xex1a			; very negative values underflow
	mov	[bp+si].UX_CLS,UXC_INF	; and very positive values overflow
	or	byte ptr [bp+SX_FL],XF_OE
xex9:	ret
xex3:	XRUN
	XS	XO_COPY,XI_F,XI_A	; F = x
	XS	XO_K,XI_C,KI_INVLN2	; C = 1/ln(2)
	XS	XO_MULT,XI_F,XI_C	; F = x/ln(2)
	XS	XO_K,XI_C,KI_LN2	; C = ln(2)
	XEND
	mov	si,SX_F
	sub	al,al
	call	xRndInt			; F = k
	call	xToLong			; AX = k
	push	ax
	XRUN
	XS	XO_MULT,XI_F,XI_C	; F = k*ln(2)
	XS	XO_SUB,XI_A,XI_F	; A = r = x - k*ln(2)
	XS	XO_COPY,XI_F,XI_A	; F = r
	XS	XO_COPY,XI_D,XI_A
	XS	XO_MULT,XI_D,XI_D	; D = z = r^2
	XEND
	mov	bx,offset kExp
	mov	cx,5
	call	xPoly			; C = P(z)
	XRUN
	XS	XO_MULT,XI_C,XI_D	; C = z*P(z)
	XS	XO_COPY,XI_A,XI_F
	XS	XO_SUB,XI_A,XI_C	; A = c = r - z*P(z)
	XS	XO_COPY,XI_G,XI_A
	XS	XO_MULT,XI_G,XI_F	; G = r*c
	XS	XO_INT,XI_B,2
	XS	XO_SUB,XI_B,XI_A	; B = 2 - c
	XS	XO_DIV,XI_G,XI_B	; G = r*c / (2 - c)
	XS	XO_COPY,XI_A,XI_F
	XS	XO_ADD,XI_A,XI_G	; A = r + r*c/(2 - c)
	XS	XO_INT,XI_B,1
	XS	XO_ADD,XI_A,XI_B	; A = e^r
	XEND
	pop	ax
	add	[bp+SX_A].UX_EXP,ax	; A = e^r * 2^k
	ret
ENDPROC	xExp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; UX constants (rounded to 64-bit mantissas)
;
KI_PIBY2	equ	0
KI_PIBY2A	equ	1
KI_PIBY2B	equ	2
KI_LN2		equ	3
KI_2BYPI	equ	4
KI_INVLN2	equ	5

	DEFLBL	kConsts,word
kPiBy2	dw	0C235h,02168h,0DAA2h,0C90Fh	; pi/2
	dw	0
	db	0,UXC_FIN
kPiBy2a	dw	00000h,00000h,0DAA2h,0C90Fh	; pi/2 (P1, the first 32 bits)
	dw	0
	db	0,UXC_FIN
kPiBy2b	dw	08A2Eh,01319h,008D3h,085A3h	; pi/2 - P1 (P2)
	dw	-34
	db	0,UXC_FIN
kLn2	dw	079ACh,0D1CFh,017F7h,0B172h	; ln(2)
	dw	-1
	db	0,UXC_FIN
k2ByPi	dw	0152Ah,04E44h,0836Eh,0A2F9h	; 2/pi
	dw	-1
	db	0,UXC_FIN
kInvLn2	dw	0F0BCh,05C17h,03B29h,0B8AAh	; 1/ln(2)
	dw	0
	db	0,UXC_FIN

;
; fdlibm's minimax polynomial coefficients (doubles, highest degree first)
; for sin and cos (on [-pi/4,pi/4]), atan (on [-7/16,7/16]), log, and exp,
; and atan(c) (high and low parts) for c = 0.5, 1, 1.5, and infinity.
; kAtnT contains the thresholds (exponent and top mantissa word) for each
; atan reduction: 7/16, 11/16, 19/16, and 39/16.
;
kSin   	dw	0D57Ch,5ACFh,0D93Ah,3DE5h	; 1.58969099521155010221e-10
	dw	9CEBh,8A2Bh,0E5E6h,0BE5Ah	; -2.50507602534068634195e-08
	dw	0FE7Dh,57B1h,1DE3h,3EC7h	; 2.75573137070700676789e-06
	dw	61D5h,19C1h,01A0h,0BF2Ah	; -1.98412698298579493134e-04
	dw	0F8A6h,1110h,1111h,3F81h	; 8.33333333332248946124e-03
	dw	5549h,5555h,5555h,0BFC5h	; -1.66666666666666324348e-01
kCos   	dw	38D4h,0BE88h,0FAE9h,0BDA8h	; -1.13596475577881948265e-11
	dw	0B1C4h,0BDB4h,0EE9Eh,3E21h	; 2.08757232129817482790e-09
	dw	52ADh,809Ch,7E4Fh,0BE92h	; -2.75573143513906633035e-07
	dw	1590h,19CBh,01A0h,3EFAh	; 2.48015872894767294178e-05
	dw	5177h,16C1h,0C16Ch,0BF56h	; -1.38888888888741095749e-03
	dw	554Ch,5555h,5555h,3FA5h	; 4.16666666666666019037e-02
kAtn   	dw	0DA11h,0E322h,0AD3Ah,3F90h	; 1.62858201153657823623e-02
	dw	6C2Fh,2C6Ah,0B444h,0BFA2h	; -3.65315727442169155270e-02
	dw	0DEBh,2476h,7B4Bh,3FA9h	; 4.97687799461593236017e-02
	dw	0FD9Ah,52DEh,0DE2Dh,0BFADh	; -5.83357013379057348645e-02
	dw	3D51h,0A0D0h,0D66h,3FB1h	; 6.66107313738753120669e-02
	dw	9A6Dh,0AF74h,0B0F2h,0BFB3h	; -7.69187620504482999495e-02
	dw	206Eh,0C54Ch,45CDh,3FB7h	; 9.09088713343650656196e-02
	dw	1671h,0FE23h,71C6h,0BFBCh	; -1.11111104054623557880e-01
	dw	83FFh,9200h,4924h,3FC2h	; 1.42857142725034663711e-01
	dw	0EBC4h,9998h,9999h,0BFC9h	; -1.99999999998764832476e-01
	dw	550Dh,5555h,5555h,3FD5h	; 3.33333333333329318027e-01
kAtnHL 	dw	0BB4Fh,0561h,0AC67h,3FDDh	; 4.63647609000806093515e-01
	dw	65E2h,222Fh,2B7Fh,3C7Ah	; 2.26987774529616870924e-17
	dw	2D18h,5444h,21FBh,3FE9h	; 7.85398163397448278999e-01
	dw	5C07h,3314h,0A626h,3C81h	; 3.06161699786838301793e-17
	dw	0F69Bh,0D281h,730Bh,3FEFh	; 9.82793723247329054082e-01
	dw	0CBBDh,7AF0h,0788h,3C70h	; 1.39033110312309984516e-17
	dw	2D18h,5444h,21FBh,3FF9h	; 1.57079632679489655800e+00
	dw	5C07h,3314h,0A626h,3C91h	; 6.12323399573676603587e-17
kLog   	dw	5244h,0DF3Eh,0F112h,3FC2h	; 1.479819860511658591e-01
	dw	0C69Fh,0D078h,9A09h,3FC3h	; 1.531383769920937332e-01
	dw	03DEh,96CBh,4664h,3FC7h	; 1.818357216161805012e-01
	dw	78AFh,1D8Eh,71C5h,3FCCh	; 2.222219843214978396e-01
	dw	9359h,9422h,4924h,3FD2h	; 2.857142874366239149e-01
	dw	0FA04h,9997h,9999h,3FD9h	; 3.999999999940941908e-01
	dw	5593h,5555h,5555h,3FE5h	; 6.666666666666735130e-01
kExp   	dw	0A4D0h,72BEh,3769h,3E66h	; 4.13813679705723846039e-08
	dw	6BF1h,0C5D2h,0BD41h,0BEBBh	; -1.65339022054652515390e-06
	dw	0DE2Ch,0AF25h,566Ah,3F11h	; 6.61375632143793436117e-05
	dw	0BD93h,16BEh,0C16Ch,0BF66h	; -2.77777777770155933842e-03
	dw	553Eh,5555h,5555h,3FC5h	; 1.66666666666666019037e-01

kAtnT	dw	-2,0E000h,-1,0B000h,0,9800h,1,9C00h

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
	ret
ENDPROC	ddfpu_init

INIT	ends

DATA	segment para public 'DATA'

ddfpu_end	db	16 dup(0)

DATA	ends

	end
