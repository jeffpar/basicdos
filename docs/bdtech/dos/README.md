---
layout: sheet
manual: BASIC-DOS Technical Reference
title: DOS Functions
permalink: /docs/bdtech/dos/
---

{% include header.html %}

BASIC-DOS provides a subset of the PC DOS 2.x function interface, through INT 21h, with the function number in AH.  Unless noted otherwise, functions that can fail return with carry set and an [error code](#error-codes) in AX, and with carry clear on success.  Programs can also use the CP/M-style CALL 5 interface.

Functions not listed below (including any function above 56h) aren't implemented, and return with carry set and AX = ERR_INVALID.

The `DOS_*` names are defined in dosapi.inc.

### Function Summary

#### Console {#console}

| AH | Name | Inputs | Outputs |
|----|------|--------|---------|
| 01h | DOS_TTY_ECHO | | AL = character read from CON and echoed; checks CTRL-C |
| 02h | DOS_TTY_WRITE | DL = character | Writes DL to CON; checks CTRL-C |
| 03h | DOS_AUX_READ | | AL = character read from AUX |
| 04h | DOS_AUX_WRITE | DL = character | Writes DL to AUX |
| 05h | DOS_PRN_WRITE | DL = character | Writes DL to PRN |
| 06h | DOS_TTY_IO | DL = character, or FFh to read | If DL = FFh: ZF clear and AL = character if one is available; no CTRL-C checks |
| 07h | DOS_TTY_IN | | AL = character read from CON; no CTRL-C checks |
| 08h | DOS_TTY_READ | | AL = character read from CON; checks CTRL-C |
| 09h | DOS_TTY_PRINT | DS:DX -> `$`-terminated string | |
| 0Ah | DOS_TTY_INPUT | DS:DX -> input buffer (first byte = maximum characters, including the RETURN) | Second byte = # characters read (excluding the RETURN), followed by the characters |
| 0Bh | DOS_TTY_STATUS | | AL = FFh if a character is available, 0 if not |
| 0Ch | DOS_TTY_FLUSH | AL = function to invoke afterward (01h, 06h, 07h, 08h, or 0Ah) | Same as the function invoked |

The line editing keys that 0Ah supports are described in [Typing Commands](../../bdman/intro/#typing-commands).

#### Disks and Directories {#disks}

| AH | Name | Inputs | Outputs |
|----|------|--------|---------|
| 0Dh | DOS_DSK_RESET | | Writes all modified disk buffers |
| 0Eh | DOS_DSK_SETDRV | DL = drive # (0 = A:) | AL = # of drives; carry set if DL is invalid |
| 19h | DOS_DSK_GETDRV | | AL = current drive # |
| 1Ah | DOS_DSK_SETDTA | DS:DX -> DTA | |
| 2Fh | DOS_DSK_GETDTA | | ES:BX -> DTA |
| 36h | DOS_DSK_GETINFO | DL = drive # (0 = default, 1 = A:) | AX = sectors per cluster (FFFFh if invalid), BX = available clusters, CX = bytes per sector, DX = clusters per disk |
| 39h | DOS_DSK_MKDIR | DS:DX -> path | Creates the directory |
| 3Ah | DOS_DSK_RMDIR | DS:DX -> path | Removes the directory (which must be empty, and not any session's current directory) |
| 3Bh | DOS_DSK_CHDIR | DS:DX -> path | Changes the current directory of the path's drive |
| 41h | DOS_DSK_DELETE | DS:DX -> filename | |
| 47h | DOS_DSK_GETCWD | DL = drive # (0 = default, 1 = A:), DS:SI -> 64-byte buffer | Buffer contains the current directory's path, without a drive or leading path character (an empty string for the root) |
| 4Eh | DOS_DSK_FFIRST | CX = attributes, DS:DX -> filespec | DTA filled in (see [FFB](../data/#ffb)) |
| 4Fh | DOS_DSK_FNEXT | DTA from the previous 4Eh or 4Fh | DTA filled in |
| 56h | DOS_DSK_RENAME | DS:DX -> existing filename, ES:DI -> new filename | Same-drive file and directory moves supported; destination must not exist; open files rejected |

#### File Handles {#handles}

| AH | Name | Inputs | Outputs |
|----|------|--------|---------|
| 3Ch | DOS_HDL_CREATE | CX = attributes, DS:DX -> filename | AX = handle |
| 3Dh | DOS_HDL_OPEN | AL = mode (see MODE_*), DS:DX -> filename | AX = handle |
| 3Eh | DOS_HDL_CLOSE | BX = handle | |
| 3Fh | DOS_HDL_READ | BX = handle, CX = byte count, DS:DX -> buffer | AX = bytes read |
| 40h | DOS_HDL_WRITE | BX = handle, CX = byte count, DS:DX -> buffer | AX = bytes written; CX = 0 sets the file size to the current position |
| 42h | DOS_HDL_SEEK | AL = method (0 = beginning, 1 = current, 2 = end), BX = handle, CX:DX = distance | DX:AX = new position |
| 44h | DOS_HDL_IOCTL | AL = IOCTL code, BX = handle, CX and DX = IOCTL data, DS:SI -> optional IOCTL data | DX = result |

Handles 0-4 are the predefined handles STDIN, STDOUT, STDERR, STDAUX, and STDPRN.  Filenames can also be device names (eg, `CON`, `NUL`, or `COM1`), optionally followed by a colon and device-specific parameters (eg, `CON:40,25`).

A file can be open more than once for reading, but a file opened for writing (MODE_ACC_WO or MODE_ACC_RW, which includes every file opened with 3Ch) can't be open anywhere else.  Opening a file in a way that would violate that rule fails with ERR_SHARE, as does deleting (41h) a file that's open.  Unlike PC DOS 3.x, BASIC-DOS doesn't need SHARE for this, and it ignores the MODE_DENY_* bits.  Devices are exempt, so `CON` can be open for both reading and writing.

A filename that is only a drive letter and colon (eg, `C:`) opens the entire volume, whose sectors can then be read (or written) at file offsets of LBA * bytes per sector; the size of the file is the size of the volume.  For sharing purposes, a volume counts as every file on it: it can be opened for reading only if no file on it is open for writing, and for writing only if no file on it is open at all, and while the volume is open, no file on it can be opened in a way that conflicts with that.  Creating, deleting, or renaming a file, and creating or removing a directory, also fail with ERR_SHARE while the volume is open.  Opening a volume writes any modified buffers for the drive, writing to it discards the drive's buffers, and closing a volume that was written rebuilds its BPB (eg, after it's been reformatted).

For IOCTL code 00h (IOCTL_GETDATA), DOS returns DX = 80h for a device, or the file's drive # (0-based) for a file.  All other IOCTL codes are passed to the device driver as a DDC_IOCTLIN request; see [IOCTL Functions](../dev/#ioctl-functions) for the BASIC-DOS-specific codes.

#### File Control Blocks {#fcbs}

| AH | Name | Inputs | Outputs |
|----|------|--------|---------|
| 0Fh | DOS_FCB_OPEN | DS:DX -> unopened FCB | AL = 0 if found (FCB filled in), FFh if not |
| 10h | DOS_FCB_CLOSE | DS:DX -> FCB | AL = 0 if found, FFh if not |
| 11h | DOS_FCB_FFIRST | DS:DX -> unopened FCB (wildcards allowed) | AL = 0 if found (drive # and DIRENT in the DTA), FFh if not |
| 12h | DOS_FCB_FNEXT | DS:DX -> FCB used with 11h | AL = 0 if found (drive # and DIRENT in the DTA), FFh if not |
| 13h | DOS_FCB_DELETE | DS:DX -> unopened FCB (wildcards allowed) | AL = 0 if any files deleted, FFh if not |
| 14h | DOS_FCB_SREAD | DS:DX -> FCB | AL = FCBERR_* result; record read into the DTA |
| 15h | DOS_FCB_SWRITE | DS:DX -> FCB | AL = FCBERR_* result (1 if the disk is full); record written from the DTA |
| 16h | DOS_FCB_CREATE | DS:DX -> unopened FCB | AL = 0 if created (FCB filled in), FFh if not |
| 17h | DOS_FCB_RENAME | DS:DX -> unopened FCB (wildcards allowed), new name at offset 11h | AL = 0 if any files renamed, FFh if not |
| 21h | DOS_FCB_RREAD | DS:DX -> FCB | AL = FCBERR_* result; record FCBF_RELREC read into the DTA |
| 22h | DOS_FCB_RWRITE | DS:DX -> FCB | AL = FCBERR_* result; record FCBF_RELREC written from the DTA |
| 23h | DOS_FCB_SIZE | DS:DX -> unopened FCB, FCB_RECSIZE = record size | AL = 0 if found (FCBF_RELREC = # records), FFh if not |
| 24h | DOS_FCB_SETREL | DS:DX -> FCB | Sets FCBF_RELREC from FCB_CURBLK and FCBF_CURREC |
| 27h | DOS_FCB_RBREAD | CX = # records, DS:DX -> FCB | AL = FCBERR_* result, CX = # records read |
| 28h | DOS_FCB_RBWRITE | CX = # records, DS:DX -> FCB | AL = FCBERR_* result, CX = # records written; CX = 0 sets the file size to FCBF_RELREC records |
| 29h | DOS_FCB_PARSE | AL = parse flags, DS:SI -> filespec, ES:DI -> FCB buffer | AL = 0 (no wildcards), 1 (wildcards), or FFh (invalid drive); DS:SI -> next character |

Any FCB function can be passed an extended FCB (an FCB preceded by 7 bytes, the first of which is FFh and the last of which contains search attributes, or the attributes of a file being created).  FCB functions always use the drive's current directory, and FCB names that are device names (eg, `NUL` or `CON`) open the device.

An FCB opens a file read-only, so any number of FCBs (and handles opened for reading) can open the same file; the FCB's first write (or truncation) upgrades it to read-write, which fails (AL = 1) if the file is read-only or already open for writing elsewhere.  Deleting or renaming with wildcards skips files that are read-only, directories, volume labels, or open.  Searches (11h and 12h) keep their position in the FCB's FCB_CURBLK field, so the same FCB must be used to continue a search.

#### Memory {#memory}

| AH | Name | Inputs | Outputs |
|----|------|--------|---------|
| 48h | DOS_MEM_ALLOC | AL = block type (MCBTYPE_*, optionally with MCBTYPE_HIGH), BX = paragraphs | AX = segment; on failure, BX = largest available |
| 49h | DOS_MEM_FREE | ES = segment | |
| 4Ah | DOS_MEM_REALLOC | ES = segment, BX = new size in paragraphs | On failure, BX = largest available |

#### Processes {#processes}

| AH | Name | Inputs | Outputs |
|----|------|--------|---------|
| 00h | DOS_PSP_TERM | | Terminates the program (same as INT 20h) |
| 26h | DOS_PSP_COPY | DX = segment | Creates a PSP by copying the current PSP |
| 4B00h | DOS_PSP_EXEC | DS:DX -> program name, ES:BX -> [EPB](../data/#epb) | Loads and runs the program |
| 4B01h | DOS_PSP_EXEC1 | DS:DX -> program name, ES:BX -> EPB | Loads the program without starting it; EPB_INIT_SP and EPB_INIT_IP are filled in |
| 4B02h | DOS_PSP_EXEC2 | ES:BX -> EPB from DOS_PSP_EXEC1 | Starts the program loaded by DOS_PSP_EXEC1 (BASIC-DOS only) |
| 4Ch | DOS_PSP_RETURN | AL = exit code | Terminates the program |
| 4Dh | DOS_PSP_RETCODE | | AL = exit code, AH = exit type (see [Exit Types](#exit-types)) |
| 50h | DOS_PSP_SET | BX = PSP segment | Sets the current PSP |
| 51h | DOS_PSP_GET | | BX = current PSP segment |
| 55h | DOS_PSP_CREATE | DX = segment | Creates a PSP, inheriting the parent's handles |

#### Miscellaneous {#misc}

| AH | Name | Inputs | Outputs |
|----|------|--------|---------|
| 25h | DOS_MSC_SETVEC | AL = vector #, DS:DX = address | |
| 2Ah | DOS_MSC_GETDATE | | CX = year (1980-2099), DH = month, DL = day, AL = day of week (0 = Sunday) |
| 2Bh | DOS_MSC_SETDATE | CX = year, DH = month, DL = day | AL = 0 if valid, FFh if not |
| 2Ch | DOS_MSC_GETTIME | | CH = hours, CL = minutes, DH = seconds, DL = hundredths |
| 2Dh | DOS_MSC_SETTIME | CH = hours, CL = minutes, DH = seconds, DL = hundredths | AL = 0 if valid, FFh if not |
| 30h | DOS_MSC_GETVER | | See [DOS_MSC_GETVER](#dos_msc_getver) |
| 33h | DOS_MSC_CTRLC | AL = 0 to get, 1 to set (from DL) | DL = CTRL-C checking state |
| 35h | DOS_MSC_GETVEC | AL = vector # | ES:BX = address |
| 3700h | DOS_MSC_GETSWC | | DL = switch character |
| 3701h | DOS_MSC_SETSWC | DL = switch character | |
| 3704h | DOS_MSC_GETPCH | | DL = path character (BASIC-DOS only; fixed at boot, so programs need to get it only once) |

The path character is derived at boot from CONFIG.SYS's SWITCHAR setting: `\` if the switch character is `/`, and `/` otherwise.  The default switch character is `-`.  DOS_MSC_SETSWC changes only the current session's switch character; it doesn't change the path character.
| 52h | DOS_MSC_GETVARS | | ES:BX -> [DOSVARS](../data/#dosvars) |

### Differences from PC DOS

#### DOS_MSC_GETVER {#dos_msc_getver}

AL returns 02h, so that PC DOS 2.x programs pass their version checks.  The other registers identify BASIC-DOS:

- AH = BASIC-DOS major version
- BH = BASIC-DOS minor version
- BL = BASIC-DOS revision (1 for A, 2 for B, etc)
- CX = internal state (bit 0 is set in DEBUG builds)

#### Memory Allocation

DOS_MEM_ALLOC takes a block type in AL, which is stored in the block's MCB (MCB_TYPE).  Types include MCBTYPE_NONE (0) and the types COMMAND.COM uses for its own blocks ('C' code, 'F' function, 'V' variable, 'S' string, 'T' text, and 'A' array).  Setting bit 7 of AL (MCBTYPE_HIGH) allocates the block from the top of the last free block that's large enough, rather than the bottom of the first, so that long-lived blocks don't fragment the memory below them.

Programs aren't given all available memory when they're loaded (see [Memory Layout](../arch/#memory-layout)), so a program doesn't need to shrink its memory before allocating more.

#### Program Loading

DOS_PSP_EXEC1 (4B01h) is the undocumented PC DOS function that debuggers use to load a program without starting it.  BASIC-DOS adds DOS_PSP_EXEC2 (4B02h), which starts a program loaded by DOS_PSP_EXEC1; the current PSP must still be the new program's PSP.

BASIC-DOS also stores additional information in the PSP, in fields that PC DOS leaves unused (see [PSP](../data/#psp)): the session number (PSP_SCB), the program's initial stack and start address, its heap, its exit code and exit type, and command-line switches parsed by DOS_UTL_PARSESW.

Environment segments (EPB_ENVSEG) aren't supported yet, so the field is ignored.

#### Files

Any filename passed to a handle function (or to FFIRST, DELETE, RENAME, MKDIR, RMDIR, CHDIR, or EXEC) may include a path, whose directory names are separated by the session's path character (DOS_MSC_GETPCH), not by both `\` and `/` as in PC DOS.  FCB functions always use the drive's current directory.  A subdirectory grows by a cluster whenever a new entry doesn't fit.  Same-drive renames can move files and directories without copying their data; existing destinations and open source files are rejected.  Directory moves update the ".." entry and reject destinations within the moved subtree.  Current directories and open child files remain valid because their directory cluster identities are unchanged.  Cross-drive moves are not supported.  Enforcing the read-only attribute when a handle opens a file, getting and setting file attributes (43h) and file dates and times (57h), and INT 25h and INT 26h (use a volume handle for absolute disk reads and writes instead) aren't supported.  Critical errors (INT 24h) aren't reported to programs yet.

BASIC-DOS doesn't store the path of each current directory, only the directory's first cluster (in a table with one entry per drive for each session), so DOS_DSK_GETCWD rebuilds the path by following ".." entries up to the root.

#### Sessions

Each session has its own current drive, current directory for every drive, DTA, switch and path characters, CTRL-C state, and exit, CTRL-C, and critical error handlers, all of which are stored in its [SCB](../data/#scb).  For example, DOS_MSC_SETVEC with vector 23h changes only the current session's CTRL-C handler.

### Exit Types

DOS_PSP_RETCODE returns one of these exit types in AH:

| Value | Name | Meaning |
|-------|------|---------|
| 0 | EXTYPE_NORMAL | Normal termination |
| 1 | EXTYPE_CTRLC | Terminated by CTRL-C |
| 2 | EXTYPE_ERROR | Terminated by a critical error |
| 3 | EXTYPE_KEEP | Terminated and stayed resident |
| 4 | EXTYPE_DVERR | Terminated by a divide error (BASIC-DOS only) |
| 5 | EXTYPE_OVERR | Terminated by an overflow error (BASIC-DOS only) |
| 6 | EXTYPE_ABORT | Session aborted with CTRL-ALT-DEL (BASIC-DOS only) |

However a program terminates, any of vectors 08h, 09h, 1Bh, and 1Ch that still points into its memory is restored to the value it had when BASIC-DOS started, since some programs (eg, MSBASIC) hook those vectors directly and restore them only when they exit normally.

### Error Codes

| Value | Name | Meaning |
|-------|------|---------|
| 1 | ERR_INVALID | Invalid function |
| 2 | ERR_NOFILE | File not found |
| 3 | ERR_NOPATH | Path not found |
| 4 | ERR_NOHANDLE | Out of handles |
| 5 | ERR_ACCDENIED | Access denied |
| 6 | ERR_BADHANDLE | Invalid handle |
| 7 | ERR_BADMCB | Invalid MCB |
| 8 | ERR_NOMEMORY | Out of memory |
| 9 | ERR_BADADDR | Invalid memory segment |
| 15 | ERR_BADDRIVE | Invalid drive |
| 16 | ERR_CURDIR | Attempt to remove a current directory |
| 17 | ERR_NOTSAME | Not the same device |
| 19-31 | | Device errors, as in DOS 3.x: 19 (write-protected), 20 (unknown unit), 21 (ERR_NOTREADY: drive not ready, eg, no diskette), 22 (unknown command), 23 (CRC error), 25 (seek error), 26 (unknown media), 27 (sector not found), 29 (write fault), 30 (read fault), or 31 (general failure, for any other device error) |
| 32 | ERR_SHARE | Sharing violation (the file is already open) |
| 39 | ERR_DISKFULL | Disk full |
| 100 | ERR_BADSESSION | Invalid session (BASIC-DOS only) |
| 101 | ERR_NOSESSION | Out of sessions (BASIC-DOS only) |

{% include footer.html prev="Architecture:../arch/" next="Utility Functions:../util/" %}
