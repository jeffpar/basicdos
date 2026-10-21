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

COM and EXE files are loaded and run as in PC DOS, and many programs written for PC DOS 1.x and 2.x work, as long as they don't rely on features that BASIC-DOS doesn't support yet (eg, subdirectories).  One difference is that BASIC-DOS gives a COM program half of the available memory (or a BASIC-DOS COM program only the memory it needs), rather than all available memory, so that other sessions can use the rest.

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

- FIND.COM, MORE.COM, SORT.COM, TEE.COM, TR.COM, and WC.COM: filters (see below)
- SLEEP.COM: waits the specified number of seconds (eg, `SLEEP 5`); CTRL-C stops it early
- VI.COM: a full-screen text editor (see [VI](#vi) below)
- FORMAT.BAS: formats a diskette (see [FORMAT](#format) below)
- MODE.BAS: sets the display, a serial port, or a printer (see [MODE](#mode) below)

Utilities that don't need the speed of assembly language are BASIC programs, written in the style BASIC-DOS lists them in: every line indented with a tab, after a line number only where one is needed as a label.

### Filters

A filter reads lines of input, which normally come from a pipe (eg, `DIR | SORT`), and writes the results to its output.  FIND, MORE, SORT, and WC also accept file names instead (since input redirection isn't supported yet).  Input ends when the pipe is closed, at the end of the file, or at a CTRL-Z.  Switches start with the switch character (`/`, or `-` if [SWITCHAR](../../cfg/#switchar) is `-` or [PATHCHAR](../../cfg/#pathchar) is `/`).

#### FIND

	FIND [/C] [/I] [/N] [/V] "string" [file...]

Displays the lines of input (or of each *file*, or with wildcards (`?` and `*`), every matching file) that contain *string* (eg, `DIR | FIND "BAS"`).  When files are specified, the lines from each file follow a line containing its name.

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

#### TEE

	TEE [/A] file

Copies input to its output and to *file* (eg, `DIR | TEE DIR.TXT | MORE`).  *file* is replaced, or with `/A`, appended to (and created if it doesn't exist).  ERRORLEVEL is set to 0, or 2 if *file* couldn't be opened or written.

#### TR

	TR [/C] [/D] [/S] set1 [set2]

Copies input to output, replacing each character in *set1* with the matching character in *set2*; if *set2* is shorter, its last character repeats.  /D deletes the characters in *set1* instead, /C uses every character *not* in *set1* (in ascending order), and /S squeezes each run of a character in the last set given into a single character.  A set can contain ranges (eg, `a-z`) and the escapes `\t` (TAB), `\n` (LF), `\r` (CR), and `\` before any other character for that character (eg, `\-` or `\\`); a set that contains spaces must be quoted.  ERRORLEVEL is set to 0, or 2 if a set is missing (or only *set1* is given, without /D or /S).

	DIR | TR a-z A-Z
	TYPE README.TXT | TR /D \r
	DIR | TR /S " "

#### WC

	WC [/L] [/W] [/C] [file...]

Displays the number of lines, words, and bytes of input (or of each *file*, or with wildcards (`?` and `*`), every matching file, followed by their totals if there's more than one), along with each file's name (eg, `DIR | WC /L` or `WC *.BAS`).  `/L`, `/W`, and `/C` display only the line, word, or byte counts, respectively (without any of them, all three are displayed).  Lines are counted by their line feeds, and words are separated by spaces and control characters (eg, tabs and line breaks).  ERRORLEVEL is set to 0, or 2 if a file couldn't be opened.

Filters can be chained (eg, `TYPE FILE | SORT | MORE`), but every command after the first needs its own session, so a pipeline can't have more commands than [SESSIONS=](../../cfg/#sessions) allows.  If any command of a pipeline fails (eg, it can't be found, or there's no session for it), the error is displayed, the commands already running are ended, and ERRORLEVEL is set to 1.  And if a command stops reading its input early (eg, FIND can't open its file), the command writing to it gets a write error instead of waiting forever; the filters stop when that happens.

### FORMAT

	FORMAT d: [/S] [/1] [/8]

Formats the diskette in drive *d* (A: or B:) as a 360K diskette (40 cylinders, 2 sides, 9 sectors per track), or with `/1` as a single-sided diskette (180K), or with `/8` with 8 sectors per track (320K, or 160K with `/1`, for PC DOS 1.x).  `/S` then copies BASDEV.COM, BASDOS.COM, and COMMAND.COM from the root directory of the current drive, making the diskette bootable.  FORMAT prompts for the diskette, formats and verifies every track (with the diskette driver's [IOCTL](../basic/#ioctl) requests), writes the boot sector (a copy of the current drive's, with the new diskette's parameters), the two FATs, and the root directory, reports the space on the diskette, and asks whether to format another.  Cluster sizes and root directory sizes follow the PC DOS 2.x rules (eg, 1K clusters and 112 root entries for a 360K diskette), with 12-bit FATs.

A write-protected diskette, an empty drive, or a track that can't be formatted ("Track *n* bad - disk unusable") ends the format.  FORMAT can't format the current drive (which also supplies the boot sector and system files).

For a hard disk drive, FORMAT first displays the disk's geometry and partition table (each partition's type, starting sector, size, and drive letter, if it's a FAT volume).  If the disk has FAT volumes, FORMAT formats the drive named on the command line (or if that drive is the whole disk, asks which volume to format), after a warning that all data on the drive will be lost.  If the disk has no partition table (eg, a new hard disk, which BASIC-DOS gives a drive letter anyway, with "unknown media"), FORMAT offers to create one, with a single volume (starting at the second track and ending at a cylinder boundary) of the size you choose in Mb, up to 32Mb (65535 sectors) or the size of the disk; it then writes a master boot record (with the hard disk driver's boot code) and formats the new volume.  A volume of up to 32680 sectors (about 16Mb) gets the PC DOS 2.x layout for its size (eg, 4K clusters and 512 root entries for 10Mb) with a 12-bit FAT; a larger volume gets 2K clusters and a 16-bit FAT, as PC DOS 3.x did.  Hard disk volumes aren't verified, and extended partitions aren't supported.

### MODE

	MODE 40|80|BW40|BW80|CO40|CO80
	MODE COMn:baud[,parity[,data[,stop]]]
	MODE LPTn:[cols][,lines]

Sets the display to 40 or 80 columns (BW turns color off, as `SCREEN 0,0` does, and CO turns it on), sets a serial port's baud rate (two digits abbreviate a rate, eg, 96 for 9600), parity (N, O, or E; the default is N), data bits (default 8), and stop bits (default 1), or sends an IBM/Epson printer its condensed (132 columns) or normal (80 columns) print codes and its 8 or 6 lines per inch codes.  A serial port is set by opening it with its parameters and an input buffer length of 0 (see [COM](../../cfg/#console)), which initializes the port and releases it again, so a port that's already open (eg, the console) isn't changed.

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
