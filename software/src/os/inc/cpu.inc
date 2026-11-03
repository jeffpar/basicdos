;
; BASIC-DOS CPU$ Driver Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; CPU$ manages all of memory, and there are two built-in CPU$ drivers, of
; which only one stays loaded: the first (286dev.asm) stores the processor
; type in CPU_HWTYPE and CPU_TYPE (see bios.inc), and stays on an 80286 or
; later that can use protected mode, where it manages memory with a table of
; PMBs (and protected-mode descriptors, too); otherwise, the second
; (x86dev.asm) stays, and manages memory with a chain of MCBs, as DOS always
; has.  Their functions are the same, and are called through DDINT_CPU (see
; bios.inc) with a function number in AH; until CPU$ is loaded, DDINT_CPU
; returns with carry set.  See docs/bdtech/mmu for details.
;

;
; CPU types (CPU_TYPE and CPU_HWTYPE): CPU_TYPE is the type that BASIC-DOS
; uses, which a "CPU=8088" line in CONFIG.SYS makes CPUTYPE_8086, and
; CPU_HWTYPE is always the processor's own (eg, for a disassembler).
;
CPUTYPE_8086	equ	0	; 8086 or 8088 (or NEC V20 or V30)
CPUTYPE_80186	equ	1	; 80186 or 80188
CPUTYPE_80286	equ	2	; 80286
CPUTYPE_80386	equ	3	; 80386 or later

;
; CPU$ functions (AH)
;
; Physical addresses and lengths are 32-bit byte values: addresses are in
; DX:CX and lengths in SI:DI (high:low).  Errors return carry set and an error
; code in AX (ERR_NOMEMORY, ERR_BADADDR, or ERR_INVALID; see dosapi.inc); for
; ERR_NOMEMORY, CPU_ALLOC returns the length of the largest free block in
; DX:CX, and CPU_REALLOC the longest the block could be.  Every function works
; the same way in either mode, except that a selector in protected mode is a
; segment in real mode, and CPU_PMODE needs an 80286.  Each block that the
; 8086 driver allocates has an MCB in the paragraph before it, so CPU_ALLOC
; with MEMF_AT needs that paragraph free too.
;
; A block (DX:CX) is the address that CPU_ALLOC returned, or DX = -1 and CX =
; the selector (or segment) that it returned, which is what DOS has.
;
CPU_GETINFO	equ	00h	; AL = CPU type, AH = CPUF_*, DX:CX = free
CPU_ALLOC	equ	01h	; AL = MEMF_*, BX = owner, SI:DI = length
CPU_FREE	equ	02h	; DX:CX = block
CPU_MAP		equ	03h	; AL = MEMF_*, DX:CX = address, SI:DI = length
CPU_UNMAP	equ	04h	; BX = selector, CX = # selectors (0 = 1)
CPU_QUERY	equ	05h	; BX = PMB # (-1 for block DX:CX); PMB to ES:DI
CPU_ALIAS	equ	06h	; AL = MEMF_*, BX = selector to alias
CPU_PMODE	equ	07h	; switch to protected mode (AX = CS data alias)
CPU_REALLOC	equ	08h	; DX:CX = block, SI:DI = new length
CPU_MOVE	equ	09h	; ES:BX -> MOVEPKT
CPU_SETBLK	equ	0Ah	; DX:CX = block, AL = type, BX = owner, ES:SI
CPU_FREEALL	equ	0Bh	; BX = owner of the blocks to free
CPU_SETLIM	equ	0Ch	; BX = selector, SI:DI = new length (<= 64K)
CPU_SEGINFO	equ	0Dh	; AL = ADDR_SEL or 0, BX = segment or selector
CPU_RWMEM	equ	0Eh	; AL = ADDR_*, BX:SI = address, CX, ES:DI
CPU_SYSREGS	equ	0Fh	; ES:DI -> 12-byte buffer (GDTR and IDTR)
CPU_SETFAULT	equ	10h	; DX:CX = fault handler (0:0 for none)
CPU_SETSTACK	equ	11h	; DX:CX = ring 0 stack (SS:SP)
CPU_SETLDT	equ	12h	; AL = session # (selects its LDT)
CPU_MAXFUNC	equ	12h

;
; CPU_ALIAS with just MEMF_CODE, for the selector that CPU_ALLOC returned for a
; block, returns that block's code alias, which the 80286 driver creates only
; once (keeping it in PMB_CODE) and frees with the block, so it must not be
; freed with CPU_UNMAP (in real mode, a segment is its own alias).
;
; CPU_SETBLK sets a block's owner (BX, which must be non-zero), its type (AL =
; MCBTYPE_*), and its name (8 characters at ES:SI, or SI = 0 for none), for
; DOS (see PMB_MCBTYPE and PMB_NAME); CPU_FREE and CPU_FREEALL clear them.
;
; An owner (for CPU_ALLOC, CPU_SETBLK, and CPU_FREEALL) is a PSP (or a driver's
; segment, or MCBOWNER_SYSTEM), which the 80286 driver stores as an owner ID
; (PMB_OWNER): in protected mode, a ring 3 program's PSP is an LDT selector,
; which another session's program can share, so its ID is 80h plus its session
; # (see CPU_SETLDT) in the high byte and its LDT index in the low byte (eg,
; 8000h for session 0's COMMAND.COM); any other owner is its own ID.
;

