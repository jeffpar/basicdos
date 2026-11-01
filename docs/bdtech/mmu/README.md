---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Protected Mode and Memory Management (Design)
permalink: /docs/bdtech/mmu/
---

{% include header.html %}

**NOTE**: This is a design document for work in progress on the `mmu` branch.  Everything here is tentative; [Phase 1](#phases) has been implemented, CPU$ now manages all memory on every processor (see [The CPU$ Driver](#cpu)), and on an 80286, BASIC-DOS switches to protected mode while its drivers initialize, and stays there: the kernel initializes, and COMMAND.COM starts and runs commands and some programs, in protected mode (see [Protected-Mode Boot](#pmboot)).  The [Protected Mode demo](/demos/mmu/) runs the current CPU$ on a 2Mb PC AT with the PCjs Debugger, and summarizes where things stand.

### Goals

- Let BASIC-DOS use the extended memory and protected mode of an 80286 or 80386, while the same binaries still run on an 8086 or 8088 (with no extra memory used there).
- Keep all knowledge of descriptors, selectors, and physical memory in one built-in driver, **CPU$**, which loads first, determines the processor type, and on a protected-mode processor, manages a physical memory arena and the GDT, IDT, and LDT.
- Restructure the rest of BASIC-DOS (drivers, kernel, and COMMAND.COM) so that it can run in either mode, using CPU$ to map existing blocks of code and data to selectors, and to allocate and free extended memory.

### Target and Test Machines

The design targets the IBM PC AT: `ibm5170` (80286, AT BIOS revision 3) with `--ram=2M`, which pc.js now splits into 640K of conventional memory (0-9FFFFh) and 1408K of extended memory (100000h-25FFFFh), like the PCjs 2048K PC AT machines.  On the `mmu` branch, [boot.sh](../../../boot.sh) passes `--ram=2M` for every configuration.

Every change is tested on three machines, with `tools/tests/mmutest.sh`, which runs quick.sh's floppy tests and CPUTEST on each:

| Name | Machine | CPU$ |
|------|---------|------|
| `8088` | IBM PC XT (`ibm5160`) | The 8086 CPU$ stays (CPU type 0, hardware type 0) |
| `real` | 2Mb PC AT with `CPU=8088` in CONFIG.SYS | The 8086 CPU$ stays (CPU type 0, hardware type 2), so BASIC-DOS runs in real mode with A20 disabled |
| `pm` | 2Mb PC AT without `CPU=8088` | Switches to protected mode (for now, the boot stops in sysinit, so this test fails) |

Because real mode is the only mode they've been tested in, every other configuration that boots on a PC AT or DeskPro 386 (the demo diskettes and hard disk, the test configurations that boot.sh uses, and mk.sh's build configuration) has `CPU=8088` in its CONFIG.SYS; only the `pm` test, `tools/tests/pmboot.sh`, and the Protected Mode demo leave it out.  The 80386 path (which returns from its self-test to real mode by clearing PE instead of resetting the CPU) is still tested occasionally with `compaq386` (a COMPAQ DeskPro 386), but only the PC AT is a target for now.

### The CPU$ Drivers {#cpu}

CPU$ manages all memory, on every processor, so BASDEV.COM starts with two CPU$ drivers, of which exactly one stays loaded (a device name only has to be unique among the drivers that stay, since only they are linked into the chain): the 80286 driver (286dev.asm), followed by the 8086 driver (x86dev.asm).  The 80286 driver, which is initialized first, determines the processor type:

1. An 8086 or 80186 decrements SP before PUSH SP stores it, whereas an 80286 or later stores the original value.
2. An 80186 masks shift counts to 5 bits, so shifting 1 left 33 times leaves 2 (instead of 0 on an 8086).
3. In real mode, an 80286 always clears FLAGS bits 12-15, whereas an 80386 lets software set bits 12-14 (IOPL and NT).

It stores the result in CPU_HWTYPE (0:513h) and CPU_TYPE (0:512h), as one of the CPUTYPE_* values in cpu.inc (0 = 8086/8088, 1 = 80186/80188, 2 = 80286, 3 = 80386 or later).  A `CPU=8088` line in CONFIG.SYS makes CPU$ store 0 (8086/8088) in CPU_TYPE and act as it does on an 8088, without enabling A20; CPU_HWTYPE is still the processor's own type, for software that must know how the processor runs instructions (eg, DEBUG.COM's disassembler).

Neither CPU$ can be skipped (devinit ignores `SKIP=CPU$`).  The one that stays makes its functions available through DDINT_CPU (0050:0030h), a 5-byte far jump in low memory like the other DDINT entry points, which devinit initializes to `STC`, `RETF`, so that a call fails (with carry set) until CPU$ initializes:

