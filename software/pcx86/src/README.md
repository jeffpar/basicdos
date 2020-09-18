## BASIC-DOS Source Files

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
to write the BASIC-DOS boot sector to the diskette is currently in drive A:.

The [CMD](cmd/) directory contains the code for the BASIC-DOS Interpreter
(`COMMAND.COM`) and help text (`COMMAND.TXT`).

The [DEV](dev/) directory contains all the BASIC-DOS device drivers.
The drivers are built as a separate .COM files, which are then concatenated
into a single file (`IBMBIO.COM`), along with a binary "header" that contains
all the boot code that didn't fit in the boot sector (`BOOT2.COM`), and a
binary "footer" (`DEVINIT.COM`) responsible for initializing each of the
drivers and removing any unnecessary drivers from memory.

The [DOS](dos/) directory contains the BASIC-DOS "kernel" (`IBMDOS.COM`).

The [INC](inc/) directory contains all the include files, which use a somewhat
arbitrary singly-linked hierarchy:

    dos.inc
    +- dev.inc
       +- disk.inc
          +- bios.inc
             +- 8086.inc
                +- macros.inc

However, since MASM started running out of symbol space when building some
of the components, I moved "public" portions of `dos.inc` and `dev.inc`
into `dosapi.inc` and `devapi.inc`.

So now a device driver like the CONSOLE driver (`CONDEV.ASM`) can include
`dev.inc` and `dosapi.inc` instead of `dos.inc`.  The CONSOLE driver is a
more complex driver that requires access to special DOS "utility" interfaces,
whereas most drivers, like the Floppy Drive Controller driver (`FDCDEV.ASM`),
need only include `dev.inc`.

The [TEST](test/) directory contains an assortment of test programs, some of
which assemble into `.COM` and `.EXE` files, while others are ready-to-run
`.BAT` and `.BAS` files.

Last but not least, the [MSB](msb/) directory contains a buildable copy of
Microsoft BASIC ("GW-BASIC"), using the open-sourced files from
[GitHub](https://github.com/microsoft/GW-BASIC) and
[OS/2 Museum](msb/OEM.ASM).

## The BASIC-DOS Build Process

The [BASIC-DOS Development Machine](https://basicdos.com/maplebar/dev/)
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
