---
layout: page
title: BASIC-DOS Protected Mode
permalink: /demos/mmu/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com2
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-2mb.json
    debugger: true
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Protected Mode Demo"
      B: "BASIC-DOS Tests"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 2Mb of memory (640K of conventional memory and 1408K of extended memory), a Color Display, a 1.2Mb and a 1.44Mb diskette drive, a 10Mb hard disk, and a DEC VT100 on COM2 for BASIC-DOS's own debugger.  It boots the BASIC-DOS Protected Mode Demo diskette, whose CONFIG.SYS (below) has no `CPU=8088` line, unlike the other PC AT and DeskPro 386 demos on this branch, so the CPU$ driver uses extended memory and protected mode.

When the boot sector's `Press a key to start...` prompt times out (pressing **Esc** at the prompt boots the hard disk instead, whose CONFIG.SYS has `CPU=8088`), CPU$ initializes and switches to protected mode, and everything after that runs in protected mode: the rest of the drivers, the kernel's initialization (sysinit), the diskette's CONFIG.SYS driver, DEBUG.COM, on COM2 (which prints its banner on the VT100), and COMMAND.COM, whose prompt appears on the Color Display.  Commands and BASIC programs work (most of the regression tests pass in protected mode), but EXE files can't run in protected mode yet (see below).  CPU$ gives each fault to DEBUG.COM, and the VT100 shows `CPU$ fault 0D` with the error code, and the registers at the faulting instruction (with `#` before its address, since it's in protected mode, and the name of the memory it's in after it).  Adding /H to the DEBUG.COM line in CONFIG.SYS stops it as soon as it's loaded, so that you can set breakpoints before booting continues.  The B: drive has the BASIC-DOS Tests diskette, so `B:\TESTS\MISC\CPUTEST` prints CPU$'s memory arena and tests its functions.

{% include vt100-demo.html id="ibm5170" %}

### Where Protected Mode Stands

This is the development page for BASIC-DOS's protected-mode work (the *mmu* branch).  The goal is for BASIC-DOS to run in protected mode on an 80286, with its drivers and kernel at ring 0, its sessions at ring 3, and extended memory for BASIC programs, while the same binaries still run in real mode on an 8088.  The PC AT is the only target for now.  See the [design](/docs/bdtech/mmu/) for details.

