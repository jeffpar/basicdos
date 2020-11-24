;
; BASIC-DOS Formatted Printing Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTWORD	<MONTHS,DAYS>
	EXTNEAR	<strlen,day_of_week,div_32_16>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; itoa
;
; Inputs:
;	DX:AX = value
;	BL = base
;	BH = flags (see PF_*)
;	CX = length (minimum; 0 for none)
;	ES:DI -> buffer
;
; Outputs:
;	AL = # of digits written to buffer
;
; Modifies:
;	AX, BX, CX, DX, ES
;
DEFPROC	itoa,DOS
	push	bp
	push	si
	push	di

	sub	si,si
	test	bh,PF_SIGN		; treat value as signed?
	jz	ia1			; no
	and	bh,NOT PF_SIGN
	test	dx,dx			; negative value?
	jns	ia1			; no
	neg	dx			; yes, negate DX:AX
	neg	ax
	sbb	dx,0
	inc	si			; SI = 1 if we must add a sign
	or	bh,PF_SIGN
ia1:	test	bh,PF_HASH
	jz	ia2
;
; For BASIC PRINT compatibility, I use PF_HASH with signed decimal output
; to indicate that a space should be displayed in lieu of a minus sign if the
; value is not negative.
;
	or	si,1
	cmp	bl,10
	je	ia2
	mov	si,2			; SI = 2 if we must add a prefix

ia2:	push	bx			; save flags and base
	push	cx			; save requested length
	mov	cl,bl
	mov	ch,0
	mov	bp,sp

ia3:	call	div_32_16		; DX:AX = DX:AX / CX
	push	bx			; push remainder onto stack
	mov	bx,dx
	or	bx,ax			; is new quotient zero?
	jnz	ia3			; no, use as next dividend

	mov	cx,[bp]			; recover requested length
	mov	bx,[bp+2]		; recover flags
	sub	bp,sp
	shr	bp,1			; BP = # of digits
	sub	dx,dx			; DX = post-padding (default is none)
	sub	cx,bp			; is space left over?
	jle	ia4			; no
	sub	cx,si			; subtract room for sign, if any
	jle	ia4			; again, jump if no space left over
;
; Padding is required, but unfortunately, spaces must appear BEFORE any sign
; or prefix, and zeros must appear AFTER any sign or prefix.
;
	test	bh,PF_ZERO		; pad with zeros?
	jnz	ia5			; yes
	test	bh,PF_LEFT		; left alignment?
	jz	ia3a			; no
	mov	dx,cx			; yes, switch to post-padding
	jmp	short ia4
ia3a:	mov	al,' '			; no, pad with spaces
	rep	stosb			; no sign, we just need to pad
;
; This takes care of any sign or prefix, and will optionally pad with as
; many zeros as CX specifies.
;
ia4:	sub	cx,cx
ia5:	test	si,1			; sign or space required?
	jz	ia6			; no
	mov	al,'-'
	test	bh,PF_SIGN
	jnz	ia5a
	mov	al,' '
ia5a:	stosb
ia6:	test	si,2			; prefix required?
	jz	ia7			; no
	mov	ax,'x0'			; assume a hex prefix
	cmp	bl,8			; was base 8 used?
	jne	ia6a			; no
	mov	ax,'o0'			; yes, use an octal prefix
ia6a:	stosw
ia7:	mov	al,'0'
	rep	stosb

ia8:	pop	ax			; pop a digit
	add	al,'0'			; convert digit to ASCII
	cmp	al,'9'			; alpha hex digit instead?
	jbe	ia9			; no
	add	al,'A'-'0'-10		; yes, adjust it to 'A' to 'F'
ia9:	stosb				; store the digit
	dec	bp
	jnz	ia8

	mov	cx,dx			; perform post-padding, if any
	mov	al,' '
	rep	stosb

	add	sp,4			; discard requested length and flags
	pop	ax
	pop	si
	pop	bp
	sub	di,ax			; current - original address
	xchg	ax,di			; DI restored, AX is the digit count
	ret
