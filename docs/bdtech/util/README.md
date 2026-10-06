---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Utility Functions
permalink: /docs/bdtech/util/
---

{% include header.html %}

BASIC-DOS provides a set of utility functions through INT 32h, with the function number in AH.  The `DOS_UTL_*` names are defined in dosapi.inc, and the DOSUTIL macro (in macros.inc) generates the calls:

	DOSUTIL	STRLEN			; MOV AH,DOS_UTL_STRLEN / INT 32h

Utility functions differ from DOS functions in a few ways, because some of them are called from interrupt handlers:

- They don't enable interrupts, clear carry, or check for CTRL-C on entry; functions that can fail set carry on failure and clear it on success, and others leave carry unchanged unless noted
- Function numbers beyond the end of the table return immediately, without setting carry
- INT 32h with AH set to a DOS function number plus 80h calls that DOS function without the usual entry processing; DOS_UTL_HDLCTL (C4h) is DOS_HDL_IOCTL (44h) called this way

Device drivers can also call DOS_UTL_WAIT, DOS_UTL_ENDWAIT, DOS_UTL_HOTKEY, DOS_UTL_LOCK, and DOS_UTL_UNLOCK with a far call to DDINT_UTIL (0:53Ah), with AH set to the function number, which avoids the stack overhead of an INT 32h call.

### Function Summary

