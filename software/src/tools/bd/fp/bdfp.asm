;
; BASIC-DOS Floating-Point Support for Microsoft C 4.00 Programs
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This replaces the arithmetic of Microsoft's alternate math libraries (eg,
; SLIBFA.LIB) with calls to the FPU$ driver (see fpu.inc), so that C programs
; compiled with /FPa use the same IEEE doubles as BASIC-DOS, and an
; 8087 when there is one.  It provides:
;
;   - The functions that compiled code calls for every floating-point
;     operation: a stack of values, with loads, stores, and arithmetic for
;     operands in memory (at DS:BX for names beginning with __f, SS:BX for
;     __s, and ES:BX for __e), and arithmetic for the top two values.
;   - The conversions that the C library calls (__fltin and __fltout).
;   - The math functions that FPU$ provides (see bdmath.c for the others).
;
; Assemble it with /MX, and /DMEM_S, /DMEM_M, /DMEM_C, or /DMEM_L for the
; small, medium, compact, or large memory model (see README.md in the BASIC-DOS
; repository's software/src/tools folder for how the libraries in TOOLS\LIB
; were made; on a BASIC-DOS hard disk, the include files are in \SRC\INC):
;
;	MASM /MX /DMEM_S /I\SRC\INC BDFP.ASM,BDFP.OBJ;
;
; DS and SS are always DGROUP in a C program, so SS:BX operands are DS:BX
; operands.  Every function preserves SI, DI, BP, and DS, as Microsoft's do,
; and __ftol preserves BX and CX, too.
;
	DOSFUNC equ 1
	include	dosapi.inc
	include	devapi.inc
	include	fpu.inc

IFDEF	MEM_M
sizeC	equ	1
sizeD	equ	0
ENDIF
IFDEF	MEM_C
sizeC	equ	0
sizeD	equ	1
ENDIF
IFDEF	MEM_L
sizeC	equ	1
sizeD	equ	1
ENDIF
IFNDEF	sizeC
sizeC	equ	0
sizeD	equ	0
ENDIF

FPDEPTH	equ	16			; # of values the stack holds

