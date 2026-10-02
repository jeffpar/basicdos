;
; BASIC-DOS FPU$ Driver Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Every FPUTBL function is tested, using FPU_ATOD to create the inputs and
; FPU_DTOA to check the outputs, along with the kernel's %f formatter (which
; also relies on FPU_DTOA), whether the FPU$ driver detected an 8087 or is
; using its software (emulation) functions.  The return code is the number of
; failures.
;
; NOTE: The expected results of transcendental functions were chosen so that
; they don't depend on the last bit of precision, since PCjs's 8087 emulation
; uses 64-bit doubles internally (instead of 80-bit extended precision).
;
	include	macros.inc
	include	dosapi.inc
	include	devapi.inc
	include	fpu.inc

CODE    SEGMENT

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

	org	100h

;
; FCALL calls the FPUTBL function at the specified offset, and FCALLD does
; the same for functions that produce doubles, after pointing ES:DI at numR.
;
FCALL	macro	fn
	mov	bx,fn
	call	getFunc
	call	dword ptr [funcPtr]
	endm

FCALLD	macro	fn
	push	ds
	pop	es
	mov	di,offset numR
	FCALL	fn
	endm

;
; PUSHD pushes a pointer to the double at the specified address (doubles are
; always passed by reference), and PUSHL pushes the long with the specified
; high and low words.
;
PUSHD	macro	addr
	push	ds
	mov	ax,offset addr
	push	ax
	endm

PUSHL	macro	hi,lo
	mov	ax,hi
	push	ax
	mov	ax,lo
	push	ax
	endm

;
; To conserve MASM symbol space, these macros don't define any labels; their
; strings follow the call to the corresponding "Inline" function instead.
;
; NUMS converts as many as two strings to doubles (numA and numB).
;
NUMS	macro	a,b
	call	numsInline
	db	a,0
	IFNB	<b>
	db	b,0
	ENDIF
	db	0
	endm

;
; CHKD prints the double (whose pointer is) on top of the stack, compares it
; to the expected string, and pops it; CHKL does the same for a long (after
; converting it to a double).
;
CHKD	macro	expect
	call	checkDInline
	db	expect,0
	add	sp,4
	endm

CHKL	macro	expect
	FCALLD	FPU_CVT1LD
	CHKD	<expect>
	endm

BEGIN	macro	desc
	call	beginInline
	db	desc,": ",0
	endm

;
; Test macros for the common cases: TESTD tests a function that takes one
; or two doubles and returns a double; TESTL tests a function that returns a
; long; TESTA tests FPU_ATOD and FPU_DTOA.
;
TESTD	macro	desc,fn,expect,a,b
	BEGIN	<desc>
	NUMS	<a>,<b>
	PUSHD	numA
	IFNB	<b>
	PUSHD	numB
	ENDIF
	FCALLD	fn
	CHKD	<expect>
	call	checkSP
	endm

TESTL	macro	desc,fn,expect,a,b
	BEGIN	<desc>
	NUMS	<a>,<b>
	PUSHD	numA
	IFNB	<b>
	PUSHD	numB
	ENDIF
	FCALL	fn
	CHKL	<expect>
	call	checkSP
	endm

TESTA	macro	str,expect
	BEGIN	<str>
	NUMS	<str>
	PUSHD	numA
	CHKD	<expect>
	call	checkSP
	endm

;
; TESTF tests the kernel's %f formatter, by passing the specified format
; string and double to DOS_UTL_SPRINTF (which expects the format string to
; follow the INT, just like PRINTF).
;
TESTF	macro	fmt,val,expect
	LOCAL	f
	BEGIN	<fmt>
	NUMS	<val>
	PUSHD	numA
	mov	di,offset outBuf
	mov	cx,FPU_MAXCHARS
	mov	bx,offset f
	mov	ah,DOS_UTL_SPRINTF
	int	INT_DOSUTIL
f	db	fmt,0
	add	sp,4
	xchg	bx,ax
	mov	outBuf[bx],0
	call	checkOutInline
	db	expect,0
	call	checkSP
	endm

