;
; BASIC-DOS Utility Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<scb_active>,word
	EXTERNS	<scb_table>,dword
	EXTERNS	<clk_ptr>,dword
	EXTERNS	<chk_devname,dev_request,write_string>,near
	EXTERNS	<scb_load,scb_start,scb_stop,scb_unload,scb_yield>,near
	EXTERNS	<scb_wait,scb_endwait>,near

	EXTERNS	<MONTH_DAYS>,byte
	EXTERNS	<MONTHS,DAYS>,word

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_strlen (AX = 1800h or 1824h)
;
; Returns the length of the REG_DS:SI string in AX, using the terminator in AL.
;
; Modifies:
;	AX
;
DEFPROC	utl_strlen,DOS
	sti
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	call	strlen
	mov	[bp].REG_AX,ax		; update REG_AX
	ret
	DEFLBL	strlen,near		; for internal calls (no REG_FRAME)
	push	cx
	push	di
	push	es
	push	ds
	pop	es
	mov	di,si
	mov	cx,di
	not	cx			; CX = largest possible count
	repne	scasb
	stc
	jne	sl9
	sub	di,si
	lea	ax,[di-1]		; don't count the terminator character
	pop	es
	pop	di
	pop	cx
sl9:	ret
ENDPROC	utl_strlen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_strupr (AX = 1801h)
;
; Makes the string at REG_DS:SI with length CX upper-case; use length 0
; if null-terminated.
;
; Outputs:
;	None
;
; Modifies:
;	AX (but not REG_AX)
;
DEFPROC	utl_strupr,DOS
	sti
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	DEFLBL	strupr,near		; for internal calls (no REG_FRAME)
	push	si
usu1:	mov	al,[si]
	test	al,al
	jz	usu9
	cmp	al,'a'
	jb	usu2
	cmp	al,'z'
	ja	usu2
	sub	al,20h
	mov	[si],al
usu2:	inc	si
	loop	usu1
usu9:	pop	si
	ret
ENDPROC	utl_strupr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_atoi (AX = 1802h)
;
; Convert string at DS:SI to decimal, then validate using values at ES:DI.
;
; For no validation, set DI to zero; otherwise, ES:DI must point to a pair
; of (min,max) 16-bit values; and like SI, DI will be advanced, making it easy
; to parse a series of values, each with their own (min,max) values.
;
; Returns:
;	AX = value, DS:SI -> next character (after non-decimal digit)
;	Carry will be set on a validation error, but AX will ALWAYS be valid
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	utl_atoi,DOS
	sti
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	ASSUME	DS:NOTHING, ES:NOTHING
	and	[bp].REG_FL,NOT FL_CARRY
	sub	ax,ax
	cwd
	mov	cx,10
ai1:	mov	dl,[si]
	cmp	dl,'0'
	jb	ai5
	sub	dl,'0'
	cmp	dl,cl
	jae	ai6
	inc	si
	push	dx
	mul	cx
	pop	dx
	add	ax,dx
	jmp	ai1
ai5:	test	dl,dl
	jz	ai6
	inc	si
ai6:	test	di,di			; validation data provided?
	jz	ai9			; no
	cmp	ax,es:[di]		; too small?
	jae	ai7			; no
	mov	ax,es:[di]
	jmp	short ai8
ai7:	cmp	es:[di+2],ax		; too large?
	jae	ai8			; no
	mov	ax,es:[di+2]
ai8:	lea	di,[di+4]		; advance DI in case there are more
	mov	[bp].REG_DI,di		; but do so without disturbing CARRY
ai9:	mov	[bp].REG_SI,si		; update caller's SI, too
	mov	[bp].REG_AX,ax		; update REG_AX
	ret
ENDPROC utl_atoi

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_itoa (AX = 1803h)
;
; Convert the value DX:SI to a string representation at ES:DI, using base BL,
; flags BH (see PF_*), minimum length CX (0 for no minimum).
;
; Returns:
;	ES:DI filled in
;	AL = # of digits
;
; Modifies:
;	AX, CX, DX, ES
;
PF_LEFT   equ	01h			; left-alignment requested
PF_HASH   equ	02h			; prefix requested (eg, "0x")
PF_ZERO   equ	04h			; zero padding requested
PF_LONG   equ	08h			; long value (32 bits); default is 16
PF_SIGN   equ	10h			; signed value
PF_WIDTH  equ	20h			; width encountered
PF_PRECIS equ	40h			; precision encountered (after '.')

