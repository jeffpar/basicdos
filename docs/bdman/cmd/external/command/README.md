---
layout: sheet
title: BASIC-DOS Command Processor
permalink: /docs/bdman/cmd/external/command/
---

{% include header.html %}

**COMMAND.COM** is the BASIC-DOS Command Processor.  Unlike other operating systems, which have a *Command Interpreter* for running operating system commands and a *BASIC Interpreter* for running BASIC language programs, BASIC-DOS provides a unified command processor.

Each session runs its own copy of COMMAND.COM, as specified by a [SHELL=](../../../cfg/#shell) line in CONFIG.SYS.  Copies share the same code, so each additional session needs only a small amount of additional memory.

### Startup Commands

> COMMAND [*command*[:*command*]...]

Any commands following COMMAND are run when it starts (eg, `SHELL=COMMAND.COM AUTOEXEC.BAT`).  There is no automatic AUTOEXEC.BAT; each session's startup commands must be given explicitly.

Running COMMAND.COM from the prompt starts another copy of the command processor; type [EXIT](../../system/#exit) to return to the previous copy.

### BASIC Compilation

BAS and BAT files, and commands typed at the prompt, are compiled into 8086 machine code before they run, which is why BASIC-DOS programs run several times faster than the same programs in Microsoft BASIC.  Since an entire program is compiled first, a statement that BASIC-DOS doesn't support causes a syntax error even if the program never reaches it.

When a BAS program ends, its compiled code is kept along with the program, so [RUN](../../system/#run) can start it again immediately.

### Memory Usage

COMMAND.COM has a *resident* portion and a *transient* portion (about 23K).  Before running a COM or EXE program, COMMAND.COM frees any variable blocks it doesn't need and discards its transient portion, leaving more memory for the program.  When the program ends, the transient portion is restored: from a copy that COMMAND.COM saves at the top of free memory, if the program didn't overwrite it, or else by reloading it from A:COMMAND.COM.

The [MEM](../../system/#mem) command includes the transient portion in its total of available memory.

{% include footer.html prev="External Commands:../" next="System Commands:../../system/" %}
