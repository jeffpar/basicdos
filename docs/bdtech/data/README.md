---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Data Structures
permalink: /docs/bdtech/data/
---

{% include header.html %}

- Program structures: [PSP](#psp), [EPB](#epb), [COMDATA](#comdata)
- Session structures: [SPB](#spb), [SCB](#scb)
- File structures: [FFB](#ffb), [SFB](#sfb), [FCB](#fcb)
- Memory structures: [MCB](#mcb), [DOSVARS](#dosvars)

### PSP

The Program Segment Prefix is compatible with PC DOS, but BASIC-DOS uses several fields that PC DOS left unused (marked with *).

| Offset | Field | Description |
|--------|-------|-------------|
| 00h | PSP_TERMCALL | INT 20h instruction |
| 02h | PSP_PARAS | Paragraphs available |
| 04h | PSP_SCB | * Session number |
| 05h | PSP_CALL5 | Far call (9Ah) for CALL 5 |
| 06h | PSP_SIZE | Size of the PSP segment |
| 08h | PSP_FCSEG | Far call segment |
| 0Ah | PSP_EXIT | Original INT 22h vector |
| 0Eh | PSP_CTRLC | Original INT 23h vector |
| 12h | PSP_ERROR | Original INT 24h vector |
| 16h | PSP_PARENT | Parent PSP (0 if none) |
| 18h | PSP_PFT | Process File Table (20 system file handles, FFh if unused) |
| 2Ch | PSP_ENVSEG | Environment segment |
| 2Eh | PSP_STACK | * Last program stack pointer |
| 32h | PSP_HDLFREE | Available handles |
| 34h | PSP_HDLPTR | Pointer to the handle table |
| 38h | PSP_SHAREPSP | |
| 3Ch | PSP_DTAPREV | * Previous DTA (restored on return) |
| 40h | PSP_START | * Initial program address |
| 44h | PSP_CODESIZE | * Shared code size (see [COMDATA](#comdata)) |
| 46h | PSP_CHECKSUM | * Code checksum |
| 48h | PSP_HEAPSIZE | * Heap size |
| 4Ah | PSP_HEAP | * Heap offset |
| 4Eh | PSP_EXCODE | * Exit code |
| 4Fh | PSP_EXTYPE | * Exit type (see [Exit Types](../dos/#exit-types)) |
| 50h | PSP_DOSCALL | INT 21h / RETF |
| 56h | PSP_DIGITS | * Digit switches (see DOS_UTL_PARSESW) |
| 58h | PSP_LETTERS | * Letter switches (see DOS_UTL_PARSESW) |
| 5Ch | PSP_FCB1 | First FCB |
| 6Ch | PSP_FCB2 | Second FCB |
| 80h | PSP_CMDTAIL | Command tail (length byte, characters, and RETURN); also the default DTA |

### EPB

The Exec Parameter Block is passed to DOS_PSP_EXEC in ES:BX.

| Offset | Field | Description |
|--------|-------|-------------|
| 00h | EPB_ENVSEG | Environment segment (0 to copy the parent's; currently ignored) |
| 02h | EPB_CMDTAIL | Far pointer to the command tail |
| 06h | EPB_FCB1 | Far pointer to the FCB for PSP_FCB1 |
| 0Ah | EPB_FCB2 | Far pointer to the FCB for PSP_FCB2 |
| 0Eh | EPB_INIT_SP | Initial SS:SP (returned by DOS_PSP_EXEC1) |
| 12h | EPB_INIT_IP | Initial CS:IP (returned by DOS_PSP_EXEC1) |

### COMDATA

Unlike PC DOS, BASIC-DOS doesn't give a COM program all available memory; it gets its file size plus MINHEAP (1024) bytes.  A COM program can request more by ending its image with a COMDATA structure, which the COMHEAP macro (in dosapi.inc) creates:

| Offset | Field | Description |
|--------|-------|-------------|
| 00h | CD_CODESIZE | Size of the shared code, in bytes |
| 02h | CD_HEAPSIZE | Additional heap space, in paragraphs |
| 04h | CD_SIG | Signature (SIG_BASICDOS, "BD") |

Dynamically allocated heap space is zero-initialized, and the program's initial stack is at the top of the heap (or the top of its first 64K, whichever is lower).  PSP_HEAP contains the offset of the heap.

CD_CODESIZE allows a COM program to share its code (starting at offset 100h) among all running copies: each copy has its own segment for DS, ES, and SS, but only the first copy contains the shared code, and the other copies contain only the code and data that follow it, plus their heaps.  COMMAND.COM uses this, so each additional session costs only its data and heap.

### SPB

The Session Parameter Block is passed to DOS_UTL_LOAD in ES:BX.

| Offset | Field | Description |
|--------|-------|-------------|
| 00h | SPB_ENVSEG | Environment segment (0 to copy the caller's) |
| 02h | SPB_CMDLINE | Far pointer to the command line (the program name and its arguments) |
| 06h | SPB_SFHIN | System file handle for STDIN (SFH_NONE, FFh, for the default) |
| 07h | SPB_SFHOUT | System file handle for STDOUT |
| 08h | SPB_SFHERR | System file handle for STDERR |
| 09h | SPB_SFHAUX | System file handle for STDAUX |
| 0Ah | SPB_SFHPRN | System file handle for STDPRN |

For example, COMMAND.COM runs each command after the first in a pipeline by loading it into a new session, with SPB_SFHIN set to the pipe.

### SCB

The Session Control Block is internal to DOS; there's one for each session (see [SESSIONS=](../../bdman/cfg/#sessions)).

| Offset | Field | Description |
|--------|-------|-------------|
| 00h | SCB_STATUS | Status (SCSTAT_INIT, SCSTAT_LOAD, SCSTAT_START, SCSTAT_ABORT) |
| 01h | SCB_NUM | Session number |
| 02h | SCB_SFHIN - SCB_SFHPRN | System file handles for STDIN, STDOUT, STDERR, STDAUX, and STDPRN |
| 08h | SCB_ENVSEG | Environment segment |
| 0Ah | SCB_CONTEXT | Console context (from the CON driver) |
| 0Ch | SCB_OWNER | PSP of the owner, if any |
| 0Eh | SCB_PSP | Current PSP in this session |
| 10h | SCB_WAITID | Wait ID if waiting, 0 if runnable |
| 14h | SCB_STACK | Session stack pointer |
| 18h | SCB_EXIT | Current exit (INT 22h) handler |
| 1Ch | SCB_CTRLC | Current CTRL-C (INT 23h) handler |
| 20h | SCB_ERROR | Current critical error (INT 24h) handler |
| 24h | SCB_DTA | Current DTA |
| 28h | SCB_PARENT | Parent SCB, if any |
| 2Ah | SCB_CTRLC_ALL | 1 if CTRL-C checking is enabled on all calls |
| 2Bh | SCB_CTRLC_ACT | 1 if CTRL-C is active |
| 2Ch | SCB_CTRLP_ACT | 1 if CTRL-P is active |
| 2Dh | SCB_INDOS | Active DOS and utility call count |
| 2Eh | SCB_CURDRV | Current drive # |
| 2Fh | SCB_SWITCHAR | Current switch character |
| 30h | SCB_FILENAME | Filename buffer |

### FFB

The Find File Block is stored in the DTA by DOS_DSK_FFIRST and DOS_DSK_FNEXT.

| Offset | Field | Description |
|--------|-------|-------------|
| 00h | FFB_DRIVE | Drive # |
| 01h | FFB_SATTR | Search attributes |
| 02h | FFB_FILESPEC | Filespec (11 characters) |
| 0Dh | FFB_RESERVED | Reserved |
| 13h | FFB_DIRNUM | Directory entry # |
| 15h | FFB_ATTR | File attributes |
| 16h | FFB_TIME | File time |
| 18h | FFB_DATE | File date |
| 1Ah | FFB_SIZE | File size |
| 1Eh | FFB_NAME | File name (null-terminated) |

### SFB

The System File Block is internal to DOS; there's one for each open file or device (see [FILES=](../../bdman/cfg/#files)).  System file handles (SFHs) are indexes into the SFB table, whereas process file handles are indexes into a PSP's Process File Table, whose entries are SFHs.  For files, the first 20h bytes of an SFB match the file's directory entry.

| Offset | Field | Description |
|--------|-------|-------------|
| 00h | SFB_NAME | Filename (11 characters) |
| 0Bh | SFB_ATTR | Attributes |
| 0Ch | SFB_DEVICE | Device driver |
| 10h | SFB_CONTEXT | Device context (first cluster if a file) |
| 12h | SFB_DRIVE | Drive # (-1 if not a block device) |
| 13h | SFB_MODE | Open mode |
| 14h | SFB_REFS | # of process handles referring to it |
| 16h | SFB_TIME | Time of last write |
| 18h | SFB_DATE | Date of last write |
| 1Ah | SFB_CLN | First cluster |
| 1Ch | SFB_SIZE | File size |
| 20h | SFB_CURPOS | Current file position |
| 24h | SFB_CURCLN | Current cluster |
| 26h | SFB_FLAGS | Flags (SFBF_FCB, SFBF_DIRTY) |
| 28h | SFB_OWNER | Owning PSP (FCBs only) |
| 2Ah | SFB_FCB | FCB address (FCBs only) |
| 2Eh | SFB_DIRNUM | Directory entry # (files only) |

### FCB

File Control Blocks are compatible with PC DOS; see FCB, FCBF, and FCBEX in dosapi.inc.  Only the first 10h bytes of an FCB fit in PSP_FCB1 and PSP_FCB2.

### MCB

Each Memory Control Block occupies the paragraph before the memory block it describes.

| Offset | Field | Description |
|--------|-------|-------------|
| 00h | MCB_SIG | 'M' (4Dh), or 'Z' (5Ah) for the last block |
| 01h | MCB_OWNER | Owner: 0 if free, 8 if owned by the system, or a PSP segment |
| 03h | MCB_PARAS | Size of the block, in paragraphs |
| 05h | MCB_TYPE | Block type (see DOS_MEM_ALLOC) |
| 06h | MCB_RESERVED | |
| 08h | MCB_NAME | Name of the owning program (zero if none) |

### DOSVARS

DOS_MSC_GETVARS returns ES:BX -> DOSVARS.  As in PC DOS, the word before it contains the first memory segment; the rest of the structure is BASIC-DOS-specific.

| Offset | Field | Description |
|--------|-------|-------------|
| -02h | DV_MCB_HEAD | First memory segment (first MCB) |
| 00h | DV_MCB_LIMIT | First unavailable segment |
| 02h | DV_BPB_TABLE | Offset and limit of the BPB table |
| 06h | DV_SFB_TABLE | Offset and limit of the SFB table |
| 0Ah | DV_SCB_TABLE | Offset and limit of the SCB table |

{% include footer.html prev="Floating-Point Interface:../fpu/" next="" %}
