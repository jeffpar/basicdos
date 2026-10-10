;
; DOS 1.x-compatible FCB confidence tests (8086 only).
; Uses no handle APIs or DOS 2.x termination services.
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
	include	macros.inc
	include	dosapi.inc

CHECK	macro	op,left,right
	local	ok
	mov	failat,offset ok
	cmp	left,right
	op	ok
	jmp	failed
ok:
	endm

FCALL	macro	func,faddr
	mov	lastfn,func AND 255
	IFB	<faddr>
	mov	dx,offset fcbtest
	ELSE
	mov	dx,offset faddr
	ENDIF
	mov	ah,func
	int	21h
	endm

FILELEN	equ	16643

CODE	segment
	ASSUME	CS:CODE,DS:CODE,ES:CODE,SS:CODE
	org	100h

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; main
;
; Exercise the standard DOS FCB functions and verify file data and size.
;
; Inputs:
;
;	CS = PSP/COM segment
;	PSP command tail = S to enable BIOS serial output
;
; Outputs:
;
;	Prints a pass or failure message, then terminates with INT 20h
;
; Modifies:
;
;	AX, BX, CX, DX, SI, DI, DS, ES, SP
;
DEFPROC	main
	cld
	push	cs
	pop	ds
	push	cs
	pop	es
	mov	sp,offset stktop
	cmp	byte ptr ds:[PSP_CMDTAIL],0
	je	start0
	inc	srlout
	mov	ax,0E3h			; initialize COM1 for PC.js output on PC DOS
	xor	dx,dx
	int	14h
start0:	mov	dx,offset strtmsg
	call	print
	mov	di,offset expect
	mov	cx,FILELEN
	xor	ax,ax
fill:
	stosb
	inc	ax
	loop	fill
	mov	si,offset pattern
	mov	di,offset findfcb
	mov	ax,2900h
	int	21h
	CHECK	je,al,1
	mov	si,offset fname
	mov	di,offset fcbtest
	mov	ax,2900h
	int	21h
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCB_NAME]>,'CF'
	mov	si,offset badname
	mov	di,offset findfcb
	mov	ax,2900h
	int	21h
	CHECK	je,al,0FFh
;
; Parse flags preserve only omitted fields, not the tails of supplied ones.
;
	mov	si,offset extname
	mov	di,offset fcbtest
	mov	ax,290Eh
	mov	lastfn,DOS_FCB_PARSE AND 255
	int	21h
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCB_NAME]>,'CF'
	CHECK	je,<word ptr [fcbtest+FCB_NAME+8]>,2042h
	mov	si,offset shortnm
	mov	di,offset fcbtest
	mov	ax,290Eh
	int	21h
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCB_NAME]>,2054h
	CHECK	je,<byte ptr [fcbtest+FCB_NAME+6]>,' '
	CHECK	je,<word ptr [fcbtest+FCB_NAME+8]>,2042h
	mov	si,offset fname
	mov	di,offset fcbtest
	mov	ax,2900h
	int	21h
	FCALL	DOS_FCB_DELETE		; remove leftovers from an interrupted test
	FCALL	DOS_FCB_CREATE		; create
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCB_RECSIZE]>,128
	CHECK	je,<word ptr [fcbtest+FCBF_FILESIZE]>,0
;
; 130 sequential 128-byte records cross the 128-record block boundary.
;
	mov	byte ptr [fcbtest+FCBF_CURREC],0
	mov	bx,offset expect
	mov	si,130
seqwr:
	mov	dx,bx
	mov	ah,1Ah
	int	21h
	FCALL	DOS_FCB_SWRITE
	CHECK	je,al,0
	add	bx,128
	dec	si
	jnz	seqwr
	CHECK	je,<word ptr [fcbtest+FCB_CURBLK]>,1
	CHECK	je,<byte ptr [fcbtest+FCBF_CURREC]>,2
;
; Change record size to 1 and write the final three bytes sequentially.
;
	mov	word ptr [fcbtest+FCB_RECSIZE],1
	mov	word ptr [fcbtest+FCB_CURBLK],130
	mov	byte ptr [fcbtest+FCBF_CURREC],0
	mov	si,3
smallwr:
	mov	dx,bx
	mov	ah,1Ah
	int	21h
	FCALL	DOS_FCB_SWRITE
	CHECK	je,al,0
	inc	bx
	dec	si
	jnz	smallwr
	CHECK	je,<word ptr [fcbtest+FCBF_FILESIZE]>,FILELEN
