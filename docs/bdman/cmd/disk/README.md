---
layout: sheet
title: Disk Commands
permalink: /docs/bdman/cmd/disk/
---

{% include header.html %}

BASIC-DOS disk commands include:

- [CD](#cd) (or CHDIR)
- [COPY](#copy)
- [DEL](#del) (or ERASE)
- [DIR](#dir)
- [LOAD](#load)
- [MD](#md) (or MKDIR)
- [RD](#rd) (or RMDIR)
- [REN](#ren) (or RENAME or MV)
- [SAVE](#save)
- [TYPE](#type)

File names follow PC DOS conventions: an optional drive letter and colon (eg, `B:`), a name of up to 8 characters, and an optional period followed by an extension of up to 3 characters (eg, `B:PRIMES.BAS`).  Drives A: and B: are diskette drives, and drives C: and D: are the first FAT12 partitions of up to two hard disks.

A file name can also be preceded by a path of directory names, each followed by the path character (`/` by default, or `\` when [SWITCHAR](../../cfg/#switchar) is `/`).  A path that begins with the path character starts at the root directory (eg, `TYPE /SUBDIR/INSIDE.TXT`); otherwise, it starts at the drive's current directory (see [CD](#cd)), which the prompt displays (eg, `C:/SUBDIR>`).  A directory name of `.` refers to the same directory, and `..` refers to the parent directory (eg, `TYPE ../HELLO.TXT`).  Each session has its own current directory for every drive.

DOS commands and external programs can use paths at the prompt and in BAT or BAS files (eg, `DIR /TOOLS` or `/TOOLS/SLEEP 1`), including after a colon that separates commands.  In BASIC file statements such as OPEN, supply a path as a quoted string or string variable.

Device names (eg, CON, PRN, AUX, COM1, LPT1, and NUL) can be used in place of file names (eg, `COPY TEST.TXT NUL` or `DIR > NUL`).

A string variable can also be used in place of any file name (or path, or filespec), in which case its value is used (eg, `F$ = "PRIMES.BAS"` and then `TYPE F$`, or `COPY CON NAME$`).  This works in BAS and BAT files, and at the prompt, where variables set with LET remain until the next program runs.  Any name that looks like a string variable (a letter, followed by letters or digits, ending with `$`) is a variable; one that doesn't exist is empty, as in BASIC, and an empty string variable is the same as no file name (eg, `DIR E$` lists all files when `E$` is empty).  To use a file name that looks like a string variable, put it in quotes (eg, `TYPE "TEST$"`); any quoted file name works the same as an unquoted one.

REN (or RENAME or MV) renames or moves a file or directory on the same drive.

### CD

> CD [*drive*:][*path*]  
> CHDIR [*drive*:][*path*]

Changes the current directory of *drive* (or the current drive) to *path*.  If no *path* is specified, the drive's current directory is displayed.

	C:/>CD SUBDIR
	C:/SUBDIR>CD
	C:/SUBDIR

	C:/SUBDIR>CD ..
	C:/>

### COPY

> COPY *input* [*output*]

Copies the contents of the input file or device to the output file or device.  The output file is created, or truncated if it already exists.  If the output is a drive or directory (or is omitted, which means the current directory), the input's filename (without any drive or path) is used.  With wildcards (? and *), every matching file is copied, and its name is displayed; the output must then be a drive or directory (or omitted).  A file cannot be copied onto itself, or onto a file that another session has open.  If the disk fills up, COPY reports "Insufficient disk space".  COPY stops at the first file it can't copy.

	COPY PRIMES.BAS B:
	COPY B:/*.BAS

### DEL

> DEL *file*  
> ERASE *file*

Deletes the specified file.  With the wildcards `?` and `*` (as in [DIR](#dir)), every matching file is deleted (eg, `DEL *.TMP` or `DEL SUBDIR/T?.TXT`); hidden and system files and directories never match.  It's an error if no file matches.  ERASE is the same as DEL, unless it's erasing arrays (see [ERASE](../basic/#erase)), and KILL is the same as DEL.

### DIR

> DIR [*filespec*]

Displays a directory listing of all files matching the given *filespec* (or all files if none is specified).  The *filespec* can contain the wildcards `?` (any character) and `*` (any characters to the end of the name or extension).  Subdirectories are listed with `<DIR>` in place of a size, and if *filespec* is a directory (eg, `DIR SUBDIR` or `DIR /`), the files in that directory are listed.  Use `DIR | MORE` to pause after each screenful of output.

	DIR *.BAS

### LOAD

> LOAD *file*

Loads the specified BAS or BAT file without running it, so that it can be [LIST](../system/#list)ed or [RUN](../system/#run).  If no extension is specified, BAS is tried first, and then BAT.  The file can be a text file or a tokenized BAS file saved by BASICA or GW-BASIC (but not a protected one).  LOAD can't be used inside a BAS or BAT file yet (it reports "Not allowed in a program"); to run another program from a BAS or BAT file, just use its name.

### MD

> MD [*drive*:]*path*  
> MKDIR [*drive*:]*path*

Creates a new directory, which initially contains only the `.` and `..` entries.  A directory grows as needed when files are added to it (unlike the root directory, which has a fixed size).

	MD GAMES

### RD

> RD [*drive*:]*path*  
> RMDIR [*drive*:]*path*

Removes a directory, which must be empty (except for its `.` and `..` entries) and can't be the current directory of any session.

	RD GAMES

### REN

> REN *source* *destination*

Renames or moves one file or directory on the same drive.  RENAME and MV are aliases.  Both paths are relative to the current directory unless qualified.  The destination can be a new filename (eg, `REN OLD.TXT NEW.TXT` or `MV IN/OLD.TXT OUT/NEW.TXT`) or an existing directory (eg, `MV IN/OLD.TXT OUT`), which retains the original filename.

An existing destination is never overwritten.  File contents, size, attributes, and timestamps are preserved.  Directories, including their contents, can also be moved; their parent (`..`) is updated, and active current directories remain valid.  A directory cannot be moved into itself or a descendant.  Open source files and files on an open volume cannot be moved, but files within a moved directory can remain open.  Cross-drive moves and wildcard names are not supported.

### SAVE

> SAVE *file*

Saves the currently loaded program as a text file, which LOAD can load again.  If no extension is specified, BAS is used.  An existing file with the same name is replaced.  If the program can't be saved completely, SAVE reports "Insufficient disk space" (or "Unable to write file"); the program remains loaded, so you can free some space or save it to another disk.

	SAVE B:HELLO

### TYPE

> TYPE *file*

Displays the contents of the specified file, or with wildcards (? and *), the name and contents of every matching file.

{% include footer.html prev="Sound Commands:../device/sound/" next="External Commands:../external/" %}
