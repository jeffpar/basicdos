---
layout: sheet
title: Using BASIC-DOS
permalink: /docs/bdman/intro/
---

{% include header.html %}

### Starting BASIC-DOS

Insert a BASIC-DOS diskette in drive A: of an IBM PC and turn the machine on.  BASIC-DOS first displays:

	BASIC-DOS 2.00
	Diskette loading...

(A hard disk displays `Hard disk loading...` instead.)  Press any key (or wait 2 seconds) to start BASIC-DOS.  If you booted a diskette on a machine with a hard disk, pressing **Esc** boots from the hard disk instead.  Pressing `-` also makes `-` the switch character (see [SWITCHAR=](../cfg/#switchar)), and on an 80286 or later, pressing `P` selects protected mode and pressing `R` selects real mode (see [CPU=](../cfg/#cpu)).  On a PC or PC XT running in PCjs, which supplies the host's date and time, pressing a letter (eg, `P` or `R`) makes BASIC-DOS prompt for them instead (see [COMMAND](../cmd/external/command/#startup-commands)).  To remove the message from a disk, see [SYS /N](../cmd/external/sys/).  The following messages should then appear on your screen:

	BASIC-DOS 2.00
	Copyright (c) PCJS.ORG 1981-2026

	BASIC-DOS Command Shell

	<A:\>

Use `MEM` to see memory usage.  If the FPU$ driver isn't loaded, numeric variables default to integers (see [SKIP=](../cfg/#skip)).

The `<A:\>` is the BASIC-DOS prompt.  The prompt displays the default drive and its current directory (`\` is the root directory; see [CD](../cmd/disk/#cd)), and indicates that BASIC-DOS is ready to accept [commands](../cmd/) from the keyboard.  Its brackets show the processor's mode: `<` and `>` in real mode, `[` and `]` in protected mode (see [CPU=](../cfg/#cpu)), and `(` and `)` in a [V86](../cmd/external/v86/) machine.  [PROMPT$](../cmd/basic/func/#prompt) can change the prompt (eg, `PROMPT$ = "%H:%02N %l%s%g"` adds the time).

Unlike PC DOS, BASIC-DOS doesn't automatically run an AUTOEXEC.BAT file.  Instead, each session's startup command (if any) is specified on a [SHELL=](../cfg/#shell) line in CONFIG.SYS.

### Typing Commands

The BASIC-DOS prompt accepts commands up to 254 characters long.  Any characters typed beyond that limit are ignored.  Press the **Enter** key to submit all characters currently displayed as the next command.

Other special keys include:

- **Backspace** deletes the previous character
- **Esc** erases the entire line
- **Up Arrow** displays the previous command (also: **Ctrl-E**)
- **Down Arrow** displays the next command (also: **Ctrl-X**)
- **Left Arrow** moves the cursor left one character (also: **Ctrl-S**)
- **Right Arrow** moves the cursor right one character (also: **Ctrl-D**)
- **Home** moves the cursor to the beginning of the line (also: **Ctrl-W**)
- **End** moves the cursor to the end of the line (also: **Ctrl-R**)
- **Ctrl-Left Arrow** moves the cursor left one word (also: **Ctrl-A**)
- **Ctrl-Right Arrow** moves the cursor right one word (also: **Ctrl-F**)
- **Del** deletes the current character (also: **Ctrl-G**)
- **Ins** toggles the current Insert/Overwrite mode (also: **Ctrl-V**)
- **Ctrl-End** deletes all characters to the end of the line (also: **Ctrl-K**)

Each session keeps a history of the latest commands typed at its prompt, as many as fit in 1K.  **Up Arrow** and **Down Arrow** step through older and newer commands, and **Down Arrow** past the newest returns to what you were typing.  If you typed some characters first, they display only the commands that begin with those characters (eg, type `DIR` and press **Up Arrow** for the latest DIR command).  Commands that are empty or the same as the latest one aren't added, and [HISTORY$](../cmd/basic/func/#history) returns any command in the history.  Lines in BAT and BAS files aren't added, and on low memory systems (see [Low Memory](../lang/#low-memory)), there's no history, so **Up Arrow** displays only the last line typed.

Other special key sequences that can be typed at any time include:

- **Ctrl-C** aborts the current operation, the next time the program uses DOS (eg, for input or output)
- **Ctrl-Break** is currently the same as **Ctrl-Alt-Del**, which stops even a program that doesn't use DOS (eg, an endless loop); on a serial terminal, its **BREAK** key does the same
- **Ctrl-S** pauses output (press any other key to continue)
- **Shift-Tab** switches to the next [console](#sessions) (**Ctrl-\\** on a serial terminal, or the key that a [HOTKEY=](../cfg/#hotkey) line sets)
- **Ctrl-Alt-Del** terminates the program running in the current session (it does *not* restart the machine; use [KILL /A](../cmd/system/#kill) for that, or KILL with a session number to end another session)

You can also type [HELP KEYS](../cmd/external/help/) to display a brief summary of special keys.

A command line can contain more than one command, separated by colons (eg, `CLS:DIR`).  BASIC-DOS commands and BASIC statements can be freely mixed, so the following is a valid command line:

	FOR I = 1 TO 3:PRINT I;:NEXT

A DOS command (eg, DIR, TYPE, or the name of a program) ends at any colon outside quotes (eg, `DIR *.BAS:PRINT "done"`), except a colon that follows a drive letter (eg, `DIR A:`) or a switch's letters (eg, `FORMAT A: /F:720`), or separates two digits (eg, `TIME 12:30`).

As in IBM PC BASIC, [LET](../cmd/basic/let/) is optional for assignments, even at the prompt (eg, `A = 1`).

### Playing BROGUE

On an 80-column PC display or VT100 console, run `CD \DEMOS` followed by `BROGUE`. Each depth is a few rooms joined by hallways, which are drawn as two walls with nothing between them. You (`u`) start on the stairs up (`<`) in the first room, and the stairs down (`>`) are in the last. Walk onto `>` to descend.

Move with the arrow keys (and Home, PgUp, End, and PgDn for the diagonals) or lowercase `h`, `j`, `k`, `l` (and `y`, `u`, `b`, `n` for the diagonals). The rooms are full of stones (`O`): push one by walking into it, and it rolls until something stops it. Bricks (shaded squares, or a checkerboard on a VT100) never move.

The top row shows the depth and the map's seed. Press `R` to start the depth over (the same map), `N` for a new map at the same depth, or `Q` to quit. To play a map again later, run BROGUE with its seed, followed by its depth if it isn't 1 (eg, `BROGUE 36AF971E 4`).

To play with others, run `BROGUE /M` in two or more sessions (eg, consoles that [START](../cmd/system/#start) opens). The first one makes the map, and each one that starts later plays the same map as it is then (with the stones where they are), starting on a random cell of the first room; a player who takes the stairs (or presses `R`) on a map that another player is already on gets that map as it is, too. Your player is always `u`, and the other players are shown by their session numbers (`1`-`9`, then `A`-`W`), wherever they are on the same map; a player who presses `N` (or quits) disappears from the others' maps. Players who take the stairs down meet again on the next map, since the stairs choose the next map from the current one. A stone that one player pushes rolls on every player's map, and if it rolls into another player, that player is squashed.

### Playing DALEKS

On an 80-column PC display or VT100 console, run `CD \DEMOS` followed by `DALEKS`. Each level is one large room, with a door on one side, where you (`u`) come in, and a door on the opposite side, which is the way out. Every time you move, each Dalek (`D`) moves one cell toward you, and if one reaches you, you're exterminated. Daleks that move into the same cell, or onto a heap of scrap (`#`), become scrap themselves. Reach the way out to go on to the next level, which has more Daleks.

Move with the same keys as BROGUE; `.` waits a turn, `T` teleports you to a random place in the room (which may be next to a Dalek), and `Z` uses a sonic screwdriver, which destroys every Dalek next to you. You get one screwdriver at each level, and keep the ones you don't use. The top row shows the level, and the bottom row shows the keys and how many screwdrivers you have. Press `R` to start the level over (the same room), or `Q` to quit; after you're exterminated, `N` starts a new game at level 1.

### Playing ATAXX

On any PC display or VT100 console with 40 or more columns, run `CD \DEMOS` followed by `ATAXX`. The board has 7 rows of 7 cells, centered on the screen, with the score above it and messages below it. You (solid pieces) and the computer (hollow pieces, drawn with double lines on a PC) start with two pieces each, in opposite corners, and take turns moving. A move is to an empty cell: a cell next to one of your pieces (in any of the 8 directions) grows a new piece there, and a cell 2 away jumps the piece there instead, leaving its old cell empty. Either way, every one of the other player's pieces next to that cell becomes yours. When the player whose turn it is can't move, the game ends, the other player gets every empty cell, and whoever has more pieces wins.

Move the cursor (a highlighted cell) with the same keys as BROGUE. `Space` (or `Enter`) on an empty cell next to one of your pieces grows a piece there. On one of your pieces, it picks that piece, which blinks, and marks the empty cells it can grow into (with a dot) and jump to (with 4 dots); `Space` on one of those moves it there, and `Space` on the piece again, or `Esc`, puts it back.

The computer looks a number of moves ahead (its level, shown on the top row): press `1`-`4` to change it, or run ATAXX with a level (eg, `ATAXX 3`); it's 2 otherwise. On a 4.77 MHz PC, level 2 takes a few seconds a move, and level 3 can take a minute or more; level 4 is for faster machines. Press `N` for a new game (the players take turns moving first), or `Q` to quit.

### Entering Programs

A line typed at the prompt that begins with a line number (followed by a space, or nothing at all) isn't a command; it's a line of BASIC that's added to the loaded program, replacing any line with the same number.  Lines are kept in line number order, so they can be typed in any order:

	20 PRINT "WORLD"
	10 PRINT "HELLO"
	LIST
	10 PRINT "HELLO"
	20 PRINT "WORLD"
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

- The root directory contains BASDEV.COM, BASDOS.COM, COMMAND.COM, CONFIG.SYS, and AUTOEXEC.BAT (if any); BASDEV.COM and BASDOS.COM are read-only hidden system files (so only `DIR /A` lists them), and COMMAND.COM is a read-only system file (see [ATTRIB](../cmd/external/attrib/))
- **EXT** contains the external BASIC-DOS utilities, in two directories: **EXT\\CMD** has the assembly language programs (eg, [FIND, MORE, and SORT](../cmd/external/#filters), [VI](../cmd/external/vi/), [DEBUG.COM](../cmd/external/debug/), and [HELP](../cmd/external/help/)), and **EXT\\BAS** has the utilities written in BASIC (eg, [FORMAT](../cmd/external/format/), [LS](../cmd/external/ls/), and [MODE](../cmd/external/mode/)); see [Files Provided with BASIC-DOS](../cmd/external/#files-provided-with-basic-dos) for the complete list)
- **DEMOS** contains demo programs (eg, HELLO.BAT, a colorful greeting, PRIMES.BAS, and DIR.BAS, a DIR written in BASIC, using [DIR$](../cmd/basic/func/#dir)), along with DONKEY.BAS, from the PC DOS 1.00 diskette

and its CONFIG.SYS sets PATH$ to the root, both EXT directories, and DEMOS (eg, `A:\;A:\EXT\CMD;A:\EXT\BAS;A:\DEMOS`), so you can type `PRIMES` or `DIR | SORT` from any directory.

Test programs are on a separate diskette, BASIC-DOS Tests: the regression tests are in its **TESTS\REGRESS** directory (eg, DOSTESTS.COM; REGRESS.BAT in **TESTS** runs them all), other test programs (eg, GFXTESTS.BAS) are in **TESTS\MISC**, and BENCH.BAS is in **TESTS**, with MSBASIC.EXE and SYMDEB.EXE in its **TOOLS** directory (the 20Mb hard disk has all of those, too, plus the rest of the PC DOS 1.00 BASIC samples in **TESTS\SAMPLES**); load it in drive B: and type (for example) `B:\TOOLS\MSBASIC`, or `B:`, `CD \TESTS`, and `REGRESS`.  Most of the tests can run while other sessions are busy, but HARDERR skips its tests if any other session is running a program (its disk hook would affect them).

The [hard disk demo](/machines/demos/bd/hd/at/) adds three more directories: **TESTS** (the same tests as the BASIC-DOS Tests diskette), **SRC** (the BASIC-DOS source code), and **TOOLS** (MASM and the other build tools, plus MSBASIC.EXE and SYMDEB.EXE, in **TOOLS\BIN**).  **MASM.EXE**, **MASM5.EXE**, **MAKE.EXE**, **LINK.EXE**, **LINK4.EXE**, **EXEMOD.EXE**, **MAPSYM.EXE**, and **EXE2BIN.EXE** in **TOOLS\BIN** are protected-mode versions of those programs: they run at ring 3, and in real mode, too.  Except for EXE2BIN, which has no banner, their banners end in **BD** (eg, **4.00BD**).  The other tools in **TOOLS\BIN** remain real-mode programs.

Use `LIST VARS` to inspect the current session's variable values and array dimensions; see [LIST](../cmd/system/#list).

When a BAS program that you ran from the prompt ends, it remains loaded, along with its variables, so you can [LIST](../cmd/system/#list) it, examine its variables (eg, `PRINT A`), or [RUN](../cmd/system/#run) it again.  RUN reuses the program's compiled code (if the whole program was compiled), unless the program or its variables have changed since it was compiled.

If a name matches a BASIC keyword that can't be used by itself (eg, `CIRCLE`, or `RANDOM`, which belongs to OPEN), BASIC-DOS runs the program with that name instead (eg, CIRCLE.BAS or RANDOM.BAT).

To stop a program, press **Ctrl-C**.  If the program doesn't respond (eg, it's in a loop that doesn't do any input or output), press **Ctrl-Break** or **Ctrl-Alt-Del**.

### Redirection and Pipes

The output of a command can be sent to a file instead of the screen:

- `DIR > FILES.TXT` creates (or truncates) FILES.TXT and writes the output to it
- `DIR >> FILES.TXT` appends the output to FILES.TXT

As with other file names, a redirection file name can be quoted or a string variable (eg, `DIR > F$`; see [Command Arguments](../lang/#command-arguments)).

Since `>` is also BASIC's "greater than" operator, BASIC statements use `:>` (or `:>>`) at the end of a line instead, which redirects the output of every statement on the line (eg, `PRINT "hello world" :> TEST` or `FOR I=1 TO 3:PRINT I:NEXT :>> TEST`).  `:>` works with any command, at the prompt and in BAT and BAS files, and its file name can be a string variable (eg, `PRINT X :> F$`), but it must come last on the line; for DOS commands, put a space before it (eg, `DIR :> FILES.TXT`), since `A:>FILE` still means drive A:.

A redirection file name can also be `@` and a session number (a number that [START](../cmd/system/#start) lists), for that session's console, which is how one session displays a message on another (eg, `TYPE NOTE.TXT > @2`); on a machine with 64K of memory, which has only one console, it's an ordinary file name.  Since an `@` can't begin any part of a BASIC expression, a `>` followed by `@` is always a redirection, so BASIC statements don't need the colon there (eg, `PRINT "Lunch is ready" > @2`, the same as `:> @2`); see [Sessions](#sessions).

The output of one command can also be sent to the input of another command, using a pipe (`|`):

	DIR | TR a-z A-Z

Each command after the first runs in its own background session, so all commands in a pipeline run at the same time.  The first command can also be a BAT or BAS file (eg, `LS | SORT`), which, like a built-in command, runs once the other commands have started.  However, a BAT or BAS file can't come after a `|`, since it would have to run in the same session as the first command (eg, `DIR | TEST.BAS` reports `Unable to open TEST.BAS`, and nothing runs).  A built-in command can't come after a `|` either, since it doesn't read its input (eg, `VER | DIR` reports `Syntax error`, and nothing runs).  On a machine with 64K of memory, there's only one session for pipelines, so a line can have only one `|`, and the command after it must fit in the memory that's left (eg, MORE, SORT, TR, UNIQ, and WC do, but FIND and SED don't; see [Memory Usage](../cmd/external/command/#memory-usage)).  The output of a pipeline can also be redirected (eg, `DIR | SORT > TEST`).  BASIC-DOS includes several filters for use with pipes: FIND, MORE, SORT, TEE, TR, and WC (see [Filters](../cmd/external/#filters)).

At the prompt, a line of BASIC statements can end with a pipe, too, which sends the output of every statement on the line to the commands after the `|` (eg, `FOR I=1 TO 100:PRINT 3.14^I:NEXT | MORE`).  The pipe must come after the line's last statement (a `|` inside quotes doesn't count), and the statements run once the other commands have started.  This isn't available in BAT and BAS files, or on low memory systems.

The input of a command can also come from a file instead of the keyboard (eg, `SORT < NAMES.TXT`).  Input redirection applies to the first command on the line, so `<` must come after all of that command's arguments and before any `|` or `>` (eg, `SORT /R < NAMES.TXT > SORTED.TXT` or `SORT < NAMES.TXT | MORE`).  The input filename must be followed by the end of the line, a pipe, or output redirection.

### Sessions

BASIC-DOS can run several programs at once, each in its own *session*.  A session can have a *console*, which can occupy the entire screen or just part of it (eg, the left and right halves of the screen, as in the [BASIC-DOS Demos](/machines/demos/)); the console with a double-line border is the one that has *focus*, which means that it receives keyboard input.

Every console needs a session, and so does every command after the first in a [pipeline](#redirection-and-pipes), so a system usually has more sessions than consoles; the extra sessions determine how many filters can run at once.

Press **Shift-Tab** to switch the focus to the next console (on a serial terminal with more than one console, press **Ctrl-\\**; a [HOTKEY=](../cfg/#hotkey) line in CONFIG.SYS sets one key for both).  When there's more than one console on the video adapters, COMMAND.COM says so when it starts on the console with the focus, after its `BASIC-DOS Command Shell` message: `Press Shift-Tab to switch sessions` (or, with a HOTKEY= line, that key, eg, `Press Ctrl-T to switch sessions`).

To display a message on another session's console, send output to `@` and that session's number, which [START](../cmd/system/#start) lists (eg, `PRINT "Back in 5 minutes" > @2`).  `@`*n* works wherever an output file name does (eg, `COPY NOTE.TXT @2`, or `OPEN "@2" FOR OUTPUT AS #1` and then `PRINT #1`), but it's for output only, so another session's keyboard input can't be read (eg, `TYPE @2` reports `Unable to open @2`), and it's the session's console even when that console doesn't have the focus.  The output appears at that console's cursor, as the output of a program running there would, so if the console is at its prompt, the prompt isn't displayed again until its next command (eg, press ENTER).  A number that isn't an active session is reported as `Unable to find @9` (for example), and `@` followed by anything else (eg, `@X`) is an ordinary file name.

CONFIG.SYS defines the number and size of the consoles (see [CON=](../cfg/#con)) and the number of sessions (see [SESSIONS=](../cfg/#sessions)).

### Getting Help

The [HELP](../cmd/external/help/) command lists all commands, and `HELP` followed by the name of a command or function (eg, `HELP MID$`) displays a brief description of it.

{% include footer.html prev="Contents:../" next="BASIC-DOS Commands:../cmd/" %}