- **The 80286 driver** stays if the processor is an 80286 or later, the BIOS reports at least 64K of extended memory (INT 15h function 88h), A20 can be enabled (with the 8042 keyboard controller, as on a PC AT), and a switch to protected mode and back succeeds.  It keeps everything but its initialization code (about 3K), enables A20 permanently, and builds its [arena](#arena) (a table of PMBs) and descriptor tables in the 64K system area.  Otherwise (or with `CPU=8088`), it unloads itself, and devinit moves the drivers after it down (see [Claiming Memory at Boot](#claiming)), so whichever driver stays is at 0970h.
- **The 8086 driver** stays unless CPU$ is already loaded.  It manages memory with a chain of MCBs, as DOS always has, starting in the paragraph after its code (about 1K), so every block that's allocated after it (eg, the other drivers, the kernel, and programs) has an MCB in the paragraph before it, which programs that walk the MCB chain can see.

The 80286 driver, which always initializes first, also applies any `MEMSIZE=` line (see [CONFIG.SYS](../../bdman/cfg/#memsize)), by lowering the BIOS's MEMORY_SIZE (which INT 12h returns), so either driver's arena ends there.  Either way, devinit claims what it's using as soon as CPU$ initializes (see [Claiming Memory at Boot](#claiming)).

The one that stays also provides DDINT_GETVEC and DDINT_SETVEC (see [Device Drivers](../dev/)), which devinit also initializes to `STC`, `RETF`: the 8086 driver points them at its own code (which reads and writes the vector table) when it initializes, and the 80286 driver at its protected-mode code when it switches to protected mode (see [Protected-Mode Boot](#pmboot)), so either way, before any other driver initializes.

#### Functions

Call DDINT_CPU with a function number in AH.  Physical addresses and lengths are 32-bit byte values: addresses in DX:CX and lengths in SI:DI (high:low).  Every function runs with interrupts disabled, preserves BX, SI, DI, BP, DS, and ES, and returns carry clear on success, or carry set with an error code in AX.

| AH | Function | Inputs | Outputs |
|----|----------|--------|---------|
| 00h | CPU_GETINFO | | AL = CPU type, AH = CPUF_* flags (bits 6-7 = CPU_HWTYPE), DX:CX = length of largest free block |
| 01h | CPU_ALLOC | AL = MEMF_* flags, BX = owner, SI:DI = length | AX = first selector (0 if MEMF_NONE), DX:CX = address |
| 02h | CPU_FREE | DX:CX = block | |
| 03h | CPU_MAP | AL = MEMF_* flags, DX:CX = address, SI:DI = length | AX = first selector, CX = number of selectors |
| 04h | CPU_UNMAP | BX = first selector, CX = number of selectors (0 = 1) | |
| 05h | CPU_QUERY | BX = PMB number (0 = first), or -1 for block DX:CX; ES:DI -> 32-byte buffer | PMB copied to ES:DI |
| 06h | CPU_ALIAS | AL = MEMF_* flags, BX = selector | AX = new selector, DX:CX = base address |
| 07h | CPU_PMODE | (none) | Protected mode, for good: CS, DS, ES, and SS are now selectors for the same memory, and AX = a data selector for the caller's CS (see [Protected-Mode Boot](#pmboot)) |
| 08h | CPU_REALLOC | DX:CX = block, SI:DI = new length | |
| 09h | CPU_MOVE | ES:BX -> MOVEPKT (source address, destination address, and length, all dwords) | |
| 0Ah | CPU_SETBLK | DX:CX = block, AL = MCBTYPE_*, BX = owner (non-zero), ES:SI -> 8-character name (SI = 0 for none) | |
| 0Bh | CPU_FREEALL | BX = owner | |
| 0Ch | CPU_SETLIM | BX = selector, SI:DI = new length (1 to 64K) | |
| 0Dh | CPU_SEGINFO | AL = ADDR_* flags, BX = selector (or segment) | DX:CX = base address, AX = limit (or with ADDR_RIGHTS, AL = access rights, AH = extended byte) |
| 0Eh | CPU_RWMEM | AL = ADDR_* flags, BX:SI = address, CX = length, ES:DI -> buffer | |
| 0Fh | CPU_SYSREGS | ES:DI -> 12-byte buffer | GDTR and IDTR stored at ES:DI; AX = MSW, CX = LDTR, DX = TR |
| 10h | CPU_SETFAULT | DX:CX = fault handler (0:0 for none) | DX:CX = previous handler |

A *block* (DX:CX) is the address that CPU_ALLOC returned, or DX = -1 and CX = the selector (or segment) that it returned, which is what DOS has (eg, in ES for DOS_MEM_FREE).  CPU_SETBLK records a block's owner, type, and name for DOS (in PMB_OWNER, PMB_MCBTYPE, and PMB_NAME, or with the 8086 driver, in the block's MCB), which MEM and DEBUG's DM show; CPU_FREE and CPU_FREEALL clear them, and CPU_FREEALL frees every block that an owner has (DOS uses it when a program ends).

MEMF_LDT (01h) requests LDT selectors instead of GDT selectors, MEMF_CODE (02h) requests execute/read code segments instead of read/write data segments, MEMF_NONE (04h) makes CPU_ALLOC allocate memory without any selectors, MEMF_RDONLY (08h) makes data read-only (or code execute-only), and MEMF_USER (10h) makes the selectors DPL 3 (for programs at ring 3) instead of DPL 0.  CPU_ALLOC also takes MEMF_LOW (20h) to allocate below 1Mb, MEMF_HIGH (40h) to allocate from the top of the last free block that's big enough, and MEMF_AT (80h) to allocate the memory at DX:CX (which must be free); otherwise, it allocates from anywhere in memory, conventional or extended (as DOS_MEM_ALLOC does).  CPU_ALIAS creates a new selector, with the access rights that its MEMF_* flags select, for the same memory as an existing one (it copies the base and limit), and CPU_UNMAP frees it; see [Code Aliases](#aliases).  CPU_SETLIM changes the length that a selector covers (its limit), keeping the selector, so that anything that already holds it (eg, a driver's header, the driver chain, and IDT gates) sees the change; fixed GDT selectors can't change.

Every function works the same way in either driver and in either mode, so callers needn't check which is which: in real mode, CPU_ALLOC, CPU_MAP, and CPU_ALIAS return the memory's segment instead of a selector (CPU_ALLOC returns 0 for a block above 1Mb, and CPU_MAP fails with ERR_INVALID unless the memory is below 1Mb and paragraph-aligned), a segment is its own alias, and CPU_UNMAP has nothing to do.  CPU_REALLOC changes a block's length (rounded up to a multiple of 16): a shorter block frees its end, and a longer one takes what it needs from the next block, which must be free and long enough (ERR_NOMEMORY otherwise, with the block unchanged); its selectors don't change.  CPU_MOVE copies any amount of memory between two physical addresses, correctly even if the source and destination overlap; in real mode, both must be below 1Mb.  With the 8086 driver, every block has an MCB in the paragraph before it, so CPU_ALLOC with MEMF_AT needs that paragraph to be free too, and CPU_QUERY describes each MCB with a PMB (whose PMB_SEL is the block's segment).  A block of more than 64K gets one selector for every 64K (each 8 more than the last, so that `selector + 8 * n` addresses the *n*th 64K), and the last one's limit covers the rest.  CPU_ALLOC rounds lengths up to a multiple of 16, so every block starts on a paragraph boundary; CPU_MAP maps exactly the requested length.  Errors are ERR_INVALID (bad function, zero length, unknown PMB, a selector that can't be unmapped, or one that isn't in use for CPU_ALIAS), ERR_NOMEMORY (no block big enough, with DX:CX = length of the largest free block; or no free PMB or descriptors), and ERR_BADADDR (a block that CPU_ALLOC didn't return, for CPU_FREE, CPU_REALLOC, CPU_SETBLK, or CPU_QUERY).

CPU_SETFAULT gives a fatal protected-mode exception to a handler (eg, DEBUG.COM's), instead of the 80286 driver reporting it (`CPU$ fault`) and stopping the machine, unless it occurred in CPU$ or in the handler's own code.  The handler is entered with the registers as they were, interrupts disabled, and SS:SP pointing to the vector, the error code, and an interrupt frame for the faulting instruction; for a software interrupt with no handler, those are its vector (0FFh if unknown), the caller's AX, and the INT itself.  The 8086 driver keeps the handler too, but never calls it, since real-mode exceptions go through the vectors.

CPU_SEGINFO, CPU_RWMEM, and CPU_SYSREGS are for debuggers (eg, [DEBUG.COM](../../bdman/cfg/#device)), so they never change CPU$'s state, and work even when CPU$ itself was interrupted (eg, at a breakpoint in CPU$); CPU_RWMEM borrows a scratch selector, and restores its descriptor afterward.  An address (*segment*:*offset*) is in real-mode form, unless ADDR_SEL (01h) is set, in which case its segment is a protected-mode selector, in either mode: any present descriptor in the GDT (including the identity selectors) or the LDT.  With ADDR_PHYS (04h), the address is a physical address instead (its "segment" holds bits 16-31), which the 8086 driver accepts only below 1Mb.  With ADDR_RIGHTS (08h), CPU_SEGINFO returns a selector's access rights byte in AL and its descriptor's extended byte in AH, instead of its limit (zero for a real-mode segment), for a debugger's DS command; the access rights can't go in another register, since cpu_entry restores every register but AX, CX, and DX.  CPU_SEGINFO returns a segment's base address and limit (FFFFh for a real-mode segment).  CPU_RWMEM copies CX bytes from the address to ES:DI, or with ADDR_WRITE (02h), from ES:DI to the address, which must be within the segment's limit (and in real mode, below 1Mb); it writes through a data selector of its own, so it can store a breakpoint in a code segment.  CPU_SYSREGS stores the GDTR and IDTR as SGDT and SIDT do (a 16-bit limit and a 24-bit base, in 6 bytes each), and returns the MSW, LDTR, and TR (the last two are zero in real mode).  The 8086 driver accepts only real-mode addresses, and CPU_SYSREGS returns ERR_INVALID, which also tells a debugger that the processor has only one mode.

CPUF_HWTYPE (C0h) holds the processor's own type (CPU_HWTYPE, in bits 6-7), which AL (CPU_TYPE) understates with `CPU=8088`.  CPUF_PMOK (02h) means the protected-mode self-test passed (so the 80286 driver stayed, and CPU_PMODE is available), and CPUF_PM (01h) means that the processor is running in protected mode (after CPU_PMODE).  Like every other function, CPU_MOVE runs with interrupts disabled, so long moves delay interrupts.

In protected mode, the same functions will be reached through a call gate (SEL_CPU, below), so callers will do `call SEL_CPU:0` instead of calling DDINT_CPU.

**Why DDINT_CPU**: an IOCTL interface (like FPU$'s IOCTL_GETFPU) would make every caller open the device, and the callers will mostly be the kernel and other drivers.  DDINT_UTIL is the DOS's entry point for drivers, so it isn't available until sysinit, and it's the wrong direction (CPU$ is called *by* the DOS).  A software interrupt would work in both modes, but uses up a vector; the call gate gives protected-mode callers the same kind of fixed far address that DDINT_CPU gives real-mode callers.

### Memory Map (tentative)

Physical memory on the baseline 2Mb PC AT:

| Address | Length | PMB type | Contents |
|---------|--------|----------|----------|
| 000000h | 1K | USED | Real-mode interrupt vector table |
| 000400h | 256 | USED | ROM BIOS data area |
| 000500h | 1136 | USED | BASIC-DOS low memory: CPU_TYPE (512h), CPU_HWTYPE (513h), CPU_ARENA (514h), DPT, DDINT entry points (530h, starting with DDINT_CPU), disk buffers |
| 000970h | | USED | Drivers: CPU$ (first), NUL, VKD$, ..., then BASDOS.COM and its tables |
| | | FREE | The rest of conventional memory, for CPU_ALLOC (including DOS's blocks, eg, programs) |
| 0A0000h | 384K | RSVD | Video memory, adapter ROMs, and the system ROM (not RAM) |
| 100000h | 64K | SYS | CPU$ system area (the HMA; see below) |
| 110000h | 1344K | FREE | The rest of extended memory, also for CPU_ALLOC (and DOS) |
| 260000h | | | End of memory |

The PMB types (PMBTYPE_* in cpu.inc) are FREE (0), USED (1, allocated by CPU_ALLOC), SYS (2), and RSVD (3).  The end of conventional memory comes from the BIOS (MEMORY_SIZE), so a machine with less than 640K (or a `MEMSIZE=` line) has a larger RSVD block.  The 80286 driver starts with conventional memory in three PMBs (USED below the drivers, USED for CPU$ itself, and FREE for the rest), and devinit and sysinit [claim](#claiming) what they use; after that, DOS allocates from it with CPU_ALLOC like anything else (MEMF_LOW, for now).

#### The System Area {#sysarea}

CPU$ keeps everything it owns, other than its code, in the first 64K of extended memory, which (with A20 enabled) is addressable in real mode as segment FFFFh, and in protected mode with selector SEL_SYS, whose base is FFFF0h, so the same offsets work in both modes.  Its code is the same in both modes, too: it gets its data segment from the mode (SMSW), and never writes through CS.

| Offset | Linear | Contents |
|--------|--------|----------|
| 0000h | 0FFFF0h | Last 16 bytes of the ROM BIOS (unusable) |
| 0020h | 100010h | SYSVARS: signature, CPU type and flags, the PMB table's offset, count, and maximum, function arguments, saved real-mode SS:SP and CS, and the GDTR and IDTR values |
| 00D0h | 1000C0h | CALL 5 trampoline: `JMP 0000:00C0h` (see below) |
| 00E0h | 1000D0h | GDT: 256 descriptors that CPU$ allocates from (the fixed ones first) |
| 08E0h | 1008D0h | PMB table (128 entries of 32 bytes) |
| 18E0h | 1018D0h | `pm_call`'s IDT (256 gates, for the self-test) |
| 20E0h | 1020D0h | The protected-mode IDT (256 gates; see [Protected-Mode Interrupts](#interrupts)) |
| 28E0h | 1028D0h | LDT (1024 descriptors) |
| 48E0h | 1048D0h | Unused (zero), up to the identity selectors |
| A0E0h | 10A0D0h | GDT: identity selectors A000h-F800h, every 800h (8 bytes each, zero in between) |

A PSP's CALL 5 (a far call to F01D:FEF0h, for example) reaches 0:00C0h (INT_DOSCALL5) only by wrapping around at 1Mb, so with A20 enabled, it lands at 1000C0h instead; like DOS 5 with DOS=HIGH, CPU$ puts a far jump to 0:00C0h there.  In protected mode, a real-mode segment isn't a selector, so a PSP's PSP_FCSEG is SEL_CALL5 instead (see psp_setmem), a call gate to SEL_C5CODE:00C0h, the far jump that sysinit stores at 0:00C0h (see set_call5); a far call through a gate ignores its offset, so PSP_SIZE keeps the value that CP/M programs read as their memory size.

The GDT's limit extends through the last identity selector (F800h), so the descriptors between its first 256 entries and A000h overlap the rest of the system area; CPU$ clears the whole area first, so most of them (everything from 48E0h up, other than the identity selectors) aren't present, and loading one of those selectors (eg, a real-mode segment by mistake) faults.

Before writing to the system area, CPU$ checks that A20 really is enabled (that SYSVARS isn't aliased to 0:0000h), and on every function call, it checks the SYSVARS signature and re-enables A20 if necessary (eg, if a program used the BIOS block move function, INT 15h function 87h, which turns A20 off).

#### Fixed GDT Selectors

| Selector | Type | Base | Use |
|----------|------|------|-----|
| 00h | | | Null selector |
| 08h | SEL_SYS | 0FFFF0h | Data: the system area |
| 10h | SEL_LDTD | 1028D0h | The LDT (for LLDT) |
| 18h | SEL_CPUCODE | CPU$ | Code: the CPU$ driver |
| 20h | SEL_LOW | 000000h | Data: the first 64K (interrupt vectors, BIOS data, BASIC-DOS low memory) |
| 28h | SEL_STACK | caller's SS | Data: the caller's stack, set on every switch to protected mode |
| 30h | SEL_TMP | 110000h | Data: scratch (the self-test writes through it) |
| 38h | SEL_CPU | | Call gate to CPU$'s function entry point |
| 40h | SEL_BIOS | 000400h | Data: the BIOS segment (40h), so code that uses segment 40h works in either mode |
| 48h | SEL_TMP2 | | Data: scratch (see pm_ptr) |
| 50h | SEL_DDINT | 000500h | Code: the DDINT segment (50h), so the DDINT entry points (eg, DDINT_SETVEC, 0050:003Ah) have the same addresses in either mode |
| 58h | SEL_C5CODE | 000000h | Code: just the CALL 5 jump at 0:00C0h (its limit is 00C4h) |
| 60h | SEL_CALL5 | | Call gate to SEL_C5CODE:00C0h, for a PSP's CALL 5 (in cpu.inc, since the kernel uses it) |
| A000h-B800h | | A0000h-B8000h | Data: identity selectors for video memory, every 800h |
| C000h-F800h | | C0000h-F8000h | Code: identity selectors for the adapter and system ROMs, every 800h, so the ROM BIOS can run at ring 0 with its own segments (eg, F000h) |

Selectors 68h-7F8h (GDT) and 04h-1FFCh (LDT) are allocated by CPU_ALLOC, CPU_MAP, and CPU_ALIAS (and CPU_PMODE); a descriptor whose access byte is zero is free.  All descriptors are 80286-format (the 80386 fields are zero, except bits 31-24 of the base, for blocks above 16Mb) and DPL 0 (unless MEMF_USER is set).

### Physical Memory Arena {#arena}

The 80286 driver's arena is a table of Physical Memory Blocks (PMBs) in address order, covering all memory from 0 to the end of extended memory, with the last PMB marked PMBSIG_LAST ('Z'), like the last MCB:

| Field | Size | Contents |
|-------|------|----------|
| PMB_SIG | byte | 'M', or 'Z' for the last PMB |
| PMB_TYPE | byte | PMBTYPE_* |
| PMB_OWNER | word | Owner (from CPU_ALLOC's BX), or zero |
| PMB_ADDR | dword | Physical address |
| PMB_LEN | dword | Length, in bytes |
| PMB_SEL | word | First selector (if any) |
| PMB_NSEL | word | Number of selectors |
| PMB_MCBTYPE | byte | Block type (MCBTYPE_*, as in an MCB), or zero |
| (reserved) | 7 bytes | |
| PMB_NAME | 8 bytes | Name of the process (as in an MCB), or zero |

CPU_ALLOC uses the first free block that's big enough, anywhere in memory (splitting it if necessary), unless MEMF_LOW, MEMF_HIGH, or MEMF_AT says otherwise, CPU_REALLOC shrinks a block or grows it into the free block after it, and CPU_FREE frees the block's selectors and merges it with any free neighbors.

Unlike MCBs, PMBs aren't stored in front of the memory they describe:

- the arena has to describe memory that isn't RAM (eg, 640K-1Mb), where no header could be stored;
- headers in extended memory couldn't be read or written in real mode, which is where CPU$ is called from until the kernel runs in protected mode;
- blocks need no header, so they stay aligned, and a block can be mapped by a selector with no offset; and
- a program that writes past the end of its block can't damage the arena.

The cost is a fixed number of PMBs (128 for now; a CONFIG.SYS option could change it).  The 8086 driver's arena is the MCB chain itself: programs on an 8086 expect to see MCBs, and conventional memory is all there is.

For debuggers that can't call CPU$ (eg, the PCjs Debugger), whichever driver stays stores the real-mode address of its arena in CPU_ARENA (0:514h): the 8086 driver's first MCB, or the 80286 driver's PMB table (FFFF:08E0h, the only arena above 1Mb).  The PCjs Debugger's `d dos` command uses it to list the arena the way DEBUG's DM does, in either mode, with each of the system's blocks shown as the drivers in it (from DD_LIST, whose links are selectors in protected mode); it labels the memory DOS is in by DOS's INT 20h handler, since it can't call DOS_MSC_GETVARS, so until sysinit installs that, the kernel's block shows as SYS.

#### Claiming Memory at Boot {#claiming}

Once CPU$ has initialized, everything that runs during the boot declares the memory it uses, with either driver and in either mode, and moves memory with CPU$ rather than on its own:

1. **devinit** (`chk_cpu`, before the first driver after CPU$ loads) claims two blocks with CPU_ALLOC and MEMF_AT: the drivers that haven't initialized yet, and its own code, CONFIG.SYS data, and scratch buffer.  Then, while it's still in real mode (so that it can use the boot code's `read_file`), it allocates a block for BASDOS.COM at the top of conventional memory (MEMF_LOW + MEMF_HIGH), loads BASDOS.COM into it, and copies the CONFIG.SYS data after it.
2. **Each driver** that shrinks (or grows) during its initialization has the drivers after it moved with CPU_MOVE.  The one exception is the first move on an 8086 (or with `CPU=8088`), where the 80286 CPU$ unloads itself before any CPU$ is loaded, so devinit moves the drivers after it down itself; reclaiming the memory of a driver that doesn't stay is devinit's job, not CPU$'s.
3. **When the last driver is done** (`i9`), devinit shrinks the drivers' block to fit (CPU_REALLOC), frees its own block and BASDOS.COM's, and allocates BASDOS.COM's new home with CPU_ALLOC and MEMF_LOW, which is the first free block, right after the drivers (and their MCB, with the 8086 driver); the block reaches at least the end of devinit, because the 8086 driver puts a free MCB after it, which must not land on devinit's code or data before the move (sysinit resizes the block anyway).  Then it pushes sysinit's inputs (including BASDOS.COM's new address) and its new entry point, and jumps to CPU_MOVE, which moves BASDOS.COM (over devinit) and "returns" to sysinit.
4. **sysinit** (with `move_init`, `dos_size`, `init_free`, and `map_buf`, in drvinit.asm) allocates a block at the top of conventional memory for its initialization code, CONFIG.SYS data, and a 512-byte stack below them, moves them there with CPU_MOVE, and jumps to them through a data selector and code alias for the block (CPU_MAP and CPU_ALIAS).  It grows the kernel's block as much as it can (CPU_REALLOC returns the longest a block could be), builds its tables after the kernel at offsets in the kernel's segment (`init_table`), gets a segment (or selector) for each disk buffer from CPU_MAP, and shrinks the block to fit.  Before loading the SHELLs, it gives back the part of its block below `sysinit_tail` (by freeing the block and claiming the rest again), and when they're loaded, it frees the rest.

Once CPU$ is loaded, neither devinit nor sysinit computes a segment from an address, or relocates memory itself.  Before then, devinit calls the first driver (CPU$) at its fixed segment (BIOS_END), and moves the drivers itself if the 80286 CPU$ unloads (above); and sysinit sets DOS's memory limit (`mcb_limit`, for PSP_PARAS) from the BIOS's MEMORY_SIZE.  (They do still copy the CONFIG.SYS data, into blocks that CPU$ gave them.)

After the boot, the kernel's memory functions (memory.asm) are just calls to CPU$, with the block's segment (or selector) in CX and DX = -1: DOS_MEM_ALLOC calls CPU_ALLOC (without MEMF_LOW, so a block can be anywhere in memory, including extended memory in protected mode, plus MEMF_HIGH for MCBTYPE_HIGH) and CPU_SETBLK (the owner and type), DOS_MEM_FREE calls CPU_FREE, DOS_MEM_REALLOC calls CPU_REALLOC, loading a program names its block with CPU_SETBLK, a program's blocks are freed with CPU_FREEALL when it ends, and DOS_UTL_QRYMEM (for MEM), finding a loaded copy of a program's code, and DEBUG's DM use CPU_QUERY.  There's no MCB chain for programs to walk, other than the 8086 driver's, so DOS_MSC_GETVARS's `mcb_head` is zero; MEM's total memory is its DV_MEM_SIZE, which sysinit sets to the conventional memory (MEMORY_SIZE) plus every block that CPU$ describes above 1Mb (`mem_total`).

### Switching Modes

CPU$'s `pm_call` runs a function in protected mode and returns to real mode, with interrupts and NMI disabled.  It points SEL_STACK at the caller's stack, saves SS:SP, loads the GDTR and IDTR, sets PE with LMSW, jumps to SEL_CPUCODE, and loads DS, ES, and SS with SEL_SYS and SEL_STACK, and LDTR with SEL_LDTD.

An 80386 returns to real mode by clearing PE (`MOV CR0,EAX`, assembled as bytes, since MASM 4.00 knows only 80286 instructions).  An 80286 can't, so before switching, `pm_call` sets the CMOS shutdown code (CMOS register 0Fh) to 0Ah and stores the address of `pm_resume` in 40:67h, and to return, it pulses the 8042's reset line (command FEh), as the BIOS's own block move (INT 15h function 87h) does.  After the reset, the BIOS sees the shutdown code and jumps through 40:67h without initializing anything else (both the original 1984 PC AT BIOS and the 1985 revision 3 support shutdown code 0Ah), and `pm_resume` restores SS:SP and the real-mode IDTR, clears the shutdown code (so that a later CTRL-ALT-DEL does a normal POST), and enables NMI again.  Because the shutdown code is set before switching, a "triple fault" (which resets the processor) also returns to `pm_resume`, and every IDT entry points to a fault handler that returns to real mode, too, so a bug in protected mode makes the caller's test fail instead of hanging the machine.

The CPU$ self-test (`pm_test`) checks that PE is set and writes and reads back a word at 110000h (through SEL_TMP), which real mode can't reach; CPU$ stays loaded only if that works.

CPU_PMODE (below) switches to protected mode the same way, but for good: it never returns to real mode.

### Protected-Mode Interrupts {#interrupts}

After CPU_PMODE, every interrupt goes through the protected-mode IDT (SYS_PIDT), and the master PIC is moved from 08h to 78h, next to the slave PIC (70h-77h), so that IRQs 0-7 no longer share vectors with processor exceptions.  Its default gates "reflect" each interrupt to the handler in the real-mode vector table, if that's in the ROM (whose segments are identity code selectors, eg, F000h), at ring 0:

| IDT entries | Default gate | Reflected to |
|-------------|--------------|--------------|
| 00h-02h, 06h-0Fh | `exc_stubs` (DPL 0) | Exceptions: fatal, except the cases below |
| 03h-05h, 10h-6Fh, 80h-FFh | `sw_int` (DPL 3) | Software interrupts: the vector's handler, if it's in the ROM; otherwise fatal |
| 70h-77h | `irq_stubs` (DPL 0) | IRQs 8-15: vectors 70h-77h's handlers, if in the ROM; otherwise an EOI |
| 78h-7Fh | `irq_stubs` (DPL 0) | IRQs 0-7: vectors 08h-0Fh's handlers, if in the ROM; otherwise an EOI |

- **Reflection**: `irq_common` "returns" to the ROM handler with the interrupt's own frame on the stack, so the handler returns straight to the interrupted code.  `sw_int` gets the vector from the caller's `INT n` (or `INT3`) instruction, and calls the handler with interrupts disabled and a frame that returns to `si_ret`, which copies the handler's result flags (CF, ZF, SF, and OF) to the caller's.  Everything runs on the caller's stack, at ring 0, so far.
- **Drivers' handlers**: in protected mode, DDINT_GETVEC and DDINT_SETVEC go to CPU$'s `pm_getvec` and `pm_setvec`, which read and write the IDT, not the real-mode vector table: setting a vector replaces its gate (for vectors 08h-0Fh, the gates for IRQs 0-7, at 78h-7Fh), so the driver's handler is called directly, and getting a vector returns its gate, or if the gate is a default one, its real-mode vector if that's in the ROM (eg, F000:FEA5h for INT 08h, which CLOCK$ chains to), or 0:0 if not.
- **INT 13h**: CPU$ reflects INT 13h like any other BIOS call, and FDC$, which makes every disk transfer (HDC$ reads MBRs through FDCX_MBR), works around the BIOS's real-mode assumptions about ES:BX in `pm_rw` (which in real mode is part of FDC$'s sector buffer instead).  The diskette BIOS turns ES:BX into a DMA address (ES * 16 + BX), so ES:BX becomes BIOS (SEL_BIOS, whose base is 400h) and the buffer's offset from 400h; a buffer more than 64K above 400h goes through FDC$'s sector buffer, a sector at a time, since `readwrite_sectors` gets each buffer's address from CPU_SEGINFO (`pm_dma`) for its 64K DMA boundary check.  The AT fixed disk BIOS uses programmed I/O, but it normalizes ES:BX by adding BX / 16 to ES, which makes ES an invalid selector unless BX is less than 16, so the buffer gets a selector of its own (CPU_MAP) with a zero offset.  FDC$'s other real-mode assumptions are gone, too: `readwrite_sectors` advances the transfer address between tracks by adding to the offset, not ES (DOS's buffers never extend beyond offset FFFFh), and `set_dpt` updates the DPT at DPT_ACTIVE (40:122h), where the boot code puts it, rather than through the INT 1Eh vector, which DDINT_GETVEC can't return in protected mode.
- **Vectors 08h-0Fh** are also software interrupts sometimes (eg, the AT BIOS's IRQ 9 handler does `INT 0Ah`), so if an exception's frame (taken as having no error code) returns just past an `INT` for its vector, `exc_common` treats it as one.
- **Null selectors in the ROM**: the BIOS loads DS with 0 to address the vectors, so a general protection fault with a zero error code, in the ROM, while DS or ES holds a null selector, is retried with SEL_LOW (base 0).  BASIC-DOS's own code gets no such fix.
- **Anything else** (any other exception, an INT 3, such as a failed DEBUG assertion, or a software interrupt with no handler we can call) is fatal: `cpu_fatal` prints, with the BIOS, `CPU$ fault vv at cccc:iiii (DS=dddd ES=eeee EC=xxxx)`, where EC is the error code (for a software interrupt, the caller's AX), and stops the machine for a debugger.

This is what the [probe](#probe) showed works for the ROM BIOS, with two differences: the GDT has identity selectors only where the BIOS needs them (and CPU$ allocates everything else), and drivers' handlers run in protected mode instead of being dropped.

### Protected-Mode Boot {#pmboot}

On an 80286 or later, when CPU$ stays loaded, BASIC-DOS switches to protected mode during devinit, right after CPU$ initializes, and never switches back; everywhere else (an 8088, or `CPU=8088`), nothing changes, and the same code runs in real mode:

1. **CPU$ initializes in real mode**, as the first driver.
2. **devinit claims its memory and loads BASDOS.COM** (`chk_cpu`), as it does in real mode (see [Claiming Memory at Boot](#claiming)).
3. **devinit calls CPU_PMODE**, which turns its CS into a code selector, DS, ES, and SS (all 0) into SEL_LOW, the view of the first 64K that devinit uses to reach the drivers, points DDINT_CPU, DDINT_GETVEC, and DDINT_SETVEC at CPU$'s protected-mode code, moves the master PIC, and loads the protected-mode IDT.  devinit then gives the drivers already in the chain (ie, CPU$) selectors, too.  The 80286 driver stays only if it can switch to protected mode, so if CPU_PMODE fails, devinit halts.
4. **Each driver gets a code selector and a data selector** before its initialization, unless it's skipped (`get_sels`, which calls CPU_MAP for a 64K data selector and CPU_ALIAS for its code alias; in real mode, both are the driver's segment): devinit stores the data selector in DDH_DATA and DDPI_END, calls the driver through its code selector, and links it into the chain (DDH_NEXT_SEG, FDC_DEVICE, HDC_SEG, and CLOCK_DEVICE) with its code selector.  When the driver's initialization returns, devinit fits both selectors to the length the driver keeps, with CPU_SETLIM (`fit_sels`), so that they end where its resident code and data do, or frees them with CPU_UNMAP if it keeps nothing; CPU$'s own selectors (from step 3) are fitted the same way.  The selectors are 64K until then, since a driver can keep more than its file (eg, FDC$'s sector buffer overlays its initialization code and extends past it).  devinit also passes its own data selector in DDP_PTR and DDPI_BUFPTR.
5. **devinit moves BASDOS.COM after the drivers and jumps to sysinit** (`i9`), as it does in real mode: it gets a code selector and a data selector for BASDOS.COM's new home, pushes the offset of the BPB (in the first 64K), the size of the CONFIG.SYS data, the data selector, and the CONFIG.SYS data's offset, which sysinit pops, and then CPU_MOVE "returns" to its entry point (CS:0002h).

`tools/tests/pmboot.sh` boots this way on the baseline 2Mb PC AT (with the console on COM1), and lists breakpoint addresses for the PCjs Debugger: `dv_init` precedes each driver's initialization, and `dv_jump` precedes sysinit.

**Where it stands**: stepping through the boot in the PCjs Debugger, every driver initializes in protected mode: NUL, VKD$, COM1-COM4, LPT1-LPT3, CLOCK$, FDC$, HDC$, PIPE$, FPU$, and MOUSE$.  Along the way, VKD$, COM, and CLOCK$ install their handlers with DDINT_SETVEC (into the IDT), CLOCK$'s timer handler runs in protected mode (and chains to the BIOS's), and BIOS calls (eg, INT 1Ah, and INT 13h functions 08h and 02h, as HDC$ reads each hard disk's MBR and its volumes' boot sectors) are reflected.  Two things needed fixing:

- **CPU_PMODE** read the new selectors from the stack (through SS) after setting PE, but SS still held 0, which PCjs treats as a null selector in protected mode; it now loads them into registers first.
- **Empty chains** (CLOCK$'s timer list and the drivers' lists of waiting packets) ended with a far pointer of -1:-1, and the code loads the whole pointer before checking the offset, which loads FFFFh into a segment register; they now end with FFFFh:0000h, and loading 0 is fine in either mode.

sysinit then runs in protected mode, moves its initialization code to the top of conventional memory through CPU$ (see [Claiming Memory at Boot](#claiming)), continues there with selectors for the new copy, sets the DOS vectors (in CPU$'s IDT, with the kernel's code selector), stores the CALL 5 jump, revectors DDINT_UTIL, builds its tables, opens its devices, loads any DEVICE= drivers (`load_devices` calls each driver's INIT through the code alias of its block, and links the driver with it), hooks INT 21h for its SHELL cache, loads the SHELLs (DOSUTIL LOAD), and finishes, all in protected mode, and `dos_leave`'s IRET starts the first session, with CS set to the code alias of its program's block (see [Code Aliases](#aliases)).  COMMAND.COM then initializes, displays its prompt, and runs commands (eg, VER and MEM) and programs (eg, FPUTESTS, which passes), all in protected mode.  DEBUG.COM, loaded as a driver, gets any fault after it's loaded (see CPU_SETFAULT), and shows the faulting instruction, and with /H (eg, `DEVICE=EXT\DEBUG.COM COM2:9600,N,8,1,VT100 /H`), it also stops as soon as it's loaded.

Getting that far also needed these fixes:

- **Code aliases kept in the PMB**: CPU_REALLOC copies a block's PMB when it frees the end of the block, and the copy, with the block's code alias, was freed, too; so when DEBUG.COM shrank to its resident size, its code selector became invalid, and CPU$ faulted when it gave DEBUG.COM the next fault.  The freed end no longer takes the alias with it.
- **FPU$**: its function table's segment was its CS plus the table's paragraph, which in protected mode isn't a selector; it now gets that segment from CPU$ (see [Floating-Point Interface](../fpu/)).
- **COMMAND.COM** (see [COMMAND.COM](#command)): its generated code runs through code aliases, freeing the blocks that ES holds no longer leaves a freed selector on the stack, and the transient portion's copy is found again without keeping a freed selector.

Then the regression tests, which needed these:

- **CALL 5**: a PSP's far call at offset 5 used a real-mode segment (PSP_FCSEG), computed so that, with the offset (PSP_SIZE), it reaches 0:00C0h (or FFFF:00D0h), which in protected mode isn't a valid selector; now it's the SEL_CALL5 call gate (see [The System Area](#sysarea)).
- **Double slots in generated code**: genSlot reserves each double's 8-byte slot in the code block, and the generated code pointed ES at it with `push cs` and `pop es` before an FPU$ function stored a result there, which in protected mode is a write through the block's code alias; now each code (and function) block has its data segment (or selector) at CBLK_DATA, which the generated code loads instead (`MOV ES,CS:[CBLK_DATA]`, or `PUSH CS:[CBLK_DATA]` for a slot passed as a parameter; see genBlkData).
- **Test programs that write through CS**: FCBTESTS, DOSTESTS, CPUTEST, HARDERR, and IOERR set DS or ES from CS and wrote their own data; now they use the DS (or SS) that a COM program starts with, as do the far pointers they pass to DOS (eg, an EPB's command tail, which the kernel writes into while it parses it), and their interrupt handlers load DS from a copy of it (`data_seg`).
- **A new program's FLAGS**: FL_DEFAULT was F202h (as an 8086 pushes FLAGS), but in protected mode at ring 0, an IRET with that value sets IOPL 3 and NT, and the next IRET with NT set (eg, the kernel's, after a CALL 5, which unlike an INT doesn't clear NT) is a task switch through the TSS; it's 0202h now.
- **Stale selectors in COMMAND.COM**: compactStrs, like freeAllBlocks, returns ES = 0 if it freed the block in ES; genCode sets ES to the heap before freeing a program's code (ES may hold a code block's alias); and findErl (for ERL) looks for a return address in a code block by comparing each word on the stack with the blocks' code segments, rather than loading it into ES.
- **Null string pointers**: an empty BASIC string is a null pointer, which `%ls` (eg, WRITE's `"%.*ls"`) passed to strlen, which read 0:0; sprintf now treats a null pointer as an empty string, as it does a typed one.
- **Vectors set with DS:DX**: HARDERR and IOERR set their handlers with DS:DX, as COM programs often do, and DS is a data selector in protected mode (CS is the block's code alias), so the IDT gate (or SCB vector) wasn't executable; now when DS is the program's PSP block, DOS_MSC_SETVEC uses the block's code alias instead (see mem_alias), which in real mode is the same segment.
- **CPUTEST's mode flag**: CPUTEST took its CPUF_* flags from AH after a PRINTF, which returns the number of characters printed in AX, so it always ran its real-mode tests, and its CPU_MOVE and CPU_RWMEM tests passed its selectors to CPU$ as segments (copying bytes to and from the wrong memory); now it saves the flags from its first CPU_GETINFO.

Now, in the `pm` configuration, VER, MEM, FPUTESTS, STRFUN, STRPOOL, ARRAYS, FLOW, EXPRERR, CMDS, VARS, FILEIO, RUNFILE, PRTUSING, MOVES, ATTRS, FCBTESTS, IOERR (including its VI tests), PRINTF, and CPUTEST pass.  What still fails:

- **DOSTESTS** passes everything up to its EXEC reservation test, whose fixture is an EXE file: the loader's relocations are paragraph arithmetic, so EXE files can't run in protected mode (see [Code Aliases](#aliases)).
- **HARDERR**: in protected mode, reading the empty drive B: fails with device error 7 (unknown media, DOS error 26) instead of 2 (not ready), so its first test fails; its metadata test also computes a segment for a direct INT 13h read.

#### What sysinit Needs {#sysinit}

sysinit was written for real mode, and most of what it does computes segments from paragraphs:

1. **Moving itself to the top of memory** (*done*): it allocates the block from CPU$, moves itself with CPU_MOVE, and jumps there through a data selector and code alias for the block (CPU_MAP and CPU_ALIAS), and uses the data selector as SS.  `dos_seg` is the kernel's data selector (from devinit), not CS.
2. **Revectoring DDINT_UTIL, DDINT_ENTER, and DDINT_LEAVE** to the kernel, **setting the DOS vectors**, and **storing the CALL 5 jump** (*done*, although DDINT_ENTER and DDINT_LEAVE come after the SHELLs are loaded): `set_ddint` and the vectors use the kernel's code selector (`dos_code`, the CS that sysinit is entered with), and `set_call5` stores the CALL 5 jump at 0:00C0h through a selector for the first 64K from CPU_MAP, which it then frees (CPU_UNMAP).  DDINT_GETVEC and DDINT_SETVEC are CPU$'s, in either mode, so sysinit leaves them alone.
3. **Building the tables** (*done*): the SCBs, BPBs, and SFBs are at offsets after the kernel (`init_table`), and each disk buffer (including the two in low memory) gets its segment, or selector, from CPU_MAP, which is what the buffer chain links.
4. **The MCB chain** (*done*): there isn't one; the kernel's memory functions call CPU$ (see [Claiming Memory at Boot](#claiming)), so DOS_MEM_ALLOC returns whatever CPU_ALLOC does (a selector, in protected mode).
5. **Loading the SHELLs** with DOSUTIL LOAD, which builds PSPs and loads programs, and starting the sessions (*done*): a COM program's CS is the code alias of its block (see [Code Aliases](#aliases)).

So sysinit's remaining operations can be converted one at a time, in the same mode-independent way as the drivers (eg, the kernel's device search also loads each link's segment before checking for the end of the chain, and the last driver's link holds a paragraph).

### Background: the Probe {#probe}

Before BASIC-DOS ran in protected mode, a build-time experiment (PROBE builds of CPU$, since removed) answered the question of whether the ROM BIOS could run in protected mode at all: after its self-test, CPU$ switched to protected mode with an "identity" GDT (8192 descriptors, each with a base of its selector times 16), ran a short routine at ring 3 that called INT 10h, 11h, 12h, 13h (including a diskette read by DMA), 15h, 16h, and 1Ah, and reflected each call to the BIOS at ring 0.  Both the PC AT and the DeskPro 386 BIOSes handled every call, with the null selector fix (the AT BIOS's GET_PARM does `LDS SI,[78h]` with DS = 0, and the VGA BIOS loads DS with 0 for every character) and, for INT 13h, an identity selector for the DMA buffer.  The DeskPro 386's IRQ 9 handler issues `INT 0Ah`, which lands on the invalid-TSS exception's gate, hence `exc_common`'s check for an INT.  A later version tried each driver's initialization in protected mode, which led to the DDINT segment at 50h and DDH_DATA (see [Mode-Independent Code](#modeless)).

### Running BASIC-DOS in Protected Mode {#plan}

Staying in protected mode after CPU$ initializes is the goal, but the rest of BASIC-DOS assumes real mode in several ways, and each needs its own solution.  This design targets the PC AT (an 80286, with IBM's BIOS); the 80386 (eg, virtual-8086 mode for DOS programs) and other BIOSes, such as the DeskPro 386's, are for later.

1. **BIOS calls** (*done*, for what the drivers' initializations use).  The ROM BIOS runs at ring 0 in protected mode, with identity selectors, a fix for null selectors, and reflection through the real-mode vector table (see [Protected-Mode Interrupts](#interrupts)), so a BIOS call needn't cost a mode switch, which on an 80286 means a processor reset (as in OS/2 1.x's real-mode session).  The rest of the BIOS functions the drivers use still need trying, diskette (DMA) buffers more than 64K above 400h could use an identity selector (rather than FDC$'s sector buffer), and a few functions (eg, INT 15h functions 87h and 89h) will need CPU$ replacements.
2. **Hardware interrupts**.  The master PIC's IRQs 0-7 use vectors 08h-0Fh, which are also processor exceptions (eg, 0Dh is a general protection fault).  CPU$ moves the master PIC to 78h-7Fh, next to the slave PIC (70h-77h), and reflects each IRQ to the BIOS's handler, unless a driver has installed its own handler (eg, CLOCK$'s timer handler), which is called directly (*done*; see [Protected-Mode Interrupts](#interrupts)).  Vectors 08h-0Fh can still be software interrupts (eg, INT 0Ah from a BIOS's IRQ 9 handler), so their gates tell the two apart.
3. **Segment arithmetic**.  The kernel and COMMAND.COM compute segments from paragraphs (eg, walking the MCB chain, `mov ax,es` + `inc ax` to get from an MCB to its block, PSP and environment segments, and paragraph rounding), use fixed segments (0 for low memory, 40h, B000h and B800h for video, and F000h for the ROM), and use `push cs` + `pop ds` and then write data (a code segment can't be written in protected mode).  Each case needs a selector: for example, DOS_MEM_ALLOC could return a selector from CPU_MAP for the new block (keeping the MCB in the arena below 640K), the fixed segments would become fixed selectors (SEL_LOW, plus SEL_VIDEO and SEL_ROM), and each module with a code segment would also get a data alias (eg, the next selector).  The first step is an inventory of every such case.
4. **DOS programs**.  COM and EXE programs are real-mode programs.  On an 80386 they can run in virtual-8086 mode; on an 80286, only in real mode, so a session running a DOS program would switch the processor back to real mode while it runs (much like OS/2's DOS session), and other sessions would wait.
5. **COMMAND.COM**.  The biggest payoff: BASIC programs, variables, strings, and arrays limited only by memory, with each block in extended memory and addressed by a selector.

#### Mode-Independent Code {#modeless}

The first step toward staying in protected mode is to change the drivers and the kernel (everything that will run at ring 0) so that the same code runs in either mode, by using only segment values that are also valid selectors, and by never writing to a code segment.  The rules, *in progress*:

1. **Low memory through segment 40h** (*done*): bios.inc's BIOS segment is now `at 40h`, as the ROM BIOS itself addresses its data, instead of 0, and it covers both the ROM BIOS data area (offsets 00h-FFh) and BASIC-DOS's low memory (500h-96Fh, at offsets 100h-56Fh): CPU_TYPE, the DDINT entry points, the DPT, and the two disk buffers.  In protected mode, 40h is an identity selector.  BIOS_DATA (400h) is the segment's linear address, for the few places that need a linear address (eg, the two disk buffers' addresses, for CPU_MAP, and devinit, which addresses the drivers through segment 0).
2. **Interrupt vectors through DDINT entry points** (*done*): segment 0 is the null selector, and the general protection fault fix for it should only ever be needed by the ROM BIOS, so drivers and the kernel read and write vectors with far calls to DDINT_GETVEC and DDINT_SETVEC (after DDINT_CPU), which pass vectors in DX:CX rather than in segment registers (see [Device Drivers](../dev/)).  CPU$ provides them, since one CPU$ always stays, and it initializes first, so they're ready for every other driver's INIT, before the kernel is loaded: the 8086 driver's use the vector table, and the 80286 driver's, from CPU_PMODE on, use its IDT.  Only the boot code and devinit, which run first, and sysinit's CALL 5 jump at 0:00C0h (code, not a vector) still use segment 0, along with HDC$'s MBR code (which runs at boot), CPU$'s A20 test, and the 8086 CPU$'s vector functions (which run only in real mode).  COMMAND.COM no longer reads the INT 33h vector to find a mouse driver (see [COMMAND.COM](#command)).
3. **DDINT entry points through segment 50h** (*done*): drivers and the kernel call the DDINT entry points through segment 50h (eg, `call far ptr DDINT_SETVEC` is CALL 0050:003Ah), which in protected mode is SEL_DDINT, a code selector with the same base (500h), so the addresses are the same in either mode; 40h stays a data selector.  The slots are still written through segment 40h (bios.inc's DDINT segment is at 50h, and an operand like `ds:[DDINT_CPU]`, with DS assumed to be BIOS, gets the BIOS offset from LINK, while an immediate offset needs DDINT_BIAS added).  In protected mode, CPU$ points DDINT_CPU, DDINT_GETVEC, and DDINT_SETVEC at its own protected-mode code (see [Protected-Mode Boot](#pmboot)).
4. **No writes through CS** (*in progress*): a protected-mode code segment can't be written, so each write with a CS override became a write through DS, ES, or SS holding the module's own segment (eg, after `push cs` and `pop ds`), in the drivers, the kernel, COMMAND.COM, DEBUG.COM, and the HARDERR and IOERR tests.  In the kernel, those segments now come from `dos_data` (eg, `mov ds,cs:[dos_data]`), where sysinit stores the kernel's data segment (or selector), and sysinit's relocated code uses SS, its own data selector (or `init_data`, in `cache_int21`, which runs on its caller's stack); `sprintf` still loads DS from CS, since it only reads through it (and it's also part of PRINTF.COM).  A write through SS needs no change at all.  MASM also gives a write an implicit CS override when the segment register that would otherwise address the variable is assumed to be NOTHING; a scan of the kernel's binary for CS-prefixed writes found one (LOCK_SCB in `mcb_getsize`), which now goes through ES, but the drivers, COMMAND.COM, and DEBUG.COM haven't been scanned yet.  Writes to a driver's own memory now go through its data selector (see the next item).
5. **No unnecessary null selectors**: segment registers are never loaded with 0 just to have a value (three places in the kernel did, before read_buffer replaced it anyway), since only the ROM BIOS should ever need the null-selector fixup.
6. **A data selector for every driver** (*done*): DDH_INTERRUPT (unused, except by COM, which now keeps its interrupt entry with its other per-port variables) is now DDH_DATA, the driver's data segment or selector, which devinit (or the kernel, for DEVICE= drivers) stores in the header before calling the driver's initialization, so every entry point (requests, interrupt handlers, and the far entry points that FDC$ provides HDC$) can load it with `mov ds,cs:[0].DDH_DATA` (instead of `push cs` and `pop ds`) whenever it writes its own memory.  In real mode, it's the driver's segment, so nothing changes; in protected mode, the driver's code selector (CS) and data selector are separate selectors for the same memory, from CPU$.  Far pointers to a driver's code (eg, vectors, DDH_NEXT_SEG, FDC_DEVICE, and BPB_DEVICE) use its code selector, and pointers to its data (eg, FDC$'s ddbuf_ptr) use its data selector.

The boot sector, which runs at 0:7C00h and then 0:0560h before anything else, keeps using segment 0 (adding BIOS_DATA to every BIOS offset), as does devinit to reach the drivers (through SEL_LOW, in protected mode), although it relocates them with CPU_MOVE.

DEBUG builds also report (and halt on) the first failed assertion, even before any console handle exists: the kernel installs a default INT 29h handler (BIOS output) whenever no driver has (eg, VKD$ isn't loaded), so the fallback in write_handle never calls a null vector.

#### COMMAND.COM {#command}

COMMAND.COM will run at ring 3, so beyond the rules above, it should use only selectors that the kernel gives it.  *Done*:

- **Which copy owns the shared code**: it used to compare CS with DS (or SS), which are different selectors in protected mode even for the owner; now it checks PSP_HEAP, since only another copy's heap starts right after its PSP (see load_program).
- **The environment**: it used to be a paragraph-aligned buffer in the heap, whose segment was DS plus a paragraph offset; now it's a block of its own, allocated from the top of memory while COMMAND runs a program (and freed when it ends), so that it never sits after COMMAND's block (where it would keep the transient portion's memory from being reused).
- **The transient portion's copy**: it used to be placed at the top of the highest free block, computed from that block's segment and size; now COMMAND allocates a block there, copies the transient portion into it, and frees it again (it's still checksummed before it's reused).
- **Graphics memory**: the graphics statements used B800h; now they ask VKD$ (IOCTL_GETMODE with CL = 1 returns the context's video memory in DX, which in protected mode will be a selector) and cache it with the mode.
- **Fixed segments and vectors**: the tick count for RANDOMIZE uses segment 40h, and MOUSE no longer reads the INT 33h vector (it checks whether MOUSE ON found a mouse, and MOUSE ON resets the mouse with INT 33h, which is always valid, since sysinit points it at an IRET when there's no mouse driver).
- **Generated code** (see [Code Aliases](#aliases)): COMMAND compiles BASIC into code blocks (CBLKs, and FBLKs for user-defined functions) that it allocates as data, runs them, and patches them while they run (genMore replaces each placeholder, which it finds from its return address).  Each block's code alias is what code transfers into (`codeSeg`), and everything else (the block chains, labels, code generation, and patching) uses the block's data selector.
- **The shared code's variables**: CMD_REFS, TRANS_SUM, TRANS_HI, CMD_PATH (and MSG_DRIVE), and FPU_TABLE are in COMMAND's code segment, and every copy now writes them through CODE_DS, the owner's data segment (or selector), which the owner stores at startup.
- **The transient portion's copy**: a freed block's selector isn't valid in protected mode, so instead of keeping the segment of the block it copied the transient portion into (and freed), COMMAND allocates the same size at the top of free memory again when the program ends, which is the same memory unless something else has allocated it, and checks the copy's checksum as before (see DOS_UTL_QRYMEM in [Utility Functions](../util/#memory)).
- **Freed selectors on the stack**: freeAllBlocks preserved the caller's ES, so freeing the block that ES held (eg, the code blocks, when a program ends) reloaded a freed selector; now it returns ES = 0 in that case, as DOS_MEM_FREE does.

- **DEF SEG, PEEK, and POKE**: a DEF SEG segment is mapped to a selector, read-only except for video memory (see [DEF SEG](#defseg)).

*Remaining*:

- **A read-only code segment**: the shared code's variables could move out of the code segment (eg, the share count into the kernel, which already finds the matching copy, and the rest into each copy's heap), so that the code segment would be read-only: one execute/read selector that every copy shares, with no checksums (nothing could modify it) and, with extended memory, perhaps no transient portion at all.  The hard part is establishing that separation, since today the shared code is simply the first part of the owner's COM image.

#### Code Aliases {#aliases}

A protected-mode segment is either code (executable, and at most readable) or data (readable, and perhaps writable), so memory that's both written and executed needs two selectors.  CPU_ALIAS (tested by CPUTEST) creates the second one: given a selector from CPU_ALLOC, CPU_MAP, or CPU_ALIAS, it returns a new selector for the same base and limit, with the access rights selected by MEMF_CODE, MEMF_RDONLY, and MEMF_USER; CPU_UNMAP frees it.

A block's own code alias (CPU_ALIAS with just MEMF_CODE, for the selector that CPU_ALLOC returned for the block) is special: the 80286 driver creates it only the first time, keeps it in the block's PMB (PMB_CODE), returns the same selector every time after that, and frees it with the block (and when CPU_REALLOC shrinks a block, the alias stays with the block, not the freed end).  So nothing else has to keep track of the pair, and it must never be freed with CPU_UNMAP.  The kernel returns it for any memory block with DOS_UTL_ALIAS (27h; see [Utility Functions](../util/#memory)), since ring 3 code won't be able to call DDINT_CPU; in real mode, a block's code alias is its segment.

- **COMMAND.COM's code blocks** (*done*): allocBlockMin gets each CBLK's and FBLK's code alias when it allocates the block (freeing the block if it can't), so getting it later can't fail, and `codeSeg` returns it wherever code transfers into a block: genCode's call, the far JMP that ensureRoom generates from one block to the next, emitJmp's far JMPs (eg, to a line in another block), genFuncExpr's calls to user-defined functions, and doChain's jump.  Return addresses and GOSUB frames are code selectors already, since the CPU pushes CS.
- **EXEC** (*done*, for COM programs): a COM program's code and data are in one block (its PSP block), so load_program gives it CS from the block's code alias, and DS, ES, and SS from the block's data selector; the alias goes with the block when the program ends.  An EXE file's relocations are paragraph arithmetic, so in protected mode they can only work if each 64K of the image has its own selector (as with CPU_MAP's consecutive selectors) and every relocated segment is a multiple of 64K from the start of the image, which isn't generally true; MZ EXE files would run only when the system is in real mode (or in virtual-8086 mode on an 80386).

#### DEF SEG, PEEK, and POKE {#defseg}

DEF SEG accepts any segment, which in protected mode isn't a selector, so it's mapped (*done*):

- **DEF SEG with no segment** (BASIC's own data, ie, the heap) stays as it is, readable and writable.
- **Any other segment** gets a selector for its 64K from the kernel (DOS_UTL_MAPSEG; see [Utility Functions](../util/#memory)), which each session keeps one of (the next call frees it): writable for video memory (A000h through BFFFh), and read-only (MEMF_RDONLY + MEMF_USER) everywhere else, including low memory (eg, segment 0 or 40h, for the BIOS data area) and the ROMs, so PEEK works, but POKE is an "Illegal function call" (POKE checks the selector with VERW, which it runs only in protected mode, when its CS, a code alias, isn't CODE_DS).
- **Segments that belong to the session** (eg, blocks that its programs allocated) could later be writable, too, once a BASIC program can get one (eg, with VARSEG); today, the only segment that BASIC-DOS gives a BASIC program is DEF SEG's default.
- In real mode, none of these restrictions apply, so programs that PEEK and POKE BIOS data or video memory keep working there.

#### Phases {#phases}

1. **Done**: CPU$ (processor detection, A20, the arena, GDT, IDT, and LDT, a self-tested switch to protected mode and back, and the CPU_* functions, all called in real mode), CPU_TYPE and DDINT_CPU in low memory, `--ram=2M` in pc.js, and CPUTEST.COM (in TESTS\MISC on test disks), which prints the arena and checks every function.
2. **Kernel interfaces**: CPU$ managing all memory in either mode, with CPU_REALLOC and CPU_MOVE (*done*), devinit and sysinit claiming, mapping, and moving their memory with them (*done*; see [Claiming Memory at Boot](#claiming)), and the kernel's memory functions (DOS_MEM_ALLOC and friends, freeing a program's blocks when it ends, and MEM) and DEBUG's DM using CPU$, with each block's owner, type, and name kept by CPU$ (*done*), allocating from all of memory, conventional and extended alike (*done*).
3. **COMMAND.COM in extended memory, from real mode**: eg, keeping the copy of the transient part, or large arrays, in extended memory with CPU_MOVE.
4. **Interrupts in protected mode** (*done*, so far): CPU$ moves the master PIC, reflects software and hardware interrupts to the ROM BIOS at ring 0, and keeps the drivers' handlers in the IDT (see [Protected-Mode Interrupts](#interrupts)).  Next: trying the rest of the BIOS functions that the drivers use.
5. **A protected-mode kernel**: the segment-arithmetic inventory and fixes (*in progress*; see [Mode-Independent Code](#modeless) and [COMMAND.COM](#command)), staying in protected mode after CPU$ initializes (*in progress*: the drivers, the kernel, and COMMAND.COM all start in protected mode; see [Protected-Mode Boot](#pmboot) and [What sysinit Needs](#sysinit)), code aliases for COMMAND's generated code and for EXEC (*done*, for COM programs), and running DOS programs in real mode (80286) or virtual-8086 mode (80386).

### Open Questions

- **The HMA**: putting the system area in the HMA costs no conventional memory and is reachable in both modes, but A20 stays enabled, so besides the CALL 5 trampoline, programs that depend on wrapping at 1Mb could break (eg, EXEPACK-compressed programs loaded in the first 64K report "Packed file is corrupt").
- **Owners**: should PMB owners be PSPs (freed when a program ends) or sessions?
- **Privilege levels**: everything is DPL 0 for now (except selectors created with MEMF_USER); DOS programs and BASIC code could run at ring 3 later, which would need a TSS and DPL 3 selectors.
- **Table sizes**: 128 PMBs, 256 GDT entries, and 1024 LDT entries are guesses; one LDT per session (or per program) may make more sense than a single LDT.
- **Identity selectors**: the GDT has them only for video memory and the ROMs (A000h-F800h, every 800h), so a ROM segment that isn't a multiple of 800h (eg, F600h, the PC's ROM BASIC) can't be reflected to, and DMA buffers more than 64K above 400h have none yet (FDC$ sends such diskette transfers through its own buffer); a few more (or temporary ones) may be needed.

{% include footer.html prev="Data Structures:../data/" next="" %}