DEFPROC	main
	mov	dx,offset fpuName
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	m0
	xchg	bx,ax			; BX = handle
	mov	si,offset fpuTable
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETFPU
	int	21h
	pushf
	mov	ah,DOS_HDL_CLOSE
	int	21h
	popf
	jnc	m1
m0:	mov	dx,offset noDriver
	call	print
	mov	al,1
	jmp	m9

m1:	mov	[fpuInfo],dx
	mov	dx,offset hwType
	cmp	byte ptr [fpuInfo+1],FPUTYPE_8087
	je	m2
	mov	dx,offset swType
m2:	call	print
	mov	dx,offset fpuMsg
	call	print
	cmp	byte ptr [fpuInfo],(size FPUTBL) SHR 1
	jae	m3
	mov	dx,offset fewFuncs
	call	print
	inc	[failures]
	jmp	m8
m3:	cmp	byte ptr [fpuInfo+1],FPUTYPE_8087
	je	m4
	call	swTests
m4:	call	fpuTests

m8:	mov	al,[failures]
m9:	mov	ah,DOS_PSP_RETURN
	int	21h
ENDPROC	main

DEFPROC	fpuTests
	TESTA	"0","0"
	TESTA	"-0.75","-.75"
	TESTA	"123.456E2","12345.6"
	TESTA	"2.5D-3",".0025"
	TESTA	"1e20","1E+20"
	TESTA	"1E-5","1E-05"
	TESTA	".0001",".0001"
	TESTA	"123456789012345","123456789012345"
	TESTA	"1234567890123456","1.23456789012346E+15"
	TESTA	"1E-300","1E-300"

	TESTF	"%f","3.14159","3.14159"
	TESTF	"%.2f","3.14159","3.14"
	TESTF	"%8.2f","3.14159","    3.14"
	TESTF	"%-8.2f|","3.14159","3.14    |"
	TESTF	"%08.2f","-3.14159","-0003.14"
	TESTF	"%2.2f","123.456","123.46"
	TESTF	"%.5f","123.456","123.45600"
	TESTF	"%#f","2.5"," 2.5"
	TESTF	"%#f","-2.5","-2.5"
	TESTF	"%.0f","2.5","2"
	TESTF	"%.2f","0.004","0.00"
	TESTF	"%.2f","0.0051","0.01"
	TESTF	"%.2f","9.996","10.00"
	TESTF	"%.3f","0","0.000"
	TESTF	"%.1f","1E20","100000000000000000000.0"
	TESTF	"%f","1E20","1E+20"
	TESTF	"x=%f!","0.25","x=.25!"

	TESTD	"1.5+2.25",FPU_ADD,"3.75","1.5","2.25"
	TESTD	"1.5-2.25",FPU_SUB,"-.75","1.5","2.25"
	TESTD	"1.5*-2",FPU_MUL,"-3","1.5","-2"
	TESTD	"1/3",FPU_DIV,".333333333333333","1","3"
	TESTD	"2/3",FPU_DIV,".666666666666667","2","3"
	TESTD	"-(2.5)",FPU_NEG,"-2.5","2.5"
	TESTD	"ABS(-2.5)",FPU_ABS,"2.5","-2.5"
	TESTD	"2^10",FPU_EXP,"1024","2","10"
	TESTD	"2^-2",FPU_EXP,".25","2","-2"
	TESTD	"-3^3",FPU_EXP,"-27","-3","3"
	TESTD	"2^.5",FPU_EXP,"1.4142135623731","2",".5"
	TESTD	"10^2.5",FPU_EXP,"316.227766016838","10","2.5"
	TESTD	"0^.5",FPU_EXP,"0","0",".5"
	TESTD	"SQR(2)",FPU_SQR,"1.4142135623731","2"
	TESTD	"INT(-2.5)",FPU_INT,"-3","-2.5"
	TESTD	"INT(2.7)",FPU_INT,"2","2.7"
	TESTD	"FIX(-2.5)",FPU_FIX,"-2","-2.5"
	TESTD	"SIN(0)",FPU_SIN,"0","0"
	TESTD	"COS(0)",FPU_COS,"1","0"
	TESTD	"COS(1)",FPU_COS,".54030230586814","1"
	TESTD	"TAN(1)",FPU_TAN,"1.5574077246549","1"
	TESTD	"SIN(-2)",FPU_SIN,"-.909297426825682","-2"
	TESTD	"COS(-2)",FPU_COS,"-.416146836547142","-2"
	TESTD	"TAN(-2)",FPU_TAN,"2.18503986326152","-2"
	TESTD	"ATN(1)",FPU_ATN,".785398163397448","1"
	TESTD	"ATN(-.5)",FPU_ATN,"-.463647609000806","-.5"
	TESTD	"ATN(1E10)",FPU_ATN,"1.5707963266949","1E10"
	TESTD	"LOG(10)",FPU_LOG,"2.30258509299405","10"
	TESTD	"LOG(1E-10)",FPU_LOG,"-23.0258509299405","1E-10"
	TESTD	"EXP(-1)",FPU_ETOX,".367879441171442","-1"
	TESTD	"EXP(10)",FPU_ETOX,"22026.4657948067","10"

	TESTL	"1.5<2.25",FPU_LT,"-1","1.5","2.25"
	TESTL	"1.5>2.25",FPU_GT,"0","1.5","2.25"
	TESTL	"2=2",FPU_EQ,"-1","2","2"
	TESTL	"2<>2",FPU_NE,"0","2","2"
	TESTL	"2<=2",FPU_LE,"-1","2","2"
	TESTL	"1>=2",FPU_GE,"0","1","2"
	TESTL	"CVT1DL(7.5)",FPU_CVT1DL,"8","7.5"
	TESTL	"CVT1DL(-7.4)",FPU_CVT1DL,"-7","-7.4"
	TESTL	"CVT1DL(2.5)",FPU_CVT1DL,"3","2.5"
	TESTL	"CVT1DL(-2.5)",FPU_CVT1DL,"-3","-2.5"
	TESTL	"CVT1DL(-.5)",FPU_CVT1DL,"-1","-.5"
	TESTL	"CVT1DL(-1E9-.5)",FPU_CVT1DL,"-1000000001","-1000000000.5"

