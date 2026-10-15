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

In the root directory:

- [COMMAND.COM](command/): the BASIC-DOS Command Shell
- HELP.TXT: the text displayed by the [HELP](../system/#help) command

In the **BIN** directory (see [Running Programs](../../intro/#running-programs) for the layout of a BASIC-DOS disk):

- CASE.COM, FIND.COM, MORE.COM, and SORT.COM: filters (see below)
- SLEEP.COM: waits the specified number of seconds (eg, `SLEEP 5`); CTRL-C stops it early
- VI.COM: a full-screen text editor (see [VI](#vi) below)

### Filters

A filter reads lines of input, which normally come from a pipe (eg, `DIR | SORT`), and writes the results to its output.  FIND, MORE, and SORT also accept file names instead (since input redirection isn't supported yet).  Input ends when the pipe is closed, at the end of the file, or at a CTRL-Z.  Switches start with SWITCHAR (`/` by default).

#### CASE

	CASE

Copies input to output, converting lower-case letters to upper-case (eg, `DIR | CASE`).

#### FIND

	FIND [/C] [/I] [/N] [/V] "string" [file...]

Displays the lines of input (or of each *file*) that contain *string* (eg, `DIR | FIND "BAS"`).  When files are specified, the lines from each file follow a line containing its name.

- `/C` displays only the number of lines
- `/I` ignores case
- `/N` puts each line's number in front of it (eg, `[3]`)
- `/V` displays the lines that do *not* contain *string*

ERRORLEVEL is set to 0 if any lines were displayed (or counted), 1 if none, and 2 if a file couldn't be opened.

#### MORE

	MORE [file]

Displays input (or *file*) one screen at a time (eg, `TYPE README.TXT | MORE`).  After each screen, it displays `-- More --` and waits for a key (read from STDERR, since STDIN is the pipe); press CTRL-C to stop.

#### SORT

	SORT [/R] [/+n] [file]

Displays the lines of input (or *file*) in sorted order, ignoring case (eg, `DIR | SORT`).  `/R` sorts in reverse order, and `/+n` sorts on the characters starting at column *n* (eg, `DIR | SORT /+10` sorts a directory listing by extension).  Up to 64K of text can be sorted.

Filters can be chained (eg, `TYPE FILE | SORT | MORE`), but every command after the first needs its own session, so a pipeline can't have more commands than [SESSIONS=](../../cfg/#sessions) allows.  If any command of a pipeline fails (eg, it can't be found, or there's no session for it), the error is displayed, the commands already running are ended, and ERRORLEVEL is set to 1.  And if a command stops reading its input early (eg, FIND can't open its file), the command writing to it gets a write error instead of waiting forever; the filters stop when that happens.

### VI

	VI [file]

A full-screen text editor with a subset of the commands of the UNIX *vi* editor.  It works on the CON console and on serial consoles with ANSI or VT100 terminals (but not GENERIC terminals), and it can edit files of up to 64K, using only as much memory as the file needs.  Files are saved with CR/LF at the end of every line.

VI starts in command mode, where keys are commands; most commands can be preceded by a count (eg, `3dd` deletes 3 lines).  The cursor keys, Home, End, PgUp, PgDn, Insert, and Delete work as you'd expect, in insert mode too.  The last row of the screen displays messages and the commands that start with `:`, `/`, and `?`.

| Commands | Description |
|----------|-------------|
| `h` `j` `k` `l` | Move left, down, up, or right (also BACKSPACE and SPACE) |
| `w` `b` `e` | Move to the next word, the previous word, or the end of the word (`W`, `B`, and `E` use words separated only by blanks) |
| `0` `^` `$` | Move to the start of the line, its first non-blank, or its end |
| `+` `-` | Move to the first non-blank of the next (also ENTER) or previous line |
| `G` `gg` | Move to the last line (or line *n*, eg, `10G`), or the first line |
| `H` `M` `L` | Move to the top, middle, or bottom line of the screen |
| `f`*c* `F`*c* `t`*c* `T`*c* | Move to the next (or previous) *c* on the line, or just before it; `;` repeats, and `,` repeats in the other direction |
| `%` | Move to the bracket matching the next `(`, `)`, `[`, `]`, `{`, or `}` on the line |
| `/`*text* `?`*text* | Search forward (or backward) for *text*, wrapping around the file; `n` repeats, and `N` repeats in the other direction |
| CTRL-F CTRL-B | Scroll forward or backward a screen |
| CTRL-D CTRL-U | Scroll down or up half a screen |
| CTRL-E CTRL-Y | Scroll down or up a line |
| `i` `a` `I` `A` | Insert before the cursor, after it, before the first non-blank, or at the end of the line |
| `o` `O` | Open a new line below (or above) the current line, and insert |
| `d`*motion* `c`*motion* `y`*motion* | Delete, change, or yank (copy) the text from the cursor to where *motion* would move; `dd`, `cc`, and `yy` use whole lines |
| `x` `X` `D` `C` `s` `S` `Y` | Same as `dl`, `dh`, `d$`, `c$`, `cl`, `cc`, and `yy` |
| `p` `P` | Put the deleted or yanked text after (or before) the cursor, or for whole lines, below (or above) the current line |
| `r`*c* | Replace the character under the cursor with *c* |
| `~` | Toggle the case of the character under the cursor |
| `J` | Join the next line to the current line |
| `u` | Undo the last change (and `u` again redoes it) |
| CTRL-G | Display the file name, whether it's modified, and the current line number |
| CTRL-L | Redraw the screen |
| `ZZ` | Save the file (if modified) and exit |

In insert mode, typed characters are inserted, ENTER starts a new line, BACKSPACE erases what was just typed, and ESC (or CTRL-C) returns to command mode.

| Command | Description |
|---------|-------------|
| `:w` [*file*] | Write the file (or another file) |
| `:wq` [*file*] or `:x` | Write the file (`:x` only if it's modified) and exit |
| `:q` | Exit, unless the file has been modified; `:q!` exits anyway |
| `:`*n* or `:$` | Move to line *n*, or the last line |
| `:s/`*old*`/`*new*`/` | Replace the first *old* on the current line with *new* (add `g` at the end to replace every *old* on the line, and use `:%s` for every line); the text is matched exactly |

Every BASIC-DOS startup diskette also contains the system files BASDEV.COM (device drivers) and BASDOS.COM (the kernel).  These files must not be run.

{% include footer.html prev="Disk Commands:../disk/" next="COMMAND.COM:command/" %}