DEFPROC	utl_itoa,DOS
	sti
	xchg	ax,si			; DX:AX is now the value
	mov	es,[bp].REG_ES		; ES:DI -> buffer
	ASSUME	ES:NOTHING
	call	itoa
	mov	[bp].REG_AX,ax		; update REG_AX
	ret
ENDPROC	utl_itoa

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
;	AX, CX, DX, ES
;
; Notes:
; 	When called from sprintf, BP does NOT point to REG_FRAME
;
DEFPROC	itoa
	push	bp
	push	si
	push	di
	push	bx			; save flags and base
	push	cx			; save requested length

	sub	si,si
	test	bh,PF_SIGN		; treat value as signed?
	jz	ia1			; no
	test	dx,dx			; negative value?
	jns	ia1			; no
	neg	dx			; yes, negate DX:AX
	neg	ax
	sbb	dx,0
	inc	si			; SI += 1 if we must add a sign
ia1:	test	bh,PF_HASH
	jz	ia2
	cmp	bl,16
	jne	ia2
	add	si,2			; SI += 2 if we must add a prefix

ia2:	mov	bh,0
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
ia5:	test	si,1			; sign required?
	jz	ia6			; no
	mov	al,'-'
	stosb
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_printf (AX = 1804h)
;
; A semi-CDECL-style calling convention is assumed, where all parameters
; EXCEPT for the format string are pushed from right to left, so that the
; first (left-most) parameter is the last one pushed.  The format string
; is stored in the CODE segment following the INT 21h, which we automatically
; skip, and the next instruction should be an "ADD SP,N*2", assuming N word
; parameters.
;
; See utl_sprintf for more details.
;
; Inputs:
;	format string follows the INT 21h
;	all other parameters must be pushed onto the stack, right to left
;
; Outputs:
;	# of characters printed
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
SPF_FRAME struc
SPF_WIDTH	dw	?		; specifier width, if any
SPF_PRECIS	dw	?		; specifier precision, if any
SPF_START	dw	?		; buffer start address
SPF_LIMIT	dw	?		; buffer limit address
SPF_CALLS	dw REG_CHECK + 1 dup(?)	; 1 near-call dispatch on stack
SPF_FRAME ends

BUFLEN	equ	80			; stack space to use as printf buffer

DEFPROC	utl_printf,DOS
	push	ss
	pop	es
	ASSUME	ES:NOTHING
	sub	sp,BUFLEN + offset SPF_CALLS
	mov	cx,BUFLEN		; CX = length
	mov	di,sp			; ES:DI -> buffer on stack
	call	sprintf
	mov	si,sp
	push	ss
	pop	ds			; DS:SI -> buffer on stack
	ASSUME	DS:NOTHING
	xchg	cx,ax			; CX = # of characters
	call	write_string
	add	sp,BUFLEN + offset SPF_CALLS
	mov	[bp].REG_AX,cx		; update REG_AX with count in CX
	add	[bp].REG_IP,bx		; update REG_IP with length in BX
	ret
ENDPROC	utl_printf endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_sprintf (AX = 1805h)
;
; A semi-CDECL-style calling convention is assumed, where all parameters
; EXCEPT for the format string are pushed from right to left, so that the
; first (left-most) parameter is the last one pushed.  The format string
; is stored in the CODE segment following the INT 21h, which we automatically
; skip, and the next instruction should be an "ADD SP,N*2", assuming N word
; parameters.
;
; When printing 32-bit values, list the low word first, then the high word,
; so that the high word is pushed first.
;
; The code relies on SPF_FRAME, which must accurately reflect the number of
; additional bytes pushed onto the stack since REG_FRAME was created.
; Obviously that could be calculated at run-time, but it's preferable to know
; the value at assembly-time so that we can use constant displacements and
; simplify register usage.
;
; Inputs:
;	ES:DI -> buffer
;	CX = length of buffer
;	format string follows the INT 21h
;	all other parameters must be pushed onto the stack, right to left
;
; Outputs:
;	# of characters generated
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
DEFPROC	utl_sprintf,DOS
	mov	es,[bp].REG_ES
	ASSUME	ES:NOTHING
	sub	sp,offset SPF_CALLS
	call	sprintf
	add	sp,offset SPF_CALLS
	mov	[bp].REG_AX,ax		; update REG_AX
	add	[bp].REG_IP,bx		; update REG_IP with length in BX
	ret
