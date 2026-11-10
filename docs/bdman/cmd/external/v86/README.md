---
layout: sheet
title: V86
permalink: /docs/bdman/cmd/external/v86/
---

{% include header.html %}

> V86 [*program* [*arguments*]]

Runs a real-mode *program* (a COM file, found in the current directory, with `.COM` added if *program* has no extension) in a V86 machine: 640K of memory that the program sees as an 8086 would, at addresses starting from 0, with the ROMs above it, while BASIC-DOS keeps running in protected mode.  Without a *program*, V86 runs COMMAND.COM.  Any switches after *program* are the program's own, but a switch before it is a `Syntax error`.

V86 machines need an 80386 (or later) running BASIC-DOS in protected mode with the 80386's features, which is what a `CPU=80386` line in CONFIG.SYS (see [CPU](../../../cfg/#cpu)) gives you; otherwise, V86 displays `V86 mode not available`.

The program can do anything an 8086 program can, except I/O, and its interrupts and exceptions go to its own vectors, which it can hook (eg, with DOS function 25h).  V86 does the DOS functions that involve the machine itself (its vectors, PSP, DTA, memory, and ending), and passes the rest on to BASIC-DOS, so the program's files, console, and devices are V86's.  So far:

- Only COM programs can run, and they can't run other programs (DOS function 4Bh) or allocate memory (48h), although they can shrink (or regrow) their own (4Ah).
- Only DOS functions (INT 20h and 21h) work; any other interrupt that the program doesn't handle itself (eg, a BIOS interrupt, or BASIC-DOS's own INT 2Bh) ends it, with a `CPU fault` message.  That's why COMMAND.COM can't run in a V86 machine yet.
- An instruction that real mode allows but a V86 machine doesn't (eg, I/O, or HLT) ends the program the same way.
- The program can't use video memory directly, and its BIOS data is a copy.

ERRORLEVEL is set to the program's exit code, or 1 if V86 couldn't run it.

Source: [v86.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/v86.asm)

{% include footer.html prev="UNIQ:../uniq/" next="VI:../vi/" %}
