;
; BASIC-DOS Formatted Printing Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<MONTH_DAYS>,byte
	EXTERNS	<MONTHS,DAYS>,word
	EXTERNS	<strlen>,near

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
	mov	bh,0
	mov	bp,sp

ia3:	mov	cx,ax			; save low dividend in CX
	mov	ax,dx			; divide high dividend
	sub	dx,dx			; DX:AX is new dividend
	div	bx			; AX is high quotient
	xchg	ax,cx			; move to CX, restore low dividend
	div	bx			; AX is low quotient
	push	dx			; save remainder
	mov	dx,cx			; new quotient in DX:AX
	or	cx,ax			; is new quotient zero?
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
; is stored in the CODE segment following the INT 21h, which we automatically
; skip, and the next instruction should be an "ADD SP,N*2", assuming N word
; parameters.
;
; When printing 32-bit ("long") values, push the high word first, then the
; low word; similarly, when pushing far ("long") pointers, push the segment
; first, then the offset.  When using the PRINTF macro, list the low word
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
; Standard format types:
;	%c:	8-bit character
;	%d:	signed 16-bit decimal integer; use %ld for 32-bit
;	%u:	unsigned 16-bit decimal integer; use %lu for 32-bit
;	%x:	unsigned 16-bit hexadecimal integer: use %lx for 32-bit
;	%s:	string (near CS-relative pointer); use %ls for far pointer
;
; Non-standard format types:
;	%U:	skip one 16-bit parameter on the stack; nothing output
;	%F:	month portion of a 16-bit DATE value, as string
;	%M:	month portion of a 16-bit DATE value, as number (1-12)
;	%D:	day portion of a 16-bit DATE value, as number (1-31)
;	%X:	year portion of a 16-bit DATE value, as 2-digit number (80-)
;	%Y:	year portion of a 16-bit DATE value, as 4-digit number (1980-)
;	%G:	hour portion of a 16-bit TIME value, as number (1-12)
;	%H:	hour portion of a 16-bit TIME value, as number (0-23)
;	%N:	minute portion of a 16-bit TIME value, as number (0-59)
;	%S:	second portion of a 16-bit TIME value, as number (0-59)
;
SPF_START	equ	TMP_AX		; buffer start address
SPF_LIMIT	equ	TMP_BX		; buffer limit address
SPF_WIDTH	equ	TMP_CX		; specifier width, if any
SPF_PRECIS	equ	TMP_DX		; specifier precision, if any

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
	test	al,al
	jz	pf3			; end of format string
	cmp	al,'%'			; format specifier?
	je	pfp			; yes
pf2:	cmp	di,[bp].SPF_LIMIT	; buffer full?
	jae	pf1			; yes, but keep consuming format chars
	stosb				; buffer the character
	jmp	pf1
pf3:	jmp	pf8

pfp:	mov	cx,10			; CH = print flags, CL = base
	mov	dx,bx			; DX = where this specifier started
	mov	word ptr [bp].SPF_WIDTH,0
	mov	word ptr [bp].SPF_PRECIS,0FF00h
pfpa:	mov	al,[bx]
	inc	bx
	cmp	al,'-'			; left-alignment indicator?
	jne	pfpb
	or	ch,PF_LEFT		; yes
	jmp	pfpa
pfpb:	cmp	al,'#'			; prefix indicator?
	jne	pfpc
	or	ch,PF_HASH		; yes
	jmp	pfpa
pfpc:	cmp	al,'0'			; zero-padding indicator
	jne	pfpd
	test	ch,PF_WIDTH OR PF_PRECIS; maybe, leading zero?
	jnz	pfpj			; no
	or	ch,PF_ZERO		; yes
	jmp	pfpa
pfpd:	cmp	al,'l'			; long value?
	jne	pfpe
	or	ch,PF_LONG		; yes
	jmp	pfpa
pfpe:	cmp	al,'d'			; decimal value?
	jne	pfpe1
	or	ch,PF_SIGN		; yes, so mark as explicitly signed
pfd0:	jmp	pfd
pfpe1:	cmp	al,'c'			; character value?
	jne	pfpf
	jmp	pfc
pfpf:	cmp	al,'s'			; string value?
	jne	pfpg
	jmp	pfs			; yes
pfpg:	cmp	al,'u'			; unsigned value?
	je	pfd0			; yes, unsigned values are the default
	cmp	al,'x'			; hex value?
	jne	pfph
	mov	cl,16			; use base 16 instead
	jmp	pfd			; hex values are always unsigned as well
pfph:	cmp	al,'.'			; precision indicator?
	jne	pfpi
	or	ch,PF_PRECIS		; yes
	jmp	pfpa
pfpi:	cmp	al,'*'			; asterisk?
	jne	pfpi2
	mov	ax,[bp+si]		; grab a stack parameter
	add	si,2			; and use that as the PRECIS or WIDTH
	jmp	short pfpj2
pfpi2:	cmp	al,'1'			; possible number?
	jb	pfpl			; no
	cmp	al,'9'
	ja	pfpl			; no