;
; Set-relative uses 128 records per block even for non-128-byte records.
;
	FCALL	DOS_FCB_SETREL
	CHECK	je,<word ptr [fcbtest+FCBF_RELREC]>,FILELEN
	mov	word ptr [fcbtest+FCB_RECSIZE],64
	mov	word ptr [fcbtest+FCB_CURBLK],1
	mov	byte ptr [fcbtest+FCBF_CURREC],7
	mov	word ptr [fcbtest+FCBF_RELREC+2],0AB00h
	FCALL	DOS_FCB_SETREL
	CHECK	je,<word ptr [fcbtest+FCBF_RELREC]>,135
	CHECK	je,<word ptr [fcbtest+FCBF_RELREC+2]>,0AB00h
;
; Random single write must not advance the relative or current record.
;
	mov	word ptr [fcbtest+FCBF_RELREC],7
	mov	di,offset expect+7*64
	mov	cx,64
	mov	al,0A5h
	rep	stosb
	mov	dx,offset expect+7*64
	mov	ah,1Ah
	int	21h
	FCALL	DOS_FCB_RWRITE
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCBF_RELREC]>,7
	CHECK	je,<byte ptr [fcbtest+FCBF_CURREC]>,7
;
; Block write crosses a sector and advances both record pointers.
;
	mov	word ptr [fcbtest+FCB_RECSIZE],1
	mov	word ptr [fcbtest+FCBF_RELREC+2],0
	mov	word ptr [fcbtest+FCBF_RELREC],509
	mov	di,offset expect+509
	mov	cx,9
	mov	al,05Ah
	rep	stosb
	mov	dx,offset expect+509
	mov	ah,1Ah
	int	21h
	mov	cx,9
	FCALL	DOS_FCB_RBWRITE
	CHECK	je,al,0
	CHECK	je,cx,9
	CHECK	je,<word ptr [fcbtest+FCBF_RELREC]>,518
	CHECK	je,<word ptr [fcbtest+FCB_CURBLK]>,4
	CHECK	je,<byte ptr [fcbtest+FCBF_CURREC]>,6
	FCALL	DOS_FCB_CLOSE
	CHECK	je,al,0
;
; Get size on an unopened FCB, rounded up to records.
;
	mov	word ptr [fcbtest+FCB_RECSIZE],128
	FCALL	DOS_FCB_SIZE
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCBF_RELREC]>,131
	FCALL	DOS_FCB_OPEN
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCBF_FILESIZE]>,FILELEN
	CHECK	je,<word ptr [fcbtest+FCBF_FILESIZE]+2>,0
;
; Read and compare every byte, followed by EOF.
;
	mov	word ptr [fcbtest+FCB_RECSIZE],1
	mov	word ptr [fcbtest+FCBF_RELREC],0
	mov	word ptr [fcbtest+FCBF_RELREC]+2,0
	mov	dx,offset actual
	mov	ah,1Ah
	int	21h
	mov	cx,FILELEN
	FCALL	DOS_FCB_RBREAD
	CHECK	je,al,0
	CHECK	je,cx,FILELEN
	mov	si,offset expect
	mov	di,offset actual
	mov	cx,FILELEN
	repe	cmpsb
	je	dataok
	jmp	failed
dataok:
	mov	cx,1
	FCALL	DOS_FCB_RBREAD
	CHECK	je,al,1
	CHECK	je,cx,0
;
; Verify all complete records sequentially and cross the block boundary.
;
	mov	word ptr [fcbtest+FCB_RECSIZE],128
	mov	word ptr [fcbtest+FCB_CURBLK],0
	mov	byte ptr [fcbtest+FCBF_CURREC],0
	mov	si,offset expect
	mov	bx,130
seqrd:	FCALL	DOS_FCB_SREAD
	CHECK	je,al,0
	mov	di,offset actual
	mov	cx,128
	repe	cmpsb
	je	seqok
	jmp	failed
seqok:	dec	bx
	jnz	seqrd
	CHECK	je,<word ptr [fcbtest+FCB_CURBLK]>,1
	CHECK	je,<byte ptr [fcbtest+FCBF_CURREC]>,2
;
; Random read of a partial record pads its tail, without advancing.
;
	mov	word ptr [fcbtest+FCB_RECSIZE],128
	mov	word ptr [fcbtest+FCBF_RELREC],130
	FCALL	DOS_FCB_RREAD
	CHECK	je,al,3
	CHECK	je,<word ptr [fcbtest+FCB_CURBLK]>,1
	CHECK	je,<byte ptr [fcbtest+FCBF_CURREC]>,2
	CHECK	je,<word ptr [fcbtest+FCBF_RELREC]>,130
	mov	si,offset expect+16640
	mov	di,offset actual
	mov	cx,3
	repe	cmpsb
	je	partok
	jmp	failed
