;
; BASIC-DOS PLAY and DRAW String Variables
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The functions that PLAY and DRAW (see snd.asm and gfx.asm) use for the
; variables in their strings: "=variable;" for a number, and "Xvariable;" for
; a string of commands.
;
	include	cmd.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<strIllegal,findVar>
	EXTLONG	<FPU_TABLE>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; execStr
;
; Used by the X command in PLAY and DRAW strings (eg, DRAW "XA$;"), which
; executes the commands in the named string variable, and then resumes the
; string that contains the X command.  The caller's DS:SI and CX are pushed
; underneath our return address (and popped when the caller reaches the end
; of the X command's string, where it must check its depth), and up to 8
; X commands can be nested (eg, in a recursive DRAW).
;
; Inputs:
;	DS:SI -> variable name (CX = # characters left in the string)
;	SS:DI -> depth (byte)
;
; Outputs:
;	DS:SI -> characters of the variable (CX = length), and the depth is
;	incremented; carry is set if the string is empty (with DS:SI and CX
;	pushed, as above)
;
; Modifies:
;	AX, CX, DX, SI, DI, DS
;
DEFPROC	execStr
	cmp	byte ptr ss:[di],8	; are too many X commands in progress?
	jae	es9			; yes
	inc	byte ptr ss:[di]
	call	getStrPtr		; DX:AX -> string (DX = 0 if empty)
	pop	di			; DI = return address
	push	ds
	push	si
	push	cx			; save the containing string's state
	push	di
	mov	ds,dx
	mov	si,ax
	mov	cx,dx
	stc
	jcxz	es8			; empty string (carry set)
	lodsb
	mov	cl,al
	mov	ch,0			; CX = length, DS:SI -> characters
	clc
es8:	ret
es9:	jmp	strIllegal
ENDPROC	execStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getStrVar and getStrPtr
;
; Used for "=variable;" in PLAY and DRAW strings (eg, PLAY "O=J;"), which
; uses the value of the named numeric variable (getStrVar), and for the X
; command (eg, DRAW "XA$;"), which uses the named string variable (getStrPtr;
; see execStr).  The name ends at a semicolon (or the end of the string), and
; the variable's type comes from its suffix, if any (eg, "J%"), or else from
; the default type of its first letter (eg, DEFINT I-N).  A double is rounded
; to a long, and as in MSBASIC, a variable that doesn't exist yet has a value
; of zero (or is an empty string).
;
; Inputs:
;	DS:SI -> name (CX = # characters left in the string)
;
; Outputs:
;	AX = value (getStrVar), or DX:AX -> string (getStrPtr; its length,
;	followed by its characters), or DX = 0 if the string is empty; carry
;	is clear, and DS:SI and CX are advanced past the name and ';' (an
;	"Illegal function call" error occurs if the name is invalid, or if the
;	variable's type is wrong)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	getStrPtr
	mov	al,VAR_STR
	jmp	short gsv0
ENDPROC	getStrPtr

DEFPROC	getStrVar
	mov	al,0			; (a numeric type)
gsv0:	push	bx
	push	es
	push	bp
	mov	bp,sp
	push	ax			; [bp-2] = VAR_STR for getStrPtr
	sub	sp,VAR_NAMELEN+1	; (room for the name)
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> name buffer
	sub	bx,bx			; BX = length of name
gsv1:	jcxz	gsv2
	lodsb
	dec	cx
	cmp	al,';'			; end of name?
	je	gsv2			; yes
	cmp	al,'a'
	jb	gsv1a
	cmp	al,'z'
	ja	gsv1a
	sub	al,20h			; (upper-case it)
gsv1a:	cmp	bl,VAR_NAMELEN		; room for another character?
	jae	gsvX			; no
	stosb
	inc	bx
	jmp	gsv1
gsv2:	test	bx,bx			; any name?
	jz	gsvX			; no
	mov	ah,VAR_LONG
	mov	al,es:[di-1]		; AL = last character of name
	cmp	al,'%'
	je	gsv3
	mov	ah,VAR_STR
	cmp	al,'$'
	je	gsv3
	mov	ah,VAR_DOUBLE
	cmp	al,'!'
	je	gsv3
	cmp	al,'#'
	je	gsv3
	mov	al,es:[bp-(VAR_NAMELEN+3)]
	sub	al,'A'			; AL = index of 1st letter
	cmp	al,26
	jae	gsvX
	cbw
	mov	di,ss:[PSP_HEAP]
	add	di,ax
	mov	ah,ss:[di].DEFVARS	; AH = default type for that letter
	test	ah,ah			; set?
	jnz	gsv4			; yes
	mov	ah,VAR_LONG		; no, so it's VAR_LONG without an FPU$
	cmp	word ptr cs:[FPU_TABLE].SEG,0
	je	gsv4			; driver, and VAR_DOUBLE otherwise
	mov	ah,VAR_DOUBLE
	jmp	short gsv4
gsvX:	jmp	strIllegal
gsv3:	dec	bx			; (the suffix isn't part of the name)
gsv4:	push	cx
	push	si
	push	ds
	push	ss
	pop	ds			; (findVar requires DS = heap)
	lea	si,[bp-(VAR_NAMELEN+3)]
	mov	cx,bx			; DS:SI -> name, CX = length
	call	findVar			; DX:SI -> var data, AH = type
	jnc	gsv4a
	sub	ax,ax			; no such var, so its value is zero
	cwd				; (or for a string, it's empty)
	jmp	short gsv8
gsv4a:	mov	es,dx
	cmp	byte ptr [bp-2],VAR_STR	; is a string required?
	jne	gsv4b			; no
	cmp	ah,VAR_STR		; is the variable one?
	jne	gsvX			; no
	mov	ax,es:[si]
	mov	dx,es:[si+2]		; DX:AX -> string
	jmp	short gsv8
gsv4b:	cmp	ah,VAR_LONG
	jne	gsv5
	mov	ax,es:[si]		; AX = value
	jmp	short gsv8
gsv5:	cmp	ah,VAR_DOUBLE
	jne	gsvX
	lds	di,cs:[FPU_TABLE]	; DS:DI -> FPUTBL
	mov	ax,ds
	test	ax,ax
	jz	gsvX
	push	ax
	push	[di].FPU_CVT1DL		; push the conversion function address
	mov	di,sp
	push	es
	push	si			; push a pointer to the double
	call	dword ptr ss:[di]	; and replace it with a long
	pop	ax			; AX = value
	add	sp,6			; (discard the high word, address)
gsv8:	pop	ds
	pop	si
	pop	cx
	mov	sp,bp
	pop	bp
	pop	es
	pop	bx
	clc
	ret
ENDPROC	getStrVar

CODE	ENDS

	end
