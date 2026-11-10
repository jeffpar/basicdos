;
; BASIC-DOS V86 Machine Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; On an 80386 in protected mode (CPU_TYPE 3), a V86 machine runs real-mode
; code in virtual-8086 mode, at ring 3, for a host program (eg, V86.COM) that
; provides the services the code asks for (eg, DOS).  The 80386 driver
; provides the machine (CPU_V86), and DOS gives it to programs (DOSUTIL
; MAPSEG with AL = 2 and 3):
;
;	CPU_V86 with AL = 0 creates a machine whose memory (SI:DI bytes,
;	rounded up to a multiple of 4K, at most 640K) starts at linear address
;	0, owned by BX (as for CPU_ALLOC); it returns the memory's first
;	selector in AX, which names the machine, and its address in DX:CX.
;	Its DPL 3 LDT selectors start every 32K, and each covers the 64K
;	there (or what remains), so anything smaller than 32K at linear
;	address L can be reached through selector AX + (L SHR 15) * 8.  The
;	machine also maps the ROMs (C0000h-FFFFFh, read-only) and wraps
;	the 64K above 1Mb to the first 64K, as an 8086 does; nothing else
;	(eg, video memory) is mapped.  Freeing the memory (or its owner
;	ending) frees the machine.
;
;	CPU_V86 with AL = 1 runs machine BX, with the registers in the V86REGS
;	at ES:DI, until it exits (see V86X_*), and then stores its registers
;	there; the IF bit in VR_EFL is the machine's own (CLI, STI, PUSHF,
;	POPF, and IRET use it, but it never stops interrupts).
;
; The machine's code can do anything an 8086 program can, except I/O and
; HLT: CLI, STI, PUSHF, POPF, and IRET work as they do in real mode, and an
; INT, or one of the exceptions that real mode delivers through the vectors
; (00h, 01h, 05h, 06h, and 07h), goes to the machine's own vector (at linear
; address 0), unless its handler's first byte is a HLT, in which case the
; machine exits (V86X_INT) with VR_EIP past the INT (or at the faulting
; instruction).  A host makes its default vectors point to HLTs (one for
; each vector), so that a hook's jump to the previous handler exits as a HLT
; (V86X_FAULT, vector 0Dh, with VR_EIP at the HLT and an interrupt frame on
; the machine's stack).
;
; Hardware interrupts go to the system's handlers, as they always do, so the
; machine gets none of its own; it exits after each timer tick (V86X_TICK),
; so that the host can check for CTRL-C (and DOS can switch sessions).
;
V86REGS		struc
VR_EDI		dd	?	; 00h: (in PUSHAD order)
VR_ESI		dd	?	; 04h
VR_EBP		dd	?	; 08h
		dd	?	; 0Ch: (ignored)
VR_EBX		dd	?	; 10h
VR_EDX		dd	?	; 14h
VR_ECX		dd	?	; 18h
VR_EAX		dd	?	; 1Ch
VR_VEC		dw	?	; 20h: exit's vector (see V86X_*)
VR_ERR		dd	?	; 22h: exit's error code (V86X_FAULT)
VR_EIP		dd	?	; 26h: (in the order an interrupt pushes them)
VR_CS		dd	?	; 2Ah
VR_EFL		dd	?	; 2Eh
VR_ESP		dd	?	; 32h
VR_SS		dd	?	; 36h
VR_ES		dd	?	; 3Ah
VR_DS		dd	?	; 3Eh
VR_FS		dd	?	; 42h
VR_GS		dd	?	; 46h
VR_DSSEL	dw	?	; 4Ah: exit's selector for VR_DS (see below)
VR_ESSEL	dw	?	; 4Ch: exit's selector for VR_ES
V86REGS		ends
;
; When the machine exits, VR_DSSEL and VR_ESSEL are selectors for 64K at its
; DS and ES (less any part beyond its memory), so that the host can pass its
; pointers to DOS; they stay the same until the next exit.
;
V86X_TICK	equ	0	; a timer tick (VR_VEC = 08h)
V86X_INT	equ	1	; an INT to a default vector (VR_VEC = vector)
V86X_FAULT	equ	2	; an exception (VR_VEC = vector, VR_ERR = code)
