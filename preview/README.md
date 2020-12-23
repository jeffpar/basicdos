---
layout: page
title: Preview
permalink: /preview/
preview: /assets/images/maplebar.jpg
machines:
  - id: ibm5150
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    sizeRAM: 128
    autoType: DATE\rTIME\rDIR\r
---

BASIC-DOS is still in development.  The target release date is August 12, 2021.

This is a preview of an unfinished product.

### Introducing BASIC-DOS for the IBM PC

This is a "sneak peek" at BASIC-DOS, the first version of DOS that *could*
have been created for the IBM PC, with the benefit of more time and
[incredible foresight](/blog/).

The machine shown below is an IBM PC (Model 5150) with two floppy
disk drives and a Color Graphics Adapter (CGA) connected to a Color Monitor.
The machine was originally configured with 64K of RAM, but it has been
upgraded to 128K for this preview.

A BASIC-DOS boot diskette (`BASIC-DOS1`) has been loaded into drive A:.  The
boot sector loads **IBMBIO.COM** into memory, which in turn loads **CONFIG.SYS**
and **IBMDOS.COM**.  Like PC DOS, IBMBIO contains all the BASIC-DOS
device drivers and IBMDOS contains all the Disk Operating System services.
Finally, IBMDOS loads **COMMAND.COM** into memory, which provides the initial
**A&gt;** command prompt.

{% include machine.html id="ibm5150" %}

All files are original BASIC-DOS production and test files, with the exception
of **SYMDEB** (Microsoft's Symbolic Debug Utility v4.00) and **MSBASIC.EXE**,
which was built from Microsoft's [GW-BASIC](https://github.com/microsoft/GW-BASIC)
open-source files, with a little help from [OS/2 Museum](http://www.os2museum.com/wp/well-hello/).
These two files are used for early testing and debugging only, and they
will not be distributed with the finished BASIC-DOS product.

NOTE: All preview binaries shown here are *DEBUG* versions, which means that
all run-time assertions are enabled, so file sizes and memory usage are larger
than normal, and overall performance is slightly lower.  Even so, BASIC-DOS
outperforms PC DOS in several respects.  More on that later.

### PC DOS Compatibility

Like PC DOS, BASIC-DOS supports a FAT file system, **COM** and **EXE**
executable formats, and many of the same PC DOS APIs, commands, and data
structures, including Program Segment Prefixes (PSPs) and
File Control Blocks (FCBs).

However, compatibility is *not* the primary goal of BASIC-DOS.  The true
goal is to demonstrate what *could* have been achieved as the first IBM PC
operating system, not to create a "clone" of PC DOS and endlessly chase
compatibility problems.  To whatever extent BASIC-DOS is compatible with
PC DOS, that compatibility is born purely out of convenience, relying on
existing designs whenever it makes sense to do so -- just as PC DOS and its
predecessors relied on CP/M designs, CP/M relied on DEC designs, and so on.

In some ways, BASIC-DOS is more primitive than PC DOS 1.00.  File system
functions are read-only (files cannot be created, written, renamed, or
deleted), and FCB functionality is limited.  However, those are temporary
limitations that will be addressed in the coming months.

In other ways, BASIC-DOS leap-frogs PC DOS 1.00, by adding the ability to
read PC DOS 2.00-formatted diskettes, load PC DOS 2.00-style device drivers,
perform handle-based I/O, support pipe and redirection operations, and more.

And, true to its name, BASIC-DOS has begun incorporating BASIC language
functionality into the command interpreter.  COMMAND.COM is on its way to
becoming a unified DOS *and* BASIC command interpreter.

### Next: [Part 2: BASIC Operations](part2/)
