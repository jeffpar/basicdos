---
layout: sheet
title: BASIC-DOS Command Shell
permalink: /docs/bdman/cmd/external/command/
---

{% include header.html %}

**COMMAND.COM** is the BASIC-DOS Command Shell.  Unlike other operating systems, which have a *Command Interpreter* for running operating system commands and a *BASIC Interpreter* for running BASIC language programs, BASIC-DOS provides a unified command shell.

Each console runs its own copy of COMMAND.COM, as specified by a [SHELL=](../../../cfg/#shell) line in CONFIG.SYS.  Copies share the same code, so each additional console needs only a small amount of additional memory.

### Startup Commands

> COMMAND [*command*[:*command*]...]  
> COMMAND /C *command*

Any commands following COMMAND are run when it starts (eg, `SHELL=COMMAND.COM AUTOEXEC.BAT`).  There is no automatic AUTOEXEC.BAT; each session's startup commands must be given explicitly.

`/C` runs *command*, without displaying a banner, and then exits, with ERRORLEVEL as its exit code (eg, `COMMAND /C PRINT 1+2`), unless it's a session's [SHELL=](../../../cfg/#shell) program, which displays the prompt instead (see [EXIT](../../system/#exit)).  It's how the C runtime's system() function runs a command, so a program like MAKE can tell when one fails.  Unlike other switches, it can start with `/` even if [SWITCHAR](../../../cfg/#switchar) has changed the switch character.

Running COMMAND.COM from the prompt starts another copy of the shell; type [EXIT](../../system/#exit) to return to the previous copy.

### Commands

COMMAND.COM performs all of the [BASIC](../../basic/), [device](../../device/), [disk](../../disk/), and [system](../../system/) commands in this manual itself, and runs everything else as an external command (see [Running Programs](../../../intro/#running-programs)).

### BASIC Compilation

BAS and BAT files, and commands typed at the prompt, are compiled into 8086 machine code, which is why BASIC-DOS programs run several times faster than the same programs in Microsoft BASIC.  A program is compiled as it runs: each line is compiled when the program first reaches it, so even a large program starts immediately.  A jump to a line that hasn't been compiled yet (eg, a GOSUB to a subroutine at the end of the program) compiles that line, and then the lines after it as the program reaches them, without compiling the lines it skipped; they're compiled when the program reaches them, too.  So lines are compiled in the order the program runs them, which means a DEFDBL, DEFINT, or DEFSTR affects the lines compiled after it (see [DEFINT](../../basic/#defint)), and a NEXT or WEND ends the innermost loop before it in the program (see [FOR](../../basic/#for)).  With too little memory for all of COMMAND.COM (eg, 64K), a jump to a later line compiles every line before it, too.  As in Microsoft BASIC, a statement that BASIC-DOS doesn't support causes a syntax error when the program reaches it, which ends the program.

When a BAS program ends, its compiled code is kept along with the program, if the whole program was compiled (eg, it ran past its last line, rather than stopping at an END), so [RUN](../../system/#run) can start it again without compiling it again.  The code is kept, too, if the whole program was compiled and CTRL-C stops it.

### Memory Usage

COMMAND.COM has a *resident* portion and a *transient* portion (about 23K).  Before running a COM or EXE program, COMMAND.COM frees any variable blocks it doesn't need and discards its transient portion, leaving more memory for the program.  When the program ends, the transient portion is restored: from a copy that COMMAND.COM saves at the top of free memory, if the program didn't overwrite it, or else by reloading it from COMMAND.COM, in the root directory of the drive it was loaded from (asking for that disk, if it isn't there).

The [MEM](../../system/#mem) command includes the transient portion in its total of available memory.

{% include footer.html prev="CHKDSK:../chkdsk/" next="COMP:../comp/" %}