partok:
	mov	cx,125
	xor	ax,ax
	repe	scasb
	je	padded
	jmp	failed
padded:
;
; Sequential partial record advances; next sequential read reports EOF.
;
	FCALL	DOS_FCB_SREAD
	CHECK	je,al,3
	CHECK	je,<byte ptr [fcbtest+FCBF_CURREC]>,3
	FCALL	DOS_FCB_SREAD
	CHECK	je,al,1
;
; DTA crossing a segment boundary fails without transferring a record.
;
	mov	dx,0FFF0h
	mov	ah,1Ah
	int	21h
	mov	word ptr [fcbtest+FCBF_RELREC],0
	FCALL	DOS_FCB_RREAD
	CHECK	je,al,2
	mov	dx,offset actual
	mov	ah,1Ah
	int	21h
	FCALL	DOS_FCB_CLOSE
	CHECK	je,al,0
;
; Extended FCBs use the same opened FCB address for all record operations.
;
	mov	si,offset fname
	mov	di,offset xfcb+7
	mov	ax,2900h
	int	21h
	FCALL	DOS_FCB_OPEN,xfcb
	CHECK	je,al,0
	mov	word ptr [xfcb+7+FCB_RECSIZE],1
	mov	word ptr [xfcb+7+FCBF_RELREC],0
	mov	cx,4
	FCALL	DOS_FCB_RBREAD,xfcb
	CHECK	je,al,0
	CHECK	je,cx,4
	mov	si,offset expect
	mov	di,offset actual
	mov	cx,4
	repe	cmpsb
	je	xdataok
	jmp	failed
xdataok:
	FCALL	DOS_FCB_CLOSE,xfcb
	CHECK	je,al,0
	FCALL	DOS_FCB_FFIRST,xfcb
	CHECK	je,al,0
	CHECK	je,<byte ptr [actual]>,0FFh
	mov	si,offset actual+8
	mov	di,offset fcbtest+FCB_NAME
	mov	cx,11
	repe	cmpsb
	je	xfindok
	jmp	failed
xfindok:
;
; Zero-record block writes truncate, extend, and empty the file.
;
	FCALL	DOS_FCB_OPEN
	CHECK	je,al,0
	mov	word ptr [fcbtest+FCB_RECSIZE],1
	mov	word ptr [fcbtest+FCBF_RELREC],1001
	mov	cx,0
	FCALL	DOS_FCB_RBWRITE
	CHECK	je,al,0
	CHECK	je,cx,0
	CHECK	je,<word ptr [fcbtest+FCBF_FILESIZE]>,1001
	mov	word ptr [fcbtest+FCBF_RELREC],FILELEN
	mov	cx,0
	FCALL	DOS_FCB_RBWRITE
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCBF_FILESIZE]>,FILELEN
	FCALL	DOS_FCB_CLOSE
	CHECK	je,al,0
	FCALL	DOS_FCB_OPEN
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCBF_FILESIZE]>,FILELEN
	mov	word ptr [fcbtest+FCB_RECSIZE],1
	mov	word ptr [fcbtest+FCBF_RELREC],0
	mov	cx,1001
	FCALL	DOS_FCB_RBREAD
	CHECK	je,al,0
	CHECK	je,cx,1001
	mov	si,offset expect
	mov	di,offset actual
	mov	cx,1001
	repe	cmpsb
	je	rszok
	jmp	failed
rszok:
	mov	word ptr [fcbtest+FCBF_RELREC],0
	mov	cx,0
	FCALL	DOS_FCB_RBWRITE
	CHECK	je,al,0
	FCALL	DOS_FCB_CLOSE
	CHECK	je,al,0
	mov	word ptr [fcbtest+FCB_RECSIZE],1
	FCALL	DOS_FCB_SIZE
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCBF_RELREC]>,0
;
; Create a second match for find-next and a rename collision.
;
	mov	si,offset renfile
	mov	di,offset xfcb+7
	mov	ax,2900h
	int	21h
	FCALL	DOS_FCB_CREATE,xfcb
	CHECK	je,al,0
	FCALL	DOS_FCB_CLOSE,xfcb
	CHECK	je,al,0
