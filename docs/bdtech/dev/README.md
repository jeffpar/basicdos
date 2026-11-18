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
| 08h | DDH_DATA | The driver's data segment (or in protected mode, its data selector), which devinit (or the kernel, for a DEVICE= driver) stores before initializing it |
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
		mov	es:[bx].DDPI_END._OFF,offset ddnul_init
		mov	ds,cs:[0].DDH_DATA
		mov	ds:[0].DDH_REQUEST,offset DEV:ddnul_req
		ret
	ENDPROC	ddnul_init

A driver never writes through CS: whenever it writes to its own memory (eg, DDH_REQUEST above, or its variables in a request or interrupt handler), it loads DS (or ES) from DDH_DATA, as above.  In real mode, that's the driver's own segment; in protected mode, CS is the driver's code selector and DDH_DATA is a separate data selector for the same memory (see [Protected-Mode Initialization](../mmu/#pminit)).  Far pointers to a driver's code (eg, vectors and DDH_NEXT_SEG) use CS, and far pointers to its data use DDH_DATA.  An empty chain's far pointer (eg, a driver's list of waiting packets) is FFFFh:0000h, not -1:-1, so that loading it into a segment register before checking the offset is safe in protected mode.

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

INIT requests use a DDPI packet, and for built-in drivers, DDP_PTR points to the CONFIG.SYS text (null-terminated, and empty if there's no CONFIG.SYS), so a driver can look for its own settings (eg, CPU$'s `CPU=8088`; see [Protected Mode](../mmu/)):

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
| 14h | DDPRW_OFFSET | Starting offset within the sector (always zero for DDC_READ, since DOS reads partial sectors through its disk buffers, so a read is always for whole sectors) |
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

A request that must wait (eg, a keyboard read with no key available) calls DOS_UTL_WAIT with the packet address as the wait ID, which lets other sessions run; the driver's interrupt handler later calls DOS_UTL_ENDWAIT with the same ID.  Interrupt handlers should begin with a far call to DDINT_ENTER (0050:003Fh) and end with a far jump to DDINT_LEAVE (0050:0044h), which lets DOS switch sessions when the interrupt ends.  The DDINT entry points (at 530h) are called through segment 50h, which in protected mode is also a code selector for the same memory, so their addresses are the same in either mode.

Drivers read and write interrupt vectors with far calls to DDINT_GETVEC (0050:0035h) and DDINT_SETVEC (0050:003Ah), rather than addressing the vector table with segment 0, which isn't a valid selector in protected mode.  Both take the vector number in AL and pass vectors in DX:CX (segment:offset), not in a segment register, since a vector's segment isn't necessarily a valid selector either: DDINT_GETVEC returns the vector in DX:CX, and DDINT_SETVEC sets the vector to DX:CX (with interrupts disabled) and returns the previous one in DX:CX, so hooking a vector takes one call.  They modify only CX and DX.  CPU$ provides them, before any other driver initializes: the 8086 driver's read and write the vector table, and the 80386 driver's, from the moment it switches to protected mode, read and write its IDT (see [Protected-Mode Interrupts](../mmu/#interrupts)).  The kernel uses them too (eg, for DOS functions 25h and 35h).

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
| C0h | IOCTL_CLOCK | Returns DX = 1 if the date came from a real-time clock or PCjs, or 0 if not (eg, on a PC or PC XT) |
| C1h | IOCTL_WAIT | Waits the number of milliseconds in DDPRW_LENGTH:DDPRW_OFFSET |
| C2h | IOCTL_SETDATE | Sets the date (CL = year - 1980 (0-127), DH = month, DL = day) |
| C3h | IOCTL_SETTIME | Sets the time (CH = hours, CL = minutes, DH = seconds, DL = hundredths) |
| C4h | IOCTL_GETDATE | Gets the date |
| C5h | IOCTL_GETTIME | Gets the time |
| C6h | IOCTL_SOUND | Plays a sound (DX = PIT divisor) for CX ticks |

On a machine without a real-time clock (eg, a PC or PC XT), PCjs saves the host's date and time in vectors 58h-5Bh (INT_CLKDATA in bios.inc) whenever an INT 13h read loads a BASIC-DOS boot sector into 0:7C00h: the signature "PCJS" (CLK_SIG1 and CLK_SIG2), the day and month (bytes), the year (word), the ticks since midnight (dword), and the BIOS tick count (dword).  When CLOCK$ initializes in real mode, it uses them, adding the ticks since they were saved, unless a letter was pressed at the boot message or the result is within 10 seconds of midnight; IOCTL_CLOCK then returns 1.

#### VKD$ {#vkd}

