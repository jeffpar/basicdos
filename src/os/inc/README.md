## BASIC-DOS Include Files

This directory contains the include files that every component shares.  A low-level source file may need only `macros.inc` and `8086.inc`, while a high-level one may need more.  Because MASM ran out of symbol space building some components, *private* definitions are separate from *public* ones (eg, `dos.inc` and `dosapi.inc`), and the larger files are divided into sections that a module can select (eg, DOSFUNC in `dosapi.inc`).

The line between public and private isn't formal; for example, EXEHDR is arguably public, but since no DOS API requires it, it's in `dos.inc` rather than `dosapi.inc`.  Similarly, a few definitions that only drivers and the kernel use (eg, `IOCTL_COMDEBUG`) are in `dev.inc` rather than `devapi.inc`, because some COMMAND.COM modules don't have room for them.  `version.inc` holds the BASIC-DOS version, which `tools/release.sh` updates.