;
; Wildcard find first/next, rename, delete, and missing-file results.
;
	mov	si,offset pattern
	mov	di,offset findfcb
	mov	ax,2900h
	int	21h
	CHECK	je,al,1
	FCALL	DOS_FCB_FFIRST,findfcb
	CHECK	je,al,0
	mov	si,offset actual+1
	mov	di,offset fcbtest+FCB_NAME
	mov	cx,11
	repe	cmpsb
	je	found
	jmp	failed
found:
	FCALL	DOS_FCB_FNEXT,findfcb
	CHECK	je,al,0
	mov	si,offset actual+1
	mov	di,offset newfile
	mov	cx,11
	repe	cmpsb
	je	nextok
	jmp	failed
nextok:
	FCALL	DOS_FCB_FNEXT,findfcb
	CHECK	je,al,0FFh
	mov	si,offset newfile
	mov	di,offset fcbtest+17
	mov	cx,11
	rep	movsb
	FCALL	DOS_FCB_RENAME
	CHECK	je,al,0FFh
	FCALL	DOS_FCB_DELETE,xfcb
	CHECK	je,al,0
	FCALL	DOS_FCB_RENAME
	CHECK	je,al,0
	mov	si,offset renfile
	mov	di,offset fcbtest
	mov	ax,2900h
	int	21h
	FCALL	DOS_FCB_DELETE
	CHECK	je,al,0
	FCALL	DOS_FCB_OPEN
	CHECK	je,al,0FFh
	mov	si,offset fname
	mov	di,offset fcbtest
	mov	ax,2900h
	int	21h
	FCALL	DOS_FCB_CREATE
	CHECK	je,al,0
	FCALL	DOS_FCB_CLOSE
	CHECK	je,al,0
	mov	si,offset renfile
	mov	di,offset fcbtest
	mov	ax,2900h
	int	21h
	FCALL	DOS_FCB_CREATE
	CHECK	je,al,0
	FCALL	DOS_FCB_CLOSE
	CHECK	je,al,0
	FCALL	DOS_FCB_DELETE,findfcb
	CHECK	je,al,0
	FCALL	DOS_FCB_OPEN
	CHECK	je,al,0FFh
	mov	si,offset fname
	mov	di,offset fcbtest
	mov	ax,2900h
	int	21h
	FCALL	DOS_FCB_OPEN
	CHECK	je,al,0FFh
;
; FCBs open files read-only, so two FCBs can open the same file; the first
; write upgrades an FCB's file to read-write, and then no other FCB can write.
; As in PC DOS, each FCB keeps its own file size, so the second FCB reads a
; record that existed when it was opened.
;
	mov	si,offset fname
	mov	di,offset fcbtest
	mov	ax,2900h
	int	21h
	FCALL	DOS_FCB_CREATE
	CHECK	je,al,0
	mov	dx,offset expect
	mov	ah,1Ah
	int	21h
	mov	word ptr [fcbtest+FCBF_RELREC],0
	mov	word ptr [fcbtest+FCBF_RELREC+2],0
	FCALL	DOS_FCB_RWRITE
	CHECK	je,al,0
	FCALL	DOS_FCB_CLOSE
	CHECK	je,al,0
	mov	si,offset fname
	mov	di,offset fcbtwo
	mov	ax,2900h
	int	21h
	FCALL	DOS_FCB_OPEN
	CHECK	je,al,0
	FCALL	DOS_FCB_OPEN,fcbtwo
	CHECK	je,al,0
	mov	word ptr [fcbtest+FCBF_RELREC],1
	FCALL	DOS_FCB_RWRITE
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCBF_FILESIZE]>,256
	mov	dx,offset actual
	mov	ah,1Ah
	int	21h
	mov	word ptr [fcbtwo+FCBF_RELREC],0
	mov	word ptr [fcbtwo+FCBF_RELREC+2],0
	FCALL	DOS_FCB_RREAD,fcbtwo
	CHECK	je,al,0
	mov	si,offset expect
	mov	di,offset actual
	mov	cx,128
	repe	cmpsb
	je	shareok
	jmp	failed
shareok:
	FCALL	DOS_FCB_RWRITE,fcbtwo
	CHECK	je,al,1
	FCALL	DOS_FCB_CLOSE,fcbtwo
	CHECK	je,al,0
