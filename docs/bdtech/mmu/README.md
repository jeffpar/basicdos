---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Protected Mode and Memory Management (Design)
permalink: /docs/bdtech/mmu/
---

{% include header.html %}

**NOTE**: This is a design document for work in progress on the `mmu` branch.  Everything here is tentative; only [Phase 1](#phases) has been implemented, along with an experimental [protected-mode probe](#probe) that runs the ROM BIOS at ring 0 on behalf of ring 3 code.  The [Protected Mode demo](/demos/mmu/) runs the current CPU$ on a 2Mb PC AT with the PCjs Debugger, and summarizes where things stand.

### Goals

- Let BASIC-DOS use the extended memory and protected mode of an 80286 or 80386, while the same binaries still run on an 8086 or 8088 (with no extra memory used there).
- Keep all knowledge of descriptors, selectors, and physical memory in one built-in driver, **CPU$**, which loads first, determines the processor type, and on a protected-mode processor, manages a physical memory arena and the GDT, IDT, and LDT.
- Restructure the rest of BASIC-DOS (drivers, kernel, and COMMAND.COM) so that it can run in either mode, using CPU$ to map existing blocks of code and data to selectors, and to allocate and free extended memory.

### Target and Test Machines

The design targets the IBM PC AT: `ibm5170` (80286, AT BIOS revision 3) with `--ram=2M`, which pc.js now splits into 640K of conventional memory (0-9FFFFh) and 1408K of extended memory (100000h-25FFFFh), like the PCjs 2048K PC AT machines.  On the `mmu` branch, [boot.sh](../../../boot.sh) passes `--ram=2M` for every configuration.

Every change is tested on three machines, with `tools/tests/mmutest.sh`, which runs quick.sh's floppy tests and CPUTEST on each:

| Name | Machine | CPU$ |
|------|---------|------|
| `8088` | IBM PC XT (`ibm5160`) | Unloads itself (CPU type 0) |
| `real` | 2Mb PC AT with `CPU=8088` in CONFIG.SYS | Unloads itself (CPU type 0), so BASIC-DOS runs in real mode with A20 disabled |
| `pm` | 2Mb PC AT without `CPU=8088` | Manages extended memory (and eventually, runs BASIC-DOS in protected mode) |

Because real mode is the only mode they've been tested in, every other configuration that boots on a PC AT or DeskPro 386 (the demo diskettes and hard disk, the test configurations that boot.sh uses, and mk.sh's build configuration) has `CPU=8088` in its CONFIG.SYS; only the `pm` test, `tools/tests/pmprobe.sh`, and the Protected Mode demo leave it out.  The 80386 path (which returns to real mode by clearing PE instead of resetting the CPU) is still tested occasionally with `compaq386` (a COMPAQ DeskPro 386), but only the PC AT is a target for now.

### The CPU$ Driver

CPU$ is the first driver in BASDEV.COM (ahead of NUL), so it's initialized before all the others.  It determines the processor type:

1. An 8086 or 80186 decrements SP before PUSH SP stores it, whereas an 80286 or later stores the original value.
2. An 80186 masks shift counts to 5 bits, so shifting 1 left 33 times leaves 2 (instead of 0 on an 8086).
3. In real mode, an 80286 always clears FLAGS bits 12-15, whereas an 80386 lets software set bits 12-14 (IOPL and NT).

