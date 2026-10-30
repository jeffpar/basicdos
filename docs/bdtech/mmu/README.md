---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Protected Mode and Memory Management (Design)
permalink: /docs/bdtech/mmu/
---

{% include header.html %}

**NOTE**: This is a design document for work in progress on the `mmu` branch.  Everything here is tentative; [Phase 1](#phases) has been implemented, CPU$ now manages all memory on every processor (see [The CPU$ Driver](#cpu)), and on an 80286, BASIC-DOS switches to protected mode while its drivers initialize, and enters the kernel's initialization in protected mode, where it currently stops (see [Protected-Mode Boot](#pmboot)).  The [Protected Mode demo](/demos/mmu/) runs the current CPU$ on a 2Mb PC AT with the PCjs Debugger, and summarizes where things stand.

### Goals

- Let BASIC-DOS use the extended memory and protected mode of an 80286 or 80386, while the same binaries still run on an 8086 or 8088 (with no extra memory used there).
- Keep all knowledge of descriptors, selectors, and physical memory in one built-in driver, **CPU$**, which loads first, determines the processor type, and on a protected-mode processor, manages a physical memory arena and the GDT, IDT, and LDT.
- Restructure the rest of BASIC-DOS (drivers, kernel, and COMMAND.COM) so that it can run in either mode, using CPU$ to map existing blocks of code and data to selectors, and to allocate and free extended memory.

### Target and Test Machines

The design targets the IBM PC AT: `ibm5170` (80286, AT BIOS revision 3) with `--ram=2M`, which pc.js now splits into 640K of conventional memory (0-9FFFFh) and 1408K of extended memory (100000h-25FFFFh), like the PCjs 2048K PC AT machines.  On the `mmu` branch, [boot.sh](../../../boot.sh) passes `--ram=2M` for every configuration.

Every change is tested on three machines, with `tools/tests/mmutest.sh`, which runs quick.sh's floppy tests and CPUTEST on each:

| Name | Machine | CPU$ |
|------|---------|------|
| `8088` | IBM PC XT (`ibm5160`) | The 8086 CPU$ stays (CPU type 0) |
| `real` | 2Mb PC AT with `CPU=8088` in CONFIG.SYS | The 8086 CPU$ stays (CPU type 0), so BASIC-DOS runs in real mode with A20 disabled |
| `pm` | 2Mb PC AT without `CPU=8088` | Switches to protected mode (for now, the boot stops in sysinit, so this test fails) |

Because real mode is the only mode they've been tested in, every other configuration that boots on a PC AT or DeskPro 386 (the demo diskettes and hard disk, the test configurations that boot.sh uses, and mk.sh's build configuration) has `CPU=8088` in its CONFIG.SYS; only the `pm` test, `tools/tests/pmboot.sh`, and the Protected Mode demo leave it out.  The 80386 path (which returns from its self-test to real mode by clearing PE instead of resetting the CPU) is still tested occasionally with `compaq386` (a COMPAQ DeskPro 386), but only the PC AT is a target for now.

### The CPU$ Drivers {#cpu}

CPU$ manages all memory, on every processor, so BASDEV.COM starts with two CPU$ drivers, of which exactly one stays loaded (a device name only has to be unique among the drivers that stay, since only they are linked into the chain): the 80286 driver (cpudev.asm), followed by the 8086 driver (cpu86dev.asm).  The 80286 driver, which is initialized first, determines the processor type:

1. An 8086 or 80186 decrements SP before PUSH SP stores it, whereas an 80286 or later stores the original value.
2. An 80186 masks shift counts to 5 bits, so shifting 1 left 33 times leaves 2 (instead of 0 on an 8086).
3. In real mode, an 80286 always clears FLAGS bits 12-15, whereas an 80386 lets software set bits 12-14 (IOPL and NT).

It stores the result in CPU_TYPE (0:512h), as one of the CPUTYPE_* values in cpu.inc (0 = 8086/8088, 1 = 80186/80188, 2 = 80286, 3 = 80386 or later).  A `CPU=8088` line in CONFIG.SYS makes CPU$ store 0 (8086/8088) and act as it does on an 8088, without enabling A20.

Neither CPU$ can be skipped (DEVINIT ignores `SKIP=CPU$`).  The one that stays makes its functions available through DDINT_CPU (0050:003Fh), a 5-byte far jump in low memory like the other DDINT entry points, which DEVINIT initializes to `STC`, `RETF`, so that a call fails (with carry set) until CPU$ initializes:

