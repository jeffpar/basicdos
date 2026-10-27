;
; BASIC-DOS Hard Error (INT 24h) Tests
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
	include	dosapi.inc
	include	devapi.inc
	include	8086.inc
	include	bios.inc

RW_SIZE equ	4096

CODE    SEGMENT

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

	org	100h
;
; The BPB tests use drive B:, which must be empty, so that every request fails
; with "not ready" (BIOS error 80h); each failure takes a few seconds, since
; the BIOS retries the request before giving up.
;
; After installing an INT 24h handler that records its inputs and returns the
; responses in a list, we open a file on B:, which fails as soon as the drive's
; BPB can't be built, and verify that:
;
;   1) RETRY reissues the request (so the handler is called again), FAIL then
;      returns error 21 (ERR_NOTREADY), and the handler saw AH = 18h (a read
;      of the reserved area, with RETRY and FAIL allowed), AL = 1 (drive B),
;      DI = 2 (not ready), BP:SI -> the FDC$ device header, and a stack other
;      than our own;
;
;   2) IGNORE is converted to FAIL when it isn't allowed (eg, while building
;      the BPB);
;
;   3) ABORT terminates the program (with exit code 255); if it doesn't, the
;      program prints "HARDERR abort failed" and returns 1.
;
; Before ABORT, data transfer tests use a temporary file in the current
; drive's root.  An INT 13h hook fails two reads or writes in succession,
; and INT 24h returns RETRY both times.  Verify the byte counts and data,
; including an aligned nonzero offset, a completed partial first sector,
; and a partial sector only.  Writes must preserve all bytes outside the
; requested range.
;
; Metadata tests then fail writes to each FAT copy and to the directory,
; returning FAIL from INT 24h.  A second disk reset must try the write again.
; After a successful reset, BIOS reads verify the saved metadata on disk,
; and reopening the file verifies its size, cluster chain, and contents.
;
; Finally, fail FAT reads while locating a cluster after a seek.  The read
; must return the error without changing the destination or advancing the
; file position, and a later read must recover without another seek.
;
; A failed FAT read while deleting the file must preserve the original
; error code.  Restore its cached name after that injected failure so the
; normal cleanup can still delete the file and reclaim its clusters.
;
; Large volume writes check unsigned byte counts around 32K and 64K.
; The BIOS hook counts these writes and reports success without writing
; the disk, so the volume's contents are preserved.
;
; "HARDERR passed" is printed before the ABORT test, so a BAT file (or script)
; should check for both that message and ERRORLEVEL 255.
;
; The INT 13h hook can't tell our disk requests from those of other sessions,
; and the disk buffers are shared, so if any other session has a program (eg,
; one running STRESS), we print "HARDERR skipped" and exit with code 0 rather
; than disturb its disk.
;
DEFPROC	main
	cld
	DOSUTIL	GETCSN			; CL = our session #
	mov	dl,cl
	sub	cx,cx			; CL = session # (from 0)
m0:	DOSUTIL	QRYSCB			; AX = session's PSP (zero if none)
	jc	m1			; no more sessions
	cmp	cl,dl			; is it our session?
	je	m0a			; yes
	test	ax,ax			; does it have a program?
	jnz	m0b			; yes
m0a:	inc	cx
	jmp	m0
m0b:	mov	dx,offset skipped
	call	print
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
m1:	mov	dx,offset starting
	call	print
	mov	dx,offset handler
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_DOSERROR
	int	21h
	mov	ax,(DOS_MSC_GETVEC SHL 8) OR INT_DOSERROR
	int	21h			; ES:BX = INT 24h handler address
	cmp	bx,offset handler
	jne	m8
	mov	ax,es
	mov	bx,cs
	cmp	ax,bx
	jne	m8
	push	cs
	pop	es