It stores the result in CPU_TYPE (0:512h), as one of the CPUTYPE_* values in cpu.inc (0 = 8086/8088, 1 = 80186/80188, 2 = 80286, 3 = 80386 or later), which DEVINIT sets to zero beforehand in case CPU$ is skipped (`SKIP=CPU$`).  A `CPU=8088` line in CONFIG.SYS makes CPU$ store 0 (8086/8088) and unload itself, as it does on an 8088, without enabling A20.

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
| 3A00h | 1039F0h | Probe only: PROBELOG, with up to 120 events (see [the probe](#probe)) |
| 3E00h | 103DF0h | Probe only: TSS |
| 3F00h | 103EF0h | Probe only: IDT (256 gates) |
| 4700h | 1046F0h | Probe only: ring 0 stack (4K) |
| 5700h | 1056F0h | Unused (about 42K; eg, for CPU$ code or kernel code that only runs on an 80286 or later) |

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

### The Protected-Mode Probe {#probe}

The plan is to stay in protected mode after CPU$ initializes, run sysinit and sessions at ring 3, and switch to ring 0 to call the kernel, the drivers, and the BIOS.  That raises a question that's easiest to answer by trying it: can the ROM BIOS run in protected mode at all, given the right selectors?  So CPU$ has an experimental probe, which runs only if CONFIG.SYS has a `CPU=PROBE` line (DEVINIT passes the CONFIG.SYS text to every built-in driver's INIT in DDP_PTR).

After its self-test, CPU$ switches to protected mode, sets up the environment below, and "returns" to a short routine (`probe3`) at ring 3, which calls the BIOS:

- INT 10h function 0Eh (writing "CPU$ ring 3"), INT 11h, INT 12h, INT 15h function 88h, and INT 16h function 01h;
- INT 13h functions 00h and 02h (resetting drive A: and reading its boot sector, by DMA); and
- INT 1Ah function 00h, until the tick count has gone up by 18 (so IRQ 0 must work).

Then it calls back to ring 0, and CPU$ restores everything, returns to real mode, prints a summary, and BASIC-DOS boots as usual.  The probe's code (about 1.4K) is all part of CPU$'s initialization code, so it's discarded either way.

	tools/tests/pmprobe.sh [ibm5170 or compaq386] [pc.js arguments...]

builds a boot floppy with that CONFIG.SYS (in tools/pc/disks/pmprobe), lists breakpoint addresses for the probe's entry points (from CPUDEV.MAP), and boots it on the baseline 2Mb PC AT (or a 2Mb DeskPro 386), with BASIC-DOS's console on COM1 (ie, the terminal).

#### The Probe's Environment

- **An identity GDT.**  The GDT fills 64K (8192 descriptors, in the memory at 110000h that SEL_TMP maps).  After the fixed selectors (with a TSS at 28h, in place of SEL_STACK), every descriptor's base is its selector times 16, with a 64K limit, so any real-mode segment that's a multiple of 8 can be loaded at ring 0 and addresses the same memory: 0040h (the BIOS data), A000h-B800h (video memory), C000h (adapter ROMs), F000h (the system ROM), and every 128-byte boundary of conventional memory.  Descriptors below C000h are read/write data, and from C000h up, execute/read code (a descriptor can't be both).  All of them are DPL 0.
- **A TSS**, which gives ring 0 a 4K stack in the system area.
- **Three LDT entries for ring 3** (DPL 3): 0007h for CPU$'s code, 000Fh for a 2K data and stack segment (in the scratch memory that DEVINIT passes in DDPI_BUFPTR), and 0017h, a call gate back to ring 0 (`probe_exit`).
- **An IDT**:

| Vectors | Gate DPL | Handler |
|---------|----------|---------|
| 00h-02h, 06h-0Fh | 0 | Exceptions (`exc_common`) |
| 03h-05h, 10h-6Fh, 80h-FFh | 3 | Software interrupts (`sw_int`) |
| 70h-77h | 0 | IRQ 8-15 (`irq_common`), reflected to vectors 70h-77h |
| 78h-7Fh | 0 | IRQ 0-7 (the master PIC moves from 08h to 78h), reflected to vectors 08h-0Fh |

**Reflection**: `sw_int` gets the vector from the caller's `INT n` (or `INT3`), and `irq_common` from its IRQ's stub; both call the handler in the real-mode vector table, through its identity selector, at ring 0, as a real-mode INT would (with FLAGS, CS, and IP on the stack, and interrupts disabled).  The handler's segment must be a multiple of 8, and C000h or higher (ie, ROM), or the interrupt isn't reflected (a software interrupt returns with carry set, and an IRQ just gets an EOI).  `sw_int` passes the handler's CF, ZF, SF, and OF back to the caller (eg, the carry from INT 13h, and the zero flag from INT 16h function 01h).

**DMA**: the diskette BIOS calculates its DMA address as ES * 16 + BX, so for INT 13h functions 02h-05h, `sw_int` replaces the caller's ES:BX (whatever its selector) with an identity selector and offset for the same physical address while the BIOS runs, and restores them afterward.  With identity selectors, the logical address (segment * 16 + offset) is the physical address, so the BIOS's DMA calculation is right, as long as the buffer is below 1Mb.

**Exceptions**: vectors 08h-0Fh are also real-mode interrupts, and on the DeskPro 386, the BIOS's IRQ 9 handler issues `INT 0Ah` (to chain to IRQ 2's handler), which lands on the invalid-TSS exception's gate.  So `exc_common` first checks whether the frame (taken as having no error code) returns just past an `INT` for that vector (using VERR and LSL, so that the check itself can't fault), and if so, reflects it.  Then, a general protection fault with a zero error code, at ring 0, while DS or ES holds a null selector, is fixed by loading SEL_LOW (base 0) and retrying the instruction, because the BIOS loads DS with 0 to reach the interrupt vectors, which is a null selector in protected mode.  Any other exception ends the probe, as does a reset (eg, a triple fault), after which an 80286 resumes at `probe_resume`, which moves the master PIC back.

