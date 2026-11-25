## BASIC-DOS Source Files

Copyright (c) 2020-2026 [Jeff Parsons](mailto:Jeff@pcjs.org)   
Released under MIT License: https://basicdos.com/LICENSE.txt  
For more information: https://github.com/jeffpar/basicdos

Sources are divided into the following directories, each with a README that describes its contents:

  - [OS](os/): the BASIC-DOS operating system
    - [INC](os/inc/): the include files that every component shares
    - [BOOT](os/boot/): the boot sector (`BOOT.COM`) and the tool that writes it (`WBOOT.COM`)
    - [DEV](os/dev/): the built-in device drivers (`BASDEV.COM`)
    - [DOS](os/dos/): the kernel (`BASDOS.COM`)
    - [CMD](os/cmd/): the command shell (`COMMAND.COM`) and help text (`HELP.TXT`)
    - [DD](os/dd/): the installable device drivers (`DEBUG.COM`)
    - [UTIL](os/util/): the external commands, in [BAS](os/util/bas/), [MISC](os/util/misc/), [VI](os/util/vi/), and [V86](os/util/v86/)
    - [DLL](os/dll/): the NE libraries (`DOSCALLS.DLL`, etc)
    - [SDK](os/sdk/): sample programs built on BASIC-DOS itself
  - [TESTS](tests/): the tests, in [REGRESS](tests/regress/), [MISC](tests/misc/), [TOOLS](tests/tools/), and [LIB](tests/lib/)
  - [DEMOS](demos/): the demo programs
  - [MSB](msb/): a buildable copy of Microsoft BASIC ("GW-BASIC"), for reference and testing only
  - [CONFIGS](configs/): the test configurations that `boot.sh` and `tools/tests/quick.sh` boot, and the CONFIG.SYS for `mk.sh`
  - [TOOLS](tools/): the build tools (see below)

This directory also contains **MKDOS.BAT** and **MKCLEAN.BAT**, which begin the build that `mkdos.sh` runs.

## The BASIC-DOS Build Process

The command-line build uses the repository's `tools/pc/pc.js` utility to run the build tools under MS-DOS 3.20 on an emulated COMPAQ DeskPro 386.  Drive C: contains MS-DOS (and MASM 4.0 and C 4.00 tools), but its AUTOEXEC.BAT puts **D:\\TOOLS\\DOS** first in the PATH, so the build uses the same tools as `mk.sh` (the originals in [TOOLS/DOS](tools/dos/): MASM5, LINK 3.05, MAKE 4.02, and so on); drive D: is a 30Mb disk built from `src`, with room for the source code, binaries, and assembly listings (which are currently off: each makefile sets `LST=NUL`; set `LST=OBJ\$*.LST` to create them).  The MS-DOS batch files (**MKDOS.BAT** in each directory) chain from one directory to the next: BOOT, DD\\DBG, DEV, DOS, CMD, UTIL\\MISC, UTIL\\VI, UTIL\\V86, DLL, TESTS, and MSB.

From the repository root, run `./mkdos.sh [FINAL or DEBUG] [CLEAN]` (the same arguments as `mk.sh`): `./mkdos.sh final` builds release (**FINAL**) binaries, and `./mkdos.sh debug` builds **DEBUG** binaries with assertions and debugging aids.  Without a mode, it uses the `config.release` property of the root package.json (`final` or `debug`), and the major and minor numbers of its `version` property are the BASIC-DOS version, with a nonzero patch number (1-26) as its revision letter (eg, "2.10.1" is 2.10A; see [tools/release.sh](../tools/release.sh), which updates [version.inc](os/inc/version.inc) when they change).  Each mode keeps its own build outputs (when the mode changes, the script saves the other mode's `OBJ` folders in `tools/pc/disks/objs` and restores the new mode's), so switching modes rebuilds only what has changed since that mode's last build.  The guest startup runs **MKDOS** automatically; the **MKDOS.BAT** batch files use the Microsoft **MAKE** utility to assemble and link the components.  The makefiles assemble with MASM5 (`ASM=MASM5`); running MAKE with `ASM=MASM` uses MASM 4.0 instead.  In each makefile, every module depends on `OBJ\INCS`, an empty file that depends on all the include files (every file in [os/inc](os/inc/), and the component's own), so changing any include file rebuilds every module of every component that could use it.  A successful build runs **QUIT**, writing modified files back to `src`.

If `PCJS` points to a checkout of the PCjs repository, `mkdos.sh` (and `mk.sh`) also runs the Gulp demo tasks after a successful build to update the BASIC-DOS demo disk images.  See the root [README](../README.md) for setup details.  If a build fails, use PC.js's **abort** command to exit without updating the demo disks.

