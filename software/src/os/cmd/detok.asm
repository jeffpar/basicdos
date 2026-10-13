;
; BASIC-DOS Tokenized BASIC File Loader
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; BAS files saved by IBM PC BASIC (BASICA) and GW-BASIC are usually tokenized:
; after an FFh signature byte, each line consists of a link word (zero at the
; end of the program), a line number, and the line's tokens, ending with zero.
; loadTokens converts each line back into text (as LIST would display it) and
; stores it in the program's text blocks, as cmdLoad does for text files.
;
; Tokens are mostly keywords (80h-FFh, or FDh-FFh followed by a second byte),
; but some are numeric constants (0Bh-1Fh), including MBF ("Microsoft Binary
; Format") floating-point constants, which we convert to IEEE doubles and then
; format with the FPU$ driver.  Tokens in strings, remarks, and DATA statements
; are not tokens (except for FFh), so we track those states, too.
;
	include	cmd.inc

CODE    SEGMENT

	IF DETOK			; (see cmd.inc)

	include	fpu.inc

	EXTNEAR	<readInput,allocText,getFPUFunc>
	EXTLONG	<FPU_TABLE>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

DT_QUOTE	equ	01h		; inside a string
DT_REM		equ	02h		; inside a remark
DT_DATA		equ	04h		; inside a DATA statement

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; loadTokens
;
; Inputs:
;	DS:SI -> FFh signature byte in LINEBUF, CX = # bytes at DS:SI
;	ES:DI -> next available byte in the current text block
;
; Outputs:
;	Carry clear if successful, set if error (eg, a line that's too long)
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	loadTokens
	push	bx
	push	bp
	inc	si			; skip the signature
	dec	cx
	jmp	short lt1
lt8:	stc
lt9:	pop	bp
	pop	bx
	ret
lt1:	call	dtWord			; AX = link to next line
	test	ax,ax			; end of program?
	jz	lt9			; yes (and carry is clear)
	mov	ax,es:[BLK_SIZE]
	sub	ax,di
	cmp	ax,300			; room for the longest line?
	jae	lt2			; yes
	push	cx
	push	si
	call	allocText		; ES:DI -> new text block
	pop	si
	pop	cx
	jc	lt9
lt2:	call	dtWord			; AX = line number (ie, label)
	stosw
	mov	bp,di			; BP -> line length
	stosb
	mov	dl,0			; DL = DT_* state

lt3:	mov	ax,di
	sub	ax,bp
	cmp	ax,256			; is line too long (> 255 chars)?
	ja	lt8			; yes
	call	dtByte
	test	al,al			; end of line?
	jz	lt7			; yes
	cmp	al,0FFh			; FFh is always a prefix
	je	ltTok
	test	dl,DT_QUOTE OR DT_REM	; any other byte in a string or
	jnz	ltChr			; remark is just a character
	cmp	al,':'
	je	ltCol
	test	dl,DT_DATA
	jnz	ltChr
	cmp	al,80h
	jae	ltTok
	cmp	al,20h
	jae	ltChr
	cmp	al,0Bh
	jb	ltChr			; (eg, TAB)
	jmp	ltNum

ltChr:	stosb
	cmp	al,'"'
	jne	lt3
	test	dl,DT_REM
	jnz	lt3
	xor	dl,DT_QUOTE
	jmp	lt3
;
; MSBASIC stores "ELSE" as ":ELSE" and "'" as ":REM'".
;
ltCol:	and	dl,NOT DT_DATA
	call	dtByte
	cmp	al,0A1h			; ELSE?
	je	ltTok			; yes, so skip the colon
	cmp	al,8Fh			; REM?
	jne	lc2			; no
	call	dtByte
	cmp	al,0D9h			; apostrophe?
	je	ltTok			; yes, so skip the colon and REM
	call	dtUnget
	mov	al,':'
	stosb
	mov	al,8Fh
	jmp	short ltTok
lc2:	call	dtUnget
	mov	al,':'
	jmp	ltChr

lt7:	mov	ax,di
	sub	ax,bp
	dec	ax			; AX = line length
	mov	es:[bp],al
	mov	es:[BLK_FREE],di
	jmp	lt1
;
; Keyword tokens: 81h-F4h, or FDh-FFh followed by 81h-A8h.
;
ltTok:	mov	dh,al			; DH = token (or prefix)
	sub	bx,bx			; BX = table #
	cmp	al,0FDh
	jb	tk1
	mov	bl,al
	sub	bl,0FCh
	call	dtByte			; AL = 2nd byte of token
tk1:	sub	al,81h			; AL = token index
	jb	tk9
	cmp	al,cs:DT_COUNTS[bx]
	jae	tk9			; unknown token
	shl	bx,1
	mov	bx,cs:DT_TABLES[bx]	; CS:BX -> names
tk2:	test	al,al
	jz	tk4
tk3:	cmp	byte ptr cs:[bx],80h	; skip a name
	inc	bx
	jb	tk3
	dec	al
	jmp	tk2
tk4:	mov	al,cs:[bx]
	inc	bx
	mov	ah,al
	and	al,7Fh
	jz	tk5
	stosb
tk5:	test	ah,ah
	jns	tk4
	cmp	dh,8Fh			; REM?
	jne	tk6
	or	dl,DT_REM
tk6:	cmp	dh,84h			; DATA?
	jne	tk7
	or	dl,DT_DATA
tk7:	cmp	dh,0D9h			; apostrophe?
	jne	tk8
	or	dl,DT_REM
tk8:	cmp	dh,0B1h			; WHILE (followed by E9h)?
	jne	tk9
	call	dtByte
	cmp	al,0E9h
	je	tk9
	call	dtUnget
tk9:	jmp	lt3
;
; Numeric constants: 0Bh (octal), 0Ch (hex), 0Dh-0Eh (line #), 0Fh (byte),
; 11h-1Bh (0-10), 1Ch (signed word), 1Dh (MBF single), and 1Fh (MBF double).
;
ltNum:	mov	bx,10			; BL = base, BH = flags
	cmp	al,1Dh
	jae	ltFlt
	cmp	al,11h
	jb	ln1
	sub	al,11h			; AL = 0-10 (or 0Bh for 1Ch)
	cbw
	cmp	al,0Bh
	jb	ln8
	mov	bh,PF_SIGN
	jmp	short ln7
ln1:	cmp	al,0Fh
	jne	ln2
	call	dtByte
	mov	ah,0
	jmp	short ln8
ln2:	cmp	al,0Dh
	jae	ln7
	mov	bl,8
	mov	ah,'O'
	cmp	al,0Ch
	jne	ln3
	mov	bl,16
	mov	ah,'H'
ln3:	mov	al,'&'
	stosw
ln7:	call	dtWord
ln8:	push	cx
	push	dx
	push	si
	cwd
	test	bh,PF_SIGN
	jnz	ln9
	sub	dx,dx
ln9:	xchg	si,ax			; DX:SI = value
	sub	cx,cx			; CX = 0 (no minimum length)
	DOSUTIL	ITOA			; AL = # digits stored at ES:DI
	cbw
	add	di,ax
	pop	si
	pop	dx
	pop	cx
	jmp	lt3
;
; Convert an MBF single (1Dh) or double (1Fh) to an IEEE double, and format
; it with FPU_DTOA (7 significant digits for a single, 15 for a double).
; MBF numbers have a 1-byte exponent (biased by 129, or zero for zero) after
; the mantissa, whose top bit is the sign; IEEE doubles have a sign bit and an
; 11-bit exponent (biased by 1023) before a 52-bit mantissa.  As in MSBASIC
; listings, doubles get a '#' suffix, and singles that are whole numbers get a
; '!' suffix, so that they remain floating-point.
;
ltFlt:	sub	sp,8
	mov	bx,sp			; SS:BX -> 8-byte buffer
	mov	ah,0FFh			; AH = precision for a double
	mov	dh,8
	cmp	al,1Fh			; double?
	je	lf1			; yes
	mov	ah,80h+7		; AH = precision for a single
	sub	dx,dx			; (DL is 0 here, since numbers
	mov	[bx],dx			; can't appear in strings, etc)
	mov	[bx+2],dx
	add	bx,4
	mov	dh,4
lf1:	call	dtByte
	mov	[bx],al
	inc	bx
	dec	dh
	jnz	lf1
	mov	bx,sp
	mov	al,[bx+7]		; AL = MBF exponent
	test	al,al			; zero?
	jnz	lf2			; no
	mov	al,'0'
	stosb
	jmp	short lf8
lf2:	push	ax			; save precision and exponent
	mov	ah,[bx+6]		; AH = sign
	push	ax
	and	byte ptr [bx+6],7Fh
	mov	byte ptr [bx+7],0
	mov	dh,3
lf3:	shr	word ptr [bx+6],1	; shift the mantissa right 3 bits
	rcr	word ptr [bx+4],1
	rcr	word ptr [bx+2],1
	rcr	word ptr [bx],1
	dec	dh
	jnz	lf3
	pop	ax
	and	ah,80h
	or	[bx+7],ah		; set the sign bit
	mov	ah,0
	add	ax,1023-129		; AX = IEEE exponent
	shl	ax,1
	shl	ax,1
	shl	ax,1
	shl	ax,1
	or	[bx+6],ax
	pop	ax			; AH = precision again
	cmp	word ptr cs:[FPU_TABLE].SEG,0
	je	lf8			; no FPU$ driver
	push	bp
	push	cx
	push	si
	push	ax
	mov	si,bx			; DS:SI -> double
	mov	bx,FPU_DTOA
	call	getFPUFunc		; DX:AX -> FPU_DTOA
	push	dx
	push	ax
	mov	bp,sp
	mov	ax,[bp+4]
	mov	al,ah			; AL = precision
	mov	ah,0			; AH = flags (none)
	sub	dx,dx			; DX = width (none)
	mov	cx,FPU_MAXCHARS
	push	di			; save start of chars
	call	dword ptr [bp]
	pop	bx			; BX = start of chars
	mov	al,'#'
	cmp	byte ptr [bp+5],0FFh	; double?
	lea	sp,[bp+6]		; (LEA doesn't change flags)
	je	lf6			; yes, it always gets a '#'
	mov	cx,di
	sub	cx,bx			; CX = # chars
	xchg	di,bx
	mov	al,'.'
	repne	scasb			; any decimal point?
	xchg	di,bx
	je	lf7			; yes
	mov	al,'!'
lf6:	stosb
lf7:	pop	si
	pop	cx
	pop	bp
lf8:	add	sp,8
	mov	dl,0
	jmp	lt3
ENDPROC	loadTokens

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dtWord
;
; Outputs:
;	AX = next word (zero at the end of the file)
;
DEFPROC	dtWord
	call	dtByte
	mov	ah,al
	call	dtByte
	xchg	al,ah
	ret
ENDPROC	dtWord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dtByte
;
; Returns the next byte at DS:SI (CX bytes remain), refilling LINEBUF from
; the input file as needed; dtUnget backs up one byte.
;
; Outputs:
;	AL = next byte (zero at the end of the file)
;
; Modifies:
;	AL, CX, SI
;
DEFPROC	dtByte
	jcxz	gb1
gb0:	lodsb
	dec	cx
	ret
gb1:	push	ax
	push	bx
	push	dx
	mov	bx,ds:[PSP_HEAP]
	lea	si,[bx].LINEBUF
	mov	cx,size LINEBUF
	call	readInput		; AX = # bytes read
	jnc	gb2
	sub	ax,ax
gb2:	xchg	cx,ax
	pop	dx
	pop	bx
	pop	ax
	test	cx,cx
	jnz	gb0
	mov	al,0
	ret
	DEFLBL	dtUnget,near
	dec	si
	inc	cx
	ret
ENDPROC	dtByte

	DEFLBL	DT_TABLES,word
	dw	DT_NAMES1, DT_NAMES2, DT_NAMES3, DT_NAMES4
	DEFLBL	DT_COUNTS,byte
	db	0F4h-80h, 8Bh-80h, 0A8h-80h, 0A5h-80h
;
; Keyword names, in token order; the last character of each name has bit 7
; set, and unused tokens have no name (just 80h).
;
DT_NAMES1	label	byte		; tokens 81h-F4h
	db	'EN','D'+80h,'FO','R'+80h,'NEX','T'+80h,'DAT','A'+80h
	db	'INPU','T'+80h,'DI','M'+80h,'REA','D'+80h,'LE','T'+80h
	db	'GOT','O'+80h,'RU','N'+80h,'I','F'+80h,'RESTOR','E'+80h
	db	'GOSU','B'+80h,'RETUR','N'+80h,'RE','M'+80h,'STO','P'+80h
	db	'PRIN','T'+80h,'CLEA','R'+80h,'LIS','T'+80h,'NE','W'+80h
	db	'O','N'+80h,'WAI','T'+80h,'DE','F'+80h,'POK','E'+80h
	db	'CON','T'+80h,80h,80h,'OU','T'+80h,'LPRIN','T'+80h
	db	'LLIS','T'+80h,80h,'WIDT','H'+80h,'ELS','E'+80h,'TRO','N'+80h
	db	'TROF','F'+80h,'SWA','P'+80h,'ERAS','E'+80h,'EDI','T'+80h
	db	'ERRO','R'+80h,'RESUM','E'+80h,'DELET','E'+80h,'AUT','O'+80h
	db	'RENU','M'+80h,'DEFST','R'+80h,'DEFIN','T'+80h
	db	'DEFSN','G'+80h,'DEFDB','L'+80h,'LIN','E'+80h,'WHIL','E'+80h
	db	'WEN','D'+80h,'CAL','L'+80h,80h,80h,80h,'WRIT','E'+80h
	db	'OPTIO','N'+80h,'RANDOMIZ','E'+80h,'OPE','N'+80h
	db	'CLOS','E'+80h,'LOA','D'+80h,'MERG','E'+80h,'SAV','E'+80h
	db	'COLO','R'+80h,'CL','S'+80h,'MOTO','R'+80h,'BSAV','E'+80h
	db	'BLOA','D'+80h,'SOUN','D'+80h,'BEE','P'+80h,'PSE','T'+80h
	db	'PRESE','T'+80h,'SCREE','N'+80h,'KE','Y'+80h,'LOCAT','E'+80h
	db	80h,'T','O'+80h,'THE','N'+80h,'TAB','('+80h,'STE','P'+80h
	db	'US','R'+80h,'F','N'+80h,'SPC','('+80h,'NO','T'+80h
	db	'ER','L'+80h,'ER','R'+80h,'STRING','$'+80h,'USIN','G'+80h
	db	'INST','R'+80h,27h+80h,'VARPT','R'+80h,'CSRLI','N'+80h
	db	'POIN','T'+80h,'OF','F'+80h,'INKEY','$'+80h,80h,80h,80h,80h
	db	80h,80h,80h,'>'+80h,'='+80h,'<'+80h,'+'+80h,'-'+80h,'*'+80h
	db	'/'+80h,'^'+80h,'AN','D'+80h,'O','R'+80h,'XO','R'+80h
	db	'EQ','V'+80h,'IM','P'+80h,'MO','D'+80h,'\'+80h
DT_NAMES2	label	byte		; tokens FD81h-FD8Bh
	db	'CV','I'+80h,'CV','S'+80h,'CV','D'+80h,'MKI','$'+80h
	db	'MKS','$'+80h,'MKD','$'+80h,80h,80h,80h,80h,'EXTER','R'+80h
DT_NAMES3	label	byte		; tokens FE81h-FEA8h
	db	'FILE','S'+80h,'FIEL','D'+80h,'SYSTE','M'+80h,'NAM','E'+80h
	db	'LSE','T'+80h,'RSE','T'+80h,'KIL','L'+80h,'PU','T'+80h
	db	'GE','T'+80h,'RESE','T'+80h,'COMMO','N'+80h,'CHAI','N'+80h
	db	'DATE','$'+80h,'TIME','$'+80h,'PAIN','T'+80h,'CO','M'+80h
	db	'CIRCL','E'+80h,'DRA','W'+80h,'PLA','Y'+80h,'TIME','R'+80h
	db	'ERDE','V'+80h,'IOCT','L'+80h,'CHDI','R'+80h,'MKDI','R'+80h
	db	'RMDI','R'+80h,'SHEL','L'+80h,'ENVIRO','N'+80h,'VIE','W'+80h
	db	'WINDO','W'+80h,'PMA','P'+80h,'PALETT','E'+80h,'LCOP','Y'+80h
	db	'CALL','S'+80h,80h,80h,'NOIS','E'+80h,'PCOP','Y'+80h
	db	'TER','M'+80h,'LOC','K'+80h,'UNLOC','K'+80h
DT_NAMES4	label	byte		; tokens FF81h-FFA5h
	db	'LEFT','$'+80h,'RIGHT','$'+80h,'MID','$'+80h,'SG','N'+80h
	db	'IN','T'+80h,'AB','S'+80h,'SQ','R'+80h,'RN','D'+80h
	db	'SI','N'+80h,'LO','G'+80h,'EX','P'+80h,'CO','S'+80h
	db	'TA','N'+80h,'AT','N'+80h,'FR','E'+80h,'IN','P'+80h
	db	'PO','S'+80h,'LE','N'+80h,'STR','$'+80h,'VA','L'+80h
	db	'AS','C'+80h,'CHR','$'+80h,'PEE','K'+80h,'SPACE','$'+80h
	db	'OCT','$'+80h,'HEX','$'+80h,'LPO','S'+80h,'CIN','T'+80h
	db	'CSN','G'+80h,'CDB','L'+80h,'FI','X'+80h,'PE','N'+80h
	db	'STIC','K'+80h,'STRI','G'+80h,'EO','F'+80h,'LO','C'+80h
	db	'LO','F'+80h


	ENDIF	; DETOK

CODE	ENDS

	end