#### The Probe's Results

PROBELOG, at system area offset 3A00h (linear 1039F0h), holds the probe's status (1 running, 2 done, 3 ended by an exception, 4 ended by a reset), the exception that ended it (vector, error code, IP, and CS), counts of reflected interrupts and null selector fixes, the ring 3 results, and the first 120 events, starting at 103A30h (an event that repeats the previous one isn't logged).  Each event is 8 bytes: a kind ('S' software interrupt, 'I' hardware interrupt, 'N' not reflected, 'F' null selector fixed, 'X' exception that ended the probe), the vector, and the caller's AX (or the error code), IP, and CS.

Both machines get through the probe, and BASIC-DOS then boots normally:

| | IBM PC AT (80286, BIOS revision 3, CGA) | COMPAQ DeskPro 386 (VGA) |
|-|-|-|
| Software interrupts reflected | About 8,500 (mostly the INT 1Ah loop) | About 24,000 |
| Hardware interrupts reflected | 21 (IRQ 0 and 6) | 86 (IRQ 0, 6, and 9) |
| Null selector fixes | 20 | 17 |
| Diskette read (by DMA) | Succeeded (signature AA55h) | Succeeded |
| Timer ticks counted | 18 | 18 |

What the event logs show:

- **PC AT**: each INT 10h teletype call makes three nested INT 10h calls (functions 03h, 0Ah, and 02h).  INT 13h goes to the hard disk BIOS first, which passes diskette requests to INT 40h, and the diskette BIOS calls INT 15h functions 90h and 91h around its wait for IRQ 6.  The null selector faults come in pairs, at F000:2994h and F000:2998h: GET_PARM does `LDS SI,[78h]` with DS = 0, and then reads through the DPT pointer's segment, which is also 0 (BASIC-DOS's boot sector sets vector 1Eh to 0:522h; 0050:0022h, the same address through an identity selector, would avoid the second fault).  The timer handler issues INT 1Ch.
- **DeskPro 386**: INT 10h goes through the VGA BIOS (INT 6Dh, at C000h), which loads DS with 0 for every character (fixed at C000:33FEh).  The diskette code faults at F000:EC69h, D4D0h, and ED38h, and IRQ 9 (about 60 per second) chains to IRQ 2's handler with INT 0Ah.

#### Debugging the Probe

