---
layout: sheet
manual: BASIC-DOS Technical Reference
title: BASIC-DOS vs. DOS Extenders
permalink: /docs/bdtech/ext/
---

{% include header.html %}

A traditional DOS extender gives one program access to protected mode and extended memory, on top of a real-mode DOS that stays in charge of files and devices.  BASIC-DOS takes the opposite approach: when protected mode is requested (see [CPU](../../bdman/cfg/#cpu)), the operating system itself runs in protected mode, and programs run at ring 3 under it, using the same DOS functions they use in real mode.

This page describes what that gains and what it gives up.  The closest comparisons are 16-bit extenders (eg, Rational Systems' DOS/16M and Phar Lap's 286\|DOS-Extender), since BASIC-DOS has only 16-bit segments, whereas 32-bit extenders (eg, DOS/4G) offer something that it doesn't.

### Traditional DOS Extenders {#extenders}

An extender is usually bound into its program, as a real-mode stub or a companion file.  It starts in real mode, and it has to:

1. **Find out who owns the processor**, and enter protected mode in whatever way that owner allows:
	- on a plain DOS machine, directly, perhaps using XMS to allocate extended memory;
	- under a 386 memory manager that has put DOS in virtual-8086 mode, through VCPI (1989), whose clients run at ring 0; or
	- under a host such as Windows, through DPMI (1990), where the host keeps ring 0, and the client asks it for descriptors, memory, and interrupt handlers.
2. **Load the program**, since neither VCPI nor DPMI defines a program format.
3. **Translate DOS and BIOS calls**, which are serviced by real-mode code that can't address extended memory or use selectors: it copies data through a buffer in conventional memory, and switches modes for each call (or on an 80386, may return to virtual-8086 mode).

BASIC-DOS needs none of this.  It's the first thing loaded, so nothing else owns the processor; the kernel includes the loader; and its INT 21h is a protected-mode function, which takes selectors for memory anywhere.

### At a Glance {#glance}

| | BASIC-DOS | Traditional DOS extender |
|---|---|---|
| **Runs on** | Its own kernel and drivers | Any compatible DOS, which the user already has |
| **Protected mode applies to** | The whole system, chosen at boot | One program, chosen by that program |
| **Programs** | COM and restricted NE; MZ only in real mode | The extender's own format (eg, LE), built with its tools |
| **Privilege** | Ring 3, with IOPL 0 (unless `RING=0`) | Often ring 0 on plain DOS or VCPI; up to the host on DPMI |
| **DOS calls** | Native, with no mode switch or copying | Translated to real-mode DOS |
| **Hardware** | Only through drivers | Direct, or as the host allows |
| **Several programs at once** | Preemptive sessions, each with its own LDT | Only under a multitasking host |
| **Addressing** | 16-bit segments | 16-bit, or 32-bit flat with a 32-bit extender |

### COM Programs in Either Mode {#com}

Under DOS, a COM program runs in real mode unless it enters protected mode itself.  BASIC-DOS instead loads a COM program in protected mode at ring 3, with no changes and no special format: its code and data are still one block, with the PSP at offset 0, so all of its offsets stay the same, and only the values in its segment registers are different (see [Loading Programs](../mmu/#exec)).  If such a program calls DOS_MEM_ALLOC, it can be given memory above 1Mb, without knowing it.

This works for programs that treat segment values as opaque, and leave the hardware to DOS and its drivers.  In particular, a program that runs in either mode:

- **Does no segment arithmetic**, and computes no segments (eg, from the end of memory at PSP:0002h).  CS and DS are different selectors for the same memory, so it doesn't assume that they're equal, either.
- **Doesn't write through CS.**  It can read through CS, and for the few cases that need more (eg, a breakpoint), DOS_UTL_ALIAS with AL = 1 returns a writable selector for its code, which in real mode is the same segment.  A handler that can't rely on DS can write through SS instead (as VI's CTRL-C handler does), if the program hasn't moved its stack out of its block.
- **Uses DOS functions and drivers, rather than the BIOS, low memory, and ports**: it issues only DOS's interrupts, INT 33h (the mouse), and INT 60h-67h, gets the tick count from DOS_UTL_GETTIME and video memory from IOCTL_GETMODE, and if it must read low memory, gets a read-only selector from DOS_UTL_MAPSEG.  It doesn't use IN, OUT, CLI, or STI.
- **Allocates no more than 64K per block**, unless it can handle both cases: the next 64K of a larger block is 1000h paragraphs away in real mode, but the next selector (8 more) in protected mode.

The same functions work in either mode, so the program needs no mode test or second code path.  COMMAND.COM is the main example: one binary runs in real mode on a 64K 8088, and at ring 3 on a PC AT.  If a program breaks a rule in protected mode, it ends with a `CPU fault` message, and other sessions continue.

### Dual NE and MZ Programs {#dual}

An NE file gives protected mode what a COM file can't: a separate block for each segment, with a limit that fits it exactly, and relocations that refer to segments by number instead of by paragraph.  An NE file also starts with an MZ "stub" for DOS to run, and BASIC-DOS uses this to carry two complete programs in one file:

- **In protected mode**, the kernel loads the NE image, which must be marked PROTMODE, with FIXED segments, no imports, and only internal relocations.
- **In real mode**, on BASIC-DOS or any other DOS, the stub is an ordinary MZ program, not just a message saying that the program can't run.

The two images can come from the same object file, and both call the same DOS functions, so no compatibility layer is needed.  `TESTS\BIN\PRIMES.EXE` is built this way: LINK makes the MZ program from PRIMES.OBJ, and LINK4 makes the NE program from PRIMES.OBJ, with the MZ program named as the stub in `tests/primes/PRIMES.DEF`.

This differs from earlier uses of the stub.  A DOS extender's stub loads the extender, which then needs a processor it can use.  OS/2's BIND made one NE image run on DOS, too, but only by adding a stub with a library of OS/2 functions for DOS, and only for programs that restricted themselves to the Family API.  A BASIC-DOS stub can be a full real-mode program, which runs on an 8088.

The cost is that the file holds the program twice: converting MASM 4.00 this way (below) took it from 85,566 bytes to 173,048.

Existing MZ programs can be converted without their sources.  `tools/misc/mkne.js` makes dual versions of the MASM, MAKE, LINK, and other build tools by patching only the NE copy, so the MZ image remains byte-identical, and BASIC-DOS can build itself at ring 3, with the same binaries as a real-mode build.  Its comments list the problems to look for.  However, each conversion is specific to one binary, and takes some work; it isn't a general way to run MZ programs.

#### The NE Loader Stub {#stub}

A pure NE program doesn't have to carry a second copy of itself.  It should already be safe to run in real mode, since what protected mode forbids (eg, segment arithmetic, or writes through CS) still works when it isn't done, whereas an MZ program rarely runs in protected mode as it stands.  So BASIC-DOS's stub can be a small NE loader (`NESTUB.BIN`, 372 bytes), rather than a real-mode program: `node tools/misc/mkne.js --stub in.exe out.exe` replaces an NE file's stub with it, and the result runs in real mode on BASIC-DOS, and if the program uses only DOS functions, on PC DOS 2.00 and MS-DOS 3.20.

The stub needs no file I/O.  Its MZ header gives a header size of zero, and a load image that's the entire file, so DOS loads the stub and the NE image together, and the stub doesn't need the program's name.  It applies the NE program's relocations with paragraphs in place of selectors, moves any segments that need more room than they have in the file, zeroes what they don't initialize, and starts the program with the same registers that the kernel's NE loader gives it.  In protected mode, the kernel ignores the stub, as it does any other.

`TESTS\BIN\PRIMES.EXE`, a pure NE program, would go from 1,348 bytes to 772, and EXE2BIN in **TOOLS** already went from 5,536 bytes to 2,944.  There are limits:

- A program that may run on an 8088 can use only 8086 instructions, as any program that targets both processors must.
- Real mode uses the program's protected-mode layout, including any fixed 64K segment (eg, EXE2BIN's file buffer), rather than sizing itself to the memory available.
- After linking, the file needs the extra `mkne.js` step, since LINK4's `STUB` statement can't set the header that the stub needs.

### Advantages {#advantages}

- **A simple programming model.**  A program has no mode to enter, no environment to detect, and no extender to ship.  Beyond DOS's usual functions, it needs only DOS_UTL_ALIAS and DOS_UTL_MAPSEG for selectors, and usually neither.
- **DOS calls without mode switches or copying.**  Buffers can be anywhere in memory, which matters most on an 80286, where returning to real mode means resetting the processor.  (BASIC-DOS hasn't been measured against an extender.)
- **Protection by default.**  Programs always run at ring 3 (unless `RING=0`), so a bad pointer, stack, or return address ends the program, rather than corrupting the system, as it can with an extender that runs at ring 0.
- **Several large programs at once**, with preemptive sessions, on an 80286.  An extended DOS program on plain DOS runs alone, and has the machine to itself.
- **Automatic cleanup.**  The kernel frees a program's memory, and removes its handlers, when it ends.
- **Small programs and machines still work.**  One system runs on everything from a 64K 8088 up, and protected-mode support costs no memory in real mode.

### Disadvantages {#disadvantages}

- **No 32-bit programs.**  BASIC-DOS has no 32-bit segments, paging, or virtual-8086 mode, which is what made 32-bit extenders so effective for large programs.
- **You have to boot it.**  An extended program runs on the DOS a user already has, along with its TSRs and drivers.  BASIC-DOS is the operating system, and it can't run on top of another one, or under a host.
- **Protected mode is all or nothing.**  It's chosen at boot, for the whole system.  In protected mode, MZ programs are refused, and in real mode, no program can use extended memory.  An extended program and an ordinary MZ program can run on one DOS without rebooting; on BASIC-DOS, an MZ program needs real mode.
- **No existing programs to run.**  Programs written for an extender, VCPI, or DPMI can't run, since BASIC-DOS provides neither interface, and programs must be written or converted for it.
- **No real-mode code in protected mode.**  Real-mode TSRs and drivers can't be used, and there's no equivalent of DPMI's real-mode callbacks.
- **Little hardware control.**  A ring 3 program can't take an IRQ, issue a BIOS interrupt, use a port, or catch a general protection fault, so programs that need to (eg, many games) need a driver or `RING=0`.
- **Lower memory limits.**  DOS_MEM_ALLOC's 16-bit paragraph count limits a block to about 1Mb, and a session's 96 LDT descriptors (at one for every 64K) limit it to less than 6Mb, including its shell.  Blocks must also be physically contiguous, since there's no paging, so free memory can fragment, and there's no virtual memory to fall back on.
- **Protection isn't security.**  There's no privilege model for programs, so any program can do what COMMAND.COM can with DOS functions.  See [Limitations](../mmu/#limits), which also lists other fixed limits.

{% include footer.html prev="Protected Mode and Memory Management:../mmu/" next="" %}