;
; CPU_SEGINFO, CPU_RWMEM, and CPU_SYSREGS are for debuggers, so they never
; change CPU$'s state, and work even when CPU$ itself was interrupted (eg, at
; a breakpoint).  An address (segment:offset) is in real-mode form unless
; ADDR_SEL is set, in which case its segment is a protected-mode selector
; (which only the 80286 driver accepts), in either mode, or ADDR_PHYS is set,
; in which case it's a physical address (the "segment" holds bits 16-31, and
; with the 8086 driver, it must be below 1Mb):
;
;	CPU_SEGINFO returns the segment's base address in DX:CX and its limit
;	in AX (FFFFh for a real-mode segment), or with ADDR_RIGHTS, a
;	selector's access rights byte in AL and its descriptor's extended byte
;	(the 80386 flags and limit bits 16-19) in AH (zero for a real-mode
;	segment); for a gate, DX:CX is its selector and AX its offset.
;
;	CPU_RWMEM copies CX bytes from BX:SI to ES:DI, or from ES:DI to BX:SI
;	if ADDR_WRITE is set, even if BX:SI is in a code segment (eg, to store
;	a breakpoint); the bytes must be within the segment's limit, and in
;	real mode, below 1Mb.
;
;	CPU_SYSREGS stores the GDTR and IDTR (as SGDT and SIDT do) at ES:DI,
;	and returns the MSW in AX, the LDTR in CX, and the TR in DX (both zero
;	in real mode); the 8086 driver returns ERR_INVALID instead.
;
; CPU_SETFAULT sets the handler that a fatal protected-mode exception goes to
; (eg, a debugger's), before the 80286 driver reports it and stops the
; machine, unless it occurred in CPU$ or in the handler's own code, and
; returns the previous handler in DX:CX.  The handler is entered with the
; registers as they were, interrupts disabled, and SS:SP -> a far return
; address, the vector, the error code, and an interrupt frame for the
; faulting instruction: for a software interrupt with no handler, its vector
; (0FFh if unknown), the caller's AX, and the INT itself.  A handler that
; can't handle the exception declines it by returning (RETF) with the
; registers and stack as they were, and then CPU$ reports it ("CPU fault vv
; (EC=xxxx) at cccc:iiii" and "System halted").  A handler that passes the
; exception on to the previous one can replace the return address with its
; own, to see whether it was declined.  Before stopping the machine, CPU$
; offers the halt to the handler, as the same exception with FAULT_HALTED in
; the vector's high byte: a debugger can accept it by never returning (eg,
; by keeping control with interrupts disabled), and any other handler must
; decline it.  The 8086 driver keeps the handler too, but never calls it,
; since real-mode exceptions go through the vectors.
;
FAULT_HALTED	equ	80h	; CPU_SETFAULT: vector's high byte for a halt

;
; CPU_SETSTACK sets the ring 0 stack (SS:SP) that the processor switches to
; when an interrupt takes ring 3 code to ring 0, and returns the previous one
; in DX:CX.  The 80286 driver keeps it in its TSS, which CPU_PMODE loads;
; until a caller sets one, there's none (0:0), so nothing can run at ring 3.
; Software interrupts have DPL 3 gates, so ring 3 code can issue them (eg,
; INT 21h), and so does INT 0 (eg, FPU$ signals a divide error with it), but
; other exceptions and IRQs have DPL 0 gates (see pm_setvec).  The 8086
; driver returns ERR_INVALID, since there's no ring 3 in real mode.
;

ADDR_SEL	equ	01h	; the segment is a selector
ADDR_WRITE	equ	02h	; CPU_RWMEM: copy from ES:DI to BX:SI
ADDR_PHYS	equ	04h	; the "segment" is bits 16-31 of an address
ADDR_RIGHTS	equ	08h	; CPU_SEGINFO: AX = access rights, not limit

;
; In protected mode, a PSP's CALL 5 (a far call to PSP_FCSEG:PSP_SIZE) can't
; use the real-mode segment that reaches 0:00C0h, so PSP_FCSEG is SEL_CALL5,
; a call gate (which ignores the offset) to the far jump at 0:00C0h, with DPL
; 3, so that ring 3 programs can use it too (see r3_call5).
;
SEL_CALL5	equ	60h	; call gate for CALL 5 (see psp_setmem)

;
; CPU_MOVE copies MV_LEN bytes from MV_SRC to MV_DST (physical addresses),
; correctly even if they overlap.
;
MOVEPKT		struc
MV_SRC		dd	?	; source address
MV_DST		dd	?	; destination address
MV_LEN		dd	?	; length
MOVEPKT		ends

;
; CPU_GETINFO flags (AH)
;
CPUF_PM		equ	01h	; processor is in protected mode
CPUF_PMOK	equ	02h	; protected-mode self-test passed
CPUF_HWTYPE	equ	0C0h	; CPU_HWTYPE (in bits 6-7)

;
; Memory flags (AL) for CPU_ALLOC, CPU_MAP, and CPU_ALIAS
;
; In protected mode, CPU_ALLOC and CPU_MAP return the first selector in AX; a
; block larger than 64K is mapped by consecutive selectors (each 8 more than
; the last), each covering the next 64K.  CPU_ALIAS returns a new selector for
; the same memory as an existing one (eg, a code selector for a block of
; generated code, or for a COM program's PSP block; see docs/bdtech/mmu), with
; its base address in DX:CX; CPU_UNMAP frees it.  CPU_SETLIM changes the
; length that a selector covers (eg, to fit a driver's selectors to what it
; keeps after its initialization), without changing the selector.  In real
; mode, the same functions return the segment of the memory instead (a
; segment is its own alias, and there's nothing to unmap or change), so
; callers needn't check the mode.
;
; CPU_ALLOC allocates from the first free block that's big enough, or with
; MEMF_HIGH, the top of the last one, anywhere in memory (conventional or
; extended), unless MEMF_LOW (below 1Mb) or MEMF_AT is set.
;
; MEMF_CONFORM (with MEMF_CODE) makes conforming code, which code at any ring
; can call, and which runs at the caller's ring (eg, FPU$'s functions, which
; the kernel calls at ring 0 and programs at ring 3).
;
MEMF_LDT	equ	01h	; LDT selector(s) (otherwise GDT)
MEMF_CODE	equ	02h	; code (execute/read), not data (read/write)
MEMF_NONE	equ	04h	; CPU_ALLOC only: no selector (AX = 0)
MEMF_CONFORM	equ	04h	; CPU_MAP and CPU_ALIAS only: conforming code
MEMF_RDONLY	equ	08h	; read-only data (or execute-only code)
MEMF_USER	equ	10h	; DPL 3, for programs (otherwise DPL 0)
MEMF_LOW	equ	20h	; CPU_ALLOC only: below 1Mb (eg, for real mode)
MEMF_HIGH	equ	40h	; CPU_ALLOC only: from the top
MEMF_AT		equ	80h	; CPU_ALLOC only: at address DX:CX

;
; Physical Memory Block (PMB)
;
; The 80286 driver's arena is a table of PMBs, in address order, describing
; all memory from address 0 to the end of extended memory; the last PMB has
; signature PMBSIG_LAST.  Unlike DOS MCBs, PMBs aren't stored in the memory
; they describe, so blocks need no header, and the arena can describe memory
; that isn't RAM (eg, adapter memory and ROMs).  Like an MCB, a PMB also has
; a block type (MCBTYPE_*) and a name, for MEM.  CPU_QUERY returns a PMB from
; either driver (the 8086 driver's describe its MCBs, and PMB_SEL is each
; block's segment).
;
; For debuggers that can't call CPU$ (eg, the PCjs Debugger's "d dos"
; command), the driver that stays stores the real-mode address of its arena
; in CPU_ARENA (see bios.inc): the 8086 driver's first MCB, or the 80286
; driver's PMB table, which is in the system area (above 1Mb).
;
PMB		struc
PMB_SIG		db	?	; 00h: PMBSIG_NEXT or PMBSIG_LAST
PMB_TYPE	db	?	; 01h: PMBTYPE_*
PMB_OWNER	dw	?	; 02h: owner ID (see CPU_SETBLK), or 0
PMB_ADDR	dd	?	; 04h: physical address
PMB_LEN		dd	?	; 08h: length, in bytes
PMB_SEL		dw	?	; 0Ch: first selector, if any
PMB_NSEL	dw	?	; 0Eh: number of selectors
PMB_MCBTYPE	db	?	; 10h: MCBTYPE_*, or 0
		db	?	; 11h: (reserved)
PMB_CODE	dw	?	; 12h: code alias (see CPU_ALIAS), or 0
		db	4 dup(?); 14h: (reserved)
PMB_NAME	db	8 dup(?); 18h: name of process (zero if none)
PMB		ends

PMBSIG_NEXT	equ	'M'
PMBSIG_LAST	equ	'Z'

PMBTYPE_FREE	equ	0	; free memory
PMBTYPE_USED	equ	1	; allocated with CPU_ALLOC
PMBTYPE_SYS	equ	2	; CPU$ system area (descriptor tables and PMBs)
PMBTYPE_RSVD	equ	3	; not RAM (eg, video memory and ROMs)