ENDPROC itoa

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sprintf
;
; A semi-CDECL-style calling convention is assumed, where all parameters
; EXCEPT for the format string are pushed from right to left, so that the
; first (left-most) parameter is the last one pushed.  The format string
; is stored in the code segment following the INT 21h, which we automatically
; skip, and the next instruction should be an "ADD SP,N*2", assuming N word
; parameters.
;
; When printing 32-bit ("long") values, push the high word first, then the
; low word; similarly, when pushing far ("long") pointers, push the segment
; first, then the offset.  When using the CCALL macro, list the low word
; first, then the high word; the macro takes care of pushing the parameters
; in reverse order.
;
; Inputs:
;	DS:BX -> format string
;	ES:DI -> output buffer
;	CX = length of buffer
;	format string follows the INT 21h
;	all other parameters must be pushed onto the stack, right to left
;
; Outputs:
;	AX = # of characters generated
;	BX = # of characters in format string (used to adjust the caller's IP)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; Standard formatters:
;	%c:	8-bit character
;	%d:	signed 16-bit decimal integer (%bd for 8-bit, %ld for 32-bit)
;	%u:	unsigned 16-bit decimal integer (%bu for 8-bit, %lu for 32-bit)
;	%s:	string (near DS-relative pointer); use %ls for far pointer
;
; Formatters also support flags '#' and '-' as well as width and precision
; (eg, "-10.4s" prints 10 characters, left-justified, with max of 4 characters
; from the given string).
;
; Standard formatters in DEBUG-only builds (to save space):
;	%x:	unsigned 16-bit hex integer (%bx for 8-bit, %lx for 32-bit);
;		use precision of ".n" to display n digits
;
; Non-standard formatters:
;	%P:	caller's address (REG_CS:REG_IP-2)
;	%U:	skip one 16-bit parameter on the stack; nothing output
;	%W:	day of week, as string
;	%F:	month portion of a 16-bit DATE value, as string
;	%M:	month portion of a 16-bit DATE value, as number (1-12)
;	%D:	day portion of a 16-bit DATE value, as number (1-31)
;	%X:	year portion of a 16-bit DATE value, as 2-digit number (80-)
;	%Y:	year portion of a 16-bit DATE value, as 4-digit number (1980-)
;	%G:	hour portion of a 16-bit TIME value, as number (1-12)
;	%H:	hour portion of a 16-bit TIME value, as number (0-23)
;	%N:	minute portion of a 16-bit TIME value, as number (0-59)
;	%S:	second portion of a 16-bit TIME value, as number (0-59)
;	%A:	'a' if AM, 'p' if PM (from 16-bit TIME value)
;
SPF_START	equ	TMP_AX		; buffer start address
SPF_LIMIT	equ	TMP_BX		; buffer limit address
SPF_WIDTH	equ	TMP_CX		; formatter width, if any
SPF_PRECIS	equ	TMP_DX		; formatter precision, if any

DEFPROC	sprintf,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	mov	[bp].SPF_START,di	; DI is the buffer start
	add	cx,di
	mov	[bp].SPF_LIMIT,cx	; CX+DI is the buffer limit
	mov	si,size REG_FRAME
					; BP+SI -> parameters
	push	bx			; save original format string address
pf1:	mov	al,[bx]			; AL = next format character
	inc	bx
;
; Support for so-called "escape sequences" (ie, backslash-prefixed control
; characters) is limited and not really encouraged, in part because it's just
; as easy to mix in control characters directly and use 1 byte instead of 2,
; but they're convenient for things like DPRINTF, where space isn't a concern.
;
; Anything other than \b, \e, \r, \n, and \t will simply output the character
; following the backslash -- which is exactly what you want in the case of \\.
;
	cmp	al,'\'
	jne	pf1e
	mov	al,[bx]
	inc	bx
	cmp	al,'b'
	jne	pf1a
	mov	al,CHR_BACKSPACE	; \b becomes 8
