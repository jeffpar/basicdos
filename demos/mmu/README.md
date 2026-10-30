---
layout: page
title: BASIC-DOS Protected Mode
permalink: /demos/mmu/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-2mb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS Protected Mode Demo"
      B: "BASIC-DOS Tests"
    commands: bw %976 'if cs==97;h;else'
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 2Mb of memory (640K of conventional memory and 1408K of extended memory), a Color Display, a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk.  It boots the BASIC-DOS Protected Mode Demo diskette, whose CONFIG.SYS (below) has no `CPU=8088` line, unlike the other PC AT and DeskPro 386 demos on this branch, so the CPU$ driver uses extended memory and protected mode.

The PCjs Debugger stops the machine as CPU$ starts to initialize, just after the boot sector's `Press a key to start...` prompt times out (pressing **Esc** at the prompt boots the hard disk instead, whose CONFIG.SYS has `CPU=8088`).  CPU$ is the first driver, at 0097:0000, and the page's breakpoint, `bw %976 'if cs==97;h;else'`, is a write breakpoint on CPU$'s DDH_REQUEST field, which halts only when CPU$ itself (CS = 0097h) writes it, as its first instruction does, so the breakpoint doesn't depend on how CPU$ is built.  Type `g` (or click **Run**) to continue.  The B: drive has the BASIC-DOS Tests diskette, so `B:\TESTS\MISC\CPUTEST` prints CPU$'s memory arena and tests its functions.

{% include machine.html id="ibm5170" %}

### Where Protected Mode Stands

This is the development page for BASIC-DOS's protected-mode work (the *mmu* branch).  The goal is for BASIC-DOS to run in protected mode on an 80286, with its drivers and kernel at ring 0, its sessions at ring 3, and extended memory for BASIC programs, while the same binaries still run in real mode on an 8088.  The PC AT is the only target for now.  See the [design](/docs/bdtech/mmu/) for details.

