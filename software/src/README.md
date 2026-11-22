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
  - [DLL](os/dll/)
  - [SDK](os/sdk/)
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
    os2.inc
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

The [UTIL](os/util/) directory contains the external utilities: [MISC](os/util/misc/) contains the single-file utilities (the filters `FIND.COM`, `MORE.COM`, `SED.COM`, `SORT.COM`, `TEE.COM`, `TR.COM`, `UNIQ.COM`, and `WC.COM`, along with `SLEEP.COM`), and each larger utility has its own directory, such as [VI](os/util/vi/) (the `VI.COM` text editor) and [V86](os/util/v86/) (`V86.COM`, which runs real-mode programs in a V86 machine).

The [DLL](os/dll/) directory contains the NE libraries that the kernel's NE loader looks for in the system drive's EXT\DLL directory (or the one that a `LIBPATH=` line in CONFIG.SYS names) when a protected-mode NE program imports their functions: `DOSCALLS.DLL` provides OS/2's DOSCALLS functions as DOS calls.

The [SDK](os/sdk/) directory contains programs to build on BASIC-DOS itself (it's SRC\\SDK on the hard disk, and the BASIC-DOS build doesn't build them): `MEM32.EXE` is a 32-bit LE program, which `MAKE MAKEFILE` there assembles with MASM5 (with the system's macros, from SRC\\INC; `MAKE REL=DEBUG MAKEFILE` defines DEBUG, so that DBGBRK and ASSERT assemble their INT 3s) and links with LINK386, in protected mode; and `FIND16.EXE` is a 16-bit OS/2 1.x program, a version of `FIND.COM` (without regular expressions) that calls only OS/2's DOSCALLS functions (with PCALL, from SRC\\INC's `os2.inc`), which MASM5 and LINK4 build, so the same file runs on OS/2 and, in protected mode, on BASIC-DOS (in real mode, its stub says it requires protected mode), where it can be compared with `FIND.COM`; and `FIND32.EXE` is the same program again as a 32-bit LE program written in C (`find32.c`), which CL386 (the Microsoft 386 C Compiler, in TOOLS\\BIN) compiles and LINK386 links with `crt32.asm` (startup code and a small library of DOS calls, declared in `crt32.h`), since the compiler's own library is for OS/2 2.0.

The [MSB](msb/) directory contains a buildable copy of Microsoft BASIC ("GW-BASIC"), using the open-source files from [GitHub](https://github.com/microsoft/GW-BASIC) and a reverse-engineered OEM source file courtesy of the [OS/2 Museum](msb/OEM.ASM).  The open-source files lack TIMER, so this copy adds it, as in BASICA and later GW-BASIC versions: the TIMER function (seconds since midnight, to hundredths), TIMER ON, OFF, and STOP, and ON TIMER(*n*) GOSUB (*n* = 1 to 86400 seconds).

NOTE: The Microsoft BASIC source files in the [MSB](msb/) directory are copyright (c) Microsoft Corporation; see the [MIT License](msb/LICENSE).  The Microsoft BASIC files are included for reference and testing purposes only and are *not* part of the final BASIC-DOS distribution.

The [TESTS](tests/) directory matches the TESTS directory of the BASIC-DOS disks: [REGRESS](tests/regress/) has the regression tests, and [MISC](tests/misc/) has the other test programs (see `software/manifest.txt` for what goes where), along with [TOOLS](tests/tools/) for the test tools (DISKREAD and DISKWRIT); their assembly-language programs are built in each folder's `OBJ` folder, while others are ready-to-run `.BAT` and `.BAS` files.

## Supporting Files

The [CONFIGS](configs/) directory contains the BASIC-DOS configurations (CONFIG.SYS, AUTOEXEC.BAT, etc) that `boot.sh` and `tools/tests/quick.sh` boot, after `tools/tests/prep.sh` copies the latest test binaries into them.

## The BASIC-DOS Build Process

The command-line build uses the repository's `tools/pc/pc.js` utility to run the build tools under MS-DOS 3.20 on an emulated COMPAQ DeskPro 386.  Drive C: contains MS-DOS (and MASM 4.0 and C 4.00 tools), but its AUTOEXEC.BAT puts **D:\\TOOLS\\DOS** first in the PATH, so the build uses the same tools as `mk.sh` (the originals in [TOOLS/DOS](tools/dos/): MASM5, LINK 3.05, MAKE 4.02, and so on); drive D: is a 30Mb disk built from `software/src`, with room for the source code, binaries, and assembly listings (which are currently off: each makefile sets `LST=NUL`; set `LST=OBJ\$*.LST` to create them).  The MS-DOS batch files (**MKDOS.BAT** in each directory) chain from one directory to the next: BOOT, DD\\DBG, DEV, DOS, CMD, UTIL\\MISC, UTIL\\VI, TESTS, and MSB.

From the repository root, run `./mkdos.sh [FINAL or DEBUG] [CLEAN]` (the same arguments as `mk.sh`): `./mkdos.sh final` builds release (**FINAL**) binaries, and `./mkdos.sh debug` builds **DEBUG** binaries with assertions and debugging aids.  Without a mode, it uses the `config.release` property of the root package.json (`final` or `debug`), and the major and minor numbers of its `version` property are the BASIC-DOS version, with a nonzero patch number (1-26) as its revision letter (eg, "2.10.1" is 2.10A; see [tools/release.sh](../../tools/release.sh), which updates [version.inc](os/inc/version.inc) when they change).  Each mode keeps its own build outputs (when the mode changes, the script saves the other mode's `OBJ` folders in `tools/pc/disks/objs` and restores the new mode's), so switching modes rebuilds only what has changed since that mode's last build.  The guest startup runs **MKDOS** automatically; the **MKDOS.BAT** batch files use the Microsoft **MAKE** utility to assemble and link the components.  The makefiles assemble with MASM5 (`ASM=MASM5`); running MAKE with `ASM=MASM` uses MASM 4.0 instead.  In each makefile, every module depends on `OBJ\INCS`, an empty file that depends on all the include files (every file in [os/inc](os/inc/), and the component's own), so changing any include file rebuilds every module of every component that could use it.  A successful build runs **QUIT**, writing modified files back to `software/src`.

If `PCJS` points to a checkout of the PCjs repository, `mkdos.sh` (and `mk.sh`) also runs the Gulp demo tasks after a successful build to update the BASIC-DOS demo disk images.  See the root [README](../../README.md) for setup details.  If a build fails, use PC.js's **abort** command to exit without updating the demo disks.

When invoking the guest batch files directly, **MKDOS DEBUG** and **MKDOS FINAL** select the build mode; **MKDOS** defaults to DEBUG unless the `MKFINAL` marker created by `mkdos.sh` is present.  Use **MKCLEAN DEBUG** or **MKCLEAN FINAL** when switching modes manually, since MAKE doesn't detect mode changes.  **MKCLEAN.BAT** deletes the build outputs before running **MKDOS.BAT**, which `mkdos.sh final clean` (or `mkdos.sh debug clean`) also does (by creating a `CLEAN` marker that tells **MKDOS.BAT** to run **MKCLEAN.BAT** first).

The `mk.sh` script builds BASIC-DOS on BASIC-DOS instead, from a bootable BASIC-DOS hard disk that PC.js builds from this directory, using the build tools in [TOOLS](tools/) (MASM5, LINK, LINK4, MAKE, EXE2BIN, EXEMOD, and MAPSYM) and the [CONFIG.SYS](CONFIG.SYS) in this directory (see the script for details).  It runs the BASIC-DOS batch file `os/mk.bat` (which builds BOOT, DD\\DBG, DEV, DOS, CMD, and UTIL, as the hard disk demos do), followed by the TESTS and MSB makefiles.  It uses the same machine (COMPAQ DeskPro 386) and 30Mb FAT16 disk format as `mkdos.sh` (2K clusters, 512 root entries), and its binaries are identical to those built on MS-DOS.  BASIC-DOS runs DOS calls on the caller's stack, so EXE2BIN has been patched to raise its initial stack from 128 bytes to 2K (SP 0080h to 0800h, with minimum allocation 81h) and to move its file buffer (segment 4Fh, relative to the load segment, at offset 15Fh in its code) up to segment C7h, just above the larger stack. Run `./mk.sh [FINAL or DEBUG] [CLEAN]` (the same arguments as os/mk.bat); as with `mkdos.sh`, the default is package.json's `config.release` property. Add `clean` after the mode (eg, `./mk.sh debug clean` or `./mk.sh final clean`) to have BASIC-DOS delete the build outputs first (using the CLEAN option of `os/mk.bat`: **MK [FINAL or DEBUG] [CLEAN]**).  Like **MKDOS**, **MK** without a mode builds DEBUG binaries, unless there's an `MKFINAL` file in the parent directory (which `mkdos.sh` creates here for FINAL builds); the BASICDOS-10MB disk has one in its root (above SRC) when its binaries are FINAL, so that MK there rebuilds in the same mode.

The tools come from two folders: [TOOLS/DOS](tools/dos/) has the original versions, and [TOOLS/BD](tools/bd/) has BASIC-DOS versions that replace them.  The hard disk's **TOOLS\\BIN** folder gets the first, overlaid with the second, and `mk.sh` searches **TOOLS\\BD** before **TOOLS\\DOS**.  **TOOLS/BD** has NE conversions of MASM 4.00, MASM 5.10B, MAKE 4.02, LINK 3.05, LINK4 5.00.12, EXEMOD 4.00, MAPSYM 4.00, EXE2BIN, and the C 4.00 compiler (CL, C1, C2, and C3; see [TOOLS/README.TXT](tools/README.TXT) for where the tools came from, and [TOOLS/README.md](tools/README.md) for the conversions and for building protected-mode C programs) that run at ring 3 in protected mode, and in real mode through an NE loader stub (`nestub.asm`, in [TOOLS/BD/STUB](tools/bd/stub/), whose binary is `NESTUB.BIN`; the `STUB.EXE` built there adds it to any NE program on BASIC-DOS, as [TOOLS/BD/DEMOS/HELLO](tools/bd/demos/hello/)'s makefile shows), so they run the same code in either mode.  Their banners end in **BD** (eg, **Version 4.00BD**).  Their data segments are always 64K, whereas the originals use less when memory is short, so in real mode, MAKE and MASM 4.00 together need about 229K of free memory.  `mk.sh` builds in protected mode, the default on its DeskPro 386, so the tools run at ring 3; with a `CPU=8088` line in its CONFIG.SYS, the same build runs in real mode and produces the same binaries.  Run `node tools/misc/mkne.js` to rebuild all the conversions.

After building, run `tools/tests/quick.sh` from the repository root for unattended confidence tests on machines with and without an 8087.  The `boot.sh` script provides interactive BASIC-DOS sessions: `./boot.sh` alone uses software floating-point, and `./boot.sh fpu`, `./boot.sh hd`, etc. select other configurations (see the script for the list).

Run `python3 tools/tests/boot.py` to test booting without CONFIG.SYS, rejection of missing required system files, and hard disk partition offsets around sector 65,536.