| AL | Name | Description |
|----|------|-------------|
| D1h | IOCTL_GETDIM | Gets the context's dimensions |
| D2h | IOCTL_GETPOS | Gets the cursor position |
| D3h | IOCTL_GETLEN | Gets the displayed length of data (eg, with tabs expanded, and other control characters counted as two, since the DOS line editor displays them as "^" + char) |
| D4h | IOCTL_MOVCUR | Moves the cursor by DDPRW_LENGTH positions |
| D5h | IOCTL_SETINS | Sets INSERT mode on (CL = 1) or off (CL = 0) |
| D6h | IOCTL_SCROLL | Scrolls the context's scrolling rows up (CX > 0) or down (CX < 0) by CX lines, or clears them (CX = 0, DX = 0) and moves the cursor to the first one; or sets them (CX = 0, DL = first row, DH = last row + 1, zero-based), which also moves the cursor to the first one.  The scrolling rows are all the rows of the interior until they're set (and again after a mode change): a LINEFEED on the last scrolling row scrolls only those rows, while on any other row, the cursor moves down a row, unless it's on the last row of the interior |
| D7h | IOCTL_GETCOLOR | Gets the fill (DL) and border (DH) colors |
| D8h | IOCTL_SETCOLOR | Sets the fill (CL) and border (CH) colors; only the bits set in DL (fill) and DH (border) change, so DX = FFFFh sets them all, and the other bits keep their current values (eg, COLOR with only a foreground needs no IOCTL_GETCOLOR first) |
| D9h | IOCTL_SETPOS | Sets the cursor position (CL = column, CH = row, anywhere in the interior; FFh keeps the current column or row, and a position outside the interior fails with a seek error) and visibility (DL = 0 to hide it, 1 to show it, or any other value to leave it alone), and if DH = 1, erases from the new position to the end of the row |
| DAh | IOCTL_GETMODE | Gets the video mode (DL) if CL = 0; if CL = 1, the segment of the context's video memory (DX), which a program can use to draw directly (in protected mode, an LDT selector of the context's own, which isn't present while another context's mode change blocks this one; see [Video Memory](../mmu/#video)); or if CL = 2, the number of VKD$ contexts (DL) and whether the caller's context has focus (DH = 1 if so), which COMMAND.COM checks to decide whether to mention SHIFT-TAB |
| DBh | IOCTL_SETMODE | Sets the video mode (CL) and the number of text rows (CH): 0 or 25 for the mode's usual 25 rows, 43 (on an EGA or VGA), or 50 (on a VGA); fails if the adapter doesn't support the mode or the rows.  If the context shares the screen and the mode is a text mode as wide as the context itself (eg, mode 1 in a 40-column context on an 80-column screen), the screen's mode doesn't change: the mode becomes the context's virtual mode (which IOCTL_GETMODE then reports), and the context is cleared and loses its border, so no other context is blocked; setting the original mode, or a mode of FFh (which does only that, and fails if there's no virtual mode), clears the context and restores its border |
| DCh | IOCTL_GETCHAR | Gets the character (DL) and attributes (DH) at column CL, row CH (zero-based; see the SCREEN function) |
| DDh | IOCTL_SETKEYS | Sets raw keys mode on (CL bit 0 = 1) or off (0); see [Raw Keys](#raw-keys).  With CL bit 1 set and a selector in DX for low memory of the caller's own that has a copy of the BIOS data at 400h (eg, a [V86 machine](../mmu/#v86)'s), VKD$ also keeps that copy's keyboard data current (the shift states, and the keyboard buffer and its pointers, from 417h through 43Dh, with an empty buffer while the console doesn't have focus): it copies them after each keyboard interrupt, read, flush, and change of focus, until an IOCTL_SETKEYS with bit 1 clear, which DOS sends if the program ends without one.  The COM driver ignores bit 1 |

Changing the video mode (with IOCTL_SETMODE, or at ring 0 or in real mode, with INT 10h directly) turns the context into a full-screen, borderless context.  In another text mode (eg, 40 columns), the driver still writes directly to video memory; in any other mode, it uses INT 10h for output, so text output and scrolling work in graphics modes.  When the context returns to its original mode, its original geometry is restored.

A text mode (0-3) with 43 or 50 rows is a mode change, too, even if the mode number is the same.  A VGA is told how many scan lines to display (350 for 43 rows, 400 for 50) before the mode is set, with a function that only its BIOS has (INT 10h, AH = 12h, BL = 30h), which is also how the driver tells a VGA from an EGA; then, as soon as the mode is set, the driver loads the BIOS's 8x8 font (INT 10h, AX = 1112h), which gives the mode its rows, and selects 400 scan lines again, so that the next mode set by anyone has the usual 25 rows.  An EGA's BIOS assumes 14-line characters when it converts CGA cursor sizes, which would hide the cursor in 8-line characters, so cursor emulation (bit 0 of 40:87h) is off while the rows are displayed, and turned on again by the next mode change.  The rows extend beyond the first 4K page of video memory, which is safe, because the other contexts on the adapter are blocked (see below) and the BIOS's mode change clears every page anyway.  The COM driver rejects more than 25 rows.

A context that has a page of its own (ie, one opened with 80 columns and 25 rows) changes from one 25-row text mode (0-3) to another *in place*, on any adapter but an MDA.  The BIOS isn't called: the context stays on its page, which the driver clears, loses its border until it returns to its original mode, and blocks no other context.  The mode belongs to the page from then on, so a context without focus keeps writing to its page with its own columns, and whenever a context is given the screen (eg, on a focus switch) and its text mode isn't the one the adapter is displaying, the driver changes the adapter's mode without clearing video memory.  The BIOS of an EGA or VGA does that itself (INT 10h, AH = 00h, with bit 7 of the mode set).  A CGA's BIOS always clears all 16K, so the driver programs a CGA directly: the 6845's horizontal timing registers (0-3, the only ones that differ between text modes) and the mode register (3D8h), along with the BIOS's copy of the latter (40:65h), which the BIOS writes back to the register after it scrolls.  Each page is 4K in either width, so a page's start address never changes.  A change to or from a graphics mode or more than 25 rows, a change by a context that shares its page, and every change on a machine with one console (64K or less) are still the BIOS's, as described above.

The first context opened gets the focus, and a context opened with a *focus* of 1 (see [CON=](../../bdman/cfg/#con); START uses it) takes the focus and remembers the context it took it from.  A context opened with an *adapter* of 2 (which START also uses) goes on the adapter of the opening session's own context, and every new context uses the original mode and cursor shape of its adapter, whichever adapter the BIOS data currently describes.  When a context with focus closes, the focus goes back to that context, if any, or else to the next one; when a context that others took the focus from closes, they remember its context instead.

While a context is in any mode other than its original mode that wasn't set in place (eg, a graphics mode, or 40-column text in a context that shares its page), it occupies the entire screen, so every other context on the same adapter is blocked: its writes, and any IOCTL_SCROLL, IOCTL_SETCOLOR, IOCTL_SETPOS, or IOCTL_SETMODE request, wait (like a context paused with CTRL-S), and its border isn't drawn (eg, on a focus switch).  When that context returns to its original mode (or is closed, in which case its original mode is restored), the borders of the other contexts on the adapter are redrawn, and every blocked request continues.

The BIOS knows only about the screen, so a mode change or an INT 10h call from a session whose context doesn't have focus waits until it does: IOCTL_SETMODE and every INT 10h function suspend the session, and a focus switch to its context lets it continue (if the wait is interrupted instead, eg, by KILL, IOCTL_SETMODE fails and the INT 10h call returns without calling the BIOS).  The exception is a context that is blocking the others, which owns the screen with or without focus.  BASIC-DOS programs have no need for INT 10h (the IOCTLs above do the same work on any context), and an INT 10h call made while the driver has the BIOS locked (eg, one that the BIOS issues itself in the middle of another) is not suspended.  Since each context has a page of its own, INT 10h function 05h (select display page) is ignored, unless the context is the one using the entire screen.

Contexts that don't fit in an adapter's pages of video memory (one on an MDA, four on a CGA) go on virtual pages, up to 8 pages per adapter in all: each is a 4,000-byte block of system memory (owned by the system, since it outlives the program or console that opened it), shared by the contexts on that page, and freed when the last one closes.  The driver writes every text-mode context's characters directly, and scrolls any page that isn't being displayed itself (a virtual page, which the BIOS can't reach, or another of the adapter's pages; on a CGA, a row at a time during vertical retrace, with interrupts off, to avoid snow without blanking the display as the BIOS does, so a full-page scroll takes several frames on an 8088); only a displayed page, or a context using INT 10h for output, is scrolled by the BIOS.  When a context on a virtual page gets the focus, or sets a video mode (the BIOS can only set the mode of a page on the adapter), its page is exchanged with the page the adapter is displaying: their contents are swapped, and the contexts on each page take the other page's number, so no page needs a buffer just to save it while it's off the screen.  After a mode change, the page of the context with focus is displayed again.  On a machine with 64K of memory or less, VKD$ doesn't keep its code for virtual pages or for switching the focus, and it opens only one context.

The COM driver also supports IOCTL_GETDIM (it assumes an 80x24 terminal, or for a VT100, whatever IOCTL_SETMODE last selected: 40x24, 80x24, 132x24, or 132x14), IOCTL_GETPOS, IOCTL_GETLEN, IOCTL_MOVCUR, IOCTL_SETINS, IOCTL_GETCOLOR, IOCTL_SETCOLOR, and IOCTL_SETKEYS, so that the same programs work on serial consoles.  It can't read the terminal's cursor, so IOCTL_GETPOS returns the position it has calculated from the context's output: the column isn't reset when a line wraps (the DOS line editor relies on that), and the row advances with each LINEFEED and each wrap, stopping at the last scrolling row.

For ANSI and VT100 terminals, it also supports IOCTL_SETPOS (by sending ESC [ *row* ; *col* H, followed by ESC [ K if DH = 1; the cursor's visibility is ignored; the row past the last one is accepted too, where the cursor waits on the last row and writes other than RETURN and LINEFEED are ignored until the next IOCTL_SETPOS or LINEFEED) and IOCTL_SCROLL: it scrolls by sending LINEFEEDs at the last scrolling row, or ESC M at the first one; it sets the scrolling rows with ESC [ *first* ; *last* r (at least two rows); and it clears them with ESC [ K on each row, or with a single ESC [ J from the first row when they reach the bottom of the terminal.  GENERIC terminals support none of that, so IOCTL_SETPOS fails, and IOCTL_SCROLL only clears the screen (by starting a new line).

IOCTL_SETCOLOR sends an ANSI terminal ESC [ 0 ; 3*f* ; 4*b* m for the fill attributes' colors (or just ESC [ 0 m for the default attributes, 07h), with ; 1 added for intensity and ; 5 for blink.  A VT100 has no colors, so it's sent the attributes that an MDA displays instead: ; 7 (reverse video) for black on white, ; 4 (underline) for a foreground of 1, and ; 1 and ; 5 as above.  For a VT100, the driver also assigns the special graphics character set to G1 when the port is opened, and translates the PC's line-drawing characters (B0h-DFh) to it as they're written, sending SO before the first one and SI before the next character that differs between the two sets (5Fh and above).

For a VT100 only, the driver supports IOCTL_GETMODE (with CL = 0, which returns mode 3 for 80 columns, mode 1 for 40, or MODE_WIDE for 132) and IOCTL_SETMODE, where modes 2 and 3 select 80 columns, modes 0 and 1 select 40, and MODE_WIDE (23h, which isn't a mode of any display adapter, so VKD$ rejects it) selects 132; the graphics modes change nothing, and anything else fails.  (On a machine with 64K or less, the driver doesn't keep the code for IOCTL_SETMODE, which then fails as well.)  A VT100 has no 40-column mode, only double-width rows (ESC # 6), and any row that scrolls into view or is erased by ESC [ J is single-width again.  So instead of preparing all 24 rows, the driver keeps a flag for each row and sends ESC # 6 just before the first write to a row that hasn't had it, or when IOCTL_SETPOS moves the cursor to one; every flag is cleared by a scroll, a clear, a mode change, or a repaint, and a sequence that turns out to be redundant is harmless.  A change of mode makes every row a scrolling row again and clears the screen, which also returns every row to single-width.

MODE_WIDE is the VT100's own 132-column mode (ESC [ ? 3 h, and ESC [ ? 3 l to leave it), which a VT100 displays with 24 rows only if it has the Advanced Video Option; otherwise it has the memory for just 14.  So when the port is opened, the driver asks the terminal for its device attributes (ESC [ c), and a reply of ESC [ ? 1 ; *n* c where *n* has no bit 1 means a VT100 without the option: MODE_WIDE then has 14 rows, which IOCTL_GETDIM reports and every row check uses, until another mode restores 24.  The reply is consumed by the driver, and a terminal that sends some other reply, or none, is assumed to have 24 rows.  Cursor positions are sent with as many digits as they need, and since a context's column is a byte that isn't reset when a line wraps, in MODE_WIDE it steps back by 132 whenever it reaches 256 (in the other modes, a 4th row's columns are the 3rd's again).  Until the next write, a cursor that a wrap or a LINEFEED has moved to a new row is displayed at half its column.

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

HDC$'s MBR code is modeled on the pc.js MBR, without its drive tables: it moves itself to 7E00h, finds the active partition (rejecting a table with more than one active entry, or with any other status), loads its boot sector at 7C00h, verifies the signature, and jumps to it with SI pointing to the partition entry.

### Serial Consoles {#serial-consoles}

A console on a COM port (see [CON](../../bdman/cfg/#con)) supports most of the VKD$ console IOCTLs, as described [above](#vkd), so the BASIC statements built on them work on a terminal, too.  The tables below summarize both directions: what each of BASIC's text screen features does on a terminal, and which of a VT100's features BASIC-DOS uses.

The COM driver can't read anything back from a terminal, and it assumes that every terminal has 24 rows and 80 columns (a VT100 can also have 40; see WIDTH below).  ANSI (the default) and VT100 are the terminal types described here; a GENERIC terminal is sent only CR, LF, BACKSPACE, TAB, and BELL, so on one, CLS just starts a new line, COLOR does nothing, and LOCATE and VIEW PRINT are an "Illegal function call".

#### Several Consoles on One Terminal {#terminal-consoles}

A COM port can have more than one console.  Each has its own context (its input buffer, cursor position, scrolling rows, attributes, and raw keys setting), and only the one with the focus transmits; the others keep running, with their output going no further than a *shadow* of their screen: 3,168 characters (24 rows of 132, whatever the console's own columns are), plus 3,168 attributes once the console sets attributes other than the default.  Shadows and contexts are blocks that the system owns, since they outlive the program that opens them.

A new console is created when a session whose console is the port opens CON with a descriptor (eg, `CON:80,25,0,2,1`, as START does); DOS passes that open to the driver of the session's console, so the same open creates a VKD$ console in a session whose console is VKD$.  All the COM driver uses of the descriptor is its fifth value (1 to take the focus).  The new console's settings are those of the console with the focus, and when it closes, the focus goes back to the console it took it from, as for VKD$.

A port's first context gets a shadow only if its terminal type is ANSI or VT100, its output buffer holds at least 96 bytes, and at least 64K of memory is free at the time; without one, the open of a new console fails with ERR_NOMEMORY.  (A driver reports a failed open with a DOS error code in its status, which the program that opened the device gets as is; other requests fail with the DDERR_* codes in dev.inc.)  Every write then updates the shadow as well as the terminal: characters, line feeds (which scroll the scrolling rows), and the erasing and scrolling that IOCTL_SCROLL and IOCTL_SETPOS do.  Escape sequences that a program writes itself are stored as the characters they are.

The key that switches the focus to the port's next console is CTRL-\\ (1Ch), or the character in HOT_KEY (see bios.inc) if CONFIG.SYS has a [HOTKEY=](../../bdman/cfg/#hotkey) line, which VKD$ then uses as well, in place of Shift-Tab.  The key is consumed even in raw keys mode, unless the port has only one console.  A switch discards the old console's buffered output (its shadow already has it), moves the terminal's flow control state (an XOFF or CTS hold) to the new console, and repaints the new console's screen from its shadow: CAN (to end any sequence that was cut short), the default character set, attributes, and scrolling rows, an erased display, each row that isn't blank (through its last cell that isn't a default-attribute space), and then the console's scrolling rows, cursor position, and attributes.  The repaint is generated a step at a time as the output buffer empties, and writes and IOCTLs to that console wait until it's done.  A switch that arrives while either console is in the middle of an IOCTL (whose output is often a sequence) waits until the IOCTL ends.

#### BASIC Features on a Terminal {#terminal-basic}

| BASIC feature | On a terminal | Notes |
|---------------|---------------|-------|
| CLS | Works | Clears the scrolling rows (the entire screen, unless VIEW PRINT changed them) and moves the cursor to the first one |
| LOCATE *row*,*col* | Works | Rows 1-24 and columns 1-80 (or 1-40, or 1-132, where a VT100 without the Advanced Video Option has rows 1-14); output on the row after the last one is ignored (for programs written for 25 rows), and anything else is an "Illegal function call" |
| LOCATE with *row* or *col* omitted | Works | Uses the calculated position (see CSRLIN and POS) |
| LOCATE ,,*cursor* | Ignored | A VT100 can't hide its cursor |
| CSRLIN | Calculated | The driver counts LINEFEEDs, line wraps, and its own cursor movements, so the row is correct once the screen has been cleared (or has scrolled), and until a program sends the terminal an escape sequence of its own |
| POS, TAB, SPC | Calculated | The column is correct up to column 80; it isn't reset when a line wraps (the DOS line editor relies on that), so it's too large on the rest of a wrapped line |
| COLOR | Differs | An ANSI terminal is sent the foreground and background colors, plus bold (8-15) and blink (16-31).  A VT100 has no colors, so it's sent the attributes that a monochrome adapter displays: reverse video (`COLOR 0,7`), underline (a foreground of 1), bold, and blink.  The border is ignored |
| VIEW PRINT *top* TO *bottom* | Works | Uses the terminal's scrolling region, which needs at least two rows |
| SCREEN(*row*,*col*) | Illegal function call | There is no screen memory to read |
| WIDTH 40, 80, or 132 | Works on a VT100 | WIDTH 40 uses the VT100's double-width rows (a row changes when it's first written to, or the cursor is moved to it), and WIDTH 132 uses its 132-column mode, which has 14 rows without the Advanced Video Option; other terminals ignore WIDTH |
| SCREEN *mode* | Ignored | There are no graphics modes; on a VT100, SCREEN 0 with a different color burst changes nothing, and it keeps 132 columns |
| Graphics (CIRCLE, DRAW, GET, LINE, PAINT, POINT, PRESET, PSET, PUT, VIEW, WINDOW) | Illegal function call | |
| INKEY$, INPUT$, INPUT, LINE INPUT | Work | A VT100's cursor keys and PF1-PF4 are returned as the PC's cursor keys and F1-F4, and its DELETE and BACKSPACE keys are exchanged (see [Raw Keys](#raw-keys)) |
| F5-F10, Home, End, PgUp, PgDn, Ins | Unavailable on a VT100 | It has no such keys; an ANSI terminal's are translated in raw keys mode, and the DOS line editor has CTRL key equivalents |
| `PRINT CHR$(7)` | Works | Rings the terminal's bell |
| `CHR$(176)` through `CHR$(223)` | Translated on a VT100 | The PC's line-drawing characters become the VT100's special graphics characters: double lines become single lines, and the shaded and solid blocks become its checkerboard.  An ANSI terminal is sent the characters unchanged |
| Other characters above 127 | Not translated | A VT100 has only 7-bit characters |
| `CHR$(1)` through `CHR$(31)` | Differ | VKD$ draws them as characters; a terminal acts on them as control characters |
| `CHR$(27)` (escape sequences) | Passed through | A program can send any sequence the terminal supports, but the driver counts those characters as displayed text, so the calculated column and row are wrong afterward (CLS or LOCATE *row*,*col* corrects them) |
| CTRL-C, CTRL-S, BREAK | Work | BREAK works like Ctrl-Break on a VKD$ console; a VT100 uses XON/XOFF flow control, so CTRL-S and CTRL-Q are never input there |

#### VT100 Features {#terminal-vt100}

| VT100 feature | Sequence | Used for |
|---------------|----------|----------|
| Cursor position (CUP) | ESC [ *row* ; *col* H | LOCATE, IOCTL_SETPOS |
| Erase to end of display (ED) | ESC [ J | CLS, when the scrolling rows reach the bottom row |
| Erase to end of line (EL) | ESC [ K | CLS for other scrolling rows; IOCTL_SETPOS with DH = 1 (eg, VI) |
| Scrolling region (DECSTBM) | ESC [ *top* ; *bottom* r | VIEW PRINT, IOCTL_SCROLL (eg, VI) |
| Reverse index (RI) | ESC M | Scrolling down (IOCTL_SCROLL) |
| Cursor forward (CUF) | ESC [ C | The DOS line editor (IOCTL_MOVCUR); BACKSPACE moves the cursor back |
| Character attributes (SGR) | ESC [ 0 ; 7 ; 4 ; 1 ; 5 m | COLOR (reverse video, underline, bold, and blink) |
| Special graphics character set (SCS, SO, SI) | ESC ) 0, then CTRL-N and CTRL-O | Line-drawing characters |
| Auto-wrap (DECAWM) | ESC [ ? 7 h | Turned on when the port is opened |
| Double-width line (DECDWL) | ESC # 6 | WIDTH 40, IOCTL_SETMODE (sent once for each row in use) |
| 132 columns (DECCOLM) | ESC [ ? 3 h, ESC [ ? 3 l | WIDTH 132 (and leaving it), IOCTL_SETMODE; also sent when the focus moves between consoles with and without 132 columns.  ESC [ ? 3 l is sent when the port is opened as well (after SI and ESC [ m), since it also clears the screen, homes the cursor, and resets the scrolling region, whatever an earlier boot left behind |
| Device attributes (DA) | ESC [ c | Sent when the port is opened; the reply (ESC [ ? 1 ; *n* c) says whether the Advanced Video Option is installed |
| Cursor and PF key sequences | ESC [ A-D, ESC O A-D, ESC O P-S | Key translation |
| XON/XOFF, the NO SCROLL key | CTRL-S, CTRL-Q | Flow control |
| BREAK key | | Stops the current program |
| Bell | CTRL-G | `PRINT CHR$(7)` |

The VT100s in the demos have the Advanced Video Option.  A VT100 without it (see the [VT100 Terminal demo without the AVO](/demos/vt100/xt/noavo/)) has a single character attribute, reverse video or underline, depending on its SET-UP cursor selection, and neither bold nor blink, and only 14 rows in 132-column mode.

These VT100 features aren't used by the driver, and have no BASIC statement, although a program can send their sequences itself:

| VT100 feature | Sequence | Notes |
|---------------|----------|-------|
| Cursor up, down, and back (CUU, CUD, CUB) | ESC [ A, B, D | |
| Save and restore cursor (DECSC, DECRC) | ESC 7, ESC 8 | |
| Erase to start of line or display, or all of either | ESC [ 1 K, 2 K, 1 J, 2 J | |
| Index and next line (IND, NEL) | ESC D, ESC E | |
| Double-height lines (DECDHL) and single-width line (DECSWL) | ESC # 3 and 4, ESC # 5 | In 40-column mode, the driver makes a row double-width again before its next write only after a scroll or a clear |
| Reverse screen (DECSCNM) | ESC [ ? 5 h | |
| Origin mode (DECOM) | ESC [ ? 6 h | Would make the driver's cursor positions relative to the scrolling region |
| Smooth or jump scroll (DECSCLM) | ESC [ ? 4 h or l | Left to the terminal's SET-UP |
| Cursor position and status reports (DSR, CPR) | ESC [ 6 n, ESC [ 5 n | The driver never asks for the cursor's position, and the reply would be read as keys |
| Keypad application mode (DECKPAM) | ESC = | Never enabled; the keypad sends digits |
| Tab stops (HTS, TBC) | ESC H, ESC [ g | The driver assumes a tab stop every 8 columns |
| Keyboard LEDs (DECLL) | ESC [ 1 q through 4 q | |
| Reset, screen alignment, VT52 mode, answerback | ESC c, ESC # 8, ESC [ ? 2 l, CTRL-E | |

### Built-in Drivers

| Device | Type | Description |
|--------|------|-------------|
| VKD$ | Character | Video and keyboard driver: a separate context for each console (see [CON=](../../bdman/cfg/#con)); interrupt-driven input, direct video output, and INT 29h fast output |
| LPT1-LPT3 | Character | Parallel ports (one for each port the BIOS found): writes print with INT 17h, a failed write's error is also reported by the next IOCTL_OUTSTATUS (see LPRINT), and IOCTL_GETPOS returns the column (see LPOS) |
| COM1-COM4 | Character | Serial ports, with interrupt-driven, asynchronous I/O |
| CPU$ | Character | Two drivers, loaded first, of which one stays to manage all memory through DDINT_CPU (see [Protected Mode](../mmu/)): the 80386 driver stores the processor type in CPU_HWTYPE (0:513h) and CPU_TYPE (0:512h), which is 0 if real mode is requested (by `CPU=8088`, or **R** at the boot message), and otherwise, on an 80286 or later with at least 256K of conventional memory, manages memory with a PMB table (and protected-mode descriptors); otherwise, it unloads, and the 8086 driver manages memory with an MCB chain.  The one that stays stores its arena's address in CPU_ARENA (0:514h), for debuggers, and provides DDINT_GETVEC and DDINT_SETVEC.  Neither can be skipped |
| NUL | Character | Null device |
| CLOCK$ | Character | Timer interrupt, date and time, delays, and sound |
| PIPE$ | Character | Pipes between sessions (used by the command shell's `|` operator), with a 128-byte buffer; as on UNIX, a read waits only until some data is available, and then returns what's there (up to the requested length), while a write waits until all its data fits; it unloads itself with 64K of memory or less |
| FPU$ | Character | Floating-point functions, using an 8087 if present, or software emulation otherwise |
| MOUSE$ | Character | Serial mouse, with an INT 33h interface (see [MOUSE$](#mouse)); loaded only if a mouse responds on a COM port |
| FDC$ | Block | Diskette drives (A: and B:) |
| HDC$ | Block | Hard disks: FAT12 and FAT16 primary partitions of up to two BIOS hard disks (C:, D:, etc.), and a disk with no FAT partitions (eg, a new disk) as a single unit with unknown media, so that FORMAT can partition it; reads and writes are done by FDC$, so FDC$ must also be loaded |

Drivers that aren't needed (eg, VKD$ in a configuration that uses only serial consoles) can be omitted with [SKIP=](../../bdman/cfg/#skip).

CON, AUX, and PRN aren't drivers, but names that DOS gives the active session's console, AUX, and PRN devices (see [CON=](../../bdman/cfg/#con), [AUX=](../../bdman/cfg/#aux), and [PRN=](../../bdman/cfg/#prn)); opening one of those names (with or without a colon) shares the session's handle for that device (see [Files](../dos/#files)).

### CLOCK$ Timers {#clock-timers}

Drivers that need to do something after a delay (eg, the COM driver, to decide that a held ESC is just an ESC) use CLOCK$ timers instead of hooking the timer interrupt.  CLOCK$ exports a far entry point immediately after its device header (CLKX in dev.inc), and devinit records the CLOCK$ header in CLOCK_DEVICE (0:50Eh), so a driver can find it at any time after initialization (CLOCK_DEVICE._SEG is zero if CLOCK$ isn't loaded).

CLKX_TIMER takes ES:DI pointing to a TMR structure (owned by the caller, with TMR_FUNC set to a far function) and CX = milliseconds, which are rounded up to whole clock ticks (the first of which may be partial); CX = 0 cancels the timer, and starting a timer that's already running restarts it.  It can be called from interrupt handlers.  When the timer expires, CLOCK$ removes it and calls TMR_FUNC from its timer interrupt handler (after DDINT_ENTER, so it can call DOS_UTL_ENDWAIT), with ES:DI pointing to the TMR and interrupts disabled; the function may modify any registers except SS:SP and BP.

FDC$ and HDC$ share one copy of the INT 13h read and write code (including the handling of multi-track transfers and of transfers that would cross a 64K DMA boundary) and one buffer (a sector, or in protected mode, a track), all in FDC$.  FDC$ exports three far entry points immediately after its device header (FDCX in dev.inc): FDCX_RW performs a DDC_READ or DDC_WRITE request for the BIOS drive number in AL, FDCX_RDBUF reads a sector into the shared buffer (eg, a volume's boot sector, when HDC$ builds its BPB), and FDCX_MBR reads or writes a hard disk's MBR using the shared buffer (or simply returns the buffer, for HDC$ to build an MBR in); HDC$'s initialization also reads each MBR with FDCX_MBR (and copies it to devinit's scratch buffer), so FDC$ makes every INT 13h transfer, and in protected mode, it works around the BIOS's real-mode assumptions about ES:BX (see [INT 13h](../mmu/#interrupts)).  HDC$ finds FDC$ through FDC_DEVICE (which devinit records before initializing HDC$), and if FDC$ isn't loaded (eg, `SKIP=FDC$`), HDC$ doesn't load either.  The shared code takes the volume's geometry from its BPB, and for hard disks, adds BPB_HIDDENSECS (the volume's first sector) to every sector number.  For diskettes, it also sets the Diskette Parameter Table's sectors per track from the BPB before every transfer (the boot code moves the DPT to RAM, at 0:522h), since the BIOS stops a transfer at that sector and the ROM's value may not match the media (eg, 8-sector diskettes).  FDC$ also supports two IOCTL requests for formatting (see [FDC$](#fdc-ioctl) above), which FORMAT.BAS uses.

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

Each DEVICE= line in CONFIG.SYS loads a character device driver from a file: a single driver with no relocations, whose DDH is at offset 0, with DDH_NEXT_OFF set to FFFFh and DDATTR_CHAR set.  A dual-mode .COM file can instead put a JMP SHORT (EBh) in DDH_NEXT_OFF, which a program run from the prompt executes first.  DOS reads the entire file into memory (the block is the driver's data segment, or in protected mode, its data selector, in DDH_DATA), then calls DDH_REQUEST, through a code alias of that block from CPU$ (CPU_ALIAS, which in real mode is the same segment), with a DDC_INIT request, where DDPI_BUFPTR points to the ASCIIZ arguments that follow the filename, and DDPI_END is preset to the end of the file.  INIT runs before any sessions exist, so the driver can open files and devices (it gets system file handles, since there's no PSP yet), but if it fails, it must close them and leave no interrupt vectors hooked.  If INIT succeeds, DOS releases any memory beyond DDPI_END._OFF and adds the driver (with its code alias) to the head of the driver list; otherwise, DOS frees the driver and displays a warning with error 31 (general failure), and for any other failure, the warning includes the DOS error (eg, 2 if the file wasn't found, or 11 if it's not a valid driver).

DEBUG.COM is a dual-mode example (see [DEBUG.COM](../../bdman/cmd/external/debug/) for its commands).  As a program, its JMP SHORT lands on its input buffer, whose initial contents (unused by the driver) jump to code past DDPI_END, so loading it as a driver costs no extra memory.  DOS names each installed driver's memory block after its device (eg, DEBUG$, with CPU_SETBLK), so DEBUG's DM command shows it by name.

- **As a driver**, it opens its COM port with MODE_DENY_RW, switches the port to polling with IOCTL_COMDEBUG (which also frees the port's context, since the debugger does its own I/O), and hooks INT 00h, 01h, 03h, 04h, 13h, and 21h and the port's hardware interrupt (enabling only the UART's receive and line status interrupts), so that a CTRL-C or BREAK stops the machine as soon as it arrives.  Its INT 13h and INT 21h hooks pass every call on to the previous handler, after displaying a report if its VT command traps that function.  Its DEBUG$ device also accepts OPEN, CLOSE, and WRITE requests, sending written data to the port, so the kernel opens it (if installed) for DOS_UTL_DPRINTF messages.  Once it has stopped the machine, it never calls DOS (which it may have interrupted); it polls the UART, reads and writes all memory other than its own through CPU$ (CPU_RWMEM, which checks each address and can store a breakpoint in a code segment), and gets the system registers and descriptors from CPU_SYSREGS and CPU_SEGINFO.  In protected mode, it also takes fatal exceptions from CPU$ (CPU_SETFAULT), passes the ones that its VT command hasn't trapped on to the handler it replaced (the kernel's, which ends the program), and stops for any that the kernel declines before CPU$ halts the machine (see [Faults](../mmu/#faults)).
- **As a program**, its L command can read a drive's sectors into memory, through a volume handle (see [File Handles](../dos/#handles)), and it loads a program named on its command line (or by its L command) with DOS_PSP_EXEC1 (load without starting), which returns the program's initial SS:SP and CS:IP in the EPB, and enters its monitor as if the program's first instruction had been interrupted, so it needs no breakpoint there.  The first G, T, or P starts the program with DOS_PSP_EXEC2 (for T or P, with FL_TRAP in DX), which returns when the program ends, and DEBUG then exits with the program's exit code (DOS_PSP_RETCODE); Q ends the program first, with DOS_PSP_RETURN.  In real mode, and in protected mode with `RING=0`, it uses CPU$ as the driver does.  At ring 3 (see [Running Programs at Ring 3](../mmu/#ring3)), where it can't call CPU$, it uses DOS functions and the 80286's unprivileged instructions instead: it runs through the code alias of a block of its own (DOS_MEM_ALLOC and DOS_UTL_ALIAS), hooks INT 01h and 03h with DOS_MSC_GETVEC and DOS_MSC_SETVEC (not INT 00h, which only its VT command needs), reads and writes memory directly through selectors that it checks first (with LSL, VERR, and VERW), so that it never faults, and writes a program's code (eg, a breakpoint) through the selector of the code's block (DOS_UTL_ALIAS with AL = 1).  For a selector that ring 3 can't use (eg, the BIOS data selector, or a driver's in the driver chain, for DM), it finds the GDT and IDT with SGDT and SIDT, and reads their entries and the memory they describe with DOS_UTL_MAPSEG with AL = 1.

Its disassembler decodes the 80386's instructions (as 16-bit code, with 66h and 67h prefixes for 32-bit operands and addresses), unless CPU$'s CPUF_HWTYPE says the processor is an 80286, 8086, or 8088 (even in real mode, it doesn't on a later processor), in which case it decodes instructions as that processor runs them (eg, on an 8086 or 8088, 0Fh is POP CS).

{% include footer.html prev="Utility Functions:../util/" next="Floating-Point Interface:../fpu/" %}
