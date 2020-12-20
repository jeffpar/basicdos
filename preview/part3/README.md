---
layout: page
title: BASIC-DOS Preview
permalink: /preview/part3/
machines:
  - id: ibm5150
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    sizeRAM: 128
    autoType: TYPE BD1.BAT\r\rBD1\r
---

### BASIC Files vs. Batch Files

There are three versions of the **PRIMES** program on the `BASIC-DOS1` diskette:
the **BAS** file previously demonstrated, a **BAT** version that uses line numbers
only as needed (as labels), and an **EXE** version that was written in assembly
language.  The source code for the assembly language version can be found in both
the BASIC-DOS [Repository]({{ site.github.repository_url }}) and [Build Machine](/build/),
along with the rest of the BASIC-DOS source code.

When processing an external filename, BASIC-DOS searches for extensions in the
same order as PC DOS: **.COM**, **.EXE**, and **.BAT**.  And if none of those
are found, it also searches for a **.BAS** file.  And unlike PC DOS, you can
override the search order with an *explicit* file extension.

Let's take a look at the **BD1.BAT** batch file in the machine below.

{% include machine.html id="ibm5150" %}

As in PC DOS 2.00, an `ECHO` command has been added to control the echoing
of lines in a batch file.  However, the only `ECHO` options are *ON* and *OFF*,
because if you want to echo something else, well, BASIC already has a command
for that: `PRINT`.

Variables, including function definitions, remain in memory after a batch file
(or BASIC program) has been run.  So the ADD function defined by **BD1.BAT**
is still available, and can be used by any BASIC command or expression typed
directly at the command prompt.  For example:

    PRINT ADD(123456,654321)

will print `777777`.  All the standard BASIC numerical, logical, and relational
operators are available as well.

Notice that BASIC-DOS 1) doesn't require function names to begin with "FN",
2) it allows them to be defined at the command prompt (ie, what IBM PC BASIC
calls "Direct Mode", aka Immediate Mode), and 3) it allows multi-line function
definitions within BASIC files, enabling the creation of more sophisticated
functions.

Take this opportunity to experiment with BASIC-DOS line-editing, which combines
all the editing features of both PC DOS and PC BASIC, improving the PC DOS
editing experience.  Use the BASIC-DOS `HELP` command to list available editing
keys (`HELP KEYS`).

Next: [Pipes and Sessions](../part4/)