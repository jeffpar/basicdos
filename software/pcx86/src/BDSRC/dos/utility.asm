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
	EXTERNS	<clk_ptr>,dword
	EXTERNS	<chk_devname,dev_request,write_string>,near
	EXTERNS	<scb_load,scb_start,scb_stop,scb_unload>,near
	EXTERNS	<scb_yield,scb_wait,scb_endwait>,near

	DEFLBL	UTILTBL,word
	dw	util_strlen,  util_atoi,    util_itoa,   util_printf	; 00h-03h
	dw	util_sprintf, util_getdev,  util_ioctl,  util_load	; 04h-07h
	dw	scb_start,    scb_stop,     scb_unload,  util_yield	; 08h-0Bh
	dw	util_sleep,   scb_wait,     scb_endwait, util_none	; 0Ch-0Fh
	dw	util_none,    util_none,    util_none,   util_none	; 10h-13h
	dw	util_none,    util_none,    util_none,   util_none	; 14h-17h
	dw	util_none,    util_none,    util_none,   util_none	; 18h-1Bh
	dw	util_none,    util_none,    util_none,   util_none	; 1Ch-1Fh
	dw	util_none,    util_none,    util_none,   util_none	; 20h-23h
	dw	util_strlen						; 24h
	DEFABS	UTILTBL_SIZE,<($ - UTILTBL) SHR 1>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_func (AH = 18h)
;
; Inputs:
;	AL = utility function (eg, UTIL_ATOI)
;
; Outputs:
;	Varies
;
DEFPROC	util_func,DOS
	cmp	al,UTILTBL_SIZE
	cmc
	jb	dc9
	mov	bl,al
	mov	bh,0
	add	bx,bx
;
; As with dos_func, all general-purpose registers except BX, DS, and ES still
; contain their original values.
;
	call	UTILTBL[bx]
	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
dc9:	ret
ENDPROC	util_func

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_strlen (AX = 1800h or 1824h)
;
; Returns the length of the REG_DS:SI string in AX, using the terminator in AL.
;
; Modifies:
;	AX
;
DEFPROC	util_strlen,DOS
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
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
	je	usl9
	stc				; error if we didn't end on a match
usl9:	sub	di,si
	lea	ax,[di-1]		; don't count the terminator character
	pop	es
	pop	di
	pop	cx
	ret
ENDPROC	util_strlen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_atoi (AX = 1801h)
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
DEFPROC	util_atoi,DOS
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	ASSUME	DS:NOTHING, ES:NOTHING
	sub	ax,ax
	cwd
	mov	cx,10
ud1:	mov	dl,[si]
	cmp	dl,'0'
	jb	ud5
	sub	dl,'0'
	cmp	dl,cl
	jae	ud6
	inc	si
	push	dx
	mul	cx
	pop	dx
	add	ax,dx
	jmp	ud1
ud5:	test	dl,dl
	jz	ud6
	inc	si
ud6:	test	di,di			; validation data provided?
	jz	ud9			; no
	cmp	ax,es:[di]		; too small?
	jae	ud7			; no
	mov	ax,es:[di]
	jmp	short ud8
ud7:	cmp	es:[di+2],ax		; too large?
	jae	ud8			; no
	mov	ax,es:[di+2]
ud8:	lea	di,[di+4]		; advance DI in case there are more
	mov	[bp].REG_DI,di		; but do so without disturbing CARRY
ud9:	mov	[bp].REG_SI,si		; update caller's SI, too
	ret
ENDPROC util_atoi

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_itoa (AX = 1802h)
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

DEFPROC	util_itoa,DOS
	xchg	ax,si			; DX:AX is now the value
	mov	es,[bp].REG_ES		; ES:DI -> buffer
	ASSUME	ES:NOTHING
;
; itoa internal calls use DX:AX
;
	DEFLBL	itoa,near		; for internal calls (no REG_FRAME)
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
ENDPROC util_itoa

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_printf (AX = 1803h)
;
; A semi-CDECL-style calling convention is assumed, where all parameters
; EXCEPT for the format string are pushed from right to left, so that the
; first (left-most) parameter is the last one pushed.  The format string
; is stored in the CODE segment following the INT 21h, which we automatically
; skip, and the next instruction should be an "ADD SP,N*2", assuming N word
; parameters.
;
; See util_sprintf for more details.
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
SPF_CALLS	dw REG_PADDING+2 dup(?)	; 2 near-call dispatches on stack
SPF_FRAME ends

BUFLEN	equ	80			; stack space to use as printf buffer