pf1a:	cmp	al,'e'
	jne	pf1b
	mov	al,CHR_ESCAPE		; \e becomes 27 (my own "invention")
pf1b:	cmp	al,'r'
	jne	pf1c
	mov	al,CHR_RETURN		; \r becomes 13
pf1c:	cmp	al,'n'
	jne	pf1d
	mov	al,CHR_LINEFEED		; \n becomes 10
pf1d:	cmp	al,'t'
	jne	pf1e
	mov	al,CHR_TAB		; \t becomes 9
pf1e:	test	al,al
	jz	pf3			; end of format string
	cmp	al,'%'			; formatter prefix?
	je	pfp			; yes
pf2:	cmp	di,[bp].SPF_LIMIT	; buffer full?
	jae	pf1			; yes, but keep consuming format chars
	stosb				; buffer the character
	jmp	pf1
pf3:	jmp	pf8

pfp:	mov	cx,10			; CH = print flags, CL = base
	mov	dx,bx			; DX = where this formatter started
	mov	word ptr [bp].SPF_WIDTH,0
	mov	word ptr [bp].SPF_PRECIS,0FF00h
pfp1:	mov	al,[bx]
	inc	bx
	cmp	al,'-'			; left-alignment indicator?
	jne	pfp2
	or	ch,PF_LEFT		; yes
	jmp	pfp1
pfp2:	cmp	al,'#'			; prefix indicator?
	jne	pfp3
	or	ch,PF_HASH		; yes
	jmp	pfp1
pfp3:	cmp	al,'0'			; zero-padding indicator
	jne	pfp4
	test	ch,PF_WIDTH OR PF_PRECIS; maybe, leading zero?
	jnz	pfp10			; no
	or	ch,PF_ZERO		; yes
	jmp	pfp1
pfp4:	cmp	al,'b'			; byte value?
	jne	pfp4a
	or	ch,PF_BYTE		; yes
	jmp	pfp1
pfp4a:	cmp	al,'l'			; long value?
	jne	pfp5
	or	ch,PF_LONG		; yes
	jmp	pfp1
pfp5:	cmp	al,'d'			; %d: decimal value?
	jne	pfp5b
	or	ch,PF_SIGN		; yes, so mark as explicitly signed
pfp5a:	jmp	pfd
pfp5b:	cmp	al,'c'			; %c character value?
	jne	pfp6
	jmp	pfc
pfp6:	cmp	al,'s'			; %s string value?
	jne	pfp7
	jmp	pfs			; yes
pfp7:	cmp	al,'u'			; %u unsigned value?
	je	pfp5a			; yes, unsigned values are the default
	IFDEF DEBUG
	cmp	al,'x'			; %x hex value?
	jne	pfp8
	mov	cl,16			; use base 16 instead
	jmp	pfp5a			; hex values are always unsigned
	ENDIF
pfp8:	cmp	al,'.'			; precision indicator?
	jne	pfp9
	or	ch,PF_PRECIS		; yes
	jmp	pfp1
pfp9:	cmp	al,'*'			; asterisk?
	jne	pfp9a
	mov	ax,[bp+si]		; grab a stack parameter
	add	si,2			; and use that as the PRECIS or WIDTH
	jmp	short pfp10a
pfp9a:	cmp	al,'1'			; possible number?
	jb	pfp12			; no
	cmp	al,'9'
	ja	pfp12			; no
pfp10:	sub	al,'0'
pfp10a:	push	dx
	push	si
	mov	si,offset SPF_PRECIS
	test	ch,PF_PRECIS		; is this a precision number?
	jnz	pfp11			; yes
	mov	si,offset SPF_WIDTH
	or	ch,PF_WIDTH		; no, so it must be a width number
