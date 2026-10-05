---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Device Drivers
permalink: /docs/bdtech/dev/
---

{% include header.html %}

BASIC-DOS device drivers use PC DOS-style driver headers and request packets, with some simplifications and extensions.  All built-in drivers are in BASDEV.COM; installable drivers (DEVICE=) aren't supported yet.

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
| 08h | DDP_PTR | Driver-specific pointer (eg, for DDC_OPEN, the device name and parameters, such as "CON:40,25") |
| 0Ch | DDP_SIG | Signature byte (DEBUG builds only) |

PC DOS defined only the first 5 bytes of the header; BASIC-DOS uses the rest to pass context information.  For example, DDC_OPEN returns a new context in DDP_CONTEXT, which DOS stores in the open file's SFB and passes back with every later request for that handle.

INIT requests use a DDPI packet:

| Offset | Field | Description |
|--------|-------|-------------|
| 0Dh | DDPI_UNITS | # of units (ie, drives) |
| 0Eh | DDPI_END | End of the driver's resident code (returned by the driver) |
| 12h | DDPI_BUFPTR | 512-byte scratch buffer |

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

On return, DDP_STATUS contains DDSTAT_DONE (0100h), plus DDSTAT_ERROR (8000h) and an error code in the low byte if the request failed.  Disk error codes are the BIOS (INT 13h) error codes (eg, 03h for write-protect, 80h for drive not ready), and the other codes use values the BIOS doesn't (eg, DDERR_UNKCMD, 06h, for an unknown command); see dev.inc for the complete list.

A request that must wait (eg, a keyboard read with no key available) calls DOS_UTL_WAIT with the packet address as the wait ID, which lets other sessions run; the driver's interrupt handler later calls DOS_UTL_ENDWAIT with the same ID.  Interrupt handlers should begin with a far call to DDINT_ENTER (0:530h) and end with a far jump to DDINT_LEAVE (0:535h), which lets DOS switch sessions when the interrupt ends.

### IOCTL Functions

DOS_HDL_IOCTL (INT 21h, AH = 44h) sends IOCTL requests to drivers: AL is passed in DDP_CODE, CX in DDPRW_LENGTH, DX in DDPRW_LBA, and DS:SI in DDPRW_ADDR, and the result returned in DDP_CONTEXT is returned in DX.  In addition to the standard codes (00h-07h), BASIC-DOS defines these:

#### CLOCK$ {#clock}

| AL | Name | Description |
|----|------|-------------|
| C1h | IOCTL_WAIT | Waits the number of milliseconds in DDPRW_LENGTH:DDPRW_OFFSET |
| C2h | IOCTL_SETDATE | Sets the date (CL = year - 1980 (0-127), DH = month, DL = day) |
| C3h | IOCTL_SETTIME | Sets the time (CH = hours, CL = minutes, DH = seconds, DL = hundredths) |
| C4h | IOCTL_GETDATE | Gets the date |
| C5h | IOCTL_GETTIME | Gets the time |
| C6h | IOCTL_SOUND | Plays a sound (DX = PIT divisor) for CX ticks |

#### CON {#con}

| AL | Name | Description |
|----|------|-------------|
| D1h | IOCTL_GETDIM | Gets the context's dimensions |
| D2h | IOCTL_GETPOS | Gets the cursor position |
| D3h | IOCTL_GETLEN | Gets the displayed length of data (eg, with tabs expanded) |
| D4h | IOCTL_MOVCUR | Moves the cursor by DDPRW_LENGTH positions |
| D5h | IOCTL_SETINS | Sets INSERT mode on (CL = 1) or off (CL = 0) |
| D6h | IOCTL_SCROLL | Scrolls (or clears) the interior of the context |
| D7h | IOCTL_GETCOLOR | Gets the fill (DL) and border (DH) colors |
| D8h | IOCTL_SETCOLOR | Sets the fill (CL) and border (CH) colors |
| D9h | IOCTL_SETPOS | Sets the cursor position (CL = column, CH = row) and visibility (DL) |
| DAh | IOCTL_GETMODE | Gets the video mode (DL) |
| DBh | IOCTL_SETMODE | Sets the video mode (CL) |

Changing the video mode (with IOCTL_SETMODE, or with INT 10h directly) turns the context into a full-screen, borderless context that uses INT 10h for output, so text output and scrolling work in graphics modes.  When the context returns to its original mode, its original geometry is restored.

#### FPU$ {#fpu}

| AL | Name | Description |
|----|------|-------------|
| E1h | IOCTL_GETFPU | Stores a far pointer to the FPU function table at DS:SI; returns DL = # of table entries and DH = FPU type (see [Floating-Point Interface](../fpu/)) |

### Built-in Drivers

| Device | Type | Description |
|--------|------|-------------|
| CON | Character | Console: keyboard and screen, with a separate context for each session (see [CONSOLE=](../../bdman/cfg/#console)); interrupt-driven input, direct video output (or BIOS output), and INT 29h fast output |
| AUX | Character | Logical serial device |
| PRN | Character | Logical parallel (printer) device |
| LPT1-LPT3 | Character | Parallel ports |
| COM1-COM4 | Character | Serial ports, with interrupt-driven, asynchronous I/O |
| NUL | Character | Null device |
| CLOCK$ | Character | Timer interrupt, date and time, delays, and sound |
| PIPE$ | Character | Pipes between sessions (used by the command processor's `|` operator) |
| FPU$ | Character | Floating-point functions, using an 8087 if present, or software emulation otherwise |
| FDC$ | Block | Diskette drives (A: and B:) |
| HDC$ | Block | Hard disks: the FAT12 primary partitions of up to two PC XT hard disks (C: and D:) |

Drivers that aren't needed (eg, CON in a configuration that uses only serial consoles) can be omitted with [SKIP=](../../bdman/cfg/#skip).

{% include footer.html prev="Utility Functions:../util/" next="Floating-Point Interface:../fpu/" %}
