---
layout: default
heading: Welcome to BASIC-DOS
permalink: /
---

## PC DOS Reimagined

Read the [Blog](blog/), then check out the [Preview](preview/), which
highlights a few of the original [Demos](demos/).

[![BASIC-DOS 1.00](assets/images/BASIC-DOS-Cover.gif)](preview/)

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
include on the floppy, specify it in place of the `200A` folder:

    $ pc.js ibm5160 software/pcx86/src/configs/200A --system=bd --version=2.00A --floppy --serial
    [Press CTRL-D to enter command mode]
    BASIC-DOS 2.00A
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