ENDPROC	utl_sprintf

DEFPROC	sprintf,DOS
	sti
	ASSUME	ES:NOTHING
	sub	bp,size SPF_FRAME
	mov	[bp].SPF_START,di	; DI is the buffer start
	add	cx,di
	mov	[bp].SPF_LIMIT,cx	; CX+DI is the buffer limit

	mov	si,size SPF_FRAME+size REG_FRAME
	mov	bx,[bp+size SPF_FRAME].REG_IP
	mov	ds,[bp+size SPF_FRAME].REG_CS
	ASSUME	DS:NOTHING		; DS:BX -> format string

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
	mov	[bp].SPF_WIDTH,0	; initial specifier width
	mov	[bp].SPF_PRECIS,0	; initial specifier precision
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
pfpi:	cmp	al,'1'			; possible number?
	jb	pfpl			; no
	cmp	al,'9'
	ja	pfpl			; no
pfpj:	sub	al,'0'
	push	dx
	push	si
	mov	si,offset SPF_PRECIS
	test	ch,PF_PRECIS		; is this a precision number?
	jnz	pfpk			; yes
	mov	si,offset SPF_WIDTH
	or	ch,PF_WIDTH		; no, so it must be a width number
pfpk:	xchg	dx,ax
	mov	al,[bp+si]
	mov	ah,10
	mul	ah
	add	al,dl
	mov	[bp+si],al
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
	jne	pfpz			; no
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
	test	dx,dx
	jz	pfs3
	cmp	ax,dx			; length < PRECIS?
	jb	pfs3			; no
	mov	ax,dx			; yes, so limit it
pfs3:	mov	dx,[bp].SPF_WIDTH
	test	dx,dx
	jz	pfs4
	cmp	dx,ax
	jbe	pfs4
	sub	dx,ax			; DX = padding count

	push	di			; make sure that DI+AX+DX < LIMIT
	add	di,ax
	add	di,dx
	cmp	di,[bp].SPF_LIMIT
	pop	di
	jb	pfs4
	jmp	pfdz

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
	add	bp,size SPF_FRAME
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
; for all elapsed years cannot exceed 128 * 365 + (128 / 4) or 46752, which we
; note is a 16-bit quantity.
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_getdev (AX = 1806h)
;
; Returns DDH in ES:DI for device name at DS:DX.
;
; Inputs:
;	DS:DX -> device name
;
; Outputs:
;	ES:DI -> DDH if success; carry set if not found
;
; Modifies:
;	AX, CX, DI, ES (ie, whatever chk_devname modifies)
;
DEFPROC	utl_getdev,DOS
	sti
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	and	[bp].REG_FL,NOT FL_CARRY
	mov	si,dx
	call	chk_devname		; DS:SI -> device name
	jc	gd9
	mov	[bp].REG_DI,di
	mov	[bp].REG_ES,es
gd9:	ret
ENDPROC	utl_getdev

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_ioctl (AX = 1807h)
;
; Inputs:
;	REG_BX = IOCTL command (BH = driver command, BL = IOCTL command)
;	REG_ES:REG_DI -> DDH
;	Other registers will vary
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	utl_ioctl,DOS
	sti
	mov	ax,[bp].REG_BX		; AX = command codes from BH,BL
	mov	es,[bp].REG_ES		; ES:DI -> DDH
	call	dev_request		; call the driver
	ret
ENDPROC	utl_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_load (AX = 1808h)
;
; Inputs:
;	REG_CL = SCB #
;	REG_DS:REG_DX = name of program (or command-line)
;
; Modifies:
;	AX, BX, CX, DX, DI, DS, ES
;
DEFPROC	utl_load,DOS
	sti
	mov	es,[bp].REG_DS
	ASSUME	DS:NOTHING		; CL = SCB #
	jmp	scb_load		; ES:DX -> name of program
ENDPROC	utl_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_start (AX = 1809h)
;
; "Start" the specified session (actual starting will handled by scb_switch).
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success, BX -> SCB
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	utl_start,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
 	jmp	scb_start
