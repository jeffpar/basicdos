## BASIC-DOS Source Files

Copyright (c) 2020-2026 [Jeff Parsons](mailto:Jeff@pcjs.org)   
Released under MIT License: https://basicdos.com/LICENSE.txt  
For more information: https://github.com/jeffpar/basicdos

Sources are divided into the following directories:

  - [BOOT](os/boot/)
  - [CMD](os/cmd/)
  - [DEV](os/dev/)
  - [DOS](os/dos/)
  - [INC](os/inc/)
  - [MSB](msb/)
  - [TESTS](tests/)

The [BOOT](os/boot/) directory contains the code for the BASIC-DOS boot sector (`BOOT.COM`) along with a small PC DOS (*not* BASIC-DOS) utility (`WBOOT.COM`) to write the BASIC-DOS boot sector to the diskette currently in drive A:.

The [CMD](os/cmd/) directory contains the code for the BASIC-DOS Command Processor (`COMMAND.COM`) and help text (`HELP.TXT`).

The [DEV](os/dev/) directory contains all the BASIC-DOS device drivers. The drivers are built as a separate .COM files, which are then concatenated into a single file (`BASDEV.COM`), along with a binary "header" that contains all the boot code that didn't fit in the boot sector (`BOOT2.COM`), and a binary "footer" (`DEVINIT.COM`) responsible for initializing each of the drivers and removing any unnecessary drivers from memory.

The [DOS](os/dos/) directory contains the BASIC-DOS "kernel" (`BASDOS.COM`).

The [INC](os/inc/) directory contains all the BASIC-DOS include files:

    8086.inc
    bios.inc
    dev.inc
    devapi.inc
    disk.inc
    dos.inc
    dosapi.inc
    fpu.inc
    macros.inc
    parser.inc
    version.inc

A low-level source file may need to include only `macros.inc` and `8086.inc`, while a high-level source file may need to include more.

When MASM ran out of symbol space building some of the components, I started separating *private* definitions from *public* ones (eg, `dos.inc` and `dosapi.inc`).

The line between public and private is not formal; for example, EXEHDR is arguably a public structure, but since it's not required by any DOS API, it's defined in `dos.inc` rather than `dosapi.inc`.

The [TESTS](tests/) directory contains an assortment of test programs, some of which assemble into `.COM` and `.EXE` files, while others are ready-to-run `.BAT` and `.BAS` files.

Last but not least, the [MSB](msb/) directory contains a buildable copy of Microsoft BASIC ("GW-BASIC"), using the open-source files from [GitHub](https://github.com/microsoft/GW-BASIC) and a reverse-engineered OEM source file courtesy of the [OS/2 Museum](msb/OEM.ASM).

NOTE: The Microsoft BASIC source files in the [MSB](msb/) directory are copyright (c) Microsoft Corporation; see the [MIT License](msb/LICENSE).

The Microsoft BASIC files are included for reference and testing purposes only and will *not* be part of the final BASIC-DOS distribution.  Any excerpts incorporated into BASIC-DOS will be separately identified with the required notices.

## The BASIC-DOS Build Process

The command-line build uses the repository's `tools/pc/pc.js` utility to run MASM 4.0 and its associated tools under MS-DOS 3.20 on an emulated COMPAQ DeskPro 386.  Drive C: contains MS-DOS and the build tools; drive D: is a 30Mb disk built from `software/pcx86/src`, with room for the source code, binaries, and assembly listings.

From the repository root, run `./mk.sh` to build release (**FINAL**) binaries, or `./mk.sh debug` to build **DEBUG** binaries with assertions and debugging aids.  The script forces a rebuild when the mode changes.  The guest startup runs **MK** automatically; the **MK.BAT** batch files use the Microsoft **MAKE** utility to assemble and link the components.  A successful build runs **QUIT**, writing modified files back to `software/pcx86/src`.

If `PCJS` points to a checkout of the PCjs repository, `mk.sh` also runs the Gulp demo tasks after a successful build to update the BASIC-DOS demo disk images.  See the root [README](../../../README.md) for setup details.  If a build fails, use PC.js's **abort** command to exit without updating the demo disks.

When invoking the guest batch files directly, **MK DEBUG** and **MK FINAL** select the build mode; **MK** defaults to DEBUG unless the `MKFINAL` marker created by `mk.sh` is present.  Use **MKCLEAN DEBUG** or **MKCLEAN FINAL** when switching modes manually, since MAKE doesn't detect mode changes.  **MKCLEAN.BAT** deletes the build outputs before running **MK.BAT**.

After building, run `tools/tests/quick.sh` from the repository root for unattended confidence tests on machines with and without an 8087.  The `boot.sh`, `bootfpu.sh`, and `boothd.sh` scripts provide interactive BASIC-DOS sessions with software floating-point, an 8087, and a bootable hard disk, respectively.