;
; The largest double < .5 must round to 0 (we don't use ATOD to create it,
; since ".49999999999999994" requires all 64 bits of 8087 precision to convert
; correctly).
;
	BEGIN	"CVT1DL(.5-2^-54)"
	PUSHD	nearHalf
	FCALL	FPU_CVT1DL
	CHKL	"0"
	call	checkSP

	BEGIN	"CVT2DL(1.6,-2.6)"
	NUMS	"1.6","-2.6"
	PUSHD	numA
	PUSHD	numB
	FCALL	FPU_CVT2DL
	CHKL	"-3"
	CHKL	"2"
	call	checkSP

	BEGIN	"CVTL1D(1.5,7)"
	NUMS	"1.5"
	PUSHD	numA
	PUSHL	0,7
	FCALLD	FPU_CVTL1D
	CHKD	"7"
	CHKD	"1.5"
	call	checkSP

	BEGIN	"CVTL2D(7,1.5)"
	NUMS	"1.5"
	PUSHL	0,7
	PUSHD	numA
	FCALLD	FPU_CVTL2D
	CHKD	"1.5"
	CHKD	"7"
	call	checkSP

	BEGIN	"CVTD1L(5,2.4)"
	NUMS	"2.4"
	PUSHL	0,5
	PUSHD	numA
	FCALL	FPU_CVTD1L
	CHKL	"2"
	CHKL	"5"
	call	checkSP

	BEGIN	"CVTD2L(-9.5,5)"
	NUMS	"-9.5"
	PUSHD	numA
	PUSHL	0,5
	FCALL	FPU_CVTD2L
	CHKL	"5"
	CHKL	"-10"
	call	checkSP

	BEGIN	"CVT2LD(3,-4)"
	PUSHL	0,3
	PUSHL	0FFFFh,0FFFCh
	FCALLD	FPU_CVT2LD
	CHKD	"-4"
	CHKD	"3"
	call	checkSP

	BEGIN	"A+B (by reference)"	; operands must not be modified
	NUMS	"1.5","2.25"
	PUSHD	numA
	PUSHD	numB
	FCALLD	FPU_ADD
	CHKD	"3.75"
	PUSHD	numA
	CHKD	"1.5"
	PUSHD	numB
	CHKD	"2.25"
	call	checkSP

	BEGIN	"A=A*A"			; result may replace an operand
	NUMS	"1.5"
	PUSHD	numA
	PUSHD	numA
	push	ds
	pop	es
	mov	di,offset numA
	FCALL	FPU_MUL
	CHKD	"2.25"
	PUSHD	numA
	CHKD	"2.25"
	call	checkSP

	BEGIN	"ATOD(abc)"
	mov	si,offset notNum
	mov	di,offset numA
	FCALL	FPU_ATOD		; carry should be set
	cmc
	call	result
	BEGIN	"ATOD(1E400)"
	mov	si,offset bigNum
	mov	di,offset numA
	FCALL	FPU_ATOD		; carry should be set
	cmc
	call	result
	ret
