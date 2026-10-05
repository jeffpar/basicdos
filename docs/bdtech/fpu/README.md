---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Floating-Point Interface
permalink: /docs/bdtech/fpu/
---

{% include header.html %}

The FPU$ driver provides BASIC-DOS's floating-point support, using IEEE 754 64-bit ("double") values.  At initialization, it checks for an 8087 coprocessor; if one is present, its functions use the 8087, and otherwise they emulate it in software, with identical results for arithmetic (math functions are within 1 ulp).  BASIC-DOS has no single-precision type and no Microsoft Binary Format (MBF) code.

### Obtaining the Function Table

Open the FPU$ device and issue IOCTL_GETFPU (E1h), with DS:SI pointing to a doubleword that receives a far pointer to the FPU function table (FPUTBL):

	mov	dx,offset FPU_NAME	; "FPU$"
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	nofpu			; FPU$ driver not loaded
	xchg	bx,ax			; BX = handle
	mov	si,offset FPU_TABLE	; DS:SI -> dword for the FPUTBL pointer
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETFPU
	int	21h			; DL = # entries, DH = FPU type
	mov	ah,DOS_HDL_CLOSE
	int	21h

DH returns the FPU type (FPUTYPE_NONE, 0, for software emulation, or FPUTYPE_8087, 1), and DL returns the number of FPUTBL entries, so that callers can tell when newer functions are available.

Each FPUTBL entry is the offset of a function, relative to the segment of the FPUTBL pointer, so every function must be called with a far call using that segment.

### Calling Conventions