- **The 80286 driver** stays if the processor is an 80286 or later, the BIOS reports at least 64K of extended memory (INT 15h function 88h), A20 can be enabled (with the 8042 keyboard controller, as on a PC AT), and a switch to protected mode and back succeeds.  It keeps everything but its initialization code (about 3K), enables A20 permanently, and builds its [arena](#arena) (a table of PMBs) and descriptor tables in the 64K system area.  Otherwise (or with `CPU=8088`), it unloads itself.
- **The 8086 driver** stays unless CPU$ is already loaded.  It manages memory with a chain of MCBs, as DOS always has, starting in the paragraph after its code (about 1K), so every block that's allocated after it (eg, the other drivers, the kernel, and programs) has an MCB in the paragraph before it, which programs that walk the MCB chain can see.

Either way, DEVINIT claims what it's using as soon as CPU$ initializes (see [Claiming Memory at Boot](#claiming)).

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
| 06h | CPU_ALIAS | AL = SELF_* flags, BX = selector | AX = new selector, DX:CX = base address |
| 07h | CPU_PMODE | (none) | Protected mode, for good: CS, DS, ES, and SS are now selectors for the same memory, and AX = a data selector for the caller's CS (see [Protected-Mode Boot](#pmboot)) |
| 08h | CPU_REALLOC | DX:CX = address from CPU_ALLOC, SI:DI = new length | |
| 09h | CPU_MOVE | ES:BX -> MOVEPKT (source address, destination address, and length, all dwords) | |

SELF_LDT (01h) requests LDT selectors instead of GDT selectors, SELF_CODE (02h) requests execute/read code segments instead of read/write data segments, SELF_NONE (04h) makes CPU_ALLOC allocate memory without any selectors, SELF_RDONLY (08h) makes data read-only (or code execute-only), and SELF_USER (10h) makes the selectors DPL 3 (for programs at ring 3) instead of DPL 0.  CPU_ALLOC also takes SELF_LOW (20h) to allocate below 1Mb, SELF_HIGH (40h) to allocate from the top of the last free block that's big enough (below 1Mb), and SELF_AT (80h) to allocate the memory at DX:CX (which must be free); otherwise, it allocates from extended memory if there is any.  CPU_ALIAS creates a new selector, with the access rights that its SELF_* flags select, for the same memory as an existing one (it copies the base and limit), and CPU_UNMAP frees it; see [Code Aliases](#aliases).

Every function works the same way in either driver and in either mode, so callers needn't check which is which: in real mode, CPU_ALLOC, CPU_MAP, and CPU_ALIAS return the memory's segment instead of a selector (CPU_ALLOC returns 0 for a block above 1Mb, and CPU_MAP fails with ERR_INVALID unless the memory is below 1Mb and paragraph-aligned), a segment is its own alias, and CPU_UNMAP has nothing to do.  CPU_REALLOC changes a block's length (rounded up to a multiple of 16): a shorter block frees its end, and a longer one takes what it needs from the next block, which must be free and long enough (ERR_NOMEMORY otherwise, with the block unchanged); its selectors don't change.  CPU_MOVE copies any amount of memory between two physical addresses, correctly even if the source and destination overlap; in real mode, both must be below 1Mb.  With the 8086 driver, every block has an MCB in the paragraph before it, so CPU_ALLOC with SELF_AT needs that paragraph to be free too, and CPU_QUERY describes each MCB with a PMB.  A block of more than 64K gets one selector for every 64K (each 8 more than the last, so that `selector + 8 * n` addresses the *n*th 64K), and the last one's limit covers the rest.  CPU_ALLOC rounds lengths up to a multiple of 16, so every block starts on a paragraph boundary; CPU_MAP maps exactly the requested length.  Errors are ERR_INVALID (bad function, zero length, unknown PMB, a selector that can't be unmapped, or one that isn't in use for CPU_ALIAS), ERR_NOMEMORY (no block big enough, with DX:CX = length of the largest free block; or no free PMB or descriptors), and ERR_BADADDR (CPU_FREE of an address that CPU_ALLOC didn't return).

CPUF_PMOK (02h) means the protected-mode self-test passed (so the 80286 driver stayed, and CPU_PMODE is available), and CPUF_PM (01h) means that the processor is running in protected mode (after CPU_PMODE).  Like every other function, CPU_MOVE runs with interrupts disabled, so long moves delay interrupts.

In protected mode, the same functions will be reached through a call gate (SEL_CPU, below), so callers will do `call SEL_CPU:0` instead of calling DDINT_CPU.