_TEXT	segment	byte public 'CODE'
_TEXT	ends
_DATA	segment	word public 'DATA'
_DATA	ends
;
; The C library's floating-point hooks (see __cinit): a segment that every
; module defines with the same size, which only a floating-point library
; fills in.  __cinit and exit call the first far pointer if it's set.
;
CDATA	segment	word common 'DATA'
	dw	0
	dd	__fpmath		; initialization and termination
	dd	0			; (Microsoft's data, for its init)
	dd	0			; (Microsoft's signal handler)
CDATA	ends

DGROUP	group	_DATA,CDATA

_DATA	segment
	extrn	__fac:qword		; where functions return doubles
;
; fpvec has a far pointer to each FPU$ function, at twice the function's
; FPUTBL offset.  fpsp points to the top value of the stack (fpstk), which
; grows upward.
;
fpvec	dd	(size FPUTBL)/2 dup (0)
fpsp	dw	offset DGROUP:fpstk - 8
fpstk	dq	FPDEPTH dup (?)
fpend	label	byte
fptmp	dq	?			; an operand converted from a single
fpname	db	"FPU$",0
;
; What __fltout returns a pointer to: the sign ('-' if negative), the
; position of the decimal point in the digits, a flag, and a pointer to the
; digits.  And for __fltin: flags, the number of characters converted, a
; long (unused), and the double.
;
outflt	dw	?,?,0,offset DGROUP:outstr
IF	sizeD
	dw	DGROUP
ENDIF
outstr	db	FPU_DIGITS+1 dup (?)
	even
inflt	dw	0,?,0,0
indbl	dq	?
_DATA	ends

IF	sizeC
	extrn	__fptrap:far
ELSE
	extrn	__fptrap:near
ENDIF

;
; FPU calls an FPU$ function, FPRET returns from a function that compiled
; code calls, and ARG1 is the offset from BP of a C function's first argument.
;
FPU	macro	fn
	call	dword ptr [fpvec+fn*2]
	endm

IF	sizeC
FPRET	macro
	db	0CBh			; (RETF, which MASM 4.00 lacks)
	endm
ARG1	equ	6
ELSE
FPRET	macro
	ret
	endm
ARG1	equ	4
ENDIF

;
; FPLABEL defines a public label for a function that compiled code calls,
; which is far in the medium and large models.
;
FPLABEL	macro	name
	public	name
IF	sizeC
name	label	far
ELSE
name	label	near
ENDIF
	endm

;
; ENTRY defines the three functions for an operand in memory, which jump to
; a common routine with the operand at ES:BX and a value in AX.
;
ENTRY	macro	name,value,routine
	FPLABEL	__f&name
	FPLABEL	__s&name
	push	ds
	pop	es
	FPLABEL	__e&name
	mov	ax,value
	jmp	routine
	endm

;
; A C function of one double, which an FPU$ function computes.
;
MATH1	macro	name,fn
	FPLABEL	_&name
	mov	bx,fn*2
	jmp	fpmath1
	endm

_TEXT	segment
	assume	cs:_TEXT,ds:DGROUP,ss:DGROUP,es:nothing

;
; __fpmath
;
; The C library calls this (always with a far call) with BX = 0 to
; initialize floating-point (before main), and with other values that don't
; matter here.  DS may be anything, but SS is DGROUP.
;
; We get the FPUTBL from the FPU$ driver, and make a far pointer for each of
; its functions.  Without the driver, the program ends with the library's
; "Floating point not loaded" message.
;
	public	__fpmath
__fpmath proc	far
	test	bx,bx
	jnz	fm9
	push	ds
	push	si
	push	di
	push	ss
	pop	ds
	mov	dx,offset DGROUP:fpname
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	fm8
	xchg	bx,ax			; BX = handle
	mov	si,offset DGROUP:fptmp	; DS:SI -> where the pointer goes
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETFPU
	int	21h
	pushf
	mov	ah,DOS_HDL_CLOSE
	int	21h
	popf
	jc	fm8
	push	ds
	pop	es
	mov	di,offset DGROUP:fpvec
	mov	cx,(size FPUTBL)/2
	mov	dx,word ptr [fptmp+2]	; DX = the FPUTBL's segment
	lds	si,dword ptr [fptmp]	; DS:SI -> FPUTBL
	cld
fm1:	movsw				; a function's offset
	xchg	ax,dx
	stosw				; and its segment
	xchg	dx,ax
	loop	fm1
	pop	di
	pop	si
	pop	ds
fm9:	clc
	ret
fm8:	jmp	__fptrap
__fpmath endp

;
; fppush
;
; Makes room for another value on the stack.
;
; Outputs:
;	DI -> the new top value (to be stored)
;
; Modifies:
;	DI
;
fppush	proc	near
	mov	di,[fpsp]
	add	di,8
	cmp	di,offset DGROUP:fpend
	jae	fm8			; too many values
	mov	[fpsp],di
	ret
fppush	endp

;
; Loads: push the double, single, 16-bit integer, or long at ES:BX.
;
	ENTRY	ldd,0,fpldd
	ENTRY	lds,0,fplds
	ENTRY	ldw,0,fpldw
	ENTRY	ldl,1,fpldw

fpldd	proc	near
	push	si
	push	di
	call	fppush
	mov	si,bx
	push	ds
	push	es
	pop	ds			; DS:SI -> the operand
	pop	es			; ES:DI -> the new top value
	cld
	movsw
	movsw
	movsw
	movsw
	push	es
	pop	ds
	pop	di
	pop	si
	FPRET
fpldd	endp

fplds	proc	near
	push	si
	push	di
	call	fppush
	call	fpcvsd			; convert the single to the top value
	pop	di
	pop	si
	FPRET
fplds	endp

;
; AX is 0 for a 16-bit integer, 1 for a long.
;
fpldw	proc	near
	push	si
	push	di
	test	ax,ax
	mov	ax,es:[bx]
	jz	lw1
	mov	dx,es:[bx+2]
	jmp	short lw2
lw1:	cwd
lw2:	call	fppush
	push	dx
	push	ax
	push	ds
	pop	es			; ES:DI -> the new top value
	FPU	FPU_CVT1LD
	add	sp,4
	pop	di
	pop	si
	FPRET
fpldw	endp

;
;
; fpcvsd
;
; Converts the single at ES:BX to a double at DS:DI, by widening its
; exponent and fraction (a denormal single becomes zero).
;
; Modifies:
;	AX, BX, CX, DX
;
fpcvsd	proc	near
	mov	ax,es:[bx]		; AX = fraction bits 15-0
	mov	dx,es:[bx+2]		; DX = sign, exponent, bits 22-16
	sub	bx,bx
	mov	[di],bx
	mov	[di+2],bx
	mov	[di+4],bx
	mov	bx,dx
	shl	bx,1
	mov	bl,bh
	mov	bh,0			; BX = exponent (0-255)
	test	bx,bx
	jnz	sd0
	sub	ax,ax			; zero (or denormal)
	jmp	short sd8
sd0:	push	bx
	mov	bx,ax
	mov	cl,13
	shl	bx,cl
	mov	[di+2],bx		; fraction bits 2-0, at bits 31-29
	mov	cl,3
	shr	ax,cl			; fraction bits 15-3
	mov	bx,dx
	mov	cl,13
	shl	bx,cl			; and bits 18-16, above them
	or	ax,bx
	mov	[di+4],ax
	mov	ax,dx
	and	ax,007Fh
	mov	cl,3
	shr	ax,cl			; AX = fraction bits 22-19
	pop	bx
	cmp	bl,255			; infinity or NaN?
	mov	cx,07FFh
	je	sd1			; yes
	lea	cx,[bx+1023-127]
sd1:	mov	bx,cx
	mov	cl,4
	shl	bx,cl			; the exponent, above them
	or	ax,bx
sd8:	and	dx,8000h		; and the sign
	or	ax,dx
	mov	[di+6],ax
	ret
fpcvsd	endp

;
; fpcvds
;
; Converts the double at DS:SI to a single at ES:BX, rounded to nearest (a
; value that's too small becomes zero, and one that's too large, infinity).
;
; Modifies:
;	AX, CX, DX, SI, DI
;
fpcvds	proc	near
	mov	dx,[si+6]
	mov	di,dx
	and	di,8000h		; DI = the sign
	and	dx,7FFFh
	mov	ax,dx
	mov	cl,4
	shr	ax,cl			; AX = exponent (0-2047)
	sub	ax,1023-127
	jle	ds8			; too small
	cmp	ax,255
	jb	ds1
	mov	dx,7F80h		; too large
	sub	cx,cx
	jmp	short ds3
;
; The single's fraction is the double's top 23 fraction bits: 4 in DX,
; 16 in the next word, and 3 in the one after that, whose next bit rounds
; (a carry out of the fraction adds 1 to the exponent, as it should).
;
ds1:	and	dx,000Fh
	push	ax
	mov	ax,[si+4]
	mov	cx,[si+2]
	shl	cx,1
	rcl	ax,1
	rcl	dx,1
	shl	cx,1
	rcl	ax,1
	rcl	dx,1
	shl	cx,1
	rcl	ax,1
	rcl	dx,1			; DX:AX = fraction (23 bits)
	shl	cx,1			; carry set to round up
	adc	ax,0
	adc	dx,0
	pop	si			; SI = exponent
	mov	cl,7
	shl	si,cl
	add	dx,si
	xchg	cx,ax
ds3:	or	dx,di
	mov	es:[bx],cx
	mov	es:[bx+2],dx
	ret
ds8:	mov	word ptr es:[bx],0
	mov	es:[bx+2],di
	ret
fpcvds	endp

;
; Stores: copy the top value to the double or single at ES:BX, and pop it if
; AX is 1.
;
	ENTRY	std,0,fpstd
	ENTRY	stdp,1,fpstd
	ENTRY	sts,0,fpsts
	ENTRY	stsp,1,fpsts

fpstd	proc	near
	push	si
	push	di
	mov	si,[fpsp]
	mov	di,bx
	cld
	movsw
	movsw
	movsw
	movsw
	jmp	short st1
fpsts	label	near
	push	si
	push	di
	mov	si,[fpsp]
	push	ax
	call	fpcvds
	pop	ax
st1:	test	ax,ax
	jz	st2
	sub	[fpsp],8
st2:	pop	di
	pop	si
	FPRET
fpstd	endp

;
; Arithmetic with an operand in memory: the top value becomes the result of
; the FPU$ function whose FPUTBL offset is AL, with the top value as its first
; operand and the double or single at ES:BX as its second, or the reverse if
; AH is 1.
;
	ENTRY	addd,FPU_ADD,fpopd
	ENTRY	subd,FPU_SUB,fpopd
	ENTRY	subdr,<FPU_SUB+100h>,fpopd
	ENTRY	muld,FPU_MUL,fpopd
	ENTRY	divd,FPU_DIV,fpopd
	ENTRY	divdr,<FPU_DIV+100h>,fpopd
	ENTRY	adds,FPU_ADD,fpops
	ENTRY	subs,FPU_SUB,fpops
	ENTRY	subsr,<FPU_SUB+100h>,fpops
	ENTRY	muls,FPU_MUL,fpops
	ENTRY	divs,FPU_DIV,fpops
	ENTRY	divsr,<FPU_DIV+100h>,fpops

fpops	proc	near
	push	si
	push	di
	push	ax
	mov	di,offset DGROUP:fptmp
	call	fpcvsd
	pop	ax
	mov	bx,di
	push	ds
	pop	es			; ES:BX -> the operand, as a double
	jmp	short op1
fpopd	label	near
	push	si
	push	di
op1:	mov	di,[fpsp]		; DS:DI -> the top value
	test	ah,ah
	jnz	op2
	push	ds
	push	di
	push	es
	push	bx
	jmp	short op3
op2:	push	es
	push	bx
	push	ds
	push	di
op3:	mov	bl,al
	mov	bh,0
	shl	bx,1
	push	ds
	pop	es			; ES:DI -> the result (the top value)
	call	dword ptr [fpvec+bx]
	add	sp,4
	pop	di
	pop	si
	FPRET
fpops	endp

;
; Arithmetic with the top two values, which the result replaces: the value
; under the top is the first operand of FPU$ function AL, and the top value is
; the second, or the reverse if AH is 1.
;
STACKOP	macro	name,value
	FPLABEL	name
	mov	ax,value
	jmp	short fpop2
	endm

	STACKOP	__fadd,FPU_ADD
	STACKOP	__fsub,FPU_SUB
	STACKOP	__fsubr,<FPU_SUB+100h>
	STACKOP	__fmul,FPU_MUL
	STACKOP	__fdiv,FPU_DIV
	STACKOP	__fdivr,<FPU_DIV+100h>

fpop2	proc	near
	push	si
	push	di
	mov	si,[fpsp]		; DS:SI -> the top value
	lea	di,[si-8]		; DS:DI -> the value under it
	mov	[fpsp],di
	test	ah,ah
	jnz	o21
	push	ds
	push	di
	push	ds
	push	si
	jmp	short o22
o21:	push	ds
	push	si
	push	ds
	push	di
o22:	mov	bl,al
	mov	bh,0
	shl	bx,1
	push	ds
	pop	es			; ES:DI -> the result
	call	dword ptr [fpvec+bx]
	add	sp,4
	pop	di
	pop	si
	FPRET
fpop2	endp

;
; __fcmp
;
; Compares the value under the top with the top value, and pops both.  The
; flags are those of a signed integer comparison of the two (compiled code
; follows this with JL, JG, JE, etc).
;
	FPLABEL	__fcmp
	push	si
	push	di
	mov	bx,FPU_LT*2
	call	fpcmp			; less?
	mov	bx,-1
	jnz	fc1			; yes
	mov	bx,FPU_GT*2
	call	fpcmp			; greater?
	mov	bx,1
	jnz	fc1			; yes
	dec	bx
fc1:	sub	[fpsp],16
	pop	di
	pop	si
	cmp	bx,0
	FPRET

fpcmp	proc	near
	mov	si,[fpsp]
	lea	ax,[si-8]
	push	ds
	push	ax
	push	ds
	push	si
	call	dword ptr [fpvec+bx]
	pop	ax			; AX = -1 if true, 0 if not
	pop	dx
	test	ax,ax
	ret
fpcmp	endp

;
; __fdup and __fchs: push a copy of the top value, and negate the top value.
;
	FPLABEL	__fdup
	mov	bx,[fpsp]
	push	ds
	pop	es
	jmp	fpldd

	FPLABEL	__fchs
	mov	bx,[fpsp]
	xor	byte ptr [bx+7],80h
	FPRET

;
; __ftol
;
; Pops the top value, and returns it in DX:AX as a long, truncated (as C
; requires, whereas FPU$'s conversion rounds).
;
	FPLABEL	__ftol
	push	bx
	push	cx
	push	si
	push	di
	mov	di,[fpsp]
	push	ds
	push	di
	push	ds
	pop	es			; ES:DI -> the top value
	FPU	FPU_FIX			; truncate it, where it is
	FPU	FPU_CVT1DL		; and convert it to a long
	pop	ax
	pop	dx
	sub	[fpsp],8
	pop	di
	pop	si
	pop	cx
	pop	bx
	FPRET

;
; The math functions that FPU$ provides.  Each takes a double (pow takes
; two) on the stack, and returns a pointer to the result, in __fac.
;
	MATH1	sqrt,FPU_SQR
	MATH1	sin,FPU_SIN
	MATH1	cos,FPU_COS
	MATH1	tan,FPU_TAN
	MATH1	atan,FPU_ATN
	MATH1	log,FPU_LOG
	MATH1	exp,FPU_ETOX
	MATH1	floor,FPU_INT

fpmath1	label	near
	push	bp
	mov	bp,sp
	push	si
	push	di
	lea	ax,[bp+ARG1]
	push	ss
	push	ax
	jmp	short ma1
	FPLABEL	_pow
	push	bp
	mov	bp,sp
	push	si
	push	di
	lea	ax,[bp+ARG1]
	push	ss
	push	ax
	add	ax,8
	push	ss
	push	ax
	mov	bx,FPU_EXP*2
ma1:	push	ds
	pop	es
	mov	di,offset DGROUP:__fac	; ES:DI -> the result
	call	dword ptr [fpvec+bx]
	add	sp,4
	mov	ax,offset DGROUP:__fac
IF	sizeD
	mov	dx,ds
ENDIF
	pop	di
	pop	si
	pop	bp
	FPRET

;
; __fltout(double)
;
; Returns a pointer to the value's sign, decimal point position, and digits
; (see outflt), for the C library's formatting.  FPU$ produces up to
; FPU_DIGITS significant digits; zero is the digit "0".
;
	FPLABEL	__fltout
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	ax,' '
	test	byte ptr [bp+ARG1+7],80h
	jz	fo1
	mov	al,'-'
fo1:	mov	[outflt],ax
;
; An infinity or NaN, which FPU$ can't convert, is a 1 followed by zeros.
;
	mov	ax,[bp+ARG1+6]
	and	ax,7FF0h
	cmp	ax,7FF0h
	mov	ax,310
	mov	cx,1
	mov	[outstr],'1'
	je	fo2
	lea	si,[bp+ARG1]		; DS:SI -> the value (SS = DS)
	push	ds
	pop	es
	mov	di,offset DGROUP:outstr	; ES:DI -> the digits
	mov	cl,FPU_DIGITS
	FPU	FPU_TODEC		; CX = # of digits, AX = exponent
	inc	ax			; AX = decimal point position
	test	cx,cx
	jnz	fo2
	mov	[outstr],'0'
	inc	cx
	sub	ax,ax
fo2:	mov	bx,cx
	mov	byte ptr [outstr+bx],0
	mov	[outflt+2],ax
	mov	ax,offset DGROUP:outflt
IF	sizeD
	mov	dx,ds
ENDIF
	pop	di
	pop	si
	pop	bp
	FPRET

;
; __fltin(string, length, scale, decimals) and __fltinf
;
; Returns a pointer to the number of characters converted and the double
; (see inflt), for atof and strtod.  Leading blanks are skipped, the length is
; ignored (the string ends with a null), and a string with no number is zero.
;
	FPLABEL	__fltin
	FPLABEL	__fltinf
	push	bp
	mov	bp,sp
	push	si
	push	di
	push	ds
	push	ds
	pop	es
IF	sizeD
	lds	si,[bp+ARG1]
ELSE
	mov	si,[bp+ARG1]
ENDIF
	cld
fi1:	lodsb
	cmp	al,' '
	je	fi1
	cmp	al,9
	je	fi1
	dec	si			; DS:SI -> the number
	mov	di,offset DGROUP:indbl	; ES:DI -> the double
	call	dword ptr es:[fpvec+FPU_ATOD*2]
	pop	ds
	jnc	fi2
	sub	ax,ax
	mov	word ptr [indbl],ax
	mov	word ptr [indbl+2],ax
	mov	word ptr [indbl+4],ax
	mov	word ptr [indbl+6],ax
fi2:	sub	si,[bp+ARG1]
	mov	[inflt+2],si
	mov	ax,offset DGROUP:inflt
IF	sizeD
	mov	dx,ds
ENDIF
	pop	di
	pop	si
	pop	bp
	FPRET

_TEXT	ends

	end
