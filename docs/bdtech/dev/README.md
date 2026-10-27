---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Device Drivers
permalink: /docs/bdtech/dev/
---

{% include header.html %}

BASIC-DOS device drivers use PC DOS-style driver headers and request packets, with some simplifications and extensions.  All built-in drivers are in BASDEV.COM; installable drivers can also be loaded with DEVICE= (see [Installable Drivers](#installable-drivers)).

### Driver Headers

Each driver begins with a Device Driver Header (DDH):

| Offset | Field | Description |
|--------|-------|-------------|
| 00h | DDH_NEXT_OFF | Offset of the next DDH (FFFFh if none) |
| 02h | DDH_NEXT_SEG | Segment of the next DDH |
| 04h | DDH_ATTR | Device attributes (DDATTR_*) |
| 06h | DDH_REQUEST | Offset of the request entry point |
| 08h | DDH_INTERRUPT | Unused (-1) |
| 0Ah | DDH_NAME | Device name (8 characters, padded with spaces) |

Unlike PC DOS drivers, which have separate STRATEGY and INTERRUPT entry points, a BASIC-DOS driver has a single REQUEST entry point that performs the request immediately.  (PC DOS always called a driver's INTERRUPT routine right after its STRATEGY routine anyway.)

Device attributes:

| Value | Name | Meaning |
|-------|------|---------|
| 0001h | DDATTR_STDIN | Standard input device |
| 0002h | DDATTR_STDOUT | Standard output device |
| 0004h | DDATTR_NUL | NUL device |
| 0008h | DDATTR_CLOCK | Clock device |
| 0800h | DDATTR_OPEN | Supports DDC_OPEN and DDC_CLOSE |
| 4000h | DDATTR_IOCTL | Supports IOCTL requests |
| 8000h | DDATTR_CHAR | Character device (clear for a block device) |

In BASDEV.COM, each driver's DDH_NEXT_OFF initially contains the driver's length, and DDH_REQUEST initially points to its initialization code.  Devinit uses the lengths to find each driver, sends it a DDC_INIT request, and chains the headers together.  The driver's INIT handler sets DDH_REQUEST to its real request handler and returns the end of its resident code in DDPI_END, so that its initialization code is discarded.  For example, the entire NUL driver is:

	NUL	DDH	<offset DEV:ddnul_end+16,,DDATTR_CHAR,offset ddnul_init,-1,20202020204C554Eh>

	DEFPROC	ddnul_req,far
		ret
	ENDPROC	ddnul_req

	DEFPROC	ddnul_init,far
		mov	es:[bx].DDPI_END.OFF,offset ddnul_init
		mov	cs:[0].DDH_REQUEST,offset DEV:ddnul_req
		ret
	ENDPROC	ddnul_init

The head of the driver chain is stored at 0:50Ah (DD_LIST), and DOS_UTL_GETDEV returns the header for a device name.

### Request Packets

DOS calls the REQUEST entry point with a far call, with ES:BX -> request packet.  Drivers don't need to preserve any registers.  Every packet begins with a 13-byte header (DDP):

| Offset | Field | Description |
|--------|-------|-------------|
| 00h | DDP_LEN | Length of the packet |
| 01h | DDP_UNIT | Unit # (block devices only) |
| 02h | DDP_CMD | Command (DDC_*) |
| 03h | DDP_STATUS | Status (DDSTAT_*) |
| 05h | DDP_CODE | IOCTL code, if an IOCTL request |
| 06h | DDP_CONTEXT | Device context, if any (eg, the console context of the session making the request) |
| 08h | DDP_PTR | Driver-specific pointer (eg, for DDC_OPEN, the device name and parameters, such as "VKD$:40,25") |
| 0Ch | DDP_SIG | Signature byte (DEBUG builds only) |

PC DOS defined only the first 5 bytes of the header; BASIC-DOS uses the rest to pass context information.  For example, DDC_OPEN returns a new context in DDP_CONTEXT, which DOS stores in the open file's SFB and passes back with every later request for that handle.

INIT requests use a DDPI packet, and for built-in drivers, DDP_PTR points to the CONFIG.SYS text (null-terminated, and empty if there's no CONFIG.SYS), so a driver can look for its own settings (eg, CPU$'s `CPU=PROBE`; see [Protected Mode](../mmu/#probe)):

| Offset | Field | Description |
|--------|-------|-------------|
| 0Dh | DDPI_UNITS | # of units (ie, drives) |
| 0Eh | DDPI_END | End of the driver's resident code (returned by the driver) |
| 12h | DDPI_BUFPTR | 512-byte scratch buffer (built-in drivers), or the DEVICE= arguments (installable drivers) |

All other requests use a DDPRW packet:

| Offset | Field | Description |
|--------|-------|-------------|
| 0Dh | DDPRW_ID | Media ID (block devices) |
| 0Eh | DDPRW_ADDR | Transfer address |
| 12h | DDPRW_LBA | Starting sector (or other position data, or IOCTL input) |
| 14h | DDPRW_OFFSET | Starting offset within the sector |
| 16h | DDPRW_LENGTH | Transfer length, in bytes (or IOCTL input); the driver returns the # of bytes not transferred |
| 18h | DDPRW_BPB | BPB for the unit (block devices only) |

Unlike PC DOS, DOS (not the driver) owns the BPBs for block devices: DOS passes the unit's BPB in DDPRW_BPB, and DDC_MEDIACHK and DDC_BUILDBPB requests ask the driver to validate and rebuild it.

Commands:

| Value | Name | Description |
|-------|------|-------------|
| 0 | DDC_INIT | Initialize |
| 1 | DDC_MEDIACHK | Media check (block devices); returns MC_UNCHANGED (1), MC_UNKNOWN (0), or MC_CHANGED (-1) in DDP_CONTEXT |
| 2 | DDC_BUILDBPB | Build BPB (block devices) |
| 3 | DDC_IOCTLIN | IOCTL request (devices with DDATTR_IOCTL) |
| 4 | DDC_READ | Read |
| 5 | DDC_NDREAD | Non-destructive read, no wait (character devices) |
| 6 | DDC_INSTATUS | Input status (character devices) |
| 7 | DDC_INFLUSH | Input flush (character devices) |
| 8 | DDC_WRITE | Write |
| 9 | DDC_WRITEV | Write with verify (not supported yet) |
| 10 | DDC_OUTSTATUS | Output status (character devices) |
| 11 | DDC_OUTFLUSH | Output flush (character devices) |
| 12 | DDC_IOCTLOUT | IOCTL output |
| 13 | DDC_OPEN | Open (devices with DDATTR_OPEN) |
| 14 | DDC_CLOSE | Close (devices with DDATTR_OPEN) |

On return, DDP_STATUS contains DDSTAT_DONE (0100h), plus DDSTAT_ERROR (8000h) and an error code in the low byte if the request failed.  Disk error codes are the BIOS (INT 13h) error codes (eg, 03h for write-protect, 80h for drive not ready), and the other codes use values the BIOS doesn't (eg, DDERR_UNKCMD, 06h, for an unknown command); see dev.inc for the complete list.  DOS reports a block device error to the session's critical error handler (see [Critical Errors](../dos/#critical-errors)), and if the response is RETRY, it reissues the same packet after clearing DDP_STATUS, so a driver that advances DDPRW_LBA, DDPRW_ADDR, and DDPRW_LENGTH as it goes (as FDC$ does) resumes at the failing sector.

Console drivers (VKD$ and COM) handle CTRL-C the same way, and only report it: they leave it in their input like any other character, and notify DOS with DOS_UTL_HOTKEY (except in [raw keys](#raw-keys) mode, where CTRL-C is just a key).  When DOS acts on a CTRL-C, it sends DDC_INFLUSH to the session's console, which discards its type-ahead (including the CTRL-C), and DDC_OUTFLUSH, which ends any CTRL-S pause (the COM driver also discards any output it has buffered, but an XOFF pause or a CTS hold still ends only when the terminal allows it).  DOS_TTY_FLUSH (INT 21h, AH = 0Ch) also sends DDC_INFLUSH, to STDIN.

To stop a program that never calls DOS, console drivers report an ABORT instead (DOS_UTL_HOTKEY with CTRL-D): the VKD$ driver does so for CTRL-ALT-DEL and CTRL-BREAK, and the COM driver does so when it receives a BREAK (a line status interrupt with LSR BI set).

A request that must wait (eg, a keyboard read with no key available) calls DOS_UTL_WAIT with the packet address as the wait ID, which lets other sessions run; the driver's interrupt handler later calls DOS_UTL_ENDWAIT with the same ID.  Interrupt handlers should begin with a far call to DDINT_ENTER (0:530h) and end with a far jump to DDINT_LEAVE (0:535h), which lets DOS switch sessions when the interrupt ends.

### IOCTL Functions

DOS_HDL_IOCTL (INT 21h, AH = 44h) sends IOCTL requests to drivers: AL is passed in DDP_CODE, CX in DDPRW_LENGTH, DX in DDPRW_LBA, and DS:SI in DDPRW_ADDR, and the result returned in DDP_CONTEXT is returned in DX.  For a volume handle (see [Files](../dos/#files)), the request goes to the drive's block driver, with the drive # in DDP_UNIT and the volume's BPB in DDPRW_BPB, and an error is returned to the caller rather than reported to the critical error handler (see [Critical Errors](../dos/#critical-errors)).  BASIC programs can send requests with the [IOCTL #](../../bdman/cmd/basic/#ioctl) statement.  In addition to the standard codes (00h-07h), BASIC-DOS defines these:

#### COM {#com}

| AL | Name | Description |
|----|------|-------------|
| 06h | IOCTL_INSTATUS | Returns the number of bytes waiting in the port's input buffer in DX (zero if none), which BASIC's [EOF](../../bdman/cmd/basic/func/#eof), [LOC](../../bdman/cmd/basic/func/#loc), and [INPUT$](../../bdman/cmd/basic/func/#input) functions use for a COM file. |
| B1h | IOCTL_COMDEBUG | Disables the port's UART interrupts, so that the caller can poll it, and returns the UART's base port in DX, OR'ed with COMDBG_XON (02h) and/or COMDBG_RTS (04h) if the port uses XON/XOFF or RTS/CTS flow control.  The handle must have been opened with MODE_DENY_RW (see [Device Sharing](#device-sharing)); otherwise, the error is ERR_ACCDENIED. |

#### CLOCK$ {#clock}

| AL | Name | Description |
|----|------|-------------|
| C1h | IOCTL_WAIT | Waits the number of milliseconds in DDPRW_LENGTH:DDPRW_OFFSET |
| C2h | IOCTL_SETDATE | Sets the date (CL = year - 1980 (0-127), DH = month, DL = day) |
| C3h | IOCTL_SETTIME | Sets the time (CH = hours, CL = minutes, DH = seconds, DL = hundredths) |
| C4h | IOCTL_GETDATE | Gets the date |
| C5h | IOCTL_GETTIME | Gets the time |
| C6h | IOCTL_SOUND | Plays a sound (DX = PIT divisor) for CX ticks |

#### VKD$ {#vkd}

| AL | Name | Description |
|----|------|-------------|
| D1h | IOCTL_GETDIM | Gets the context's dimensions |
| D2h | IOCTL_GETPOS | Gets the cursor position |
| D3h | IOCTL_GETLEN | Gets the displayed length of data (eg, with tabs expanded, and other control characters counted as two, since the DOS line editor displays them as "^" + char) |
| D4h | IOCTL_MOVCUR | Moves the cursor by DDPRW_LENGTH positions |
| D5h | IOCTL_SETINS | Sets INSERT mode on (CL = 1) or off (CL = 0) |
| D6h | IOCTL_SCROLL | Scrolls the interior of the context up (CX > 0) or down (CX < 0) by CX lines, or clears it (CX = 0) |
| D7h | IOCTL_GETCOLOR | Gets the fill (DL) and border (DH) colors |
| D8h | IOCTL_SETCOLOR | Sets the fill (CL) and border (CH) colors |
| D9h | IOCTL_SETPOS | Sets the cursor position (CL = column, CH = row) and visibility (DL) |
| DAh | IOCTL_GETMODE | Gets the video mode (DL) |
| DBh | IOCTL_SETMODE | Sets the video mode (CL) |
| DCh | IOCTL_GETCHAR | Gets the character (DL) and attributes (DH) at column CL, row CH (zero-based; see the SCREEN function) |
| DDh | IOCTL_SETKEYS | Sets raw keys mode on (CL = 1) or off (CL = 0); see [Raw Keys](#raw-keys) |

Changing the video mode (with IOCTL_SETMODE, or with INT 10h directly) turns the context into a full-screen, borderless context that uses INT 10h for output, so text output and scrolling work in graphics modes.  When the context returns to its original mode, its original geometry is restored.

While a context is in any mode other than its original mode (eg, a graphics mode, or 40-column text in an 80-column context), it occupies the entire screen, so every other context on the same adapter is blocked: its writes, and any IOCTL_SCROLL, IOCTL_SETCOLOR, or IOCTL_SETMODE request, wait (like a context paused with CTRL-S), and its border isn't drawn (eg, on a focus switch).  When that context returns to its original mode (or is closed, in which case its original mode is restored), the borders of the other contexts on the adapter are redrawn, and every blocked request continues.  Programs that call INT 10h directly from other sessions are not blocked.

The COM driver also supports IOCTL_GETDIM (it assumes an 80x24 terminal), IOCTL_GETPOS and IOCTL_GETLEN (columns only), IOCTL_MOVCUR, IOCTL_SETINS, IOCTL_GETCOLOR, IOCTL_SETCOLOR, and IOCTL_SETKEYS, so that the same programs work on serial consoles.  For ANSI and VT100 terminals, it also supports IOCTL_SETPOS (by sending ESC [ *row* ; *col* H; the cursor's visibility is ignored) and scrolling with IOCTL_SCROLL (by sending LINEFEEDs at the bottom row, or ESC M at the top row); GENERIC terminals support neither, so IOCTL_SETPOS fails, and IOCTL_SCROLL only clears the screen.

#### Raw Keys {#raw-keys}

Both console drivers return every non-ASCII key as a zero followed by the key's PC scan code (the SCAN_* values in bios.inc), as PC DOS does, so programs (eg, BASIC's INKEY$) don't need to know which driver they're using.  The DOS line editor (DOS_TTY_INPUT) maps the keys it uses for editing to the control characters that also edit (eg, the up-arrow key to CTRL-E, and the left-arrow key to CTRL-S), and ignores the others.  The COM driver translates the keys of a VT100 terminal (and in raw keys mode, an ANSI terminal) from these escape sequences:

| Key | Scan code | ANSI/VT100 sequences |
|-----|-----------|----------------------|
| Up, Down, Right, Left | 48h, 50h, 4Dh, 4Bh | ESC [ A-D, or ESC O A-D |
| Home, End | 47h, 4Fh | ESC [ H, ESC [ F (or ESC O H, ESC O F), or ESC [ 1 ~, ESC [ 4 ~ |
| Insert, Delete | 52h, 53h | ESC [ 2 ~, ESC [ 3 ~ |
| PgUp, PgDn | 49h, 51h | ESC [ 5 ~, ESC [ 6 ~ |
| F1-F4 | 3Bh-3Eh | ESC O P-S (the VT100's PF1-PF4), or ESC [ P-S |
| F5-F10 | 3Fh-44h | ESC [ 15 ~, ESC [ 17 ~ through ESC [ 21 ~ |

Modifier parameters (eg, the 5 in ESC [ 1 ; 5 A) are ignored, and other sequences are discarded.  Since an ESC key can't be distinguished from the start of a sequence until the next byte arrives, the driver holds an ESC until then, or for about 110ms (using a [CLOCK$ timer](#clock-timers)), after which it's returned as an ESC.  For VT100 terminals, the key that erases the previous character (DELETE, 7Fh) returns BACKSPACE (08h), and BACKSPACE returns the Delete key (00h, 53h), like the PC's keys; for ANSI terminals, both are returned as they are.  GENERIC terminals return bytes as they are.

All other keys are returned as their ASCII codes, including control characters.  In raw keys mode (IOCTL_SETKEYS with CL = 1), CTRL-C, CTRL-S, and CTRL-P are ordinary keys, too: they aren't reported to DOS (so DOS doesn't echo ^C or call INT 23h), and they don't pause or resume output; an ANSI terminal's escape sequences are translated, too (otherwise, they're left alone, since an ANSI port may be a program's data port, eg, COM1 in COMM.BAS).  CTRL-BREAK still aborts the program on a VKD$ console, SHIFT-TAB still switches focus, and a COM console with XON flow control still uses CTRL-S and CTRL-Q for flow control.  A program that sets raw keys mode should turn it off before it exits; if it doesn't (eg, if it's aborted), DOS turns it off for the session's console when the program ends (DOS records the last IOCTL_SETKEYS setting in the program's PSP, at PSP_RAWKEYS).

#### FPU$ {#fpu}

| AL | Name | Description |
|----|------|-------------|
| E1h | IOCTL_GETFPU | Stores a far pointer to the FPU function table at DS:SI; returns DL = # of table entries and DH = FPU type (see [Floating-Point Interface](../fpu/)) |

#### FDC$ {#fdc-ioctl}

| AL | Name | Description |
|----|------|-------------|
| F1h | IOCTL_SETPARMS | Copies the BPB at DS:SI (CX = its length, at least 21h bytes, eg, the BPB of a new boot sector) to the volume's BPB and initializes the rest of the BPB (as building it from the boot sector would), so that the volume of an unformatted diskette can be written; an unusable BPB is DDERR_UNKMEDIA, and too little data is DDERR_BADREQ |
| F2h | IOCTL_FORMAT | Formats and verifies the track at cylinder CX, head DX, with the sectors per track in the volume's BPB (the DPT's sectors per track and format gap are set accordingly, and on a PC AT, the media type is set with INT 13h function 17h), and then timestamps the BPB, so that the media check that follows treats the media as unchanged; errors are the BIOS error codes (eg, 03h for a write-protected diskette) |
| F3h | IOCTL_GETPART | Since diskettes have no partition table, stores only the drive's type, in one byte (DX = 1): 1 (360K), 2 (1.2M), 3 (720K), or 4 (1.44M), from INT 13h function 08h, or nothing (DX = 0) if the BIOS can't report it (eg, on a PC or XT); a hard disk's PARTINFO is longer (see HDC$ below), so FORMAT and DISKCOPY can tell a diskette from a hard disk |

#### HDC$ {#hdc-ioctl}

| AL | Name | Description |
|----|------|-------------|
| F1h | IOCTL_SETPARMS | As for FDC$, except that the BPB's geometry and location come from the volume table (as when the BPB is built from the boot sector) |
| F3h | IOCTL_GETPART | Reads the MBR of the unit's disk and stores a PARTINFO (see devapi.inc) at DS:SI (CX = the buffer's length, at least 74 bytes): the disk's cylinders (word), heads, sectors per track, and BIOS drive #, a flag that's 1 if the MBR has a valid signature, the drive letter of each of the 4 partitions (0 if it isn't a volume), and the 64-byte partition table; returns DX = 74 |
| F4h | IOCTL_SETPART | Writes a new MBR, consisting of the driver's MBR code, the 64-byte partition table at DS:SI, and the signature, to a disk that has no partitions (ie, the unit is the whole disk; otherwise, the error is DDERR_BADREQ), and then makes the unit the first FAT12 or FAT16 partition in the table, so that IOCTL_SETPARMS can initialize it |

The MBR code (mbr_code in hdcdev.asm) is modeled on the pc.js MBR (tools/pc/mbr.asm in the PCjs repository) without its drive tables: it moves itself to 7E00h, finds the active partition (rejecting a table with more than one active entry, or with any other status), loads its boot sector at 7C00h, verifies the signature, and jumps to it with SI pointing to the partition entry.

### Built-in Drivers

| Device | Type | Description |
|--------|------|-------------|
| VKD$ | Character | Video and keyboard driver: a console with a separate context for each session (see [CON=](../../bdman/cfg/#con)); interrupt-driven input, direct video output (or BIOS output), and INT 29h fast output |
| LPT1-LPT3 | Character | Parallel ports (one for each port the BIOS found): writes print with INT 17h, a failed write's error is also reported by the next IOCTL_OUTSTATUS (see LPRINT), and IOCTL_GETPOS returns the column (see LPOS) |
| COM1-COM4 | Character | Serial ports, with interrupt-driven, asynchronous I/O |
| CPU$ | Character | Loaded first: stores the processor type in CPU_TYPE (0:512h), and on an 80286 or later with at least 64K of extended memory, stays loaded to manage extended memory and protected-mode descriptors through DDINT_CPU (see [Protected Mode](../mmu/)); otherwise, it unloads itself |
| NUL | Character | Null device |
| CLOCK$ | Character | Timer interrupt, date and time, delays, and sound |
| PIPE$ | Character | Pipes between sessions (used by the command shell's `|` operator), with a 128-byte buffer; as on UNIX, a read waits only until some data is available, and then returns what's there (up to the requested length), while a write waits until all its data fits |
| FPU$ | Character | Floating-point functions, using an 8087 if present, or software emulation otherwise |
| MOUSE$ | Character | Serial mouse, with an INT 33h interface (see [MOUSE$](#mouse)); loaded only if a mouse responds on a COM port |
| FDC$ | Block | Diskette drives (A: and B:) |
| HDC$ | Block | Hard disks: FAT12 and FAT16 primary partitions of up to two BIOS hard disks (C:, D:, etc.), and a disk with no FAT partitions (eg, a new disk) as a single unit with unknown media, so that FORMAT can partition it; reads and writes are done by FDC$, so FDC$ must also be loaded |

Drivers that aren't needed (eg, VKD$ in a configuration that uses only serial consoles) can be omitted with [SKIP=](../../bdman/cfg/#skip).

CON, AUX, and PRN aren't drivers, but names that DOS gives the active session's console, AUX, and PRN devices (see [CON=](../../bdman/cfg/#con), [AUX=](../../bdman/cfg/#aux), and [PRN=](../../bdman/cfg/#prn)); opening one of those names (with or without a colon) shares the session's handle for that device (see [Files](../dos/#files)).

### CLOCK$ Timers {#clock-timers}

Drivers that need to do something after a delay (eg, the COM driver, to decide that a held ESC is just an ESC) use CLOCK$ timers instead of hooking the timer interrupt.  CLOCK$ exports a far entry point immediately after its device header (CLKX in dev.inc), and DEVINIT records the CLOCK$ header in CLOCK_DEVICE (0:50Eh), so a driver can find it at any time after initialization (CLOCK_DEVICE.SEG is zero if CLOCK$ isn't loaded).

CLKX_TIMER takes ES:DI pointing to a TMR structure (owned by the caller, with TMR_FUNC set to a far function) and CX = milliseconds, which are rounded up to whole clock ticks (the first of which may be partial); CX = 0 cancels the timer, and starting a timer that's already running restarts it.  It can be called from interrupt handlers.  When the timer expires, CLOCK$ removes it and calls TMR_FUNC from its timer interrupt handler (after DDINT_ENTER, so it can call DOS_UTL_ENDWAIT), with ES:DI pointing to the TMR and interrupts disabled; the function may modify any registers except SS:SP and BP.

FDC$ and HDC$ share one copy of the INT 13h read and write code (including the handling of multi-track transfers and of transfers that would cross a 64K DMA boundary) and one sector buffer, all in FDC$.  FDC$ exports three far entry points immediately after its device header (FDCX in dev.inc): FDCX_RW performs a DDC_READ or DDC_WRITE request for the BIOS drive number in AL, FDCX_RDBUF reads a sector into the shared buffer (eg, a volume's boot sector, when HDC$ builds its BPB), and FDCX_MBR reads or writes a hard disk's MBR using the shared buffer (or simply returns the buffer, for HDC$ to build an MBR in).  HDC$ finds FDC$ through FDC_DEVICE (which DEVINIT records before initializing HDC$), and if FDC$ isn't loaded (eg, `SKIP=FDC$`), HDC$ doesn't load either.  The shared code takes the volume's geometry from its BPB, and for hard disks, adds BPB_HIDDENSECS (the volume's first sector) to every sector number.  For diskettes, it also sets the Diskette Parameter Table's sectors per track from the BPB before every transfer (the boot code moves the DPT to RAM, at 0:522h), since the BIOS stops a transfer at that sector and the ROM's value may not match the media (eg, 8-sector diskettes).  FDC$ also supports two IOCTL requests for formatting (see [FDC$](#fdc-ioctl) above), which FORMAT.BAS uses.

HDC$ recognizes partition types 01h (FAT12) and 04h (FAT16), with 512-byte sectors and fewer than 65,536 sectors per volume (just under 32MiB). The FAT entry width is determined from the data-cluster count, not the partition label. FAT16 booting, reading, and writing use the same sector buffers as FAT12; the entire FAT does not have to fit in memory. Larger volumes, FAT32, and extended partitions are not supported.

The 30Mb FAT16 source disk created by `mk.sh` (`--target=30M --fat=16:2048:512`) is within these limits. When attaching an existing pc.js image, the emulated controller and BIOS must use the image's geometry.

### MOUSE$ {#mouse}

At boot, MOUSE$ looks for a Microsoft-compatible serial mouse on each COM port listed in the BIOS data area: it sets the port to 1200 baud (7 data bits, no parity, 1 stop bit), turns DTR and RTS off for 2 timer ticks, turns them back on, and waits up to 3 ticks for the mouse to send an "M".  If no port responds, the port's settings are restored, and the driver isn't installed.  Otherwise, MOUSE$ takes over the port's hardware interrupt (IRQ4 for ports 3xxh, IRQ3 for ports 2xxh), so that port shouldn't also be used as a COM device, and hooks INT 33h and INT 10h.  On a machine with no mouse, probing adds a fraction of a second to the boot, which `SKIP=MOUSE$` avoids.

Positions are virtual coordinates (640x200 in every mode), with one mickey per horizontal pixel and two per vertical pixel.  The pointer is drawn only in MDA and CGA modes: text modes 0-3 and 7 invert the attribute of a character cell, and graphics modes 4-6 draw an 8x12 arrow.  Erasing the pointer restores only the bits that the pointer changed and that still have the pointer's values, so anything drawn on top of the pointer is preserved.  The pointer is also hidden around INT 10h calls that may change the screen (anything other than functions 01h-03h and 0Fh), except for character writes (functions 09h and 0Ah) in graphics modes that don't overlap the pointer, since erasing and redrawing the pointer is slow; and after a mode change (function 00h), the mode is determined again (with function 0Fh, which the CON driver answers for the caller's session).

| AX | Function | Description |
|----|----------|-------------|
| 00h | Reset | Hides the pointer, centers it, resets the limits, empties the event queue, and determines the video mode; returns AX = FFFFh and BX = 2 (buttons) |
| 01h | Show pointer | Decrements the hide count; when it reaches zero, determines the video mode and draws the pointer (or moves it, if function 10h left it on the screen) |
| 02h | Hide pointer | Increments the hide count and erases the pointer |
| 03h | Get position | Returns BX = buttons (bit 0 = left, bit 1 = right), CX = x, DX = y |
| 04h | Set position | CX = x, DX = y |
| 07h | Set x limits | CX = minimum, DX = maximum |
| 08h | Set y limits | CX = minimum, DX = maximum |
| 10h | Conditional off | CX, DX = upper left, SI, DI = lower right; like function 02h, increments the hide count, but in graphics modes, the pointer is erased only if it overlaps the area (otherwise, it stays on the screen, and doesn't move until the next function 01h) |
| BDh | Get event (BASIC-DOS) | If BX = 0, removes the next button event from the queue (up to 8 are saved) and returns AX = event (1 = left pressed, 2 = left released, 3 = right pressed, 4 = right released), BX = buttons, and CX, DX = position at the time of the event; otherwise (or if there are no events), returns AX = 0 and the current buttons and position.  Positions are in screen units: pixels in graphics modes, or a column and row (starting at 1) in text modes |

Other functions are ignored.  The [MOUSE](../../bdman/cmd/device/mouse/) statement and function use functions 00h-02h and BDh.

### Device Sharing {#device-sharing}

A device can be opened any number of times, unless an open (DOS_HDL_OPEN, INT 21h AH = 3Dh) includes the MODE_DENY_RW (10h) sharing mode in AL: that open fails with ERR_SHARE if the device is already open, and while that handle remains open, every other open of the device fails with ERR_SHARE.  Other sharing modes are ignored for devices.

### Installable Drivers {#installable-drivers}

Each DEVICE= line in CONFIG.SYS loads a character device driver from a file: a single driver with no relocations, whose DDH is at offset 0, with DDH_NEXT_OFF set to FFFFh and DDATTR_CHAR set.  A dual-mode .COM file can instead put a JMP SHORT (EBh) in DDH_NEXT_OFF, which a program run from the prompt executes first.  DOS reads the entire file into memory, then calls DDH_REQUEST with a DDC_INIT request, where DDPI_BUFPTR points to the ASCIIZ arguments that follow the filename, and DDPI_END is preset to the end of the file.  INIT runs before any sessions exist, so the driver can open files and devices (it gets system file handles, since there's no PSP yet), but if it fails, it must close them and leave no interrupt vectors hooked.  If INIT succeeds, DOS releases any memory beyond DDPI_END.OFF and adds the driver to the head of the driver list; otherwise, DOS frees the driver and displays a warning with error 31 (general failure), and for any other failure, the warning includes the DOS error (eg, 2 if the file wasn't found, or 11 if it's not a valid driver).

DEBUG.COM (software/src/os/dd/dbg/dbgdev.asm) is a dual-mode example.  As a program, its JMP SHORT lands on its input buffer, whose initial contents (unused by the driver) jump to code past DDPI_END, so loading it as a driver costs no extra memory.  DOS names each installed driver's memory block after its device (eg, DEBUG$), and the block owns itself, so DEBUG's DM command lists it in address order.  As a driver, it null-terminates the COM descriptor at the start of its arguments, opens the COM port with MODE_DENY_RW, switches it to polling with IOCTL_COMDEBUG (which also frees the port's context, since the debugger does its own I/O; the exclusive handle still reserves the port), and then hooks INT 01h, INT 03h, and the port's hardware interrupt, enabling only the UART's receive and line status interrupts, so that a Ctrl-C or BREAK stops the machine as soon as it arrives (other input is discarded, and an interrupt from another port sharing the IRQ is passed on).  Its DEBUG$ device also accepts OPEN, CLOSE, and WRITE requests, sending written data to the port, so sysinit opens it (if installed) for DPRINTF messages.  When the monitor stops on an INT 3 that is neither a breakpoint nor a DBGBRK (an INT 3 preceded by a NOP), it displays "Assertion failure" before the registers.  Any switches that follow the descriptor are monitor commands: INIT changes its final RET to an INT 3 and redirects get_line's one call to get_char to a routine that returns the text of each switch as a line (ended by the next switch char), and then a G, unless one of the switches was /H, in which case it reads the port; either way, the routine restores the call at the end of the last line, since it isn't resident (so a /G, which would resume INIT before then, is ignored).  Its monitor never calls DOS, since it may have interrupted DOS, so it polls the UART instead.  On entry, it copies the interrupted registers from the interrupted stack, and when it resumes, it copies them back below the (possibly changed) SS:SP before the IRET.  Breakpoints are INT 3 instructions that are written only while running: the monitor restores the original bytes on entry (backing up IP if one was hit), and G single-steps past any breakpoint at CS:IP before writing them.  The disassembler decodes each instruction twice, first with output muted to find its length, so that the bytes can be displayed before the mnemonic.  In program mode, a program named on the command line is loaded with DOS_PSP_EXEC1 (load without starting), which returns its initial SS:SP (with AX on top of the stack) and CS:IP in the EPB and leaves its PSP current; DEBUG then enters its monitor as if the program's first instruction had been interrupted, so G simply resumes it.  The program's termination returns to the instruction after the EXEC1 call (see PSP_EXIT), as does Q, which terminates the program with DOS_PSP_RETURN while its PSP is still current; DEBUG then exits with the program's exit code (DOS_PSP_RETCODE).  Without a program, DEBUG stores a RET at PSP:0100h (over its JMP SHORT, which has done its job), so G pops the zero that DOS pushed on the stack and runs the INT 20h at PSP:0000h; DOS then restores INT 01h and INT 03h, as it would for any program that terminates with them hooked.  A switch on the command line (eg, `/DM`) is copied to the command buffer, and DEBUG, without hooking INT 01h and INT 03h (so that a dump shows their vectors as they are), patches its monitor to perform that command in place of displaying the registers, and to exit in place of prompting for another.

{% include footer.html prev="Utility Functions:../util/" next="Floating-Point Interface:../fpu/" %}
