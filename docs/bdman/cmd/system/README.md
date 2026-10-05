---
layout: sheet
title: System Commands
permalink: /docs/bdman/cmd/system/
---

{% include header.html %}

BASIC-DOS system commands include:

- [EXIT](#exit)
- [HELP](#help)
- [KEYS](#keys)
- [LIST](#list)
- [MEM](#mem)
- [NEW](#new)
- [RESTART](#restart)
- [RUN](#run)
- [VER](#ver)

The EDIT command isn't supported yet.

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

> LIST

Lists all lines of the currently loaded BAS or BAT program.

### MEM

> MEM

Displays used and available memory.  In DEBUG builds of BASIC-DOS, /D displays memory blocks, /F displays open files, and /S displays active sessions.

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
	BASIC-DOS Version 2.00B

{% include footer.html prev="COMMAND.COM:../external/command/" next="BASIC-DOS Programming:../../lang/" %}
