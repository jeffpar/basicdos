---
layout: sheet
title: V86
permalink: /docs/bdman/cmd/external/v86/
---

{% include header.html %}

> V86 [/M:*size*] [*program* [*arguments*]]

Runs a real-mode *program* (a COM or EXE file, with `.COM` or `.EXE` added if *program* has no extension, found in the current directory, or if *program* has no drive or directory, in a directory of PATH$) in a V86 machine: memory that the program sees as an 8086 would, at addresses starting from 0, with the ROMs above it, while BASIC-DOS keeps running in protected mode.  Without a *program*, V86 runs COMMAND.COM, so `START V86` opens a real-mode command shell on a console of its own.  `/M:`*size* sets the machine's memory, in K, from 4 to 640 (eg, `START V86 /M:256` opens a shell in a 256K machine); without it, the machine has 640K.  The machine uses that much of the system's memory for as long as it runs, however little its programs use, so a smaller *size* leaves more for other sessions.  Any switches after *program* are the program's own, but any other switch before it (or a *size* out of range) is a `Syntax error`.  V86 gets PATH$ the way an external program does, from its environment, but since a session that START makes has none, START gives V86 the current PATH$ ahead of its *arguments*, as it does for COMMAND.COM (eg, `START V86 DEBUG` runs `V86 PATH$="C:\;C:\EXT":DEBUG`), and V86 passes that PATH$ on to its program's environment, as PATH.

V86 machines need an 80386 (or later) running BASIC-DOS in protected mode with the 80386's features, which is what a `CPU=80386` line in CONFIG.SYS (see [CPU](../../../cfg/#cpu)) gives you; otherwise, V86 displays `V86 mode not available`.

The program can do anything an 8086 program can, except I/O, and its interrupts and exceptions go to its own vectors, which it can hook (eg, with DOS function 25h).  V86 does the DOS functions that involve the machine itself (its vectors, memory blocks, PSPs, DTA, and running and ending programs, with their exit codes), and passes the rest of the DOS and BASIC-DOS functions on to BASIC-DOS, so the machine's files, consoles, and devices are V86's.  So COMMAND.COM runs in it as it does in real mode, along with the programs it runs (eg, BASIC-DOS's utilities, and tools like MASM and SYMDEB), with these differences:

- Floating-point works, through a copy of the FPU$ driver's functions in the machine's memory.
- The later programs of a pipeline (eg, MORE in `DIR | MORE`) run as ordinary BASIC-DOS programs, in sessions of their own, so a real-mode program can only be the first program of a pipeline.  START and KILL work as they do at any other prompt.
- MEM, FRE, and DOS function 52h report the machine's memory, and so does the memory size in its BIOS data.
- BIOS interrupts (eg, INT 10h and INT 16h) aren't available yet; an interrupt that the machine's programs don't handle themselves, other than DOS's and a few that only check whether something is installed (INT 28h, 2Ah, 2Fh, and 33h), ends the program with a `CPU fault` message, and so does an instruction that real mode allows but a V86 machine doesn't (eg, I/O, or HLT).
- The machine's programs can't use video memory directly, and their BIOS data is a copy.

ERRORLEVEL is set to the program's exit code, or 1 if V86 couldn't run it.  When V86 is the first program of its session (eg, `START V86`), its console closes when it ends, so if V86 or its program fails (a non-zero exit code), V86 first displays `Press any key` and waits for one, so that the messages can be read.

Source: [software/src/os/util/v86](https://github.com/jeffpar/basicdos/tree/main/software/src/os/util/v86)

{% include footer.html prev="UNIQ:../uniq/" next="VI:../vi/" %}