ENDPROC	fpuTests

DEFPROC	swTests
	mov	dx,offset negTest
	call	print
	PUSHD	sw15
	FCALLD	FPU_NEG			; numR = -(sw15)
	pop	ax
	pop	bx
	cmp	ax,offset numR		; is the result pointer numR?
	jne	sw1
	mov	si,offset numR
	mov	dx,0BFF8h		; -1.5 is BFF8000000000000h
	call	checkBits
	jc	sw1
	mov	si,offset sw15
	mov	dx,3FF8h		; 1.5 is 3FF8000000000000h
	call	checkBits		; (sw15 must not be modified)
	jc	sw1
	PUSHD	numR
	FCALLD	FPU_ABS			; numR = ABS(numR)
	add	sp,4
	mov	si,offset numR
	mov	dx,3FF8h
	call	checkBits
	jnc	sw2
sw1:	stc
sw2:	call	result
	ret
ENDPROC	swTests

;
; beginInline
;
; Prints the description that follows the call, and records SP (adjusted for
; our return address) for checkSP.
;
DEFPROC	beginInline
	pop	dx			; DX -> description
	call	skipInline
	call	print0
	mov	ax,sp
	inc	ax
	inc	ax
	mov	[spBegin],ax
	ret
ENDPROC	beginInline

;
; numsInline
;
; Converts the strings that follow the call (up to an empty string) to
; doubles in numA and numB.
;
DEFPROC	numsInline
	pop	si			; SI -> strings
	mov	di,offset numA
ni1:	cmp	byte ptr [si],0
	je	ni9
	call	atod			; (which advances SI past the number)
ni2:	lodsb
	test	al,al
	jnz	ni2
	mov	di,offset numB
	jmp	ni1
ni9:	inc	si			; skip the empty string
	jmp	si
ENDPROC	numsInline

;
; checkDInline, checkOutInline
;
; Same as checkD and checkOut, but with the expected string following the call.
;
DEFPROC	checkDInline
	pop	dx			; DX -> expected string
	call	skipInline
	jmp	checkD
	DEFLBL	checkOutInline,near
	pop	dx
	call	skipInline
	jmp	checkOut
ENDPROC	checkDInline

;
; skipInline
;
; Pushes the address that follows the string at DX as the caller's caller's
; return address (and preserves DX); modifies AL, CX, and SI.
;
DEFPROC	skipInline
	pop	cx			; CX = our return address
	mov	si,dx
si1:	lodsb
	test	al,al
	jnz	si1
	push	si			; caller's new return address
	jmp	cx
ENDPROC	skipInline

