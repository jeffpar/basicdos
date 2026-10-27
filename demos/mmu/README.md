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

- **Done**: the CPU$ driver.  On an 80286 or later with extended memory, it enables A20, builds a physical memory arena and the GDT, IDT, and LDT in the first 64K of extended memory, checks that it can switch to protected mode and back (returning to real mode, on an 80286, by resetting the processor with CMOS shutdown code 0Ah), and then provides its functions (CPU_ALLOC, CPU_FREE, CPU_MAP, CPU_UNMAP, CPU_QUERY, and CPU_GETINFO) through DDINT_CPU, a far jump at 53Fh.  BASIC-DOS itself still runs in real mode.  On an 8088, or with `CPU=8088`, CPU$ records processor type 0 (in CPU_TYPE, at 0:512h) and unloads itself.
- **In progress**: making the drivers and the kernel run unchanged in either mode.  The BIOS data and BASIC-DOS's low memory (at 500h) are now accessed through segment 40h, which is also a valid selector, instead of segment 0.  Next, interrupt vectors will be read and written through new DDINT entry points (since 0 isn't a valid selector), and writes through CS will become writes through DS or ES (a code segment can't be written in protected mode).  Every change is tested on three machines: an IBM PC XT (8088), a 2Mb PC AT with `CPU=8088` (real mode), and a 2Mb PC AT without it (this configuration).
- **Next**: loading modules at 128-byte boundaries (so that every segment is also a valid selector), the remaining segment arithmetic (eg, MCBs and PSPs), and then staying in protected mode after CPU$ initializes.

#### Physical Memory

| Address | Length | Contents |
|---------|--------|----------|
| 000000h | 1K | Real-mode interrupt vector table |
| 000400h | 256 | ROM BIOS data area (segment 40h) |
| 000500h | 1136 | BASIC-DOS low memory (also segment 40h, from offset 100h): CPU_TYPE (512h), the diskette parameter table (522h), the DDINT entry points (530h, including DDINT_CPU at 53Fh), and two disk buffers |
| 000970h | | Drivers (CPU$ first), then BASDOS.COM, its tables, and the MCB chain |
| 0A0000h | 384K | Video memory, adapter ROMs, and the system ROM |
| 100000h | 64K | CPU$'s system area (the HMA, segment FFFFh in real mode) |
| 110000h | 1344K | Extended memory for CPU_ALLOC |

CPU$'s physical memory arena describes all of that as a table of Physical Memory Blocks (PMBs), in the system area, which also holds:

| Linear | Contents |
|--------|----------|
| 1000C0h | A far jump to 0:00C0h, for programs that use CALL 5 (with A20 enabled, it no longer wraps around to 0:00C0h) |
| 1000F0h | SYSVARS: CPU type and flags, saved real-mode registers, and the GDTR and IDTR values |
| 1001F0h | PMB table (128 entries) |
| 1009F0h | IDT (256 gates, which return to real mode for now) |
| 1011F0h | GDT (256 descriptors) |
| 1019F0h | LDT (1024 descriptors) |

#### Selectors

CPU$'s GDT starts with these fixed selectors:

| Selector | Name | Base | Use |
|----------|------|------|-----|
| 08h | SEL_SYS | 0FFFF0h | Data: the system area (so offsets match segment FFFFh) |
| 10h | SEL_LDTD | 1019F0h | The LDT |
| 18h | SEL_CPUCODE | 000970h | Code: CPU$ |
| 20h | SEL_LOW | 000000h | Data: the first 64K |
| 28h | SEL_STACK | caller's SS | Data: the caller's stack |
| 30h | SEL_TMP | 110000h | Data: scratch |
| 38h | SEL_CPU | | Call gate to CPU$'s functions |

CPU_ALLOC and CPU_MAP allocate the rest of the GDT (40h-7F8h) and the LDT (04h-1FFCh).  All descriptors are DPL 0 for now.

#### Debugging Tips

- `r` shows each segment register's selector with its base and limit in protected mode (eg, `CS=0018[000970,FFFF]` in CPU$), along with the GDTR, IDTR, LDTR, and TR.
- Linear breakpoints (eg, `bp %1295`) work in either mode.  An address in CPU$ is 970h plus its offset in CPUDEV.MAP (eg, `pm_test`, which CPU$ runs in protected mode during its self-test).
- Clear a breakpoint (`bc *`) before tracing (`t`) from it, or the trace stops there again.

{% comment %}
The protected-mode probe is assembled only in builds of CPU$ with PROBE defined (eg, /DPROBE in AFLAGS in
software/src/os/dev/makefile), so it isn't on this diskette.  After its self-test, a PROBE build of CPU$ switches to
protected mode again and runs a short routine at ring 3 that calls the ROM BIOS (INT 10h, 11h, 12h, 13h, 15h, 16h, and
1Ah) through interrupt gates; each call is reflected to the BIOS, which runs at ring 0.  The PC AT BIOS handles all of
them, including a diskette read by DMA, with only one workaround: the BIOS often loads DS with 0, which is a null
selector in protected mode, so a general protection fault handler loads a selector whose base is 0 and retries the
instruction.  CPU$ then returns to real mode and prints a summary of the probe's results with the BIOS (which the
console driver clears a moment later).  The results stay in the system area at 1039F0h (PROBELOG and up to 120 events,
followed by the probe's TSS, IDT, and ring 0 stack): `db %1039F0 l400` dumps PROBELOG's status (2 if the probe
finished), its counts of interrupts, IRQs, and null selector fixes, and its events (8 bytes each, from 103A30h).

The probe uses its own GDT, an *identity* GDT of 8192 descriptors, in which each selector's base is the selector times
16 (eg, 0040h addresses the BIOS data, B800h the CGA's memory, and F000h the ROM), so a real-mode segment that's a
multiple of 8 works unchanged as a selector, and the BIOS's own segment arithmetic (including its DMA addresses) stays
correct.  Selectors below C000h are read/write data, and C000h and up are execute/read code (for adapter ROMs and the
system ROM).  Its ring 3 code uses LDT selectors 07h (code), 0Fh (data and stack), and 17h (a call gate back to ring
0), so `r` shows `CS=0007[000970,FFFF]` there.  Its IDT reflects software interrupts to the real-mode vector table,
takes hardware interrupts at 70h-7Fh (the master PIC moved from 08h to 78h, next to the slave PIC), and handles
exceptions 00h-0Fh.  On the mmu branch, tools/tests/pmprobe.sh boots a PROBE build and lists the probe's entry points
for breakpoints.
{% endcomment %}

### **CONFIG.SYS** from the BASIC-DOS Protected Mode Demo Diskette

```
{% include_relative CONFIG.SYS %}
```