- **Done**: the CPU$ drivers, which manage all memory on every processor.  There are two, and only one stays: on an 80286 or later with extended memory, the first enables A20, keeps a table of physical memory blocks (PMBs) and the GDT, IDTs, and LDT in the first 64K of extended memory, and checks that it can switch to protected mode; on an 8088, or with `CPU=8088`, it records processor type 0 (in CPU_TYPE, at 0:512h) and unloads itself, and the second stays instead (about 1K), managing memory with a traditional MCB chain, and BASIC-DOS runs in real mode, as before.  Both provide the same functions (CPU_GETINFO, CPU_ALLOC, CPU_FREE, CPU_REALLOC, CPU_MOVE, CPU_MAP, CPU_UNMAP, CPU_ALIAS, CPU_QUERY, and with the first, CPU_PMODE) through DDINT_CPU, at 0050:003Fh, which work the same way in either mode (in real mode, a selector is a segment).
- **Done**: claiming memory at boot.  As soon as CPU$ initializes, DEVINIT claims the memory it's using (the drivers, and its own code and data) and loads the kernel (BASDOS.COM) into a block at the top of conventional memory; drivers that shrink are packed together with CPU_MOVE; and at the end, DEVINIT frees its blocks and has CPU$ move the kernel after the drivers and "return" to it, in either mode.  sysinit takes the memory for its tables and its initialization code from CPU$ too, and moves its code with CPU$.
- **Done**: the drivers run in either mode.  The DDINT entry points are called through segment 50h, which in protected mode is a code selector for the same memory; every driver gets a data segment (or selector) in its header (DDH_DATA), which it uses to write to itself, instead of CS; and CPU$ reflects interrupts to the ROM BIOS at ring 0 and keeps the drivers' interrupt handlers in its IDT.
- **In progress**: staying in protected mode.  On this machine, DEVINIT switches to protected mode (CPU_PMODE) right after CPU$ initializes, gives each driver a code and a data selector, initializes all of them in protected mode, and jumps to the kernel's initialization (sysinit) in protected mode, which moves its own code with CPU$ and stops when it revectors DDINT_SETVEC to the kernel, with `CPU$ fault 000D, error 0178 at 0050:0049` (see [Protected-Mode Boot](/docs/bdtech/mmu/#pmboot)).  This page's diskette is refreshed only by FINAL builds, so it may show an earlier stage.
- **Next**: the kernel's memory functions using CPU$ (eg, what DOS_MEM_ALLOC returns in protected mode); then sysinit's other operations, one at a time (see [What sysinit Needs](/docs/bdtech/mmu/#sysinit)); later, code aliases for COMMAND.COM's generated code and for EXEC, and restricting DEF SEG.

Every change is tested on three machines: an IBM PC XT (8088), a 2Mb PC AT with `CPU=8088` (real mode), and a 2Mb PC AT without it (this configuration, which stops in sysinit for now).

#### Physical Memory

| Address | Length | Contents |
|---------|--------|----------|
| 000000h | 1K | Real-mode interrupt vector table |
| 000400h | 256 | ROM BIOS data area (segment 40h) |
| 000500h | 1136 | BASIC-DOS low memory (also segment 40h, from offset 100h): CPU_TYPE (512h), the diskette parameter table (522h), the DDINT entry points (530h, called through segment 50h, including DDINT_CPU at 0050:003Fh and the vector functions), and two disk buffers |
| 000970h | | Drivers (CPU$ first), then BASDOS.COM, its tables, and the MCB chain |
| 0A0000h | 384K | Video memory, adapter ROMs, and the system ROM |
| 100000h | 64K | CPU$'s system area (the HMA, segment FFFFh in real mode) |
| 110000h | 1344K | Extended memory for CPU_ALLOC |

CPU$'s physical memory arena describes all of that as a table of Physical Memory Blocks (PMBs), in the system area, which also holds:

| Linear | Contents |
|--------|----------|
| 100010h | SYSVARS: CPU type and flags, the PMB table's location and size, saved real-mode registers, and the GDTR and IDTR values |
| 1000C0h | A far jump to 0:00C0h, for programs that use CALL 5 (with A20 enabled, it no longer wraps around to 0:00C0h) |
| 1000D0h | GDT (256 descriptors, and identity selectors from A000h to F800h, every 800h, at 10A0D0h-10F8D7h) |
| 1008D0h | PMB table (128 entries) |
| 1018D0h | IDT for the self-test (256 gates, which return to real mode) |
| 1020D0h | Protected-mode IDT (256 gates) |
| 1028D0h | LDT (1024 descriptors) |

#### Selectors

CPU$'s GDT starts with these fixed selectors:

| Selector | Name | Base | Use |
|----------|------|------|-----|
| 08h | SEL_SYS | 0FFFF0h | Data: the system area (so offsets match segment FFFFh) |
| 10h | SEL_LDTD | 1028D0h | The LDT |
| 18h | SEL_CPUCODE | 000970h | Code: CPU$ |
| 20h | SEL_LOW | 000000h | Data: the first 64K (DEVINIT's view of the drivers) |
| 28h | SEL_STACK | caller's SS | Data: the caller's stack (for the self-test) |
| 30h | SEL_TMP | 110000h | Data: scratch |
| 38h | SEL_CPU | | Call gate to CPU$'s functions |
| 40h | SEL_BIOS | 000400h | Data: segment 40h |
| 50h | SEL_DDINT | 000500h | Code: segment 50h (the DDINT entry points) |

CPU_ALLOC, CPU_MAP, and CPU_ALIAS allocate the rest of the GDT (58h-7F8h) and the LDT (04h-1FFCh).  In this configuration, DEVINIT's code selector is 58h, and each driver gets a data selector and a code selector after that (eg, 78h and 80h for NUL).

#### Debugging Tips

- `r` shows each segment register's selector with its base and limit in protected mode (eg, `CS=0018[000970,FFFF]` in CPU$), along with the GDTR, IDTR, LDTR, and TR.
- Linear breakpoints (eg, `bp %1295`) work in either mode.  An address in CPU$ is 970h plus its offset in CPUDEV.MAP (eg, `cpu_fatal`, which reports a fatal exception and stops the machine); on the mmu branch, tools/tests/pmboot.sh lists those, along with `dv_init` (in DEVINIT, just before each driver's initialization) and `dv_jump` (just before sysinit).
- Clear a breakpoint (`bc *`) before tracing (`t`) from it, or the trace stops there again.

### **CONFIG.SYS** from the BASIC-DOS Protected Mode Demo Diskette

```
{% include_relative CONFIG.SYS %}
```