For example:

	tools/tests/pmprobe.sh --halt
	pm_probe     bp %1295
	probe3       bp %122B
	...
	>> bp %122B
	>> g
	bp %122B hit
	...
	>> bc *
	>> t 40

Linear breakpoints (`%`) work in either mode, and once the probe has started, `r` shows each selector with its base and limit (eg, `CS=0007[000960,FFFF]` at ring 3, `CS=0018[000960,FFFF]` in `sw_int`, and `CS=F000[0F0000,FFFF]` in the BIOS), along with the GDTR, IDTR, LDTR, and TR.  Clear a breakpoint (`bc *`) before tracing from it, or the trace stops there again.  Tracing from `probe3` goes through its `INT 10h` to `sw_int` at ring 0 (on the ring 0 stack, SS = 0008h), through the `CALL FAR` to the BIOS's INT 10h entry (F000:F065h), and then to `CALL DDS`, which loads DS with 0040h, the BIOS data's identity selector.  When the machine is running, CTRL-D enters the debugger, and after the probe, `db %1039F0 l400` dumps PROBELOG.

#### What the Probe Shows {#feasibility}

1. **The ROM BIOS can run at ring 0 in protected mode**, on both machines and for every function tried, with three mechanisms: identity selectors (so the BIOS's fixed segments, and its segment arithmetic, including DMA addresses, still work), the fix for a null DS or ES, and reflection of software and hardware interrupts to the real-mode vector table.  Ring 3 code, with its own selectors, can call it through interrupt gates.  Nothing has needed replacing yet.
2. **What the BIOS can't do in protected mode**: functions that switch modes themselves (INT 15h functions 87h, block move, and 89h, switch to protected mode), and DMA to or from a buffer above 1Mb (the BIOS's DMA address is ES * 16 + BX).  CPU$ would provide the former (eg, a CPU_MOVE function), and disk drivers would copy through a buffer below 1Mb for the latter.  Not tried yet: the hard disk BIOS (which uses PIO through ES:BX, so identity selectors should work), diskette writes, INT 10h mode sets (which, like GET_PARM, load DS with 0), INT 14h, INT 17h, and INT 1Ah's clock functions.
3. **BASIC-DOS's own code can't run in protected mode unchanged**, at either ring, for reasons that don't apply to the BIOS:
   - **Segments that aren't multiples of 8**: the drivers, the kernel, and programs are loaded at any paragraph (CPU$ itself is at 0096h), and only multiples of 8 have identity selectors (a selector's low 3 bits are its table and privilege bits, so 0096h is LDT entry 12h with RPL 2).  Each such segment needs its own alias, or must be loaded at a 128-byte boundary.
   - **Writes through CS**: protected-mode code segments are never writable, and the drivers write through CS about 63 times (the kernel about 18, COMMAND about 5, and DEBUG about 15).  Each needs a data alias (another selector for the same memory) instead.
   - **Segment 0**: the drivers and the kernel reach the BIOS data and BASIC-DOS's low memory with DS or ES set to 0 (in about 54 places).  The probe's fix handles that at ring 0 (with a fault for every load), but not at ring 3 (SEL_LOW is DPL 0), and loading SEL_LOW directly would be faster.
   - **Ring 3 selectors**: CS and SS selectors must have RPL 3 at ring 3, so an identity selector there is the segment plus 3, and any arithmetic on CS or SS (eg, `mov ax,cs` followed by `add`) is off by 3 paragraphs.
   - **Computed segments**: walking MCBs (`inc ax` from an MCB to its block), PSP and environment segments, paragraph rounding, and so on, as noted [below](#plan).
4. **So sysinit isn't a good first ring 3 candidate**: it relocates the kernel (computing segments from MEMORY_SIZE), writes the interrupt vectors, and builds every table, which is all ring 0 work.  A better order:
   1. keep the probe's environment (the identity GDT, reflection, and the fixes) as CPU$'s protected-mode foundation;
   2. make DEVINIT, the drivers, and the kernel protected-mode-safe one change at a time, testing each in real mode first (eg, 128-byte load boundaries, data aliases instead of writes through CS, and a fixed selector for low memory), with the probe's log showing what still faults;
   3. run the drivers' INIT, and then the kernel, at ring 0, with BIOS calls reflected; and
   4. move COMMAND.COM's sessions (ie, BASIC code) to ring 3, calling the kernel through INT 21h gates.

   DOS programs would still need real mode (on an 80286) or virtual-8086 mode (on an 80386).

### Running BASIC-DOS in Protected Mode {#plan}

Staying in protected mode after CPU$ initializes is the goal, but the rest of BASIC-DOS assumes real mode in several ways, and each needs its own solution.  This design targets the PC AT (an 80286, with IBM's BIOS); the 80386 (eg, virtual-8086 mode for DOS programs) and other BIOSes, such as the DeskPro 386's, are for later.

1. **BIOS calls**.  The drivers call the ROM BIOS (INT 10h, 13h, 14h, 17h, and 1Ah).  The [probe](#probe) shows that the BIOS can run at ring 0 in protected mode, with identity selectors, a fix for null selectors, and reflection through the real-mode vector table, so a BIOS call needn't cost a mode switch, which on an 80286 means a processor reset (as in OS/2 1.x's real-mode session).  The remaining BIOS functions the drivers use still need trying, and a few (eg, INT 15h functions 87h and 89h) will need CPU$ replacements.
2. **Hardware interrupts**.  The master PIC's IRQs 0-7 use vectors 08h-0Fh, which are also processor exceptions (eg, 0Dh is a general protection fault).  The probe moves the master PIC to 78h-7Fh, next to the slave PIC (70h-77h), and its IDT reflects each IRQ to its real-mode handler, which works for the BIOS's handlers; the drivers' handlers (CLOCK$, VKD$, COM, MOUSE$) will need protected-mode-safe code, or protected-mode handlers of their own.  Vectors 08h-0Fh can still be software interrupts (eg, INT 0Ah from a BIOS's IRQ 9 handler), so their gates must tell the two apart.
3. **Segment arithmetic**.  The kernel and COMMAND.COM compute segments from paragraphs (eg, walking the MCB chain, `mov ax,es` + `inc ax` to get from an MCB to its block, PSP and environment segments, and paragraph rounding), use fixed segments (0 for low memory, 40h, B000h and B800h for video, and F000h for the ROM), and use `push cs` + `pop ds` and then write data (a code segment can't be written in protected mode).  Each case needs a selector: for example, DOS_MEM_ALLOC could return a selector from CPU_MAP for the new block (keeping the MCB in the arena below 640K), the fixed segments would become fixed selectors (SEL_LOW, plus SEL_VIDEO and SEL_ROM), and each module with a code segment would also get a data alias (eg, the next selector).  The first step is an inventory of every such case.
4. **DOS programs**.  COM and EXE programs are real-mode programs.  On an 80386 they can run in virtual-8086 mode; on an 80286, only in real mode, so a session running a DOS program would switch the processor back to real mode while it runs (much like OS/2's DOS session), and other sessions would wait.
5. **COMMAND.COM**.  The biggest payoff: BASIC programs, variables, strings, and arrays limited only by memory, with each block in extended memory and addressed by a selector.

#### Mode-Independent Code {#modeless}

The first step toward staying in protected mode is to change the drivers and the kernel (everything that will run at ring 0) so that the same code runs in either mode, by using only segment values that are also valid selectors, and by never writing to a code segment.  The rules, *in progress*:

1. **BIOS data through segment 40h**: the ROM BIOS data area is addressed as segment 40h (offsets 00h-FFh), as the BIOS itself does, instead of segment 0.  In protected mode, 40h is an identity selector.
2. **BASIC-DOS low memory through segment 50h**: CPU_TYPE, the DDINT entry points, the DPT, the disk buffers, and the rest of BASIC-DOS's data at 500h-95Fh are addressed as segment 50h.
3. **Interrupt vectors through CPU$**: segment 0 is the null selector, so vectors will be read and written with CPU$ functions (eg, CPU_GETVEC and CPU_SETVEC), which in protected mode can also maintain the IDT.  So CPU$ must stay loaded on every processor, keeping just a small core (DDINT_CPU, CPU_GETINFO, and the vector functions) on an 8088 or with `CPU=8088`, and CPU$ can no longer be skipped.
4. **No writes through CS**: a protected-mode code segment can't be written, so each write with a CS override becomes a write through DS or ES holding the module's own segment, which in protected mode will be a data alias of its code segment (eg, if modules are loaded at 128-byte boundaries, the LDT could hold an execute/read descriptor for each identity data selector in the GDT, so that `CS AND 0FFF8h` would be the data alias in either mode).

The boot sector, which runs at 0:7C00h and then 0:0550h before anything else, keeps using segment 0, as do DEVINIT and sysinit where they load and relocate the drivers and the kernel, since they run only in real mode, at boot.

Inventory: about 250 references to the low memory symbols in bios.inc (86 of them in VKD$), interrupt vector accesses in the INIT code of CLOCK$, VKD$, MOUSE$, FDC$, and DEVINIT and in the kernel (DOS functions 25h and 35h, checking vectors when a program ends, and saving vectors when a session is locked), and about 80 writes through CS in the drivers and kernel.

#### Phases {#phases}

1. **Done**: CPU$ (processor detection, A20, the arena, GDT, IDT, and LDT, a self-tested switch to protected mode and back, and the CPU_* functions, all called in real mode), CPU_TYPE and DDINT_CPU in low memory, `--ram=2M` in pc.js, and CPUTEST.COM (in TESTS\MISC on test disks), which prints the arena and checks every function.
2. **Kernel interfaces**: DOS functions for extended memory that record the owner (the PSP), so that a program's blocks are freed when it ends; a CPU_MOVE function (copying between physical addresses through `pm_call`, or on an 80286 perhaps LOADALL, which PCjs supports and which avoids the reset); and MEM showing the arena.
3. **COMMAND.COM in extended memory, from real mode**: eg, keeping the copy of the transient part, or large arrays, in extended memory with CPU_MOVE.
4. **Interrupts in protected mode**: *started*: the [probe](#probe) remaps the master PIC, reflects software and hardware interrupts to real-mode handlers, and runs the BIOS at ring 0 for ring 3 code.  Next: try the rest of the BIOS functions that the drivers use (eg, with a hard disk), and make the probe's environment a permanent part of CPU$.
5. **A protected-mode kernel**: the segment-arithmetic inventory and fixes, staying in protected mode after CPU$ initializes, and running DOS programs in real mode (80286) or virtual-8086 mode (80386).

### Open Questions

- **The HMA**: putting the system area in the HMA costs no conventional memory and is reachable in both modes, but A20 stays enabled, so besides the CALL 5 trampoline, programs that depend on wrapping at 1Mb could break (eg, EXEPACK-compressed programs loaded in the first 64K report "Packed file is corrupt").
- **Owners**: should PMB owners be PSPs (freed when a program ends) or sessions?
- **Privilege levels**: everything is DPL 0 for now; DOS programs and BASIC code could run at ring 3 later, which would need a TSS and DPL 3 selectors.
- **Table sizes**: 128 PMBs, 256 GDT entries, and 1024 LDT entries are guesses; one LDT per session (or per program) may make more sense than a single LDT.
- **Identity selectors and allocation**: an identity GDT uses every GDT entry, so CPU_ALLOC and CPU_MAP would have to allocate LDT selectors only, or GDT entries for segments that nothing uses as real-mode segments.  The probe also gives the identity descriptors a fixed type (data below C000h, code from C000h up), so real-mode code in RAM, such as the drivers' interrupt handlers, would need code aliases.

{% include footer.html prev="Data Structures:../data/" next="" %}