**Why DDINT_CPU**: an IOCTL interface (like FPU$'s IOCTL_GETFPU) would make every caller open the device, and the callers will mostly be the kernel and other drivers.  DDINT_UTIL is the DOS's entry point for drivers, so it isn't available until sysinit, and it's the wrong direction (CPU$ is called *by* the DOS).  A software interrupt would work in both modes, but uses up a vector; the call gate gives protected-mode callers the same kind of fixed far address that DDINT_CPU gives real-mode callers.

### Memory Map (tentative)

Physical memory on the baseline 2Mb PC AT:

| Address | Length | PMB type | Contents |
|---------|--------|----------|----------|
| 000000h | 1K | DOS | Real-mode interrupt vector table |
| 000400h | 256 | DOS | ROM BIOS data area |
| 000500h | 1136 | DOS | BASIC-DOS low memory: CPU_TYPE (512h), DPT, DDINT entry points (530h, including DDINT_CPU at 53Fh), disk buffers |
| 000970h | | DOS | Drivers: CPU$ (first), NUL, VKD$, ..., then BASDOS.COM, its tables, and the MCB chain |
| 0A0000h | 384K | RSVD | Video memory, adapter ROMs, and the system ROM (not RAM) |
| 100000h | 64K | SYS | CPU$ system area (the HMA; see below) |
| 110000h | 1344K | FREE | Extended memory available to CPU_ALLOC |
| 260000h | | | End of memory |

The PMB types (PMBTYPE_* in cpu.inc) are FREE (0), USED (1, allocated by CPU_ALLOC), DOS (2, conventional memory, which DOS manages with MCBs), SYS (3), and RSVD (4).  The end of conventional memory comes from the BIOS (MEMORY_SIZE), so a machine with less than 640K has a larger RSVD block.  For now, the 80286 driver starts with conventional memory in three PMBs (USED below the drivers, USED for CPU$ itself, and FREE for the rest), and DEVINIT and sysinit [claim](#claiming) what they use; the DOS type isn't used yet.

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

A PSP's CALL 5 (a far call to F01D:FEF0h, for example) reaches 0:00C0h (INT_DOSCALL5) only by wrapping around at 1Mb, so with A20 enabled, it lands at 1000C0h instead; like DOS 5 with DOS=HIGH, CPU$ puts a far jump to 0:00C0h there.

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
| 48h | | | (Unused) |
| 50h | SEL_DDINT | 000500h | Code: the DDINT segment (50h), so the DDINT entry points (eg, DDINT_SETVEC, 0050:0049h) have the same addresses in either mode |
| A000h-B800h | | A0000h-B8000h | Data: identity selectors for video memory, every 800h |
| C000h-F800h | | C0000h-F8000h | Code: identity selectors for the adapter and system ROMs, every 800h, so the ROM BIOS can run at ring 0 with its own segments (eg, F000h) |

Selectors 58h-7F8h (GDT) and 04h-1FFCh (LDT) are allocated by CPU_ALLOC, CPU_MAP, and CPU_ALIAS (and CPU_PMODE); a descriptor whose access byte is zero is free.  All descriptors are 80286-format (the 80386 fields are zero, except bits 31-24 of the base, for blocks above 16Mb) and DPL 0 (unless SELF_USER is set).

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

CPU_ALLOC uses the first free block that's big enough (splitting it if necessary), unless SELF_HIGH or SELF_AT says otherwise, CPU_REALLOC shrinks a block or grows it into the free block after it, and CPU_FREE frees the block's selectors and merges it with any free neighbors.

Unlike MCBs, PMBs aren't stored in front of the memory they describe:

- the arena has to describe memory that isn't RAM (eg, 640K-1Mb), where no header could be stored;
- headers in extended memory couldn't be read or written in real mode, which is where CPU$ is called from until the kernel runs in protected mode;
- blocks need no header, so they stay aligned, and a block can be mapped by a selector with no offset; and
- a program that writes past the end of its block can't damage the arena.

The cost is a fixed number of PMBs (128 for now; a CONFIG.SYS option could change it).  The 8086 driver's arena is the MCB chain itself: programs on an 8086 expect to see MCBs, and conventional memory is all there is.

#### Claiming Memory at Boot {#claiming}

Once CPU$ has initialized, everything that runs during the boot declares the memory it uses, with either driver and in either mode, and moves memory with CPU$ rather than on its own:

1. **DEVINIT** (`chk_cpu`, before the first driver after CPU$ loads) claims two blocks with CPU_ALLOC and SELF_AT: the drivers that haven't initialized yet, and its own code, CONFIG.SYS data, and scratch buffer.  Then, while it's still in real mode (so that it can use the boot code's `read_file`), it allocates a block for BASDOS.COM at the top of conventional memory (SELF_LOW + SELF_HIGH), loads BASDOS.COM into it, and copies the CONFIG.SYS data after it.
2. **Each driver** that shrinks (or grows) during its initialization has the drivers after it moved with CPU_MOVE.  The one exception is on an 8086, where the 80286 CPU$ unloads itself before any CPU$ is loaded, so DEVINIT moves the drivers after it down itself.
3. **When the last driver is done** (`i9`), DEVINIT shrinks the drivers' block to fit (CPU_REALLOC), frees its own block and BASDOS.COM's, and claims the memory one paragraph after the drivers (room for the 8086 driver's MCB) for BASDOS.COM.  Then it pushes sysinit's inputs (including BASDOS.COM's new address) and its new entry point, and jumps to CPU_MOVE, which moves BASDOS.COM (over DEVINIT) and "returns" to sysinit.
4. **sysinit** (with `move_init`, `dos_size`, and `init_free`, in drvinit.asm) allocates a block at the top of conventional memory for its initialization code, CONFIG.SYS data, and a 512-byte stack below them, moves them there with CPU_MOVE, and jumps to them through a data selector and code alias for the block (CPU_MAP and CPU_ALIAS).  It grows the kernel's block as much as it can (CPU_REALLOC returns the longest a block could be), builds its tables after the kernel, and shrinks the block to fit.  Before loading the SHELLs, it gives back the part of its block below `sysinit_tail` (by freeing the block and claiming the rest again), and when they're loaded, it frees the rest.

With the 8086 CPU$, the kernel's MCB chain (`mcb_head`) starts at the free block after its tables, which is part of CPU$'s own chain, so the kernel's memory functions still work, on the same MCBs.  The next step is for them to call CPU$ instead (DOS_MEM_ALLOC and friends, freeing a program's blocks when it ends, MEM, and DEBUG's /DM), which is what the PMB's type and name are for.

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
- **INT 13h**: the BIOS turns ES:BX into a DMA address (ES * 16 + BX), so for functions 02h-05h, `sw_int` replaces ES:BX with SEL_BIOS and the buffer's offset from 400h (the buffer must be within 64K of 400h, for now), and `si_ret` restores them.
- **Vectors 08h-0Fh** are also software interrupts sometimes (eg, the AT BIOS's IRQ 9 handler does `INT 0Ah`), so if an exception's frame (taken as having no error code) returns just past an `INT` for its vector, `exc_common` treats it as one.
- **Null selectors in the ROM**: the BIOS loads DS with 0 to address the vectors, so a general protection fault with a zero error code, in the ROM, while DS or ES holds a null selector, is retried with SEL_LOW (base 0).  BASIC-DOS's own code gets no such fix.
- **Anything else** (any other exception, an INT 3, such as a failed DEBUG assertion, or a software interrupt with no handler we can call) is fatal: `cpu_fatal` prints, with the BIOS, `CPU$ fault vv, error eeee at cccc:iiii, ds dddd, es eeee` (for a software interrupt, the "error" is the caller's AX), and stops the machine for a debugger.

This is what the [probe](#probe) showed works for the ROM BIOS, with two differences: the GDT has identity selectors only where the BIOS needs them (and CPU$ allocates everything else), and drivers' handlers run in protected mode instead of being dropped.

### Protected-Mode Boot {#pmboot}

On an 80286 or later, when CPU$ stays loaded, BASIC-DOS switches to protected mode during DEVINIT, right after CPU$ initializes, and never switches back; everywhere else (an 8088, or `CPU=8088`), nothing changes, and the same code runs in real mode:

1. **CPU$ initializes in real mode**, as the first driver.
2. **DEVINIT claims its memory and loads BASDOS.COM** (`chk_cpu`), as it does in real mode (see [Claiming Memory at Boot](#claiming)).
3. **DEVINIT calls CPU_PMODE**, which turns its CS into a code selector, DS, ES, and SS (all 0) into SEL_LOW, the view of the first 64K that DEVINIT uses to reach the drivers, points DDINT_CPU, DDINT_GETVEC, and DDINT_SETVEC at CPU$'s protected-mode code, moves the master PIC, and loads the protected-mode IDT.  DEVINIT then gives the drivers already in the chain (ie, CPU$) selectors, too.
4. **Each driver gets a code selector and a data selector** before its initialization (`get_sels`, which calls CPU_MAP for a 64K data selector and CPU_ALIAS for its code alias; in real mode, both are the driver's segment): DEVINIT stores the data selector in DDH_DATA and DDPI_END, calls the driver through its code selector, and links it into the chain (DDH_NEXT_SEG, FDC_DEVICE, HDC_SEG, and CLOCK_DEVICE) with its code selector.  DEVINIT also passes its own data selector in DDP_PTR and DDPI_BUFPTR.
5. **DEVINIT moves BASDOS.COM after the drivers and jumps to sysinit** (`i9`), as it does in real mode: it gets a code selector and a data selector for BASDOS.COM's new home, pushes the offset of the BPB (in the first 64K), the size of the CONFIG.SYS data, the data selector, and the CONFIG.SYS data's offset, which sysinit pops, and then CPU_MOVE "returns" to its entry point (CS:0002h).

`tools/tests/pmboot.sh` boots this way on the baseline 2Mb PC AT (with the console on COM1), and lists breakpoint addresses for the PCjs Debugger: `dv_init` precedes each driver's initialization, and `dv_jump` precedes sysinit.

**Where it stands**: stepping through the boot in the PCjs Debugger, every driver initializes in protected mode: NUL, VKD$, COM1-COM4, LPT1-LPT3, CLOCK$, FDC$, HDC$, PIPE$, FPU$, and MOUSE$.  Along the way, VKD$, COM, and CLOCK$ install their handlers with DDINT_SETVEC (into the IDT), CLOCK$'s timer handler runs in protected mode (and chains to the BIOS's), and BIOS calls (eg, INT 1Ah and INT 13h function 08h) are reflected.  Two things needed fixing:

- **CPU_PMODE** read the new selectors from the stack (through SS) after setting PE, but SS still held 0, which PCjs treats as a null selector in protected mode; it now loads them into registers first.
- **Empty chains** (CLOCK$'s timer list and the drivers' lists of waiting packets) ended with a far pointer of -1:-1, and the code loads the whole pointer before checking the offset, which loads FFFFh into a segment register; they now end with FFFFh:0000h, and loading 0 is fine in either mode.

sysinit then runs in protected mode, moves its initialization code to the top of conventional memory through CPU$ (see [Claiming Memory at Boot](#claiming)), and continues there with selectors for the new copy, until it revectors DDINT_SETVEC to the kernel (`sto_jmpf` stores the kernel's data selector as the jump's segment), where the next driver call stops (`CPU$ fault 000D, error 0178 at 0050:0049`).  So the `pm` test configuration (and the Protected Mode demo) currently stop there.

#### What sysinit Needs {#sysinit}

sysinit was written for real mode, and most of what it does computes segments from paragraphs:

1. **Moving itself to the top of memory** (*done*): it allocates the block from CPU$, moves itself with CPU_MOVE, and jumps there through a data selector and code alias for the block (CPU_MAP and CPU_ALIAS), and uses the data selector as SS; it still saves CS as `dos_seg`, which it later uses as a data segment.
2. **Revectoring DDINT_GETVEC, DDINT_SETVEC, DDINT_UTIL, DDINT_ENTER, and DDINT_LEAVE** to the kernel (`sto_jmpf`, which stores DS as the jump target's segment, where it needs a code selector); in protected mode, CPU$ must keep DDINT_GETVEC and DDINT_SETVEC.
3. **Building the tables** (SCBs, BPBs, the buffer chain, SFBs) at paragraphs after the kernel, and storing those paragraphs (eg, the buffer chain's links are paragraphs).
4. **Building the MCB chain**: MCBs are paragraph-based by design (each block's segment is its MCB's plus 1), so in protected mode, the kernel's memory functions (DOS_MEM_ALLOC and friends) need selectors for blocks, eg, from CPU_MAP, while the MCBs themselves stay where they are.
5. **Loading the SHELLs** with DOSUTIL LOAD, which builds PSPs and loads programs, and starting the sessions; COMMAND.COM would need the [code aliases](#aliases) described below.

So the next decisions are about the kernel's memory model in protected mode (eg, what DOS_MEM_ALLOC returns), after which sysinit's operations can be converted one at a time, in the same mode-independent way as the drivers (eg, the kernel's device search also loads each link's segment before checking for the end of the chain, and the last driver's link holds a paragraph).

### Background: the Probe {#probe}

Before BASIC-DOS ran in protected mode, a build-time experiment (PROBE builds of CPU$, since removed) answered the question of whether the ROM BIOS could run in protected mode at all: after its self-test, CPU$ switched to protected mode with an "identity" GDT (8192 descriptors, each with a base of its selector times 16), ran a short routine at ring 3 that called INT 10h, 11h, 12h, 13h (including a diskette read by DMA), 15h, 16h, and 1Ah, and reflected each call to the BIOS at ring 0.  Both the PC AT and the DeskPro 386 BIOSes handled every call, with the null selector fix (the AT BIOS's GET_PARM does `LDS SI,[78h]` with DS = 0, and the VGA BIOS loads DS with 0 for every character) and, for INT 13h, an identity selector for the DMA buffer.  The DeskPro 386's IRQ 9 handler issues `INT 0Ah`, which lands on the invalid-TSS exception's gate, hence `exc_common`'s check for an INT.  A later version tried each driver's initialization in protected mode, which led to the DDINT segment at 50h and DDH_DATA (see [Mode-Independent Code](#modeless)).

### Running BASIC-DOS in Protected Mode {#plan}

Staying in protected mode after CPU$ initializes is the goal, but the rest of BASIC-DOS assumes real mode in several ways, and each needs its own solution.  This design targets the PC AT (an 80286, with IBM's BIOS); the 80386 (eg, virtual-8086 mode for DOS programs) and other BIOSes, such as the DeskPro 386's, are for later.

1. **BIOS calls** (*done*, for what the drivers' initializations use).  The ROM BIOS runs at ring 0 in protected mode, with identity selectors, a fix for null selectors, and reflection through the real-mode vector table (see [Protected-Mode Interrupts](#interrupts)), so a BIOS call needn't cost a mode switch, which on an 80286 means a processor reset (as in OS/2 1.x's real-mode session).  The rest of the BIOS functions the drivers use still need trying, INT 13h buffers more than 64K above 400h need another way to get an identity selector, and a few functions (eg, INT 15h functions 87h and 89h) will need CPU$ replacements.
2. **Hardware interrupts**.  The master PIC's IRQs 0-7 use vectors 08h-0Fh, which are also processor exceptions (eg, 0Dh is a general protection fault).  CPU$ moves the master PIC to 78h-7Fh, next to the slave PIC (70h-77h), and reflects each IRQ to the BIOS's handler, unless a driver has installed its own handler (eg, CLOCK$'s timer handler), which is called directly (*done*; see [Protected-Mode Interrupts](#interrupts)).  Vectors 08h-0Fh can still be software interrupts (eg, INT 0Ah from a BIOS's IRQ 9 handler), so their gates tell the two apart.
3. **Segment arithmetic**.  The kernel and COMMAND.COM compute segments from paragraphs (eg, walking the MCB chain, `mov ax,es` + `inc ax` to get from an MCB to its block, PSP and environment segments, and paragraph rounding), use fixed segments (0 for low memory, 40h, B000h and B800h for video, and F000h for the ROM), and use `push cs` + `pop ds` and then write data (a code segment can't be written in protected mode).  Each case needs a selector: for example, DOS_MEM_ALLOC could return a selector from CPU_MAP for the new block (keeping the MCB in the arena below 640K), the fixed segments would become fixed selectors (SEL_LOW, plus SEL_VIDEO and SEL_ROM), and each module with a code segment would also get a data alias (eg, the next selector).  The first step is an inventory of every such case.
4. **DOS programs**.  COM and EXE programs are real-mode programs.  On an 80386 they can run in virtual-8086 mode; on an 80286, only in real mode, so a session running a DOS program would switch the processor back to real mode while it runs (much like OS/2's DOS session), and other sessions would wait.
5. **COMMAND.COM**.  The biggest payoff: BASIC programs, variables, strings, and arrays limited only by memory, with each block in extended memory and addressed by a selector.

#### Mode-Independent Code {#modeless}

The first step toward staying in protected mode is to change the drivers and the kernel (everything that will run at ring 0) so that the same code runs in either mode, by using only segment values that are also valid selectors, and by never writing to a code segment.  The rules, *in progress*:

1. **Low memory through segment 40h** (*done*): bios.inc's BIOS segment is now `at 40h`, as the ROM BIOS itself addresses its data, instead of 0, and it covers both the ROM BIOS data area (offsets 00h-FFh) and BASIC-DOS's low memory (500h-96Fh, at offsets 100h-56Fh): CPU_TYPE, the DDINT entry points, the DPT, and the two disk buffers.  In protected mode, 40h is an identity selector.  BIOS_DATA (400h) is the segment's linear address, for the few places that need a linear address or paragraph (eg, the disk buffer chain's paragraphs, and DEVINIT, which addresses the drivers it relocates through segment 0).
2. **Interrupt vectors through DDINT entry points** (*done*): segment 0 is the null selector, and the general protection fault fix for it should only ever be needed by the ROM BIOS, so drivers and the kernel read and write vectors with far calls to DDINT_GETVEC and DDINT_SETVEC (after DDINT_CPU), which pass vectors in DX:CX rather than in segment registers (see [Device Drivers](../dev/)).  The kernel provides them (int_getvec and int_setvec), since they're needed on every processor, whether or not CPU$ is loaded; but drivers hook their vectors in INIT, before the kernel is loaded, so DEVINIT provides them until sysinit points them at the kernel, as sysinit does for DDINT_ENTER, DDINT_LEAVE, and DDINT_UTIL.  In protected mode, their implementations could also maintain the IDT.  Only the boot code and DEVINIT, which run first, and sysinit's CALL 5 jump at 0:00C0h (code, not a vector) still use segment 0, along with HDC$'s MBR code (which runs at boot) and CPU$'s A20 test.  COMMAND.COM no longer reads the INT 33h vector to find a mouse driver (see [COMMAND.COM](#command)).
3. **DDINT entry points through segment 50h** (*done*): drivers and the kernel call the DDINT entry points through segment 50h (eg, `call far ptr DDINT_SETVEC` is CALL 0050:0049h), which in protected mode is SEL_DDINT, a code selector with the same base (500h), so the addresses are the same in either mode; 40h stays a data selector.  The slots are still written through segment 40h (bios.inc's DDINT segment is at 50h, and an operand like `ds:[DDINT_CPU]`, with DS assumed to be BIOS, gets the BIOS offset from LINK, while an immediate offset needs DDINT_BIAS added).  In protected mode, CPU$ points DDINT_CPU, DDINT_GETVEC, and DDINT_SETVEC at its own protected-mode code (see [Protected-Mode Boot](#pmboot)).
4. **No writes through CS** (*done*): a protected-mode code segment can't be written, so each write with a CS override became a write through DS, ES, or SS holding the module's own segment (eg, after `push cs` and `pop ds`), in the drivers, the kernel, COMMAND.COM, DEBUG.COM, and the HARDERR and IOERR tests, which a scan of the MASM listings confirms.  In protected mode, those loads of CS will become loads of a data alias of the code segment (eg, if modules are loaded at 128-byte boundaries, the LDT could hold an execute/read descriptor for each identity data selector in the GDT, so that `CS AND 0FFF8h` would be the data alias in either mode), and a write through SS needs no change at all.  Writes to a driver's own memory now go through its data selector (see the next item).
5. **No unnecessary null selectors**: segment registers are never loaded with 0 just to have a value (three places in the kernel did, before read_buffer replaced it anyway), since only the ROM BIOS should ever need the null-selector fixup.
6. **A data selector for every driver** (*done*): DDH_INTERRUPT (unused, except by COM, which now keeps its interrupt entry with its other per-port variables) is now DDH_DATA, the driver's data segment or selector, which DEVINIT (or the kernel, for DEVICE= drivers) stores in the header before calling the driver's initialization, so every entry point (requests, interrupt handlers, and the far entry points that FDC$ provides HDC$) can load it with `mov ds,cs:[0].DDH_DATA` (instead of `push cs` and `pop ds`) whenever it writes its own memory.  In real mode, it's the driver's segment, so nothing changes; in protected mode, the driver's code selector (CS) and data selector are separate selectors for the same memory, from CPU$.  Far pointers to a driver's code (eg, vectors, DDH_NEXT_SEG, FDC_DEVICE, and BPB_DEVICE) use its code selector, and pointers to its data (eg, FDC$'s ddbuf_ptr) use its data selector.

The boot sector, which runs at 0:7C00h and then 0:0560h before anything else, keeps using segment 0 (adding BIOS_DATA to every BIOS offset), as does DEVINIT where it relocates the drivers, since both run only in real mode, at boot.

DEBUG builds also report (and halt on) the first failed assertion, even before any console handle exists: the kernel installs a default INT 29h handler (BIOS output) whenever no driver has (eg, VKD$ isn't loaded), so the fallback in write_handle never calls a null vector.

#### COMMAND.COM {#command}

COMMAND.COM will run at ring 3, so beyond the rules above, it should use only selectors that the kernel gives it.  *Done*:

- **Which copy owns the shared code**: it used to compare CS with DS (or SS), which are different selectors in protected mode even for the owner; now it checks PSP_HEAP, since only another copy's heap starts right after its PSP (see load_program).
- **The environment**: it used to be a paragraph-aligned buffer in the heap, whose segment was DS plus a paragraph offset; now it's a block of its own, allocated from the top of memory, so that it never sits after COMMAND's block (where it would keep the transient portion's memory from being reused).
- **The transient portion's copy**: it used to be placed at the top of the highest free block, computed from that block's segment and size; now COMMAND allocates a block there, copies the transient portion into it, and frees it again (it's still checksummed before it's reused).
- **Graphics memory**: the graphics statements used B800h; now they ask VKD$ (IOCTL_GETMODE with CL = 1 returns the context's video memory in DX, which in protected mode will be a selector) and cache it with the mode.
- **Fixed segments and vectors**: the tick count for RANDOMIZE uses segment 40h, and MOUSE no longer reads the INT 33h vector (it checks whether MOUSE ON found a mouse, and MOUSE ON resets the mouse with INT 33h, which is always valid, since sysinit points it at an IRET when there's no mouse driver).

*Remaining*:

- **Generated code** (see [Code Aliases](#aliases)): COMMAND compiles BASIC into code blocks (CBLKs) that it allocates as data, runs them with CS set to the block, and patches them while they run (genMore replaces each placeholder, which it finds from its return address).  In protected mode, each code block needs a code alias, which every far jump between blocks, every return address, every GOSUB frame, and ON ERROR's ERR_ADDR must use, while every write (code generation, patching, and keepCode) must use the block's data selector.
- **The shared code's variables**: CMD_REFS, TRANS_SUM, TRANS_HI, CMD_PATH (and MSG_DRIVE), and FPU_TABLE are written in COMMAND's code segment; copies that don't own the code write them after `push cs` and `pop ds`, which will need a data alias.  Better still, those variables could move out of the code segment (eg, the share count into the kernel, which already finds the matching copy, and the rest into each copy's heap), so that the code segment would be read-only: one execute/read selector that every copy shares, with no checksums (nothing could modify it) and, with extended memory, perhaps no transient portion at all.  The hard part is establishing that separation, since today the shared code is simply the first part of the owner's COM image.
- **The transient portion in protected mode**: a freed block's selector is invalid, so the copy would have to stay allocated (or simply be reloaded), unless the code is read-only and shared as described above.
- **DEF SEG, PEEK, and POKE** (see [DEF SEG](#defseg)).

#### Code Aliases {#aliases}

A protected-mode segment is either code (executable, and at most readable) or data (readable, and perhaps writable), so memory that's both written and executed needs two selectors.  CPU_ALIAS (prototyped and tested by CPUTEST) creates the second one: given a selector from CPU_ALLOC, CPU_MAP, or CPU_ALIAS, it returns a new selector for the same base and limit, with the access rights selected by SELF_CODE, SELF_RDONLY, and SELF_USER; CPU_UNMAP frees it.

- **COMMAND.COM's code blocks**: when COMMAND allocates a CBLK, the kernel (eg, a DOSUTIL function, since ring 3 code can't call DDINT_CPU) would return a code alias (SELF_CODE + SELF_USER) along with the block's data selector, and free it with the block.  COMMAND must keep both, which is easiest if the alias is always the data selector plus a fixed amount (eg, CPU_ALIAS could allocate the alias in the next LDT entry, so that `data + 8` is the code alias and `code - 8` the data selector, and in real mode both are the same segment, with an increment of 0).
- **EXEC**: a COM program's code and data are in one block (its PSP block), so EXEC would give it DS, ES, and SS from the block's data selector and CS from a code alias of it, freeing the alias when the program ends.  An EXE file's relocations are paragraph arithmetic, so in protected mode they can only work if each 64K of the image has its own selector (as with CPU_MAP's consecutive selectors) and every relocated segment is a multiple of 64K from the start of the image, which isn't generally true; MZ EXE files would run only when the system is in real mode (or in virtual-8086 mode on an 80386).

#### DEF SEG, PEEK, and POKE {#defseg}

DEF SEG accepts any segment, which in protected mode is an arbitrary selector, so it must be restricted.  The plan:

- **DEF SEG with no segment** (BASIC's own data, ie, the heap) stays as it is, readable and writable.
- **Common real-mode segments**, such as 0 and 40h (and perhaps the video and ROM segments), would get read-only selectors (eg, CPU_MAP of that 64K with SELF_RDONLY + SELF_USER), so that PEEK works but POKE fails with "Illegal function call" (checked by POKE, rather than relying on a general protection fault).
- **Other segments** would be allowed only if they belong to the session (eg, blocks that its programs allocated, checked against the MCB owner by the kernel), as writable data selectors; anything else fails.  Today, the only segment that a BASIC program can get from BASIC-DOS is DEF SEG's default, so this matters only once functions like VARSEG exist.
- In real mode, none of these restrictions apply, so programs that PEEK and POKE BIOS data or video memory keep working there.

#### Phases {#phases}

1. **Done**: CPU$ (processor detection, A20, the arena, GDT, IDT, and LDT, a self-tested switch to protected mode and back, and the CPU_* functions, all called in real mode), CPU_TYPE and DDINT_CPU in low memory, `--ram=2M` in pc.js, and CPUTEST.COM (in TESTS\MISC on test disks), which prints the arena and checks every function.
2. **Kernel interfaces**: CPU$ managing all memory in either mode, with CPU_REALLOC and CPU_MOVE (*done*), and DEVINIT claiming and moving its memory with them (*done*; see [Claiming Memory at Boot](#claiming)); next, sysinit and the kernel's memory functions (DOS_MEM_ALLOC and friends) using CPU$, DOS functions for extended memory that record the owner (the PSP), so that a program's blocks are freed when it ends, and MEM showing the arena.
3. **COMMAND.COM in extended memory, from real mode**: eg, keeping the copy of the transient part, or large arrays, in extended memory with CPU_MOVE.
4. **Interrupts in protected mode** (*done*, so far): CPU$ moves the master PIC, reflects software and hardware interrupts to the ROM BIOS at ring 0, and keeps the drivers' handlers in the IDT (see [Protected-Mode Interrupts](#interrupts)).  Next: trying the rest of the BIOS functions that the drivers use (eg, with a hard disk), and INT 13h buffers anywhere in memory.
5. **A protected-mode kernel**: the segment-arithmetic inventory and fixes (*in progress*; see [Mode-Independent Code](#modeless) and [COMMAND.COM](#command)), staying in protected mode after CPU$ initializes (*started*: the drivers initialize in protected mode, and sysinit starts there; see [Protected-Mode Boot](#pmboot) and [What sysinit Needs](#sysinit)), code aliases for COMMAND's generated code and for EXEC (CPU_ALIAS is *done*), and running DOS programs in real mode (80286) or virtual-8086 mode (80386).

### Open Questions

- **The HMA**: putting the system area in the HMA costs no conventional memory and is reachable in both modes, but A20 stays enabled, so besides the CALL 5 trampoline, programs that depend on wrapping at 1Mb could break (eg, EXEPACK-compressed programs loaded in the first 64K report "Packed file is corrupt").
- **Owners**: should PMB owners be PSPs (freed when a program ends) or sessions?
- **Privilege levels**: everything is DPL 0 for now (except selectors created with SELF_USER); DOS programs and BASIC code could run at ring 3 later, which would need a TSS and DPL 3 selectors.
- **Table sizes**: 128 PMBs, 256 GDT entries, and 1024 LDT entries are guesses; one LDT per session (or per program) may make more sense than a single LDT.
- **Identity selectors**: the GDT has them only for video memory and the ROMs (A000h-F800h, every 800h), so a ROM segment that isn't a multiple of 800h (eg, F600h, the PC's ROM BASIC) can't be reflected to, and DMA buffers more than 64K above 400h have none yet; a few more (or temporary ones) may be needed.

{% include footer.html prev="Data Structures:../data/" next="" %}
