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

A command's arguments are passed as typed, except that an argument that's a string variable is replaced by its value (eg, `FORMAT D$` formats the drive in `D$`); see [Command Arguments](../../lang/#command-arguments).

### Binary Programs

Many COM and EXE programs written for PC DOS 1.x and 2.x will work, as long as they don't rely on features that BASIC-DOS doesn't support (eg, TSR functions that allow a program to terminate-and-stay-resident).  One key difference is that BASIC-DOS does not give COM programs all available memory.  BASIC-DOS COM programs can specify a memory size, and non-BASIC-DOS programs only receive a portion of what's available.

Also, when an executable runs, [COMMAND.COM](command/) tries to release most of its own memory if no other session is using it, in which case the `MEM` command will report more memory available for EXEC vs. BASIC operations.

### BASIC Programs

BAT and BAS files are text files containing BASIC-DOS commands and BASIC statements (see [BASIC-DOS Programming](../../lang/)).  The differences between them are:

- BAT files can echo each line as it runs (after [ECHO ON](../device/screen/#echo)); BAS files can't
- BAS files run from the prompt remain loaded when they end, along with their variables, so they can be LIST'ed or RUN again

A BAT or BAS file can run other BAT or BAS files (no CALL command is required) and then continue; each nested BAS file gets its own variables.  See [Batch Files](../../lang/#batch-files) for how BASIC-DOS batch files differ from PC DOS batch files.

### Files Provided with BASIC-DOS

These are the programs provided with BASIC-DOS, each of which has a page of its own.  COMMAND.COM is in the root directory of every BASIC-DOS disk, and the rest are in the **EXT** directory (see [Running Programs](../../intro/#running-programs) for the layout of a BASIC-DOS disk).

- [ATTRIB.BAS](attrib/): displays or changes the attributes of files
- [CHKDSK.BAS](chkdsk/): checks a drive's FAT and directories, and reports its space
- [COMMAND.COM](command/): the BASIC-DOS Command Shell
- [COMP.BAS](comp/): compares files
- [DEBUG.COM](debug/): a debugger, which runs as a program or as a device driver
- [DISKCOPY.BAS](diskcopy/): copies a diskette
- [FIND.COM](find/): a filter that displays the lines containing a string or matching a regular expression
- [FORMAT.BAS](format/): formats a diskette or hard disk volume
- [HELP.COM](help/): displays help for commands and functions
- [HELP.TXT](help/#helptxt): the text that HELP.COM displays
- [HEXDUMP.BAS](hexdump/): displays a file in hexadecimal
- [LABEL.BAS](label/): creates, changes, or deletes a volume label
- [LS.BAS](ls/): lists files and directories like the UNIX `ls` command
- [MODE.BAS](mode/): sets the display, a serial port, or a printer
- [MORE.COM](more/): a filter that displays its input one screen at a time
- [SED.COM](sed/): a filter that edits lines, like a simple version of the UNIX `sed` command
- [SLEEP.COM](sleep/): waits the specified number of seconds
- [SORT.COM](sort/): a filter that sorts lines
- [SYS.BAS](sys/): makes a disk bootable
- [TEE.COM](tee/): a filter that copies its input to a file, too
- [TR.COM](tr/): a filter that replaces or deletes characters
- [TREE.BAS](tree/): displays a directory tree
- [UNIQ.COM](uniq/): a filter that removes repeated lines
- [VI.COM](vi/): a full-screen text editor
- [VOL.BAS](vol/): displays a volume label
- [WC.COM](wc/): a filter that counts lines, words, and bytes

Every BASIC-DOS startup diskette also contains the system files BASDEV.COM (device drivers) and BASDOS.COM (the kernel), which are read-only hidden system files.  These files must not be run.

Utilities that don't need the speed of assembly language are BASIC programs, written in the style BASIC-DOS lists them in: every line indented with a tab, after a line number only where one is needed as a label.  Their switches start with the switch character (`/`, unless [SWITCHAR](../../cfg/#switchar) changes it, eg, to `-`), and when a required argument is missing or an argument isn't valid (eg, an unknown switch), a utility displays `Syntax error` (use [HELP](help/) to see a command's usage).  Like other commands, a utility that fails this way (or in any other way) sets ERRORLEVEL to 1, with [END](../basic/#end).

### Filters

[FIND](find/), [MORE](more/), [SED](sed/), [SORT](sort/), [TEE](tee/), [TR](tr/), [UNIQ](uniq/), and [WC](wc/) are filters.  A filter reads lines of input, which normally come from a pipe (eg, `DIR | SORT`) or a file (eg, `SORT < NAMES.TXT`), and writes the results to its output.  FIND, MORE, SED, SORT, UNIQ, and WC also accept file names instead (FIND and WC accept more than one).  Input ends when the pipe is closed, at the end of the file, or at a CTRL-Z, and a line longer than 254 characters is split.

Switches start with the switch character (`/`, or `-` if [SWITCHAR](../../cfg/#switchar) is `-` or [PATHCHAR](../../cfg/#pathchar) is `/`).  Their letters can be in upper or lower case, and can be combined (eg, `FIND /IN BAS`).  Anything else after the switch character displays `Syntax error`, and sets ERRORLEVEL to 2.

Filters can be chained (eg, `TYPE FILE | SORT | MORE`), but every command after the first needs its own session, so a pipeline can't have more commands than [SESSIONS=](../../cfg/#sessions) allows, and a BAT or BAS file (which runs in the current session) can only be the first command (eg, `LS | MORE`, but not `DIR | TEST.BAS`, which reports `Unable to open TEST.BAS`).  If any command of a pipeline fails (eg, it can't be found, or there's no session for it), the error is displayed, the commands already running are ended, and ERRORLEVEL is set to 1.  And if a command stops reading its input early (eg, FIND can't open its file), the command writing to it gets a write error instead of waiting forever; the filters stop when that happens.

### Regular Expressions

SED's addresses and `s` command, and FIND's `/R` switch, use the regular expressions of the UNIX `ed` and `sed` commands of the 1970s and 1980s:

- an ordinary character matches itself, and `\` before any character makes it ordinary (eg, `\.`, `\*`, `\[`, or `\/` for SED's delimiter)
- `.` matches any character
- `[chars]` matches any one of the *chars*, which can include ranges (eg, `[A-Za-z0-9]`), and `[^chars]` matches any character that *isn't* one of them; a `]` first (eg, `[]x]`) or a `-` first or last is ordinary, and so is `\`
- `*` after a character, `.`, or `[chars]` matches it zero or more times, as many as possible (eg, `[0-9][0-9]*` matches a number)
- `^` at the start matches the start of the line, and `$` at the end matches its end (elsewhere, they're ordinary)
- `\(` and `\)` mark a group (up to 9), which the text of a SED `s` command can refer to

An empty regular expression in SED (eg, `//` or `s//text/`) reuses the previous one.  The newer `+`, `?`, `|`, and `\{m,n\}` aren't supported.

Source: the `UTILRE` section of [utilproc.inc](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/utilproc.inc)

{% include footer.html prev="Disk Commands:../disk/" next="ATTRIB:attrib/" %}
