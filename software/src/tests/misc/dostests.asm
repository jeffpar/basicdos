;
; BASIC-DOS Miscellaneous DOS Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dosapi.inc

MEMSTEP	equ	67		; memory test increment, in paragraphs (a prime number,
			; so that allocation sizes vary more than powers of two)

CODE    SEGMENT

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

	org	5
	DEFLBL	DOS,near

	org	100h

DEFPROC	main
;
; The following REALLOC is not necessary in BASIC-DOS, because it detects
; our COMHEAP signature and resizes us automatically, but if we want to run
; with the same footprint in PC DOS, then we must still resize ourselves.
;
	mov	bx,offset HEAP + MINHEAP
	and	bl,0F0h
	or	bl,0Eh		; BX adjusted to top word of top paragraph
	mov	word ptr [bx],0	; store a zero there so we can simply return
	mov	sp,bx		; lower the stack
	mov	cl,4
	add	bx,15
	shr	bx,cl
	mov	ah,DOS_MEM_REALLOC
	int	21h
;
; In PC DOS 2.x, the DOS_MSC_GETVARS function (52h) sets ES:BX-2 to the
; address of the first MCB segment, ES:BX+4 points to the SFT, etc.  However,
; all you can rely on in BASIC-DOS is ES:BX-2.
;
	mov	ah,DOS_MSC_GETVARS
	int	21h		; ES:BX-2 -> mcb_head
;
; Test the CALL 5 interface.
;
	mov	dx,offset call5test
	call	print
;
; Make a series of increasingly large memory allocations (in MEMSTEP
; increments), until an allocation fails; then verify that an allocation of
; the maximum size reported by the failure succeeds.
;
	mov	dx,offset alloctest
	call	print

	mov	cx,3		; perform the series CX times
m1:	sub	bx,bx		; start with a zero paragraph request
m2:	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h
	jc	m3
	mov	es,ax		; ES = new segment
	mov	ah,DOS_MEM_FREE
	int	21h
	ASSERT	NC
	add	bx,MEMSTEP	; ask for MEMSTEP more paragraphs
	jnc	m2
	jmp	short m4	; we should never get this far
m3:	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h		; BX = max paragraphs available
	jc	m4		; so this allocation should succeed
	mov	es,ax		; ES = new segment
	mov	ah,DOS_MEM_FREE
	int	21h
	jc	m4
	mov	dx,offset progress
	call	print
	loop	m1
	clc
m4:	call	result
;
; Create a new file, write a string to it, close it, and then verify it.
;
	push	ds
	pop	es
	mov	dx,offset filetest
	call	print
	call	test_file
	call	result
;
; Verify that an open file can be opened again for reading, but not created
; (truncated) or deleted.
;
	mov	dx,offset sharetest
	call	print
	call	test_share
	call	result
;
; Verify that the path char can't be changed (3705h is no longer supported).
;
	mov	dx,offset pchtest
	call	print
	mov	ax,DOS_MSC_GETPCH
	int	21h		; DL = path char
	mov	dh,dl		; DH = path char
	mov	dl,':'
	mov	ax,DOS_MSC_GETPCH + 1
	int	21h		; attempt to set the path char
	cmp	al,0FFh		; unsupported?
	jne	m5		; no
	mov	ax,DOS_MSC_GETPCH
	int	21h
	cmp	dl,dh		; is the path char unchanged?
	je	m6		; yes (and carry is clear)
