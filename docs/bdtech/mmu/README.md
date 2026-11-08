---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Protected Mode and Memory Management
permalink: /docs/bdtech/mmu/
---

{% include header.html %}

BASIC-DOS manages all memory, on every processor, through a built-in driver, **CPU$**, which is also the only part of BASIC-DOS that knows about descriptors, selectors, and physical memory.  CPU$ loads first and determines the processor type, and on a processor that can use protected mode, it manages a table of physical memory blocks covering conventional and extended memory, along with the GDT, the IDT, and the LDTs that sessions use (see [The CPU$ Drivers](#cpu)).

On an 80286 or later, when protected mode is requested (by a `CPU=80286` or `CPU=80386` line in CONFIG.SYS, or **P** at the boot message), BASIC-DOS switches to protected mode while its drivers initialize, and stays there (see [Protected-Mode Initialization](#pminit)): CPU$, the drivers, and the kernel run at ring 0, and COMMAND.COM, its BASIC programs, and the programs it runs run at ring 3, with each console's sessions' memory in an LDT of their own (see [Running Programs at Ring 3](#ring3)), and DOS allocates memory from anywhere in conventional or extended memory.  Otherwise, as on an 8086 or 8088, the same binaries run in real mode, BASIC-DOS's default and most compatible mode, where CPU$ manages memory with a chain of MCBs, as DOS always has, and uses no extra memory (see [Mode-Independent Code](#modeless)).

The [Protected Mode demo](/demos/mmu/) boots in protected mode on a 2Mb PC AT (see [The Protected Mode Demo](#pmdemo)).  What doesn't work in protected mode yet (most notably, MZ EXE files) is listed under [Limitations](#limits).

### Supported Machines {#machines}

Protected mode needs an 80286 or later, at least 256K of conventional memory (after any `MEMSIZE=` line), and A20 control through the 8042 keyboard controller, as on a PC AT; otherwise (or without a request for it; see [CPU](../../bdman/cfg/#cpu)), BASIC-DOS runs in real mode.  Extended memory is a bonus: it adds to the memory that DOS can allocate.

Protected mode is built and tested for the IBM PC AT (80286, with IBM's revision 3 BIOS), typically with 2Mb of memory: 640K of conventional memory and 1408K of extended memory.  An 80386 runs the same code, with 80286-format descriptors; it's tested only occasionally, on a COMPAQ DeskPro 386.  So every configuration that boots on a PC AT or DeskPro 386 runs in real mode, the default, except for the Protected Mode demo and the protected-mode tests, which have a `CPU=80286` line in their CONFIG.SYS, and which `tools/tests/mmutest.sh` runs on four machines: a PC XT, a PC AT in real mode, and a PC AT in protected mode, both with `RING=0` and without it.

### The CPU$ Drivers {#cpu}

BASDEV.COM starts with two CPU$ drivers, of which exactly one stays loaded: the 80286 driver, followed by the 8086 driver.  The 80286 driver, which is initialized first, determines the processor type:

1. An 8086 or 80186 decrements SP before PUSH SP stores it, whereas an 80286 or later stores the original value.
2. An 80186 masks shift counts to 5 bits, so shifting 1 left 33 times leaves 2 (instead of 0 on an 8086).
3. In real mode, an 80286 always clears FLAGS bits 12-15, whereas an 80386 lets software set bits 12-14 (IOPL and NT).

It stores the result in CPU_HWTYPE (0:513h) and CPU_TYPE (0:512h), as one of the CPUTYPE_* values in cpu.inc (0 = 8086/8088, 1 = 80186/80188, 2 = 80286, 3 = 80386 or later).  No request for protected mode (a `CPU=80286` or `CPU=80386` line in CONFIG.SYS, or **P** at the boot message, either of which **R** at the boot message overrides), or less than 256K of conventional memory (after any `MEMSIZE=` line, which the 80286 driver applies by lowering the BIOS's memory size), makes CPU$ store 0 in CPU_TYPE and act as it does on an 8088, without enabling A20, and so does any later reason not to stay (no A20 control, or a failed test of protected mode); CPU_HWTYPE is still the processor's own type, for software that must know how the processor runs instructions (eg, DEBUG.COM's disassembler).

- **The 80286 driver** stays if the processor is an 80286 or later, with the memory and A20 control that protected mode needs (see [Supported Machines](#machines)), and a switch to protected mode and back succeeds.  It enables A20 permanently, and builds its [arena](#arena) (a table of PMBs) and descriptor tables in the 64K [system area](#sysarea).
- **The 8086 driver** stays otherwise.  It manages memory with a chain of MCBs, as DOS always has, so every block that's allocated after it (eg, the other drivers, the kernel, and programs) has an MCB in the paragraph before it, which programs that walk the MCB chain can see.

Neither can be skipped (devinit ignores `SKIP=CPU$`), and whichever stays is at 0970h.  It provides its functions through DDINT_CPU (0050:0030h), a far jump in low memory like the other DDINT entry points, which fails (with carry set) until CPU$ initializes.  It also provides DDINT_GETVEC and DDINT_SETVEC (see [Device Drivers](../dev/)), which read and write the real-mode vector table, or in protected mode, CPU$'s IDT.

#### Functions {#functions}

Call DDINT_CPU with a function number in AH.  Physical addresses and lengths are 32-bit byte values: addresses in DX:CX and lengths in SI:DI (high:low).  Every function runs with interrupts disabled, preserves BX, SI, DI, BP, DS, and ES, and returns carry clear on success, or carry set with an error code in AX.

| AH | Function | Inputs | Outputs |
|----|----------|--------|---------|
| 00h | CPU_GETINFO | | AL = CPU type, AH = CPUF_* flags (bits 6-7 = CPU_HWTYPE), DX:CX = length of largest free block |
| 01h | CPU_ALLOC | AL = MEMF_* flags, BX = owner (see [Owner IDs](#owners)), SI:DI = length | AX = first selector (0 if MEMF_NONE), DX:CX = address |
| 02h | CPU_FREE | DX:CX = block | |
| 03h | CPU_MAP | AL = MEMF_* flags, DX:CX = address, SI:DI = length (with MEMF_REMAP, BX = selector ID) | AX = first selector, CX = number of selectors, and with MEMF_LDT, DX = the selector's ID (see [Selector IDs](#selids)) |
| 04h | CPU_UNMAP | BX = first selector, CX = number of selectors (0 = 1), or BX = selector ID | |
| 05h | CPU_QUERY | BX = PMB number (0 = first), or -1 for block DX:CX; ES:DI -> 32-byte buffer | PMB copied to ES:DI |
| 06h | CPU_ALIAS | AL = MEMF_* flags, BX = selector | AX = new selector, DX:CX = base address |
| 07h | CPU_PMODE | (none) | Protected mode, for good: CS, DS, ES, and SS are now selectors for the same memory, and AX = a data selector for the caller's CS (see [Protected-Mode Initialization](#pminit)) |
| 08h | CPU_REALLOC | DX:CX = block, SI:DI = new length | |
| 09h | CPU_MOVE | ES:BX -> MOVEPKT (source address, destination address, and length, all dwords) | |
| 0Ah | CPU_SETBLK | DX:CX = block, AL = MCBTYPE_*, BX = owner (non-zero), ES:SI -> 8-character name (SI = 0 for none) | |
| 0Bh | CPU_FREEALL | BX = owner (see [Owner IDs](#owners)) | |
| 0Ch | CPU_SETLIM | BX = selector, SI:DI = new length (1 to 64K) | |
| 0Dh | CPU_SEGINFO | AL = ADDR_* flags, BX = selector (or segment) | DX:CX = base address, AX = limit (or with ADDR_RIGHTS, AL = access rights, AH = extended byte) |
| 0Eh | CPU_RWMEM | AL = ADDR_* flags, BX:SI = address, CX = length, ES:DI -> buffer | |
| 0Fh | CPU_SYSREGS | ES:DI -> 12-byte buffer | GDTR and IDTR stored at ES:DI; AX = MSW, CX = LDTR, DX = TR |
| 10h | CPU_SETFAULT | DX:CX = fault handler (0:0 for none) | DX:CX = previous handler |
| 11h | CPU_SETSTACK | DX:CX = ring 0 stack (SS:SP) | DX:CX = previous ring 0 stack |
| 12h | CPU_SETLDT | AL = LDT number | |

Every function works the same way in either driver and in either mode, so callers needn't check which is which: in real mode, CPU_ALLOC, CPU_MAP, and CPU_ALIAS return the memory's segment instead of a selector (CPU_ALLOC returns 0 for a block above 1Mb, and CPU_MAP needs memory below 1Mb that's paragraph-aligned), a segment is its own alias, and CPU_UNMAP has nothing to do.  Errors are ERR_INVALID (eg, a bad function, a zero length, or a selector that isn't in use), ERR_NOMEMORY (no block big enough, with DX:CX = the length of the largest free block; or no free PMB or descriptors), and ERR_BADADDR (a block that CPU_ALLOC didn't return).

- **Blocks**: a *block* (DX:CX) is the address that CPU_ALLOC returned, or DX = -1 and CX = the selector (or segment) that it returned, which is what DOS has (eg, in ES for DOS_MEM_FREE).  CPU_ALLOC rounds lengths up to a multiple of 16, so every block starts on a paragraph boundary, and a block of more than 64K gets one selector for every 64K (each 8 more than the last).  CPU_REALLOC shrinks a block, or grows it into the free block after it; its first selector and code alias stay the same, but its selectors always fit its new length (it gets or loses one for every 64K, so growing past a multiple of 64K needs free descriptors after its last selector), and CPU_MOVE copies memory between any two physical addresses (below 1Mb, in real mode), even if they overlap.  CPU_SETBLK records a block's owner, type, and name for DOS (as an MCB does), which MEM and DEBUG's DM show, and CPU_FREEALL frees every block an owner has (DOS uses it when a program ends).
- **Owner IDs**{: #owners}: an owner is a PSP (or a driver's segment, or MCBOWNER_SYSTEM), which the 80286 driver stores as an *owner ID* (PMB_OWNER).  In protected mode, a ring 3 program's PSP is an LDT selector, which a program with another LDT can share (see [Ring 3](#ring3)), so its ID is 80h plus its LDT number in the high byte and its LDT index in the low byte (eg, 8000h for session 0's COMMAND.COM, whose PSP is selector 0007h, and 8100h for session 1's, if session 1 has LDT 1), which is unique, and above MCBOWNER_SYSTEM, like a PSP segment; any other owner is its own ID.  CPU_QUERY returns the IDs (eg, to MEM and DEBUG's DM, which display them), and CPU_FREEALL takes an owner, as CPU_ALLOC and CPU_SETBLK do.  DOS compares a block's owner with a program's ID, which it gets from the program's own block (every PSP block owns itself), when it needs to know whether the program owns the block (eg, for a fault in the program's code, or FRE(-1); see DOS_UTL_QRYMEM).
- **Memory flags**: MEMF_LDT (01h) requests LDT selectors instead of GDT selectors, MEMF_CODE (02h) code segments instead of data segments, MEMF_NONE (04h) a block without any selectors (for CPU_MAP and CPU_ALIAS, the same bit is MEMF_CONFORM, which makes conforming code, which code at any ring can call, and which runs at the caller's ring, as FPU$'s functions do), MEMF_RDONLY (08h) read-only data (or execute-only code), and MEMF_USER (10h) DPL 3 selectors, for programs at ring 3.  CPU_MAP also takes MEMF_REMAP (80h; see [Selector IDs](#selids)).  CPU_ALLOC also takes MEMF_LOW (20h) to allocate below 1Mb, MEMF_HIGH (40h) to allocate from the top of the last free block that's big enough, and MEMF_AT (80h) to allocate the memory at DX:CX; otherwise, it allocates from the first free block that's big enough, conventional or extended.
- **Selectors**: CPU_MAP maps existing memory, CPU_ALIAS creates another selector for the same memory as an existing one, with different access rights (see [Code Aliases](#aliases)), CPU_UNMAP frees either, and CPU_SETLIM changes the length that a selector covers, keeping the selector.
- **Selector IDs**{: #selids}: CPU_MAP with MEMF_LDT returns its selector's ID in DX, in the same form as an [owner ID](#owners) (80h plus the LDT number, and the LDT index), which names the selector in any LDT, so that a driver can change what it maps later, from any session: CPU_MAP with MEMF_REMAP and BX = the ID gives it a new address and length (64K or less), or with a length of zero, makes it not present, and CPU_UNMAP with BX = the ID frees it.  A program that loads a not-present selector (or that DOS resumes with one in DS or ES) waits, as if for DOS_UTL_WAIT with wait ID SELID_WAIT (FFFFh):ID, so the driver ends that wait with DOS_UTL_ENDWAIT (once for each waiting session, until it returns carry) when the selector is present again, and the program retries the instruction.  A segment register that already holds the selector keeps what it had until it's loaded again, so a driver changes a selector only while the sessions that use it aren't running (eg, during another session's DOS call); VKD$ uses these for video memory (see [Video Memory](#video)).
- **Debuggers**: CPU_SEGINFO, CPU_RWMEM, and CPU_SYSREGS never change CPU$'s state, so they work even when CPU$ itself was interrupted.  An address is in real-mode form unless ADDR_SEL (01h) says its segment is a protected-mode selector (in either mode) or ADDR_PHYS (04h) says it's a physical address (its "segment" holds bits 16-31), or in protected mode, ADDR_LDT (10h) says that its "segment" is an LDT number, and the segment is that LDT (so that DEBUG's DL command can find any session's, although the GDT describes only the active one).  CPU_SEGINFO returns a segment's base address and limit, or with ADDR_RIGHTS (08h), its descriptor's access rights and extended byte.  CPU_RWMEM copies CX bytes from the address to ES:DI, or with ADDR_WRITE (02h), from ES:DI to the address, which must be within the segment's limit; it can write to a code segment (eg, to store a breakpoint).  CPU_SYSREGS stores the GDTR and IDTR (as SGDT and SIDT do), and returns the MSW, LDTR, and TR; the 8086 driver returns ERR_INVALID, which tells a debugger that the processor has only one mode.
- **Faults**: CPU_SETFAULT gives a fatal protected-mode exception to a handler (eg, the kernel's, or a debugger's), before CPU$ reports it and stops the machine.  The handler is entered with the registers as they were, interrupts disabled, and SS:SP pointing to a far return address, the vector, the error code, and an interrupt frame for the faulting instruction.  A handler that can't handle the exception declines it by returning (RETF) with the registers and stack as they were.  Before stopping the machine, CPU$ offers the halt to the handler, as the same exception with FAULT_HALTED (80h) in the vector's high byte: a debugger can accept it by never returning, and any other handler declines it.  See [Faults](#faults).
- **Ring 3 support**: CPU_SETSTACK sets the ring 0 stack that the processor switches to when an interrupt or exception takes ring 3 code to ring 0, and CPU_SETLDT makes one of its 32 LDTs the active one, so that the selectors that the other functions allocate, free, and resolve are in that LDT, which DOS assigns to one or more sessions (see [Running Programs at Ring 3](#ring3)).  In real mode, CPU_SETSTACK returns ERR_INVALID, and CPU_SETLDT does nothing.

CPU_GETINFO's flags are CPUF_PM (01h), set when the processor is in protected mode, CPUF_PMOK (02h), set when the 80286 driver stayed (so CPU_PMODE is available), and CPUF_HWTYPE (C0h), the processor's own type (CPU_HWTYPE), which AL (CPU_TYPE) understates in real mode.

DDINT_CPU is the entry point in either mode, since a far call through segment 50h has the same address in protected mode (see [Mode-Independent Code](#modeless)), and it doesn't use up an interrupt vector.  In protected mode, segment 50h is a DPL 0 code segment, so only ring 0 code (the drivers, the kernel, and programs run with `RING=0`) can call CPU$; programs at ring 3 use DOS functions instead (eg, DOS_MEM_ALLOC, DOS_UTL_ALIAS, and DOS_UTL_MAPSEG).

### Memory Map

Physical memory on a 2Mb PC AT:

| Address | Length | PMB type | Contents |
|---------|--------|----------|----------|
| 000000h | 1K | USED | Real-mode interrupt vector table |
| 000400h | 256 | USED | ROM BIOS data area (segment 40h) |
| 000500h | 1136 | USED | BASIC-DOS low memory (also segment 40h, from offset 100h): CPU_TYPE (512h), CPU_HWTYPE (513h), CPU_ARENA (514h), the diskette parameter table (522h), the DDINT entry points (530h, called through segment 50h, starting with DDINT_CPU at 0050:0030h), and two disk buffers |
| 000970h | | USED | Drivers: CPU$ (first), NUL, VKD$, ..., then BASDOS.COM and its tables |
| | | FREE | The rest of conventional memory, except for: |
| 090000h | 64K | SYS | CPU$ system area (see below) |
| 0A0000h | 384K | RSVD | Video memory, adapter ROMs, and the system ROM (not RAM) |
| 100000h | 1408K | FREE | Extended memory, if any |
| 260000h | | | End of memory |

The PMB types (PMBTYPE_* in cpu.inc) are FREE (0), USED (1, allocated by CPU_ALLOC), SYS (2), and RSVD (3).  The end of conventional memory comes from the BIOS, so a machine with less than 640K (or a `MEMSIZE=` line) has a larger RSVD block.

#### The System Area {#sysarea}

CPU$ keeps its data in the last whole 64K of conventional memory (090000h-09FFFFh, with 640K), which is addressable in real mode with a segment (9000h, with 640K), and in protected mode with a selector whose base is the same address, so the same offsets work in both modes:

| Offset | Contents |
|--------|----------|
| 0000h | Unused (except by the protected-mode test) |
| 0020h | CPU$'s variables |
| 00E0h | GDT: 256 descriptors (the fixed ones first) |
| 08E0h | The protected-mode IDT (256 gates; see [Protected-Mode Interrupts](#interrupts)) |
| 10E0h | TSS (44 bytes, 80286 format), only for its ring 0 stack |
| 110Eh | PMB table (32 bytes per entry), growing up, and below A0DEh, LDTs, growing down (see [Table Growth](#growth)) |
| A0E0h | GDT: identity selectors A000h-F800h, every 800h (see below), through offset F8E7h |

A PSP's CALL 5 uses PSP_FCSEG, which in protected mode is SEL_CALL5, a DPL 3 call gate to the far jump at 0:00C0h (a far call through a gate ignores its offset, so PSP_SIZE keeps the value that CP/M programs read as their memory size).

#### Table Growth {#growth}

The PMB table and the LDTs share the 36,816 bytes between the TSS and the identity selectors.  The PMB table starts at the bottom and is only as long as the blocks it describes, and the LDTs are packed down from the top, with LDT 0 first.  Each LDT starts empty, and grows 32 descriptors at a time, up to 256 (all that fits in an [owner ID](#owners)).  Moving an LDT doesn't change any selectors, since they're indexes.  Allocating fails with ERR_NOMEMORY only when the PMB table and the LDTs would meet, or an LDT has all 256 descriptors.  An LDT keeps its largest size until the system restarts.

So that long tables don't delay interrupts, the CPU$ functions that walk or change them (CPU_GETINFO, CPU_ALLOC, CPU_FREE, CPU_MAP, CPU_QUERY, CPU_ALIAS, CPU_REALLOC, CPU_SETBLK, and CPU_FREEALL) run with interrupts on if the caller had them on, holding a session lock (through DDINT_UTIL), so no other session can call CPU$ until they're done.  Interrupts are off only while moving a piece of the PMB table (64 words at a time), and while moving the active LDT and reloading the LDTR, which is never more than 1K words.  Interrupt handlers must not call those functions.

#### Fixed GDT Selectors

| Selector | Base | Use |
|----------|------|-----|
| 00h | | Null selector |
| 08h | System area | Data: the system area (so offsets match its real-mode segment) |
| 10h | | The active LDT |
| 18h | 000970h | Code: CPU$ |
| 20h | 000000h | Data: the first 64K (interrupt vectors, BIOS data, BASIC-DOS low memory) |
| 28h | | Data: the caller's stack, while switching modes |
| 30h, 48h | | Data: scratch |
| 38h | | Call gate (DPL 0) to CPU$'s functions (unused, since DDINT_CPU works in either mode) |
| 40h | 000400h | Data: the BIOS segment (40h), so code that uses segment 40h works in either mode |
| 50h | 000500h | Code: the DDINT segment (50h), so the DDINT entry points have the same addresses in either mode |
| 58h | 000000h | Code: just the CALL 5 jump at 0:00C0h |
| 60h | | SEL_CALL5: call gate (DPL 3) for a PSP's CALL 5 |
| 68h | System area + 10E0h | The TSS |
| A000h-B800h | A0000h-B8000h | Data: identity selectors for video memory, every 800h, for the BIOS and the drivers (a ring 3 program gets its own selector from VKD$; see [Video Memory](#video)) |
| C000h-F800h | C0000h-F8000h | Code: identity selectors for the adapter and system ROMs, every 800h, so the ROM BIOS can run at ring 0 with its own segments (eg, F000h) |

Selectors 70h-7F8h (GDT) and 04h-7FCh (the active LDT) are allocated by CPU_ALLOC, CPU_MAP, and CPU_ALIAS.  All descriptors are 80286-format (the 80386 fields are zero, except bits 31-24 of the base, for blocks above 16Mb) and DPL 0 (unless MEMF_USER is set).  The GDT's limit extends through the identity selectors, so the processor can also read the rest of the system area as descriptors, through selectors 0800h to 9FF8h.  So the PMB table and LDTs start at an offset of 6 mod 8, which puts each of those selectors' access bytes on a byte that never has its present bit set (bits 31-24 of a descriptor's base, or in a PMB, the top of PMB_ADDR, the high byte of PMB_NSEL, a reserved byte, or the last byte of PMB_NAME, whose bit 7 CPU_SETBLK clears).  That way, loading one of those selectors (eg, a real-mode segment by mistake) always faults, and a ring 3 program can't reach another LDT's descriptors through the GDT.

### Physical Memory Arena {#arena}

The 80286 driver's arena is a table of Physical Memory Blocks (PMBs) in address order, covering all memory from 0 to the end of extended memory, with the last PMB marked PMBSIG_LAST ('Z'), like the last MCB:

| Field | Size | Contents |
|-------|------|----------|
| PMB_SIG | byte | 'M', or 'Z' for the last PMB |
| PMB_TYPE | byte | PMBTYPE_* |
| PMB_OWNER | word | Owner ID (see [Owner IDs](#owners)), or zero |
| PMB_ADDR | dword | Physical address |
| PMB_LEN | dword | Length, in bytes |
| PMB_SEL | word | First selector (if any) |
| PMB_NSEL | word | Number of selectors |
| PMB_MCBTYPE | byte | Block type (MCBTYPE_*, as in an MCB), or zero |
| (reserved) | byte | |
| PMB_CODE | word | The block's code alias (see [Code Aliases](#aliases)), or zero |
| (reserved) | 4 bytes | |
| PMB_NAME | 8 bytes | Name of the process (as in an MCB), or zero |

Unlike MCBs, PMBs aren't stored in front of the memory they describe:

- the arena has to describe memory that isn't RAM (eg, 640K-1Mb), where no header could be stored;
- headers in extended memory couldn't be read or written in real mode;
- blocks need no header, so they stay aligned, and a block can be mapped by a selector with no offset; and
- a program that writes past the end of its block can't damage the arena.

The cost is the room that the table takes in the system area (see [Table Growth](#growth)).  The 8086 driver's arena is the MCB chain itself: programs on an 8086 expect to see MCBs, and conventional memory is all there is.  With the 8086 driver, CPU_QUERY describes each MCB with a PMB (whose PMB_SEL is the block's segment).

For debuggers that can't call CPU$ (eg, the PCjs Debugger, whose `d dos` command lists the arena the way DEBUG's DM does), whichever driver stays stores the real-mode address of its arena in CPU_ARENA (0:514h): the 8086 driver's first MCB, or the 80286 driver's PMB table (in the system area, at offset 110Eh); a nonzero offset means it's the table, since an MCB's offset is always zero.

#### Memory and DOS {#dosmem}

From the moment CPU$ initializes, everything that runs during the boot (devinit, each driver, and sysinit) claims the memory it uses from CPU$, and moves memory only with CPU_MOVE, so neither devinit nor sysinit computes a segment from an address.  After the boot, DOS's memory functions are calls to CPU$: DOS_MEM_ALLOC calls CPU_ALLOC (so in protected mode, a block can be anywhere in conventional or extended memory) and CPU_SETBLK, DOS_MEM_FREE calls CPU_FREE, DOS_MEM_REALLOC calls CPU_REALLOC, a program's blocks are freed with CPU_FREEALL when it ends, and DOS_UTL_QRYMEM (for MEM) uses CPU_QUERY.  There's no MCB chain for programs to walk, other than the 8086 driver's, and MEM's total memory (which DOS_MSC_GETVARS returns in AX) includes extended memory.

### Switching Modes

To test protected mode, CPU$ switches to it and back.  An 80386 returns to real mode by clearing PE.  An 80286 can't, so before switching, CPU$ sets the CMOS shutdown code to 0Ah and stores its return address in 40:67h, and to return, it resets the processor through the 8042, as the BIOS's own block move (INT 15h function 87h) does; the BIOS sees the shutdown code and jumps through 40:67h without initializing anything else.  Because the shutdown code is set before switching, a "triple fault" (which resets the processor) also returns to CPU$, and until the test passes, every gate in the IDT returns to real mode (without a reset, on an 80386), so a bug in protected mode makes the test fail instead of hanging the machine.  The test writes and reads back a word at the start of the system area, through its selector; CPU$ stays loaded only if that works; otherwise, it turns A20 back off, and the 8086 driver stays instead.

CPU_PMODE switches to protected mode the same way, but for good: it never returns to real mode.

### Protected-Mode Initialization {#pminit}

On an 80286 or later, when the 80286 CPU$ stays loaded, BASIC-DOS switches to protected mode during devinit, right after CPU$ initializes, and never switches back:

1. **CPU$ initializes in real mode**, as the first driver, and devinit loads BASDOS.COM (the kernel) while it can still use the boot code.  It also moves itself up, since FDC$'s buffer is larger in protected mode (up to 9K), and the drivers after FDC$ will move up to make room.
2. **devinit calls CPU_PMODE**, which turns its segment registers into selectors for the same memory, points DDINT_CPU, DDINT_GETVEC, and DDINT_SETVEC at CPU$'s protected-mode code, moves the master PIC's interrupts to 78h-7Fh, and loads the protected-mode IDT and the TSS.
3. **Each driver gets a code selector and a data selector** (CPU_MAP and CPU_ALIAS) before its initialization: devinit stores the data selector in DDH_DATA, calls the driver through its code selector, and links it into the chain with its code selector.  When the driver's initialization returns, devinit fits both selectors to what the driver keeps (CPU_SETLIM).  Drivers install their interrupt handlers in the IDT with DDINT_SETVEC.
4. **devinit moves the kernel after the drivers**, with a code selector and a data selector for it, and starts the kernel's initialization (sysinit).
5. **sysinit runs in protected mode**: it points the DOS vectors at the kernel's code selector, gives CPU$ the kernel's fault handler (CPU_SETFAULT), builds its tables, gets a selector for each disk buffer, loads any DEVICE= drivers (calling each one through a code alias of its block), and loads the SHELLs.
6. **The first session starts**, at ring 3 unless CONFIG.SYS has `RING=0`, with CS set to the code alias of its program's block (see [Code Aliases](#aliases)).

The kernel's protected-mode-only code (its fault handler, NE loader, and ring 3 support) comes after the rest of its resident code, so in real mode, it costs no memory.

### Protected-Mode Interrupts {#interrupts}

After CPU_PMODE, every interrupt goes through CPU$'s IDT, and the master PIC is moved from 08h to 78h, next to the slave PIC (70h-77h), so that IRQs 0-7 no longer share vectors with processor exceptions.  Its default gates "reflect" each interrupt to the handler in the real-mode vector table, if that's in the ROM (whose segments are identity selectors, eg, F000h), at ring 0, on the interrupted code's stack (or for an interrupt from ring 3, its ring 0 stack), so a BIOS call never costs a mode switch:

| IDT entries | DPL | Default handling |
|-------------|-----|------------------|
| 00h | 3 | Divide errors (DPL 3, since ring 3 code may issue INT 0, as FPU$ does) |
| 01h-02h, 06h-0Fh | 0 | Exceptions: fatal, except the cases below |
| 03h-05h, 10h-6Fh, 80h-FFh | 3 | Software interrupts: the vector's handler, if it's in the ROM; otherwise fatal |
| 70h-77h | 0 | IRQs 8-15: vectors 70h-77h's handlers, if in the ROM; otherwise an EOI |
| 78h-7Fh | 0 | IRQs 0-7: vectors 08h-0Fh's handlers, if in the ROM; otherwise an EOI |

Ring 3 code can issue software interrupts (eg, INT 21h, or INT 10h, which is reflected to the ROM at ring 0), but an INT at ring 3 for any other exception or an IRQ is a general protection fault.

- **Drivers' handlers**: in protected mode, DDINT_GETVEC and DDINT_SETVEC read and write the IDT: setting a vector replaces its gate's selector and offset (for vectors 08h-0Fh, the gates for IRQs 0-7), keeping the gate's DPL, so the driver's handler is called directly, and getting a vector returns its gate, or if the gate is a default one, its real-mode vector if that's in the ROM (eg, F000:FEA5h for INT 08h, which CLOCK$ chains to), or 0:0 if not.
- **INT 13h**: the BIOS's disk functions assume that ES:BX is a real-mode address, so FDC$, which makes every disk transfer, gives the BIOS an address that works in both modes: for the diskette BIOS, which turns ES:BX into a DMA address, an offset from segment 40h (or, for a buffer more than 64K above it, a buffer of its own, large enough for a track of the largest diskette drive, so that reading a track still takes one BIOS call), and for the fixed disk BIOS, a selector of the buffer's own, with a zero offset.
- **Vectors 08h-0Fh** are also software interrupts sometimes (eg, the AT BIOS's IRQ 9 handler does `INT 0Ah`), so an exception whose return address follows an `INT` for its vector is treated as one.
- **Null selectors in the ROM**: the BIOS loads DS with 0 to address the vectors (eg, `LDS SI,[78h]` with DS = 0), so a general protection fault with a zero error code, in the ROM, while DS or ES holds a null selector, is retried with a selector for the first 64K.  BASIC-DOS's own code gets no such fix.

#### Faults {#faults}

Any other exception (including an INT 3, such as a failed DEBUG assertion, or a software interrupt with no handler that CPU$ can call) goes to the fault handler (see CPU_SETFAULT), which is the kernel's unless a debugger has replaced it:

- **In the current program's own code** (or any block that the program owns, such as one of COMMAND's BASIC code blocks), DOS displays `CPU fault vv (EC=xxxx) at cccc:iiii` and ends the program with exit code 255 and EXTYPE_FAULT, as it does for a divide error, and the system continues.
- **A not-present LDT selector** (#NP), which a driver took away (see [Selector IDs](#selids)), isn't fatal: in a program, or in the kernel resuming one, the session waits for the selector, as if the faulting instruction were a DOS call, and then the instruction runs again.  In a hardware interrupt, or while the session is locked, it's treated like any other fault.
- **In the kernel, working for a ring 3 program**: a protection fault (#TS, #NP, #SS, or #GP) in the kernel, usually from a bad pointer that a program gave it, ends that program the same way, since the kernel can abandon what it was doing: it resets its session lock and INDOS count, returns to the top of the program's ring 0 stack, and ends the program as if the program had asked to end.  A fault in a hardware interrupt isn't working for a program, and a fault while already ending one could repeat forever, so both are fatal.
- **Anywhere else** (eg, in a driver or the ROM, or in the kernel with `RING=0`), the exception is fatal: CPU$ prints the same `CPU fault` line, followed by `System halted`, offers the halt to the fault handler, and unless a debugger takes it, stops the machine.
- **With DEBUG.COM** loaded as a driver, DEBUG.COM passes each exception on to the kernel unless its VT command traps the vector, and stops for any that the kernel declines, so that G can retry it (eg, after a fix); it then accepts CPU$'s halt, so that it never gives up control (see [Exceptions and Faults](../../bdman/cmd/external/debug/#exceptions-and-faults)).

### Mode-Independent Code {#modeless}

The drivers and the kernel (everything that runs at ring 0) are the same code in either mode, so they follow these rules:

1. **Low memory through segment 40h**: the ROM BIOS data area and BASIC-DOS's low memory (CPU_TYPE, the DDINT entry points, and the diskette parameter table) are addressed through segment 40h, which in protected mode is a selector with the same base.
2. **Interrupt vectors through DDINT_GETVEC and DDINT_SETVEC**, which pass vectors in DX:CX rather than in segment registers (see [Device Drivers](../dev/)), since segment 0 is the null selector in protected mode.  Only the boot code and devinit, which run first, use segment 0.
3. **DDINT entry points through segment 50h** (eg, DDINT_SETVEC is 0050:003Ah), which in protected mode is a code selector with the same base, so the addresses are the same in either mode.
4. **No writes through CS**: a protected-mode code segment can't be written, so code that writes to its own memory uses DS, ES, or SS holding its own data segment (or selector); a driver gets its own from DDH_DATA (see [Device Drivers](../dev/)), whose code selector (CS) and data selector are separate selectors for the same memory in protected mode.
5. **No unnecessary null selectors**: segment registers are never loaded with 0 just to have a value, and an empty chain's far pointer (eg, CLOCK$'s list of waiting packets) has an offset of FFFFh and a segment of 0, rather than -1:-1, so that loading the whole pointer before checking the offset is safe.
6. **A new program's FLAGS** are 0202h, not F202h (as an 8086 pushes FLAGS), so that an IRET in protected mode doesn't set IOPL 3 and NT (and the next IRET with NT set doesn't switch tasks), which also gives every program IOPL 0, so ring 3 code can't use IN, OUT, CLI, or STI.

#### COMMAND.COM {#command}

COMMAND.COM runs at ring 3, so it uses only selectors that the kernel gives it, and asks the kernel or a driver for anything it can't reach itself:

- **Video memory** comes from VKD$ (IOCTL_GETMODE with CL = 1 returns the context's video memory in DX, which in protected mode is an LDT selector of the context's own; see [Video Memory](#video)).
- **The tick count** (for RANDOMIZE, SOUND, and PLAY) comes from DOS_UTL_GETTIME with AL = 1, MEM's total memory from DOS_MSC_GETVARS, and KILL's session list from DOS_UTL_QRYSCB.
- **Sounds** start and stop through CLOCK$ (DOS_UTL_SOUND), rather than with IN and OUT.
- **BASIC code** runs from code blocks through their code aliases (see [Code Aliases](#aliases)), and DEF SEG gets a selector from the kernel (see [DEF SEG](#defseg)).
- **Blocks** (for code, text, variables, and strings) come from DOS_MEM_ALLOC with MCBTYPE_HIGH, so in protected mode, they come from the top of memory.

### Code Aliases {#aliases}

A protected-mode segment is either code (executable, and at most readable) or data (readable, and perhaps writable), so memory that's both written and executed needs two selectors.  CPU_ALIAS creates the second one: given a selector, it returns a new selector for the same base and limit, with the access rights selected by MEMF_CODE, MEMF_RDONLY, and MEMF_USER, and CPU_UNMAP frees it.

A block's own code alias (CPU_ALIAS with just MEMF_CODE, for the selector that CPU_ALLOC returned for the block) is created only once, with the block's DPL, and is freed with the block, so nothing else has to keep track of it (and it must never be freed with CPU_UNMAP).  Programs get it from DOS_UTL_ALIAS (27h; see [Utility Functions](../util/#memory)), since ring 3 code can't call CPU$, and with AL = 1, the same function does the reverse, returning the block's own selector for its code alias, since a code selector isn't writable (eg, so that a debugger can store a breakpoint in a program's code); in real mode, a block's code alias is its segment.

COMMAND.COM compiles BASIC into code blocks that it allocates as data, and runs them (and transfers from one to another) through their code aliases.  Generated code that writes to its own block (eg, a double's result) gets the block's data selector from the block itself, rather than from CS.

#### Loading Programs {#exec}

In protected mode, the DOS_PSP_EXEC functions run COM and NE programs, but not "MZ" EXE files:

- **COM programs**: a COM program's code and data are in one block (its PSP block).  CS comes from the block's code alias, and DS, ES, and SS come from the block's data selector.  A program that sets a vector with DS:DX, as COM programs often do, would give it a data selector, so when DS is the program's PSP block, DOS_MSC_SETVEC uses the block's code alias instead, which in real mode is the same segment.
- **MZ EXE files**: an EXE file's relocations are paragraph arithmetic, which doesn't work with selectors, so in protected mode, the DOS_PSP_EXEC functions refuse them with ERR_NOMEMORY, which COMMAND reports as "Unable to load X".
- **NE programs**: an NE ("new executable") file lists each segment's type and size, and its relocations refer to segments by number, so each segment gets a block of its own, owned by the program's PSP, and a selector whose limit fits the segment exactly (for a code segment, the block's code alias).  The program must be marked PROTMODE, with FIXED segments, no imports, and only internal relocations; it starts with DS and ES addressing its PSP, as an MZ program does.  In real mode, an NE file runs its MS-DOS stub, like any MZ EXE file.

`TESTS\BIN\PRIMES.EXE` is an NE program, linked by LINK4 (see `tests/primes/PRIMES.DEF` and the [build tools](../../../software/src/tools/dos/README.TXT)), with the real-mode program as its MS-DOS stub, so it runs in either mode.  LINK4 makes a segment code only if its class is `CODE`, and requires a DGROUP.

### DEF SEG, PEEK, and POKE {#defseg}

DEF SEG accepts any segment, which in protected mode isn't a selector, so COMMAND.COM gets a selector for the segment's 64K from the kernel (DOS_UTL_MAPSEG; see [Utility Functions](../util/#memory)), which each session keeps one of.  The selector is writable for video memory (A000h through BFFFh), and read-only everywhere else, including low memory and the ROMs, so PEEK works, but POKE is an "Illegal function call".  DEF SEG with no segment (BASIC's own data) is readable and writable, as before.  In real mode, none of these restrictions apply.

### Video Memory {#video}

In protected mode, the identity selectors for video memory are DPL 0, for the BIOS and the drivers, so a ring 3 program that draws directly (eg, COMMAND.COM's graphics statements) gets a selector from the console's driver instead: IOCTL_GETMODE with CL = 1 returns VKD$'s LDT selector for the context, which maps the adapter's video memory (16K for a CGA, or 4K for an MDA).  VKD$ creates it with CPU_MAP the first time a program asks, in the LDT of the sessions on that console, and frees it when the context closes, and in between, it decides what the selector maps (see [Selector IDs](#selids)):

- **While another context on the same adapter is in a mode other than its original one** (eg, after SCREEN 1), the context is blocked (its output waits), and its selector is not present, so a program that loads the selector waits, too, until the other context returns to its original mode.
- **Otherwise**, the selector maps the adapter's video memory, where the context has a region (or a page) of its own, so it stays present when the context loses focus.

A driver that saved a blocked context's video memory in a buffer could map the selector to the buffer instead, so that the program keeps running; VKD$ doesn't.  In real mode, IOCTL_GETMODE returns the video memory's segment.  DEF SEG's selectors (DOS_UTL_MAPSEG) don't go through the driver, so POKE can still change any console's video memory.

### Running Programs at Ring 3 {#ring3}

In protected mode, unless CONFIG.SYS has `RING=0` (see [CONFIG.SYS](../../bdman/cfg/#ring)), every session's first program (eg, COMMAND.COM) and every program that the DOS_PSP_EXEC functions start runs at ring 3, with CPU$, the drivers, and the kernel at ring 0, so that a program can use only the memory it's given, and can't use privileged instructions.

- **Selectors**: the blocks that DOS_MEM_ALLOC allocates for a ring 3 program (including the blocks that a program is loaded into) have DPL 3 selectors (MEMF_USER) in its session's LDT (MEMF_LDT), and a program's CS has RPL 3, which is how DOS knows to start it at ring 3.
- **LDTs**: each session that sysinit loads (eg, each SHELL) has an LDT of its own, whose number is the session's number, and a session that a program loads (eg, the next program of a pipeline) shares that program's LDT, so the sessions on a console share one, and a program can't name the memory of a session with another LDT; the kernel makes a session's LDT the active one (CPU_SETLDT) whenever it switches sessions.  Selectors repeat from one LDT to the next, so a ring 3 program's PSP doesn't identify it on its own, and CPU$ stores the owner of each of its blocks as an [owner ID](#owners) that includes the LDT number, which is what CPU_FREEALL frees by.  A program can also reach the memory of the other sessions that share its LDT.
- **Ring 0 stacks**: the TSS is used only for its ring 0 stack (CPU_SETSTACK), which the processor switches to when an interrupt takes ring 3 code to ring 0.  A program's ring 0 stack is its parent's stack, where the parent waits for it to end, so nested programs need no stacks of their own; a session's first program, which has no parent, uses a 1K ring 0 stack that the kernel allocates for each session.
- **DOS calls**: a DOS call's parameters on the caller's stack (eg, for DOS_UTL_PRINTF and DOS_UTL_SPRINTF) are read through a ring 0 alias of the caller's stack, and a CALL 5 works at ring 3, too, since SEL_CALL5 is a DPL 3 gate.
- **Memory blocks**: a ring 3 program can free or resize only a block that it owns, so any other selector with the same base address (eg, a DOS_UTL_MAPSEG selector for low memory) gets ERR_BADADDR, and it can't free its PSP's block, or shrink it below the PSP, since the kernel needs the PSP until the program ends.  If it frees or shrinks the memory that it's running in, it ends with a `CPU fault`, as it would have at its next instruction.  A DS or ES selector that's gone becomes 0.
- **The kernel's checks**: a fault in the kernel stops the system, so before the kernel uses a ring 3 program's stack, or returns to an address that the program supplied, it checks that it won't fault (with VERW, LSL, and LAR).  If it would, the program ends with a `CPU fault` (a handler that can't be entered gets the default CTRL-C or ABORT response, and an interrupt that can't be reflected goes to the previous handler).  INT 22h's gate must be DPL 3, for the ring 3 stub described below, so issuing it for any other reason ends the program, too, with the error code of a fault on that gate.  Disk and device transfers are checked first, too (DOS_HDL_READ, DOS_HDL_WRITE, and the FCB functions), since a transfer's physical address ignores the buffer selector's limit, and a fault in a driver is fatal, and so is the data for each IOCTL that uses DS:SI (the program ends with a `CPU fault` if it isn't all in the program's memory).  Any other bad pointer faults in the kernel, which ends the program (see [Faults](#faults)).
- **The PSP**: a program can write its own PSP, and its parent's, so the kernel keeps what it depends on where a program can't reach it: a record at the top of each program's ring 0 stack holds its parent's PSP, ring 0 stack, CTRL-C and critical error handlers, and DTA, and SCB_SP0 points to the record.  When a program ends, the kernel rewrites PSP_PARENT, PSP_SCB, PSP_CTRLC, PSP_ERROR, and PSP_DTAPREV in its PSP, and PSP_STACK and PSP_SCB in its parent's, from what it knows, and it returns to PSP_EXIT only if that's a usable ring 3 address.  A handler that isn't at ring 3 is always the kernel's default.  DOS_PSP_SET accepts only a PSP in the same LDT, and DOS_PSP_COPY and DOS_PSP_CREATE only a block that the program owns.
- **Selectors in memory**: the processor checks a selector that a program loads into a segment register, but not one that it leaves in memory or a general register, which the kernel could then load at ring 0.  So each far pointer in an EPB, or an SPB's command line, gets RPL 3 before the kernel uses it, which makes the processor fault on a ring 0 selector, as it would at ring 3.
- **CTRL-C and critical error handlers** (INT 23h and INT 24h) run at ring 3, on the stack of the program that called DOS, and return to the kernel through a ring 3 stub.  A critical error handler gets a copy of the device header (since it can't read the driver's memory), and a CTRL-C handler can continue the DOS call (with any registers it changed) or end the program, as at ring 0; either way, the kernel makes sure the program stays at ring 3, with IOPL 0.
- **BIOS and other interrupts**: ring 3 code can issue only INT 00h, 03h, 04h, DOS's vectors (INT 20h-2Fh), INT 33h (the mouse), and INT 60h-67h; any other INT ends the program with a `CPU fault`.  A BIOS function would run at ring 0, trusting what it was given (eg, disk functions compute a DMA address from a segment value), and a fault in the ROM stops the system.  Programs use DOS and the drivers' IOCTLs instead, and programs that need the BIOS (eg, DISKREAD and DISKWRIT in TESTS\MISC) need `RING=0`.
- **Functions for drivers and the kernel**: DOS_UTL_HPRINTF, DOS_UTL_WAIT, DOS_UTL_ENDWAIT, DOS_UTL_HOTKEY, DOS_UTL_LOCK, and DOS_UTL_UNLOCK return ERR_ACCDENIED to a ring 3 caller, since a lock stops every other session, and the others can affect other sessions.
- **Selectors for blocks**: DOS_UTL_ALIAS returns a code alias only for the selector of a block that the program owns (otherwise, ERR_BADADDR), since those are the aliases that the kernel frees, and a program could otherwise use up the GDT.
- **File handles**: a program can write anything in its PSP_PFT, so the kernel keeps a table that only it can reach, of which sessions opened each open SFB.  A handle's SFB must be one that its session opened, or one of the session's standard SFBs, or the DOS function returns ERR_BADHANDLE; any other entry is removed from PSP_PFT before the kernel copies or closes them, and an SPB's SFHs are checked the same way.
- **Chains of programs**: a program's ring 0 stack is its parent's, so DOS_PSP_EXEC returns ERR_NOMEMORY when less than 512 bytes of the session's 1K ring 0 stack would remain, which is about 8 programs.
- **Interrupt vectors**: a ring 3 program can hook only the vectors on a short list: the exceptions that a program can handle (INT 00h, 01h, 03h, and 04h), DOS (INT 21h), and the vectors free for programs to use (INT 60h-67h).  Any other DOS_MSC_SETVEC returns ERR_ACCDENIED, and any other DOS_MSC_GETVEC returns 0:0, so a program can't take over an IRQ, whose handler would stop that interrupt for every session if it didn't chain.  The IDT is shared by every session and by ring 0 code, so a ring 3 program's handler can't go in a gate.  Instead, when a ring 3 program sets a vector (other than INT 22h-24h, which each session has its own of), the kernel puts a gate of its own there, which reflects the interrupts that ring 3 code in the program's session issues to the program's handler, at ring 3, and passes all others to the previous handler.  A ring 3 program that gets a vector (eg, to chain to it) gets the address of a ring 3 stub that passes the interrupt to the previous handler.  The kernel removes the program's handlers when it ends.  So, for example, an INT 21h hook sees the DOS calls of the programs it runs, but not the kernel's own.
- **FPU$**: its functions are mapped with conforming code selectors, so the kernel and programs at ring 3 call them through the same FPUTBL, and they run at the caller's ring (see [Floating-Point Interface](../fpu/)).
- **DEBUG.COM** as a driver (at ring 0) can stop and resume ring 3 programs with every command.  As a program at ring 3, it can't call CPU$, so it uses DOS functions and the 80286's unprivileged instructions instead (see [Installable Drivers](../dev/#installable-drivers)), and it can write only the memory that ring 3 can (eg, the program's own, not DOS's, the drivers', or the BIOS data area), although it can read memory below 1Mb, by finding a selector's base in the GDT (see DOS_UTL_MAPSEG); it has no LN command, no `&`, `#`, or `%` addresses, and no system registers, and T steps over an INT, as P does.

### The Protected Mode Demo {#pmdemo}

The [Protected Mode demo](/demos/mmu/) is a 2Mb PC AT with a Color Display and three full-screen consoles, one on each page of video memory, and the [Protected Mode (640K) demo](/demos/mmu/640k/) runs the same sessions on a PC AT with no extended memory.  The [Protected Mode (VT100) demo](/demos/mmu/vt100/) runs the same sessions, with a DEC VT100 on COM2 for DEBUG.COM, and its [Debugger](/demos/mmu/vt100/debugger/) page is the same machine with the PCjs Debugger.  Each boots a diskette whose CONFIG.SYS has a `CPU=80286` line (pressing **Esc** at the boot message boots the hard disk instead, which runs in real mode, and pressing **R** boots the diskette in real mode).  Everything after CPU$ initializes runs in protected mode, and COMMAND.COM runs at ring 3, with C: as the default drive.  Commands, BASIC programs, and NE programs work (eg, PRIMES.BAS in the third session), but MZ EXE files don't (see [Loading Programs](#exec)).

In the VT100 demo, DEBUG.COM, loaded as a driver, shows each fault on the VT100, with the registers at the faulting instruction (adding /H to its line in CONFIG.SYS stops it as soon as it's loaded, so that you can set breakpoints before booting continues).  The B: drive has the BASIC-DOS Tests diskette, so `B:\TESTS\MISC\FAULT n` causes exception *n* (0, 1, 3-6, 12, or 13), or with -1, a fault in the kernel (a null pointer to a filename), to see how BASIC-DOS responds: DOS reports a divide error (0) or an overflow (4) and ends the program, a single-step trap (1) or a breakpoint (3) resumes (unless DEBUG.COM stops there), and DOS ends the program for the rest (eg, `CPU fault 0D`), unless DEBUG.COM's VT command traps the vector.

### Debugging {#pmdebug}

- DEBUG.COM works in either mode: an address can start with `&` (real mode), `#` (protected mode), or `%` (a physical address), `DS selector` displays a selector's descriptor, R also shows the MSW, GDTR, and IDTR (and in protected mode, the LDTR, TR, and each segment register's base and limit), and `LN [address]` shows the name of the memory an address is in (see [DEBUG.COM](../../bdman/cmd/external/debug/)).
- The PCjs Debugger's `r` shows each segment register's selector with its base and limit in protected mode (eg, `CS=0018[000970,FFFF]` in CPU$), along with the GDTR, IDTR, LDTR, and TR, and its `d dos` command lists CPU$'s arena, in either mode (see [Physical Memory Arena](#arena)).

### Limitations {#limits}

- **MZ EXE files** don't run in protected mode (see [Loading Programs](#exec)).  They could run with the processor switched back to real mode on an 80286 (as in OS/2's DOS session, with other sessions waiting), or in virtual-8086 mode on an 80386; neither is implemented.
- **The 80386** runs the 80286 code (with no virtual-8086 mode, paging, or 32-bit segments), and only IBM's PC AT BIOS is tested in protected mode.
- **BIOS functions**: the ones that the drivers use work in protected mode, but the rest haven't been tried, and a few (eg, INT 15h functions 87h and 89h, which switch modes themselves) would need CPU$ replacements.
- **Interrupt hooks at ring 3**: a ring 3 program's handler sees only the interrupts that ring 3 code in its own session issues, so a hook of an interrupt that ring 0 code issues (eg, INT 1Ch, from the BIOS's timer handler, or INT 13h, from FDC$) never runs.  And there are only 8 reflected vectors for all sessions; with none free, DOS_MSC_SETVEC returns ERR_NOMEMORY, and DOS_MSC_GETVEC returns 0:0.
- **CPU$ from ring 3**: ring 3 code can't call CPU$, so programs that do (eg, CPUTESTS) need `RING=0`, and DEBUG.COM run as a program has fewer commands at ring 3 (see [Running Programs at Ring 3](#ring3)).
- **I/O at ring 3**: programs run with IOPL 0, so a program that uses IN, OUT, CLI, or STI needs `RING=0`.
- **Table sizes**: the GDT (256 entries) and the number of LDTs (32) are fixed, and the PMB table and LDTs share a fixed amount of space (see [Table Growth](#growth)).
- **Faults in drivers** are still fatal, since only the driver knows what it was doing.  DOS checks the buffers that it gives them.
- **Sharing an SFB**: a session that shares an SFB (eg, a pipe, or a file that two sessions opened) can close more references to it than it has, by repeating its SFH in its PSP_PFT, which can affect the other session.  It still can't reach an SFB that it never had.
- **What DOS allows**: there's no privilege model for programs, so any program can do what COMMAND.COM can with DOS functions: restart the system (DOS_UTL_RESTART), end another session (DOS_UTL_END), and change any file, or write any volume (eg, with FORMAT's IOCTLs).  It can also use all of memory, up to the table limits, and through DEF SEG (DOS_UTL_MAPSEG), draw on any console's video memory.
- **Reading kernel memory**: a `%ls` parameter to DOS_UTL_PRINTF can still point to a ring 0 selector, so a ring 3 program can read kernel memory that way (but not write it).
- **Identity selectors** exist only every 800h from A000h to F800h, so a ROM segment that isn't a multiple of 800h (eg, F600h, the PC's ROM BASIC) can't be reflected to.
- **A20** stays enabled, so programs that depend on addresses wrapping at 1Mb could break (eg, EXEPACK-compressed programs loaded in the first 64K report "Packed file is corrupt").
- **COMMAND.COM's shared code** includes some variables, so it can't be one read-only code selector that every copy shares, and an LDT selector means something else in another LDT, so at ring 3, every copy loads its own code (at ring 0 and in real mode, copies share it).
- **DEF SEG** makes only video memory and BASIC's own data writable, even for blocks that belong to the session.

{% include footer.html prev="Data Structures:../data/" next="BASIC-DOS vs. DOS Extenders:../ext/" %}
