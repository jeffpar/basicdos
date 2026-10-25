## BASIC-DOS Source Files

Copyright (c) 2020-2026 [Jeff Parsons](mailto:Jeff@pcjs.org)   
Released under MIT License: https://basicdos.com/LICENSE.txt  
For more information: https://github.com/jeffpar/basicdos

Sources are divided into the following directories:

  - [INC](os/inc/)
  - [BOOT](os/boot/)
  - [DD](os/dd/)
  - [DEV](os/dev/)
  - [DOS](os/dos/)
  - [CMD](os/cmd/)
  - [UTIL](os/util/)
  - [MSB](msb/)
  - [TESTS](tests/)

along with [CONFIGS](configs/) (test configurations) and [TOOLS](tools/) (build tools; see below).

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
    uart.inc
    version.inc

A low-level source file may need to include only `macros.inc` and `8086.inc`, while a high-level source file may need to include more.

When MASM ran out of symbol space building some of the components, I started separating *private* definitions from *public* ones (eg, `dos.inc` and `dosapi.inc`).

The line between public and private is not formal; for example, EXEHDR is arguably a public structure, but since it's not required by any DOS API, it's defined in `dos.inc` rather than `dosapi.inc`.  Similarly, a few definitions that only drivers and the kernel use (eg, `IOCTL_COMDEBUG`) are in `dev.inc` rather than `devapi.inc`, because some COMMAND.COM modules don't have room for them.

The [BOOT](os/boot/) directory contains the code for the BASIC-DOS boot sector (`BOOT.COM`) along with a small PC DOS (*not* BASIC-DOS) utility (`WBOOT.COM`) to write the BASIC-DOS boot sector to the diskette currently in drive A:.

The [DD](os/dd/) directory contains installable device drivers, which are loaded with `DEVICE=` in CONFIG.SYS.  Each driver has its own subdirectory, with its own makefile and OBJ directory; currently, there's only [DBG](os/dd/dbg/), a simple serial debugger (`DEBUG.COM`).

The [DEV](os/dev/) directory contains all the built-in BASIC-DOS device drivers. The drivers are built as a separate .COM files, which are then concatenated into a single file (`BASDEV.COM`), along with a binary "header" that contains all the boot code that didn't fit in the boot sector (`BOOT2.COM`), and a binary "footer" (`DEVINIT.COM`) responsible for initializing each of the drivers and removing any unnecessary drivers from memory.

The [DOS](os/dos/) directory contains the BASIC-DOS "kernel" (`BASDOS.COM`), including the code that loads installable device drivers (`DRVINIT.ASM`).

The [CMD](os/cmd/) directory contains the code for the BASIC-DOS Command Shell (`COMMAND.COM`) and help text (`HELP.TXT`).

The [UTIL](os/util/) directory contains the external utilities: [MISC](os/util/misc/) contains the single-file utilities (the filters `FIND.COM`, `MORE.COM`, `SORT.COM`, `TEE.COM`, `TR.COM`, and `WC.COM`, along with `SLEEP.COM`), and each larger utility has its own directory, such as [VI](os/util/vi/) (the `VI.COM` text editor).

The [MSB](msb/) directory contains a buildable copy of Microsoft BASIC ("GW-BASIC"), using the open-source files from [GitHub](https://github.com/microsoft/GW-BASIC) and a reverse-engineered OEM source file courtesy of the [OS/2 Museum](msb/OEM.ASM).

NOTE: The Microsoft BASIC source files in the [MSB](msb/) directory are copyright (c) Microsoft Corporation; see the [MIT License](msb/LICENSE).  The Microsoft BASIC files are included for reference and testing purposes only and are *not* part of the final BASIC-DOS distribution.

The [TESTS](tests/) directory contains an assortment of test programs, some of which assemble into `.COM` and `.EXE` files (in `tests/bin`), while others are ready-to-run `.BAT` and `.BAS` files.

## Supporting Files

The [CONFIGS](configs/) directory contains the BASIC-DOS configurations (CONFIG.SYS, AUTOEXEC.BAT, etc) that `boot.sh` and `tools/tests/quick.sh` boot, after `tools/tests/prep.sh` copies the latest test binaries into them.

## The BASIC-DOS Build Process

The command-line build uses the repository's `tools/pc/pc.js` utility to run MASM 4.0 and its associated tools under MS-DOS 3.20 on an emulated COMPAQ DeskPro 386.  Drive C: contains MS-DOS and the build tools; drive D: is a 30Mb disk built from `software/src`, with room for the source code, binaries, and assembly listings (which are currently off: each makefile sets `LST=NUL`; set `LST=OBJ\$*.LST` to create them).  The MS-DOS batch files (**MKDOS.BAT** in each directory) chain from one directory to the next: BOOT, DD\\DBG, DEV, DOS, CMD, UTIL\\MISC, UTIL\\VI, TESTS, and MSB.

From the repository root, run `./mkdos.sh [FINAL or DEBUG] [CLEAN]` (the same arguments as `mk.sh`): `./mkdos.sh final` builds release (**FINAL**) binaries, and `./mkdos.sh debug` builds **DEBUG** binaries with assertions and debugging aids.  Without a mode, it uses the `config.release` property of the root package.json (`final` or `debug`), and the major and minor numbers of its `version` property are the BASIC-DOS version (see [tools/release.sh](../../tools/release.sh), which updates [version.inc](os/inc/version.inc) when they change).  Each mode keeps its own build outputs (when the mode changes, the script saves the other mode's `OBJ` folders in `tools/pc/disks/objs` and restores the new mode's), so switching modes rebuilds only what has changed since that mode's last build.  The guest startup runs **MKDOS** automatically; the **MKDOS.BAT** batch files use the Microsoft **MAKE** utility to assemble and link the components.  In each makefile, every module depends on `OBJ\INCS`, an empty file that depends on all the include files (every file in [os/inc](os/inc/), and the component's own), so changing any include file rebuilds every module of every component that could use it.  A successful build runs **QUIT**, writing modified files back to `software/src`.

