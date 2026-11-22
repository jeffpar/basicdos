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
- [HOTKEY](#hotkey)
- [LIBPATH](#libpath)
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

Sets the number of disk buffers, each of which holds one 512-byte sector of a FAT, a directory, or a file, so that recently used sectors don't have to be read again.  The default is 8, or 3 with 128K of memory or less, and *n* can range from 2 to 32.  Each buffer beyond the first two uses 528 bytes of memory.  More buffers mainly help systems with multiple sessions (eg, sessions working in different directories).  `BUFFERS=2` saves memory on a 64K machine, but programs that read small amounts from two or more files at once (eg, COMP) become much slower.  For file data, only reads of part of a sector use the buffers; whole sectors and all writes are transferred directly by the disk drivers.

### CON

> CON=VKD$:*cols*,*rows*[,*border*[,*adapter*[,*focus*]]]  
> CON=COM*n*:*baud*,*parity*,*databits*,*stopbits*[,*options*]

Defines a console for a session: either a VKD$ console, which uses the video adapter and keyboard, or a COM console, which uses a serial port.  CON isn't a driver, but a name for the session's console, so a program that opens CON (or CON:) uses its session's console, whatever device it is.

A CON line defines the console of the session that the next [SHELL](#shell) line starts.  A SHELL line without a CON line before it (since the previous SHELL line) gets a full-screen console, as if `CON=VKD$:80,25` had been specified, so CON lines are needed only for other consoles.  If several CON lines come before a SHELL line, the last one is used, and CON lines after the last SHELL line are ignored (unless there are no SHELL lines, in which case the last CON line is the console of the default SHELL).  If a console can't be opened (eg, its adapter or serial port doesn't exist), a warning is displayed; for the first SHELL line, `VKD$:80,25` is used instead, and otherwise, that SHELL line is skipped.

For a VKD$ console:

- *cols* and *rows* are the size of the console (16 to 80 columns and 4 to 25 rows)
- *border* is 1 to draw a border around the console, or 0 for none; a border uses the outermost rows and columns of the console
- *adapter* is 0 for the primary video adapter, 1 for a second adapter (eg, a machine with both an MDA and a CGA), or 2 for the adapter of the console that the session opening it is using (as [START](../cmd/system/#start) does, so that its new console is on the same monitor)
- *focus* is 1 for the console to take the focus from the console that has it (the first console always gets the focus); when a console that took the focus closes, the focus goes back to the console it took it from (as for [START](../cmd/system/#start))

Consoles are positioned automatically, in the order of their CON lines.  Each adapter's first console starts at the top left corner of the screen, and each one after it starts below the previous one, or if the previous one reached the bottom of the screen, at the top of the screen, to its right.  A console that doesn't fit in the remaining space is made smaller to fit (but not below the minimum size, or the console isn't created).

Once a screen is full, the next console starts on another page of video memory (a CGA has 4, an MDA only 1), which is displayed whenever one of its consoles has the focus.  Once the adapter's pages are full, the next consoles go on virtual pages, each 4,000 bytes of system memory, up to 8 pages per adapter in all (eg, 8 full-screen consoles on an MDA).  When a console on a virtual page gets the focus, its page trades places with the page on the screen, whose consoles move to the virtual page, and every console keeps running wherever its page is.  A console that starts a new page goes on the first page that no console is using, so the pages of closed consoles (eg, from [START](../cmd/system/#start)) are used again.  A program on a virtual page that calls the video BIOS (INT 10h) directly to write characters writes them on the screen instead.

A COM console uses a serial port (eg, a terminal connected to COM1) for both input and output.  Its *options*, in any order, are:

- ANSI (the default) for a terminal that supports ANSI (VT100) cursor and erase sequences
- GENERIC for a terminal that supports only CR, LF, BACKSPACE, and TAB
- VT100, which is ANSI plus XON, auto-wrap, the VT100's own character attributes and line-drawing characters, and the VT100 key translations described below (eg, `CON=COM1:9600,N,8,1,VT100`)
- XON for XON/XOFF flow control: the terminal sends XOFF (CTRL-S) to stop output and XON (CTRL-Q) to resume it, and neither is ever treated as input (which a VT100 does when it falls behind, such as while smooth scrolling, so the VT100 type includes XON)
- RTS for RTS/CTS (hardware) flow control: RTS is raised to tell the terminal that BASIC-DOS is ready, and output is held whenever the terminal drops CTS, resuming when CTS is raised again

A terminal is often still displaying text from before the system was started, so for the VT100 type, the driver clears the screen when the port is opened (as [CLS](../cmd/device/screen/#cls) would), and returns the terminal to 80 columns, with no character attributes and every row scrolling.  A VT100 also leaves auto-wrap off by default, so the driver turns it on then, and long lines wrap instead of being truncated at the last column.

A VT100 has no colors and no characters above 127, so for the VT100 type, [COLOR](../cmd/device/screen/#color) selects reverse video, underline, bold, and blink instead, and the PC's line-drawing characters (176-223, eg, `CHR$(196)`) are displayed with the VT100's special graphics characters: single and double lines are both drawn as single lines, and the shaded and solid blocks (176-178 and 219-223) as its checkerboard.  Other characters above 127 are displayed as whatever the terminal makes of them.

Every ANSI or VT100 terminal is assumed to have 24 rows and 80 columns (or for a VT100, 40 columns after [WIDTH 40](../cmd/device/screen/#width), which uses its double-width characters, or 132 columns after WIDTH 132, with 14 rows if the terminal reports that it has no Advanced Video Option); [LOCATE](../cmd/device/screen/#locate), [CLS](../cmd/device/screen/#cls), and [VIEW PRINT](../cmd/device/screen/#view-print) work there as they do on a video console, but the `SCREEN` function can't read characters back.  See [Serial Consoles](../../bdtech/dev/#serial-consoles) in the Technical Reference for a complete list of what BASIC's screen features do on a terminal, and which VT100 features BASIC-DOS uses.

The VT100 type also swaps the DELETE and BACKSPACE keys, since on a VT100, DELETE (7Fh) is the key that erases the previous character, like the PC's BACKSPACE key, while BACKSPACE (08h) then deletes the character at the cursor, like the PC's DEL key.  And its cursor keys (which send ESC sequences) work like the PC's cursor keys, so an ESC on its own takes effect when the next key is pressed, and pressing ESC twice produces a single ESC.

Without XON, CTRL-S pauses output and any other key resumes it, except while a program is waiting for input, when CTRL-S is passed to the program.

An ANSI or VT100 terminal can have more than one console, although it shows only one at a time: [START](../cmd/system/#start), typed on a COM console, puts its new console on the same terminal, and **Ctrl-\\** (or the [HOTKEY](#hotkey) key) switches to the terminal's next console, whose screen is redrawn (which takes up to 2 seconds at 9600 baud).  A console that isn't being shown keeps running, and its output appears when you switch back to it.  With only one console on the terminal, **Ctrl-\\** is an ordinary key.

That requires a copy of each console's screen (about 2K of memory, and another 2K once the console uses [COLOR](../cmd/device/screen/#color)), so it's available only on a machine with more than 64K of memory, if at least 64K is free when the terminal's first console is opened, and its output buffer holds at least 96 characters (the default is 128); otherwise, START on that terminal fails (`Unable to load` *program*).  A screen is redrawn from what was written to it, so if a program sends the terminal its own escape sequences, the result may differ.

On any COM console, a BREAK (eg, from a VT100's BREAK key) works like **Ctrl-Break** and **Ctrl-Alt-Del** on a VKD$ console: it stops the current program, even one that never uses DOS (eg, an endless loop that CTRL-C can't stop).

Two consoles side by side, each 40 columns wide with a border:

	SESSIONS=4
	CON=VKD$:40,25,1
	SHELL=COMMAND.COM
	CON=VKD$:40,25,1
	SHELL=COMMAND.COM

Two full-screen consoles on a CGA, each on its own page:

	SHELL=COMMAND.COM
	SHELL=COMMAND.COM

The same lines on an MDA put the second console on a virtual page.

A machine with 64K of memory or less has only one VKD$ console (a second CON line's console can't be opened), since the driver doesn't keep its code for switching the focus or for virtual pages there.

### CPU

> CPU=8088
> CPU=80286
> CPU=80386

On an 80286 or later processor, BASIC-DOS runs in protected mode by default, and on an 80386 or later, it uses the 80386's features (see [Protected Mode](../../bdtech/mmu/#cpu)), unless there's a `CPU=80286` line, which limits it to the 80286's; `CPU=80386` is the same as no line.  Protected mode needs at least 256K of conventional memory (after any [MEMSIZE](#memsize) line), and any extended memory is a bonus; with less, or on an 8088 or 8086, BASIC-DOS runs in real mode.

`CPU=8088` runs BASIC-DOS in real mode, its most compatible mode (eg, MZ EXE files don't run in protected mode), and treats an 80286 or later processor as an 8088: the processor type is recorded as 8086/8088 (the actual type is still recorded too, so that DEBUG disassembles instructions as the processor runs them), extended memory isn't used, and the A20 address line stays disabled, so addresses wrap at 1Mb as they do on an 8088.  Pressing `R` at the boot message also selects real mode, and pressing `P` there overrides a `CPU=8088` line.

### DEVICE

> DEVICE=*filename* [*arguments*]

Loads an installable device driver, passing it any *arguments*.  DEVICE lines are processed in order, after the first console has been opened (so that any errors can be reported) and before any other consoles (and [AUX](#aux) and [PRN](#prn)) are opened.  If a driver can't be loaded, a warning is displayed (eg, `Warning: unable to find device DEBUG.COM`) and startup continues.

BASIC-DOS includes one installable driver, [DEBUG.COM](../cmd/external/debug/) (in the EXT\\CMD directory), a debugger that runs on a terminal connected to a serial port; its argument is the port's settings, using the same format as a COM [CON](#con) (eg, `DEVICE=EXT\CMD\DEBUG.COM COM2:9600,N,8,1,VT100`), and any switches after them are debugger commands.  The debugger claims the port, so no other program or console can open it.  See [Loading DEBUG as a Driver](../cmd/external/debug/#loading-debug-as-a-driver) for details.

### FILES

> FILES=*n*

Sets the maximum number of files (and devices) that can be open at once, across all sessions.  The default is 20 (or 8, on a machine with 128K of memory or less), and *n* can range from 8 to 254.

Each session's console counts as an open device, and a program that needs more files than are available may report a missing file instead (eg, MASM's `Include file ... not found`).

### HOTKEY

> HOTKEY=^*char*

Sets the key that switches the focus to the next console, for every console: a caret followed by a character, which together name a control character (eg, `HOTKEY=^T` for **Ctrl-T**, or `HOTKEY=^\` for **Ctrl-\\**).  Any other setting is ignored.  That key then never reaches a program, so choose one that nothing else needs (eg, not `^C`, `^S`, or `^M`, which is ENTER).

Without a HOTKEY line, each kind of console has its own key: **Shift-Tab** on the keyboard (VKD$ consoles), and **Ctrl-\\** on a terminal (COM consoles), since a terminal's TAB key sends the same character with or without SHIFT.  With one, **Shift-Tab** is an ordinary key again.

### LIBPATH

> LIBPATH=*path*

Names the directory that holds libraries (DLL files), which protected-mode EXE programs can import functions from (eg, `LIBPATH=C:\LIB`); BASIC-DOS loads a library along with any program that needs it.  The path can be up to 31 characters, and it's a single directory, not a list.  Without a LIBPATH line, libraries are in **EXT\\DLL** on the system drive (the drive that BASIC-DOS started from).  In real mode, where programs can't import from libraries, the line has no effect.

### MEMSIZE

> MEMSIZE=*n*

Limits the memory that BASIC-DOS uses to *n* kilobytes (16-640), assuming the machine has at least that much memory; the CPU$ driver lowers the BIOS's memory size (which INT 12h reports) to *n*, and leaves the rest unused.  This is mainly used for testing BASIC-DOS with different amounts of memory; it doesn't reserve memory for individual sessions, since all sessions share the same memory.

### PRN

> PRN=*device*

Sets the device that PRN refers to (eg, `PRN=LPT2`, or a serial printer, `PRN=COM2:1200,N,8,1`), which [LPRINT](../cmd/device/screen/#lprint) and [LLIST](../cmd/system/#llist) print on.  The default is LPT1.  PRN isn't a driver, but a name for the device, which every session shares, along with its handle STDPRN (4).

PRN is opened after any [DEVICE](#device) drivers are loaded, so it can't be a port that a driver has claimed.  If a PRN line's device can't be opened, a warning is displayed; then, as when there's no LPT1, there's no PRN device: PRN can't be opened, and writing to STDPRN (including LPRINT and LLIST) fails.

### RING

> RING=0

In protected mode (see [CPU](#cpu)), BASIC-DOS runs COMMAND.COM, every BASIC program, and every program they run (COM and EXE files alike) at ring 3, the processor's least privileged level, rather than at ring 0 with BASIC-DOS itself, so that a program can't write to memory that isn't its own (including another session's), or use privileged instructions (eg, IN, OUT, CLI, and STI) or BIOS interrupts; a program that tries is ended with a `CPU fault` message, as an error such as a divide by zero ends it.  RING=0 runs them all at ring 0 instead.  In real mode, everything runs at ring 0, and the line has no effect.

A program's interrupt handlers (eg, an INT 21h hook that passes the calls it doesn't handle on to DOS) run at ring 3, too, for the interrupts that programs in its own session issue, but not for those that BASIC-DOS, its drivers, or the ROM BIOS issue, so some programs don't work at ring 3 yet, and need RING=0: programs that hook such an interrupt (eg, the BIOS disk interrupt, or the timer tick), and programs that call CPU$ or the ROM BIOS disk functions directly.  DEBUG.COM run as a program works at ring 3, with fewer commands than at ring 0 (see [DEBUG](../cmd/external/debug/#ring-3)), and its driver can debug ring 3 programs.  Programs with their own CTRL-C or critical error handlers work, since those handlers run at ring 3, too.

### SESSIONS

> SESSIONS=*n*

Sets the maximum number of sessions that can be active at once; *n* can range from 1 to 32.  The default is the number of consoles (the number of [SHELL](#shell) lines, or 1 if there aren't any), plus 4 so that pipelines can have up to 4 filters at once, unless the PIPE$ driver isn't loaded (see [SKIP](#skip)), plus 4 more with more than 256K of memory (eg, for [START](../cmd/system/#start)).  Each session costs only about 80 bytes of the kernel's memory (plus 1K at ring 3), and [MEM](../cmd/system/#mem) displays the number.

Sessions are used not only by consoles, but also by [pipes](../intro/#redirection-and-pipes): every command after the first in a pipeline runs in its own session.  So if you set SESSIONS yourself, it should exceed the number of consoles by at least the number of filters you want to run at once.

### SHELL

> SHELL=*program* [*command*[:*command*]...]

Specifies the program to run in the next session, along with any startup commands.  Each SHELL line starts a session, with a console of its own (see [CON](#con)); the number of SHELL lines can't exceed [SESSIONS](#sessions).  If there are no SHELL lines, COMMAND.COM is run in the first session.  A session starts on the drive specified by its *program* (eg, `SHELL=C:/COMMAND.COM` starts on drive C:), or else on the boot drive.

BASIC-DOS doesn't automatically run an AUTOEXEC.BAT file, so a session's startup commands must be specified on its SHELL line, separated by colons.  Every BASIC-DOS disk's CONFIG.SYS also sets [PATH$](../cmd/basic/func/#path) on each SHELL line, so that every session can find the programs in the EXT\\CMD, EXT\\BAS, and DEMOS directories:

	SHELL=COMMAND.COM PATH$="A:\;A:\EXT\CMD;A:\EXT\BAS;A:\DEMOS":COLOR 7,1:AUTOEXEC.BAT

Everything after the *program* name becomes the program's command tail, which can't exceed 126 characters; a longer SHELL line isn't run (its session reports "SHELL line too long", followed by the start of the line), so put longer startup sequences in a batch file.

### SKIP

> SKIP=*device*[,*device*]...

Lists built-in device drivers that should not be loaded, using their exact device names (eg, `SKIP=VKD$,FPU$`); there can be more than one SKIP line.  A skipped driver is never initialized, and its memory is reclaimed.  The CPU$ driver, which manages memory, can't be skipped.

For example, a configuration that uses only serial consoles doesn't need the VKD$ driver, and skipping the FPU$ driver disables floating-point support (so variables default to integers, and `/` and `^` become integer operations).  On a machine with 64K of memory or less, the FPU$ and PIPE$ drivers unload themselves, as if they had been skipped.  Skipping the MOUSE$ driver avoids the time it takes to look for a serial mouse at boot.

### PATHCHAR

> PATHCHAR=*char*

Changes the character that separates directory names in paths from `\` (the default, as in PC DOS) to `/` (eg, `PATHCHAR=/`, so that `CD /EXT` is used instead of `CD \EXT`).  Only `\` and `/` are allowed; any other character is ignored.

Since the path character can't also be the switch character (which introduces command options), `PATHCHAR=/` also changes the switch character from `/` (the default, as in PC DOS) to `-` (eg, `TIME -P` instead of `TIME /P`).  Both characters remain fixed after boot.

### SWITCHAR

> SWITCHAR=*char*

Changes the character that introduces command options (switches) from `/` (the default, as in PC DOS) to `-` (eg, `SWITCHAR=-`, so that `TIME -P` is used instead of `TIME /P`).  Only `-` and `/` are allowed; any other character is ignored.  Pressing `-` at the boot message has the same effect as `SWITCHAR=-`.  The switch character remains fixed after boot.

The switch character can't also be the path character (see [PATHCHAR](#pathchar)), so if it is (eg, `SWITCHAR=/` with `PATHCHAR=/`), a warning is displayed at boot, and the switch character is left unchanged.

A `-` begins a switch only at the start of an argument, so that it can also appear inside arguments (eg, `TYPE MY-FILE.TXT`).

### Sample Configuration

This CONFIG.SYS runs a single console on a terminal connected to COM1, without loading the VKD$ driver:

	REM Demonstration of a single-console configuration
	SKIP=VKD$
	SESSIONS=3
	CON=COM1:9600,N,8,1
	SHELL=COMMAND.COM AUTOEXEC.BAT

The Terminal Only demo uses a similar configuration on a 64K [IBM PC](/demos/bd/term/pc/) with no video adapter, where a VT100 on COM1 is the only console, and on a 640K [IBM PC XT](/demos/bd/term/xt/), whose shell starts on its 10Mb hard disk.

{% include footer.html prev="BASIC-DOS Programming:../lang/" next="Technical Reference:/docs/bdtech/" %}
