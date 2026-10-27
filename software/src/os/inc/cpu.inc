;
; BASIC-DOS CPU$ Driver Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The CPU$ driver is the first built-in driver.  It stores the processor type
; in CPU_TYPE (see bios.inc), and on an 80286 or later with at least 64K of
; extended memory, it stays loaded to manage physical memory and protected-mode
; descriptors; otherwise, it unloads itself.  Its functions are called through
; DDINT_CPU (see bios.inc) with a function number in AH; if CPU$ isn't loaded,
; DDINT_CPU returns with carry set.  See docs/bdtech/mmu for the design.
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
; code in AX (ERR_NOMEMORY, ERR_BADADDR, or ERR_INVALID; see dosapi.inc).
;
CPU_GETINFO	equ	00h	; AL = CPU type, AH = CPUF_*, DX:CX = free
CPU_ALLOC	equ	01h	; AL = SELF_*, BX = owner, SI:DI = length
CPU_FREE	equ	02h	; DX:CX = address returned by CPU_ALLOC
CPU_MAP		equ	03h	; AL = SELF_*, DX:CX = address, SI:DI = length
CPU_UNMAP	equ	04h	; BX = selector, CX = # selectors (0 = 1)
CPU_QUERY	equ	05h	; BX = PMB #; stores PMB at ES:DI
CPU_ALIAS	equ	06h	; AL = SELF_*, BX = selector to alias
CPU_MAXFUNC	equ	06h

;
; CPU_GETINFO flags (AH)
;
CPUF_PM		equ	01h	; processor is in protected mode
CPUF_PMOK	equ	02h	; protected-mode self-test passed

;
; Selector flags (AL) for CPU_ALLOC, CPU_MAP, and CPU_ALIAS
;
; CPU_ALLOC and CPU_MAP return the first selector in AX; a block larger than
; 64K is mapped by consecutive selectors (each 8 more than the last), each
; covering the next 64K.  CPU_ALIAS returns a new selector for the same memory
; as an existing one (eg, a code selector for a block of generated code, or
; for a COM program's PSP block; see docs/bdtech/mmu), with its base address
; in DX:CX; CPU_UNMAP frees it.  It works on selectors in either mode (CPU$
; keeps its descriptor tables in real mode, too), but in real mode, a segment
; is its own alias, so callers that run in either mode should check CPUF_PM.
;
SELF_LDT	equ	01h	; LDT selector(s) (otherwise GDT)
SELF_CODE	equ	02h	; code (execute/read), not data (read/write)
SELF_NONE	equ	04h	; CPU_ALLOC only: no selector (AX = 0)
SELF_RDONLY	equ	08h	; read-only data (or execute-only code)
SELF_USER	equ	10h	; DPL 3, for programs (otherwise DPL 0)

;
; Physical Memory Block (PMB)
;
; The physical memory arena is a table of PMBs, in address order, describing
; all memory from address 0 to the end of extended memory; the last PMB has
; signature PMBSIG_LAST.  Unlike DOS MCBs, PMBs aren't stored in the memory
; they describe, so blocks need no header, and the arena can describe memory
; that isn't RAM (eg, adapter memory and ROMs).
;
PMB		struc
PMB_SIG		db	?	; 00h: PMBSIG_NEXT or PMBSIG_LAST
PMB_TYPE	db	?	; 01h: PMBTYPE_*
PMB_OWNER	dw	?	; 02h: owner (from CPU_ALLOC), or 0
PMB_ADDR	dd	?	; 04h: physical address
PMB_LEN		dd	?	; 08h: length, in bytes
PMB_SEL		dw	?	; 0Ch: first selector, if any
PMB_NSEL	dw	?	; 0Eh: number of selectors
PMB		ends

PMBSIG_NEXT	equ	'M'
PMBSIG_LAST	equ	'Z'

PMBTYPE_FREE	equ	0	; free extended memory
PMBTYPE_USED	equ	1	; allocated with CPU_ALLOC
PMBTYPE_DOS	equ	2	; conventional memory (managed with DOS MCBs)
PMBTYPE_SYS	equ	3	; CPU$ system area (descriptor tables and PMBs)
PMBTYPE_RSVD	equ	4	; not RAM (eg, video memory and ROMs)