;
; checkSP
;
; Verifies that SP matches the value recorded by beginInline, and then reports.
;
DEFPROC	checkSP
	mov	ax,sp
	inc	ax
	inc	ax
	cmp	ax,[spBegin]
	je	report
	mov	dx,offset badStack
	call	print
	inc	[failures]
	mov	sp,[spBegin]		; recover (we can't return normally)
	jmp	m8
ENDPROC	checkSP

;
; result
;
; Counts a failure if carry is set, and then reports.
;
DEFPROC	result
	jnc	report
	inc	[failures]
	DEFLBL	report,near
;
; report
;
; Prints "passed" or "failed", depending on whether any failures occurred
; since the last report.
;
	mov	dx,offset passed
	mov	al,[failures]
	cmp	al,[lastFailures]
	je	rs9
	mov	[lastFailures],al
	mov	dx,offset failed
rs9:	call	print
	ret
ENDPROC	result

;
; checkD
;
; Converts the double (whose pointer is) above our return address to a
; string, prints it, and compares it to the expected string at DX.
;
DEFPROC	checkD
	push	dx
	mov	bx,FPU_DTOA
	call	getFunc			; (which modifies AX)
	push	ds
	pop	es
	mov	di,offset outBuf
	mov	cx,FPU_MAXCHARS		; CX = buffer length
	mov	ax,0FFh			; AL = no precision, AH = no flags
	sub	dx,dx			; DX = no width
	mov	bx,sp
	push	ds
	lds	si,[bx+4]		; DS:SI -> double
	call	dword ptr cs:[funcPtr]
	pop	ds
	mov	byte ptr [di],0
	pop	dx
	DEFLBL	checkOut,near
;
; checkOut
;
; Prints the string in outBuf and compares it to the expected string at DX.
;
	mov	[expectPtr],dx
	mov	dx,offset outBuf
	call	print0
	mov	dl,' '
	call	printChar
	mov	si,[expectPtr]
	mov	di,offset outBuf
cd1:	lodsb
	scasb
	jne	cd8
	test	al,al
	jnz	cd1
	ret
cd8:	mov	dx,offset expected
	call	print0
	mov	dx,[expectPtr]
	call	print0
	mov	dl,' '
	call	printChar
	inc	[failures]
	ret
ENDPROC	checkD

;
; checkBits
;
; Sets carry unless the double at SI is all zeros except for the top word,
; which must match DX.
;
DEFPROC	checkBits
	lodsw
	or	ax,[si]
	or	ax,[si+2]
	jnz	cb8
	cmp	[si+4],dx
	je	cb9
cb8:	stc
cb9:	ret
ENDPROC	checkBits

;
; atod
;
; Converts the string at SI to a double at DI, counting a failure if the
; conversion fails.
;
DEFPROC	atod
	push	ds
	pop	es			; ES:DI -> double
	FCALL	FPU_ATOD
	jnc	at9
	inc	[failures]
at9:	ret
ENDPROC	atod

;
; getFunc
;
; Sets funcPtr to the FPUTBL function at offset BX.
;
DEFPROC	getFunc
	push	si
	push	es
	les	si,[fpuTable]
	mov	ax,es:[si+bx]
	mov	[funcPtr].OFF,ax
	mov	[funcPtr].SEG,es
	pop	es
	pop	si
	ret
ENDPROC	getFunc

DEFPROC	print
	mov	ah,DOS_TTY_PRINT
	int	21h
	ret
ENDPROC	print

;
; print0
;
; Prints the null-terminated string at DX.
;
DEFPROC	print0
	push	si
	mov	si,dx
p01:	lodsb
	test	al,al
	jz	p09
	mov	dl,al
	call	printChar
	jmp	p01
p09:	pop	si
	ret
ENDPROC	print0

DEFPROC	printChar
	mov	ah,DOS_TTY_WRITE
	int	21h
	ret
ENDPROC	printChar

fpuName		db	"FPU$",0
noDriver	db	"FPU$ driver not found",13,10,'$'
hwType		db	"8087$"
swType		db	"Emulation$"
fpuMsg		db	" functions",13,10,'$'
fewFuncs	db	"Too few functions",13,10,'$'
negTest		db	"NEG/ABS test $"
badStack	db	"stack mismatch",13,10,'$'
passed		db	"passed",13,10,'$'
failed		db	"failed",13,10,'$'
expected	db	"expected ",0
notNum		db	"abc",0
bigNum		db	"1E400",0

	even
sw15		dq	3FF8000000000000h	; 1.5
nearHalf	dq	3FDFFFFFFFFFFFFFh	; .5-2^-54 (.49999999999999994)
fpuTable	dd	0
funcPtr		dd	0
fpuInfo		dw	0
spBegin		dw	0
expectPtr	dw	0
failures	db	0
lastFailures	db	0
	even
numA		dq	0
numB		dq	0
numR		dq	0,0		; results (FPU_CVT2LD produces two)
outBuf		db	FPU_MAXCHARS+1 dup (0)
	even

	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
