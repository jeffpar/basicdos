;
; BASIC-DOS 80386 Processor (CPU$) Driver Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The system area, SYSVARS, descriptor, and selector definitions that the
; 80386 driver's modules (386dev.asm and 386v86.asm) share.
;
;
; The system area is the last whole 64K of conventional memory, which is
; addressable in real mode with segment sys_seg and in protected mode with
; selector SEL_SYS (whose base is sys_seg * 16), so the same offsets work in
; both modes.
;
; The GDT starts after that, with GDT_MAX entries that CPU$ allocates from,
; but its limit extends to the "identity" selectors (A000h to F800h, every
; 800h), whose bases are their values times 16, so the ROM BIOS can use its
; own segments (eg, F000h and B800h) in protected mode; everything else in
; the system area fits between the first part of the GDT and A000h.
;
SYS_VARS	equ	0020h
SYS_GDT		equ	00E0h
GDT_MAX		equ	256
SYS_PIDT	equ	SYS_GDT + GDT_MAX * 8
IDT_MAX		equ	256
;
; The TSS is only for its ring 0 stack (SS0:SP0; see CPU_SETSTACK), which the
; processor switches to when an interrupt takes ring 3 code to ring 0; we
; never switch tasks, so the rest of it stays zero.  It has room for the
; 80386 format, which we use on an 80386 (see SV_TYPE), with an I/O map base
; (TSS_IOMAP) beyond its limit, so that it has no I/O permission bitmap, and
; every I/O instruction at ring 3 (with IOPL 0) faults, as on an 80286.
; SV_TSSSP0 is the offset of SP0 (2, or ESP0 at 4), which is also how much
; further SS0 is (at 4 or 8).
;
SYS_TSS		equ	SYS_PIDT + IDT_MAX * 8
TSS_IOMAP	equ	66h	; 80386: I/O map base
TSS_LEN		equ	104	; (an 80286 TSS needs only 44)
SEL_VIDEO	equ	0A000h	; first identity selector (data)
;
; The rest is a pool for the PMB table and the LDTs: the table grows up from
; the bottom as blocks are added (see pmb_dup), and with programs at ring 3,
; each session uses one of LDT_SESSIONS LDTs (see CPU_SETLDT), which DOS
; assigns, so that its programs' selectors (MEMF_LDT) can't name the memory of
; a session with another LDT.  The LDTs are packed down from the top, with LDT
; 0 first; each one starts empty, and grows as needed (see ldt_grow), up to
; LDT_LIMIT descriptors, which is all that fits in an owner ID (see
; enc_owner).  SV_LDTS has each LDT's offset, so each one ends at the offset
; of the LDT before it; the active LDT's offset is also in SV_LDT, and its
; limit is in the LDTR's descriptor (SEL_LDTD).
;
; Since the GDT's limit covers everything up to the identity selectors, the
; processor can also read the pool as descriptors, through selectors below
; A000h, each of whose access bytes is at an offset of 5 mod 8.  So the PMBs
; and LDTs must start at an offset of 6 mod 8 (and everything in them moves by
; multiples of 8), which puts those access bytes on byte 7 of every 8 bytes of
; a table, none of which ever has its present bit set: the top of a
; descriptor's base; and in a PMB, the top of PMB_ADDR, the high byte of
; PMB_NSEL, a reserved byte, and the last byte of PMB_NAME (see ddcpu_setblk).
; Otherwise, a ring 3 program could load another LDT's descriptors, or a PMB,
; as its own.
;
SYS_PMBS	equ	((SYS_TSS + TSS_LEN + 1) OR 7) - 1 ; (the next 6 mod 8)
SYS_LDTTOP	equ	SYS_GDT + SEL_VIDEO - 2
LDT_SESSIONS	equ	32	; LDTs (one for each session, at most)
LDT_STEP	equ	32	; descriptors to add at a time
LDT_LIMIT	equ	256	; descriptors per LDT
	ASSERT	<(SYS_PMBS AND 7)>,EQ,6
	ASSERT	<(SYS_LDTTOP AND 7)>,EQ,6
	ASSERT	<(PMB_NSEL AND 7)>,EQ,6
	ASSERT	<((PMB_NAME + size PMB_NAME) AND 7)>,EQ,0
SEL_ROM		equ	0C000h	; first identity code selector
SEL_IDSTEP	equ	0800h	; identity selectors are every 800h
GDT_LIMIT	equ	0F807h	; (through the last identity selector)