pfp11:	cbw
	xchg	dx,ax			; DX = value of next digit
	mov	al,[bp+si]		; load SPF value as an 8-bit value
	mov	ah,10			; (we assume it never goes over 255)
	mul	ah			; multiply SPF value * 10
	add	ax,dx			; add digit
	mov	[bp+si],ax		; update SPF value as a 16-bit value
	pop	si
	pop	dx
	jmp	pfp1
pfp12:	cmp	al,'F'			; %F (month as a string)?
	jne	pfp12a			; no
	jmp	pfm
pfp12a:	cmp	al,'W'			; %W (day-of-week as a string)?
	jne	pfp12b			; no
	jmp	pfw
pfp12b:	cmp	al,'M'			; %M (month portion of DATE)?
	jne	pfp13			; no
	mov	dx,0F05h		; shift DATE right 5, mask with 0Fh
	jmp	pda
pfp13:	cmp	al,'D'			; %D (day portion of DATE)?
	jne	pfp14			; no
	mov	dx,1F00h		; shift DATE right 0, mask with 1Fh
	jmp	short pda
pfp14:	cmp	al,'X'			; %X (year portion of DATE)?
	jne	pfp15			; no
	mov	dx,7F09h		; shift DATE right 9, mask with 7Fh
	jmp	short pda
pfp15:	cmp	al,'Y'			; %Y (year portion of DATE)?
	jne	pfp16			; no
	mov	dx,0FF09h		; shift DATE right 9, mask with FFh
	jmp	short pda
pfp16:	cmp	al,'G'			; %G (12-hour portion of TIME)?
	jne	pfp17			; no
	mov	dx,0FF0Bh		; shift TIME right 11, mask with FFh
	jmp	short pda
pfp17:	cmp	al,'H'			; %H (24-hour portion of TIME)?
	jne	pfp18			; no
	mov	dx,1F0Bh		; shift TIME right 11, mask with 1Fh
	jmp	short pda
pfp18:	cmp	al,'N'			; %N (minute portion of TIME)?
	jne	pfp19			; no
	mov	dx,3F05h		; shift TIME right 5, mask with 0Fh
	jmp	short pda
pfp19:	cmp	al,'S'			; %S (second portion of TIME)?
	jne	pfp20			; no
	mov	dx,1FFFh		; shift TIME left 1, mask with 1Fh
	jmp	short pda
pfp20:	cmp	al,'A'			; %A (AM or PM portion of TIME)?
	jne	pfp21			; no
	mov	ax,[bp+si]		; get the TIME
	push	cx
	mov	cl,11
	shr	ax,cl			; AX = hour
	pop	cx
	cmp	al,12			; is hour < 12?
	mov	al,'a'
	jb	pfp20a			; yes, use 'a'
	mov	al,'p'			; no, use 'p'
pfp20a:	mov	[bp+si],ax
	jmp	pfc
pfp21:	cmp	al,'U'			; %U (skip one 16-bit parameter)?
	jne	pfp22			; no
	add	si,2			; yes, bump parameter index
	jmp	pf1			; and return to top
pfp22:	cmp	al,'P'			; %P (CS:IP)?
	jne	pfp23			; no
	mov	dx,[bp].REG_CS		; yes, load caller's CS:IP-2 into DX:AX
	mov	ax,[bp].REG_IP
	dec	ax
	dec	ax
	mov	cl,16			; set base
	jmp	pfd4			; print as base-16 32-bit value
pfp23:	mov	bx,dx			; error, didn't end with known letter
	mov	al,'%'			; restore '%'
	jmp	pf2