;
; A wildcard delete skips a file that's open, but deletes the others.
;
	mov	si,offset renfile
	mov	di,offset fcbtwo
	mov	ax,2900h
	int	21h
	FCALL	DOS_FCB_CREATE,fcbtwo
	CHECK	je,al,0
	FCALL	DOS_FCB_CLOSE,fcbtwo
	CHECK	je,al,0
	FCALL	DOS_FCB_DELETE,findfcb
	CHECK	je,al,0
	FCALL	DOS_FCB_OPEN,fcbtwo
	CHECK	je,al,0FFh
	FCALL	DOS_FCB_CLOSE
	CHECK	je,al,0
	FCALL	DOS_FCB_SIZE
	CHECK	je,al,0
	CHECK	je,<word ptr [fcbtest+FCBF_RELREC]>,2
	FCALL	DOS_FCB_DELETE,findfcb
	CHECK	je,al,0
	FCALL	DOS_FCB_OPEN
	CHECK	je,al,0FFh
;
; Device names (eg, NUL) open the device, and creating one makes no file.
;
	mov	si,offset nulname
	mov	di,offset fcbtwo
	mov	ax,2900h
	int	21h
	FCALL	DOS_FCB_CREATE,fcbtwo
	CHECK	je,al,0
	CHECK	je,<byte ptr [fcbtwo+FCB_DRIVE]>,0
	FCALL	DOS_FCB_SWRITE,fcbtwo
	CHECK	je,al,0
	FCALL	DOS_FCB_CLOSE,fcbtwo
	CHECK	je,al,0
	FCALL	DOS_FCB_OPEN,fcbtwo
	CHECK	je,al,0
	FCALL	DOS_FCB_CLOSE,fcbtwo
	CHECK	je,al,0
	FCALL	DOS_FCB_FFIRST,fcbtwo
	CHECK	je,al,0FFh
	mov	dx,offset passed
	call	print
	int	20h
failed:
	mov	failal,al
	mov	ax,failat
	mov	di,offset failpc+3
	mov	cx,4
failhex:
	push	ax
	and	al,15
	call	hexchr
	mov	[di],al
	dec	di
	pop	ax
	push	cx
	mov	cl,4
	shr	ax,cl
	pop	cx
	loop	failhex
	mov	al,lastfn
	mov	cl,4
	shr	al,cl
	call	hexchr
	mov	failfn,al
	mov	al,lastfn
	and	al,15
	call	hexchr
	mov	failfn+1,al
	mov	al,failal
	mov	cl,4
	shr	al,cl
	call	hexchr
	mov	failrc,al
	mov	al,failal
	and	al,15
	call	hexchr
	mov	failrc+1,al
	mov	dx,offset failmsg
	call	print
	int	20h
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hexchr
;
; Convert a hexadecimal digit to its uppercase ASCII character.
;
; Inputs:
;
;	AL = digit (0-15)
;
; Outputs:
;
;	AL = ASCII character (0-9 or A-F)
;
; Modifies:
;
;	AX
;
DEFPROC	hexchr
	add	al,'0'
	cmp	al,'9'
	jbe	hx9
	add	al,7
hx9:	ret
ENDPROC	hexchr


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; print
;
; Print a DOS string and optionally mirror it to BIOS serial output.
; Pass S on PC DOS to enable the mirror; BASIC-DOS owns COM1.
;
; Inputs:
;
;	DS:DX -> dollar-terminated string
;	srlout = non-zero to enable BIOS serial output
;
; Outputs:
;
;	String written to the console and optional serial port
;
; Modifies:
;
;	AX, DX, SI
;
DEFPROC	print
	mov	ah,9
	int	21h
	cmp	srlout,0
	je	pr9
	mov	si,dx
pr1:
	lodsb
	cmp	al,'$'
	je	pr9
	xor	dx,dx
	mov	ah,1
	int	14h
	jmp	pr1
pr9:
	ret
ENDPROC	print
strtmsg	db	'FCBTESTS starting',13,10,'$'
passed	db	'FCBTESTS passed',13,10,'$'
srlout	db	0
lastfn	db	29h
failmsg	db	'FCBTESTS failed after function '
failfn	db	'00 at '
failpc	db	'0000 AL='
failrc	db	'00',13,10,'$'
failat	dw	0
failal	db	0
extname	db	'.B',0
shortnm	db	'T',0
badname	db	'Z:FCBTST1.DAT',0
fname	db	'FCBTST1.DAT',0
renfile	db	'FCBTST2.DAT',0
pattern	db	'FCBTST?.DAT',0
newfile	db	'FCBTST2 DAT'
nulname	db	'NUL',0
fcbtest	db	size FCBF dup(0)
findfcb	db	size FCBF dup(0)
fcbtwo	db	size FCBF dup(0)
xfcb	db	0FFh,6 dup(0),size FCBF dup(0)
expect	db	FILELEN dup(0)
actual	db	FILELEN dup(0)
	db	512 dup(0)
stktop	label	word
CODE	ends
	end	main