;
; SYSVARS is at SYS_VARS in the system area, and the PMB table at SYS_PMBS.
;
SYSVARS		struc
SV_TYPE		db	?	; CPU type
SV_FLAGS	db	?	; CPUF_* flags
SV_NPMBS	dw	?	; number of PMBs
SV_ARG		db	?	; CPU_ALLOC: MEMF_* flags
SV_LDTNUM	db	?	; active LDT # (see CPU_SETLDT)
SV_OWNER	dw	?	; CPU_ALLOC: owner
SV_LEN		dd	?	; CPU_ALLOC, CPU_REALLOC, CPU_MOVE: length
SV_SRC		dd	?	; CPU_MOVE: source
SV_DST		dd	?	; CPU_MOVE: destination
SV_RMSP		dw	?	; real-mode SP (while in protected mode)
SV_RMSS		dw	?	; real-mode SS (while in protected mode)
SV_RMCS		dw	?	; real-mode CS (ie, the CPU$ segment)
SV_GDTR		dw	3 dup (?) ; GDT limit and base (for LGDT)
SV_PIDTR	dw	3 dup (?) ; protected mode's IDT limit and base
SV_RMIDTR	dw	3 dup (?) ; real-mode IDT limit and base
SV_FAULT	dd	?	; fault handler (see CPU_SETFAULT and to_fault)
SV_TSSSP0	dw	?	; offset of SP0 in the TSS (see SYS_TSS)
SV_PDIR		dd	?	; 80386: page directory (see LIN_HI)
SV_LINHI	db	?	; 80386: base bits 31-24 to add (see LIN_HI)
SV_NPT		db	?	; 80386: number of page tables
SV_V86IDTR	dw	3 dup (?) ; 80386: V86 mode's IDT (see 386v86.asm)
SV_V86SEL	dw	?	; 80386: its two GDT selectors (or 0 if none)
SV_LDT		dw	?	; active LDT's offset (see CPU_SETLDT)
SV_LDTTOP	dw	?	; the end of LDT 0 (see ldt_grow)
SV_LDTS		dw	LDT_SESSIONS dup (?) ; each LDT's offset
SYSVARS		ends
SV_LDTLOW	equ	SV_LDTS + (LDT_SESSIONS - 1) * 2 ; (the lowest LDT)
	ASSERT	<SYS_VARS + size SYSVARS>,LE,SYS_GDT

;
; Descriptors (gates use DESC_LIMIT for the offset, DESC_BASE for the
; selector, and DESC_BASE16 for the parameter count)
;
DESC		struc
DESC_LIMIT	dw	?	; limit (bits 15-0)
DESC_BASE	dw	?	; base (bits 15-0)
DESC_BASE16	db	?	; base (bits 23-16)
DESC_ACC	db	?	; access rights (ACC_*), or zero if free
DESC_EXT	dw	?	; 80386: limit (19-16), flags, base (31-24)
DESC		ends

ACC_DATA	equ	92h	; present, DPL 0, read/write data
ACC_CODE	equ	9Ah	; present, DPL 0, execute/read code
ACC_RW		equ	02h	; writable data (or readable code)
ACC_CONFORM	equ	04h	; conforming code (added to ACC_CODE)
ACC_PRESENT	equ	80h	; present (in every ACC_* value but ACC_DPL3)
ACC_DPL3	equ	60h	; DPL 3 (added to another ACC_* value)
ACC_LDT		equ	82h	; present, LDT
ACC_CALLGATE	equ	84h	; present, DPL 0, 80286 call gate
ACC_INTGATE	equ	86h	; present, DPL 0, 80286 interrupt gate
ACC_TSS		equ	81h	; present, DPL 0, available 80286 TSS
ACC_TSS386	equ	89h	; present, DPL 0, available 80386 TSS
ACC_INTG386	equ	8Eh	; present, DPL 0, 80386 interrupt gate
EXT_LIMIT	equ	0Fh	; DESC_EXT: limit bits 19-16
EXT_KEEP	equ	50h	; DESC_EXT: the AVL and D/B bits
EXT_GRAN	equ	80h	; DESC_EXT: 4K granularity
;
; On an 80386, protected mode has paging, and maps all of physical memory at
; linear address C0000000h (LIN_HI is its bits 31-24), so the lower linear
; addresses are free for other mappings.  Every descriptor that we create
; (or that ddcpu_init made before switching) has that much added to its base
; (see SV_LINHI), so the selectors for any memory (eg, the identity selectors
; for the ROMs) work as before, and the addresses that we report (and accept)
; are still physical (see desc_addr).  The page directory and the page
; tables (one for every 4Mb) are just below the system area (see SV_PDIR),
; and every page is user-accessible, since segment limits protect memory.
; Until the switch (see pm_pmode), the low linear addresses map physical
; memory, too, as they must for the instruction that turns paging on.
;
LIN_HI		equ	0C0h	; linear map of physical memory: base bits 31-24
PDE_KERNEL	equ	LIN_HI * 4 * 4	; offset of its first PDE (C0000000h)
PG_USER		equ	07h	; PDE and PTE bits: present, writable, user
PG_ROM		equ	05h	; PTE bits: present, read-only, user
PG_SIZE		equ	4096

SEL_TI		equ	04h	; table indicator (set for LDT selectors)
;
; Protected mode's vectors for the slave and master PICs (see pm_pmode).
;
IRQ_SLAVE	equ	70h	; IRQs 8-15
IRQ_MASTER	equ	78h	; IRQs 0-7
;
; Fixed GDT selectors; SEL_BIOS and SEL_DDINT are the same values as the
; BIOS and DDINT segments, so code that uses those works in either mode.
;
SEL_SYS		equ	08h	; data: system area
SEL_LDTD	equ	10h	; LDT
SEL_CPUCODE	equ	18h	; code: CPU$ driver
SEL_LOW		equ	20h	; data: first 64K of memory
SEL_STACK	equ	28h	; data: caller's stack (see pm_call)
SEL_TMP		equ	30h	; data: scratch
SEL_CPU		equ	38h	; call gate: cpu_entry
SEL_BIOS	equ	40h	; data: segment 40h (BIOS)
SEL_TMP2	equ	48h	; data: scratch (see pm_ptr)
SEL_DDINT	equ	50h	; code: segment 50h (DDINT)
SEL_C5CODE	equ	58h	; code: the CALL 5 jump (0:00C0h)
;		equ	60h	; SEL_CALL5 (in cpu.inc): call gate to it
SEL_TSS		equ	68h	; TSS (see CPU_SETSTACK)
GDT_FIXED	equ	0Eh	; number of fixed GDT entries