Doubles are always passed by reference, never by value: like a string, a double is passed as a far pointer to its 8 bytes.  This applies to every BASIC-DOS interface (eg, sprintf's `%f`), so there are no 64-bit pushes anywhere.

Most functions operate on operands on the stack:

- The first operand is pushed first, so the second operand is on top
- Every stack operand is 4 bytes: either a 32-bit integer ("long", low word on top) or a far pointer to a double (offset on top)
- Results replace operands, and any operands not needed for the result are popped
- A function that produces a double stores it at ES:DI (which the caller must supply, and which may be the address of an operand), and the result on the stack is a far pointer to ES:DI; operands are otherwise never modified
- Conversions to longs are rounded, with halves rounded away from zero (like Microsoft BASIC)
- Stack functions may modify AX, BX, CX, DX, SI, DI, and ES

### Function Table

In the descriptions below, D is a double (ie, a far pointer to one), L is a long, and "+" marks a function that requires ES:DI.

| Offset | Name | Description |
|--------|------|-------------|
| 00h | FPU_NEG | +-A (D -> D) |
| 02h | FPU_EXP | +A^B (D,D -> D) |
| 04h | FPU_MUL | +A*B (D,D -> D) |
| 06h | FPU_DIV | +A/B (D,D -> D) |
| 08h | FPU_ADD | +A+B (D,D -> D) |
| 0Ah | FPU_SUB | +A-B (D,D -> D) |
| 0Ch | FPU_EQ | A=B (D,D -> L: -1 if true, 0 if not) |
| 0Eh | FPU_NE | A<>B (D,D -> L) |
| 10h | FPU_LT | A<B (D,D -> L) |
| 12h | FPU_GT | A>B (D,D -> L) |
| 14h | FPU_LE | A<=B (D,D -> L) |
| 16h | FPU_GE | A>=B (D,D -> L) |
| 18h | FPU_CVT1DL | Converts the top double to a long (D -> L) |
| 1Ah | FPU_CVT2DL | Converts both doubles to longs (D,D -> L,L) |
| 1Ch | FPU_CVTL1D | +Converts the top long to a double (D,L -> D,D) |
| 1Eh | FPU_CVTL2D | +Converts the lower long to a double (L,D -> D,D) |
| 20h | FPU_CVTD1L | Converts the top double to a long (L,D -> L,L) |
| 22h | FPU_CVTD2L | Converts the lower double to a long (D,L -> L,L) |
| 24h | FPU_CVT1LD | +Converts a long to a double (L -> D) |
| 26h | FPU_CVT2LD | +Converts both longs to doubles, stored at ES:DI and ES:DI+8 (L,L -> D,D) |
| 28h | FPU_ABS | +ABS(A) (D -> D) |
| 2Ah | FPU_INT | +INT(A), the largest integer <= A (D -> D) |
| 2Ch | FPU_FIX | +FIX(A), A truncated (D -> D) |
| 2Eh | FPU_SQR | +SQR(A), the square root (D -> D) |
| 30h | FPU_ATOD | Converts characters at DS:SI to a double at ES:DI |
| 32h | FPU_DTOA | Converts the double at DS:SI to characters at ES:DI |
| 34h | FPU_TODEC | Converts the double at DS:SI to decimal digits at ES:DI |
| 36h | FPU_FROMDEC | Converts decimal digits at DS:SI to a double at ES:DI |
| 38h | FPU_SIN | +SIN(A), A in radians (D -> D) |
| 3Ah | FPU_COS | +COS(A), A in radians (D -> D) |
| 3Ch | FPU_TAN | +TAN(A), A in radians (D -> D) |
| 3Eh | FPU_ATN | +ATN(A), the arctangent in radians (D -> D) |
| 40h | FPU_LOG | +LOG(A), the natural logarithm (D -> D) |
| 42h | FPU_ETOX | +EXP(A), e raised to A (D -> D) |

The first 12 entries are in the same order as the code generator's operator indexes (OPEVAL_NEG through OPEVAL_GE), so that it can use (OPEVAL - 1) * 2 as the offset of the corresponding entry.

### Conversion Functions

**FPU_ATOD** converts the number at DS:SI, consisting of an optional sign, digits with an optional decimal point, and an optional exponent (E or D, followed by an optional sign and digits), to a double at ES:DI.  On success, carry is clear and SI points to the first character after the number.  Carry is set if there were no digits (SI is unchanged) or the number is out of range.  Modifies AX, BX, CX, and DX.

**FPU_DTOA** converts the double at DS:SI to characters at ES:DI, where CX is the buffer length, DX is the width (minimum # of characters), AL is the precision (FFh if none), and AH contains sprintf-style flags (PF_LEFT, PF_ZERO, and PF_HASH, which displays a space in place of a minus sign, as BASIC's PRINT does).  Without a precision, the format is BASIC-style, with up to 15 (FPU_DIGITS) significant digits (eg, "-.25" or "1E+20"), requiring at most 24 (FPU_MAXCHARS) characters; with a precision, the format is fixed-point with that many fractional digits (eg, "-0.25" for a precision of 2).  Returns DI pointing to the first byte after the last character.  Modifies AX, BX, CX, DX, and SI.

**FPU_TODEC** and **FPU_FROMDEC** are the FPU-dependent primitives that FPU_DTOA and FPU_ATOD rely on:

- FPU_TODEC converts the absolute value of the (finite) double at DS:SI to CL (0 to 15) significant digits at ES:DI, rounded to nearest, returning CX = # of digits stored (0 if the value is zero) and AX = the decimal exponent of the first digit.  When CL is zero, the value is rounded to either zero (CX = 0) or one digit ("1") at the next higher decimal exponent.  Modifies AX, BX, CX, and DX.
- FPU_FROMDEC converts CX digits at DS:SI (up to 19), multiplied by 10 raised to the power in AX, to a double at ES:DI, negated if bit 7 of BL is set.  Carry is set if the value is out of range.  Modifies AX, CX, DX, and SI.

### Limitations

The 8087's state isn't saved and restored on session switches yet, so FPU$ functions currently disable interrupts while they run.

{% include footer.html prev="Device Drivers:../dev/" next="Data Structures:../data/" %}
