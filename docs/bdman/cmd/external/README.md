---
layout: sheet
title: External Commands
permalink: /docs/bdman/cmd/external/
---

{% include header.html %}

Any program on a disk can be run as a command, by typing its name (see [Running Programs](../../intro/#running-programs)).  BASIC-DOS supports two kinds of external commands:

- Binary files (COM and EXE files)
- BASIC programs (BAT and BAS files)

If no extension is specified, BASIC-DOS looks for a COM, EXE, BAT, and BAS file, in that order.

### Binary Programs

COM and EXE files are loaded and run as in PC DOS, and many programs written for PC DOS 1.x and 2.x work, as long as they don't rely on features that BASIC-DOS doesn't support yet (eg, subdirectories).  One difference is that BASIC-DOS gives a COM program only the memory it needs (its file size plus at least 1K of heap), rather than all available memory, so that other sessions can use the rest.

When a binary program runs, COMMAND.COM temporarily releases most of its own memory (see [COMMAND.COM](command/)).

### BASIC Programs

BAT and BAS files are text files containing BASIC-DOS commands and BASIC statements (see [BASIC-DOS Programming](../../lang/)).  The differences between them are:

- BAT files can echo each line as it runs (after [ECHO ON](../device/screen/#echo)); BAS files can't
- BAS files run from the prompt remain loaded when they end, along with their variables, so they can be LIST'ed or RUN again

A BAT or BAS file can run other BAT or BAS files (no CALL command is required) and then continue; each nested BAS file gets its own variables.  See [Batch Files](../../lang/#batch-files) for how BASIC-DOS batch files differ from PC DOS batch files.

### Files Provided with BASIC-DOS

- [COMMAND.COM](command/): the BASIC-DOS Command Processor
- HELP.TXT: the text displayed by the [HELP](../system/#help) command

Every BASIC-DOS startup diskette also contains the system files BASDEV.COM (device drivers) and BASDOS.COM (the kernel).  These files must not be run.

{% include footer.html prev="Disk Commands:../disk/" next="COMMAND.COM:command/" %}
