---
layout: page
title: Preview
permalink: /preview/
preview: /assets/images/maplebar.jpg
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    autoType: DATE\rTIME\rDIR\r
---

The machine below is an IBM PC (Model 5150) with two floppy disk drives, a Color Graphics Adapter (CGA) connected to a Color Monitor, and 128K of RAM.  It boots the BASIC-DOS diskette in drive A: (`BASICDOS-360K-S80`), and then runs the `DATE`, `TIME`, and `DIR` commands.

{% include machine.html id="ibm5150" %}

This is a preview of a perpetually unfinished product.

BASIC-DOS development started in 2020 with the goal of an initial roll-out by August 12, 2021, just in time for the 40th anniversary of the IBM PC.  And a "preview release" of BASIC-DOS was completed by then, so in terms of demonstrating the potential of BASIC-DOS, that goal was more or less achieved.  However, it also demonstrated the limits of what a single person, building a product from scratch one assembly-language instruction at a time, could realistically hope to accomplish.

Fast forward a few years, and the introduction of AI agents like Claude Code has dramatically changed what is possible.  The BASIC-DOS operating system architecture hasn't changed, but AI has made it possible to fill in lots of missing functionality, quickly resolve bugs, test compatibility and performance issues, improve documentation, and more.

Most of the limitations originally discussed in these preview pages have since been removed, so the pages now focus on what BASIC-DOS does that PC DOS and MS-DOS never did.  Some limitations remain, and there will always be more, because is any project ever truly finished?

### Contents

 1. [Introducing BASIC-DOS](#introducing-basic-dos-for-the-ibm-pc)
 2. [BASIC Operations](part2/)
 3. [BASIC Files vs. Batch Files](part3/)
 4. [Pipes and Sessions](part4/)
 5. [Were Dual Monitors Ever This Cool?](part5/)
 6. [Performance](part6/)

### Introducing BASIC-DOS for the IBM PC

This is a "sneak peek" at BASIC-DOS, the first version of DOS that *could* have been created for the IBM PC, with the benefit of more time and [incredible foresight](/blog/).

The boot sector of the BASIC-DOS diskette loads **BASDEV.COM** into memory, which in turn loads **CONFIG.SYS** and **BASDOS.COM**.  Like IBMBIO.COM and IBMDOS.COM in PC DOS, BASDEV contains all the BASIC-DOS device drivers and BASDOS contains all the Disk Operating System services.  Finally, BASDOS loads **COMMAND.COM** into memory, which provides the initial command prompt.

All files are original BASIC-DOS production and test files, with the exception of **SYMDEB** (Microsoft's Symbolic Debug Utility v4.00) and **MSBASIC.EXE**, which was built from Microsoft's [GW-BASIC](https://github.com/microsoft/GW-BASIC) open-source files, with a little help from [OS/2 Museum](http://www.os2museum.com/wp/well-hello/). These two files are used for testing and comparison only, so they live in the **TOOLS** directory of the `BASICDOS-360K-TESTS` diskette rather than the BASIC-DOS distribution.

NOTE: All preview binaries shown here are release (non-DEBUG) versions.  DEBUG versions, which enable all run-time assertions, are also available by building BASIC-DOS with "mkdos.sh debug"; their file sizes and memory usage are larger, and their overall performance is slightly lower.  Either way, BASIC-DOS outperforms PC DOS in several respects.  More on that later.

### PC DOS Compatibility

Like PC DOS, BASIC-DOS supports a FAT file system, **COM** and **EXE** executable formats, and many of the same PC DOS APIs, commands, and data structures, including Program Segment Prefixes (PSPs) and File Control Blocks (FCBs).

However, compatibility is *not* the primary goal of BASIC-DOS.  The true goal is to demonstrate what *could* have been achieved as the first IBM PC operating system, not to create a "clone" of PC DOS and endlessly chase compatibility problems.  To whatever extent BASIC-DOS is compatible with PC DOS, that compatibility is born purely out of convenience, relying on existing designs whenever it makes sense to do so -- just as PC DOS and its predecessors relied on CP/M designs, CP/M relied on DEC designs, and so on.

BASIC-DOS leap-frogs PC DOS 1.00 (and in several respects PC DOS 2.00) by supporting subdirectories, handle-based I/O, installable device drivers, hard disks, critical error handling, pipe and redirection operations, and last but not least, preemptive multitasking of multiple DOS applications across multiple screens or portions of a single screen.

And, true to its name, BASIC-DOS has incorporated the BASIC language into the command interpreter.  COMMAND.COM is a unified DOS *and* BASIC command interpreter: batch files are BASIC programs, BASIC programs are compiled into 8086 code before they run, and even system utilities like FORMAT and MODE are written in BASIC.

### Next: [Part 2: BASIC Operations](part2/)