ENDPROC	utl_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_stop (AX = 180Ah)
;
; "Stop" the specified session.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	utl_stop,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_stop
ENDPROC	utl_stop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_unload (AX = 180Bh)
;
; Unload the current program from the specified session.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	utl_unload,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_unload
ENDPROC	utl_unload

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_yield (AX = 180Ch)
;
; Asynchronous interface to decide which SCB should run next.
;
; Inputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	utl_yield,DOS
	sti
	mov	ax,[scb_active]
	jmp	scb_yield
ENDPROC	utl_yield

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_sleep (AX = 180Dh)
;
; Converts DX from milliseconds (1000/second) to ticks (18.2/sec) and
; issues an IOCTL to the CLOCK$ driver to wait the corresponding # of ticks.
;
; 1 tick is equivalent to approximately 55ms, so that's the granularity of
; sleep requests.
;
; Inputs:
;	REG_DX = # of milliseconds to sleep
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	utl_sleep,DOS
	sti
	xchg	ax,dx
	add	ax,27			; add 1/2 tick (as # ms) for rounding
	sub	dx,dx			; DX:AX = # ms
	mov	cx,55
	div	cx			; AX = ticks, DX = remainder
	xchg	dx,ax
	sub	cx,cx			; CX:DX = # ticks
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_WAIT
	les	di,clk_ptr
	call	dev_request		; call the driver
	ret
ENDPROC	utl_sleep

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_wait (AX = 180Eh)
;
; Synchronous interface to mark current SCB as waiting for the specified ID.
;
; Inputs:
;	REG_DX:REG_DI == wait ID
;
; Outputs:
;	None
;
DEFPROC	utl_wait,DOS
	jmp	scb_wait
ENDPROC	utl_wait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_endwait (AX = 180Fh)
;
; Asynchronous interface to examine all SCBs for the specified ID and clear it.
;
; Inputs:
;	REG_DX:REG_DI == wait ID
;
; Outputs:
;	Carry clear if found, set if not
;
DEFPROC	utl_endwait,DOS
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_endwait
ENDPROC	utl_endwait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_hotkey (AX = 1810h)
;
; Inputs:
;	REG_CX = CONSOLE context
;	REG_DL = char code, REG_DH = scan code
;
; Outputs:
;	Carry clear if successful, set if unprocessed
;
; Modifies:
;	AX
;
DEFPROC	utl_hotkey,DOS
	sti
	xchg	ax,dx			; AL = char code, AH = scan code
	and	[bp].REG_FL,NOT FL_CARRY
;
; Find the SCB with the matching context; that's the one with focus.
;
	mov	bx,[scb_table].OFF
hk1:	cmp	[bx].SCB_CONTEXT,cx
	je	hk2
	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	jb	hk1
	stc
	jmp	short hk9

hk2:	cmp	al,CHR_CTRLC
	jne	hk3
	or	[bx].SCB_CTRLC_ACT,1

hk3:	cmp	al,CHR_CTRLP
	clc
	jne	hk9
	xor	[bx].SCB_CTRLP_ACT,1

hk9:	ret
ENDPROC	utl_hotkey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_tokify (AX = 1811h)
;
; Inputs:
;	REG_AL = token type (TODO)
;	REG_DS:REG_SI -> BUF_INPUT
;	REG_ES:REG_DI -> BUF_TOKENS
;
; Outputs:
;	AX = # tokens; token buffer updated
;
; Modifies:
;	AX
;
DEFPROC	utl_tokify,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ds,[bp].REG_DS		; DS:SI -> BUF_INPUT
	mov	es,[bp].REG_ES		; ES:DI -> BUF_TOKENS
	ASSUME	DS:NOTHING, ES:NOTHING

	LOCVAR	pStart,word
	ENTER

	sub	bx,bx			; BX = token index
	add	si,offset INP_BUF	; SI -> 1st character
	mov	[pStart],si		; BP = starting position
	lodsb				; preload the first character
	jmp	ut8			; and dive in
;
; Skip all whitespace in front of the next token.
;
ut1:	lodsb
ut2:	cmp	al,CHR_RETURN
	je	ut9
	cmp	al,CHR_SPACE
	je	ut1
	cmp	al,CHR_TAB
	je	ut1
;
; For the next token word-pair, we need to record the offset and the length;
; we know the offset already (SI-pStart-1), so put that in DX.
;
	lea	dx,[si-1]
	sub	dx,[pStart]		; DX = offset of next token
;
; Skip over the next token. This is complicated by additional rules, such as
; treating all quoted sequences as a single token.
;
	mov	ah,0			; AH = 0 (or quote char)
	cmp	al,'"'
	je	ut3
	cmp	al,"'"
	jne	ut4
ut3:	mov	ah,al
ut4:	lodsb
	cmp	al,CHR_RETURN
	je	ut6
	test	ah,ah			; did we start with a quote?
	jz	ut5			; no
	cmp	al,ah			; yes, so have we found another?
	jnz	ut4			; no
	lodsb				; yes, preload the next character
	jmp	short ut6		; and record the token length
ut5:	cmp	al,CHR_SPACE
	je	ut6
	cmp	al,CHR_TAB
	jne	ut4

ut6:	lea	cx,[si-1]
	sub	cx,[pStart]
	sub	cx,dx			; CX = length of token
;
; DX:CX has our next token pair; store it at the token index in BX
;
	add	bx,bx
	add	bx,bx
	mov	es:[di+bx+2],dx
	mov	es:[di+bx+4],cx
	shr	bx,1
	shr	bx,1
	inc	bx			; increment token index

ut8:	cmp	bl,es:[di]		; room for more tokens?
	jb	ut2			; yes

ut9:	LEAVE

	mov	es:[di+1],bl		; update # tokens
	mov	[bp].REG_AX,bx		; return # tokens in AX, too
	ret
ENDPROC	utl_tokify

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_tokid (AX = 1812h)
;
; Inputs:
;	REG_CX = token length
;	REG_DS:REG_SI -> token
;	REG_ES:REG_DI -> DEF_TOKENs
; Outputs:
;	If carry clear, AX = token ID (TOK_ID), DX = token data (TOK_DATA)
;	If carry set, token not found
;
; Modifies:
;	AX
;
DEFPROC	utl_tokid,DOS
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ds,[bp].REG_DS		; DS:SI -> token (length CX)
	mov	es,[bp].REG_ES		; ES:DI -> DEF_TOKENs
	ASSUME	DS:NOTHING, ES:NOTHING

	push	bp
	sub	bp,bp			; BP = top index
	mov	dx,es:[di]		; DX = number of tokens in DEF_TOKENs
	add	di,2

utc0:	mov	ax,-1
	cmp	bp,dx
	stc
	je	utc9
	mov	bx,dx
	add	bx,bp
	shr	bx,1			; BX = midpoint index

	push	bx
	IF	SIZE DEF_TOKEN EQ 6
	mov	ax,bx
	add	bx,bx
	add	bx,ax
	add	bx,bx
	ELSE
	ASSERT	B,<cmp bl,256>
	mov	al,size DEF_TOKEN
	mul	bl
	mov	bx,ax
	ENDIF
	mov	ch,es:[di+bx].TOK_LEN	; CH = length of current token
	mov	ax,cx			; CL is saved in AL
	push	si
	push	di
	mov	di,es:[di+bx].TOK_OFF	; ES:DI -> current token
utc1:	cmpsb				; compare input to current
	jne	utc2
	sub	cx,0101h
	jz	utc2			; match!
	test	cl,cl
	stc
	jz	utc2			; if CL exhausted, input < current
	test	ch,ch
	jz	utc2			; if CH exhausted, input > current
	jmp	utc1

utc2:	pop	di
	pop	si
	jcxz	utc8
;
; If carry is set, set the bottom range to BX, otherwise set the top range
;
	pop	bx			; BX = index of token we just tested
	xchg	cx,ax			; restore CL from AL
	jnc	utc3
	mov	dx,bx			; new bottom is middle
	jmp	utc0
utc3:	inc	bx
	mov	bp,bx			; new top is middle + 1
	jmp	utc0

utc8:	sub	ax,ax			; zero AX (and carry, too)
	mov	al,es:[di+bx].TOK_ID	; AX = token ID
	mov	dx,es:[di+bx].TOK_DATA	; DX = user-defined token data
	pop	bx			; toss BX from stack

utc9:	pop	bp
	jc	utc9a
	mov	[bp].REG_DX,dx
	mov	[bp].REG_AX,ax
utc9a:	ret
ENDPROC	utl_tokid

DOS	ends

	end
