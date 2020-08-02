---
layout: post
title: Interlude
date: 2020-07-31 11:00:00
permalink: /maplebar/blog/2020/07/31/
---

I had originally thought about blogging every day about the progress
of BASIC-DOS, but reality quickly set it.  First of all, I'd much rather be
writing code than stupid blog entries, and secondly, no one would really be
all that interested.  Any blow-by-blow description of building a piece of
software byte by tedious byte would be about as fascinating as watching paint
dry.

But after more than two months into the project, an update is probably overdue.

## The Boot Sector

This is where development started.  And I'm happy to report that the boot
sector is in good shape.  It includes features that I don't think existed in
any version of DOS until MS-DOS 5.0:

 - IBMBIO.COM and IBMDOS.COM can be located anywhere in root directory
 - Those same files can use any clusters (they don't need to be contiguous)

In addition, the boot sector will prompt you if a hard disk is detected, and
if you press the Esc key, you can boot from the hard disk instead of the
BASIC-DOS diskette.  In the "old days," if you left a diskette in your IBM
PC XT's floppy drive, you booted from the diskette -- period.

## System Configuration

The BASIC-DOS boot code also loads CONFIG.SYS, if any, into memory, so that
the system can be tailored to your needs.  In the real world, PC DOS didn't
support CONFIG.SYS until version 2.0, over 1.5 years after the IBM PC and PC
DOS were introduced.

Installable device drivers (using the **DEVICE** keyword) aren't supported
yet, but support does exist for:

  - **DEBUG** (eg, DEBUG=COM1:9600,N,8,1 will enable debug messages to COM1)
  - **FILES** (eg, FILES=20 will allocate memory for up to 20 files)
  - **MEMSIZE** (eg, MEMSIZE=32 will limit system memory usage to 32K)
  - **SESSIONS** (eg, SESSIONS=4 will allocate memory for up to 4 sessions)
  - **SHELL** (eg, SHELL=SHELL.COM will load SHELL.COM instead of COMMAND.COM)

Sessions are one of the cool new features of BASIC-DOS.  More on that below,
when I talk about the **CONSOLE** driver.

## Built-in Device Drivers

IBMBIO.COM is the first file loaded by the boot sector, and it's little
more than the binary concatenation of all the standard (built-in) device
drivers, followed by a small bit code calls each driver's INIT function.
If a driver isn't needed (eg, if the hardware for COM3 or COM4 isn't
present), then the driver is discarded, to save memory.

If you type the `MEM` command, you'll see that BASIC-DOS includes all the
usual built-in DOS device drivers, although the only ones that really do
anything at this point are:

  - CON
  - COM#
  - CLOCK$
  - FDC$

And before talking about specific device drivers, it's worth pointing out
that although BASIC-DOS drivers and PC DOS drivers use a similar architecture,
they are *not* binary compatible.  After all, in this alternate timeline,
BASIC-DOS was the first version of DOS, so driver compatibility was a non-issue
-- there were no drivers to be compatible with.

Even though PC DOS drivers were designed with separate **STRATEGY** and
**INTERRUPT** entry points, the promise of asynchronous I/O was never
fulfilled.  BASIC-DOS drivers, on the other hand, have a single **REQUEST**
entry point that doesn't need to preserve any registers, and support for
asynchronous I/O is baked in.  The BASIC-DOS **CON** and **COM** drivers
already support interrupt-driven (rather than polling-driven) I/O.

Other details, like the format of device driver request packets and how IOCTLs
are handled, are also slightly different in BASIC-DOS.  The driver model is
inspired by DOS, not constrained by it.

### The CONSOLE Driver

The CONSOLE ("CON") driver is a cornerstone of **SESSIONS**, one of the
major features of BASIC-DOS.

BASIC-DOS supports a default of 4 sessions (which you can change with the
**SESSIONS** keyword in CONFIG.SYS), and each session can be configured to use
a specific portion of the screen and a specific shell.  For example, the
following pairs of lines in **CONFIG.SYS**:

    CONSOLE=CON:40,25,0,0,1
    SHELL=COMMAND.COM

and:

    CONSOLE=CON:40,25,40,0,1
    SHELL=COMMAND.COM

define two 40-column, 25-line sessions that will be displayed side-by-side
on an 80-column IBM PC monitor.

Sessions define a *context* within which one or more DOS programs many run,
and the system automatically multi-tasks between sessions, providing many of
the benefits a true multi-tasking operating system while still supporting
the traditional DOS application model.

At the moment, the CONSOLE driver is fairly stupid -- it will create contexts
with any size and position, without regard for other contexts, so you define
two or more overlapping contexts, expect to see a mess on the screen.