pfpj:	sub	al,'0'
pfpj2:	push	dx
	push	si
	mov	si,offset SPF_PRECIS
	test	ch,PF_PRECIS		; is this a precision number?
	jnz	pfpk			; yes
	mov	si,offset SPF_WIDTH
	or	ch,PF_WIDTH		; no, so it must be a width number
pfpk:	cbw
	xchg	dx,ax			; DX = value of next digit
	mov	al,[bp+si]		; load SPF value as an 8-bit value
	mov	ah,10			; (we assume it never goes over 255)
	mul	ah			; multiply SPF value * 10
	add	ax,dx			; add digit
	mov	[bp+si],ax		; update SPF value as a 16-bit value
	pop	si
	pop	dx
	jmp	pfpa
pfpl:	cmp	al,'F'			; %F (month as a string)?
	jne	pfpl2			; no
	jmp	pfm
pfpl2:	cmp	al,'W'			; %W (day-of-week as a string)?
	jne	pfpl3			; no
	jmp	pfw
pfpl3:	cmp	al,'M'			; %M (month portion of DATE)?
	jne	pfpm			; no
	mov	dx,0F05h		; shift DATE right 5, mask with 0Fh
	jmp	short pfda
pfpm:	cmp	al,'D'			; %D (day portion of DATE)?
	jne	pfpn			; no
	mov	dx,1F00h		; shift DATE right 0, mask with 1Fh
	jmp	short pfda
pfpn:	cmp	al,'X'			; %X (year portion of DATE)?
	jne	pfpo			; no
	mov	dx,7F09h		; shift DATE right 9, mask with 7Fh
	jmp	short pfda
pfpo:	cmp	al,'Y'			; %Y (year portion of DATE)?
	jne	pfpp			; no
	mov	dx,0FF09h		; shift DATE right 9, mask with FFh
	jmp	short pfda
pfpp:	cmp	al,'G'			; %G (12-hour portion of TIME)?
	jne	pfpq			; no
	mov	dx,0FF0Bh		; shift TIME right 11, mask with FFh
	jmp	short pfda
pfpq:	cmp	al,'H'			; %H (24-hour portion of TIME)?
	jne	pfpr			; no
	mov	dx,1F0Bh		; shift TIME right 11, mask with 1Fh
	jmp	short pfda
pfpr:	cmp	al,'N'			; %N (minute portion of TIME)?
	jne	pfps			; no
	mov	dx,3F05h		; shift TIME right 5, mask with 0Fh
	jmp	short pfda
pfps:	cmp	al,'S'			; %S (second portion of TIME)?
	jne	pfpt			; no
	mov	dx,1FFFh		; shift TIME left 1, mask with 1Fh
	jmp	short pfda
pfpt:	cmp	al,'A'			; %A (AM or PM portion of TIME)?
	jne	pfpu			; no
	mov	ax,[bp+si]		; get the TIME
	push	cx
	mov	cl,11
	shr	ax,cl			; AX = hour
	pop	cx
	cmp	al,12			; is hour < 12?
	mov	al,'a'
	jb	pfps2			; yes, use 'a'
	mov	al,'p'			; no, use 'p'
pfps2:	mov	[bp+si],ax
	jmp	pfc
pfpu:	cmp	al,'U'			; %U (skip one 16-bit parameter)?
	jne	pfpz			; no
	add	si,2			; yes, bump parameter index
	jmp	pf1			; and return to top

pfpz:	mov	bx,dx			; error, didn't end with known letter
	mov	al,'%'			; restore '%'
	jmp	pf2