DEFPROC	util_printf,DOS
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
	push	ax
	xchg	cx,ax			; CX = # of characters
	call	write_string
	pop	ax			; recover # of characters for caller
	add	sp,BUFLEN + offset SPF_CALLS
	ret
ENDPROC	util_printf endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_sprintf (AX = 1804h)
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
DEFPROC	util_sprintf,DOS
	mov	es,[bp].REG_ES
	ASSUME	ES:NOTHING
	sub	sp,offset SPF_CALLS
	call	sprintf
	add	sp,offset SPF_CALLS
	ret
ENDPROC	util_sprintf

DEFPROC	sprintf,DOS
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
	jne	pfpf
	or	ch,PF_SIGN		; yes, so mark as explicitly signed
	jmp	short pfd
pfpf:	cmp	al,'s'			; string value?
	jne	pfpg
	jmp	pfs			; yes
pfpg:	cmp	al,'u'			; unsigned value?
	je	pfd			; yes, unsigned values are the default
	cmp	al,'x'			; hex value?
	jne	pfph
	mov	cl,16			; use base 16 instead
	jmp	short pfd		; hex values are always unsigned as well
pfph:	cmp	al,'.'			; precision indicator?
	jne	pfpi
	or	ch,PF_PRECIS		; yes
	jmp	pfpa
pfpi:	cmp	al,'1'			; possible number?
	jb	pfpz			; no
	cmp	al,'9'
	ja	pfpz			; no
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
pfpz:	mov	bx,dx			; error, didn't end with known letter
	mov	al,'%'			; restore '%'
	jmp	pf2
;
; Process %d, %u, and %x specifications.
;
; TODO: Any specified width is a minimum, not a maximum, and if the value
; is larger, itoa will not truncate it.  So unless we want to make worst-case
; length estimates for all numeric possibilities, we really need to pass our
; buffer limit to itoa, so that it can guarantee the buffer never overflows.
;
; Another option would be to pass the minimum in CL and the maxiumum (LIMIT-DI)
; in CH; that would make it possible for util_itoa to perform bounds checking,
; too, but actually implementing that checking would be rather messy.
;
pfd:	mov	ax,[bp].SPF_WIDTH
	add	ax,di
	cmp	ax,[bp].SPF_LIMIT
	jae	pfpz			; not enough room for specified length

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
; Process %s specification.
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
	mov	dx,[bp].SPF_PRECIS
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
	jae	pfpz

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
	add	[bp+size SPF_FRAME].REG_IP,bx
	sub	di,[bp].SPF_START
	xchg	ax,di			; AX = # of characters
	add	bp,size SPF_FRAME
	ret
ENDPROC	sprintf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_getdev (AX = 1805h)
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
DEFPROC	util_getdev,DOS
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	mov	si,dx
	call	chk_devname		; DS:SI -> device name
	jc	gd9
	mov	[bp].REG_DI,di
	mov	[bp].REG_ES,es
gd9:	ret
ENDPROC	util_getdev

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_ioctl (AX = 1806h)
;
; Inputs:
;	REG_BX = IOCTL command (BH = driver command, BL = IOCTL command)
;	REG_ES:REG_DI -> DDH
;	Other registers will vary
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	util_ioctl,DOS
	mov	ax,[bp].REG_BX		; AX = command codes from BH,BL
	mov	es,[bp].REG_ES		; ES:DI -> DDH
	call	dev_request		; call the driver
	ret
ENDPROC	util_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_load (AX = 1807h)
;
; Inputs:
;	REG_CL = SCB #
;	REG_DS:REG_DX = name of executable
;
; Modifies:
;	AX, BX, CX, DX, DI, DS, ES
;
DEFPROC	util_load,DOS
	mov	es,[bp].REG_DS
	ASSUME	DS:NOTHING		; CL = SCB #
	jmp	scb_load		; ES:DX -> name of executable
ENDPROC	util_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_yield (AX = 180Bh)
;
; Asynchronous interface to decide which SCB should run next.
;
; Inputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	util_yield,DOS
	mov	ax,[scb_active]
	jmp	scb_yield
ENDPROC	util_yield

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_sleep (AX = 180Ch)
;
; Issues an IOCTL to the CLOCK$ driver to wait the specified number of ticks.
;
; Inputs:
;	REG_CX:REG_DX = # of ticks to sleep
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	util_sleep,DOS
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_WAIT
	les	di,clk_ptr
	call	dev_request		; call the driver
	ret
ENDPROC	util_sleep

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_none
;
; Modifies:
;	None
;
DEFPROC	util_none
	ret
ENDPROC	util_none

DOS	ends

	end
