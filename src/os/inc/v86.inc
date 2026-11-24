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
;	selector in AX, which names the machine.  Its DPL 3 LDT selectors
;	start every 32K, and each covers the 64K there (or what remains), so
;	anything smaller than 32K at linear address L can be reached through
;	selector AX + (L SHR 15) * 8.  The machine also maps the ROMs
;	(C0000h-FFFFFh, read-only) and wraps the 64K above 1Mb to the first
;	64K, as an 8086 does.  If DX is a console's video memory selector (from
;	IOCTL_GETMODE with CL = 1), the machine has that memory, too, at the
;	start of its frame (eg, a console's text page at B8000h, as page 0
;	would be), and DX returns that segment (otherwise, DX is zero, and
;	nothing else is mapped); it's there while the selector is present, and
;	while it isn't, a machine that touches it waits (see SELID_WAIT).  The
;	machine's video memory follows the selector's (eg, to A0000h, when the
;	console sets one of an EGA or VGA's graphics modes), and while it's
;	below B0000h, which means that the console has the screen to itself,
;	the machine's code can use the video ports (3C0h-3DFh) as well.
;	Freeing the memory (or its owner ending) frees the machine.
;
;	CPU_V86 with AL = 1 runs machine BX, with the registers in the V86REGS
;	at ES:DI, until it exits (see V86X_*), and then stores its registers
;	there; the IF bit in VR_EFL is the machine's own (CLI, STI, PUSHF,
;	POPF, and IRET use it, but it never stops interrupts).
;
;	CPU_V86 with AL = 4 lends ports CX through CX + DX - 1 to machine
;	BX, so that its code uses them itself, and AL = 5 takes them back
;	(CX and DX must be multiples of 8, and the ports below the video
;	ports); only a driver that owns the device should (eg, SND$).  With
;	AL = 4, ES:DI -> a far function of the driver's (or 0:0), which is
;	called (with interrupts off, AL = 0) when the machine is suspended,
;	and again (AL = 1) when it resumes.
;
;	A machine that has the video ports is suspended while its video
;	memory selector isn't present (eg, while VKD$ has its console's
;	state saved elsewhere): it doesn't run at all until the selector is
;	present again (or the wait ends early, eg, for a CTRLC, and it exits
;	with V86X_TICK and VR_VEC = 0Eh).
;
;	CPU_V86 with AL = 2 copies the registers of the machine that ran
;	last to the V86REGS at ES:DI, and AL = 3 copies them back (only the
;	flags that the machine can change do), for a debugger that stopped
;	the machine's hardware interrupt in its handler (see CPU_SYSREGS),
;	where the machine resumes when the handler returns; at any other time,
;	they aren't the machine's current registers.  With AL = 3, a nonzero
;	VR_VEC sends the machine's single-step traps and INT 3s to the
;	system's INT 01h and 03h handlers (the debugger's) instead of its own
;	vectors, the same way, until another AL = 3 with VR_VEC zero.
;
; A flat machine runs 32-bit code instead, at ring 3, in protected mode, in a
; linear address space of its own (every address below C0000000h, where the
; system's begin), with only the memory that it's been given, which starts at
; linear address 10000h, so that a null pointer faults.  DOS runs LE programs
; in them (see load_le), and gives them to their host through DOSUTIL MAPSEG
; with AL = 4 and 5 (CPU_V86 with AL = 7 and 8):
;
;	CPU_V86 with AL = 6 creates a flat machine with SI:DI bytes of memory
;	(rounded up to a multiple of 4K), owned by BX, and returns the machine
;	in AX and its memory's linear address in DX:CX.  The machine is the
;	first of five consecutive LDT selectors: one that only CPU$ uses, two
;	for its host (as in VR_DSSEL and VR_ESSEL), and its code and data
;	selectors (32-bit, with base 0), which are the only CS and SS that
;	it ever runs with.  Its owner ending frees it.
;
;	CPU_V86 with AL = 7 points one of machine BX's two selectors for its
;	host (SI = 0 for VR_DSSEL, or 1 for VR_ESSEL) at linear address DX:CX,
;	and returns the selector in AX and its limit in CX: it covers as many
;	of the bytes there as are in consecutive physical pages, up to 64K
;	(DOS and the drivers use it with the system's page tables, so a
;	transfer must not go beyond it); an address with no memory is an error.
;
;	CPU_V86 with AL = 8 adds SI:DI bytes (rounded up to a multiple of 4K)
;	to the end of machine BX's memory, and returns their linear address in
;	DX:CX; the memory isn't zeroed (DOSUTIL MAPSEG zeroes it).
;
;	CPU_V86 with AL = 1 runs a flat machine, too, with VR_CS and VR_SS
;	ignored, and the VR_DS, VR_ES, VR_FS, and VR_GS that ring 3 could load
;	(any other becomes zero).  An INT exits (V86X_INT, with VR_EIP past
;	it), a hardware interrupt exits after the system's handler (V86X_TICK),
;	and anything else is a fault (V86X_FAULT, with VR_EIP at the
;	instruction): it has no ports, no vectors of its own, and IOPL 0.
;	An INT 3 doesn't exit: the system's INT 03h handler gets it (eg, a
;	debugger's, which AL = 2 and 3 give the machine's registers), with
;	VR_VEC = 03h, and so does a single-step trap after AL = 3 with a
;	nonzero VR_VEC, and then the machine runs again.  That handler gets
;	a fault, too, before the exit (with the fault's VR_VEC and VR_ERR),
;	as it does an INT 3 that follows a NOP (a failed assertion, which
;	then exits as a fault with VR_VEC = 03h); if it calls AL = 3, the
;	machine runs again instead (eg, after a debugger's G).
;
; The machine's code can do anything an 8086 program can, except HLT, and
; I/O, which exits (V86X_IO), so that the host can do something like it (the
; only ports that the machine ever uses itself are the video ports, as
; above, and any that a driver lent it, and CPU$ does the interrupt
; controller's, 20h and 21h, which read zero, and the game port's, 201h,
; which reads FFh, without an exit): VR_EIP is past the IN or OUT, the low
; word of VR_ERR is the port, and the high word is the opcode (bit 0 is set
; for a word, bit 1 for OUT).  String I/O (and I/O of a dword) is a fault.
; CLI, STI, PUSHF, POPF, and IRET work as they do in real mode, and an
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
; machine gets none of its own; it exits after each one (V86X_TICK, with
; VR_VEC = the interrupt's real-mode vector, eg, 08h for a timer tick), so
; that DOS can switch sessions, and the host can give the machine an
; interrupt of its own (eg, by pushing an interrupt frame on its stack, and
; running it at its INT 08h or 1Ch handler, or for an interrupt that a driver
; counted for it, its handler for that one), and the same way when its wait
; for its video memory ends early (eg, for a CTRLC, with VR_VEC = 0Eh).
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
V86X_IO		equ	3	; an IN or OUT (VR_ERR = port and opcode)
