---
layout: sheet
title: System Commands
permalink: /docs/bdman/cmd/system/
---

{% include header.html %}

BASIC-DOS system commands include:

- [AUTO](#auto)
- [DELETE](#delete)
- [EDIT](#edit)
- [EXIT](#exit)
- [HELP](#help)
- [KEYS](#keys)
- [LIST](#list)
- [MEM](#mem)
- [NEW](#new)
- [RESTART](#restart)
- [RUN](#run)
- [VER](#ver)

AUTO, DELETE, EDIT, LIST, and NEW work with the loaded program, which can also be changed by typing lines with line numbers at the prompt (see [Entering Programs](../../intro/#entering-programs)).  AUTO, DELETE, and EDIT can't be used inside a BAS or BAT file (they report "Not allowed in a program").

### AUTO

> AUTO [*line*][,*increment*]

Prompts for program lines, starting with *line* (default 10) and adding *increment* (default 10) after each line is entered.  Each prompt is the next line number, which you can change; if a line with that number already exists, it's displayed for editing, and pressing **Enter** keeps it.  To stop, press **Enter** on a line with nothing after its number (the line isn't deleted), or press **Ctrl-C**.  Typing anything other than a numbered line also stops AUTO, and the input is processed as a command.

	AUTO 100,5
	100 PRINT "HELLO"
	105

### DELETE

> DELETE *line*[-[*line*]]  
> DELETE -*line*

Deletes the specified range of program lines (eg, `DELETE 10-50` deletes lines 10 through 50, and `DELETE 100-` deletes line 100 and everything after it).  Lines without line numbers are deleted along with the numbered line that precedes them.  To delete a single line, you can also type its line number by itself.

### EDIT

> EDIT *line*

Displays the specified program line (with its line number) for editing, using the same keys as the prompt (see [Typing Commands](../../intro/#typing-commands)).  Press **Enter** to store the edited line, or **Esc** and **Enter** to leave it unchanged.  If you change the line number, the edited line is stored as a new line, and the original line remains.  If you delete everything after the line number, the line is deleted.

### EXIT

> EXIT

Exits the command processor if there is a previously loaded copy (see [COMMAND.COM](../external/command/)).

### HELP

> HELP [*command*|*function*]

Displays help for the specified *command* or *function* (eg, `HELP MID$`), or lists all commands if none is specified.  The help text comes from the file HELP.TXT.

### KEYS

> KEYS

Displays a summary of the special keys that can be used when typing commands (see [Typing Commands](../../intro/#typing-commands)).

### LIST

> LIST [*line*][-[*line*]]

Lists all lines of the currently loaded BAS or BAT program, or the specified range of lines (eg, `LIST 100`, `LIST 100-200`, `LIST 100-`, or `LIST -200`).  Lines without line numbers are listed with the numbered line that precedes them.

### MEM

> MEM [/D]

Displays the total memory, followed by the memory free for running external programs (EXEC) and the memory free for BASIC programs.  The difference between the two is the transient portion of COMMAND.COM, which is set aside while an external program runs, but which BASIC programs need (it compiles and runs them).  When more than one session is running, every session shares the same COMMAND.COM code, so the transient portion can't be set aside, and MEM displays a single "bytes free" value instead.

/D also displays every memory block, with its segment, owner, size, and description (eg, a device driver, COMMAND, or one of COMMAND's VAR, STR, TEXT, or CODE blocks).  In DEBUG builds of BASIC-DOS, /F also displays open files, and /S displays active sessions.

	MEM
	  131072 bytes
	   93568 bytes free for EXEC
	   66928 bytes free for BASIC

### NEW

> NEW

Erases the loaded program, functions, and variables.

### RESTART

> RESTART

Restarts the system, after writing any modified disk data.

### RUN

> RUN

Runs the currently loaded BAS or BAT program.  If the program and its variables haven't changed since it last ran, its compiled code is reused, so it starts immediately.  Programs can also be run without the RUN command, by typing their names.

### VER

> VER

Displays the BASIC-DOS version number and revision.

	VER
	BASIC-DOS Version 2.00

{% include footer.html prev="COMMAND.COM:../external/command/" next="BASIC-DOS Programming:../../lang/" %}
