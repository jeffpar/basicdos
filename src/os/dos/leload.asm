;
; BASIC-DOS LE Program Loader
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Only protected mode needs this code (and only on an 80386), so like the NE
; loader, it's in the part of the kernel's resident code that real mode
; doesn't keep (see set_fault).
;
; An LE ("linear executable") program is 32-bit code and data for a flat
; address space, which it gets from a flat machine (see CPU_V86 in v86.inc):
; a linear address space of its own, where only the memory it's been given is
; mapped, and where its code runs at ring 3, in protected mode.  The system's
; interrupt gates are all 16-bit (they'd lose the upper half of a 32-bit
; program's EIP and ESP), and DOS takes 16-bit pointers, so the program
; doesn't call DOS itself: as far as DOS can tell, the program is le_host, a
; piece of 16-bit kernel code that the program's PSP_START points to, which
; runs at ring 3 like any program's code (through le_csel), with the PSP's
; block as its data and stack.  It runs the machine until the 32-bit code
; issues an INT 21h (which exits from the machine, as every interrupt does),
; makes the DOS call itself, with selectors for whatever the call's 32-bit
; pointers point to (see fl_lin in 386v86.asm), and runs the machine again.
; So nothing in the kernel has to know about 32-bit programs, and since the
; translation happens at ring 3, it can't do anything that the program
; couldn't.
;
	DOSPSP equ 1
	DOSFUNC equ 1
	DOSNE equ 1
	include	macros.inc
	include	bios.inc
	include	dosapi.inc
	include	cpu.inc
	include	v86.inc
	include	leload.inc

DOS	segment word public 'CODE'

	EXTNEAR	<ne_read,ne_mz,load_done,load_fail,le_sel>
	EXTABS	<LE_HOSTOFF>
	EXTBYTE	<prog_user>
	EXTWORD	<dos_data>

	.286p
;
; An LE program's PSP block holds its PSP, then le_host's data (LED_*), and
; then le_host's stack, up to LE_LEN.  While loading, the block is LE_LOADLEN
; bytes, and what will be the stack holds the LE header, the object table,
; and the loader's variables (LEV_*), followed by a buffer for one page's
; fixup records.
;
NEBUF		equ	size PSP	; (see neload.asm)
LE_MAXOBJ	equ	16		; the most objects a program can have
LE_MEMHI	equ	4		; initial memory: 256K at most (64K's)
LE_HDR		equ	200h		; LE header (LEH_LEN bytes)
LE_OBJS		equ	LE_HDR + LEH_LEN; object table (LE_MAXOBJ entries)
LEV_TMP		equ	LE_OBJS + LE_MAXOBJ * LEO_LEN
LEV_DELTA	equ	LEV_TMP + 8	; dword: added to the file's addresses
LEV_HI		equ	LEV_DELTA + 4	; dword: the image's end (in the file)
LEV_LIN		equ	LEV_HI + 4	; dword: linear address of the page
LEV_VAL		equ	LEV_LIN + 4	; dword: a fixup's value
LEV_SIZE	equ	LEV_VAL + 4	; dword: the machine's memory size
LEV_BASE	equ	LEV_SIZE + 4	; dword: and linear address
LEV_HDR		equ	LEV_BASE + 4	; dword: file offset of the LE header
LEV_OBJ		equ	LEV_HDR + 4	; word: the object being loaded
LEV_IDX		equ	LEV_OBJ + 2	; word: index of the page's map entry
LEV_PAGE	equ	LEV_IDX + 2	; word: the page's number in the file
LEV_FILE	equ	LEV_PAGE + 2	; word: file handle
LEV_END		equ	LEV_FILE + 2	; word: end of the fixup records
LE_LEN		equ	800h		; the block's length (and stack's top)
LE_FIXBUF	equ	LE_LEN		; fixup records (while loading)
LE_FIXMAX	equ	2800h		; the most that one page can have
LE_LOADLEN	equ	LE_FIXBUF + LE_FIXMAX
	ASSERT	<LEV_END + 2>,LE,LE_LEN

	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING
;
; LE_INIT is what load_le copies to LED_MSG and LED_TBL, since le_host can
; read and write only the PSP's block: the message for a fault in the 32-bit
; code, whose digits le_host fills in, and a table of DOS
; functions, as the last function of each range and how its pointers are
; translated (LEF_*).
;
LEF_PASS	equ	0		; none (registers only)
LEF_STR		equ	1		; DS:EDX -> string or buffer (to 64K)
LEF_RW		equ	2		; DS:EDX -> ECX bytes to read or write
LEF_CWD		equ	3		; DS:ESI -> buffer
LEF_REN		equ	4		; DS:EDX and ES:EDI -> strings
LEF_MEM		equ	5		; allocate EBX bytes (EAX = address)
LEF_NONE	equ	-1		; not supported

	DEFLBL	LE_INIT,byte
	db	"CPU fault 00 (EC=0000) at 0000:00000000",13,10,'$'
	ASSERT	<$ - LE_INIT>,EQ,LE_MSGLEN
	db	DOS_TTY_READ,LEF_PASS,DOS_TTY_INPUT,LEF_STR
	db	DOS_TTY_STATUS,LEF_PASS,DOS_TTY_FLUSH,LEF_NONE
	db	DOS_DSK_SETDRV,LEF_PASS,DOS_DSK_GETDRV-1,LEF_NONE
	db	DOS_DSK_GETDRV,LEF_PASS,DOS_MSC_GETDATE-1,LEF_NONE
	db	DOS_MSC_SETTIME,LEF_PASS,DOS_DSK_GETDTA,LEF_NONE
	db	DOS_MSC_GETVER,LEF_PASS,DOS_DSK_GETDPB,LEF_NONE
	db	DOS_MSC_CTRLC,LEF_PASS,DOS_MSC_GETVEC,LEF_NONE
	db	DOS_DSK_GETINFO+1,LEF_PASS,DOS_DSK_MKDIR-1,LEF_NONE
	db	DOS_HDL_OPEN,LEF_STR,DOS_HDL_CLOSE,LEF_PASS
	db	DOS_HDL_WRITE,LEF_RW,DOS_DSK_DELETE,LEF_STR
	db	DOS_HDL_SEEK,LEF_PASS,DOS_HDL_SEEK+1,LEF_STR
	db	DOS_HDL_IOCTL,LEF_PASS,DOS_DSK_GETCWD-1,LEF_NONE
	db	DOS_DSK_GETCWD,LEF_CWD,DOS_MEM_ALLOC,LEF_MEM
	db	DOS_PSP_RETURN-1,LEF_NONE,DOS_PSP_RETCODE,LEF_PASS
	db	DOS_DSK_FFIRST,LEF_STR,DOS_DSK_FNEXT,LEF_PASS
	db	DOS_DSK_RENAME-1,LEF_NONE,DOS_DSK_RENAME,LEF_REN
	db	DOS_DSK_RENAME+1,LEF_PASS,0FFh,LEF_NONE
LE_INITLEN	equ	$ - LE_INIT
	ASSERT	<LED_TBL + LE_INITLEN - LE_MSGLEN>,LE,LE_HDR

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; load_le
;
; ne_load jumps here for a program whose new header isn't NE.  If it's
; an LE header (and the processor is an 80386, with programs at ring 3), we
; create a flat machine for the program, with enough memory for its objects,
; or more if there's plenty: half of the largest free block, up to 256K (it
; can ask for more; see lh_mem).  The objects are loaded one after another,
; each starting on a page, from the start of the machine's memory (not at the
; addresses that the linker gave them): each object's pages are read (or left
; zeroed), and each page's fixup records are applied, which must all be
; internal 32-bit offsets, which is what a flat program has.
;
; The program starts at le_host, with its entry point and stack pointer (from
; the LE header) in the machine's registers, along with DS = its data selector
; (which its SS always is), ES = its PSP's (16-bit) selector, EDX = its first
; object's address, EBX = the address after its last object, and ECX = how
; much memory follows that.
;
; Inputs:
;	BX = file handle
;	DS = PSP, with the header's file offset in NE_CRC (see ne_load)
;	SS:BP -> load_ne's frame
;
; Outputs:
;	As for load_ne
;
DEFPROC	load_le,DOS
	push	ds
	pop	es
	push	bx
	mov	bx,LE_LOADLEN SHR 4
	mov	ah,DOS_MEM_REALLOC
	int	21h			; resize the PSP's block for loading
	pop	bx
	jc	le9
	mov	ds:[LEV_FILE],bx
	mov	ax,ds:[NEBUF].NE_CRC._OFF
	mov	ds:[LEV_HDR],ax
	mov	ax,ds:[NEBUF].NE_CRC._SEG
	mov	ds:[LEV_HDR+2],ax
	sub	ax,ax
	cwd
	mov	si,LE_HDR
	mov	cx,LEH_LEN
	call	le_hread		; read the LE header
	jc	le_mz			; there's none (the file's too short)
	cmp	word ptr [si],SIG_LE	; is it an LE header?
	jne	le_mz			; no, so it's a real-mode program
	cmp	cs:[prog_user],0	; programs at ring 3?
	je	le8			; no
	cmp	word ptr [si+LEH_ORDER],0	; little-endian?
	jne	le8			; no
	cmp	word ptr [si+LEH_PAGESIZE],LE_PGSIZE
	jne	le8
	mov	cx,[si+LEH_NOBJ]
	jcxz	le8			; no objects
	cmp	cx,LE_MAXOBJ		; too many (for our table)?
	jbe	le1			; no
