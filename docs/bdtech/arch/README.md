---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Architecture
permalink: /docs/bdtech/arch/
---

{% include header.html %}

### Components

BASIC-DOS consists of a boot sector and three files, which must be in the root directory of the startup diskette:

| File | Contents |
|------|----------|
| (boot sector) | Loads the other files and starts the drivers |
| BASDEV.COM | Built-in device drivers, followed by their initialization code (devinit) |
| BASDOS.COM | The DOS kernel, followed by its initialization code (sysinit) |
| COMMAND.COM | The BASIC-DOS Command Processor (the default SHELL) |

The startup diskette may also contain CONFIG.SYS (see [Configuring BASIC-DOS](../../bdman/cfg/)) and HELP.TXT (used by the HELP command).

Unlike PC DOS, there is no separate BIOS-level file (IO.SYS or IBMBIO.COM); BASIC-DOS relies on the ROM BIOS for low-level services, and its device drivers fill the role of IBMBIO.COM.  The initialization code at the end of BASDEV.COM and BASDOS.COM is discarded once it's done, and its memory is reused.

### Boot Process

The boot sector runs in three parts:

1. Part 1 copies the BIOS diskette parameter table (DPT) to low memory (522h) so its values can be tuned, and moves the boot sector to low memory (550h).  If a hard disk is present, it displays "Press a key to start..." and waits; **Esc** boots from the hard disk instead.  The key pressed is saved in BOOT_KEY (52Dh).  It then finds BASDEV.COM, BASDOS.COM, and CONFIG.SYS in the root directory.
2. Part 2 loads BASDEV.COM at BIOS_END (960h), hops over its driver headers to find the devinit code that follows them, and calls it.  Devinit reads CONFIG.SYS (to honor any SKIP= line), chains the driver headers together, and sends each driver a DDC_INIT request; each driver reports how much memory it needs, so the drivers end up packed together, and skipped drivers take no memory.
3. Part 3 loads BASDOS.COM above the drivers and jumps to sysinit, passing it the CONFIG.SYS data.

Sysinit then:

- Processes SWITCHAR= and MEMSIZE=, and records the boot key (or BOOTKEY=)
- Allocates the Session Control Block table (SESSIONS=) and the System File Block table (FILES=), along with the BPBs, the current directory table, and any extra disk buffers (BUFFERS=)
- Opens a CON context for each CONSOLE= line (or a single default context), and opens AUX and PRN
- Opens the DEBUG= device, if any, and obtains the FPU$ function table (FPUTBL), if the FPU$ driver is present
- Revectors the DDINT_ENTER, DDINT_LEAVE, and DDINT_UTIL entry points (530h-53Fh) used by driver interrupt handlers
- Prints the startup banner, and for each SHELL= line (or the default, COMMAND.COM), loads the program into the next session with DOS_UTL_LOAD and starts it with DOS_UTL_START

Successive loads of the same program (eg, COMMAND.COM in several sessions) are served from a cached copy of the file, so the disk is read only once.

### Memory Layout

| Address | Contents |
|---------|----------|
| 0000h | Interrupt vector table |
| 0400h | ROM BIOS data area |
| 0500h | BASIC-DOS low memory data: drive info, device list head (50Ah), DPT (522h), BOOT_KEY (52Dh), DDINT entry points (530h) |
| 0540h | First disk buffer (16-byte header and 512-byte sector; initially the FAT sector the boot code read) |
| 0750h | Second disk buffer (header and 512-byte sector) |
| 0960h | BIOS_END: device drivers (BASDEV.COM), followed by the DOS kernel (BASDOS.COM) |
| | Resident tables: SCBs, BPBs, current directories, SFBs, and any extra disk buffers (BUFFERS=) |
| | Memory arena: MCB chain (programs, COMMAND.COM blocks, and free memory) |

All the disk buffers form a circular chain, ordered from most to least recently used.  Each buffer holds a FAT sector or a directory sector (file data goes directly through the disk drivers), and when a sector isn't already in a buffer, the least recently used buffer is reused, except that the most recently used buffer of the other kind (FAT or directory) is never reused, so that DOS can keep working with a directory entry while it updates the FAT (and vice versa).

The memory arena is a chain of Memory Control Blocks (see [MCB](../data/#mcb)), as in PC DOS.  [DOS_MEM_ALLOC](../dos/#memory) normally allocates from the bottom of the first free block that's big enough, but with MCBTYPE_HIGH (80h) set in AL, it allocates from the top of the last one.  COMMAND.COM allocates its code, text, variable, and string blocks from the top, so that the memory it frees before running a program stays contiguous.

Unlike PC DOS, BASIC-DOS doesn't give a program all available memory: a COM program gets its file size plus a heap (at least MINHEAP, or 1K, or more if the program requests it; see [COMDATA](../data/#comdata)), and an EXE program gets its image size plus the minimum its header requests (EXE_PARASMIN), rather than the maximum (EXE_PARASMAX).  This leaves memory available for other sessions.

### Sessions

Each session is described by a Session Control Block (see [SCB](../data/#scb)), which records the session's console context, standard file handles, current PSP, stack, DTA, CTRL-C and exit handlers, and wait state.

Sessions are scheduled preemptively: hardware interrupt handlers (eg, the CLOCK$ driver's timer handler) exit through DDINT_LEAVE, which can switch to another runnable session.  A session that's waiting for something (eg, keyboard input or a timer) calls DOS_UTL_WAIT with a wait ID, which makes it non-runnable until a driver calls DOS_UTL_ENDWAIT with the same ID.

Code that must not be interrupted by a session switch can use DOS_UTL_LOCK and DOS_UTL_UNLOCK; a switch requested while the session is locked is deferred until it's unlocked.

Each session has its own console context (if it was given one by a CONSOLE= line), and keyboard input goes to the context with focus (Shift-Tab switches the focus).  Sessions without a console of their own (eg, the sessions that run the commands of a pipeline) use the handles supplied in their Session Parameter Block (see [SPB](../data/#spb)).  A zero-length write to a pipe marks the end of its data (a reader then gets 0 bytes once the pipe is empty); the command processor does this after the first command of a pipeline, and when a session ends, DOS does the same to its output handle if it's a character device, so every command of a pipeline sees the end of its input.  Similarly, a zero-length read from a pipe means that its reader is done, and when a session ends, DOS does that to its input handle if it's a character device; from then on, writes to the pipe fail (with a write fault) instead of waiting for room.

### Interrupt Vectors

| Vector | Use |
|--------|-----|
| 00h, 04h | Divide error and overflow: the program is terminated (exit types EXTYPE_DVERR and EXTYPE_OVERR) |
| 01h, 03h | Single-step and breakpoint (used by DEBUG builds) |
| 20h | Terminate program |
| 21h | DOS functions (see [DOS Functions](../dos/)) |
| 22h | Exit address |
| 23h | CTRL-C handler address |
| 24h | Critical error handler address (critical error handling isn't implemented yet) |
| 25h, 26h | Absolute disk read and write (not implemented yet) |
| 27h | Terminate and stay resident (not implemented yet) |
| 28h | Idle notification (default handler only) |
| 29h | Fast console output (installed by the CON driver) |
| 2Ah-2Fh | Reserved (default handlers only) |
| 30h | CALL 5 far jump (overlaps vector 31h) |
| 32h | BASIC-DOS utility functions (see [Utility Functions](../util/)) |

Programs should use DOS_MSC_SETVEC (25h) to set vectors 22h, 23h, and 24h, which BASIC-DOS stores in the current session's SCB, rather than writing the vector table directly.

{% include footer.html prev="Contents:../" next="DOS Functions:../dos/" %}
