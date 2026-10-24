;
; BASIC-DOS Miscellaneous DOS Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	dos.inc
	include	dosapi.inc

MEMSTEP	equ	67	; memory test increment, in paragraphs (a prime number,
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
; Check full-word handle bounds and access modes on an existing file.
;
	mov	dx,offset handletest
	call	print
	call	test_handles
	call	result
	mov	dx,offset accesstest
	call	print
	call	test_access
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
;
; Check date validation and readback, restoring the original date afterward.
;
	mov	dx,offset datetest
	call	print
	call	test_date
	call	result
;
; BASIC-DOS session loads must release their inherited handles on failure.
;
	mov	ah,DOS_MSC_GETVER
	int	21h
	cmp	bx,SIG_BASICDOS		; session utilities are BASIC-DOS-specific
	jne	m7
	mov	dx,offset loadtest
	call	print
	call	test_load
	call	result
	mov	dx,offset reservetest
	call	print
	call	test_reserve
	call	result
m7:

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
; test_handles
;
; Plant a valid SFH just beyond the PFT, at an already-executed code byte,
; so handle 0100h deterministically exposes a byte-only bounds check.
; Restore that byte and close the real handle on every exit.
;
; Returns carry clear if every API rejects every invalid handle.
;
DEFPROC	test_handles
	mov	dx,offset testfile
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jnc	th0
	ret
th0:	push	ax
	mov	bx,ax
	mov	al,ds:[PSP_PFT+bx]
	xchg	al,ds:[PSP_PFT+100h]
	push	ax
	mov	si,offset badhandles
th1:	mov	di,offset handleapis
th2:	mov	bx,[si]
	mov	dx,offset readbuf
	xor	cx,cx
	mov	ax,[di]
	int	21h
	call	chk_badhandle
	jc	th8
	add	di,2
	cmp	word ptr [di],0		; zero terminates the API list
	jne	th2
	add	si,2
	cmp	word ptr [si],0		; zero terminates the invalid handles
	jne	th1
	clc
th8:	pop	ax
	mov	ds:[PSP_PFT+100h],al
	pop	bx
	pushf
	mov	ah,DOS_HDL_CLOSE
	int	21h
	popf
	ret
ENDPROC	test_handles

;
; test_access
;
; Check zero- and one-byte reads in all three access modes, including
; sharing flags.  A rejected read must not change the buffer or position.
; Write the file's original first byte to check write access as well.
;
; Returns carry clear if access restrictions and valid operations work.
;
DEFPROC	test_access
	xor	si,si			; SI = access mode (RO, WO, RW)
ta0:	mov	dx,offset testfile
	mov	ax,DOS_HDL_OPENRO OR MODE_DENY_NONE
	or	ax,si
	int	21h
	jnc	ta1
	ret
ta1:	mov	bx,ax
	xor	bp,bp			; BP = requested read count (0, 1)
ta2:	mov	byte ptr [readbuf],0A5h
	mov	dx,offset readbuf
	mov	cx,bp
	mov	ah,DOS_HDL_READ
	int	21h
	pushf
	cmp	si,MODE_ACC_WO		; write-only reads must fail, even with CX=0
	jne	ta3
	popf
	call	chk_access
	jc	ta8
	cmp	byte ptr [readbuf],0A5h	; rejection must leave the buffer untouched
	jne	ta7
	jmp	short ta4
ta3:	popf
	jc	ta8
	cmp	ax,bp			; allowed reads must return the requested count
	jne	ta7
ta4:	inc	bp
	cmp	bp,2			; test both zero- and one-byte requests
	jb	ta2
	xor	cx,cx
	xor	dx,dx
	mov	ax,DOS_HDL_SEEKCUR
	int	21h
	jc	ta8
	mov	di,1
	cmp	si,MODE_ACC_WO		; only successful reads advance the position
	jne	ta5
	dec	di
ta5:	cmp	ax,di			; expect position 0 for WO, 1 for RO/RW
	jne	ta7
	test	dx,dx			; the high word of the position must be zero
	jnz	ta7
	mov	ax,DOS_HDL_SEEKBEG
	int	21h			; CX:DX is still zero
	jc	ta8
	mov	dx,offset teststr
	mov	cx,1
	mov	ah,DOS_HDL_WRITE
	int	21h
	pushf
	cmp	si,MODE_ACC_RO		; only read-only writes must fail
	jne	ta6
	popf
	call	chk_access
	jmp	short ta8
ta6:	popf
	jc	ta8
	cmp	ax,1			; WO and RW must permit the write
	je	ta8
ta7:	stc
ta8:	pushf
	mov	ah,DOS_HDL_CLOSE
	int	21h
	popf
	jc	ta9
	inc	si
	cmp	si,MODE_ACC_RW		; all three access modes checked?
	ja	ta9
	jmp	ta0
ta9:	ret
ENDPROC	test_access

;
; chk_badhandle / chk_access
;
; Return carry clear only if the preceding API failed with the expected error.
;
DEFPROC	chk_badhandle
	mov	dx,ERR_BADHANDLE
	jmp	short chk_handle_error
ENDPROC	chk_badhandle

DEFPROC	chk_access
	mov	dx,ERR_ACCDENIED
chk_handle_error:
	cmc
	jc	che9			; the API succeeded, which is a test failure
	cmp	ax,dx			; the error code must match too
	je	che9
	stc
che9:	ret
ENDPROC	chk_access

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
; test_date
;
; Each case supplies a year, month/day, and expected SETDATE result.
; Valid dates must read back correctly; invalid dates must leave the
; previous date unchanged.  Restore the caller's date even on failure.
;
; Returns carry clear if successful, carry set if not.
;
DEFPROC	test_date
	mov	ah,DOS_MSC_GETDATE
	int	21h
	push	cx
	push	dx
	mov	[dateyear],cx
	mov	[datemonthday],dx
	mov	si,offset datecases
td1:	mov	cx,[si]
	mov	dx,[si+2]
	mov	ah,DOS_MSC_SETDATE
	int	21h
	cmp	al,byte ptr [si+4]	; was the date accepted or rejected as expected?
	jne	td7
	test	al,al
	jnz	td2
	mov	cx,[si]
	mov	dx,[si+2]
	mov	[dateyear],cx
	mov	[datemonthday],dx
td2:	mov	ah,DOS_MSC_GETDATE
	int	21h
	cmp	cx,[dateyear]		; valid year saved, or invalid input ignored?
	jne	td7
	cmp	dx,[datemonthday]	; check both month and day as well
	jne	td7
	add	si,6
	cmp	word ptr [si],0		; zero year terminates the cases
	jne	td1
	clc
	jmp	short td8
td7:	stc
td8:	pop	dx
	pop	cx
	pushf
	mov	ah,DOS_MSC_SETDATE
	int	21h
	popf
	ret
ENDPROC	test_date

;
; test_load
;
; Supply one writable file as all five session handles, then repeatedly
; try to load that same file (which must fail with a sharing violation).
; Its reference count must return to the caller's single reference each
; time.  Finally load and run a tiny COM file to verify session reuse and
; normal termination.  The DOS tables are read only, for checking counts.
;
DEFPROC	test_load
	push	cs
	pop	es
	mov	dx,offset loadchild
	xor	cx,cx
	mov	ah,DOS_HDL_CREATE
	int	21h
	jnc	tl0
	ret
tl0:	mov	[loadhandle],ax
	mov	bx,ax
	mov	dx,offset loadimage
	mov	cx,2
	mov	ah,DOS_HDL_WRITE
	int	21h
	jnc	tl0b
	jmp	tl8
tl0b:	cmp	ax,2			; the child must contain its entire INT 20h
	jne	tl7
	mov	ah,DOS_HDL_CLOSE
	int	21h
	jnc	tl0a
	ret
tl0a:	mov	[loadhandle],-1
	mov	dx,offset testfile
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jc	tl8
	mov	[loadhandle],ax
	mov	bx,ax
	mov	al,ds:[PSP_PFT+bx]
	mov	di,offset loadspb.SPB_SFHIN
	mov	cx,5
	rep	stosb			; the same SFH must be balanced five times
	mov	ah,size SFB
	mul	ah
	push	ax			; offset of this SFH within the SFB table
	mov	ah,DOS_MSC_GETVARS
	int	21h
	sub	bx,2			; ES:BX -> DOSVARS, including DV_MCB_HEAD
	pop	ax
	add	ax,es:[bx].DV_SFB_TABLE.OFF
	mov	[loadrefs].OFF,ax
	mov	[loadrefs].SEG,es
	mov	[loadspb].SPB_CMDLINE.SEG,cs
	mov	[loadspb].SPB_CMDLINE.OFF,offset testfile
	mov	bp,32
tl1:
	call	load_session
	jnc	tl7
	cmp	ax,ERR_SHARE		; cleanup must preserve the original load error
	jne	tl7
	call	load_refcheck
	jc	tl7
	dec	bp
	jnz	tl1
	mov	[loadspb].SPB_CMDLINE.OFF,offset loadchild
	call	load_session
	jc	tl7
	DOSUTIL	START
	jc	tl7
	DOSUTIL	WAITEND
	jc	tl7
	call	load_refcheck		; successful termination must release them too
	jmp	short tl8
tl7:	stc
tl8:	pushf
	mov	bx,[loadhandle]
	cmp	bx,-1			; did the caller's fixture handle open?
	je	tl8a
	mov	ah,DOS_HDL_CLOSE
	int	21h
tl8a:	mov	dx,offset loadchild
	mov	ah,DOS_DSK_DELETE
	int	21h
	push	cs
	pop	es
	popf
tl9:	ret
ENDPROC	test_load

;
; load_session / load_refcheck
;
; Load through the session API, or check the fixture's reference count.
;
DEFPROC	load_session
	push	cs
	pop	es
	mov	bx,offset loadspb
	xor	cx,cx			; no subsequent pipeline stages
	DOSUTIL	LOAD
	ret
ENDPROC	load_session

DEFPROC	load_refcheck
	les	di,[loadrefs]
	cmp	es:[di].SFB_REFS,1	; only the caller's handle may remain
	je	lr9
	stc
lr9:	ret
ENDPROC	load_refcheck

;
; test_reserve
;
; EXEC and EXEC1 must ignore CH, while EXEC6 must reserve memory for the CH
; programs to follow.  A tiny EXE requests all available memory and reports
; its allocation into this process before exiting.  Compare EXEC with CH=0
; and FFh, EXEC1 with CH=FFh, and EXEC6 with CH=0 and 1, starting each
; loaded child with EXEC2.
;
DEFPROC	test_reserve
	mov	[reserveparent],cs
	mov	dx,offset reservefile
	xor	cx,cx
	mov	ah,DOS_HDL_CREATE
	int	21h
	jnc	rv0a
	ret
rv0a:	xchg	bx,ax
	mov	dx,offset reserveimage
	mov	cx,offset reserveend-offset reserveimage
	mov	ah,DOS_HDL_WRITE
	int	21h
	jc	rv6
	cmp	ax,cx			; the fixture must be written in full
	je	rv0
	stc
rv6:	pushf
	mov	ah,DOS_HDL_CLOSE
	int	21h
	popf
	jmp	short rv8
rv0:	mov	ah,DOS_HDL_CLOSE
	int	21h
	jc	rv8
	mov	[execparms].EPB_CMDTAIL.SEG,cs
	mov	[execparms].EPB_FCB1.SEG,cs
	mov	[execparms].EPB_FCB2.SEG,cs
	xor	cx,cx
	mov	ax,DOS_PSP_EXEC
	call	reserve_exec
	jc	rv8
	mov	[reservebase],ax
	mov	cx,0FF00h
	mov	ax,DOS_PSP_EXEC
	call	reserve_exec
	jc	rv8
	cmp	ax,[reservebase]	; ordinary EXEC must ignore nonzero CH
	jne	rv7
	mov	cx,0FF00h
	mov	ax,DOS_PSP_EXEC1
	call	reserve_exec
	jc	rv8
	cmp	ax,[reservebase]	; EXEC1 must ignore nonzero CH too
	jne	rv7
	xor	cx,cx
	mov	ax,DOS_PSP_EXEC6
	call	reserve_exec
	jc	rv8
	cmp	ax,[reservebase]	; EXEC6 with CH=0 must agree
	jne	rv7
	mov	cx,0100h
	mov	ax,DOS_PSP_EXEC6
	call	reserve_exec
	jc	rv8
	cmp	ax,[reservebase]	; smaller with a reservation?
	cmc				; CF clear only if smaller
	jmp	short rv8
rv7:	stc
rv8:	pushf
	mov	dx,offset reservefile
	mov	ah,DOS_DSK_DELETE
	int	21h
	popf
	ret
ENDPROC	test_reserve

;
; reserve_exec
;
; Run the fixture using AX's subfunction and CH's reservation count.
; Return its allocation in AX, or carry set if it could not run.
;
DEFPROC	reserve_exec
	push	ax
	push	cs
	pop	es
	mov	bx,offset execparms
	mov	dx,offset reservefile
	int	21h
	pop	dx
	jc	re9
	test	dl,dl			; loaded but not started?
	jz	re8
	mov	ax,DOS_PSP_EXEC2
	int	21h
	jc	re9
re8:	mov	ax,[reserveparas]
	clc
re9:	ret
ENDPROC	reserve_exec

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
handletest	db		"handle bounds test $"
accesstest	db		"handle access test $"
badhandles	dw		20,0FFh,100h,113h,0FF00h,0FFFFh,0
handleapis	dw		DOS_HDL_READ SHL 8,DOS_HDL_WRITE SHL 8
		dw		DOS_HDL_SEEKBEG,DOS_HDL_CLOSE SHL 8,4400h,0
renametest	db		"rename/delete test $"
sharetest	db		"sharing test $"
pchtest		db		"path char test $"
datetest	db		"date test $"
dateyear	dw		0
datemonthday	dw		0
;
; Each case contains year, month/day (DH/DL), and expected result (AL).
;
datecases	dw		2023,0201h,0
		dw		2023,021Ch,0
		dw		2023,021Dh,0FFh
		dw		2024,0201h,0
		dw		2024,021Ch,0
		dw		2024,021Dh,0
		dw		2023,0200h,0FFh
		dw		2023,021Eh,0FFh
		dw		2024,0200h,0FFh
		dw		2024,021Eh,0FFh
		dw		1980,021Dh,0
		dw		2000,021Dh,0
		dw		2099,021Dh,0FFh
		dw		2024,011Fh,0
		dw		2024,041Eh,0
		dw		2024,041Fh,0FFh
		dw		0,0,0
loadtest	db		"session load test $"
loadhandle	dw		-1
loadrefs	dd		0
loadspb		SPB		<0,0,0FFh,0FFh,0FFh,0FFh,0FFh>
loadchild	db		"LOADTEST.COM",0
;
; LOADTEST.COM deliberately has no COMDATA (unlike our other COM programs),
; so the loader's path for other COM files is tested, too (see load_program).
;
loadimage	db		0CDh,20h

reservetest	db		"EXEC reservation test $"
reservefile	db		"EXECTEST.EXE",0
reservebase	dw		0
reserveparas	dw		0
;
; EXE image with a 32-byte header (its fields after SP are zero), no
; relocations, and maximum allocation.  DS initially points to its PSP;
; report BASIC-DOS's paragraph count to the parent using a segment patched
; before the file is written.
;
reserveimage	EXEHDR	<SIG_EXE,reserveend-reserveimage,1,0,2,40h,-1,0,400h>
		dw		0,0
reservecode label byte
	mov	ax,ds:[PSP_PARAS]
	mov	dx,cs:[reserveparent-reservecode]
	mov	ds,dx
	mov	[reserveparas],ax
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
reserveparent	dw		0
reserveend label byte

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
