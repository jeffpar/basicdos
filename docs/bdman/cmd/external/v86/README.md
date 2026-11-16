---
layout: sheet
title: V86
permalink: /docs/bdman/cmd/external/v86/
---

{% include header.html %}

> V86 [/M:*size*] [*program* [*arguments*]]

Runs a real-mode *program* (a COM or EXE file, with `.COM` or `.EXE` added if *program* has no extension, found in the current directory, or if *program* has no drive or directory, in a directory of PATH$) in a V86 machine: memory that the program sees as an 8086 would, at addresses starting from 0, with the ROMs above it, while BASIC-DOS keeps running in protected mode.  Without a *program*, V86 runs COMMAND.COM, so `START V86` opens a real-mode command shell on a console of its own.  `/M:`*size* sets the machine's memory, in K, from 4 to 640 (eg, `START V86 /M:256` opens a shell in a 256K machine, and `START /B V86 /M:256 DEBUG` runs DEBUG in one without switching to its console); without it, the machine has 640K.  The machine uses that much of the system's memory for as long as it runs, however little its programs use, so a smaller *size* leaves more for other sessions.  Any switches after *program* are the program's own, but any other switch before it (or a *size* out of range) is a `Syntax error`.  V86 gets PATH$ the way an external program does, from its environment, but since a session that START makes has none, START gives V86 the current PATH$ ahead of its *arguments*, as it does for COMMAND.COM (eg, `START V86 DEBUG` runs `V86 PATH$="C:\;C:\EXT":DEBUG`), and V86 passes that PATH$ on to its program's environment, as PATH.

V86 machines need an 80386 (or later) running BASIC-DOS in protected mode with the 80386's features, which is what a `CPU=80386` line in CONFIG.SYS (see [CPU](../../../cfg/#cpu)) gives you; otherwise, V86 displays `V86 mode not available`.

The program can do anything an 8086 program can, except I/O (other than the few ports listed below), and its interrupts and exceptions go to its own vectors, which it can hook (eg, with DOS function 25h).  V86 does the DOS functions that involve the machine itself (its vectors, memory blocks, PSPs, DTA, and running and ending programs, with their exit codes), and passes the rest of the DOS and BASIC-DOS functions on to BASIC-DOS, so the machine's files, consoles, and devices are V86's.  So COMMAND.COM runs in it as it does in real mode, along with the programs it runs (eg, BASIC-DOS's utilities, and tools like MASM and SYMDEB), with these differences:

- Floating-point works, through a copy of the FPU$ driver's functions in the machine's memory.
- The later programs of a pipeline (eg, MORE in `DIR | MORE`) run as ordinary BASIC-DOS programs, in sessions of their own, so a real-mode program can only be the first program of a pipeline.  START and KILL work as they do at any other prompt.
- MEM, FRE, and DOS function 52h report the machine's memory, and so does the memory size in its BIOS data.
- [DEBUG](../debug/) works as it does in real mode, except that DM reports `?` (and LN finds no block), since the machine's memory blocks are V86's, not the CPU$ driver's.
- The common BIOS video (INT 10h), keyboard (INT 16h), and printer (INT 17h) functions work, but V86 does them with the console's own functions rather than the ROM's, so they work on any console (even a terminal, which can't read characters back from its screen, so programs that do, like MSBASIC, need a video console), and with its limits: a scrolled window is always as wide as the screen (though a character written at the end of the last row doesn't scroll it, as with the ROM), and a character that the console acts on (eg, RETURN) can't be drawn.  The functions are set mode, set cursor type and position, get cursor position, scroll up and down, read and write characters at the cursor, write teletype, and get mode; wait for a key and check for a key (and on a video console, the keyboard buffer and shift states in the machine's BIOS data stay current, for programs like MSBASIC that look there first); and print a character and get the printer's status.  Other BIOS functions do nothing.
- The machine gets timer ticks while its programs run: an INT 08h about 18 times a second (unless its interrupts are off, in which case that tick is lost), whose default handler issues an INT 1Ch, as the ROM's does, and the tick count in its BIOS data stays current.  There are no ticks while a program waits in a DOS or BIOS function (eg, for a key), and no other hardware interrupts.
- The only I/O port is the game port (201h), which reads as it does when there's no game adapter (programs like MSBASIC read it on every tick); an IN or OUT with any other port ends the program with a `CPU fault` message.
- Any other interrupt that the machine's programs don't handle themselves, other than DOS's, a breakpoint (INT 03h) or an INT 06h instruction (which do nothing without a debugger, as in real mode), and a few that only check whether something is installed (INT 28h, 2Ah, 2Fh, and 33h), ends the program with a `CPU fault` message, and so does an instruction that real mode allows but a V86 machine doesn't (eg, HLT).
- The machine's programs can't use video memory directly, and their BIOS data is a copy, in which only the keyboard data and the tick count are kept current.

ERRORLEVEL is set to the program's exit code, or 1 if V86 couldn't run it.  When V86 is the first program of its session (eg, `START V86`), its console closes when it ends, so if V86 or its program fails (a non-zero exit code), V86 first displays `Press any key` and waits for one, so that the messages can be read.

Source: [software/src/os/util/v86](https://github.com/jeffpar/basicdos/tree/main/software/src/os/util/v86)

{% include footer.html prev="UNIQ:../uniq/" next="VI:../vi/" %}