le8:	mov	ax,ERR_BADFORMAT	; COMMAND reports "Unable to load X"
le9:	mov	sp,bp
	pop	bp
	jmp	load_fail
le_mz:	jmp	ne_mz			; (which continues at load_fail, too)
le1:	mov	ax,LEO_LEN
	mul	cx
	xchg	cx,ax			; CX = size of the object table
	mov	ax,[si+LEH_OBJTAB]
	mov	dx,[si+LEH_OBJTAB+2]
	mov	si,LE_OBJS
	call	le_hread		; read the object table
	jc	le9
;
; Pack the objects: each one's address becomes the end of the one before it,
; rounded up to a page (and the first one's becomes zero), whatever address
; the linker gave it, since every reference to an object's address is a fixup
; record with the object's number (see le_fix).  LINK386 1.01, for one, puts
; each object at a multiple of 64K, which would otherwise be 64K of memory
; for each of them.
;
	mov	cx,ds:[LE_HDR+LEH_NOBJ]
	sub	di,di
	sub	bx,bx			; BX:DI = the next object's address
	mov	ds:[LEV_DELTA],di
	mov	ds:[LEV_DELTA+2],di	; (the lowest address, for now)
le2:	mov	[si+LEO_BASE],di
	mov	[si+LEO_BASE+2],bx
	add	di,[si+LEO_SIZE]
	adc	bx,[si+LEO_SIZE+2]	; BX:DI = the object's end
	jc	le8
	mov	ds:[LEV_HI],di
	mov	ds:[LEV_HI+2],bx	; (the image's end, after the last)
	add	di,LE_PGSIZE - 1
	adc	bx,0
	jc	le8
	and	di,NOT (LE_PGSIZE - 1)
	add	si,LEO_LEN
	loop	le2
	mov	si,bx			; SI:DI = the image's length, in pages
	mov	ax,si
	or	ax,di
	jnz	le2d
	jmp	le8			; there's nothing to load
le2d:
;
; Create the machine with half of the largest free block (256K at most),
; if that's more than the image needs and there's still room for it (and
; the machine's tables), or else with just what the image needs.
;
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU	; DX:CX = largest free block
	shr	dx,1
	rcr	cx,1			; half of it
	and	cx,NOT (LE_PGSIZE - 1)
	cmp	dx,LE_MEMHI		; more than the most we start with?
	jb	le3			; no
	mov	dx,LE_MEMHI
	sub	cx,cx
le3:	cmp	dx,si			; more than the image needs?
	jb	le4			; no
	ja	le3a
	cmp	cx,di
	jbe	le4
le3a:	push	si
	push	di
	mov	si,dx
	mov	di,cx
	call	le_new
	pop	di
	pop	si
	jnc	le5
le4:	call	le_new			; AX = machine, DX:CX = its memory
	jnc	le5
	jmp	le8			; (no memory, or no 80386)
le5:	mov	ds:[LED_MACH],ax
	mov	ds:[LEV_BASE],cx
	mov	ds:[LEV_BASE+2],dx
	xchg	bx,ax			; BX = machine
	mov	si,ds:[LEV_SIZE+2]
	mov	di,ds:[LEV_SIZE]
	call	le_zero			; zero all of its memory
	jnc	le5a
	jmp	le9
le5a:
	mov	ax,ds:[LEV_BASE]
	mov	dx,ds:[LEV_BASE+2]
	sub	ax,ds:[LEV_DELTA]
	sbb	dx,ds:[LEV_DELTA+2]
	mov	ds:[LEV_DELTA],ax
	mov	ds:[LEV_DELTA+2],dx	; what to add to the file's addresses
;
; Load each object's pages.
;
	mov	si,LE_OBJS
	mov	cx,ds:[LE_HDR+LEH_NOBJ]
le6:	push	cx
	mov	ds:[LEV_OBJ],si
	mov	ax,[si+LEO_BASE]
	mov	dx,[si+LEO_BASE+2]
	add	ax,ds:[LEV_DELTA]
	adc	dx,ds:[LEV_DELTA+2]
	mov	ds:[LEV_LIN],ax
	mov	ds:[LEV_LIN+2],dx
	mov	ax,[si+LEO_MAPIDX]
	dec	ax
	mov	ds:[LEV_IDX],ax
	mov	cx,[si+LEO_NPAGES]
	jcxz	le6b
le6a:	push	cx
	call	le_page
	pop	cx
	jnc	le6c
	jmp	le9
le6c:
	add	word ptr ds:[LEV_LIN],LE_PGSIZE
	adc	word ptr ds:[LEV_LIN+2],0
	inc	word ptr ds:[LEV_IDX]
	loop	le6a
le6b:	pop	cx
	mov	si,ds:[LEV_OBJ]
	add	si,LEO_LEN
	loop	le6
	mov	bx,ds:[LEV_FILE]
	mov	ah,DOS_HDL_CLOSE
	int	21h			; close the file
	jnc	le6d
	jmp	le9
le6d:
;
; Set up le_host's data: the machine's registers, the fault message, and
; the function table.
;
	push	ds
	pop	es
	mov	di,LED_REGS
	mov	cx,(LE_HDR - LED_REGS) / 2
	sub	ax,ax
	cld
	rep	stosw
	mov	bx,LEH_EIPOBJ
	call	le_addr			; DX:AX = entry point
	jnc	le7
le6e:	jmp	le8
le7:
	mov	word ptr ds:[LED_REGS].VR_EIP,ax
	mov	word ptr ds:[LED_REGS].VR_EIP+2,dx
	mov	bx,LEH_ESPOBJ
	call	le_addr			; DX:AX = stack pointer
	jc	le6e
	mov	word ptr ds:[LED_REGS].VR_ESP,ax
	mov	word ptr ds:[LED_REGS].VR_ESP+2,dx
	mov	ax,ds:[LED_MACH]
	add	ax,4 * 8 + 3		; AX = its data selector (see fl_lin)
	mov	word ptr ds:[LED_REGS].VR_DS,ax
	mov	word ptr ds:[LED_REGS].VR_ES,ds
	mov	ax,ds:[LEV_HI]
	mov	dx,ds:[LEV_HI+2]
	add	ax,ds:[LEV_DELTA]
	adc	dx,ds:[LEV_DELTA+2]
	add	ax,3
	adc	dx,0
	and	al,0FCh			; DX:AX = the address after the image
	mov	word ptr ds:[LED_REGS].VR_EBX,ax
	mov	word ptr ds:[LED_REGS].VR_EBX+2,dx
	mov	cx,ds:[LEV_BASE]
	mov	bx,ds:[LEV_BASE+2]
	mov	word ptr ds:[LED_REGS].VR_EDX,cx
	mov	word ptr ds:[LED_REGS].VR_EDX+2,bx
	add	cx,ds:[LEV_SIZE]
	adc	bx,ds:[LEV_SIZE+2]
	sub	cx,ax
	sbb	bx,dx			; BX:CX = the memory that follows it
	mov	word ptr ds:[LED_REGS].VR_ECX,cx
	mov	word ptr ds:[LED_REGS].VR_ECX+2,bx
	mov	si,offset LE_INIT
	mov	di,LED_MSG
	mov	cx,LE_INITLEN
	rep	movs byte ptr es:[di],byte ptr cs:[si]
	call	le_sel			; AX = le_host's code selector
	jc	le6e
	mov	ds:[PSP_START]._SEG,ax
	mov	ds:[PSP_START]._OFF,LE_HOSTOFF
	mov	ds:[PSP_STACK]._SEG,ds
	mov	ds:[PSP_STACK]._OFF,LE_LEN
	mov	sp,bp
	pop	bp
	mov	bx,LE_LEN SHR 4		; BX = paras for the PSP's block
	sub	dx,dx			; DX = 0 (no heap to zero)
	jmp	load_done
ENDPROC	load_le


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; le_new
;
; Creates the program's flat machine.
;
; Inputs:
;	SI:DI = length of its memory
;	DS = PSP (its owner)
;
; Outputs:
;	Carry clear: AX = machine, DX:CX = its memory's linear address
;	Carry set: AX = error code
;
DEFPROC	le_new
	mov	ds:[LEV_SIZE],di
	mov	ds:[LEV_SIZE+2],si
	mov	bx,ds
	mov	ax,(CPU_V86 SHL 8) OR 6
	call	far ptr DDINT_CPU
	ret
ENDPROC	le_new

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; le_hread
;
; Reads CX bytes into DS:SI, from offset DX:AX of the LE header.
;
; Outputs:
;	As for ne_read
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	le_hread
	add	ax,ds:[LEV_HDR]
	adc	dx,ds:[LEV_HDR+2]
	mov	bx,ds:[LEV_FILE]
	jmp	ne_read
ENDPROC	le_hread

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; le_addr
;
; Returns the linear address of an object number and offset in the LE header
; (the entry point's, or the stack pointer's).
;
; Inputs:
;	BX = offset of the object number in the header (the offset follows it)
;	DS = PSP
;
; Outputs:
;	Carry clear: DX:AX = linear address
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	le_addr
	mov	ax,ds:[LE_HDR+bx]
	dec	ax
	cmp	ax,ds:[LE_HDR+LEH_NOBJ]	; is it a valid object #?
	cmc
	jc	la9			; no
	mov	si,LEO_LEN
	mul	si
	xchg	si,ax			; SI = offset of the object's entry
	mov	ax,ds:[LE_HDR+bx+4]
	mov	dx,ds:[LE_HDR+bx+6]
	add	ax,ds:[LE_OBJS+si+LEO_BASE]
	adc	dx,ds:[LE_OBJS+si+LEO_BASE+2]
	add	ax,ds:[LEV_DELTA]
	adc	dx,ds:[LEV_DELTA+2]
	clc
la9:	ret
ENDPROC	le_addr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; le_page
;
; Loads the page at LEV_LIN, from the object page map entry LEV_IDX: 3 bytes
; with the page's number in the file (high byte first), which is also its
; number in the fixup page table, and a byte of flags: zero if the page's data
; is in the file, 1 if it's "iterated" (not supported), or anything else if
; there's none (the page stays zeroed).  The last page in the file has only
; LEH_LASTPAGE bytes.
;
; Inputs:
;	DS = PSP
;
; Outputs:
;	Carry clear if successful, set if not (AX = error code)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	le_page
	mov	ax,ds:[LEV_IDX]
	call	le_x4			; DX:AX = offset of its map entry
	add	ax,ds:[LE_HDR+LEH_PAGEMAP]
	adc	dx,ds:[LE_HDR+LEH_PAGEMAP+2]
	mov	si,LEV_TMP
	mov	cx,4
	call	le_hread
	jnc	lg0c
lg0:	ret
lg0a:	clc
	ret
lg0b:	jmp	lg8
lg0c:	mov	al,[si+3]		; AL = the page's flags
	cmp	al,1
	je	lg0b			; (iterated)
	ja	lg0a			; (no data)
	mov	ah,[si+1]
	mov	al,[si+2]		; AX = the page's number in the file
	test	ax,ax
	jz	lg0a
	mov	ds:[LEV_PAGE],ax
	mov	di,LE_PGSIZE		; DI = # of bytes it has in the file
	cmp	ax,ds:[LE_HDR+LEH_PAGES]	; is it the last page?
	jne	lg1			; no
	mov	ax,ds:[LE_HDR+LEH_LASTPAGE]
	dec	ax
	cmp	ax,di			; does it have a valid length?
	jae	lg1			; no (so it's a whole page)
	inc	ax
	xchg	di,ax
lg1:	mov	bx,ds:[LED_MACH]
	mov	cx,ds:[LEV_LIN]
	mov	dx,ds:[LEV_LIN+2]
	sub	si,si
	mov	ax,(CPU_V86 SHL 8) OR 7
	call	far ptr DDINT_CPU	; AX = selector for the page
	jc	lg0b			; (it's outside the machine's memory)
	cmp	cx,LE_PGSIZE - 1	; does it cover the whole page?
	jb	lg0b			; no
	mov	es,ax
	mov	ax,ds:[LEV_PAGE]
	dec	ax
	mov	dx,ax
	shl	ax,12
	shr	dx,4			; DX:AX = the page's offset in the data
	add	ax,ds:[LE_HDR+LEH_DATA]
	adc	dx,ds:[LE_HDR+LEH_DATA+2]
	mov	cx,di
	mov	bx,ds:[LEV_FILE]
	push	ds
	push	es
	pop	ds
	sub	si,si
	call	ne_read			; read the page
	pop	ds
	jc	lg9
	mov	ax,ds:[LEV_PAGE]
	dec	ax
	call	le_x4			; DX:AX = offset of its fixup offsets
	add	ax,ds:[LE_HDR+LEH_FIXPAGE]
	adc	dx,ds:[LE_HDR+LEH_FIXPAGE+2]
	mov	si,LEV_TMP
	mov	cx,8
	call	le_hread		; this page's offset, and the next's
	jc	lg9
	mov	cx,[si+4]
	sub	cx,[si]			; CX = length of its fixup records
	jz	lg7			; there are none
	cmp	cx,LE_FIXMAX		; too many (for our buffer)?
	ja	lg8			; yes
	mov	ax,[si]
	mov	dx,[si+2]
	add	ax,ds:[LE_HDR+LEH_FIXREC]
	adc	dx,ds:[LE_HDR+LEH_FIXREC+2]
	mov	si,LE_FIXBUF
	push	cx
	call	le_hread		; read them
	pop	cx
	jc	lg9
	jmp	short le_fix		; and apply them
lg7:	clc
	ret
lg8:	mov	ax,ERR_BADFORMAT
	stc
lg9:	ret
le_x4:	sub	dx,dx
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1			; DX:AX = AX * 4
	ret
ENDPROC	le_page

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; le_fix
;
; Applies a page's fixup records, each of which must be for a 32-bit offset
; (source type 07h) to an object of the program (target flags 00h, with 10h
; for a 32-bit target offset and 40h for a 16-bit object number); the source
; is an offset in the page, or with 20h in the source type, a count of
; offsets that follow the target.  A source that crosses into another page
; has a record in each page (with a negative offset in the second), so only
; the bytes in this page are stored.
;
; Inputs:
;	DS:SI -> records, CX = their length
;	ES:0 -> the page
;
; Outputs:
;	Carry clear if successful, set if not (AX = error code)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	le_fix
	add	cx,si
	mov	ds:[LEV_END],cx
	jmp	short lf1
lf0:	mov	ax,ERR_BADFORMAT
	stc
	ret
lf1:	cmp	si,ds:[LEV_END]		; any more records?
	jb	lf1a			; yes
	ret				; (carry is clear)
lf1a:	lodsw				; AL = source type, AH = target flags
	mov	dx,ax
	and	al,0DFh
	cmp	al,07h			; a 32-bit offset?
	jne	lf0			; no
	test	dh,0AFh			; to an object of the program?
	jnz	lf0			; no
	mov	cx,1
	test	dl,20h			; a list of sources?
	jz	lf2			; no
	lodsb
	mov	cl,al			; CX = # of sources
	jcxz	lf0
	jmp	short lf3
lf2:	lodsw
	xchg	di,ax			; DI = the source's offset
lf3:	lodsb
	mov	ah,0
	test	dh,40h			; a 16-bit object #?
	jz	lf3a			; no
	dec	si
	lodsw
lf3a:	dec	ax
	cmp	ax,ds:[LE_HDR+LEH_NOBJ]	; is it a valid object #?
	jae	lf0			; no
	mov	bx,LEO_LEN
	push	dx
	mul	bx
	pop	dx
	xchg	bx,ax			; BX = offset of the object's entry
	mov	ax,ds:[LE_OBJS+bx+LEO_BASE]
	add	ax,ds:[LEV_DELTA]
	mov	ds:[LEV_VAL],ax
	mov	ax,ds:[LE_OBJS+bx+LEO_BASE+2]
	adc	ax,ds:[LEV_DELTA+2]
	mov	ds:[LEV_VAL+2],ax	; the object's linear address
	lodsw
	add	ds:[LEV_VAL],ax
	adc	word ptr ds:[LEV_VAL+2],0
	test	dh,10h			; a 32-bit target offset?
	jz	lf4			; no
	lodsw
	add	ds:[LEV_VAL+2],ax
lf4:	test	dl,20h			; a list of sources?
	jz	lf6			; no
lf5:	lodsw
	xchg	di,ax
lf6:	push	si
	push	cx
	mov	si,LEV_VAL
	mov	cx,4
lf7:	lodsb
	cmp	di,LE_PGSIZE		; is this byte in the page?
	jae	lf7a			; no
	mov	es:[di],al
lf7a:	inc	di
	loop	lf7
	pop	cx
	pop	si
	test	dl,20h
	jz	lf8
	loop	lf5
lf8:	jmp	lf1
ENDPROC	le_fix

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; le_zero
;
; Zeroes memory in a flat machine, a piece at a time (see fl_lin), with
; interrupts as they were, since CPU$ would have to do it with them off.
;
; Inputs:
;	BX = machine, DX:CX = linear address
;	SI:DI = length (a multiple of LE_PGSIZE)
;
; Outputs:
;	Carry clear if successful, set if not (AX = error code)
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	le_zero
lz1:	mov	ax,si
	or	ax,di			; anything left?
	jz	lz9			; no (and carry is clear)
	push	si
	push	cx
	push	dx
	sub	si,si
	mov	ax,(CPU_V86 SHL 8) OR 7
	call	far ptr DDINT_CPU	; AX = selector, CX = its limit
	pop	dx
	pop	si			; DX:SI = linear address
	jc	lz8
	mov	es,ax
	inc	cx			; CX = # of bytes there (0 if 64K)
	pop	ax			; AX:DI = length
	test	ax,ax			; 64K or more left?
	jnz	lz2			; yes
	jcxz	lz1a
	cmp	cx,di			; more there than is left?
	jbe	lz2			; no
lz1a:	mov	cx,di
lz2:	push	ax
	push	di
	push	cx
	sub	di,di
	sub	ax,ax
	shr	cx,1
	jnz	lz3
	mov	ch,80h			; (64K)
lz3:	cld
	rep	stosw
	pop	cx
	pop	di
	pop	ax
	cmp	cx,1			; (carry set if 64K)
	adc	dx,0
	add	si,cx
	adc	dx,0			; DX:SI = the next address
	cmp	cx,1
	sbb	ax,0
	sub	di,cx
	sbb	ax,0			; AX:DI = what's left
	mov	cx,si
	xchg	si,ax
	jmp	lz1
lz8:	pop	si
lz9:	ret
ENDPROC	le_zero


DOS	ends

	end