If `PCJS` points to a checkout of the PCjs repository, `mkdos.sh` (and `mk.sh`) also runs the Gulp demo tasks after a successful build to update the BASIC-DOS demo disk images.  See the root [README](../../README.md) for setup details.  If a build fails, use PC.js's **abort** command to exit without updating the demo disks.

When invoking the guest batch files directly, **MKDOS DEBUG** and **MKDOS FINAL** select the build mode; **MKDOS** defaults to DEBUG unless the `MKFINAL` marker created by `mkdos.sh` is present.  Use **MKCLEAN DEBUG** or **MKCLEAN FINAL** when switching modes manually, since MAKE doesn't detect mode changes.  **MKCLEAN.BAT** deletes the build outputs before running **MKDOS.BAT**, which `mkdos.sh final clean` (or `mkdos.sh debug clean`) also does (by creating a `CLEAN` marker that tells **MKDOS.BAT** to run **MKCLEAN.BAT** first).

The `mk.sh` script builds BASIC-DOS on BASIC-DOS instead, from a bootable BASIC-DOS hard disk that PC.js builds from this directory, using the build tools in [TOOLS](tools/) (MASM, LINK, MAKE, EXE2BIN, EXEMOD, and MAPSYM) and the [CONFIG.SYS](CONFIG.SYS) in this directory (see the script for details).  It runs the BASIC-DOS batch file `os/mk.bat` (which builds BOOT, DD\\DBG, DEV, DOS, CMD, and UTIL, as the hard disk demos do), followed by the TESTS and MSB makefiles.  It uses the same machine (COMPAQ DeskPro 386) and 30Mb FAT16 disk format as `mkdos.sh` (2K clusters, 512 root entries), and its binaries are identical to those built on MS-DOS.  BASIC-DOS runs DOS calls on the caller's stack, so EXE2BIN has been patched to raise its initial stack from 128 bytes to 2K (SP 0080h to 0800h, with minimum allocation 81h) and to move its file buffer (segment 4Fh, relative to the load segment, at offset 15Fh in its code) up to segment C7h, just above the larger stack. Run `./mk.sh [FINAL or DEBUG] [CLEAN]` (the same arguments as os/mk.bat); as with `mkdos.sh`, the default is package.json's `config.release` property. Add `clean` after the mode (eg, `./mk.sh debug clean` or `./mk.sh final clean`) to have BASIC-DOS delete the build outputs first (using the CLEAN option of `os/mk.bat`: **MK [FINAL or DEBUG] [CLEAN]**).  Like **MKDOS**, **MK** without a mode builds DEBUG binaries, unless there's an `MKFINAL` file in the parent directory (which `mkdos.sh` creates here for FINAL builds); the BASICDOS-10MB disk has one in its root (above SRC) when its binaries are FINAL, so that MK there rebuilds in the same mode.

After building, run `tools/tests/quick.sh` from the repository root for unattended confidence tests on machines with and without an 8087.  The `boot.sh` script provides interactive BASIC-DOS sessions: `./boot.sh` alone uses software floating-point, and `./boot.sh fpu`, `./boot.sh hd`, etc. select other configurations (see the script for the list).

Run `python3 tools/tests/boot.py` to test booting without CONFIG.SYS, rejection of missing required system files, and hard disk partition offsets around sector 65,536.