;
; Helper code for DATE/TIME specifiers:
;
; Take the next value from the stack (which must be either a 16-bit DATE or
; TIME), shift it right by the number in DL (or left if DL is negative), mask
; it with value in DH, and then put it back on the stack and continue as if
; the specifier was %d.
;
; Some masks are "special": 7F09h and FF09h are used to mask a year, so we
; also add 1980 to the result, and FF0Bh is used to mask an hour that needs to
; be converted to 12-hour format (FFh is an overbroad mask, but since there
; are no bits to the left of the hour, it's OK).
;
pfda:	mov	ax,[bp+si]		; grab the next stack parameter
	push	cx
	mov	cl,dl
	test	dl,dl
	jge	pfda1
	neg	cl
	shl	ax,cl
	jmp	short pfda2
pfda1:	shr	ax,cl
pfda2:	pop	cx
	and	al,dh
	mov	ah,0
	cmp	dl,09h			; mask used specifically for year?
	jne	pfda3			; no
	add	ax,1980			; yes, so add 1980
	cmp	dh,7Fh			; mask also used for 2-digit year?
	jne	pfda9			; no
	mov	dl,100			; yes, so divide AX by 100
	div	dl
	mov	al,ah			; and move the remainder into AL
	cbw
	jmp	short pfda9
pfda3:	cmp	dx,0FF0Bh		; mask used specifically for 12-hour?
	jne	pfda9			; no
	test	ax,ax
	jnz	pfda4
	mov	ax,12			; transform 0 to 12
pfda4:	cmp	ax,12			; and subtract 12 from anything > 12
	jbe	pfda9
	sub	ax,12
pfda9:	mov	[bp+si],ax		; update the shifted/masked parameter
;
; Process %d, %u, and %x specifiers.
;
; TODO: Any specified width is a minimum, not a maximum, and if the value
; is larger, itoa will not truncate it.  So unless we want to make worst-case
; length estimates for all numeric possibilities, we really need to pass our
; buffer limit to itoa, so that it can guarantee the buffer never overflows.
;
; Another option would be to pass the minimum in CL and the maxiumum (LIMIT-DI)
; in CH; that would make it possible for itoa to perform bounds checking, too,
; but actually implementing that checking would be rather messy.
;
pfd:	mov	ax,[bp].SPF_WIDTH
	add	ax,di
	cmp	ax,[bp].SPF_LIMIT
pfdz:	jae	pfpz			; not enough room for specified length

	mov	ax,[bp+si]		; grab a stack parameter
	add	si,2
	test	ch,PF_LONG
	jnz	pfd2
	sub	dx,dx			; DX:AX = 16-bit value
	test	ch,PF_SIGN		; signed value?
	jz	pfd1			; no
	cwd				; yes, sign-extend AX to DX
pfd1:	push	bx
	mov	bx,cx			; set flags (BH) and base (BL)
	mov	cx,[bp].SPF_WIDTH	; CX = length (0 if unspecified)
	call	itoa
	add	di,ax			; adjust DI by number of digits
	pop	bx
	jmp	pf1

pfd2:	mov	dx,[bp+si]		; grab another stack parameter
	add	si,2			; DX:AX = 32-bit value
	jmp	pfd1
;
; Process %F specifier, which we convert to a "fake" string parameter.
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
; Process %W specifier, which we convert to a "fake" string parameter.
;
pfw:	push	ds
	mov	ax,[bp+si]		; get the DATE parameter
	add	si,2
	push	si
	push	cs
	pop	ds
	call	day_of_week		; convert AX from DATE to string pointer
	xchg	si,ax			; DS:SI -> day string
	mov	al,0
	call	strlen			; AX = length
	jmp	short pfs2a		; jump into the string code now
;
; Process %c specifier, which we treat as a 1-character string.
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
; Process %s specifier.
;
pfs:	push	ds
	mov	ax,[bp+si]		; use %s for CS-relative near pointers
	add	si,2
	test	ch,PF_LONG		; use %ls for far pointers
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

pf8:	pop	ax			; restore original format string address
	sub	bx,ax			; BX = length of format string + 1
	sub	di,[bp].SPF_START
	xchg	ax,di			; AX = # of characters
	ret
ENDPROC	sprintf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; day_of_week
;
; For the given DATE, calculate the day of the week.  Given that Jan 1 1980
; (DATE "zero") was a TUESDAY (day-of-week 2, since SUNDAY is day-of-week 0),
; we simply calculate how many days have elapsed, add 2, and compute days mod 7.
;
; Since 2000 was one of those every-400-years leap years, the number of elapsed
; leap days is a simple calculation as well.
;
; Note that since a DATE's year cannot be larger than 127, the number of days
; for all elapsed years cannot exceed 128 * 365 + (128 / 4) or 46752, which is
; happily a 16-bit quantity.
;
; Inputs:
;	AX = DATE
;
; Outputs:
;	DS:AX -> DAY string
;
; Modifies:
;	AX
;
DEFPROC	day_of_week,DOS
	ASSUME	ES:NOTHING
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	sub	di,di			; DI = day accumulator
	mov	bx,ax			; save the original date in BX
	mov	cl,9
	shr	ax,cl			; AX = # of full years elapsed
	push	ax
	shr	ax,1			; divide full years by 4
	shr	ax,1			; to get number of leap days
	add	di,ax			; add to DI
	pop	ax
	mov	dx,365
	mul	dx			; AX = total days for full years
	add	di,ax			; add to DI
	mov	ax,bx			; AX = original date again
	mov	cl,5
	shr	ax,cl
	and	ax,0Fh
	dec	ax			; AX = # of full months elapsed
	xchg	si,ax
dow1:	dec	si
	jl	dow2
	mov	dl,[MONTH_DAYS][si]
	mov	dh,0
	add	di,dx			; add # of days in past month to DI
	jmp	dow1
dow2:	mov	ax,bx			; AX = original date again
	and	ax,1Fh			; AX = day of the current month
	add	di,ax
	xchg	ax,di
	add	ax,2			; add 2 days (DATE "zero" was a Tues)
	sub	dx,dx			; DX:AX = total days
	mov	cx,7			; divide by length of week
	div	cx
	mov	si,dx			; SI = remainder from DX (0-6)
	add	si,si			; convert day-of-week index into offset
	mov	ax,[DAYS][si]		; AX -> day-of-week string
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	day_of_week

DOS	ends

	end