;
; Helper code for DATE/TIME formatters:
;
; Take the next value from the stack (which must be either a 16-bit DATE or
; TIME), shift it right by the number in DL (or left if DL is negative), mask
; it with value in DH, and then put it back on the stack and continue as if
; the formatter was %d.
;
; Some masks are "special": 7F09h and FF09h are used to mask a year, so we
; also add 1980 to the result, and FF0Bh is used to mask an hour that needs to
; be converted to 12-hour format (FFh is an overbroad mask, but since there
; are no bits to the left of the hour, it's OK).
;
pda:	mov	ax,[bp+si]		; grab the next stack parameter
	push	cx
	mov	cl,dl
	test	dl,dl
	jge	pda1
	neg	cl
	shl	ax,cl
	jmp	short pda2
pda1:	shr	ax,cl
pda2:	pop	cx
	and	al,dh
	mov	ah,0
	cmp	dl,09h			; mask used specifically for year?
	jne	pda3			; no
	add	ax,1980			; yes, so add 1980
	cmp	dh,7Fh			; mask also used for 2-digit year?
	jne	pda9			; no
	mov	dl,100			; yes, so divide AX by 100
	div	dl
	mov	al,ah			; and move the remainder into AL
	cbw
	jmp	short pda9
pda3:	cmp	dx,0FF0Bh		; mask used specifically for 12-hour?
	jne	pda9			; no
	test	ax,ax
	jnz	pda4
	mov	ax,12			; transform 0 to 12
pda4:	cmp	ax,12			; and subtract 12 from anything > 12
	jbe	pda9
	sub	ax,12
pda9:	mov	[bp+si],ax		; update the shifted/masked parameter
;
; Process %d, %u, and %x formatters.
;
; In order to support partial bit values, we'd like to use precision to mod
; the value as follows: for %x, mod with (1 << (SPF_PRECIS << 2)), and
; for %d, mod with (10 ^ SPF_PRECIS).  For now, this is only supported for %x.

; TODO: Add precision support for %d and %u.
;
; TODO: Any specified width is a minimum, not a maximum, and if the value
; is larger, itoa will not truncate it.  So unless we want to make worst-case
; length estimates for all numeric possibilities, we really need to pass our
; buffer limit to itoa, so that it can guarantee the buffer never overflows.
;
; Another option would be to pass the minimum in CL and the maximum (LIMIT-DI)
; in CH; that would make it possible for itoa to perform bounds checking, too,
; but actually implementing that checking would be rather messy.
;
pfd:	mov	ax,[bp].SPF_WIDTH
	add	ax,di
	cmp	ax,[bp].SPF_LIMIT
	jae	pfp23			; not enough room for specified length

	mov	ax,[bp+si]		; grab a stack parameter
	sub	dx,dx			; DX:AX = 16-bit value
	add	si,2
	test	ch,ch			; PF_BYTE set?
	ASSERT	PF_BYTE,EQ,80h
	jns	pfd2			; no
	mov	ah,0			; DX:AX = 8-bit value
	test	ch,PF_SIGN		; signed value?
	jz	pfd2			; no
	cbw				; DX:AX = signed 8-bit value
pfd2:	test	ch,PF_SIGN		; signed value?
	jz	pfd3			; no
	cwd				; DX:AX = signed 16-bit value
pfd3:	test	ch,PF_LONG
	jz	pfd4
	mov	dx,[bp+si]		; grab another stack parameter
	add	si,2			; DX:AX = 32-bit value

pfd4:	push	bx
;
; Limited support for precision is next.  The goal for now is to support
; masking of hex values; eg, %0.2x will display only 2 hex digits (8 bits),
; %0.3x will display only 3 hex digits (12 bits), etc.
;
	IFDEF DEBUG
	cmp	cl,16			; base 16?
	jne	pfd6+1			; no, precision not supported
	push	cx
	mov	cx,[bp].SPF_PRECIS	; CX = precision
	test	cx,cx			; precision set?
	jl	pfd6			; no
	shl	cl,1
	shl	cl,1			; CL = CL * 4 (# of bits precision)
	cmp	cl,16			; more than 16 bits?
	jae	pfd5			; yes, leave AX alone
	mov	bx,1
	shl	bx,cl
	dec	bx			; BX = 16-bit mask
	and	ax,bx			; mask AX
	sub	dx,dx			; and zero DX
	jmp	short pfd6		; all done
pfd5:	sub	cl,16			; more than 32 bits?
	jae	pfd6			; yes, leave DX alone
	mov	bx,1
	shl	bx,cl
	dec	bx			; BX = 16-bit mask
	and	dx,bx			; mask DX
pfd6:	pop	cx
	ENDIF

	mov	bx,cx			; set flags (BH) and base (BL)
	mov	cx,[bp].SPF_WIDTH	; CX = length (0 if unspecified)
	call	itoa
	add	di,ax			; adjust DI by number of digits
	pop	bx
	jmp	pf1
;
; Process %F formatter, which we convert to a "fake" string parameter.
;
pfm:	push	ds
	mov	ax,[bp+si]		; get the DATE parameter
	add	si,2
	push	si
	push	cs
	pop	ds
	push	cx
	mov	cl,5
	shr	ax,cl
	and	ax,0Fh			; AX = month
	pop	cx
	dec	ax			; AX = month index
	add	ax,ax			; AX = month offset
	add	ax,offset MONTHS	; AX = month address
	xchg	si,ax			; DS:SI -> month address
	mov	si,[si]			; DS:SI -> month string
	mov	al,0
	call	strlen			; AX = length
	jmp	short pfs2a		; jump into the string code now
;
; Process %W formatter, which we convert to a "fake" string parameter.
;
pfw:	push	ds
	mov	ax,[bp+si]		; get the DATE parameter
	add	si,2
	push	si
	push	cs
	pop	ds
	call	day_of_week		; convert AX from DATE to string ptr
	mov	al,0
	call	strlen			; AX = length
	jmp	short pfs2a		; jump into the string code now
;
; Process %c formatter, which we treat as a 1-character string.
;
pfc:	push	ds
	lea	ax,[bp+si]
	add	si,2
	push	si
	push	ss
	pop	ds
	xchg	si,ax			; DS:SI -> character
	mov	ax,1			; AX = length
	jmp	short pfs2a		; jump into the string code now
;
; Process %s formatter.
;
pfs:	push	ds
	mov	ax,[bp+si]		; %s implies DS-relative near pointer
	add	si,2
	mov	ds,[bp].REG_DS
	test	ch,PF_LONG		; %ls implies far pointer
	jz	pfs2
	mov	ds,[bp+si]
	add	si,2
pfs2:	push	si
	xchg	si,ax			; DS:SI -> string
	mov	al,0
	call	strlen			; AX = length
pfs2a:	mov	dx,[bp].SPF_PRECIS
	test	dx,dx			; was a precision specified?
	js	pfs3			; no (still set to negative FF00h)
	cmp	ax,dx			; is length < PRECIS?
	jl	pfs3			; no
	mov	ax,dx			; yes, so limit it
pfs3:	mov	dx,[bp].SPF_WIDTH
	test	dx,dx
	jz	pfs3a
	sub	dx,ax			; DX = padding count
	jae	pfs3a
	sub	dx,dx
pfs3a:	push	di			; make sure that DI+AX+DX < LIMIT
	add	di,ax
	add	di,dx
	cmp	di,[bp].SPF_LIMIT	; too long?
	pop	di
	jb	pfs4			; no
	mov	ax,[bp].SPF_LIMIT	; yes, so instead of bailing, we'll
	sub	ax,di			; set the length to the amount of
	sub	dx,dx			; remaining space and zero the padding

pfs4:	test	ch,PF_LEFT		; left-aligned?
	jnz	pfs5			; yes
	mov	cx,dx
	sub	dx,dx
	push	ax
	mov	al,' '
	rep	stosb			; pad it
	pop	ax
pfs5:	xchg	cx,ax
	rep	movsb			; move it
	mov	cx,dx
	mov	al,' '
	rep	stosb			; pad it
	pop	si
	pop	ds
	jmp	pf1			; all done with %s

pf8:	pop	ax			; restore original format string addr
	sub	bx,ax			; BX = length of format string + 1
	sub	di,[bp].SPF_START
	xchg	ax,di			; AX = # of characters
	ret
ENDPROC	sprintf

DOS	ends

	end