m5:	stc
m6:	call	result
;
; Create another file, rename it, and then delete it.
;
	mov	dx,offset renametest
	call	print
	call	test_rename
	call	result

	mov	dx,offset execfile
	mov	ax,DOS_HDL_OPENRO
	int	21h		; open file (and neglect to close it)

	mov	bx,offset execparms
	mov	[bx].EPB_CMDTAIL.SEG,cs
	mov	[bx].EPB_FCB1.SEG,cs
	mov	[bx].EPB_FCB2.SEG,cs
	mov	ax,DOS_PSP_EXEC1
	mov	dx,offset execfile
	int	21h		; exec (but don't launch)
;
; If the exec was successful, an INT 21h termination call is the simplest
; way to clean up the process (ie, free the program's memory, handles, etc),
; because the current PSP is the new PSP.  After termination, control will
; return here again, and we'll gracefully terminate ourselves.
;
; In BASIC-DOS, we could also use INT 20h here, but PC DOS requires that CS
; contain the PSP being terminated when calling INT 20h (BASIC-DOS does not).
;
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
	ret			; a return is not necessary, but just in case
ENDPROC	main

;
; test_file
;
; Creates testfile, writes teststr to it, and closes it; then reopens the
; file, reads it, and verifies that it contains exactly teststr.
;
; Returns carry clear if successful, carry set if not.
;
DEFPROC	test_file
	mov	dx,offset testfile
	sub	cx,cx		; CX = attributes (none)
	mov	ah,DOS_HDL_CREATE
	int	21h		; create the file
	jc	tf9
	xchg	bx,ax		; BX = handle
	mov	dx,offset teststr
	mov	cx,offset teststr_end - offset teststr
	mov	ah,DOS_HDL_WRITE
	int	21h		; write the string
	jc	tf8
	cmp	ax,cx		; were all the bytes written?
	jne	tf7		; no
	mov	ah,DOS_HDL_CLOSE
	int	21h		; close the file
	jc	tf9

	mov	dx,offset testfile
	mov	ax,DOS_HDL_OPENRO
	int	21h		; reopen the file
	jc	tf9
	xchg	bx,ax		; BX = handle
	mov	dx,offset readbuf
	mov	cx,offset readbuf_end - offset readbuf
	mov	ah,DOS_HDL_READ
	int	21h		; read the file
	jc	tf8
	mov	cx,offset teststr_end - offset teststr
	cmp	ax,cx		; did we read exactly what we wrote?
	jne	tf7		; no
	mov	si,offset teststr
	mov	di,offset readbuf
	repe	cmpsb		; do the contents match?
	jne	tf7		; no
	mov	ah,DOS_HDL_CLOSE
	int	21h		; close the file
	ret
tf7:	stc
tf8:	pushf
	mov	ah,DOS_HDL_CLOSE
	int	21h		; close the file (preserving the failure)
	popf
tf9:	ret
ENDPROC	test_file

;
; test_share
;
; Opens testfile for reading twice (which must succeed), and then attempts to
; create and delete it while it's still open (which must fail with ERR_SHARE).
;
; Returns carry clear if successful, carry set if not.
;
DEFPROC	test_share
	mov	dx,offset testfile
	mov	ax,DOS_HDL_OPENRO
	int	21h		; open the file for reading
	jc	ts9
	xchg	bx,ax		; BX = handle
	mov	ax,DOS_HDL_OPENRO
	int	21h		; a second reader is allowed
	jc	ts8
	push	bx
	xchg	bx,ax
	mov	ah,DOS_HDL_CLOSE
	int	21h		; close the second handle
	pop	bx
	sub	cx,cx		; CX = attributes (none)
	mov	ah,DOS_HDL_CREATE
	int	21h		; but a writer is not
	call	chk_share
	jc	ts8
	mov	ah,DOS_DSK_DELETE
	int	21h		; and neither is a delete
	call	chk_share
ts8:	pushf
	mov	ah,DOS_HDL_CLOSE
	int	21h		; close the file (preserving any failure)
	popf
ts9:	ret
ENDPROC	test_share

;
; chk_share
;
; Returns carry clear if the previous call failed with ERR_SHARE, carry set
; if it succeeded or failed with any other error.
;
DEFPROC	chk_share
	cmc
	jc	cs9		; the call succeeded, which is a failure
	cmp	ax,ERR_SHARE
	je	cs9		; (carry is clear)
	stc
cs9:	ret
ENDPROC	chk_share

;
; test_rename
;
; Creates tempfile1, renames it to tempfile2, and then deletes tempfile2,
; verifying along the way that the old names can no longer be opened.
;
; Returns carry clear if successful, carry set if not.
;
DEFPROC	test_rename
	mov	dx,offset tempfile1
	sub	cx,cx		; CX = attributes (none)
	mov	ah,DOS_HDL_CREATE
	int	21h		; create the file
	jc	tr9
	xchg	bx,ax		; BX = handle
	mov	ah,DOS_HDL_CLOSE
	int	21h		; close the (empty) file
	jc	tr9

	mov	dx,offset tempfile1
	mov	di,offset tempfile2
	mov	ah,DOS_DSK_RENAME
	int	21h		; rename the file
	jc	tr9
	mov	dx,offset tempfile1
	call	chk_nofile	; make sure the old name is gone
	jc	tr9

	mov	dx,offset tempfile2
	mov	ah,DOS_DSK_DELETE
	int	21h		; delete the file
	jc	tr9
	mov	dx,offset tempfile2
	call	chk_nofile	; make sure the new name is gone, too
tr9:	ret
ENDPROC	test_rename

;
; chk_nofile
;
; Returns carry clear if the file at DS:DX can NOT be opened, carry set if
; it can (in which case, it's closed again).
;
DEFPROC	chk_nofile
	mov	ax,DOS_HDL_OPENRO
	int	21h
	cmc			; carry is now clear if the open failed
	jnc	cn9
	xchg	bx,ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	stc
cn9:	ret
ENDPROC	chk_nofile

;
; result
;
; Prints "passed" if carry is clear, "failed" if carry is set.
;
DEFPROC	result
	mov	dx,offset passed
	jnc	rs9
	mov	dx,offset failed
rs9:	call	print
	ret
ENDPROC	result

DEFPROC	print
	push	cx
	mov	cl,DOS_TTY_PRINT
	call	DOS
	pop	cx
	ret
ENDPROC	print

call5test	db		"CALL 5 test "
passed		db		"passed",13,10,'$'
failed		db		"failed",13,10,'$'
progress	db		".$"
alloctest	db		"memory test$"
filetest	db		"file test $"
renametest	db		"rename/delete test $"
sharetest	db		"sharing test $"
pchtest		db		"path char test $"

testfile	db		"HELLO.TXT",0
tempfile1	db		"TEMP1.TXT",0
tempfile2	db		"TEMP2.TXT",0
teststr		db		"hello world",13,10
teststr_end	label	byte
readbuf		db		32 dup (?)	; big enough to detect any extra bytes
readbuf_end	label	byte

execfile	db		"dostests.com",0
execparms	EPB		<0,PSP_CMDTAIL,PSP_FCB1,PSP_FCB2>
;
; COMHEAP 0 means we don't need a heap, but BASIC-DOS will still allocate a
; minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
