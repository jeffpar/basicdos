---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Protected Mode and Memory Management (Design)
permalink: /docs/bdtech/mmu/
---

{% include header.html %}

**NOTE**: This is a design document for work in progress on the `mmu` branch.  Everything here is tentative, and only [Phase 1](#phases) has been implemented.

### Goals

- Let BASIC-DOS use the extended memory and protected mode of an 80286 or 80386, while the same binaries still run on an 8086 or 8088 (with no extra memory used there).
- Keep all knowledge of descriptors, selectors, and physical memory in one built-in driver, **CPU$**, which loads first, determines the processor type, and on a protected-mode processor, manages a physical memory arena and the GDT, IDT, and LDT.
- Restructure the rest of BASIC-DOS (drivers, kernel, and COMMAND.COM) so that it can run in either mode, using CPU$ to map existing blocks of code and data to selectors, and to allocate and free extended memory.

### Baseline Machine

All `mmu` work is tested on a 2Mb IBM PC AT: `ibm5170` (80286, AT BIOS revision 3) with `--ram=2M`, which pc.js now splits into 640K of conventional memory (0-9FFFFh) and 1408K of extended memory (100000h-25FFFFh), like the PCjs 2048K PC AT machines.  On the `mmu` branch, [boot.sh](../../../boot.sh) passes `--ram=2M` for every configuration.  For example:

	./boot.sh fpe 'VER;\TESTS\MISC\CPUTEST'

The 80386 path (which returns to real mode by clearing PE instead of resetting the CPU) is tested with `compaq386` (a COMPAQ DeskPro 386), and the 8086 path (where CPU$ unloads itself) with `ibm5160`, which `tools/tests/quick.sh` uses.

### The CPU$ Driver

CPU$ is the first driver in BASDEV.COM (ahead of NUL), so it's initialized before all the others.  It determines the processor type:

1. An 8086 or 80186 decrements SP before PUSH SP stores it, whereas an 80286 or later stores the original value.
2. An 80186 masks shift counts to 5 bits, so shifting 1 left 33 times leaves 2 (instead of 0 on an 8086).
3. In real mode, an 80286 always clears FLAGS bits 12-15, whereas an 80386 lets software set bits 12-14 (IOPL and NT).

It stores the result in CPU_TYPE (0:512h), as one of the CPUTYPE_* values in cpu.inc (0 = 8086/8088, 1 = 80186/80188, 2 = 80286, 3 = 80386 or later), which DEVINIT sets to zero beforehand in case CPU$ is skipped (`SKIP=CPU$`).

CPU$ unloads itself (taking no memory) unless the processor is an 80286 or later, the BIOS reports at least 64K of extended memory (INT 15h function 88h), A20 can be enabled (with the 8042 keyboard controller, as on a PC AT), and a switch to protected mode and back succeeds.  Otherwise, it stays loaded, enables A20 permanently, builds the arena and descriptor tables described below, and makes its functions available through DDINT_CPU (0:513h), a 5-byte far jump in low memory like the other DDINT entry points.  DEVINIT initializes DDINT_CPU to `STC`, `RETF`, so a call fails (with carry set) whenever CPU$ isn't loaded.

When it stays loaded, CPU$ takes 1K of conventional memory (its initialization code is discarded), plus the 64K system area in extended memory.

#### Functions

Call DDINT_CPU with a function number in AH.  Physical addresses and lengths are 32-bit byte values: addresses in DX:CX and lengths in SI:DI (high:low).  Every function runs with interrupts disabled, preserves BX, SI, DI, BP, DS, and ES, and returns carry clear on success, or carry set with an error code in AX.

| AH | Function | Inputs | Outputs |
|----|----------|--------|---------|
| 00h | CPU_GETINFO | | AL = CPU type, AH = CPUF_* flags, DX:CX = length of largest free block |
| 01h | CPU_ALLOC | AL = SELF_* flags, BX = owner, SI:DI = length | AX = first selector (0 if SELF_NONE), DX:CX = address |
| 02h | CPU_FREE | DX:CX = address from CPU_ALLOC | |
| 03h | CPU_MAP | AL = SELF_* flags, DX:CX = address, SI:DI = length | AX = first selector, CX = number of selectors |
| 04h | CPU_UNMAP | BX = first selector, CX = number of selectors (0 = 1) | |
| 05h | CPU_QUERY | BX = PMB number (0 = first), ES:DI -> 16-byte buffer | PMB copied to ES:DI |

SELF_LDT (01h) requests LDT selectors instead of GDT selectors, SELF_CODE (02h) requests execute/read code segments instead of read/write data segments, and SELF_NONE (04h) makes CPU_ALLOC allocate memory without any selectors.  A block of more than 64K gets one selector for every 64K (each 8 more than the last, so that `selector + 8 * n` addresses the *n*th 64K), and the last one's limit covers the rest.  CPU_ALLOC rounds lengths up to a multiple of 16, so every block starts on a paragraph boundary; CPU_MAP maps exactly the requested length.  Errors are ERR_INVALID (bad function, zero length, unknown PMB, or a selector that can't be unmapped), ERR_NOMEMORY (no block big enough, with DX:CX = length of the largest free block; or no free PMB or descriptors), and ERR_BADADDR (CPU_FREE of an address that CPU_ALLOC didn't return).

CPUF_PMOK (02h) means the protected-mode self-test passed (always, if CPU$ is loaded), and CPUF_PM (01h) will mean that the processor is running in protected mode (never, so far).

In protected mode, the same functions will be reached through a call gate (SEL_CPU, below), so callers will do `call SEL_CPU:0` instead of calling DDINT_CPU.

**Why DDINT_CPU**: an IOCTL interface (like FPU$'s IOCTL_GETFPU) would make every caller open the device, and the callers will mostly be the kernel and other drivers.  DDINT_UTIL is the DOS's entry point for drivers, so it isn't available until sysinit, and it's the wrong direction (CPU$ is called *by* the DOS).  A software interrupt would work in both modes, but uses up a vector; the call gate gives protected-mode callers the same kind of fixed far address that DDINT_CPU gives real-mode callers.

### Memory Map (tentative)

Physical memory on the baseline 2Mb PC AT:

| Address | Length | PMB type | Contents |
|---------|--------|----------|----------|
| 000000h | 1K | DOS | Real-mode interrupt vector table |
| 000400h | 256 | DOS | ROM BIOS data area |
| 000500h | 1120 | DOS | BASIC-DOS low memory: CPU_TYPE (512h), DDINT_CPU (513h), DPT, DDINT entry points, disk buffers |
| 000960h | | DOS | Drivers: CPU$ (first, if loaded), NUL, VKD$, ..., then BASDOS.COM, its tables, and the MCB chain |
| 0A0000h | 384K | RSVD | Video memory, adapter ROMs, and the system ROM (not RAM) |
| 100000h | 64K | SYS | CPU$ system area (the HMA; see below) |
| 110000h | 1344K | FREE | Extended memory available to CPU_ALLOC |
| 260000h | | | End of memory |

The PMB types (PMBTYPE_* in cpu.inc) are FREE (0), USED (1, allocated by CPU_ALLOC), DOS (2, conventional memory, which DOS manages with MCBs), SYS (3), and RSVD (4).  The conventional memory PMB's length comes from the BIOS (MEMORY_SIZE), so a machine with less than 640K has a larger RSVD block.

#### The System Area

CPU$ keeps everything it owns, other than its code, in the first 64K of extended memory, which (with A20 enabled) is addressable in real mode as segment FFFFh, and in protected mode with selector SEL_SYS, whose base is FFFF0h, so the same offsets work in both modes.  Its code is the same in both modes, too: it gets its data segment from the mode (SMSW), and never writes through CS.

| Offset | Linear | Contents |
|--------|--------|----------|
| 0000h | 0FFFF0h | Last 16 bytes of the ROM BIOS (unusable) |
| 00D0h | 1000C0h | CALL 5 trampoline: `JMP 0000:00C0h` (see below) |
| 0100h | 1000F0h | SYSVARS: signature, CPU type and flags, PMB count, saved real-mode SS:SP and CS, and the GDTR/IDTR values |
| 0200h | 1001F0h | PMB table (128 entries of 16 bytes) |
| 0A00h | 1009F0h | IDT (256 gates) |
| 1200h | 1011F0h | GDT (256 descriptors) |
| 1A00h | 1019F0h | LDT (1024 descriptors) |
| 3A00h | 1039F0h | Unused (about 50K; eg, for CPU$ code or kernel code that only runs on an 80286 or later) |

A PSP's CALL 5 (a far call to F01D:FEF0h, for example) reaches 0:00C0h (INT_DOSCALL5) only by wrapping around at 1Mb, so with A20 enabled, it lands at 1000C0h instead; like DOS 5 with DOS=HIGH, CPU$ puts a far jump to 0:00C0h there.

Before writing to the system area, CPU$ checks that A20 really is enabled (that SYSVARS isn't aliased to 0:00F0h), and on every function call, it checks the SYSVARS signature and re-enables A20 if necessary (eg, if a program used the BIOS block move function, INT 15h function 87h, which turns A20 off).

#### Fixed GDT Selectors

| Selector | Type | Base | Use |
|----------|------|------|-----|
| 00h | | | Null selector |
| 08h | SEL_SYS | 0FFFF0h | Data: the system area |
| 10h | SEL_LDTD | 1019F0h | The LDT (for LLDT) |
| 18h | SEL_CPUCODE | CPU$ | Code: the CPU$ driver |
| 20h | SEL_LOW | 000000h | Data: the first 64K (interrupt vectors, BIOS data, BASIC-DOS low memory) |
| 28h | SEL_STACK | caller's SS | Data: the caller's stack, set on every switch to protected mode |
| 30h | SEL_TMP | 110000h | Data: scratch (the self-test writes through it) |
| 38h | SEL_CPU | | Call gate to CPU$'s function entry point |

Selectors 40h-7F8h (GDT) and 04h-1FFCh (LDT) are allocated by CPU_ALLOC and CPU_MAP; a descriptor whose access byte is zero is free.  All descriptors are 80286-format (the 80386 fields are zero, except bits 31-24 of the base, for blocks above 16Mb), DPL 0, and all IDT entries are 80286 interrupt gates that point to CPU$'s fault handler (see below).

### Physical Memory Arena

The arena is a table of Physical Memory Blocks (PMBs) in address order, covering all memory from 0 to the end of extended memory, with the last PMB marked PMBSIG_LAST ('Z'), like the last MCB:

| Field | Size | Contents |
|-------|------|----------|
| PMB_SIG | byte | 'M', or 'Z' for the last PMB |
| PMB_TYPE | byte | PMBTYPE_* |
| PMB_OWNER | word | Owner (from CPU_ALLOC's BX), or zero |
| PMB_ADDR | dword | Physical address |
| PMB_LEN | dword | Length, in bytes |
| PMB_SEL | word | First selector (if any) |
| PMB_NSEL | word | Number of selectors |

CPU_ALLOC uses the first free block that's big enough (splitting it if necessary), and CPU_FREE frees the block's selectors and merges it with any free neighbors.

Unlike MCBs, PMBs aren't stored in front of the memory they describe:

- the arena has to describe memory that isn't RAM (eg, 640K-1Mb), where no header could be stored;
- headers in extended memory couldn't be read or written in real mode, which is where CPU$ is called from until the kernel runs in protected mode;
- blocks need no header, so they stay aligned, and a block can be mapped by a selector with no offset; and
- a program that writes past the end of its block can't damage the arena.

The cost is a fixed number of PMBs (128 for now; a CONFIG.SYS option could change it).

### Switching Modes

CPU$'s `pm_call` runs a function in protected mode and returns to real mode, with interrupts and NMI disabled.  It points SEL_STACK at the caller's stack, saves SS:SP, loads the GDTR and IDTR, sets PE with LMSW, jumps to SEL_CPUCODE, and loads DS, ES, and SS with SEL_SYS and SEL_STACK, and LDTR with SEL_LDTD.

An 80386 returns to real mode by clearing PE (`MOV CR0,EAX`, assembled as bytes, since MASM 4.00 knows only 80286 instructions).  An 80286 can't, so before switching, `pm_call` sets the CMOS shutdown code (CMOS register 0Fh) to 0Ah and stores the address of `pm_resume` in 40:67h, and to return, it pulses the 8042's reset line (command FEh), as the BIOS's own block move (INT 15h function 87h) does.  After the reset, the BIOS sees the shutdown code and jumps through 40:67h without initializing anything else (both the original 1984 PC AT BIOS and the 1985 revision 3 support shutdown code 0Ah), and `pm_resume` restores SS:SP and the real-mode IDTR, clears the shutdown code (so that a later CTRL-ALT-DEL does a normal POST), and enables NMI again.  Because the shutdown code is set before switching, a "triple fault" (which resets the processor) also returns to `pm_resume`, and every IDT entry points to a fault handler that returns to real mode, too, so a bug in protected mode makes the caller's test fail instead of hanging the machine.

The CPU$ self-test (`pm_test`) checks that PE is set and writes and reads back a word at 110000h (through SEL_TMP), which real mode can't reach; CPU$ stays loaded only if that works.

### Running BASIC-DOS in Protected Mode {#plan}

Staying in protected mode after CPU$ initializes is the goal, but the rest of BASIC-DOS assumes real mode in several ways, and each needs its own solution:

1. **BIOS calls**.  The drivers call the ROM BIOS (INT 10h, 13h, 16h, 17h, and 1Ah), which only runs in real mode.  An 80386 can run it in virtual-8086 mode, but an 80286 can only switch back to real mode, which takes a processor reset (OS/2 1.x did this for its real-mode session).  So on an 80286, each BIOS call from protected mode would cost a reset (and a triple fault is faster than the 8042 reset that the BIOS uses).  The alternatives are drivers that don't use the BIOS in protected mode (the COM driver already doesn't, and disk I/O through the controllers directly would be a large addition), or real-mode drivers that are called through a mode switch.
2. **Hardware interrupts**.  The master PIC's IRQs 0-7 use vectors 08h-0Fh, which are also processor exceptions (eg, 0Dh is a general protection fault).  CPU$ would reprogram the master PIC (eg, to 50h-57h), and copy vectors 08h-0Fh of the real-mode vector table to 50h-57h for whenever the processor is in real mode.  The slave PIC (70h-77h) can stay where it is.  The IDT would then have protected-mode handlers for each interrupt the drivers handle (CLOCK$, VKD$, COM, MOUSE$, and the disk drivers' BIOS interrupts), or gates that "reflect" interrupts to their real-mode handlers.
3. **Segment arithmetic**.  The kernel and COMMAND.COM compute segments from paragraphs (eg, walking the MCB chain, `mov ax,es` + `inc ax` to get from an MCB to its block, PSP and environment segments, and paragraph rounding), use fixed segments (0 for low memory, 40h, B000h and B800h for video, and F000h for the ROM), and use `push cs` + `pop ds` and then write data (a code segment can't be written in protected mode).  Each case needs a selector: for example, DOS_MEM_ALLOC could return a selector from CPU_MAP for the new block (keeping the MCB in the arena below 640K), the fixed segments would become fixed selectors (SEL_LOW, plus SEL_VIDEO and SEL_ROM), and each module with a code segment would also get a data alias (eg, the next selector).  The first step is an inventory of every such case.
4. **DOS programs**.  COM and EXE programs are real-mode programs.  On an 80386 they can run in virtual-8086 mode; on an 80286, only in real mode, so a session running a DOS program would switch the processor back to real mode while it runs (much like OS/2's DOS session), and other sessions would wait.
5. **COMMAND.COM**.  The biggest payoff: BASIC programs, variables, strings, and arrays limited only by memory, with each block in extended memory and addressed by a selector.

#### Phases {#phases}

1. **Done**: CPU$ (processor detection, A20, the arena, GDT, IDT, and LDT, a self-tested switch to protected mode and back, and the CPU_* functions, all called in real mode), CPU_TYPE and DDINT_CPU in low memory, `--ram=2M` in pc.js, and CPUTEST.COM (in TESTS\MISC on test disks), which prints the arena and checks every function.
2. **Kernel interfaces**: DOS functions for extended memory that record the owner (the PSP), so that a program's blocks are freed when it ends; a CPU_MOVE function (copying between physical addresses through `pm_call`, or on an 80286 perhaps LOADALL, which PCjs supports and which avoids the reset); and MEM showing the arena.
3. **COMMAND.COM in extended memory, from real mode**: eg, keeping the copy of the transient part, or large arrays, in extended memory with CPU_MOVE.
4. **Interrupts in protected mode**: PIC remapping and IDT reflection to real-mode handlers, and measuring what a BIOS call through a reset costs on an 80286.
5. **A protected-mode kernel**: the segment-arithmetic inventory and fixes, staying in protected mode after CPU$ initializes, and running DOS programs in real mode (80286) or virtual-8086 mode (80386).

### Open Questions

- **80286 or 80386 first?**  Every BIOS call or DOS program on an 80286 costs a mode switch through a reset, whereas an 80386 has virtual-8086 mode.  The 80286 baseline keeps the design honest (16-bit descriptors, 64K segments, and no paging), but a protected-mode kernel might be practical only on an 80386, with the 80286 limited to phases 2 and 3.
- **The HMA**: putting the system area in the HMA costs no conventional memory and is reachable in both modes, but A20 stays enabled, so besides the CALL 5 trampoline, programs that depend on wrapping at 1Mb could break (eg, EXEPACK-compressed programs loaded in the first 64K report "Packed file is corrupt").
- **Owners**: should PMB owners be PSPs (freed when a program ends) or sessions?
- **Privilege levels**: everything is DPL 0 for now; DOS programs and BASIC code could run at ring 3 later, which would need a TSS and DPL 3 selectors.
- **Table sizes**: 128 PMBs, 256 GDT entries, and 1024 LDT entries are guesses; one LDT per session (or per program) may make more sense than a single LDT.

{% include footer.html prev="Data Structures:../data/" next="" %}