| AH | Name | Description |
|----|------|-------------|
| 00h | [DOS_UTL_STRLEN](#strings) | Returns the length of a null-terminated string |
| 01h | [DOS_UTL_STRSTR](#strings) | Finds a string within another string |
| 02h | [DOS_UTL_STRUPR](#strings) | Converts a string to upper case |
| 03h | [DOS_UTL_PRINTF](#formatted-output) | printf to the console (STDOUT) |
| 04h | [DOS_UTL_HPRINTF](#formatted-output) | printf to a system file handle |
| 05h | [DOS_UTL_DPRINTF](#formatted-output) | printf to the DEBUG device, if any |
| 06h | [DOS_UTL_SPRINTF](#formatted-output) | sprintf to a buffer |
| 07h | [DOS_UTL_ITOA](#numbers) | Converts a 32-bit number to a string |
| 08h | [DOS_UTL_ATOI16](#numbers) | Converts a string to a validated 16-bit number |
| 09h | [DOS_UTL_ATOI32](#numbers) | Converts a string to a 32-bit number |
| 0Ah | [DOS_UTL_ATOI32D](#numbers) | Converts a decimal string to a 32-bit number |
| 0Bh | [DOS_UTL_TOKEN1](#parsing) | Splits a string into whitespace-separated tokens |
| 0Ch | [DOS_UTL_TOKEN2](#parsing) | Splits a string into BASIC tokens |
| 0Dh | [DOS_UTL_TOKID](#parsing) | Looks up a token in a sorted token table |
| 0Eh | [DOS_UTL_PARSESW](#parsing) | Parses command-line switches |
| 0Fh | [DOS_UTL_GETDEV](#devices) | Returns the driver header for a device name |
| 10h | [DOS_UTL_GETCSN](#sessions) | Returns the current session number |
| 11h | [DOS_UTL_LOAD](#sessions) | Loads a program into a new session |
| 12h | [DOS_UTL_START](#sessions) | Starts a session |
| 13h | [DOS_UTL_STOP](#sessions) | Stops a session (not implemented yet) |
| 14h | [DOS_UTL_END](#sessions) | Ends the current program in a session |
| 15h | [DOS_UTL_WAITEND](#sessions) | Waits for all programs in a session to end |
| 16h | [DOS_UTL_YIELD](#scheduling) | Lets another session run |
| 17h | [DOS_UTL_SLEEP](#scheduling) | Sleeps for a number of milliseconds |
| 18h | [DOS_UTL_SOUND](#sound) | Plays a sound for a number of clock ticks |
| 19h | [DOS_UTL_WAIT](#scheduling) | Waits on an ID |
| 1Ah | [DOS_UTL_ENDWAIT](#scheduling) | Ends a wait on an ID |
| 1Bh | [DOS_UTL_HOTKEY](#scheduling) | Notifies DOS of a hotkey (used by the CON driver) |
| 1Ch | [DOS_UTL_LOCK](#scheduling) | Locks the current session (disables session switches) |
| 1Dh | [DOS_UTL_UNLOCK](#scheduling) | Unlocks the current session |
| 1Eh | [DOS_UTL_QRYMEM](#memory) | Returns information about a memory block |
| 1Fh | [DOS_UTL_TERM](#programs) | Terminates the program with an exit code and type |
| 20h | [DOS_UTL_RESTART](#programs) | Restarts the system |
| 21h | [DOS_UTL_GETDATE](#date-and-time) | Returns the date, including a packed date |
| 22h | [DOS_UTL_GETTIME](#date-and-time) | Returns the time, including a packed time |
| 23h | [DOS_UTL_INCDATE](#date-and-time) | Advances a date by one day |
| 24h | [DOS_UTL_EDITLN](#console) | Reads an edited line of console input |

### Strings

**DOS_UTL_STRLEN (00h)**: DS:SI -> null-terminated string.  Returns AX = length.

**DOS_UTL_STRSTR (01h)**: CS:SI -> null-terminated string to find (in the caller's code segment), ES:DI -> null-terminated string to search.  On a match, carry is clear and DI is updated to the position of the match; otherwise, carry is set.

**DOS_UTL_STRUPR (02h)**: DS:SI -> string, CX = length (0 if null-terminated).  Converts the string to upper case.

### Formatted Output

**DOS_UTL_PRINTF (03h)** prints to STDOUT, using a format string stored in the code segment immediately after the INT 32h instruction (DOS skips over it when returning).  All other parameters are pushed on the stack from right to left, and removed by the caller after the call (eg, with ADD SP,N*2).  Returns AX = # of characters printed.  The PRINTF macro takes care of all of this:

	PRINTF	<"%d files, %ld bytes",13,10>,cx,ax,dx

**DOS_UTL_HPRINTF (04h)** is the same, but prints to the system file handle (SFH) in BL.

**DOS_UTL_DPRINTF (05h)** is the same, but prints to the DEBUG device (see [DEBUG=](../../bdman/cfg/#debug)), and the format string is preceded by a one-byte option code; the message is printed only if the option code matches the boot key (eg, an upper-case boot key `T` enables messages with option code `t`), and only by a DEBUG build of BASDOS.COM.  The DPRINTF macro generates these calls, in DEBUG builds only.

**DOS_UTL_SPRINTF (06h)**: DS:BX -> format string, ES:DI -> output buffer, CX = buffer length, and parameters pushed as above.  Returns AX = # of characters generated.

Supported format specifiers include:

| Specifier | Parameter |
|-----------|-----------|
| `%c` | 8-bit character |
| `%d`, `%bd`, `%ld` | Signed 16-bit, 8-bit, or 32-bit decimal integer |
| `%u`, `%bu`, `%lu` | Unsigned 16-bit, 8-bit, or 32-bit decimal integer |
| `%x`, `%bx`, `%lx` | Unsigned 16-bit, 8-bit, or 32-bit hexadecimal integer (DEBUG builds only) |
| `%s`, `%ls` | String (near DS-relative pointer, or far pointer) |
| `%f` | Double, formatted by the FPU$ driver; the parameter is a far pointer to the double |
| `%W`, `%F`, `%M`, `%D`, `%X`, `%Y` | Day of week, month name, month, day, 2-digit year, and 4-digit year of a packed date |
| `%U` | Skips one 16-bit parameter |

Specifiers also support the `#` and `-` flags, a width, and a precision (eg, `%-10.4s`).  32-bit values are passed as two 16-bit parameters, low word first (as in the PRINTF example above, where AX is the low word of `%ld`).

### Numbers

**DOS_UTL_ITOA (07h)**: DX:SI = value, BL = base, BH = flags (PF_*, eg, PF_HASH to print a space instead of a minus sign for non-negative values), CX = minimum length (0 for none), ES:DI -> buffer.  Returns AL = # of digits, and DI advanced.

**DOS_UTL_ATOI16 (08h)**: DS:SI -> string, BL = base, ES:DI -> validation triplet of 16-bit (default, minimum, maximum) values, or DI = -1 for no validation.  Returns AX = value, with SI advanced past the first non-digit and DI advanced to the next triplet, making it easy to parse a series of values; carry is set on a validation error (and AX is the default value).

**DOS_UTL_ATOI32 (09h)**: DS:SI -> string, CX = length (-1 if unknown), BL = base.  Returns DX:AX = value, with SI pointing to the first unprocessed character; carry is set if there were no digits.

**DOS_UTL_ATOI32D (0Ah)**: Same as DOS_UTL_ATOI32 with BL = 10 and CX = -1, without using BX or CX.

### Parsing

**DOS_UTL_TOKEN1 (0Bh)** and **DOS_UTL_TOKEN2 (0Ch)**: CL = string length, DS:SI -> string, ES:DI -> token buffer (TOKBUF; see parser.inc).  TOKEN1 returns only tokens separated by whitespace (or the switch character), while TOKEN2 parses BASIC syntax and returns all tokens, including whitespace.  Returns carry clear and AX = # of tokens if any were found.

**DOS_UTL_TOKID (0Dh)**: CX = token length, DS:SI -> token, CS:DX -> token table (TOKTBL, followed by TOKDEFs sorted by name).  Returns carry clear, AX = token ID, and SI -> the TOKDEF if found; otherwise, carry set and AX = 0.

**DOS_UTL_PARSESW (0Eh)**: DL = first token to parse, DH = # of non-switch tokens to ignore, ES:DI -> TOKBUF.  Sets a bit in PSP_DIGITS or PSP_LETTERS (see [PSP](../data/#psp)) for each switch character found (eg, `/P` sets the bit for P), and returns DL = first non-switch token.

### Devices

**DOS_UTL_GETDEV (0Fh)**: DS:DX -> device name.  Returns ES:DI -> device driver header, or carry set if not found.

### Sessions

**DOS_UTL_GETCSN (10h)**: Returns CL = current session number.

**DOS_UTL_LOAD (11h)**: ES:BX -> Session Parameter Block (see [SPB](../data/#spb)), which specifies the command line and the standard handles for the new session.  Loads the program into an available session; returns CL = session number, or carry set and AX = error code.

**DOS_UTL_START (12h)**: CL = session number.  Marks the session startable; it starts running at the next session switch.

**DOS_UTL_STOP (13h)**: CL = session number.  Not implemented yet.

**DOS_UTL_END (14h)**: CL = session number.  Ends the current program in the session.

**DOS_UTL_WAITEND (15h)**: CL = session number.  Waits for all programs in the session to end.

### Scheduling

**DOS_UTL_YIELD (16h)**: Lets another session run, if one is ready.

**DOS_UTL_SLEEP (17h)**: CX:DX = # of milliseconds to sleep.

**DOS_UTL_WAIT (19h)**: DX:DI = wait ID (typically the address of a request packet).  Marks the current session as waiting until another caller (typically a driver's interrupt handler) calls DOS_UTL_ENDWAIT with the same ID.  Carry is set if the wait was interrupted (eg, by CTRL-C or CTRL-ALT-DEL), in which case the caller must clean up whatever it was waiting on.

**DOS_UTL_ENDWAIT (1Ah)**: DX:DI = wait ID.  Makes any session waiting on the ID runnable again; carry is set if no session was waiting.

**DOS_UTL_HOTKEY (1Bh)**: CX = console context, DL = character code, DH = scan code.  Used by the CON driver to notify DOS of CTRL-C, CTRL-P, and CTRL-ALT-DEL.

**DOS_UTL_LOCK (1Ch)**: Locks the current session, so that no session switch occurs until DOS_UTL_UNLOCK is called.  Returns AX = the console context of the current session (0 if none).

**DOS_UTL_UNLOCK (1Dh)**: Unlocks the current session, performing any session switch that was deferred while it was locked.

### Memory

**DOS_UTL_QRYMEM (1Eh)**: Returns information about a memory block.

Inputs:

- CX = memory block # (0-based)
- DL = block type: 0 for any block, 1 for free blocks, 2 for used blocks, or 3 for the highest free block (CX is ignored)

Outputs (carry clear if a block was found; carry set if there are no more blocks of the requested type):

- BX = segment
- AX = owner (eg, a PSP segment, or 0 if free)
- DX = size, in paragraphs
- ES:DI -> name of the owning program or block type, if any

With DL = 3, BX + DX is the highest free paragraph + 1, which is useful for storing data that can be recreated if it's overwritten.  For example, COMMAND.COM keeps a copy of its transient portion there while a program runs.  Since the block remains free, another session can allocate it at any time, so a caller should use DOS_UTL_LOCK and DOS_UTL_UNLOCK around any code that writes to the block or relies on its contents (eg, from the query through the copy, and from verifying the copy's checksum through copying it back).

The MEM /D command (in DEBUG builds) uses this function to list memory blocks.

### Programs

**DOS_UTL_TERM (1Fh)**: DL = exit code, DH = exit type (see [Exit Types](../dos/#exit-types)).  Terminates the current program.

**DOS_UTL_RESTART (20h)**: Writes any modified disk buffers and restarts the system.

### Date and Time

**DOS_UTL_GETDATE (21h)**: Same outputs as DOS_MSC_GETDATE (CX = year, DH = month, DL = day, AL = day of week), plus AX = packed date: bits 15-9 = year - 1980, bits 8-5 = month, bits 4-0 = day.  Carry is unchanged.

**DOS_UTL_GETTIME (22h)**: Same outputs as DOS_MSC_GETTIME (CH = hours, CL = minutes, DH = seconds, DL = hundredths), plus AX = packed time: bits 15-11 = hours, bits 10-5 = minutes, bits 4-0 = seconds / 2.  Carry is unchanged.

**DOS_UTL_INCDATE (23h)**: CX = year, DH = month, DL = day.  Returns the date advanced by one day.

### Console

**DOS_UTL_EDITLN (24h)**: DS:DX -> input buffer, as for DOS_TTY_INPUT, and AL = options: bit 0 returns AX = the last editing action, so that the caller can respond to keys like **Up** and **Down** (eg, for command history), and bit 1 displays the buffer's existing characters (INP_CNT) first, as if they had been recalled, so that they can be edited (COMMAND.COM uses this for AUTO and EDIT).  Otherwise, it's the same as DOS_TTY_INPUT.

### Sound

**DOS_UTL_SOUND (18h)**: CX = # of clock ticks, DX = PIT divisor for the frequency (1193182 / frequency), or 0 to turn the sound off.  Starts the sound and returns immediately; the CLOCK$ driver turns the sound off after the specified number of ticks.

{% include footer.html prev="DOS Functions:../dos/" next="Device Drivers:../dev/" %}
