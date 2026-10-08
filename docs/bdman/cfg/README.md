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
> CONSOLE=COM*n*:*baud*,*parity*,*databits*,*stopbits*

Defines a console for a session.  Each CONSOLE line defines a console for the next session, so a CONSOLE line is needed for every session that has its own console; the number of CONSOLE lines can't exceed [SESSIONS](#sessions).  If there are no CONSOLE lines, a single console is created, as if `CONSOLE=CON:80,25` had been specified.

For a CON console:

- *cols* and *rows* are the size of the console (up to 80 columns and 25 rows)
- *x* and *y* are the column and row of the console's top left corner on the screen (default 0,0)
- *border* is 1 to draw a border around the console, or 0 for none; a border uses the outermost rows and columns of the console
- *adapter* is 0 for the primary video adapter, or 1 for a second adapter (eg, a machine with both an MDA and a CGA)

BIOS (or just B) following *rows* creates a full-screen console that writes characters using the BIOS (INT 10h), rather than directly to video memory.

A COM console uses a serial port (eg, a terminal connected to COM1) for both input and output.

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

### PATHCHAR

> PATHCHAR=*char*

Changes the character that separates directory names in a path (eg, `CD /SUBDIR`).  The default is `/`, unless [SWITCHAR](#switchar) changes the switch character to `/`, in which case the default is `\` (as in PC DOS, where paths look like `CD \SUBDIR`).  Only the path character is recognized; BASIC-DOS doesn't also accept the other one.

### SESSIONS

> SESSIONS=*n*

Sets the maximum number of sessions that can be active at once.  The default is 4, and *n* can range from 1 to 32.

Sessions are used not only by consoles, but also by [pipes](../intro/#pipes-and-redirection): every command after the first in a pipeline runs in its own session.  So SESSIONS should allow for at least one more session than the number of consoles.

### SHELL

> SHELL=*program* [*command*[:*command*]...]

Specifies the program to run in the next session, along with any startup commands.  Each SHELL line starts a session, using the consoles defined by CONSOLE lines in order.  If there are no SHELL lines, COMMAND.COM is run in the first session.

BASIC-DOS doesn't automatically run an AUTOEXEC.BAT file, so a session's startup commands must be specified on its SHELL line, separated by colons:

	SHELL=COMMAND.COM COLOR 7,1:AUTOEXEC.BAT

### SKIP

> SKIP=*device*[,*device*]...

Lists built-in device drivers that should not be loaded, using their exact device names (eg, `SKIP=CON,FPU$`).  A skipped driver is never initialized, and its memory is reclaimed.

For example, a configuration that uses a serial console doesn't need the CON driver, and skipping the FPU$ driver disables floating-point support (so variables default to integers, and `/` and `^` become integer operations).  Skipping the MOUSE$ driver avoids the time it takes to look for a serial mouse at boot.

### SWITCHAR

> SWITCHAR=*char*

Changes the character that introduces command options (switches) from `-` (the default) to *char* (eg, `SWITCHAR=/`, so that `DIR /P` is used instead of `DIR -P`, as in PC DOS).  Changing it to `/` also changes the default [PATHCHAR](#pathchar) to `\`.

A switch character other than `/` begins a switch only at the start of an argument, so that it can also appear inside arguments (eg, `TYPE MY-FILE.TXT`).

### Sample Configuration

This CONFIG.SYS runs a single session on a terminal connected to COM1, without loading the CON driver:

	REM Demonstration of a single-session configuration
	SKIP=CON
	SESSIONS=3
	CONSOLE=COM1:9600,N,8,1
	SHELL=COMMAND.COM AUTOEXEC.BAT

{% include footer.html prev="BASIC-DOS Programming:../lang/" next="Technical Reference:/docs/bdtech/" %}
