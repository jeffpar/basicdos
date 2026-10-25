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

Many COM and EXE programs written for PC DOS 1.x and 2.x will work, as long as they don't rely on features that BASIC-DOS doesn't support (eg, TSR functions that allow a program to terminate-and-stay-resident).  One key difference is that BASIC-DOS does not give COM programs all available memory.  BASIC-DOS COM programs can specify a memory size, and non-BASIC-DOS programs only receive a portion of what's available.

Also, when an executable runs, [COMMAND.COM](command/) tries to release most of its own memory if no other session is using it, in which case the `MEM` command will report more memory available for EXEC vs. BASIC operations.

### BASIC Programs

BAT and BAS files are text files containing BASIC-DOS commands and BASIC statements (see [BASIC-DOS Programming](../../lang/)).  The differences between them are:

- BAT files can echo each line as it runs (after [ECHO ON](../device/screen/#echo)); BAS files can't
- BAS files run from the prompt remain loaded when they end, along with their variables, so they can be LIST'ed or RUN again

A BAT or BAS file can run other BAT or BAS files (no CALL command is required) and then continue; each nested BAS file gets its own variables.  See [Batch Files](../../lang/#batch-files) for how BASIC-DOS batch files differ from PC DOS batch files.

### Files Provided with BASIC-DOS

In the root directory:

- [COMMAND.COM](command/): the BASIC-DOS Command Shell
- HELP.TXT: the text displayed by the [HELP](../system/#help) command

In the **EXT** directory (see [Running Programs](../../intro/#running-programs) for the layout of a BASIC-DOS disk):

- FIND.COM, MORE.COM, SORT.COM, TEE.COM, TR.COM, and WC.COM: filters (see below)
- SLEEP.COM: waits the specified number of seconds (eg, `SLEEP 5`); CTRL-C stops it early (source: [sleep.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/sleep.asm))
- VI.COM: a full-screen text editor (see [VI](#vi) below)
- ATTRIB.BAS: displays or changes the attributes of files (see [ATTRIB](#attrib) below)
- CHKDSK.BAS: checks a drive's FAT and directories (see [CHKDSK](#chkdsk) below)
- COMP.BAS: compares files (see [COMP](#comp) below)
- DISKCOPY.BAS: copies a diskette (see [DISKCOPY](#diskcopy) below)
- FORMAT.BAS: formats a diskette or hard disk volume (see [FORMAT](#format) below)
- LABEL.BAS and VOL.BAS: change or display a volume label (see [LABEL and VOL](#label) below)
- LS.BAS: lists files and directories like the UNIX `ls` command (see [LS](#ls) below)
- MODE.BAS: sets the display, a serial port, or a printer (see [MODE](#mode) below)
- SYS.BAS: makes a disk bootable (see [SYS](#sys) below)
- TREE.BAS: displays a directory tree (see [TREE](#tree) below)

Utilities that don't need the speed of assembly language are BASIC programs, written in the style BASIC-DOS lists them in: every line indented with a tab, after a line number only where one is needed as a label.

### Filters

A filter reads lines of input, which normally come from a pipe (eg, `DIR | SORT`) or a file (eg, `SORT < NAMES.TXT`), and writes the results to its output.  FIND, MORE, SORT, and WC also accept file names instead.  Input ends when the pipe is closed, at the end of the file, or at a CTRL-Z.  Switches start with the switch character (`/`, or `-` if [SWITCHAR](../../cfg/#switchar) is `-` or [PATHCHAR](../../cfg/#pathchar) is `/`).

#### FIND

	FIND [/C] [/I] [/N] [/V] "string" [file...]

Displays the lines of input (or of each *file*, or with wildcards (`?` and `*`), every matching file) that contain *string* (eg, `DIR | FIND "BAS"`).  When files are specified, the lines from each file follow a line containing its name.

- `/C` displays only the number of lines
- `/I` ignores case
- `/N` puts each line's number in front of it (eg, `[3]`)
- `/V` displays the lines that do *not* contain *string*

ERRORLEVEL is set to 0 if any lines were displayed (or counted), 1 if none, and 2 if a file couldn't be opened.

Source: [find.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/find.asm)

#### MORE

	MORE [file]

Displays input (or *file*) one screen at a time (eg, `TYPE README.TXT | MORE`).  After each screen, it displays `-- More --` and waits for a key (read from STDERR, since STDIN is the pipe or file); press CTRL-C to stop.

Source: [more.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/more.asm)

#### SORT

	SORT [/R] [/+n] [file]

Displays the lines of input (or *file*) in sorted order, ignoring case (eg, `DIR | SORT`).  `/R` sorts in reverse order, and `/+n` sorts on the characters starting at column *n* (eg, `DIR | SORT /+10` sorts a directory listing by extension).  Up to 64K of text can be sorted.

Source: [sort.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/sort.asm)

#### TEE

	TEE [/A] file

Copies input to its output and to *file* (eg, `DIR | TEE DIR.TXT | MORE`).  *file* is replaced, or with `/A`, appended to (and created if it doesn't exist).  ERRORLEVEL is set to 0, or 2 if *file* couldn't be opened or written.

Source: [tee.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/tee.asm)

#### TR

	TR [/C] [/D] [/S] set1 [set2]

Copies input to output, replacing each character in *set1* with the matching character in *set2*; if *set2* is shorter, its last character repeats.  /D deletes the characters in *set1* instead, /C uses every character *not* in *set1* (in ascending order), and /S squeezes each run of a character in the last set given into a single character.  A set can contain ranges (eg, `a-z`) and the escapes `\t` (TAB), `\n` (LF), `\r` (CR), and `\` before any other character for that character (eg, `\-` or `\\`); a set that contains spaces must be quoted.  ERRORLEVEL is set to 0, or 2 if a set is missing (or only *set1* is given, without /D or /S).

	DIR | TR a-z A-Z
	TYPE README.TXT | TR /D \r
	DIR | TR /S " "

Source: [tr.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/tr.asm)

#### WC

	WC [/L] [/W] [/C] [file...]

Displays the number of lines, words, and bytes of input (or of each *file*, or with wildcards (`?` and `*`), every matching file, followed by their totals if there's more than one), along with each file's name (eg, `DIR | WC /L` or `WC *.BAS`).  `/L`, `/W`, and `/C` display only the line, word, or byte counts, respectively (without any of them, all three are displayed).  Lines are counted by their line feeds, and words are separated by spaces and control characters (eg, tabs and line breaks).  ERRORLEVEL is set to 0, or 2 if a file couldn't be opened.

Source: [wc.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/wc.asm)

Filters can be chained (eg, `TYPE FILE | SORT | MORE`), but every command after the first needs its own session, so a pipeline can't have more commands than [SESSIONS=](../../cfg/#sessions) allows, and a BAT or BAS file (which runs in the current session) can only be the first command (eg, `LS | MORE`, but not `DIR | TEST.BAS`, which reports `Unable to open TEST.BAS`).  If any command of a pipeline fails (eg, it can't be found, or there's no session for it), the error is displayed, the commands already running are ended, and ERRORLEVEL is set to 1.  And if a command stops reading its input early (eg, FIND can't open its file), the command writing to it gets a write error instead of waiting forever; the filters stop when that happens.

### ATTRIB

	ATTRIB [+R|-R] [+H|-H] [+S|-S] [+A|-A] [filespec]

Displays the attributes of each file matching *filespec* (or every file in the current directory), including hidden and system files, with an `A` (archive), `S` (system), `H` (hidden), or `R` (read-only) in its column for each attribute it has, followed by the file's name.  Attributes given with `+` are set first, and those given with `-` are cleared, and one `+` or `-` can be followed by several attributes (eg, `ATTRIB +RS *.COM`).  A read-only file can't be opened for writing, replaced, or deleted, and only a hidden file is left out of DIR listings (unless [DIR /A](../disk/#dir) is used).  ATTRIB sets attributes with DOS function 4301h (see [DOS](../basic/#dos)), so a file whose attributes can't be changed (eg, while its volume is open) is a "Permission denied" error.

	ATTRIB
	  A          CONFIG.SYS
	     SHR     BASDEV.COM
	     SHR     BASDOS.COM
	     S R     COMMAND.COM
	  A          HELP.TXT
	ATTRIB -R COMMAND.COM

Source: [ATTRIB.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/ATTRIB.BAS)

### CHKDSK

	CHKDSK [d:] [/V]

Checks the FAT and directories of drive *d* (or the current drive): every file's and directory's cluster chain is followed, and CHKDSK reports a chain that's cross-linked with another (sharing a cluster), that doesn't match its file's size, or that contains an invalid cluster, and finally, lost clusters (in use, but in no file's chain).  Then it reports the volume label (with its date and time) and the space on the drive: the total, the bad sectors, the hidden files, directories, and user files (each in whole clusters), the lost clusters, and the space available.  `/V` lists the name of every file and directory as it's checked.

Unlike PC DOS, CHKDSK only reports problems (there's no `/F` to fix them), and it doesn't report memory (see [MEM](../system/#mem)).  CHKDSK reads the volume directly (see [OPEN](../basic/#open)), so it can't check directories beyond the first 14Mb of a volume, which it reports.

	CHKDSK A:

	Volume BD-D40      created 10-23-2026 12:08a

	      362496 bytes total disk space
	       46080 bytes in 2 hidden files
	        3072 bytes in 3 directories
	      214016 bytes in 53 user files
	       99328 bytes available on disk

Source: [CHKDSK.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/CHKDSK.BAS)

### COMP

	COMP file1 file2

Compares each file matching *file1* (which can contain wildcards, but doesn't match hidden files) with *file2*, or if *file2* is a drive or directory, with the file there that has the same name.  As in PC DOS, files of different sizes aren't compared, and each difference is reported with its offset (in hex) and the byte from each file, until 10 differences have been found; otherwise, COMP reports `Files compare ok`.

	COMP *.BAS B:

Source: [COMP.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/COMP.BAS)

### DISKCOPY

	DISKCOPY [d1: [d2:]]

Copies the diskette in drive *d1* (or the current drive) to the diskette in drive *d2* (or *d1*), track by track, formatting each of the target's tracks (with the source's parameters) as it goes, so the target doesn't have to be formatted first.  If both drives are the same, DISKCOPY reads as many tracks as memory allows, then asks for the target diskette, writes them, and asks for the source diskette again, until the whole diskette has been copied.  DISKCOPY copies diskettes of any size its drives support, including PC DOS 1.x diskettes (whose sizes come from the media ID in their FATs), and it refuses hard disks.

Source: [DISKCOPY.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/DISKCOPY.BAS)

### FORMAT

	FORMAT d: [/S] [/V[:label]] [/F:size] [/1] [/8]

Formats the diskette in drive *d* (A: or B:) as a 360K diskette (40 cylinders, 2 sides, 9 sectors per track), or with `/1` as a single-sided diskette (180K), or with `/8` with 8 sectors per track (320K, or 160K with `/1`, for PC DOS 1.x).  `/F:720` formats a 720K diskette (80 cylinders, 9 sectors per track) in a 3.5-inch drive, and `/F:1200` a 1.2M diskette (80 cylinders, 15 sectors per track) in a high-capacity 5.25-inch drive; without `/F`, FORMAT uses the drive's own size, which the BIOS of a PC AT (or later) reports, and a PC or XT doesn't (so 360K), and a 1.44M drive formats 720K diskettes.  `/S` then copies BASDEV.COM, BASDOS.COM, and COMMAND.COM from the root directory of the current drive, making the diskette bootable, and makes BASDEV.COM and BASDOS.COM read-only hidden system files and COMMAND.COM a read-only system file, and `/V` gives the new volume a label (up to 11 characters, which FORMAT asks for, unless it's given as `/V:label`).  FORMAT prompts for the diskette, formats and verifies every track (with the diskette driver's [IOCTL](../basic/#ioctl) requests), writes the boot sector (a copy of the current drive's, with the new diskette's parameters), the two FATs, and the root directory, reports the space on the diskette, and asks whether to format another.  Cluster sizes and root directory sizes follow the PC DOS 2.x rules (eg, 1K clusters and 112 root entries for 360K and 720K diskettes), with 12-bit FATs, except that 1.2M diskettes get PC DOS 3.x's layout (512-byte clusters and 224 root entries).

A write-protected diskette, an empty drive, or a track that can't be formatted ("Track *n* bad - disk unusable") ends the format.  FORMAT can't format the current drive (which also supplies the boot sector and system files).

For a hard disk drive, FORMAT first displays the disk's geometry and partition table (each partition's type, starting sector, size, and drive letter, if it's a FAT volume).  If the disk has FAT volumes, FORMAT formats the drive named on the command line (or if that drive is the whole disk, asks which volume to format), after a warning that all data on the drive will be lost.  If the disk has no partition table (eg, a new hard disk, which BASIC-DOS gives a drive letter anyway, with "unknown media"), FORMAT offers to create one, with a single volume (starting at the second track and ending at a cylinder boundary) of the size you choose in Mb, up to 32Mb (65535 sectors) or the size of the disk; it then writes a master boot record (with the hard disk driver's boot code) and formats the new volume.  A volume of up to 32680 sectors (about 16Mb) gets the PC DOS 2.x layout for its size (eg, 4K clusters and 512 root entries for 10Mb) with a 12-bit FAT; a larger volume gets 2K clusters and a 16-bit FAT, as PC DOS 3.x did.  Hard disk volumes aren't verified, and extended partitions aren't supported.

Source: [FORMAT.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/FORMAT.BAS)

### LABEL and VOL {#label}

	LABEL [d:][label]
	VOL [d:]

LABEL gives drive *d* (or the current drive) a volume label of up to 11 characters, which can include spaces, but not `* ? / \ | . , ; : + = [ ] < >` or `"`.  Without a *label*, LABEL displays the current label and asks for a new one; pressing ENTER deletes the current label (after asking).  VOL displays the label, as DIR does at the start of a listing.  The label is a root directory entry with the volume attribute, which LABEL writes directly (see [OPEN](../basic/#open)), so the drive can't have any files open.

	LABEL A:SAVED FILES

Source: [LABEL.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/LABEL.BAS) and [VOL.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/VOL.BAS)

### LS

	LS [-1aFlRrSt] [filespec]...

Lists files and directories like the UNIX `ls` command.  Each *filespec* that's a directory (eg, `LS \EXT`, `LS ..`, or `LS A:`) lists the files in that directory, and without one, the current directory is listed.  Any other *filespec* lists the files that match it (and with wildcards, the directories that match it, too), with the *filespec*'s drive and path in front of each name, as a UNIX shell would expand them (eg, `LS \EXT\T*.COM` lists `\EXT\TEE.COM  \EXT\TR.COM`); those files are listed first, all together, and then each directory, after a line with its name and a colon if more than one *filespec* was given.  A *filespec* that matches nothing is reported (eg, `Unable to find X.BAS`).

Names are sorted, and listed in columns down the screen, each column 2 characters wider than the longest name, with as many columns as fit the console's width.  When the output isn't the console (eg, `LS > FILES.TXT`), names are listed one per line, as UNIX does.  Hidden files, and the `.` and `..` entries of a subdirectory, are listed only with `-a`.

Options start with `-` (regardless of [SWITCHAR](../../cfg/#switchar)), are case-sensitive, and can be combined (eg, `LS -ltr` is the same as `LS -l -t -r`):

- `-1` lists one name per line
- `-a` lists all files, including hidden files and the `.` and `..` entries
- `-F` adds the path character (eg, `\`) after the name of each directory, and `*` after each program (COM, EXE, BAT, and BAS files)
- `-l` lists each file's mode, link count (always 1), size, date, and name, after a `total` line with the directory's size in K (the sum of each file's size rounded up to a whole K); the mode is `d` for a directory (or `-`), followed by `rwxr-xr-x` for a directory or program, or `rw-r--r--` for any other file, without the `w` for a read-only file.  The date shows the time if it's within the last 6 months, or else the year.  Since files have no owners, there are no owner or group columns.
- `-R` lists the subdirectories of each directory listed, too, after a line with each one's path (eg, `.\TESTS:`)
- `-r` reverses the order
- `-S` sorts by size, largest first
- `-t` sorts by date and time, newest first (and `-tr`, oldest first)

Files with the same size or time are sorted by name.  A listing can have up to 512 names (more is a "Subscript out of range" error).

	LS \EXT
	ATTRIB.BAS    DISKCOPY.BAS  LS.BAS        SORT.COM      TREE.BAS
	CHKDSK.BAS    FIND.COM      MODE.BAS      SYS.BAS       VI.COM
	COMP.BAS      FORMAT.BAS    MORE.COM      TEE.COM       VOL.BAS
	DEBUG.COM     LABEL.BAS     SLEEP.COM     TR.COM        WC.COM
	LS -F \
	AUTOEXEC.BAT*  CONFIG.SYS     HELP.TXT       TOOLS\
	COMMAND.COM*   EXT\           TESTS\
	LS -lt \EXT\T*.*
	-rwxr-xr-x 1  533 Oct 24 11:22 \EXT\TEE.COM
	-rwxr-xr-x 1  579 Oct 24 11:22 \EXT\TR.COM
	-rwxr-xr-x 1 2978 Oct 23 12:17 \EXT\TREE.BAS

Source: [LS.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/LS.BAS)

### MODE

	MODE 40|80|BW40|BW80|CO40|CO80
	MODE COMn:baud[,parity[,data[,stop]]]
	MODE LPTn:[cols][,lines]

Sets the display to 40 or 80 columns (BW turns color off, as `SCREEN 0,0` does, and CO turns it on), sets a serial port's baud rate (two digits abbreviate a rate, eg, 96 for 9600), parity (N, O, or E; the default is N), data bits (default 8), and stop bits (default 1), or sends an IBM/Epson printer its condensed (132 columns) or normal (80 columns) print codes and its 8 or 6 lines per inch codes.  A serial port is set by opening it with its parameters and an input buffer length of 0 (see [COM](../../cfg/#console)), which initializes the port and releases it again, so a port that's already open (eg, the console) isn't changed.

Source: [MODE.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/MODE.BAS)

### SYS

	SYS d:

Makes drive *d* bootable without reformatting it: SYS copies BASDEV.COM, BASDOS.COM, and COMMAND.COM from the root directory of the current drive to the root directory of *d* (replacing any copies already there), makes them read-only system files (and BASDEV.COM and BASDOS.COM hidden), and gives *d*'s boot sector the current drive's boot code, keeping *d*'s disk parameters.  Since the boot code follows the system files' cluster chains, they don't have to be the first files on the drive, or contiguous, so SYS works on any FAT volume with room for them (including one formatted by another DOS).

Source: [SYS.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/SYS.BAS)

### TREE

	TREE [d:][path] [/F] [/A]

Displays the directories below *path* (or the current directory), each one connected to its parent by line-drawing characters, or with `/A`, by ASCII characters (eg, for a printer); `/F` lists each directory's files, too, before its subdirectories.  If there are no subdirectories, TREE says so.

	TREE C:\ /A
	Directory PATH listing for Volume BD-10MB
	C:\
	+---EXT
	+---DEMOS
	|   \---WOLF3D
	+---SAMPLES
	+---SRC
	|   +---BOOT
	|   |   \---OBJ
	|   +---CMD
	|   |   \---OBJ
	...

Source: [TREE.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/TREE.BAS)

### VI

	VI [/WS] [file]

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

In insert mode, typed characters are inserted, ENTER starts a new line, BACKSPACE erases what was just typed, and ESC (or CTRL-C or Insert) returns to command mode.  On the CON console, insert mode displays a block cursor.

| Command | Description |
|---------|-------------|
| `:w` [*file*] | Write the file (or another file) |
| `:wq` [*file*] or `:x` | Write the file (`:x` only if it's modified) and exit |
| `:q` | Exit, unless the file has been modified; `:q!` exits anyway |
| `:`*n* or `:$` | Move to line *n*, or the last line |
| `:s/`*old*`/`*new*`/` | Replace the first *old* on the current line with *new* (add `g` at the end to replace every *old* on the line, and use `:%s` for every line); the text is matched exactly |

`/WS` adds these WordStar keys, which work in insert mode too (and replace the vi commands that use the same keys, such as CTRL-D and CTRL-E).  The key after CTRL-Q can be typed with or without CTRL (eg, CTRL-Q CTRL-R or CTRL-Q R).

| WordStar Keys | Description |
|---------------|-------------|
| CTRL-S CTRL-D | Move left or right |
| CTRL-E CTRL-X | Move up or down |
| CTRL-Q S, CTRL-Q D | Move to the start or end of the line |
| CTRL-Q E, CTRL-Q X | Move to the top or bottom line of the screen |
| CTRL-Q R, CTRL-Q C | Move to the first or last line |
| CTRL-Q F | Find text (like `/`) |
| CTRL-R CTRL-C | Scroll backward or forward a screen |
| CTRL-W CTRL-Z | Scroll up or down a line |
| CTRL-G | Delete the character under the cursor |
| CTRL-Y | Delete the line |
| CTRL-Q Y | Delete to the end of the line |
| CTRL-N | Insert a new line above the current line |
| CTRL-V | Switch between insert mode and command mode |

Source: [software/src/os/util/vi](https://github.com/jeffpar/basicdos/tree/main/software/src/os/util/vi)

Every BASIC-DOS startup diskette also contains the system files BASDEV.COM (device drivers) and BASDOS.COM (the kernel), which are read-only hidden system files.  These files must not be run.

{% include footer.html prev="Disk Commands:../disk/" next="COMMAND.COM:command/" %}
