---
layout: default
heading: Welcome to BASIC-DOS
permalink: /
---

# PC DOS Reimagined

Read the [Blog](blog/), then check out the [Preview](preview/), which
highlights a few of the original [Demos](demos/).

[![BASIC-DOS 1.00](assets/images/BASIC-DOS-Cover.gif)](preview/)

## Project Status

BASIC-DOS began as a technology demo: a reimagining of what the first IBM PC
operating system *could* have been, with a unified DOS and BASIC command
interpreter, preemptive multitasking sessions, and other features that PC DOS
wouldn't offer for years (if ever).  The goal now is to turn it into a usable
product.

This section tracks what's been completed (**[x]**) and what remains
(**[ ]**).  Items marked *partial* work, but with known gaps.

### Boot and System Configuration

- [x] Boot sector that loads the BASIC-DOS drivers, kernel, and interpreter
- [x] Boot prompt when a hard disk is detected (press **Esc** to boot from it)
- [x] CONFIG.SYS support for BOOTKEY, CONSOLE, DEBUG, FILES, MEMSIZE,
      SESSIONS, SHELL, and SWITCHAR
- [ ] Installable device drivers (DEVICE=)
- [ ] Critical ("hard") error handling (eg, "Abort, Retry, Ignore")

### Device Drivers

- [x] CON, with multiple console contexts (one per session)
- [x] COM, AUX, LPT, PRN, NUL, CLOCK$, and PIPE$ devices
- [x] Interrupt-driven, asynchronous I/O for CON and COM
- [x] Floppy disk reads, including multi-track requests and requests
      that cross 64K boundaries
- [x] Floppy disk writes
- [x] Media check and BPB rebuilds (reads PC DOS 1.x and 2.x diskettes)
- [ ] Write-with-verify (DDC_WRITEV), formatting, and hard disk support
- [ ] "Popup" and background console contexts

### Kernel: Processes, Memory, and Sessions

- [x] COM and EXE program loading, PSPs, EXEC, and exit codes
- [x] Memory allocation (MCBs), including per-program heap requests
- [x] Preemptive multitasking of multiple sessions
- [x] CTRL-C/CTRL-Break handling, and CTRL-ALT-DEL session aborts
- [ ] Session STOP/END operations (currently TODOs)
- [ ] TSR support (INT 27h and INT 21h function 31h)
- [ ] Environment segments for EXEC (EPB_ENVSEG)

### Kernel: File System

- [x] FAT12 file reading
- [x] Handle-based open, read, seek, IOCTL, and close
- [x] Find first/next, disk info (free space), and current drive/DTA
- [x] Handle-based file creation (function 3Ch) and writing (function 40h)
- [x] File deletion (function 41h) and renaming (function 56h)
- [x] FAT cluster allocation and freeing
- [x] Write-back of modified FAT and directory buffers (every FAT copy is
      updated), including when the buffer is reused, on file close, disk
      reset, and restart
- [ ] *partial*: FCB support (open, close, and reads only; no create,
      write, delete, or rename)
- [ ] Truncating/extending a file with a zero-length write
- [ ] Enforcing the read-only attribute on open, and getting/setting file
      attributes (function 43h) and date/time (function 57h)
- [ ] Subdirectories (MKDIR, RMDIR, CHDIR, and paths)
- [ ] Absolute disk reads and writes (INT 25h and INT 26h)
- [ ] FAT16, hard disks, and a larger buffer cache (there are currently
      only two sector buffers: one for FAT sectors and one for directory
      sectors)

### Command Interpreter: DOS Commands

- [x] COPY, DATE, DIR, EXIT, HELP, KEYS, MEM, RESTART, TIME, TYPE, and VER
- [x] Running COM, EXE, BAT, and BAS files, and loading programs into
      other sessions
- [x] Pipes (`|`) and redirection (`>`)
- [x] COPY creates (or truncates) the output file, and refuses to copy a
      file onto itself
- [ ] *partial*: Output redirection works only with existing files (it
      should use DOS_HDL_CREATE, like COPY)
- [ ] DEL/ERASE, REN/RENAME, and SAVE (for BASIC programs)
- [ ] Disk utilities (eg, FORMAT, CHKDSK, SYS)

### Command Interpreter: BASIC Language

- [x] 32-bit integer variables, constants, and expressions (including
      AND, OR, XOR, EQV, IMP, NOT, MOD, and shifts)
- [x] String variables, concatenation, and comparisons
- [x] CLS, COLOR, DEF FN, DEFINT, DEFSTR, ECHO, GOTO, IF/THEN/ELSE, LET,
      PRINT, REM, and RETURN
