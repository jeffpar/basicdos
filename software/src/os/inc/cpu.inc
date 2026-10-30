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
; which only one stays loaded: the first (cpudev.asm) stores the processor
; type in CPU_TYPE (see bios.inc), and stays on an 80286 or later that can use
; protected mode, where it manages memory with a table of PMBs (and protected-
; mode descriptors, too); otherwise, the second (cpu86dev.asm) stays, and
; manages memory with a chain of MCBs, as DOS always has.  Their functions are
; the same, and are called through DDINT_CPU (see bios.inc) with a function
; number in AH; until CPU$ is loaded, DDINT_CPU returns with carry set.  See
; docs/bdtech/mmu for the design.
;

;
; CPU types (CPU_TYPE)
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
; with SELF_AT needs that paragraph free too.
;
CPU_GETINFO	equ	00h	; AL = CPU type, AH = CPUF_*, DX:CX = free
CPU_ALLOC	equ	01h	; AL = SELF_*, BX = owner, SI:DI = length
CPU_FREE	equ	02h	; DX:CX = address returned by CPU_ALLOC
CPU_MAP		equ	03h	; AL = SELF_*, DX:CX = address, SI:DI = length
CPU_UNMAP	equ	04h	; BX = selector, CX = # selectors (0 = 1)
CPU_QUERY	equ	05h	; BX = PMB #; stores PMB at ES:DI
CPU_ALIAS	equ	06h	; AL = SELF_*, BX = selector to alias
CPU_PMODE	equ	07h	; switch to protected mode (AX = CS data alias)
CPU_REALLOC	equ	08h	; DX:CX = address of block, SI:DI = new length
CPU_MOVE	equ	09h	; ES:BX -> MOVEPKT
CPU_MAXFUNC	equ	09h

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

;
; Selector flags (AL) for CPU_ALLOC, CPU_MAP, and CPU_ALIAS
;
; In protected mode, CPU_ALLOC and CPU_MAP return the first selector in AX; a
; block larger than 64K is mapped by consecutive selectors (each 8 more than
; the last), each covering the next 64K.  CPU_ALIAS returns a new selector for
; the same memory as an existing one (eg, a code selector for a block of
; generated code, or for a COM program's PSP block; see docs/bdtech/mmu), with
; its base address in DX:CX; CPU_UNMAP frees it.  In real mode, the same
; functions return the segment of the memory instead (a segment is its own
; alias, and there's nothing to unmap), so callers needn't check the mode.
;
; CPU_ALLOC allocates the first free block that's big enough, in extended
; memory if there is any, unless SELF_LOW, SELF_HIGH, or SELF_AT is set.
;
SELF_LDT	equ	01h	; LDT selector(s) (otherwise GDT)
SELF_CODE	equ	02h	; code (execute/read), not data (read/write)
SELF_NONE	equ	04h	; CPU_ALLOC only: no selector (AX = 0)
SELF_RDONLY	equ	08h	; read-only data (or execute-only code)
SELF_USER	equ	10h	; DPL 3, for programs (otherwise DPL 0)
SELF_LOW	equ	20h	; CPU_ALLOC only: below 1Mb (eg, for DOS)
SELF_HIGH	equ	40h	; CPU_ALLOC only: from the top (of SELF_LOW)
SELF_AT		equ	80h	; CPU_ALLOC only: at address DX:CX

;
; Physical Memory Block (PMB)
;
; The 80286 driver's arena is a table of PMBs, in address order, describing
; all memory from address 0 to the end of extended memory; the last PMB has
; signature PMBSIG_LAST.  Unlike DOS MCBs, PMBs aren't stored in the memory
; they describe, so blocks need no header, and the arena can describe memory
; that isn't RAM (eg, adapter memory and ROMs).  Like an MCB, a PMB also has
; a block type (MCBTYPE_*) and a name, for MEM.  CPU_QUERY returns a PMB from
; either driver (the 8086 driver's describe its MCBs).
;
PMB		struc
PMB_SIG		db	?	; 00h: PMBSIG_NEXT or PMBSIG_LAST
PMB_TYPE	db	?	; 01h: PMBTYPE_*
PMB_OWNER	dw	?	; 02h: owner (from CPU_ALLOC), or 0
PMB_ADDR	dd	?	; 04h: physical address
PMB_LEN		dd	?	; 08h: length, in bytes
PMB_SEL		dw	?	; 0Ch: first selector, if any
PMB_NSEL	dw	?	; 0Eh: number of selectors
PMB_MCBTYPE	db	?	; 10h: MCBTYPE_*, or 0
		db	7 dup(?); 11h: (reserved)
PMB_NAME	db	8 dup(?); 18h: name of process (zero if none)
PMB		ends

PMBSIG_NEXT	equ	'M'
PMBSIG_LAST	equ	'Z'

PMBTYPE_FREE	equ	0	; free memory
PMBTYPE_USED	equ	1	; allocated with CPU_ALLOC
PMBTYPE_DOS	equ	2	; conventional memory (managed with DOS MCBs)
PMBTYPE_SYS	equ	3	; CPU$ system area (descriptor tables and PMBs)
PMBTYPE_RSVD	equ	4	; not RAM (eg, video memory and ROMs)
