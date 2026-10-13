;
; BASIC-DOS FPU Driver Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

;
; The FPU$ driver provides an FPUTBL (FPU function table) containing the
; offsets of all its 64-bit floating-point ("double") functions; all offsets
; are relative to the segment of the FPUTBL far pointer that IOCTL_GETFPU
; returns, so every function must be called with a FAR call using that segment.
;
; IOCTL_GETFPU also returns DL = # of FPUTBL entries and DH = FPU type
; (FPUTYPE_*), so that callers can tell when newer functions are available.
;
; DOUBLES ARE ALWAYS PASSED BY REFERENCE, NEVER BY VALUE.  Like strings, a
; double is passed as a far pointer to its 8 bytes, which is cheaper than four
; 16-bit pushes.  This applies to every interface in BASIC-DOS (eg, these FPU
; functions, sprintf's %f, and the code that the code generator produces), so
; there are no 64-bit pushes anywhere; please keep it that way.
;
; Functions that operate on the stack use the same conventions as the
; evaluators in long.asm: the first operand is pushed first, so the second
; operand is on top.  Every stack operand is 4 bytes: a long (stored in memory
; order, so the low word is on top) or a far pointer to a double (offset on
; top).  Results replace operands, and any operands not needed for the result
; are popped.
;
; Any function that produces a double stores it at ES:DI (which the caller
; must supply), and the result on the stack is a far pointer to ES:DI.  Only
; FPU_CVT2LD produces two doubles: the first (A) at ES:DI and the second (B)
; at ES:DI+8.  ES:DI may also be the address of any operand.  Operands are
; never modified (unless ES:DI points to one).
;
; The conversion functions are named after the corresponding conversions in
; BASIC-DOS's code generator (see genCvtType in genfpu.asm), where the "1" or
; "2" indicates whether the top operand (1) or the operand underneath it (2)
; is converted, while the other operand (if any) is left as-is; a "1" or "2"
; BEFORE the type indicates that 1 or 2 operands of that type are converted.
; Also, like long.asm, stack functions may modify AX, BX, CX, DX, SI, DI, and
; ES.
;
; The first 12 FPUTBL entries must remain in the same order as the OPEVAL_NEG
; through OPEVAL_GE operator indexes in cmd.inc, so that the code generator
; can use (OPEVAL - 1) * 2 as the offset of the corresponding FPUTBL entry.
;
; In the comments below, D is a double (ie, a pointer to one, on the stack),
; L is a long, and "+" marks a function that requires ES:DI.  Conversions to
; longs are rounded (with ties rounded away from zero, like MSBASIC).
;
FPUTBL		struc
FPU_NEG		dw	?	; 00h: +-A (D -> D)
FPU_EXP		dw	?	; 02h: +A^B (D,D -> D)
FPU_MUL		dw	?	; 04h: +A*B (D,D -> D)
FPU_DIV		dw	?	; 06h: +A/B (D,D -> D)
FPU_ADD		dw	?	; 08h: +A+B (D,D -> D)
FPU_SUB		dw	?	; 0Ah: +A-B (D,D -> D)
FPU_EQ		dw	?	; 0Ch: A=B (D,D -> L: -1 if true, 0 if not)
FPU_NE		dw	?	; 0Eh: A<>B (D,D -> L)
FPU_LT		dw	?	; 10h: A<B (D,D -> L)
FPU_GT		dw	?	; 12h: A>B (D,D -> L)
FPU_LE		dw	?	; 14h: A<=B (D,D -> L)
FPU_GE		dw	?	; 16h: A>=B (D,D -> L)
FPU_CVT1DL	dw	?	; 18h: conv1DoubleToLong (D -> L)
FPU_CVT2DL	dw	?	; 1Ah: conv2DoubleToLong (D,D -> L,L)
FPU_CVTL1D	dw	?	; 1Ch: +convLong1ToDouble (D,L -> D,D)
FPU_CVTL2D	dw	?	; 1Eh: +convLong2ToDouble (L,D -> D,D)
FPU_CVTD1L	dw	?	; 20h: convDouble1ToLong (L,D -> L,L)
FPU_CVTD2L	dw	?	; 22h: convDouble2ToLong (D,L -> L,L)
FPU_CVT1LD	dw	?	; 24h: +conv1LongToDouble (L -> D)
FPU_CVT2LD	dw	?	; 26h: +conv2LongToDouble (L,L -> D,D)
FPU_ABS		dw	?	; 28h: +ABS(A) (D -> D)
FPU_INT		dw	?	; 2Ah: +INT(A), largest integer <= A (D -> D)
FPU_FIX		dw	?	; 2Ch: +FIX(A), A truncated (D -> D)
FPU_SQR		dw	?	; 2Eh: +SQR(A), square root (D -> D)
FPU_ATOD	dw	?	; 30h: chars at DS:SI -> double at ES:DI
FPU_DTOA	dw	?	; 32h: double at DS:SI -> chars at ES:DI
FPU_TODEC	dw	?	; 34h: double at DS:SI -> digits at ES:DI
FPU_FROMDEC	dw	?	; 36h: digits at DS:SI -> double at ES:DI
FPU_SIN		dw	?	; 38h: +SIN(A), A in radians (D -> D)
FPU_COS		dw	?	; 3Ah: +COS(A), A in radians (D -> D)
FPU_TAN		dw	?	; 3Ch: +TAN(A), A in radians (D -> D)
FPU_ATN		dw	?	; 3Eh: +ATN(A), arctangent in radians (D -> D)
FPU_LOG		dw	?	; 40h: +LOG(A), natural logarithm (D -> D)
FPU_ETOX	dw	?	; 42h: +EXP(A), e raised to A (D -> D)
FPUTBL		ends

;
; FPU_ATOD converts the number at DS:SI, consisting of an optional sign,
; digits with an optional decimal point, and an optional exponent (E or D,
; followed by an optional sign and digits), to a double at ES:DI.  On success,
; carry is clear and SI points to the first character after the number.
; Carry is set if there were no digits (SI unchanged) or the number is out of
; range.  Modifies AX, BX, CX, DX.
;
; FPU_DTOA converts the double at DS:SI to chars at ES:DI, where CX is the
; buffer length, DX is the width (minimum # of chars), AL is the precision
; (0FFh if none, or 80h+n for BASIC-style with n significant digits, where
; n <= FPU_DIGITS), and AH contains sprintf-style flags (PF_LEFT, PF_ZERO, and
; PF_HASH, which displays a space in lieu of a minus sign, as BASIC's PRINT
; does).  Without a precision, the format is BASIC-style, with as many as
; FPU_DIGITS significant digits (eg, "-.25", "1E+20"), which requires no more
; than FPU_MAXCHARS chars; with a precision, the format is fixed-point with
; that many fractional digits (eg, "-0.25" for a precision of 2).  Returns DI
; pointing to the first byte after the last char.  Modifies AX, BX, CX, DX, SI.
;
; FPU_TODEC and FPU_FROMDEC are the FPU-dependent primitives that FPU_DTOA
; and FPU_ATOD rely on.
;
; FPU_TODEC converts the absolute value of the (finite) double at DS:SI to CL
; (0 to FPU_DIGITS) significant digits at ES:DI, rounded to nearest, returning
; CX = # of digits stored (zero if the value is zero) and AX = the decimal
; exponent of the first digit.  When CL is zero, the value is rounded to either
; zero (CX = 0) or one digit ("1") at the next higher decimal exponent.
; Modifies AX, BX, CX, DX.
;
; FPU_FROMDEC converts CX digits at DS:SI (up to 19), multiplied by 10 raised
; to the power in AX, to a double at ES:DI, negated if bit 7 of BL is set.
; Carry is set if the value is out of range.  Modifies AX, CX, DX, SI.
;
FPU_DIGITS	equ	15
FPU_MAXCHARS	equ	24

FPUTYPE_NONE	equ	0	; no FPU (functions emulated in software)
FPUTYPE_8087	equ	1	; 8087 FPU detected
