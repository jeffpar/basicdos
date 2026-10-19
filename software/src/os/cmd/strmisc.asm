;
; BASIC-DOS String Functions (Miscellaneous)
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The string functions that don't extract, search, or convert strings (HEX$,
; OCT$, UCASE$, LCASE$, INKEY$, DATE$, TIME$, and FRE) moved here from
; STRHELP.ASM when it reached MASM's symbol space limit.
;
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<allocStr,compactStrs,isTempStr,newStr,getStrLen>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strHex (HEX$) and strOct (OCT$)
;
; Negative values are treated as unsigned 32-bit values (eg, HEX$(-1) is
; "FFFFFFFF").
;
; Inputs:
;	32-bit return value
;	32-bit value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strHex,FAR
	mov	bl,16
	DEFLBL	strBase,near
	RETVAR	retBase,dword
	ARGVAR	baseNum,dword
	LOCVAR	baseBuf,byte,12
	ENTER
	mov	si,[baseNum].LOW
	mov	dx,[baseNum].HIW	; DX:SI = value
	mov	bh,PF_LONG
	sub	cx,cx
	push	ss
	pop	es
	lea	di,[baseBuf]
	push	di
	DOSUTIL	ITOA			; AL = # of digits
	pop	si
	mov	cl,al
	mov	ch,0
	call	newStr
	mov	[retBase].OFF,ax
	mov	[retBase].SEG,dx
	LEAVE
	RETURN
ENDPROC	strHex

DEFPROC	strOct,FAR
	mov	bl,8
	jmp	strBase
ENDPROC	strOct

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strUCase (UCASE$) and strLCase (LCASE$)
;
; Inputs:
;	32-bit return value
;	string value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strUCase,FAR
	mov	bx,('z' SHL 8) OR 'a'	; BL = 'a', BH = 'z'
	DEFLBL	strCase,near
	RETVAR	retCase,dword
	ARGVAR	pCaseStr,dword
	ENTER
	push	ds
	lea	si,[pCaseStr]
	call	getStrLen		; CX = length, ES:DI = string
	jcxz	sc9
	call	isTempStr		; can we modify the string in place?
	je	sc1			; yes
	push	bx
	call	allocStr		; ES:DI -> new string
	pop	bx
	lds	si,[pCaseStr]
	push	di
	movsb
	mov	cl,es:[di-1]
	rep	movsb			; copy the string
	pop	di
	mov	[pCaseStr].OFF,di	; and use the copy instead
	mov	[pCaseStr].SEG,es
sc1:	push	di
	mov	cl,es:[di]
	inc	di
sc2:	mov	al,es:[di]
	cmp	al,bl
	jb	sc3
	cmp	al,bh
	ja	sc3
	xor	al,20h			; flip the case
	mov	es:[di],al
sc3:	inc	di
	loop	sc2
	pop	di
sc9:	mov	ax,[pCaseStr].OFF
	mov	[retCase].OFF,ax
	mov	ax,[pCaseStr].SEG
	mov	[retCase].SEG,ax
	pop	ds
	LEAVE
	RETURN
ENDPROC	strUCase

DEFPROC	strLCase,FAR
	mov	bx,('Z' SHL 8) OR 'A'	; BL = 'A', BH = 'Z'
	jmp	strCase
ENDPROC	strLCase

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strInkey (INKEY$)
;
; Returns the next key (if any) without waiting; extended keys (eg, cursor
; keys) are returned as two characters: a null and the scan code.
;
; Inputs:
;	32-bit return value
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	strInkey,FAR
	RETVAR	retInkey,dword
	LOCVAR	keyBuf,word
	ENTER
	sub	cx,cx
	mov	dl,0FFh
	mov	ah,DOS_TTY_IO
	int	21h			; ZF set if no key
	jz	sk8
	inc	cx
	mov	byte ptr [keyBuf],al
	test	al,al			; extended key?
	jnz	sk8			; no
	mov	ah,DOS_TTY_IO
	int	21h
	mov	byte ptr [keyBuf+1],al	; scan code
	inc	cx
sk8:	lea	si,[keyBuf]
	call	newStr
	mov	[retInkey].OFF,ax
	mov	[retInkey].SEG,dx
	LEAVE
	RETURN
ENDPROC	strInkey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strDate (DATE$) and strTime (TIME$)
;
; Returns the date as "MM-DD-YYYY" or the time as "HH:MM:SS".
;
; Inputs:
;	32-bit return value
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strDate,FAR
	RETVAR	retDate,dword
	LOCVAR	dateBuf,byte,10
	ENTER
	push	ss
	pop	es
	lea	di,[dateBuf]
	mov	ah,DOS_MSC_GETDATE
	int	21h			; CX = year, DH = month, DL = day
	mov	bx,'--'
	mov	al,dh
	call	putDigits		; "MM-"
	mov	al,dl
	call	putDigits		; "DD-"
	xchg	ax,cx
	mov	cl,100
	div	cl			; AL = century, AH = year
	push	ax
	call	put2Digits		; "YY"
	pop	ax
	mov	al,ah
	call	put2Digits		; "YY"
	mov	cx,10
	jmp	short strDT
ENDPROC	strDate

DEFPROC	strTime,FAR
	RETVAR	retTime,dword
	LOCVAR	timeBuf,byte,10
	ENTER
	push	ss
	pop	es
	lea	di,[timeBuf]
	mov	ah,DOS_MSC_GETTIME
	int	21h			; CH = hour, CL = min, DH = sec
	mov	bx,'::'
	mov	al,ch
	call	putDigits		; "HH:"
	mov	al,cl
	call	putDigits		; "MM:"
	mov	al,dh
	call	put2Digits		; "SS"
	mov	cx,8
	DEFLBL	strDT,near
	lea	si,[timeBuf]
	call	newStr
	mov	[retTime].OFF,ax
	mov	[retTime].SEG,dx
	LEAVE
	RETURN
ENDPROC	strTime

;
; putDigits stores AL as two decimal digits at ES:DI, followed by BL.
;
DEFPROC	putDigits
	call	put2Digits
	mov	al,bl
	stosb
	ret
ENDPROC	putDigits

DEFPROC	put2Digits
	aam				; AH = tens, AL = ones
	xchg	al,ah
	add	ax,'00'
	stosw
	ret
ENDPROC	put2Digits

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strFre (FRE)
;
; Compacts the string pool and then returns the amount of free memory, in
; bytes.  The argument is ignored.
;
; Inputs:
;	32-bit return value
;	32-bit value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strFre,FAR
	RETVAR	retFre,dword
	ARGVAR	freArg,dword
	ENTER
	push	ds
	call	compactStrs
	sub	cx,cx			; CX = memory block #
	sub	si,si			; SI = free paragraphs
fr1:	mov	dl,1			; DL = 1 (free blocks only)
	DOSUTIL	QRYMEM
	jc	fr8
	add	si,dx
	inc	cx
	jmp	fr1
fr8:	xchg	ax,si
	mov	cx,16
	mul	cx			; DX:AX = free bytes
	mov	[retFre].LOW,ax
	mov	[retFre].HIW,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	strFre

CODE	ENDS

	end
