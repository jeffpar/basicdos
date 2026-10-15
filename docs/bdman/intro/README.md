---
layout: sheet
title: Using BASIC-DOS
permalink: /docs/bdman/intro/
---

{% include header.html %}

### Starting BASIC-DOS

Insert a BASIC-DOS diskette in drive A: of an IBM PC and turn the machine on.  If the machine has a hard disk, BASIC-DOS first displays:

	BASIC-DOS 2.00
	Press a key to start...

Press any key (or wait 5 seconds) to start BASIC-DOS, or press **Esc** to boot from the hard disk instead.  The following messages should then appear on your screen:

	BASIC-DOS 2.00 for the IBM PC
	Copyright (c) PCJS.ORG 1981-2026

	BASIC-DOS Command Processor

	A:\>

Use `MEM` to see memory usage, and `MEM /D` to see every memory block, including the FPU$ driver (if it's loaded; without it, numeric variables default to integers; see [SKIP=](../cfg/#skip)).

The `A:\>` is the BASIC-DOS prompt.  The prompt displays the default drive and its current directory (`\` is the root directory; see [CD](../cmd/disk/#cd)), and indicates that BASIC-DOS is ready to accept [commands](../cmd/) from the keyboard.

Unlike PC DOS, BASIC-DOS doesn't automatically run an AUTOEXEC.BAT file.  Instead, each session's startup command (if any) is specified on a [SHELL=](../cfg/#shell) line in CONFIG.SYS.

### Typing Commands

The BASIC-DOS prompt accepts commands up to 254 characters long.  Any characters typed beyond that limit are ignored.  Press the **Enter** key to submit all characters currently displayed as the next command.

Other special keys include:

- **Backspace** deletes the previous character
- **Esc** erases the entire line
- **Up Arrow** displays the previous line (also: **Ctrl-E**)
- **Down Arrow** displays the next line (also: **Ctrl-X**)
- **Left Arrow** moves the cursor left one character (also: **Ctrl-S**)
- **Right Arrow** moves the cursor right one character (also: **Ctrl-D**)
- **Home** moves the cursor to the beginning of the line (also: **Ctrl-W**)
- **End** moves the cursor to the end of the line (also: **Ctrl-R**)
- **Ctrl-Left Arrow** moves the cursor left one word (also: **Ctrl-A**)
- **Ctrl-Right Arrow** moves the cursor right one word (also: **Ctrl-F**)
- **Del** deletes the current character (also: **Ctrl-G**)
- **Ins** toggles the current Insert/Overwrite mode (also: **Ctrl-V**)
- **Ctrl-End** deletes all characters to the end of the line (also: **Ctrl-K**)

Other special key sequences that can be typed at any time include:

- **Ctrl-C** aborts the current operation, the next time the program uses DOS (eg, for input or output)
- **Ctrl-Break** is currently the same as **Ctrl-Alt-Del**, which stops even a program that doesn't use DOS (eg, an endless loop); on a serial terminal, its **BREAK** key does the same
- **Ctrl-S** pauses output (press any other key to continue)
- **Shift-Tab** switches to the next [session](#sessions)
- **Ctrl-Alt-Del** terminates the program running in the current session (it does *not* restart the machine; use [RESTART SYSTEM](../cmd/system/#restart) for that, or RESTART with a session number to stop another session's program)

You can also use the [KEYS](../cmd/system/#keys) command to display a brief summary of special keys.

A command line can contain more than one command, separated by colons (eg, `CLS:DIR`).  BASIC-DOS commands and BASIC statements can be freely mixed, so the following is a valid command line:

	FOR I = 1 TO 3:PRINT I;:NEXT

A DOS command (eg, DIR, TYPE, or the name of a program) ends at any colon outside quotes (eg, `DIR *.BAS:PRINT "done"`), except a colon that follows a drive letter (eg, `DIR A:`) or separates two digits (eg, `TIME 12:30`).

As in IBM PC BASIC, [LET](../cmd/basic/let/) is optional for assignments, even at the prompt (eg, `A = 1`).

### Entering Programs

A line typed at the prompt that begins with a line number (followed by a space, or nothing at all) isn't a command; it's a line of BASIC that's added to the loaded program, replacing any line with the same number.  Lines are kept in line number order, so they can be typed in any order:

	20 PRINT "WORLD"
	10 PRINT "HELLO"
	LIST
	   10	PRINT "HELLO"
	   20	PRINT "WORLD"
	RUN
	HELLO
	WORLD

Typing a line number by itself deletes that line.  Line numbers range from 1 to 65529.  Since a line number must be followed by a space, programs whose names begin with digits (eg, `4DOS`) can still be run by name.

The [AUTO](../cmd/system/#auto), [DELETE](../cmd/system/#delete), [EDIT](../cmd/system/#edit), and [LIST](../cmd/system/#list) commands also work with program lines, [NEW](../cmd/system/#new) erases the program, and [SAVE](../cmd/disk/#save) saves it to a file.

### Running Programs

To run a program, type its name, optionally followed by any arguments the program accepts.  If you don't specify an extension, BASIC-DOS looks for a file with the extension COM, EXE, BAT, or BAS, in that order.

- **COM** and **EXE** files are binary programs, as in PC DOS
- **BAT** and **BAS** files are BASIC programs (see [BASIC-DOS Programming](../lang/))

For example, if a disk contains both DONKEY.COM and DONKEY.BAS, typing `DONKEY` runs DONKEY.COM, and typing `DONKEY.BAS` runs DONKEY.BAS.

If the program isn't in the current directory, and its name doesn't include a drive or directory, BASIC-DOS searches the directories listed in [PATH$](../cmd/basic/func/#path), in order.  Every bootable BASIC-DOS disk has the same layout:

- The root directory contains BASDEV.COM, BASDOS.COM, COMMAND.COM, CONFIG.SYS, AUTOEXEC.BAT (if any), and HELP.TXT
- **BIN** contains the BASIC-DOS utilities (eg, [FIND, MORE, and SORT](../cmd/external/#filters)) and DEBUG.COM
- **SAMPLES** contains the PC DOS BASIC samples (eg, DONKEY.BAS)
- **DEMOS** contains the programs that the demos run (eg, HELLO.BAT, FIBO.BAT, and PRIMES.BAS)

and its CONFIG.SYS sets PATH$ to the root, BIN, SAMPLES, and DEMOS (eg, `A:\;A:\BIN;A:\SAMPLES;A:\DEMOS`), so you can type `PRIMES` or `DIR | SORT` from any directory.

Test programs (eg, DOSTESTS.COM), along with MSBASIC.EXE and SYMDEB.EXE, are on a separate diskette, BASICDOS-360K-TESTS, in its **TESTS** directory; load it in drive B: and type (for example) `B:\TESTS\MSBASIC`.

The [hard disk demo](/demos/hd/at/) adds three more directories: **TESTS** (the same test programs as BASICDOS-360K-TESTS), **SRC** (the BASIC-DOS source code), and **TOOLS** (MASM and the other build tools).

Use `LIST VARS` to inspect the current session's variable values and array dimensions; see [LIST](../cmd/system/#list).

When a BAS program that you ran from the prompt ends, it remains loaded, along with its variables, so you can [LIST](../cmd/system/#list) it, examine its variables (eg, `PRINT A`), or [RUN](../cmd/system/#run) it again.  RUN reuses the program's compiled code, so the program starts immediately, unless the program or its variables have changed since it was compiled.

If a name matches a BASIC keyword that can't be used by itself (eg, `CIRCLE`), BASIC-DOS runs the program with that name instead (eg, CIRCLE.BAS).

To stop a program, press **Ctrl-C**.  If the program doesn't respond (eg, it's in a loop that doesn't do any input or output), press **Ctrl-Break** or **Ctrl-Alt-Del**.

### Pipes and Redirection

The output of a command can be sent to a file instead of the screen:

- `DIR > FILES.TXT` creates (or truncates) FILES.TXT and writes the output to it
- `DIR >> FILES.TXT` appends the output to FILES.TXT

Since `>` is also BASIC's "greater than" operator, BASIC statements use `:>` (or `:>>`) at the end of a line instead, which redirects the output of every statement on the line (eg, `PRINT "hello world" :> TEST` or `FOR I=1 TO 3:PRINT I:NEXT :>> TEST`).  `:>` works with any command, at the prompt and in BAT and BAS files, and its file name can be a string variable (eg, `PRINT X :> F$`), but it must come last on the line; for DOS commands, put a space before it (eg, `DIR :> FILES.TXT`), since `A:>FILE` still means drive A:.

The output of one command can also be sent to the input of another command, using a pipe (`|`):

	DIR | CASE

Each command after the first runs in its own background session, so all commands in a pipeline run at the same time.  The output of a pipeline can also be redirected (eg, `DIR | CASE > TEST`).  BASIC-DOS includes several filters for use with pipes: CASE, FIND, MORE, and SORT (see [Filters](../cmd/external/#filters)).

Input redirection (`<`) isn't supported yet.

### Sessions

BASIC-DOS can run several programs at once, each in its own *session*.  A session has its own console, which can occupy the entire screen or just part of it (eg, the left and right halves of the screen, as in the [BASIC-DOS Demos](/demos/)); the console with a double-line border is the one that has *focus*, which means that it receives keyboard input.

Press **Shift-Tab** to switch the focus to the next session.

The number of sessions and the size and position of their consoles are defined in CONFIG.SYS (see [CONSOLE=](../cfg/#console) and [SESSIONS=](../cfg/#sessions)).

### Getting Help

The [HELP](../cmd/system/#help) command lists all commands, and `HELP` followed by the name of a command or function (eg, `HELP MID$`) displays a brief description of it.

{% include footer.html prev="Contents:../" next="BASIC-DOS Commands:../cmd/" %}
