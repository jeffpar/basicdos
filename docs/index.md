---
layout: page
title: BASIC-DOS Documentation
permalink: /maplebar/docs/
machines:
  - id: ibm5150-0
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    sizeRAM: 128
    autoType: DATE\rTIME\rDIR\r
  - id: ibm5150-1
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    sizeRAM: 128
    autoType: TYPE BD1.BAT\r\rBD1\r
  - id: ibm5150-2
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    sizeRAM: 128
    autoMount:
      A: "BASIC-DOS2"
  - id: ibm5150-3
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    sizeRAM: 128
    autoMount:
      A: "BASIC-DOS3"
  - id: ibm5150-4
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-dual-256kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS4"
      B: "PC DOS 2.00 (Disk 2)"
---

### Quick Overview

The machine shown below is an IBM PC (Model 5150) with two floppy
disk drives and a Color Graphics Adapter (CGA) connected to a Color Monitor.
Also, the machine was originally configured with 64K of RAM, but it has been
upgraded to 128K for this overview.

A BASIC-DOS boot diskette (`BASIC-DOS1`) has been loaded into drive A:.  The
boot sector loads **IBMBIO.COM** into memory, which in turn loads **CONFIG.SYS**
and **IBMDOS.COM** into memory.  Like PC DOS, IBMBIO contains all the BASIC-DOS
device drivers and IBMDOS contains all the "Disk Operating System" services.
IBMDOS loads **COMMAND.COM** into memory, which provides the initial **A:**
command prompt.

{% include machine.html id="ibm5150-0" %}

All but the last two files are unique to BASIC-DOS.  **SYMDEB** is v4.00 of
Microsoft's Symbolic Debug Utility and **MSBASIC.EXE** was built from Microsoft's
[GW-BASIC](https://github.com/microsoft/GW-BASIC) open source files, with a
little help from [OS/2 Museum](http://www.os2museum.com/wp/well-hello/).

### PC DOS Compatibility

In some ways, BASIC-DOS is more primitive than PC DOS 1.00.  File system
functions are read-only (files cannot be created, written, renamed, or deleted),
although that will change in the coming months.

But in other ways, BASIC-DOS leap-frogs PC DOS 1.00, by adding
BPB support and the ability to read diskettes up to 360K, as well as
handle-based I/O functions, with pipe and redirection operations.

And, true to its name, BASIC-DOS has begun incorporating BASIC language
functionality into the command interpreter.  COMMAND.COM is on its way to
becoming a unified DOS *and* BASIC command interpreter.

### BASIC Operations

At the moment, the set of available BASIC commands is *very* basic: DEF, GOTO,
IF, LET, and PRINT.  But those are enough to write some simple programs.  Only
integer constants, variables, and operators are supported (no floating-point
yet).  String variables can be created, but there are no string operations yet
either.

**PRIMES.BAS** was the first BASIC program written to run in both BASIC-DOS and
**MSBASIC**.  Type `MSBASIC PRIMES` to run it with the Microsoft BASIC interpreter
first.  After it prints:

    TOTAL PRIMES < 1000:  168

type `SYSTEM` to return to the BASIC-DOS prompt.  Then type `PRIMES.BAS` to
load and run the same program directly within BASIC-DOS.

Notice how much *faster* BASIC-DOS execution is.  And BASIC-DOS performs
full 32-bit integer operations, while MSBASIC only does 16-bit operations.

### BASIC Files vs. Batch Files

There are three versions of the **PRIMES** program on the demo diskette: the
**BAS** file just discussed, a **BAT** version that is largely identical but
omits unnecessary line numbers, and an **EXE** version that was written in
assembly language.

When processing a filename, BASIC-DOS uses the same search order as PC DOS:
**.COM**, **.EXE**, and **.BAT**.  And if none of those are found, it also
searches for a **.BAS** file.  And unlike PC DOS, you can override the search
order with an *explicit* file extension.

Let's take a look at the **BD1.BAT** batch file in the machine below.

{% include machine.html id="ibm5150-1" %}

As in PC DOS 2.00, an **ECHO** command has been added to control the echoing
of lines in a batch file.  However, the only ECHO options are "ON" and "OFF",
because if you want to echo something else, well, that's what the PRINT command
is for.

Variables, including function definitions, remain in memory after a batch file
(or BASIC program) has been run.  So the ADD function defined by **BD1.BAT**
is still available, and can be used by any BASIC command or expression typed
directly at the command prompt.  For example:

    PRINT ADD(123456,654321)

will print `777777`.  All the standard BASIC numerical, logical, and relational
operators are available as well.

Notice that BASIC-DOS 1) doesn't require function names to begin with "FN",
2) it allows them to be defined at the command prompt (ie, what IBM PC BASIC
calls "Direct Mode", also known as "Immediate Mode"), and 3) it allows
multi-line function definitions, enabling the creation of more sophisticated
functions.

### Pipes and Redirection

In PC DOS, pipes require a writable disk with enough disk space to contain the
entire pipe output; in other words, pipe operations are really just "faked"
using temporary files.  So you might wonder how BASIC-DOS can support pipes if
it doesn't handle write operations (yet).

Well, it can, thanks to two features that PC DOS never included:

 1. A PIPE$ device driver
 2. Background session multitasking

For a command such as:

    TYPE PRIMES.BAS | CASE

the interpreter opens a PIPE$ handle to create a simple FIFO queue and passes
the handle as STDIN for a new background session running CASE.COM, a simple
BASIC-DOS I/O filter program that upper-cases letters.

### What's a Session?

BASIC-DOS supports a task unit known as a "session".  Sessions represent
separate execution environments.  Each session can run one or more programs,
each with their own assigned memory blocks, but they all share the same file
system, the same memory pool, etc.

Moreover, sessions can run entirely in the *background*, or they can be
assigned to specific regions of the screen.  The next two machines illustrate
how this works, using two side-by-side *foreground* sessions.

The CONFIG.SYS of the first machine has defined two 40-column foreground
sessions.  Use SHIFT-TAB to toggle keyboard focus between them.  Notice how
the border changes to indicate which session has focus.

{% include machine.html id="ibm5150-2" %}

And the CONFIG.SYS of this next machine has defined two 80-column foreground
sessions.

{% include machine.html id="ibm5150-3" %}

Foreground sessions are even more useful on dual-monitor systems, like the
system below, because each session has exclusive access to an entire screen.

{% include machine.html id="ibm5150-4" %}

It's important to note that BASIC-DOS is *not* attempting to create the
illusion of a "virtual machine" for each session.  That would require swapping
global memory (eg, ROM BIOS Data) on every context-switch, which would be
prohibitively expensive.  And it's completely unnecessary, as long as all
BASIC-DOS apps rely exclusively on BASIC-DOS APIs.  Most ROM BIOS APIs and
data should be reserved for exclusive use by BASIC-DOS itself.

Even though, in selected demos, I will sometimes run PC DOS applications like
**MSBASIC**, the fact that they work is a happy coincidence.  Most actually do
*not* work, often because they either 1) use DOS interfaces that I have not yet
implemented (and may *never* implement), 2) use BIOS interfaces that only
BASIC-DOS should be using, or 3) have a stack so small that crashing is
inevitable.

In fact, the "stack" issue is a major difference between BASIC-DOS and PC DOS:
BASIC-DOS *never* switches stacks within in a session.  The BASIC-DOS philosophy
is simple: apps should provide ample stack space, and all BASIC-DOS APIs should
be re-entrant.  PC DOS, by contrast, evolved complicated stack switching
procedures and rules that BASIC-DOS plans to avoid at all costs.