- [x] LOAD, LIST, NEW, and RUN
- [x] Functions: ERRORLEVEL, MAXINT, and RND%
- [ ] Control flow: GOSUB, FOR/NEXT, WHILE/WEND, and ON ... GOTO/GOSUB
- [ ] INPUT, READ, DATA, and RESTORE
- [ ] Arrays (DIM)
- [ ] String functions (eg, LEFT$, MID$, RIGHT$, LEN, CHR$, ASC, STR$, VAL)
- [ ] File I/O statements (eg, OPEN, CLOSE, PRINT #, INPUT #)
- [ ] Error handling (eg, ON ERROR, ERR, ERL)

### Floating-Point

BASIC-DOS will support only one floating-point type: IEEE 754 64-bit
(double-precision) values.  It won't use any MBF (Microsoft Binary Format)
code.

- [x] Parser support for floating-point constants (CLS_FLOAT tokens)
- [x] DEFDBL and DEFSNG are accepted (currently no effect)
- [x] MBF-based MSLIB option removed
- [ ] Utility functions DOS_UTL_ATOF64, DOS_UTL_I32F64, and DOS_UTL_OPF64
      (currently stubs)
- [ ] Arithmetic and comparison operations
- [ ] Conversions between integers and floating-point values
- [ ] Floating-point input (parsing) and output (PRINT formatting)
- [ ] Expression generator support for mixed integer/floating-point
      operations (promotion and demotion rules)
- [ ] Math functions (eg, SQR, SIN, COS, ATN, LOG, EXP)
- [ ] Optional 8087 coprocessor support

### Build, Tests, and Documentation

- [x] Builds with MASM 4.0 using `mk.sh` (PC.js) or the in-browser
      [Build Machine](build/)
- [x] DOSTESTS: CALL 5, memory allocation, file create/write/read-back,
      and file rename/delete tests
- [x] Unattended test runs using `test.sh` (boots BASIC-DOS, runs DOSTESTS,
      and reports whether the tests passed)
- [ ] More tests (eg, BASIC language and CMD command tests)
- [ ] Complete the [BASIC-DOS manual](docs/pcx86/bdman/)

## Roadmap

These are the next steps, roughly in priority order:

1. Use DOS_HDL_CREATE for output redirection, and add the DEL and REN
   commands
2. Handle zero-length writes (truncation), the read-only attribute, and
   file attribute/date/time functions
3. FCB create, write, delete, and rename functions
4. Essential BASIC statements: GOSUB, FOR/NEXT, INPUT, READ/DATA, and DIM
5. BASIC string functions and file I/O statements
6. IEEE 754 floating-point support, starting with conversions and I/O
7. Critical error handling
8. Subdirectory support

## License

[BASIC-DOS](https://github.com/jeffpar/basicdos) is an open-source project
on [GitHub](https://github.com/jeffpar) released under the terms of an
[MIT License](/LICENSE.txt).

{% comment %}

## Building BASIC-DOS

The updated build process requires the [PCjs](https://github.com/jeffpar/pcjs)
repository, along with the `v2` branch of the BASIC-DOS repository.

    git clone https://github.com/jeffpar/pcjs
    git clone https://github.com/jeffpar/basicdos
    cd basicdos
    git checkout v2

It's recommended that you also set environment variables to the locations of
the repositories and then update your PATH to include the PCjs directories for
the `diskimage.js` and `pc.js` utilities:

    $ export PCJS="$HOME/pcjs"
    $ export BASICDOS="$HOME/basicdos"
    $ export PATH="$PATH:$PCJS/tools/diskimage:$PCJS/tools/pc"

Now you're ready to build BASIC-DOS, using `pc.js` to load a `tools` disk
image as drive C and the BASIC-DOS source code as drive D, using the `mk.sh`
script:

    $ mk.sh
    [Press CTRL-D to enter command mode]

    C>ECHO OFF
    Microsoft (R) Program Maintenance Utility  Version 4.02
    Copyright (C) Microsoft Corp 1984, 1985, 1986.  All rights reserved.
    
    ...

    D:\>quit

Assuming the `mk` script was successful, you should now have everything you
need to boot and run BASIC-DOS.

The `boot.sh` script runs `pc.js` again, this time building a 360K boot floppy
(the largest floppy supported by an IBM PC XT Model 5160) with BASIC-DOS boot
sector and system files. If you have a folder with different files you want to
include on the floppy, specify it in place of the `v2` folder:

    $ pc.js ibm5160 software/pcx86/src/configs/v2 --system=bd --version=2 --floppy --serial
    [Press CTRL-D to enter command mode]
    BASIC-DOS 2.00B
    Press a key to start...

## Tool Trivia

In keeping with the era for which BASIC-DOS is designed, it's built with
Microsoft Assembler (MASM) 4.0 and associated tools, circa 1985.  While we
could have opted for even older tools, the MASM 4.0 release strikes a nice
balance between vintage operation and modern tooling.

However, as with any old tools, there are idiosyncrasies that can catch you
by surprise.

One is how MASM encodes 32-bit and 64-bit floating-point numbers: by default,
it uses the Microsoft Binary Format (MBF) instead of the IEEE 754 format used
by 80x87 Intel coprocessors.  This is probably because Microsoft's original
floating-point emulation libraries were written using MBF and they didn't want
to spend time and resources creating new emulation libraries that supported
the newer IEEE 754 format.

So, by default, an assembly language data directive such as:

    DQ  1.0

will generate:

    00 00 00 00 00 00 00 81

instead of:

    00 00 00 00 00 00 F0 3F

And while neither the MASM 4.0 User Guide or Reference Manual discuss this,
it turns out that if you pass /R on the MASM command-line, MASM will use
the IEEE 754 format instead.  The stated purpose of /R is to generate 80x87
opcodes instead of emulation calls whenever using coprocessor instructions,
but another important consideration is encoding all floating-point number in
a compatible format (ie, IEEE 754 for coprocessors or MBF for the Microsoft
emulation library) -- which /R happens to do as well.

Other idiosyncrasies include some minor code generation quirks.  For example,
an instruction like:

    cmp	ah,UTILTBL_SIZE

should always generate 3 bytes (2 bytes for the opcode and 1 byte for the
immediate operand), but if a constant like UTILTBL_SIZE is calculated using
16-bit values, even if the result is 8 bits, MASM 4.0 will reserve 16 bits
and then replace the upper 8 bits with a NOP (0x90).

To eliminate the NOP, one work-around is to explicitly truncate the operand
with an 8-bit mask, as in:

    cmp	ah,UTILTBL_SIZE AND 255

{% endcomment %}