- **Done**: the CPU$ drivers, which manage all memory on every processor.  There are two, and only one stays: on an 80286 or later with extended memory, the first enables A20, keeps a table of physical memory blocks (PMBs) and the GDT, IDTs, and LDT in the first 64K of extended memory, and checks that it can switch to protected mode; on an 8088, or with `CPU=8088`, it records processor type 0 (in CPU_TYPE, at 0:512h) and unloads itself, and the second stays instead (about 1K), managing memory with a traditional MCB chain, and BASIC-DOS runs in real mode, as before.  Both provide the same functions (CPU_GETINFO, CPU_ALLOC, CPU_FREE, CPU_REALLOC, CPU_MOVE, CPU_MAP, CPU_UNMAP, CPU_ALIAS, CPU_QUERY, CPU_SETBLK, CPU_FREEALL, CPU_SETLIM, and for debuggers, CPU_SEGINFO, CPU_RWMEM, CPU_SYSREGS, and CPU_SETFAULT, plus with the first, CPU_PMODE) through DDINT_CPU, at 0050:0030h, which work the same way in either mode (in real mode, a selector is a segment).
- **Done**: claiming memory at boot.  As soon as CPU$ initializes, devinit claims the memory it's using (the drivers, and its own code and data) and loads the kernel (BASDOS.COM) into a block at the top of conventional memory; drivers that shrink are packed together with CPU_MOVE; and at the end, devinit frees its blocks and has CPU$ move the kernel after the drivers and "return" to it, in either mode.  sysinit takes the memory for its tables and its initialization code from CPU$ too, moves its code with CPU$, and gets a segment (or selector) for each disk buffer from CPU_MAP, so neither computes segments from addresses.
- **Done**: DOS memory through CPU$.  DOS_MEM_ALLOC, DOS_MEM_FREE, and DOS_MEM_REALLOC call CPU$ with the block's segment (or selector), and a block can be anywhere in memory (on this machine, conventional or extended, so MEM reports all 2Mb), CPU$ keeps each block's owner, type, and name (CPU_SETBLK), a program's blocks are freed with CPU_FREEALL when it ends, and MEM and DEBUG's DM command (eg, `DEBUG /DM`, which lists the arena) use CPU_QUERY.
- **Done**: the drivers run in either mode.  The DDINT entry points are called through segment 50h, which in protected mode is a code selector for the same memory, and CPU$ provides DDINT_CPU, DDINT_GETVEC, and DDINT_SETVEC in either mode; every driver gets a data segment (or selector) in its header (DDH_DATA), which it uses to write to itself, instead of CS; FPU$ gets its function table's segment from CPU$; and CPU$ reflects interrupts to the ROM BIOS at ring 0, keeps the drivers' interrupt handlers in its IDT, and gives faults to DEBUG.COM (CPU_SETFAULT).
- **In progress**: staying in protected mode.  On this machine, devinit switches to protected mode (CPU_PMODE) right after CPU$ initializes, gives each driver a code and a data selector, and initializes all of them in protected mode; sysinit moves its own code with CPU$, loads DEBUG.COM (a DEVICE= driver) and COMMAND.COM, and starts COMMAND.COM with CS set to its block's code alias; COMMAND.COM runs its generated code (BASIC programs) through the code aliases of its code blocks, which the kernel returns with DOS_UTL_ALIAS; and a PSP's CALL 5 goes through a call gate (see [Protected-Mode Boot](/docs/bdtech/mmu/#pmboot) and [Code Aliases](/docs/bdtech/mmu/#aliases)).  This page's diskette is refreshed by DEBUG builds, so that it has the assertions.
- **Next**: what the protected-mode tests still don't pass: EXE files (whose relocations are paragraph arithmetic, so they need real mode, or virtual-8086 mode on an 80386) and HARDERR (an empty diskette drive reports "unknown media" instead of "not ready").  (DEF SEG now maps a segment to a selector that's read-only, except for video memory, so a BASIC program can PEEK low memory and the ROMs, but not POKE them.)

Every change is tested on three machines: an IBM PC XT (8088), a 2Mb PC AT with `CPU=8088` (real mode), and a 2Mb PC AT without it (this configuration, where most of the tests now pass, too).

#### Physical Memory

| Address | Length | Contents |
|---------|--------|----------|
| 000000h | 1K | Real-mode interrupt vector table |
| 000400h | 256 | ROM BIOS data area (segment 40h) |
| 000500h | 1136 | BASIC-DOS low memory (also segment 40h, from offset 100h): CPU_TYPE (512h), CPU_ARENA (514h, the address of CPU$'s arena, for debuggers), the diskette parameter table (522h), the DDINT entry points (530h, called through segment 50h, including DDINT_CPU at 0050:0030h and the vector functions), and two disk buffers |
| 000970h | | Drivers (CPU$ first), then BASDOS.COM and its tables, and free memory |
| 0A0000h | 384K | Video memory, adapter ROMs, and the system ROM |
| 100000h | 64K | CPU$'s system area (the HMA, segment FFFFh in real mode) |
| 110000h | 1344K | Extended memory, free for CPU_ALLOC (and DOS) |

CPU$'s physical memory arena describes all of that as a table of Physical Memory Blocks (PMBs), in the system area, which also holds:

| Linear | Contents |
|--------|----------|
| 100010h | SYSVARS: CPU type and flags, the PMB table's location and size, saved real-mode registers, and the GDTR and IDTR values |
| 1000C0h | A far jump to 0:00C0h, for programs that use CALL 5 in real mode (with A20 enabled, it no longer wraps around to 0:00C0h); in protected mode, a PSP's CALL 5 goes through the SEL_CALL5 call gate instead |
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
| 20h | SEL_LOW | 000000h | Data: the first 64K (devinit's view of the drivers) |
| 28h | SEL_STACK | caller's SS | Data: the caller's stack (for the self-test) |
| 30h | SEL_TMP | 110000h | Data: scratch |
| 38h | SEL_CPU | | Call gate to CPU$'s functions |
| 40h | SEL_BIOS | 000400h | Data: segment 40h |
| 48h | SEL_TMP2 | | Data: scratch |
| 50h | SEL_DDINT | 000500h | Code: segment 50h (the DDINT entry points) |
| 58h | SEL_C5CODE | 000000h | Code: just the CALL 5 jump at 0:00C0h |
| 60h | SEL_CALL5 | | Call gate to SEL_C5CODE:00C0h, for a PSP's CALL 5 (a far call through a gate ignores its offset, which CP/M programs read as their memory size) |

CPU_ALLOC, CPU_MAP, and CPU_ALIAS allocate the rest of the GDT (68h-7F8h) and the LDT (04h-1FFCh).  In this configuration, devinit's code selector is 68h, and each driver gets a data selector and a code selector after that (eg, 78h and 80h for CPU$, and 88h and 90h for NUL), which devinit fits to what the driver keeps (CPU_SETLIM), or frees if it keeps nothing.

#### Debugging Tips

- `r` shows each segment register's selector with its base and limit in protected mode (eg, `CS=0018[000970,FFFF]` in CPU$), along with the GDTR, IDTR, LDTR, and TR.
- Linear breakpoints (eg, `bp %1295`) work in either mode.  An address in CPU$ is 970h plus its offset in 286DEV.MAP (eg, `cpu_fatal`, which reports a fatal exception and stops the machine); on the mmu branch, tools/tests/pmboot.sh lists those, along with `dv_init` (in devinit, just before each driver's initialization) and `dv_jump` (just before sysinit).
- `d dos` lists CPU$'s memory arena the way DEBUG's DM command does, in either mode, once CPU$ has initialized: each block's address, length, owner, and name or type, with the system's blocks shown as the drivers in them (eg, CPU$ at 000970h).
- Clear a breakpoint (`bc *`) before tracing (`t`) from it, or the trace stops there again.
- To stop as CPU$ starts to initialize, halt the machine, set `bw %976 'if cs==97;h;else'`, and reset: it's a write breakpoint on CPU$'s DDH_REQUEST field (CPU$ is the first driver, at 0097:0000), which halts only when CPU$ itself writes it, as the start of its initialization does, so it doesn't depend on how CPU$ is built.
- To have the PCjs Debugger, rather than DEBUG.COM, stop at a DBGBRK (a lone INT 3) or an assertion failure, turn on its INT and HALT messages (`m int on` and `m halt on`) before booting (without the write breakpoint above, since with HALT messages on, it also stops the machine where it shouldn't).
- BASIC-DOS's own debugger, DEBUG.COM (on the VT100), works in either mode (as a driver or a program): an address can start with `&` (real mode) or `#` (protected mode), and otherwise has the processor's current mode, or with `%`, it's a physical address (eg, `%100000`), `DS selector` displays a selector's descriptor as the PCjs Debugger's DS command does (eg, `base=000970 limit=FFFF type=1B (code,readable,accessed) ext=0000 dpl=00`), `R` also shows the MSW, GDTR, and IDTR, and in protected mode, uses the PCjs Debugger's format (each segment register's base and limit, A20, the LDTR, GDTR, IDTR, TR, MSW, and the flags as 0 or 1), and `LN [address]` ("list near") shows an address (CS:IP by default), its linear address, and the name of the memory it's in (eg, `#0128:3754 0095E4 <DOS>`), as DM would show it.

### **CONFIG.SYS** from the BASIC-DOS Protected Mode Demo Diskette

```
{% include_relative CONFIG.SYS %}
```