;
; Test 1: RETRY, then FAIL
;
	mov	si,offset test1
	call	trigger			; AX = error code, carry set
	jnc	m8			; the open should have failed
	cmp	ax,ERR_NOTREADY
	jne	m8
	cmp	[count],2
	jne	m8
	cmp	[regAX],((CRERR_RETRYOK OR CRERR_FAILOK) SHL 8) OR 1
	jne	m8
	cmp	[regDI],ERR_NOTREADY - 19
	jne	m8
	mov	ax,[regSS]
	cmp	ax,bx			; was the handler called on our stack?
	je	m8			; yes (it should have been DOS's)
	les	di,[regDDH]		; ES:DI -> DDH, hopefully
	cmp	word ptr es:[di].DDH_NAME,'DF'
	jne	m8
	cmp	word ptr es:[di].DDH_NAME+2,'$C'
	jne	m8
	push	cs
	pop	es
;
; Test 2: IGNORE (not allowed here, so it should be converted to FAIL)
;
	mov	si,offset test2
	call	trigger
	jnc	m8
	cmp	ax,ERR_NOTREADY
	jne	m8
	cmp	[count],1
	jne	m8
	call	data_retries
	jc	m8
	call	volume_writes
	jc	m8
	mov	dx,offset passed
	call	print
;
; Test 3: ABORT (the program should be terminated; if we return, it failed)
;
	mov	si,offset test3
	call	trigger
	mov	dx,offset abortfail
m8a:	call	print
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
m8:	mov	dx,offset failed
	jmp	m8a
ENDPROC	main

;
; trigger
;
; Resets the handler's call count, gives it a new list of responses, and
; opens a file on drive B:.
;
; Inputs:
;	SI -> list of responses
;
; Outputs:
;	Carry set if the open failed, AX = error code
;
DEFPROC	trigger
	mov	[responses],si
	mov	[count],0
	mov	dx,offset filename
	mov	ax,DOS_HDL_OPENRO
	int	21h
	ret
ENDPROC	trigger

;
; data_retries
;
; Create a patterned file before installing the BIOS fault hook, then run
; each request with two injected errors.  The buffers live in our heap.
; Always restore the BIOS vector and remove the temporary file on return.
;
; Outputs:
;	Carry set if any test failed
;
DEFPROC	data_retries
	mov	ah,DOS_DSK_GETDRV
	int	21h
	mov	[rwdrive],al
	add	al,'A'
	mov	[rwname],al
;
; DOS numbers A: and B: as 0 and 1, as does the BIOS.  Hard disks start
; at DOS drive 2 (C:), whereas their BIOS drive numbers start at 80h.
;
	cmp	[rwdrive],2	; is the current drive a hard disk?
	jb	dr0
	add	[rwdrive],80h-2
dr0:
	mov	di,ds:[PSP_HEAP]
	mov	cx,RW_SIZE/2
	xor	ax,ax
dr1:
	stosw
	inc	ax
	loop	dr1
	mov	dx,offset rwname
	xor	cx,cx
	mov	ah,DOS_HDL_CREATE
	int	21h
	jnc	dr1a
	ret
dr1a:
	mov	[rwhandle],ax
	mov	bx,ax
	mov	dx,ds:[PSP_HEAP]
	mov	cx,RW_SIZE
	mov	ah,DOS_HDL_WRITE
	int	21h
	jc	dr1b
	cmp	ax,RW_SIZE	; was the entire fixture written?
	jne	dr1b
	mov	ax,(DOS_MSC_GETVEC SHL 8) OR 13h
	int	21h
	mov	[old_disk].OFF,bx
	mov	[old_disk].SEG,es
	push	cs
	pop	es
	mov	dx,offset disk_handler
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 13h
	int	21h
	mov	[hooked],1
	mov	bp,offset rwcases
	jmp	short dr2
dr1b:
	stc
	jmp	dr8
dr2:
	mov	bx,[rwhandle]
	xor	cx,cx
	mov	dx,[bp]
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	jc	dr1b
	mov	dx,ds:[PSP_HEAP]
	mov	cx,[bp+2]
	mov	al,[bp+4]
	mov	[rwcmd],al
	mov	al,[bp+5]
	mov	[rwskip],al
	cmp	[rwcmd],3	; is this a BIOS write test?
	jne	dr3
;
; Change the expected bytes so a skipped or misplaced write is observable.
;
	add	dx,[bp]
	mov	si,dx
dr2a:
	not	byte ptr [si]
	inc	si
	loop	dr2a
	jmp	dr4
dr3:
	add	dx,RW_SIZE
	mov	di,dx
	xor	ax,ax
	rep	stosb			; erase the read destination
dr4:
	mov	[count],0
	mov	[responses],offset rwresponses
	mov	[rwfaults],2
	mov	cx,[bp+2]
	mov	ah,DOS_HDL_READ
	cmp	[rwcmd],3	; select DOS read or write to match the fault
	jne	dr4a
	mov	ah,DOS_HDL_WRITE
dr4a:
	int	21h
	jc	dr8
	cmp	ax,[bp+2]	; RETRY must complete the original byte count
	jne	dr7
	cmp	[count],2	; both injected failures must reach INT 24h
	jne	dr7
	cmp	[rwfaults],0	; ensure the fault hook actually ran twice
	jne	dr7
	mov	si,ds:[PSP_HEAP]
	add	si,[bp]
	mov	cx,[bp+2]
	cmp	[rwcmd],3	; writes require a whole-file comparison
	jne	dr5
	xor	cx,cx
	xor	dx,dx
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	jc	dr8
	mov	dx,ds:[PSP_HEAP]
	add	dx,RW_SIZE
	mov	cx,RW_SIZE
	mov	ah,DOS_HDL_READ
	int	21h
	jc	dr8
	cmp	ax,RW_SIZE	; check the entire file, including untouched bytes
	jne	dr7
	mov	si,ds:[PSP_HEAP]
	mov	cx,RW_SIZE
dr5:
	mov	di,ds:[PSP_HEAP]
	add	di,RW_SIZE
	repe	cmpsb
	jne	dr7			; transferred data must match the fixture
	add	bp,6
	cmp	word ptr [bp+2],0 ; zero length marks the end of the cases
	je	dr6
	jmp	dr2
dr6:
	call	metadata_retries
	jc	dr8
	call	seek_failures
	jc	dr8
	call	delete_failure
	jmp	dr8
dr7:
	stc
dr8:
	pushf
	cmp	[hooked],0	; restore INT 13h only if we installed the hook
	je	dr8a
	push	ds
	lds	dx,[old_disk]
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 13h
	int	21h
	pop	ds
dr8a:
	mov	bx,[rwhandle]
	cmp	bx,-1		; did the metadata tests already close the handle?
	je	dr8b
	mov	ah,DOS_HDL_CLOSE
	int	21h
dr8b:
	mov	dx,offset rwname
	mov	ah,DOS_DSK_DELETE
	int	21h
	popf
	ret
ENDPROC	data_retries

;
; volume_writes
;
; Write from a separate 64K buffer through the current drive's volume
; handle.  Check the returned byte count and the number of BIOS sectors
; written, including partial sectors and a nonzero aligned offset.
; Install the write-suppressing hook only after opening the volume, so
; that pending metadata is flushed normally first.
;
; Outputs:
;	Carry set if any boundary count failed
;
DEFPROC	volume_writes
	mov	bx,1000h
	mov	ah,DOS_MEM_ALLOC
	int	21h
	jnc	vw0
	ret
vw0:	mov	[volseg],ax
	mov	es,ax
	xor	di,di
	mov	cx,8000h
vw1:	stosw
	inc	ax
	loop	vw1
	mov	al,[rwname]
	mov	[volname],al
	mov	dx,offset volname
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jc	vw8
	mov	[rwhandle],ax
	mov	ax,(DOS_MSC_GETVEC SHL 8) OR 13h
	int	21h
	mov	[old_disk].OFF,bx
	mov	[old_disk].SEG,es
	mov	dx,offset disk_handler
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 13h
	int	21h
	mov	[rwlarge],1
	mov	bp,offset volcases
vw2:	mov	bx,[rwhandle]
	xor	cx,cx
	mov	dx,[bp]
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	jc	vw6
	mov	[volsectors],0
	xor	dx,dx
	mov	cx,[bp+2]
	push	ds
	mov	ds,[volseg]
	mov	ah,DOS_HDL_WRITE
	int	21h
	pop	ds
	jc	vw6
	cmp	ax,[bp+2]		; the full unsigned byte count must be returned
	jne	vw5
	mov	ax,[volsectors]
	cmp	ax,[bp+4]		; count every whole or merged partial sector
	jne	vw5
	add	bp,6
	cmp	word ptr [bp+2],0	; zero length terminates the cases
	jne	vw2
	clc
	jmp	short vw6
vw5:	stc
vw6:	pushf
	mov	[rwlarge],0
	push	ds
	lds	dx,[old_disk]
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 13h
	int	21h
	pop	ds
	mov	bx,[rwhandle]
	mov	ah,DOS_HDL_CLOSE
	int	21h
	popf
vw8:	pushf
	mov	es,[volseg]
	mov	ah,DOS_MEM_FREE
	int	21h
	push	cs
	pop	es
	popf
	jc	vw9
	mov	dx,offset volpassed
	call	print
	clc
vw9:	ret
ENDPROC	volume_writes

;
; metadata_retries
;
; Extend the file for each FAT test, then close it for the directory test.
; BP selects the first FAT (0), second FAT (1), or directory (2).
;
; Outputs:
;	Carry set if a failed metadata write could not be recovered
;
DEFPROC	metadata_retries
	mov	ah,DOS_DSK_RESET
	int	21h			; start with clean disk buffers
	jc	mr8
	xor	bp,bp
mr1:
	call	metadata_case
	jc	mr8
	inc	bp
	cmp	bp,3			; all three metadata failures tested?
	jb	mr1
	call	metadata_readback
	jc	mr8
	mov	dx,offset metapassed
	call	print
	clc
	ret
mr8:
	mov	dx,offset metafailed
	call	print
	stc
	ret
ENDPROC	metadata_retries

;
; metadata_case
;
; Fail the initial flush and a subsequent disk reset, then let the next
; reset succeed.  Retain a snapshot of the failed sector for a BIOS read
; that bypasses the DOS cache after recovery.
;
DEFPROC	metadata_case
	cmp	bp,2			; the directory is updated on close
	je	mc1
	mov	bx,[rwhandle]
	xor	cx,cx
	xor	dx,dx
	mov	ax,DOS_HDL_SEEKEND
	int	21h
	jc	mc9
	mov	dx,ds:[PSP_HEAP]
	mov	cx,RW_SIZE
	mov	ah,DOS_HDL_WRITE
	int	21h			; allocate more clusters, dirtying the FAT
	jc	mc9
	cmp	ax,RW_SIZE		; the extension must be written in full
	jne	mc8
mc1:
	call	arm_metadata
	cmp	bp,2			; close commits the file's directory entry
	jne	mc2
	mov	bx,[rwhandle]
	mov	[rwhandle],-1		; DOS closes it even if committing fails
	mov	ah,DOS_HDL_CLOSE
	int	21h
	jmp	short mc3
mc2:
	mov	ah,DOS_DSK_RESET
	int	21h
mc3:
	call	check_metadata
	jc	mc9
	push	ds
	lds	si,[faultaddr]
	mov	di,es:[PSP_HEAP]
	add	di,RW_SIZE
	mov	cx,256
	rep	movsw			; save the metadata that failed to write
	pop	ds
	call	arm_metadata
	mov	ah,DOS_DSK_RESET
	int	21h			; the same pending write must be retried
	call	check_metadata
	jc	mc9
	mov	[count],0
	mov	ah,DOS_DSK_RESET
	int	21h			; no injected error this time
	jc	mc9
	cmp	[count],0		; the recovery flush must not report an error
	jne	mc8
	call	metadata_sector
	ret
mc8:
	stc
mc9:
	ret
ENDPROC	metadata_case

;
; arm_metadata / check_metadata
;
; Arm one BIOS write failure and an INT 24h FAIL response, and verify that
; the failure was reported for the expected disk area.
;
DEFPROC	arm_metadata
	mov	[rwcmd],3
	mov	[rwskip],0
	cmp	bp,1			; skip the first FAT when testing its mirror
	jne	am1
	mov	[rwskip],1
am1:
	mov	[metaarea],CRERR_WRITE OR 2
	cmp	bp,2			; distinguish directory writes from FAT writes
	jne	am2
	mov	[metaarea],CRERR_WRITE OR 4
am2:
	mov	[count],0
	mov	[responses],offset metaresponses
	mov	[rwfaults],1
	ret
ENDPROC	arm_metadata

DEFPROC	check_metadata
	cmp	[count],1		; each flush must report the injected failure
	jne	cm8
	cmp	[rwfaults],0		; ensure a pending write reached the BIOS
	jne	cm8
	mov	al,byte ptr [regAX+1]
	and	al,CRERR_AREA OR CRERR_WRITE
	cmp	al,[metaarea]		; was it the intended kind of metadata?
	jne	cm8
	clc
	ret
cm8:
	stc
	ret
ENDPROC	check_metadata

;
; metadata_sector
;
; Read the failed sector through the BIOS and compare it with the snapshot.
; Align the destination on a physical 512-byte boundary inside the second
; heap buffer, so that this read cannot cross a DMA boundary.
;
DEFPROC	metadata_sector
	mov	ax,cs
	mov	dx,ds:[PSP_HEAP]
	add	dx,RW_SIZE+512+15
	mov	cl,4
	shr	dx,cl
	add	ax,dx
	add	ax,31
	and	ax,0FFE0h
	mov	es,ax
	xor	bx,bx
	mov	cx,[faultcx]
	mov	dx,[faultdx]
	mov	ax,0201h
	push	bp
	int	13h
	pop	bp
	jc	ms9
	mov	si,ds:[PSP_HEAP]
	add	si,RW_SIZE
	xor	di,di
	mov	cx,512
	repe	cmpsb
	je	ms9			; the recovered sector must match every byte
	stc
ms9:
	push	cs
	pop	es
	ret
ENDPROC	metadata_sector

;
; metadata_readback
;
; Reopen the file after the directory flush and cache invalidation, and
; verify the original data and both appended copies of it.
;
DEFPROC	metadata_readback
	mov	dx,offset rwname
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	mb9
	mov	[rwhandle],ax
	mov	bx,ax
	xor	cx,cx
	xor	dx,dx
	mov	ax,DOS_HDL_SEEKEND
	int	21h
	jc	mb9
	cmp	dx,0			; the size must fit in the low word
	jne	mb8
	cmp	ax,3*RW_SIZE		; both FAT extensions and size must persist
	jne	mb8
	xor	dx,dx
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	jc	mb9
	mov	bp,3
mb1:
	mov	dx,ds:[PSP_HEAP]
	add	dx,RW_SIZE
	mov	cx,RW_SIZE
	mov	ah,DOS_HDL_READ
	int	21h
	jc	mb9
	cmp	ax,RW_SIZE		; all clusters in this copy must be readable
	jne	mb8
	mov	si,ds:[PSP_HEAP]
	mov	di,dx
	mov	cx,RW_SIZE
	repe	cmpsb
	jne	mb8			; verify the data reached through the FAT chain
	dec	bp
	jnz	mb1
	clc
	ret
mb8:
	stc
mb9:
	ret
ENDPROC	metadata_readback

;
; seek_failures
;
; Seek into the third copy of the data, beyond the first cluster on both
; test disks (1K floppy clusters and 4K hard disk clusters).  With a fresh
; handle and empty disk buffers, locating that cluster requires a FAT read.
; Fail two successive reads with INT 24h FAIL, then allow recovery.
;
; Outputs:
;	Carry set if an error, buffer, position, or recovery check failed
;
DEFPROC	seek_failures
	call	seek_setup
	jc	sf8
	mov	di,ds:[PSP_HEAP]
	add	di,RW_SIZE
	mov	cx,128
	mov	al,0A5h
	rep	stosb			; a failed lookup must not overwrite these bytes
	mov	bp,2
sf1:
	mov	[rwcmd],2
	mov	[rwskip],0
	mov	[rwfaults],1
	mov	[count],0
	mov	[responses],offset metaresponses
	mov	[metaarea],2		; expect a FAT read, not a data or BPB read
	call	seek_read
	jnc	sf8			; INT 24h FAIL must reach the caller
	cmp	ax,ERR_NOTREADY		; preserve the original FAT read error
	jne	sf8
	call	check_metadata
	jc	sf8
	mov	di,ds:[PSP_HEAP]
	add	di,RW_SIZE
	mov	cx,128
	mov	al,0A5h
	repe	scasb
	jne	sf8			; no file data may be returned after lookup failure
	dec	bp
	jnz	sf1			; retry without seeking or repairing the handle
	jmp	short sf2
sf8:
	mov	dx,offset seekfailed
	call	print
	stc
	ret
sf2:
	call	seek_read		; no injected failure remains
	jc	sf8
	cmp	ax,128			; recovery must return the complete request
	jne	sf8
	mov	si,ds:[PSP_HEAP]
	inc	si			; expected bytes at offset 2*RW_SIZE+1
	mov	di,dx
	mov	cx,128
	repe	cmpsb
	jne	sf8			; recovery must read the requested cluster
	xor	cx,cx
	xor	dx,dx
	mov	ax,DOS_HDL_SEEKCUR
	int	21h
	jc	sf8
	cmp	dx,0			; file position must still fit in the low word
	jne	sf8
	cmp	ax,2*RW_SIZE+1+128	; only the successful read may advance it
	jne	sf8
	mov	dx,offset seekpassed
	call	print
	clc
	ret
ENDPROC	seek_failures

;
; seek_setup / seek_read
;
; Reopen the file to reset its cluster hint, seek beyond its first cluster,
; and invalidate cached FAT sectors before fault injection.  seek_read then
; issues the same read for each failing attempt and the recovery attempt.
;
DEFPROC	seek_setup
	mov	bx,[rwhandle]
	mov	[rwhandle],-1
	mov	ah,DOS_HDL_CLOSE
	int	21h
	jc	ss9
	mov	dx,offset rwname
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	ss9
	mov	[rwhandle],ax
	mov	bx,ax
	xor	cx,cx
	mov	dx,2*RW_SIZE+1
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	jc	ss9
	mov	ah,DOS_DSK_RESET
	int	21h
ss9:
	ret
ENDPROC	seek_setup

DEFPROC	seek_read
	mov	bx,[rwhandle]
	mov	dx,ds:[PSP_HEAP]
	add	dx,RW_SIZE
	mov	cx,128
	mov	ah,DOS_HDL_READ
	int	21h
	ret
ENDPROC	seek_read

;
; delete_failure
;
; Empty the disk cache, then reopen and close the fixture to cache only its
; directory entry.  Fail the first FAT read while freeing its chain: no
; clusters have been freed yet, but del_dirent has marked the name deleted.
; Restore that first character in the pinned directory buffer so cleanup
; can reclaim the fixture, even when the wrapper returns the wrong error.
;
; Outputs:
;	Carry set if the delete did not return the original FAT read error
;
DEFPROC	delete_failure
	mov	bx,[rwhandle]
	mov	[rwhandle],-1
	mov	ah,DOS_HDL_CLOSE
	int	21h
	jc	df0
	mov	ah,DOS_DSK_RESET
	int	21h
	jc	df0
	mov	dx,offset rwname
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	df0
	mov	bx,ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	jnc	df0a
df0:	jmp	df8
;
; The two original BIOS buffers remain in the circular buffer chain.
; Find the fixture's entry in a cached directory sector before deleting it.
;
df0a:	mov	ax,offset FAT_BUFHDR + BIOS_DATA
	mov	cl,4
	shr	ax,cl
	mov	bp,ax			; BP = first buffer's paragraph
df1:	mov	es,ax
	cmp	es:[BUF_TYPE],((offset DIR_BUFHDR)-(offset FAT_BUFHDR)) AND 0FFh
	jne	df4			; inspect only directory buffers
	cmp	es:[BUF_LBA],0		; ignore invalidated buffer contents
	je	df4
	mov	al,[rwname]
	sub	al,'A'
	cmp	es:[BUF_DRIVE],al	; match the fixture's DOS drive, not its BIOS drive
	jne	df4
	mov	di,size BUFHDR
	mov	bx,16			; sixteen directory entries per sector
df2:	push	di
	mov	si,offset rwentry
	mov	cx,11
	repe	cmpsb
	pop	di
	je	df5			; matching 8.3 name found
	add	di,32
	dec	bx
	jnz	df2
df4:	mov	ax,es:[BUF_NEXT]
	cmp	ax,bp			; searched the entire buffer chain?
	jne	df1
	jmp	short df8
df5:	mov	[rwcmd],2
	mov	[rwskip],0
	mov	[rwfaults],1
	mov	[count],0
	mov	[responses],offset metaresponses
	mov	[metaarea],2		; the failure must be a FAT read
	push	es
	push	di
	mov	dx,offset rwname
	mov	ah,DOS_DSK_DELETE
	int	21h
	pop	di
	pop	es
	jnc	df8			; deletion must report the injected failure
	push	ax
	call	check_metadata
	pop	ax
	jc	df8			; restore the entry only for the intended fault
	mov	byte ptr es:[di],'H'	; restore HERRDATA.TMP for normal cleanup
	cmp	ax,ERR_NOTREADY		; preserve the FAT read error, not the drive #
	jne	df8
	mov	dx,offset deletepassed
	call	print
	clc
	jmp	short df9
df8:	mov	dx,offset deletefailed
	call	print
	stc
df9:	push	cs
	pop	es
	ret
ENDPROC	delete_failure

;
; disk_handler (INT 13h)
;
; Fail selected data operations on the test drive with BIOS error 80h
; (not ready).
; Skip successful operations when testing a failure after partial progress.
; For large volume writes, count sectors and suppress the actual writes.
; All other operations go to the original BIOS handler.
;
DEFPROC	disk_handler,far
	cmp	dl,cs:[rwdrive]		; only the test file's BIOS drive
	jne	dh9
	cmp	cs:[rwlarge],0		; are large volume writes being counted?
	je	dh0
	cmp	ah,3			; leave reads to the real BIOS
	jne	dh9
	push	ax
	xor	ah,ah
	add	cs:[volsectors],ax
	pop	ax
	mov	ah,0			; simulate success without changing the disk
	push	bp
	mov	bp,sp
	and	word ptr [bp+6],NOT FL_CARRY
	pop	bp
	iret
dh0:
	cmp	ah,cs:[rwcmd]		; only the selected read/write operation
	jne	dh9
	cmp	cs:[rwfaults],0		; stop injecting after two failures
	je	dh9
	cmp	cs:[rwskip],0		; allow the partial first sector to finish
	je	dh1
	dec	cs:[rwskip]
	jmp	dh9
dh1:
	dec	cs:[rwfaults]
	mov	cs:[faultaddr].OFF,bx
	mov	cs:[faultaddr].SEG,es
	mov	cs:[faultcx],cx
	mov	cs:[faultdx],dx
	push	bp
	mov	bp,sp
	or	word ptr [bp+6],FL_CARRY ; return carry in the saved interrupt flags
	pop	bp
	mov	ax,8000h
	iret
dh9:
	jmp	cs:[old_disk]
ENDPROC	disk_handler

;
; handler (INT 24h)
;
; Records the registers DOS passed, counts the call, and returns the next
; response from the list.
;
DEFPROC	handler,far
	push	ds
	push	cs
	pop	ds
	mov	[regAX],ax
	mov	[regDI],di
	mov	[regDDH].OFF,si
	mov	[regDDH].SEG,bp
	mov	[regSS],ss
	inc	[count]
	push	si
	mov	si,[responses]
	lodsb
	mov	[responses],si
	pop	si
	pop	ds
	iret
ENDPROC	handler

DEFPROC	print
	mov	ah,DOS_TTY_PRINT
	int	21h
	ret
ENDPROC	print

count		db	0
responses	dw	0
regAX		dw	0
regDI		dw	0
regDDH		dd	0		; BP:SI
regSS		dw	0
test1		db	CRERR_RETRY,CRERR_FAIL
test2		db	CRERR_IGNORE,CRERR_FAIL
test3		db	CRERR_ABORT,CRERR_FAIL
filename	db	"B:HARDERR.TMP",0
starting	db	"HARDERR starting",13,10,'$'
passed		db	"HARDERR passed",13,10,'$'
failed		db	"HARDERR failed",13,10,'$'
abortfail	db	"HARDERR abort failed",13,10,'$'
skipped		db	"HARDERR skipped (other sessions are running)",13,10,'$'
old_disk	dd	0
rwhandle	dw	0
hooked		db	0
rwcmd		db	0
rwskip		db	0
rwfaults	db	0
rwdrive		db	0
rwlarge		db	0
volseg		dw	0
volsectors	dw	0
volname		db	"A:",0
volpassed	db	"HARDERR large writes passed",13,10,'$'
;
; Each case contains the volume offset, unsigned byte count, and expected
; BIOS write sector count (partial sectors require a merged sector write).
;
volcases	dw	0,7FFFh,64
		dw	0,8000h,64
		dw	0,8001h,65
		dw	0,0FFFEh,128
		dw	0,0FFFFh,128
		dw	512,8000h,64
		dw	1,8000h,65
		dw	1,0FFFFh,128
		dw	0,0,0
rwresponses	db	CRERR_RETRY,CRERR_RETRY,CRERR_FAIL
rwname		db	"A:\HERRDATA.TMP",0
rwentry		db	"HERRDATATMP"
faultaddr	dd	0
faultcx		dw	0
faultdx		dw	0
metaarea	db	0
metaresponses	db	CRERR_FAIL,CRERR_FAIL
metapassed	db	"HARDERR metadata passed",13,10,'$'
metafailed	db	"HARDERR metadata failed",13,10,'$'
seekpassed	db	"HARDERR seek passed",13,10,'$'
seekfailed	db	"HARDERR seek failed",13,10,'$'
deletepassed	db	"HARDERR delete passed",13,10,'$'
deletefailed	db	"HARDERR delete failed",13,10,'$'
;
; Each case contains file offset, length, BIOS command, and successful
; BIOS operations to skip before injecting the first failure.
;
rwcases		dw	512,512
		db	2,0
		dw	1,1536
		db	2,1
		dw	0,128
		db	2,0
		dw	512,512
		db	3,0
		dw	1,1536
		db	3,1
		dw	0,128
		db	3,0
		dw	0,0

	COMHEAP	<2*RW_SIZE+512>

CODE	ENDS

	end	main
