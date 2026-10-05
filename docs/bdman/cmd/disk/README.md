---
layout: sheet
title: Disk Commands
permalink: /docs/bdman/cmd/disk/
---

{% include header.html %}

BASIC-DOS disk commands include:

- [COPY](#copy)
- [DEL](#del) (or ERASE)
- [DIR](#dir)
- [LOAD](#load)
- [TYPE](#type)

File names follow PC DOS conventions: an optional drive letter and colon (eg, `B:`), a name of up to 8 characters, and an optional period followed by an extension of up to 3 characters (eg, `B:PRIMES.BAS`).  Drives A: and B: are diskette drives, and drives C: and D: are the first FAT12 partitions of up to two hard disks.  Subdirectories aren't supported yet.

Device names (eg, CON, PRN, AUX, COM1, LPT1, and NUL) can be used in place of file names (eg, `COPY TEST.TXT NUL` or `DIR > NUL`).

The REN (RENAME) and SAVE commands aren't supported yet.

### COPY

> COPY *input* *output*

Copies the contents of the input file or device to the output file or device.  The output file is created, or truncated if it already exists.  A file cannot be copied onto itself.

	COPY PRIMES.BAS B:

### DEL

> DEL *file*  
> ERASE *file*

Deletes the specified file.  Wildcards aren't supported yet.  ERASE is the same as DEL, unless it's erasing arrays (see [ERASE](../basic/#erase)).

### DIR

> DIR [*filespec*] [/P]

Displays a directory listing of all files matching the given *filespec* (or all files if none is specified).  The *filespec* can contain the wildcards `?` (any character) and `*` (any characters to the end of the name or extension).  /P pauses after each screenful of output.

	DIR *.BAS

### LOAD

> LOAD *file*

Loads the specified BAS or BAT file without running it, so that it can be [LIST](../system/#list)ed or [RUN](../system/#run).  If no extension is specified, BAS is tried first, and then BAT.  The file can be a text file or a tokenized BAS file saved by BASICA or GW-BASIC (but not a protected one).  LOAD can't be used inside a BAS or BAT file yet (it reports "LOAD not allowed in a program"); to run another program from a BAS or BAT file, just use its name.

### TYPE

> TYPE *file*

Displays the contents of the specified file.

{% include footer.html prev="Sound Commands:../device/sound/" next="External Commands:../external/" %}
