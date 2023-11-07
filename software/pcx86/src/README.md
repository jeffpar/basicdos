## BASIC-DOS Source Files

Copyright (c) 2020-2021 [Jeff Parsons](mailto:Jeff@pcjs.org)   
Released under MIT License: https://basicdos.com/LICENSE.txt  
For more information: https://github.com/jeffpar/basicdos

Sources are divided into the following directories:

  - [BOOT](boot/)
  - [CMD](cmd/)
  - [DEV](dev/)
  - [DOS](dos/)
  - [INC](inc/)
  - [MSB](msb/)
  - [TEST](test/)

The [BOOT](boot/) directory contains the code for the BASIC-DOS boot sector
(`BOOT.COM`) along with a small PC DOS (*not* BASIC-DOS) utility (`WBOOT.COM`)
to write the BASIC-DOS boot sector to the diskette currently in drive A:.

The [CMD](cmd/) directory contains the code for the BASIC-DOS Interpreter
(`COMMAND.COM`) and help text (`HELP.TXT`).

The [DEV](dev/) directory contains all the BASIC-DOS device drivers.
The drivers are built as a separate .COM files, which are then concatenated
into a single file (`IBMBIO.COM`), along with a binary "header" that contains
all the boot code that didn't fit in the boot sector (`BOOT2.COM`), and a
binary "footer" (`DEVINIT.COM`) responsible for initializing each of the
drivers and removing any unnecessary drivers from memory.

The [DOS](dos/) directory contains the BASIC-DOS "kernel" (`IBMDOS.COM`).

The [INC](inc/) directory contains all the BASIC-DOS include files:

    macros.inc
    8086.inc
    bios.inc
    disk.inc
    dev.inc
    devapi.inc
    dos.inc
    dosapi.inc
    version.inc

A low-level source file may need to include only `macros.inc` and `8086.inc`,
while a high-level source file may need to include more.

When MASM ran out of symbol space building some of the components,
I started separating *private* definitions from *public* ones (eg,
`dos.inc` and `dosapi.inc`).

The line between public and private is not formal; for example, EXEHDR is
arguably a public structure, but since it's not required by any DOS API, it's
defined in `dos.inc` rather than `dosapi.inc`.

The [TEST](test/) directory contains an assortment of test programs, some of
which assemble into `.COM` and `.EXE` files, while others are ready-to-run
`.BAT` and `.BAS` files.

Last but not least, the [MSB](msb/) directory contains a buildable copy of
Microsoft BASIC ("GW-BASIC"), using the open-source files from
[GitHub](https://github.com/microsoft/GW-BASIC) and a reverse-engineered OEM
source file courtesy of the [OS/2 Museum](msb/OEM.ASM).

NOTE: The Microsoft BASIC source files in the [MSB](msb/) directory are
copyright (c) Microsoft Corporation; see the [MIT License](msb/LICENSE).

The Microsoft BASIC files are included for reference and testing purposes only
and will *not* be part of the final BASIC-DOS distribution.  Any excerpts
incorporated into BASIC-DOS will be separately identified with the required
notices.

## The BASIC-DOS Build Process

The [BASIC-DOS Build Machine](https://basicdos.com/build/)
contains two 10Mb hard disks: drive C: contains all the tools used to build
BASIC-DOS, and drive D: contains all the source code.

To build BASIC-DOS, switch to drive D: and type **MK**. The **MK.BAT** batch
files use the Microsoft **MAKE** utility to do most of the work, but the batch
files are also responsible for copying the resulting binaries to whatever
diskette is currently in drive A:.

By default, the binaries contain *DEBUG* code (eg, assertions and debugging
aids).  To build non-debug binaries, type **MK FINAL**, or **MKCLEAN FINAL**
if switching between *DEBUG* and *FINAL* binaries.  The **MKCLEAN.BAT** batch
file simply deletes all the binaries before running **MK.BAT**.