When invoking the guest batch files directly, **MKDOS DEBUG** and **MKDOS FINAL** select the build mode; **MKDOS** defaults to DEBUG unless the `MKFINAL` marker created by `mkdos.sh` is present.  Use **MKCLEAN DEBUG** or **MKCLEAN FINAL** when switching modes manually, since MAKE doesn't detect mode changes.  **MKCLEAN.BAT** deletes the build outputs before running **MKDOS.BAT**, which `mkdos.sh final clean` (or `mkdos.sh debug clean`) also does (by creating a `CLEAN` marker that tells **MKDOS.BAT** to run **MKCLEAN.BAT** first).

The `mk.sh` script builds BASIC-DOS on BASIC-DOS instead, from a bootable BASIC-DOS hard disk that PC.js builds from this directory, using the build tools in [TOOLS](tools/) (MASM5, LINK, LINK4, MAKE, EXE2BIN, EXEMOD, and MAPSYM) and [configs/mk/CONFIG.SYS](configs/mk/CONFIG.SYS) (see the script for details).  It runs the BASIC-DOS batch file `os/mk.bat` (which builds BOOT, DD\\DBG, DEV, DOS, CMD, UTIL, and DLL, as the hard disk demos do), followed by the TESTS and MSB makefiles.  It uses the same machine (COMPAQ DeskPro 386) and 30Mb FAT16 disk format as `mkdos.sh` (2K clusters, 512 root entries), and its binaries are identical to those built on MS-DOS.  BASIC-DOS runs DOS calls on the caller's stack, so EXE2BIN has been patched to raise its initial stack from 128 bytes to 2K (SP 0080h to 0800h, with minimum allocation 81h) and to move its file buffer (segment 4Fh, relative to the load segment, at offset 15Fh in its code) up to segment C7h, just above the larger stack. Run `./mk.sh [FINAL or DEBUG] [CLEAN]` (the same arguments as os/mk.bat); as with `mkdos.sh`, the default is package.json's `config.release` property. Add `clean` after the mode (eg, `./mk.sh debug clean` or `./mk.sh final clean`) to have BASIC-DOS delete the build outputs first (using the CLEAN option of `os/mk.bat`: **MK [FINAL or DEBUG] [CLEAN]**).  Like **MKDOS**, **MK** without a mode builds DEBUG binaries, unless there's an `MKFINAL` file in the parent directory (which `mkdos.sh` creates here for FINAL builds); the BASICDOS-20MB disk has one in its root (above SRC) when its binaries are FINAL, so that MK there rebuilds in the same mode.

The tools come from two folders: [TOOLS/DOS](tools/dos/) has the original versions, and [TOOLS/BD](tools/bd/) has BASIC-DOS versions that replace them.  The hard disk's **TOOLS\\BIN** folder gets the first, overlaid with the second, and `mk.sh` searches **TOOLS\\BD** before **TOOLS\\DOS**.  **TOOLS/BD** has NE conversions of MASM 4.00, MASM 5.10B, MAKE 4.02, LINK 3.05, LINK4 5.00.12, EXEMOD 4.00, MAPSYM 4.00, EXE2BIN, and the C 4.00 compiler (CL, C1, C2, and C3; see [TOOLS/README.TXT](tools/README.TXT) for where the tools came from, and [TOOLS/README.md](tools/README.md) for the conversions and for building protected-mode C programs) that run at ring 3 in protected mode, and in real mode through an NE loader stub (`nestub.asm`, in [TOOLS/BD/STUB](tools/bd/stub/), whose binary is `NESTUB.BIN`; the `STUB.EXE` built there adds it to any NE program on BASIC-DOS, as [TOOLS/BD/DEMOS/HELLO](tools/bd/demos/hello/)'s makefile shows), so they run the same code in either mode.  Their banners end in **BD** (eg, **Version 4.00BD**).  Their data segments are always 64K, whereas the originals use less when memory is short, so in real mode, MAKE and MASM 4.00 together need about 229K of free memory.  `mk.sh` builds in protected mode, the default on its DeskPro 386, so the tools run at ring 3; with a `CPU=8088` line in its CONFIG.SYS, the same build runs in real mode and produces the same binaries.  Run `node tools/misc/mkne.js` to rebuild all the conversions.

After building, run `tools/tests/quick.sh` from the repository root for unattended confidence tests on machines with and without an 8087.  The `boot.sh` script provides interactive BASIC-DOS sessions: `./boot.sh` alone uses software floating-point, and `./boot.sh fpu`, `./boot.sh hd`, etc. select other configurations (see the script for the list).
