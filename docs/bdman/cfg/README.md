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
- 2 disk buffers (one for FAT sectors and one for directory sectors)

and it creates a single 80-column, 25-row console, running COMMAND.COM.

Those settings, along with others, can be changed through entries in a special file named **CONFIG.SYS** on your BASIC-DOS startup diskette.  Each entry is a line of the form *KEYWORD*=*value*.  Lines that don't begin with a recognized keyword (eg, lines beginning with REM) are ignored.

For example, if the following lines appear in **CONFIG.SYS**:

	FILES=30
	SESSIONS=8

then memory will be set aside for up to 30 simultaneous open files and up to 8 simultaneous active sessions.

The recognized keywords are:

- [BOOTKEY](#bootkey)
- [BUFFERS](#buffers)
- [CONSOLE](#console)
- [DEBUG](#debug)
- [FILES](#files)
- [MEMSIZE](#memsize)
- [PATHCHAR](#pathchar)
- [SESSIONS](#sessions)
- [SHELL](#shell)
- [SKIP](#skip)
- [SWITCHAR](#switchar)

Installable device drivers (DEVICE=) aren't supported yet.

### BOOTKEY

> BOOTKEY=*key*

Acts as if *key* had been pressed at the BASIC-DOS boot prompt.  This is a debugging aid: DEBUG builds of BASIC-DOS use the boot key to enable additional diagnostic messages.  It has no effect if a key other than **Enter** was actually pressed.

### BUFFERS

> BUFFERS=*n*

Sets the number of disk buffers, each of which holds one 512-byte sector of a FAT or a directory, so that recently used sectors don't have to be read again.  The default is 2 (the minimum), and *n* can range from 2 to 32.  Each additional buffer uses 528 bytes of memory, so more buffers mainly help systems with multiple sessions (eg, sessions working in different directories) and memory to spare.  File data isn't buffered; it's transferred directly by the disk drivers.

### CONSOLE

> CONSOLE=CON:*cols*,*rows*[,*x*,*y*[,*border*[,*adapter*]]]  
> CONSOLE=CON:*cols*,*rows*,BIOS  
> CONSOLE=COM*n*:*baud*,*parity*,*databits*,*stopbits*[,*options*]

Defines a console for a session.  Each CONSOLE line defines a console for the next session, so a CONSOLE line is needed for every session that has its own console; the number of CONSOLE lines can't exceed [SESSIONS](#sessions).  If there are no CONSOLE lines, a single console is created, as if `CONSOLE=CON:80,25` had been specified.  If a CONSOLE line can't be opened (eg, its adapter or serial port doesn't exist), a warning is displayed; if it's the first CONSOLE line, `CON:80,25` is used instead, and otherwise, that console and its SHELL line are skipped.

For a CON console:

- *cols* and *rows* are the size of the console (up to 80 columns and 25 rows)
- *x* and *y* are the column and row of the console's top left corner on the screen (default 0,0)
- *border* is 1 to draw a border around the console, or 0 for none; a border uses the outermost rows and columns of the console
- *adapter* is 0 for the primary video adapter, or 1 for a second adapter (eg, a machine with both an MDA and a CGA)

BIOS (or just B) following *rows* creates a full-screen console that writes characters using the BIOS (INT 10h), rather than directly to video memory.

A COM console uses a serial port (eg, a terminal connected to COM1) for both input and output.  Its *options*, in any order, are:

- ANSI (the default) for a terminal that supports ANSI (VT100) cursor and erase sequences, or GENERIC for a terminal that supports only CR, LF, BACKSPACE, and TAB
- XON for XON/XOFF flow control: the terminal sends XOFF (CTRL-S) to stop output and XON (CTRL-Q) to resume it, and neither is ever treated as input (eg, `CONSOLE=COM1:9600,N,8,1,XON` for a VT100, which sends XOFF when it falls behind, such as while smooth scrolling)
- RTS for RTS/CTS (hardware) flow control: RTS is raised to tell the terminal that BASIC-DOS is ready, and output is held whenever the terminal drops CTS, resuming when CTS is raised again

Without XON, CTRL-S pauses output and any other key resumes it, except while a program is waiting for input, when CTRL-S is passed to the program.

Two consoles side by side, each 40 columns wide with a border:

	SESSIONS=4
	CONSOLE=CON:40,25,0,0,1
	SHELL=COMMAND.COM
	CONSOLE=CON:40,25,40,0,1
	SHELL=COMMAND.COM

### DEBUG

> DEBUG=*device*

Sends diagnostic messages from DEBUG builds of BASIC-DOS to the specified device (eg, `DEBUG=COM1:9600,N,8,1,0`).

### FILES

> FILES=*n*

Sets the maximum number of files (and devices) that can be open at once, across all sessions.  The default is 20, and *n* can range from 8 to 255.

### MEMSIZE

> MEMSIZE=*n*

Limits the memory that BASIC-DOS uses to *n* kilobytes (16-640), assuming the machine has at least that much memory.  This is mainly used for testing BASIC-DOS with different amounts of memory; it doesn't reserve memory for individual sessions, since all sessions share the same memory.

### SESSIONS

> SESSIONS=*n*

Sets the maximum number of sessions that can be active at once.  The default is 4, and *n* can range from 1 to 32.

Sessions are used not only by consoles, but also by [pipes](../intro/#pipes-and-redirection): every command after the first in a pipeline runs in its own session.  So SESSIONS should allow for at least one more session than the number of consoles.

### SHELL

> SHELL=*program* [*command*[:*command*]...]

Specifies the program to run in the next session, along with any startup commands.  Each SHELL line starts a session, using the consoles defined by CONSOLE lines in order.  If there are no SHELL lines, COMMAND.COM is run in the first session.  A SHELL line without a console of its own is reported as an error (101) and skipped.  A session starts on the drive specified by its *program* (eg, `SHELL=C:/COMMAND.COM` starts on drive C:), or else on the boot drive.

BASIC-DOS doesn't automatically run an AUTOEXEC.BAT file, so a session's startup commands must be specified on its SHELL line, separated by colons.  Every BASIC-DOS disk's CONFIG.SYS also sets [PATH$](../cmd/basic/func/#path) on each SHELL line, so that every session can find the programs in the BIN, SAMPLES, and TESTS directories:

	SHELL=COMMAND.COM PATH$="A:/;A:/BIN;A:/SAMPLES;A:/TESTS":COLOR 7,1:AUTOEXEC.BAT

### SKIP

> SKIP=*device*[,*device*]...

Lists built-in device drivers that should not be loaded, using their exact device names (eg, `SKIP=CON,FPU$`).  A skipped driver is never initialized, and its memory is reclaimed.

For example, a configuration that uses a serial console doesn't need the CON driver, and skipping the FPU$ driver disables floating-point support (so variables default to integers, and `/` and `^` become integer operations).  Skipping the MOUSE$ driver avoids the time it takes to look for a serial mouse at boot.

### PATHCHAR

> PATHCHAR=*char*

Changes the character that separates directory names in paths from `/` (the default) to `\` (eg, `PATHCHAR=\`, so that `CD \BIN` is used instead of `CD /BIN`, as in PC DOS).  Only `/` and `\` are allowed; any other character is ignored.  Only one path character is recognized, and it remains fixed after boot.

### SWITCHAR

> SWITCHAR=*char*

Changes the character that introduces command options (switches) from `-` (the default) to `/` (eg, `SWITCHAR=/`, so that `MEM /D` is used instead of `MEM -D`, as in PC DOS).  Only `-` and `/` are allowed; any other character is ignored, and so is `/` if it's also the path character, so a PC DOS-style configuration needs both `PATHCHAR=\` and `SWITCHAR=/`.  The switch character remains fixed after boot, and it's independent of [PATHCHAR](#pathchar).

A switch character other than `/` begins a switch only at the start of an argument, so that it can also appear inside arguments (eg, `TYPE MY-FILE.TXT`).

### Sample Configuration

This CONFIG.SYS runs a single session on a terminal connected to COM1, without loading the CON driver:

	REM Demonstration of a single-session configuration
	SKIP=CON
	SESSIONS=3
	CONSOLE=COM1:9600,N,8,1
	SHELL=COMMAND.COM AUTOEXEC.BAT

{% include footer.html prev="BASIC-DOS Programming:../lang/" next="Technical Reference:/docs/bdtech/" %}