Contexts are created by opening the "CON" device with a descriptor, which is
a string following the device name, separated by a colon; eg:

    CON:40,25,40,0,1,0

The 6 possible values in a CON descriptor are:

  1. number of columns
  2. number of rows
  3. starting column
  4. starting row
  5. border style (0 for none)
  6. adapter number (0 for default)

Context borders exist within the context, which reduces the effective number
of rows and columns by 2.  Borders provide a visual delineation of the context,
and the width of the border indicates which context has focus (ie, where keys
will be delivered).  However, they obviously come at the expense of valuable
screen real estate.

The adapter number specifies which monitor to use in a dual-monitor machine.
Adapter 0 is the default adapter (ie, the monitor the machine is configured to
use on boot).

For example:

    CONSOLE=CON:80,25,0,0,0,0
    CONSOLE=CON:80,25,0,0,0,1

defines two full-screen border-less contexts, each assigned to a different
monitor.  In this case, the presence of a blinking cursor is your sole visual
cue as to which context has focus.

### The COM Driver

For each serial device present in the machine, an instance of the **COM**
driver will be installed.  You can open a COM device with just the bare name
("COM1"), or with a basic descriptor ("COM1:9600,N,8,1") to initialize the
device, or with a full descriptor ("COM1:9600,N,8,1,64,128") to also enable
asynchronous I/O (eg, with a 64-byte input buffer and a 128-byte output
buffer).

### The FDC$ Driver

This is a block device driver specifically designed for the IBM PC's floppy
disk controller.  However, unlike the CON and COM drivers, it does *not*
currently support asynchronous I/O.  I didn't feel like taking on that work
just yet, so it's largely just a wrapper for the BIOS INT 13h READ and WRITE
functions.

And because it relies entirely on the BIOS, it needs the DOS kernel to "lock"
the session while any disk operation is in progress, so that there's no risk
of a context-switch in the middle of a disk operation.

That obviously isn't ideal, but replicating all the BIOS functionality to
support asynchronous disk I/O is a big chunk of work.  And that's not the only
barrier: DOS itself uses shared buffers and other data structures that have
to be properly managed before I can allow fully overlapping I/O operations.

However, the FDC driver already does more than simply wrap INT 13h calls.
It provides a much nicer interface that supports:

  - Partial sector requests
  - Multi-sector requests
  - Sector requests that cross 64K boundaries

Support for partial sector requests relieves DOS from blocking/deblocking
I/O requests using intermediate buffers.  So if an app wants just 10 bytes
out of the middle of a sector, that request can more or less go straight to
the FDC driver.  And since the FDC does its own buffering, such requests
can usually be satisfied without hitting the disk again.

The BIOS only supports multi-sector requests as long as all the sectors are
on the same track; the FDC driver eliminates that requirement, by breaking
the request into multiple BIOS requests as appropriate.  Multi-sector requests
can even include partial sector requests, starting and/or stopping on
non-sector boundaries.

And finally, while the BIOS could fail a request simply because the transfer
address crossed a 64K boundary, the FDC driver automatically detects and avoids
those failures.

There's no support in the system for hard errors (eg, the familiar "Abort,
Retry, Ignore" prompts).  Any unrecoverable error is reported immediately back
to the caller.  That'll change at some point -- probably after I add support
to the CONSOLE driver for "popup" and background display contexts.

### BIOS Parameter Blocks

While the BPB is a diskette structure that was introduced in PC DOS 2.00,
BASIC-DOS had the, um, "foresight" to include that feature in BASIC-DOS 1.00
-- with some extensions.

BASIC-DOS on-disk BPBs have a few additional fields that relieve the boot code
from having to make expensive calculations (eg, the first root directory sector
and first data sector), and our in-memory BPBs have even more.  This makes them
suitable for all internal I/O requirements, eliminating the need for other
largely redundant data structures, such as Drive Parameter Blocks.

BPB support means that BASIC-DOS can read any standard PC diskette, even those
that didn't exist until PC DOS 2.00 or later, as long as the BIOS can read it.
However, diskettes with subdirectories won't be fully usable, at least not
until the day comes -- if ever -- that BASIC-DOS supports them.

BASIC-DOS changes another aspect of the BPB paradigm, too.  Whereas PC DOS
expected the driver to allocate memory for BPBs, BASIC-DOS takes charge of
that memory.  This seems to make more sense, given the central role that BPBs
play in managing an entire disk.

This in turn means that the FDC functions that manage and rebuild BPBs behave
differently (and, I would argue, more rationally) in BASIC-DOS.

## The DOS "Kernel"

IBMDOS.COM is the second file loaded by the boot code. 
