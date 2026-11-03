---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Protected Mode and Memory Management
permalink: /docs/bdtech/mmu/
---

{% include header.html %}

BASIC-DOS manages all memory, on every processor, through a built-in driver, **CPU$**, which is also the only part of BASIC-DOS that knows about descriptors, selectors, and physical memory.  CPU$ loads first and determines the processor type, and on a processor that can use protected mode, it manages a table of physical memory blocks covering conventional and extended memory, along with the GDT, the IDT, and an LDT for each session (see [The CPU$ Drivers](#cpu)).

On an 80286 or later, BASIC-DOS switches to protected mode while its drivers initialize, and stays there (see [Protected-Mode Initialization](#pminit)): CPU$, the drivers, and the kernel run at ring 0, and COMMAND.COM, its BASIC programs, and the programs it runs run at ring 3, with each session's memory in its own LDT (see [Running Programs at Ring 3](#ring3)), and DOS allocates memory from anywhere in conventional or extended memory.  The same binaries run in real mode on an 8086 or 8088 (or with `CPU=8088` in CONFIG.SYS), where CPU$ manages memory with a chain of MCBs, as DOS always has, and uses no extra memory (see [Mode-Independent Code](#modeless)).

The [Protected Mode demo](/demos/mmu/) boots in protected mode on a 2Mb PC AT (see [The Protected Mode Demo](#pmdemo)).  What doesn't work in protected mode yet (most notably, MZ EXE files) is listed under [Limitations](#limits).

### Supported Machines {#machines}

Protected mode needs an 80286 or later, at least 128K of conventional memory (after any `MEMSIZE=` line), at least 64K of extended memory, and A20 control through the 8042 keyboard controller, as on a PC AT; otherwise (or with [CPU=8088](../../bdman/cfg/#cpu)), BASIC-DOS runs in real mode.

Protected mode is built and tested for the IBM PC AT (80286, with IBM's revision 3 BIOS), typically with 2Mb of memory: 640K of conventional memory and 1408K of extended memory.  An 80386 runs the same code, with 80286-format descriptors; it's tested only occasionally, on a COMPAQ DeskPro 386.  So every configuration that boots on a PC AT or DeskPro 386 has `CPU=8088` in its CONFIG.SYS, except for the Protected Mode demo and the protected-mode tests, which `tools/tests/mmutest.sh` runs on four machines: a PC XT, a PC AT with `CPU=8088`, and a PC AT in protected mode, both with `RING=0` and without it.

### The CPU$ Drivers {#cpu}

BASDEV.COM starts with two CPU$ drivers, of which exactly one stays loaded: the 80286 driver, followed by the 8086 driver.  The 80286 driver, which is initialized first, determines the processor type:

1. An 8086 or 80186 decrements SP before PUSH SP stores it, whereas an 80286 or later stores the original value.
2. An 80186 masks shift counts to 5 bits, so shifting 1 left 33 times leaves 2 (instead of 0 on an 8086).
3. In real mode, an 80286 always clears FLAGS bits 12-15, whereas an 80386 lets software set bits 12-14 (IOPL and NT).

It stores the result in CPU_HWTYPE (0:513h) and CPU_TYPE (0:512h), as one of the CPUTYPE_* values in cpu.inc (0 = 8086/8088, 1 = 80186/80188, 2 = 80286, 3 = 80386 or later).  A `CPU=8088` line in CONFIG.SYS, or less than 128K of conventional memory (after any `MEMSIZE=` line, which the 80286 driver applies by lowering the BIOS's memory size), makes CPU$ store 0 in CPU_TYPE and act as it does on an 8088, without enabling A20; CPU_HWTYPE is still the processor's own type, for software that must know how the processor runs instructions (eg, DEBUG.COM's disassembler).

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
| 03h | CPU_MAP | AL = MEMF_* flags, DX:CX = address, SI:DI = length | AX = first selector, CX = number of selectors |
| 04h | CPU_UNMAP | BX = first selector, CX = number of selectors (0 = 1) | |
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
| 12h | CPU_SETLDT | AL = session number | |

Every function works the same way in either driver and in either mode, so callers needn't check which is which: in real mode, CPU_ALLOC, CPU_MAP, and CPU_ALIAS return the memory's segment instead of a selector (CPU_ALLOC returns 0 for a block above 1Mb, and CPU_MAP needs memory below 1Mb that's paragraph-aligned), a segment is its own alias, and CPU_UNMAP has nothing to do.  Errors are ERR_INVALID (eg, a bad function, a zero length, or a selector that isn't in use), ERR_NOMEMORY (no block big enough, with DX:CX = the length of the largest free block; or no free PMB or descriptors), and ERR_BADADDR (a block that CPU_ALLOC didn't return).

- **Blocks**: a *block* (DX:CX) is the address that CPU_ALLOC returned, or DX = -1 and CX = the selector (or segment) that it returned, which is what DOS has (eg, in ES for DOS_MEM_FREE).  CPU_ALLOC rounds lengths up to a multiple of 16, so every block starts on a paragraph boundary, and a block of more than 64K gets one selector for every 64K (each 8 more than the last).  CPU_REALLOC shrinks a block, or grows it into the free block after it (without changing its selectors), and CPU_MOVE copies memory between any two physical addresses (below 1Mb, in real mode), even if they overlap.  CPU_SETBLK records a block's owner, type, and name for DOS (as an MCB does), which MEM and DEBUG's DM show, and CPU_FREEALL frees every block an owner has (DOS uses it when a program ends).
- **Owner IDs** {#owners}: an owner is a PSP (or a driver's segment, or MCBOWNER_SYSTEM), which the 80286 driver stores as an *owner ID* (PMB_OWNER).  In protected mode, a ring 3 program's PSP is an LDT selector, which another session's program can share (see [Ring 3](#ring3)), so its ID is 80h plus its session number in the high byte and its LDT index in the low byte (eg, 8000h for session 0's COMMAND.COM, whose PSP is selector 0007h, and 8100h for session 1's), which is unique, and above MCBOWNER_SYSTEM, like a PSP segment; any other owner is its own ID.  CPU_QUERY returns the IDs (eg, to MEM and DEBUG's DM, which display them), and CPU_FREEALL takes an owner, as CPU_ALLOC and CPU_SETBLK do.  DOS compares a block's owner with a program's ID, which it gets from the program's own block (every PSP block owns itself), when it needs to know whether the program owns the block (eg, for a fault in the program's code, or FRE(-1); see DOS_UTL_QRYMEM).
- **Memory flags**: MEMF_LDT (01h) requests LDT selectors instead of GDT selectors, MEMF_CODE (02h) code segments instead of data segments, MEMF_NONE (04h) a block without any selectors (for CPU_MAP and CPU_ALIAS, the same bit is MEMF_CONFORM, which makes conforming code, which code at any ring can call, and which runs at the caller's ring, as FPU$'s functions do), MEMF_RDONLY (08h) read-only data (or execute-only code), and MEMF_USER (10h) DPL 3 selectors, for programs at ring 3.  CPU_ALLOC also takes MEMF_LOW (20h) to allocate below 1Mb, MEMF_HIGH (40h) to allocate from the top of the last free block that's big enough, and MEMF_AT (80h) to allocate the memory at DX:CX; otherwise, it allocates from the first free block that's big enough, conventional or extended.
- **Selectors**: CPU_MAP maps existing memory, CPU_ALIAS creates another selector for the same memory as an existing one, with different access rights (see [Code Aliases](#aliases)), CPU_UNMAP frees either, and CPU_SETLIM changes the length that a selector covers, keeping the selector.
- **Debuggers**: CPU_SEGINFO, CPU_RWMEM, and CPU_SYSREGS never change CPU$'s state, so they work even when CPU$ itself was interrupted.  An address is in real-mode form unless ADDR_SEL (01h) says its segment is a protected-mode selector (in either mode) or ADDR_PHYS (04h) says it's a physical address (its "segment" holds bits 16-31).  CPU_SEGINFO returns a segment's base address and limit, or with ADDR_RIGHTS (08h), its descriptor's access rights and extended byte.  CPU_RWMEM copies CX bytes from the address to ES:DI, or with ADDR_WRITE (02h), from ES:DI to the address, which must be within the segment's limit; it can write to a code segment (eg, to store a breakpoint).  CPU_SYSREGS stores the GDTR and IDTR (as SGDT and SIDT do), and returns the MSW, LDTR, and TR; the 8086 driver returns ERR_INVALID, which tells a debugger that the processor has only one mode.
- **Faults**: CPU_SETFAULT gives a fatal protected-mode exception to a handler (eg, the kernel's, or a debugger's), before CPU$ reports it and stops the machine.  The handler is entered with the registers as they were, interrupts disabled, and SS:SP pointing to a far return address, the vector, the error code, and an interrupt frame for the faulting instruction.  A handler that can't handle the exception declines it by returning (RETF) with the registers and stack as they were.  Before stopping the machine, CPU$ offers the halt to the handler, as the same exception with FAULT_HALTED (80h) in the vector's high byte: a debugger can accept it by never returning, and any other handler declines it.  See [Faults](#faults).
- **Ring 3 support**: CPU_SETSTACK sets the ring 0 stack that the processor switches to when an interrupt or exception takes ring 3 code to ring 0, and CPU_SETLDT makes a session's LDT the active one, so that the selectors that the other functions allocate, free, and resolve are in that session's LDT (see [Running Programs at Ring 3](#ring3)).  In real mode, CPU_SETSTACK returns ERR_INVALID, and CPU_SETLDT does nothing.

CPU_GETINFO's flags are CPUF_PM (01h), set when the processor is in protected mode, CPUF_PMOK (02h), set when the 80286 driver stayed (so CPU_PMODE is available), and CPUF_HWTYPE (C0h), the processor's own type (CPU_HWTYPE), which AL (CPU_TYPE) understates with `CPU=8088`.

DDINT_CPU is the entry point in either mode, since a far call through segment 50h has the same address in protected mode (see [Mode-Independent Code](#modeless)), and it doesn't use up an interrupt vector.  In protected mode, segment 50h is a DPL 0 code segment, so only ring 0 code (the drivers, the kernel, and programs run with `RING=0`) can call CPU$; programs at ring 3 use DOS functions instead (eg, DOS_MEM_ALLOC, DOS_UTL_ALIAS, and DOS_UTL_MAPSEG).

### Memory Map

Physical memory on a 2Mb PC AT:

| Address | Length | PMB type | Contents |
|---------|--------|----------|----------|
| 000000h | 1K | USED | Real-mode interrupt vector table |
| 000400h | 256 | USED | ROM BIOS data area (segment 40h) |
| 000500h | 1136 | USED | BASIC-DOS low memory (also segment 40h, from offset 100h): CPU_TYPE (512h), CPU_HWTYPE (513h), CPU_ARENA (514h), the diskette parameter table (522h), the DDINT entry points (530h, called through segment 50h, starting with DDINT_CPU at 0050:0030h), and two disk buffers |
| 000970h | | USED | Drivers: CPU$ (first), NUL, VKD$, ..., then BASDOS.COM and its tables |
| | | FREE | The rest of conventional memory |
| 0A0000h | 384K | RSVD | Video memory, adapter ROMs, and the system ROM (not RAM) |
| 100000h | 64K | SYS | CPU$ system area (the HMA; see below) |
| 110000h | 1344K | FREE | The rest of extended memory |
| 260000h | | | End of memory |

The PMB types (PMBTYPE_* in cpu.inc) are FREE (0), USED (1, allocated by CPU_ALLOC), SYS (2), and RSVD (3).  The end of conventional memory comes from the BIOS, so a machine with less than 640K (or a `MEMSIZE=` line) has a larger RSVD block.

#### The System Area {#sysarea}

CPU$ keeps its data in the first 64K of extended memory, which (with A20 enabled) is addressable in real mode as segment FFFFh, and in protected mode with a selector whose base is FFFF0h, so the same offsets work in both modes:

| Offset | Linear | Contents |
|--------|--------|----------|
| 0000h | 0FFFF0h | Last 16 bytes of the ROM BIOS (unusable) |
| 0020h | 100010h | CPU$'s variables |
| 00D0h | 1000C0h | CALL 5 trampoline: `JMP 0000:00C0h` (see below) |
| 00E0h | 1000D0h | GDT: 256 descriptors (the fixed ones first) |
| 08E0h | 1008D0h | PMB table (128 entries of 32 bytes) |
| 18E0h | 1018D0h | The self-test's IDT (256 gates, which return to real mode) |
| 20E0h | 1020D0h | The protected-mode IDT (256 gates; see [Protected-Mode Interrupts](#interrupts)) |
| 28E0h | 1028D0h | LDTs: one for each of 32 sessions, 96 descriptors each |
| 88E0h | 1088D0h | TSS (44 bytes, 80286 format), only for its ring 0 stack |
| A0E0h | 10A0D0h | GDT: identity selectors A000h-F800h, every 800h (see below), through 10F8D7h |

A PSP's CALL 5 (a far call to F01D:FEF0h, for example) reaches 0:00C0h only by wrapping around at 1Mb, so with A20 enabled, it lands at 1000C0h instead; like DOS 5 with DOS=HIGH, CPU$ puts a far jump to 0:00C0h there.  In protected mode, PSP_FCSEG is SEL_CALL5 instead, a DPL 3 call gate to that jump (a far call through a gate ignores its offset, so PSP_SIZE keeps the value that CP/M programs read as their memory size).

On every function call, CPU$ checks that A20 is still enabled, and re-enables it if necessary (eg, if a program used the BIOS block move function, INT 15h function 87h, which turns A20 off).

#### Fixed GDT Selectors

| Selector | Base | Use |
|----------|------|-----|
| 00h | | Null selector |
| 08h | 0FFFF0h | Data: the system area (so offsets match segment FFFFh) |
| 10h | | The active session's LDT |
| 18h | 000970h | Code: CPU$ |
| 20h | 000000h | Data: the first 64K (interrupt vectors, BIOS data, BASIC-DOS low memory) |
| 28h | | Data: the caller's stack, while switching modes |
| 30h, 48h | | Data: scratch |
| 38h | | Call gate (DPL 0) to CPU$'s functions (unused, since DDINT_CPU works in either mode) |
| 40h | 000400h | Data: the BIOS segment (40h), so code that uses segment 40h works in either mode |
| 50h | 000500h | Code: the DDINT segment (50h), so the DDINT entry points have the same addresses in either mode |
| 58h | 000000h | Code: just the CALL 5 jump at 0:00C0h |
| 60h | | SEL_CALL5: call gate (DPL 3) for a PSP's CALL 5 |
| 68h | 1088D0h | The TSS |
| A000h-B800h | A0000h-B8000h | Data: identity selectors for video memory, every 800h (DPL 3, so that ring 3 programs can draw directly) |
| C000h-F800h | C0000h-F8000h | Code: identity selectors for the adapter and system ROMs, every 800h, so the ROM BIOS can run at ring 0 with its own segments (eg, F000h) |

Selectors 70h-7F8h (GDT) and 04h-2FCh (the active session's LDT) are allocated by CPU_ALLOC, CPU_MAP, and CPU_ALIAS.  All descriptors are 80286-format (the 80386 fields are zero, except bits 31-24 of the base, for blocks above 16Mb) and DPL 0 (unless MEMF_USER is set).  The GDT's limit extends through the identity selectors, so the descriptors between its first 256 entries and A000h overlap the rest of the system area; none of them is present, so loading one (eg, a real-mode segment by mistake) faults.

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

The cost is a fixed number of PMBs (128).  The 8086 driver's arena is the MCB chain itself: programs on an 8086 expect to see MCBs, and conventional memory is all there is.  With the 8086 driver, CPU_QUERY describes each MCB with a PMB (whose PMB_SEL is the block's segment).

For debuggers that can't call CPU$ (eg, the PCjs Debugger, whose `d dos` command lists the arena the way DEBUG's DM does), whichever driver stays stores the real-mode address of its arena in CPU_ARENA (0:514h): the 8086 driver's first MCB, or the 80286 driver's PMB table (FFFF:08E0h).

#### Memory and DOS {#dosmem}

From the moment CPU$ initializes, everything that runs during the boot (devinit, each driver, and sysinit) claims the memory it uses from CPU$, and moves memory only with CPU_MOVE, so neither devinit nor sysinit computes a segment from an address.  After the boot, DOS's memory functions are calls to CPU$: DOS_MEM_ALLOC calls CPU_ALLOC (so in protected mode, a block can be anywhere in conventional or extended memory) and CPU_SETBLK, DOS_MEM_FREE calls CPU_FREE, DOS_MEM_REALLOC calls CPU_REALLOC, a program's blocks are freed with CPU_FREEALL when it ends, and DOS_UTL_QRYMEM (for MEM) uses CPU_QUERY.  There's no MCB chain for programs to walk, other than the 8086 driver's, and MEM's total memory (which DOS_MSC_GETVARS returns in AX) includes extended memory.

### Switching Modes

To test protected mode, CPU$ switches to it and back.  An 80386 returns to real mode by clearing PE.  An 80286 can't, so before switching, CPU$ sets the CMOS shutdown code to 0Ah and stores its return address in 40:67h, and to return, it resets the processor through the 8042, as the BIOS's own block move (INT 15h function 87h) does; the BIOS sees the shutdown code and jumps through 40:67h without initializing anything else.  Because the shutdown code is set before switching, a "triple fault" (which resets the processor) also returns to CPU$, and every gate in the self-test's IDT returns to real mode, too, so a bug in protected mode makes the test fail instead of hanging the machine.  The test writes and reads back a word at 110000h, which real mode can't reach; CPU$ stays loaded only if that works.

CPU_PMODE switches to protected mode the same way, but for good: it never returns to real mode.

### Protected-Mode Initialization {#pminit}

On an 80286 or later, when the 80286 CPU$ stays loaded, BASIC-DOS switches to protected mode during devinit, right after CPU$ initializes, and never switches back:

1. **CPU$ initializes in real mode**, as the first driver, and devinit loads BASDOS.COM (the kernel) while it can still use the boot code.
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
- **INT 13h**: the BIOS's disk functions assume that ES:BX is a real-mode address, so FDC$, which makes every disk transfer, gives the BIOS an address that works in both modes: for the diskette BIOS, which turns ES:BX into a DMA address, an offset from segment 40h (or a sector buffer of its own, for a buffer more than 64K above it), and for the fixed disk BIOS, a selector of the buffer's own, with a zero offset.
- **Vectors 08h-0Fh** are also software interrupts sometimes (eg, the AT BIOS's IRQ 9 handler does `INT 0Ah`), so an exception whose return address follows an `INT` for its vector is treated as one.
- **Null selectors in the ROM**: the BIOS loads DS with 0 to address the vectors (eg, `LDS SI,[78h]` with DS = 0), so a general protection fault with a zero error code, in the ROM, while DS or ES holds a null selector, is retried with a selector for the first 64K.  BASIC-DOS's own code gets no such fix.

#### Faults {#faults}

Any other exception (including an INT 3, such as a failed DEBUG assertion, or a software interrupt with no handler that CPU$ can call) goes to the fault handler (see CPU_SETFAULT), which is the kernel's unless a debugger has replaced it:

- **In the current program's own code** (or any block that the program owns, such as one of COMMAND's BASIC code blocks), DOS displays `CPU fault vv (EC=xxxx) at cccc:iiii` and ends the program with exit code 255 and EXTYPE_FAULT, as it does for a divide error, and the system continues.
- **Anywhere else** (eg, in the kernel, a driver, or the ROM), the exception is fatal: CPU$ prints the same `CPU fault` line, followed by `System halted`, offers the halt to the fault handler, and unless a debugger takes it, stops the machine.
- **With DEBUG.COM** loaded as a driver, DEBUG.COM passes each exception on to the kernel unless its VT command traps the vector, and stops for any that the kernel declines, so that G can retry it (eg, after a fix); it then accepts CPU$'s halt, so that it never gives up control (see [DEVICE](../../bdman/cfg/#device)).

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

- **Video memory** comes from VKD$ (IOCTL_GETMODE with CL = 1 returns the context's video memory in DX, which in protected mode is a DPL 3 identity selector).
- **The tick count** (for RANDOMIZE, SOUND, and PLAY) comes from DOS_UTL_GETTIME with AL = 1, MEM's total memory from DOS_MSC_GETVARS, and RESTART's session list from DOS_UTL_QRYSCB.
- **Sounds** start and stop through CLOCK$ (DOS_UTL_SOUND), rather than with IN and OUT.
- **BASIC code** runs from code blocks through their code aliases (see [Code Aliases](#aliases)), and DEF SEG gets a selector from the kernel (see [DEF SEG](#defseg)).
- **Blocks** (for code, text, variables, and strings) come from DOS_MEM_ALLOC with MCBTYPE_HIGH, so in protected mode, they come from the top of extended memory.

### Code Aliases {#aliases}

A protected-mode segment is either code (executable, and at most readable) or data (readable, and perhaps writable), so memory that's both written and executed needs two selectors.  CPU_ALIAS creates the second one: given a selector, it returns a new selector for the same base and limit, with the access rights selected by MEMF_CODE, MEMF_RDONLY, and MEMF_USER, and CPU_UNMAP frees it.

A block's own code alias (CPU_ALIAS with just MEMF_CODE, for the selector that CPU_ALLOC returned for the block) is created only once, with the block's DPL, and is freed with the block, so nothing else has to keep track of it (and it must never be freed with CPU_UNMAP).  Programs get it from DOS_UTL_ALIAS (27h; see [Utility Functions](../util/#memory)), since ring 3 code can't call CPU$, and with AL = 1, the same function does the reverse, returning the block's own selector for its code alias, since a code selector isn't writable (eg, so that a debugger can store a breakpoint in a program's code); in real mode, a block's code alias is its segment.

COMMAND.COM compiles BASIC into code blocks that it allocates as data, and runs them (and transfers from one to another) through their code aliases.  Generated code that writes to its own block (eg, a double's result) gets the block's data selector from the block itself, rather than from CS.

#### Loading Programs {#exec}

In protected mode, the DOS_PSP_EXEC functions run COM and NE programs, but not "MZ" EXE files:

- **COM programs**: a COM program's code and data are in one block (its PSP block).  CS comes from the block's code alias, and DS, ES, and SS come from the block's data selector.  A program that sets a vector with DS:DX, as COM programs often do, would give it a data selector, so when DS is the program's PSP block, DOS_MSC_SETVEC uses the block's code alias instead, which in real mode is the same segment.
- **MZ EXE files**: an EXE file's relocations are paragraph arithmetic, which doesn't work with selectors, so in protected mode, the DOS_PSP_EXEC functions refuse them with ERR_NOMEMORY, which COMMAND reports as "Unable to load X".
- **NE programs**: an NE ("new executable") file lists each segment's type and size, and its relocations refer to segments by number, so each segment gets a block of its own, owned by the program's PSP, and a selector whose limit fits the segment exactly (for a code segment, the block's code alias).  The program must be marked PROTMODE, with FIXED segments, no imports, and only internal relocations; it starts with DS and ES addressing its PSP, as an MZ program does.  In real mode, an NE file runs its MS-DOS stub, like any MZ EXE file.

`TESTS\BIN\PRIMES.EXE` is an NE program, linked by LINK4 (see `tests/primes/PRIMES.DEF` and the [build tools](../../../software/src/tools/README.TXT)), with the real-mode program as its MS-DOS stub, so it runs in either mode.  LINK4 makes a segment code only if its class is `CODE`, and requires a DGROUP.

### DEF SEG, PEEK, and POKE {#defseg}

DEF SEG accepts any segment, which in protected mode isn't a selector, so COMMAND.COM gets a selector for the segment's 64K from the kernel (DOS_UTL_MAPSEG; see [Utility Functions](../util/#memory)), which each session keeps one of.  The selector is writable for video memory (A000h through BFFFh), and read-only everywhere else, including low memory and the ROMs, so PEEK works, but POKE is an "Illegal function call".  DEF SEG with no segment (BASIC's own data) is readable and writable, as before.  In real mode, none of these restrictions apply.

### Running Programs at Ring 3 {#ring3}

In protected mode, unless CONFIG.SYS has `RING=0` (see [CONFIG.SYS](../../bdman/cfg/#ring)), every session's first program (eg, COMMAND.COM) and every program that the DOS_PSP_EXEC functions start runs at ring 3, with CPU$, the drivers, and the kernel at ring 0, so that a program can use only the memory it's given, and can't use privileged instructions.

- **Selectors**: the blocks that DOS_MEM_ALLOC allocates for a ring 3 program (including the blocks that a program is loaded into) have DPL 3 selectors (MEMF_USER) in its session's LDT (MEMF_LDT), and a program's CS has RPL 3, which is how DOS knows to start it at ring 3.
- **LDTs**: each session has its own LDT, so a program can't name another session's memory; the kernel makes a session's LDT the active one (CPU_SETLDT) whenever it switches sessions.  Selectors repeat from one session's LDT to the next, so a ring 3 program's PSP doesn't identify it on its own, and CPU$ stores the owner of each of its blocks as an [owner ID](#owners) that includes the session number, which is what CPU_FREEALL frees by.
- **Ring 0 stacks**: the TSS is used only for its ring 0 stack (CPU_SETSTACK), which the processor switches to when an interrupt takes ring 3 code to ring 0.  A program's ring 0 stack is its parent's stack, where the parent waits for it to end, so nested programs need no stacks of their own; a session's first program, which has no parent, uses a 1K ring 0 stack that the kernel allocates for each session.
- **DOS calls**: a DOS call's parameters on the caller's stack (eg, for DOS_UTL_PRINTF and DOS_UTL_SPRINTF) are read through a ring 0 alias of the caller's stack, and a CALL 5 works at ring 3, too, since SEL_CALL5 is a DPL 3 gate.
- **CTRL-C and critical error handlers** (INT 23h and INT 24h) run at ring 3, on the stack of the program that called DOS, and return to the kernel through a ring 3 stub.  A critical error handler gets a copy of the device header (since it can't read the driver's memory), and a CTRL-C handler can continue the DOS call (with any registers it changed) or end the program, as at ring 0; either way, the kernel makes sure the program stays at ring 3, with IOPL 0.
- **Interrupt vectors**: the IDT is shared by every session and by ring 0 code, so a ring 3 program's handler can't go in a gate.  Instead, when a ring 3 program sets a vector (other than INT 22h-24h, which each session has its own of), the kernel puts a gate of its own there, which reflects the interrupts that ring 3 code in the program's session issues to the program's handler, at ring 3, and passes all others to the previous handler.  A ring 3 program that gets a vector (eg, to chain to it) gets the address of a ring 3 stub that passes the interrupt to the previous handler.  The kernel removes the program's handlers when it ends.  So, for example, an INT 21h hook sees the DOS calls of the programs it runs, but not the kernel's own.
- **FPU$**: its functions are mapped with conforming code selectors, so the kernel and programs at ring 3 call them through the same FPUTBL, and they run at the caller's ring (see [Floating-Point Interface](../fpu/)).
- **DEBUG.COM** as a driver (at ring 0) can stop and resume ring 3 programs with every command.  As a program at ring 3, it can't call CPU$, so it uses DOS functions and the 80286's unprivileged instructions instead (see [Installable Drivers](../dev/#installable-drivers)), and it can reach only the memory that ring 3 can (eg, the program's own, not DOS's, the drivers', or the BIOS data area); it has no DM, DS (selector), or LN commands, no `&`, `#`, or `%` addresses, and no system registers, and T steps over an INT, as P does.

### The Protected Mode Demo {#pmdemo}

The [Protected Mode demo](/demos/mmu/) is a 2Mb PC AT with a Color Display and a DEC VT100 on COM2 for DEBUG.COM, and its [Debugger](/demos/mmu/debugger/) page is the same machine with the PCjs Debugger.  It boots the BASIC-DOS Protected Mode Demo diskette, whose CONFIG.SYS has no `CPU=8088` line (pressing **Esc** at the boot prompt boots the hard disk instead, whose CONFIG.SYS has `CPU=8088`).  Everything after CPU$ initializes runs in protected mode, and COMMAND.COM runs at ring 3, with C: as the default drive.  Commands, BASIC programs, and NE programs work (eg, `PRIMES` in `C:\TESTS\MISC`), but MZ EXE files don't (see [Loading Programs](#exec)).

DEBUG.COM, loaded as a driver, shows each fault on the VT100, with the registers at the faulting instruction (adding /H to its line in CONFIG.SYS stops it as soon as it's loaded, so that you can set breakpoints before booting continues).  The B: drive has the BASIC-DOS Tests diskette, so `B:\TESTS\MISC\FAULT n` causes exception *n* (0, 1, 3-6, 12, or 13), or with -1, a fatal fault in the kernel, to see how BASIC-DOS responds: DOS reports a divide error (0) or an overflow (4) and ends the program, a single-step trap (1) or a breakpoint (3) resumes (unless DEBUG.COM stops there), and DOS ends the program for the rest (eg, `CPU fault 0D`), unless DEBUG.COM's VT command traps the vector.

### Debugging {#pmdebug}

- DEBUG.COM works in either mode: an address can start with `&` (real mode), `#` (protected mode), or `%` (a physical address), `DS selector` displays a selector's descriptor, R also shows the MSW, GDTR, and IDTR (and in protected mode, the LDTR, TR, and each segment register's base and limit), and `LN [address]` shows the name of the memory an address is in (see [DEVICE](../../bdman/cfg/#device)).
- The PCjs Debugger's `r` shows each segment register's selector with its base and limit in protected mode (eg, `CS=0018[000970,FFFF]` in CPU$), along with the GDTR, IDTR, LDTR, and TR, and its `d dos` command lists CPU$'s arena, in either mode (see [Physical Memory Arena](#arena)).

### Limitations {#limits}

- **MZ EXE files** don't run in protected mode (see [Loading Programs](#exec)).  They could run with the processor switched back to real mode on an 80286 (as in OS/2's DOS session, with other sessions waiting), or in virtual-8086 mode on an 80386; neither is implemented.
- **The 80386** runs the 80286 code (with no virtual-8086 mode, paging, or 32-bit segments), and only IBM's PC AT BIOS is tested in protected mode.
- **BIOS functions**: the ones that the drivers use work in protected mode, but the rest haven't been tried, and a few (eg, INT 15h functions 87h and 89h, which switch modes themselves) would need CPU$ replacements.
- **Interrupt hooks at ring 3**: a ring 3 program's handler sees only the interrupts that ring 3 code in its own session issues, so a hook of an interrupt that ring 0 code issues (eg, INT 1Ch, from the BIOS's timer handler, or INT 13h, from FDC$) never runs.  And there are only 8 reflected vectors for all sessions; with none free, a vector is set (and returned) as it would be at ring 0.
- **CPU$ from ring 3**: ring 3 code can't call CPU$, so programs that do (eg, CPUTEST) need `RING=0`, and DEBUG.COM run as a program has fewer commands at ring 3 (see [Running Programs at Ring 3](#ring3)).
- **I/O at ring 3**: programs run with IOPL 0, so a program that uses IN, OUT, CLI, or STI needs `RING=0`.
- **Table sizes**: the 128 PMBs, 256 GDT entries, and 32 LDTs of 96 entries each are fixed.  A block keeps its selectors when CPU_REALLOC shrinks it, so a program loaded into a large free block holds one LDT selector for every 64K of that block (eg, 16 for COMMAND.COM, loaded into a 1Mb block).
- **Identity selectors** exist only every 800h from A000h to F800h, so a ROM segment that isn't a multiple of 800h (eg, F600h, the PC's ROM BASIC) can't be reflected to.
- **A20** stays enabled, so programs that depend on addresses wrapping at 1Mb could break (eg, EXEPACK-compressed programs loaded in the first 64K report "Packed file is corrupt").
- **COMMAND.COM's shared code** includes some variables, so it can't be one read-only code selector that every copy shares.
- **DEF SEG** makes only video memory and BASIC's own data writable, even for blocks that belong to the session.

{% include footer.html prev="Data Structures:../data/" next="" %}
