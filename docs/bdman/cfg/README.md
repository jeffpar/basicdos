---
layout: sheet
title: Configuring BASIC-DOS
permalink: /docs/bdman/cfg/
---

{% include header.html %}

### System Configuration

When BASIC-DOS starts, it automatically allocates enough memory for:

- Up to 20 open files at a time
- Up to 4 active sessions at a time
- 3 disk buffers (which hold recently used FAT, directory, and file sectors)

and it creates a single 80-column, 25-row console, running COMMAND.COM.

Those settings, along with others, can be changed through entries in a special file named **CONFIG.SYS** on your BASIC-DOS startup diskette.  Each entry is a line of the form *KEYWORD*=*value*.  Lines that don't begin with a recognized keyword (eg, lines beginning with REM) are ignored.

For example, if the following lines appear in **CONFIG.SYS**:

	FILES=30
	SESSIONS=8

then memory will be set aside for up to 30 simultaneous open files and up to 8 simultaneous active sessions.

The recognized keywords are:

- [AUX](#aux)
- [BUFFERS](#buffers)
- [CON](#con)
- [CPU](#cpu)
- [DEVICE](#device)
- [FILES](#files)
- [MEMSIZE](#memsize)
- [PATHCHAR](#pathchar)
- [PRN](#prn)
- [RING](#ring)
- [SESSIONS](#sessions)
- [SHELL](#shell)
- [SKIP](#skip)
- [SWITCHAR](#switchar)

### AUX

> AUX=*device*

Sets the device that AUX refers to (eg, `AUX=COM2`, or with its settings, `AUX=COM2:1200,N,8,1`).  The default is COM1.  AUX isn't a driver, but a name for the device, which every session shares, along with its handle STDAUX (3).

AUX is opened after any [DEVICE](#device) drivers are loaded, so it can't be a port that a driver has claimed (eg, DEBUG.COM's port).  If an AUX line's device can't be opened, a warning is displayed; then, as when there's no COM1, there's no AUX device: AUX can't be opened, and reading or writing STDAUX fails.

### BUFFERS

> BUFFERS=*n*

Sets the number of disk buffers, each of which holds one 512-byte sector of a FAT, a directory, or a file, so that recently used sectors don't have to be read again.  The default is 3, and *n* can range from 2 to 32.  Each buffer beyond the first two uses 528 bytes of memory.  More than 3 mainly help systems with multiple sessions (eg, sessions working in different directories) and memory to spare.  `BUFFERS=2` saves memory on a 64K machine, but programs that read small amounts from two or more files at once (eg, COMP) become much slower.  For file data, only reads of part of a sector use the buffers; whole sectors and all writes are transferred directly by the disk drivers.

### CON

> CON=VKD$:*cols*,*rows*[,*border*[,*adapter*]]  
> CON=VKD$:*cols*,*rows*,BIOS  
> CON=COM*n*:*baud*,*parity*,*databits*,*stopbits*[,*options*]

Defines a console for a session: either a VKD$ console, which uses the video adapter and keyboard, or a COM console, which uses a serial port.  CON isn't a driver, but a name for the session's console, so a program that opens CON (or CON:) uses its session's console, whatever device it is.

Each CON line defines a console for the next session, so a CON line is needed for every session that has its own console; the number of CON lines can't exceed [SESSIONS](#sessions).  If there are no CON lines, a single console is created, as if `CON=VKD$:80,25` had been specified.  If a CON line can't be opened (eg, its adapter or serial port doesn't exist), a warning is displayed; if it's the first CON line, `VKD$:80,25` is used instead, and otherwise, that console and its SHELL line are skipped.

For a VKD$ console:

- *cols* and *rows* are the size of the console (16 to 80 columns and 4 to 25 rows)
- *border* is 1 to draw a border around the console, or 0 for none; a border uses the outermost rows and columns of the console
- *adapter* is 0 for the primary video adapter, or 1 for a second adapter (eg, a machine with both an MDA and a CGA)

BIOS (or just B) following *rows* creates a console that writes characters using the BIOS (INT 10h), rather than directly to video memory.

Consoles are positioned automatically, in the order of their CON lines.  Each adapter's first console starts at the top left corner of the screen, and each one after it starts below the previous one, or if the previous one reached the bottom of the screen, at the top of the screen, to its right.  A console that doesn't fit in the remaining space is made smaller to fit (but not below the minimum size, or the console isn't created).

Once a screen is full, the next console starts on another page of video memory (a CGA has 4, an MDA only 1), which is displayed whenever one of its consoles has the focus; once every page is full, no more consoles can be created on that adapter.

A COM console uses a serial port (eg, a terminal connected to COM1) for both input and output.  Its *options*, in any order, are:

- ANSI (the default) for a terminal that supports ANSI (VT100) cursor and erase sequences
- GENERIC for a terminal that supports only CR, LF, BACKSPACE, and TAB
- VT100, which is ANSI plus XON, auto-wrap, and the VT100 key translations described below (eg, `CON=COM1:9600,N,8,1,VT100`)
- XON for XON/XOFF flow control: the terminal sends XOFF (CTRL-S) to stop output and XON (CTRL-Q) to resume it, and neither is ever treated as input (which a VT100 does when it falls behind, such as while smooth scrolling, so the VT100 type includes XON)
- RTS for RTS/CTS (hardware) flow control: RTS is raised to tell the terminal that BASIC-DOS is ready, and output is held whenever the terminal drops CTS, resuming when CTS is raised again

A VT100 leaves auto-wrap off by default, so for the VT100 type, the driver turns it on when the port is opened, and long lines wrap instead of being truncated at the last column.

The VT100 type also swaps the DELETE and BACKSPACE keys, since on a VT100, DELETE (7Fh) is the key that erases the previous character, like the PC's BACKSPACE key, while BACKSPACE (08h) then deletes the character at the cursor, like the PC's DEL key.  And its cursor keys (which send ESC sequences) work like the PC's cursor keys, so an ESC on its own takes effect when the next key is pressed, and pressing ESC twice produces a single ESC.

Without XON, CTRL-S pauses output and any other key resumes it, except while a program is waiting for input, when CTRL-S is passed to the program.

On any COM console, a BREAK (eg, from a VT100's BREAK key) works like **Ctrl-Break** and **Ctrl-Alt-Del** on a VKD$ console: it stops the current program, even one that never uses DOS (eg, an endless loop that CTRL-C can't stop).

Two consoles side by side, each 40 columns wide with a border:

	SESSIONS=4
	CON=VKD$:40,25,1
	SHELL=COMMAND.COM
	CON=VKD$:40,25,1
	SHELL=COMMAND.COM

Two full-screen consoles on a CGA, each on its own page:

	CON=VKD$:80,25
	SHELL=COMMAND.COM
	CON=VKD$:80,25
	SHELL=COMMAND.COM

### CPU

> CPU=8088

Makes BASIC-DOS treat an 80286 or later processor as an 8088: the processor type is recorded as 8086/8088 (the actual type is still recorded too, so that DEBUG disassembles instructions as the processor runs them), extended memory isn't used, and the A20 address line stays disabled, so addresses wrap at 1Mb as they do on an 8088.  On an 8088 or 8086, the line has no effect.  BASIC-DOS also acts this way automatically with less than 128K of conventional memory (eg, with [MEMSIZE](#memsize)=64), since protected mode needs at least that much.

### DEVICE

> DEVICE=*filename* [*arguments*]

Loads an installable device driver, passing it any *arguments*.  DEVICE lines are processed in order, after the first console has been opened (so that any errors can be reported) and before any other consoles (and [AUX](#aux) and [PRN](#prn)) are opened.  If a driver can't be loaded, a warning is displayed (eg, `Warning: unable to find device DEBUG.COM`) and startup continues.

BASIC-DOS includes one installable driver, [DEBUG.COM](../cmd/external/debug/) (in the EXT directory), a debugger that runs on a terminal connected to a serial port; its argument is the port's settings, using the same format as a COM [CON](#con) (eg, `DEVICE=EXT\DEBUG.COM COM2:9600,N,8,1,VT100`), and any switches after them are debugger commands.  The debugger claims the port, so no other program or console can open it.  See [Loading DEBUG as a Driver](../cmd/external/debug/#loading-debug-as-a-driver) for details.

### FILES

> FILES=*n*

Sets the maximum number of files (and devices) that can be open at once, across all sessions.  The default is 20, and *n* can range from 8 to 254.

### MEMSIZE

> MEMSIZE=*n*

Limits the memory that BASIC-DOS uses to *n* kilobytes (16-640), assuming the machine has at least that much memory; the CPU$ driver lowers the BIOS's memory size (which INT 12h reports) to *n*, and leaves the rest unused.  This is mainly used for testing BASIC-DOS with different amounts of memory; it doesn't reserve memory for individual sessions, since all sessions share the same memory.

### PRN

> PRN=*device*

Sets the device that PRN refers to (eg, `PRN=LPT2`, or a serial printer, `PRN=COM2:1200,N,8,1`), which [LPRINT](../cmd/device/screen/#lprint) and [LLIST](../cmd/system/#llist) print on.  The default is LPT1.  PRN isn't a driver, but a name for the device, which every session shares, along with its handle STDPRN (4).

PRN is opened after any [DEVICE](#device) drivers are loaded, so it can't be a port that a driver has claimed.  If a PRN line's device can't be opened, a warning is displayed; then, as when there's no LPT1, there's no PRN device: PRN can't be opened, and writing to STDPRN (including LPRINT and LLIST) fails.

### RING

> RING=0

In protected mode (on an 80286 or later, without [CPU](#cpu)=8088), BASIC-DOS runs COMMAND.COM, every BASIC program, and every program they run (COM and EXE files alike) at ring 3, the processor's least privileged level, rather than at ring 0 with BASIC-DOS itself, so that a program can't write to memory that isn't its own (including another session's), or use privileged instructions (eg, IN, OUT, CLI, and STI); a program that tries is ended with a `CPU fault` message, as an error such as a divide by zero ends it.  RING=0 runs them all at ring 0 instead.  In real mode, everything runs at ring 0, and the line has no effect.

A program's interrupt handlers (eg, an INT 21h hook that passes the calls it doesn't handle on to DOS) run at ring 3, too, for the interrupts that programs in its own session issue, but not for those that BASIC-DOS, its drivers, or the ROM BIOS issue, so some programs don't work at ring 3 yet, and need RING=0: programs that hook such an interrupt (eg, the BIOS disk interrupt, or the timer tick), and programs that call CPU$ or the ROM BIOS disk functions directly.  DEBUG.COM run as a program works at ring 3, with fewer commands than at ring 0 (see [DEBUG](../cmd/external/debug/#ring-3)), and its driver can debug ring 3 programs.  Programs with their own CTRL-C or critical error handlers work, since those handlers run at ring 3, too.

### SESSIONS

> SESSIONS=*n*

Sets the maximum number of sessions that can be active at once.  The default is 4, and *n* can range from 1 to 32.

Sessions are used not only by consoles, but also by [pipes](../intro/#pipes-and-redirection): every command after the first in a pipeline runs in its own session.  So SESSIONS should allow for at least one more session than the number of consoles.

### SHELL

> SHELL=*program* [*command*[:*command*]...]

Specifies the program to run in the next session, along with any startup commands.  Each SHELL line starts a session, using the consoles defined by CON lines in order.  If there are no SHELL lines, COMMAND.COM is run in the first session.  A SHELL line without a console of its own is reported as an error (101) and skipped.  A session starts on the drive specified by its *program* (eg, `SHELL=C:/COMMAND.COM` starts on drive C:), or else on the boot drive.

BASIC-DOS doesn't automatically run an AUTOEXEC.BAT file, so a session's startup commands must be specified on its SHELL line, separated by colons.  Every BASIC-DOS disk's CONFIG.SYS also sets [PATH$](../cmd/basic/func/#path) on each SHELL line, so that every session can find the programs in the EXT, DEMOS, and SAMPLES directories:

	SHELL=COMMAND.COM PATH$="A:\;A:\EXT;A:\DEMOS;A:\SAMPLES":COLOR 7,1:AUTOEXEC.BAT

Everything after the *program* name becomes the program's command tail, which can't exceed 126 characters; a longer SHELL line isn't run (its session reports "SHELL line too long", followed by the start of the line), so put longer startup sequences in a batch file.

### SKIP

> SKIP=*device*[,*device*]...

Lists built-in device drivers that should not be loaded, using their exact device names (eg, `SKIP=VKD$,FPU$`).  A skipped driver is never initialized, and its memory is reclaimed.  The CPU$ driver, which manages memory, can't be skipped.

For example, a configuration that uses only serial consoles doesn't need the VKD$ driver, and skipping the FPU$ driver disables floating-point support (so variables default to integers, and `/` and `^` become integer operations).  On a machine with 64K of memory or less, the FPU$ driver unloads itself, as if it had been skipped.  Skipping the MOUSE$ driver avoids the time it takes to look for a serial mouse at boot.

### PATHCHAR

> PATHCHAR=*char*

Changes the character that separates directory names in paths from `\` (the default, as in PC DOS) to `/` (eg, `PATHCHAR=/`, so that `CD /EXT` is used instead of `CD \EXT`).  Only `\` and `/` are allowed; any other character is ignored.

Since the path character can't also be the switch character (which introduces command options), `PATHCHAR=/` also changes the switch character from `/` (the default, as in PC DOS) to `-` (eg, `TIME -P` instead of `TIME /P`).  Both characters remain fixed after boot.

### SWITCHAR

> SWITCHAR=*char*

Changes the character that introduces command options (switches) from `/` (the default, as in PC DOS) to `-` (eg, `SWITCHAR=-`, so that `TIME -P` is used instead of `TIME /P`).  Only `-` and `/` are allowed; any other character is ignored.  Pressing `-` at the boot prompt (which appears when booting from a diskette on a machine with a hard disk) has the same effect as `SWITCHAR=-`.  The switch character remains fixed after boot.

The switch character can't also be the path character (see [PATHCHAR](#pathchar)), so if it is (eg, `SWITCHAR=/` with `PATHCHAR=/`), a warning is displayed at boot, and the switch character is left unchanged.

A `-` begins a switch only at the start of an argument, so that it can also appear inside arguments (eg, `TYPE MY-FILE.TXT`).

### Sample Configuration

This CONFIG.SYS runs a single session on a terminal connected to COM1, without loading the VKD$ driver:

	REM Demonstration of a single-session configuration
	SKIP=VKD$
	SESSIONS=3
	CON=COM1:9600,N,8,1
	SHELL=COMMAND.COM AUTOEXEC.BAT

The Terminal Only demo uses a similar configuration on a 64K [IBM PC](/demos/term/pc/) with no video adapter, where a VT100 on COM1 is the only console, and on a 640K [IBM PC XT](/demos/term/xt/), whose shell starts on its 10Mb hard disk.

{% include footer.html prev="BASIC-DOS Programming:../lang/" next="Technical Reference:/docs/bdtech/" %}
