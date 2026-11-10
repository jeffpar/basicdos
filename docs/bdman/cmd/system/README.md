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
- [KILL](#kill)
- [LIST](#list)
- [LLIST](#llist)
- [MEM](#mem)
- [NEW](#new)
- [RUN](#run)
- [START](#start)
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

Exits the command shell (see [COMMAND.COM](../external/command/)), returning to the program that ran it (eg, the copy of COMMAND.COM that loaded it).  A shell that a [SHELL=](../../cfg/#shell) line starts ignores EXIT (as PC DOS's `COMMAND /P` does), since its session would close, and with no other session, the system would halt; use [KILL](#kill) to end such a session.  Any other shell with no program to return to closes its session.

### KILL

> KILL *session*\|/A

`KILL` *session* ends the specified session (a number from the list that [START](#start) displays): every program running in it is stopped, as **Ctrl-Alt-Del** stops a program on its console, even one stuck in a loop that never uses DOS, including the session's shell, and then the session closes, so its console no longer responds.  For example, `KILL 2` ends a looping program and its shell on a serial display, from the PC's own console display.  If no other session is left, the system halts.  A number that isn't in the list is reported as `Invalid session`.

`KILL /A` restarts the system, with a warm boot, which skips the ROM's memory tests, after writing any modified disk data, but first it asks `Are you sure (Y/N)? `, until you answer Y or N.  It takes no session number.  KILL alone is a syntax error.

### LIST

> LIST [*line*][-[*line*]]  
> LIST VARS

Lists all lines of the currently loaded BAS or BAT program, or the specified range of lines (eg, `LIST 100`, `LIST 100-200`, `LIST 100-`, or `LIST -200`).  Lines without line numbers are listed with the numbered line that precedes them.  Each line is listed as [SAVE](../disk/#save) writes it (a line number is followed by one space), so the listing lines up the same way as the saved file does with [TYPE](../disk/#type) (eg, a line indented with a tab starts at the next tab stop).

`LIST VARS` lists preserved string variables such as `PATH$` first, followed by the current session's ordinary variables and their values in allocation order.  Names include `%`, `#`, or `$` to identify their types, and string values are quoted.  Arrays show each dimension's lower and upper bounds (eg, `A%(0 TO 2, 0 TO 3)`), without listing their elements.  Function definitions are omitted.  The listing can be redirected (eg, `LIST VARS > VARS.TXT` at the prompt) or paged with `LIST VARS | MORE`.

### LLIST

> LLIST [*line*][-[*line*]]

Lists all lines (or the specified range of lines) like [LIST](#list), but to the printer (PRN, normally LPT1; see [LPRINT](../device/screen/#lprint)).  Without a PRN device, a "Device unavailable" error occurs.  LLIST isn't available on low memory systems.

### MEM

> MEM

Displays the total memory ("bytes total") and the memory available for running external programs ("bytes available"), followed by the memory available for BASIC programs ("bytes for BASIC") when that's less.  The difference between the last two is the transient portion of COMMAND.COM, which is set aside while an external program runs, but which BASIC programs need (it compiles and runs them).  When more than one session is running, every session shares the same COMMAND.COM code, so the transient portion can't be set aside, and MEM omits the "bytes for BASIC" line, since the available memory is the same for both.

A line follows for anything that's unavailable: `Floating-point disabled` when the FPU$ driver was skipped or couldn't be loaded, and `Some features disabled (see HELP CORE)` when there wasn't enough memory for all of COMMAND.COM (see [Low Memory](../../lang/#low-memory) for what's left out).

To see every device driver and memory block, use the DM command of [DEBUG.COM](../external/debug/#dm).

	MEM
	  131072 bytes total
	   93568 bytes available
	   66928 bytes for BASIC

### NEW

> NEW

Erases the loaded program, functions, and variables.

### RUN

> RUN [*file*]

Runs the currently loaded BAS or BAT program.  If the whole program was compiled when it last ran, and neither the program nor its variables have changed since, its compiled code is reused instead of being compiled again.  Programs can also be run without the RUN command, by typing their names.

In a program, RUN restarts the program at its first line, as in Microsoft BASIC: its variables are cleared, any open files are closed, [READ](../basic/#read) starts over at the first DATA item, and any GOSUBs, FOR and WHILE loops, and [ON ERROR](../basic/#on-error) handler in progress are ended.  A BAT file restarts as a BAT file.

With *file*, RUN runs that BAS file, as in Microsoft BASIC.  If the file isn't in the current directory, and its name doesn't include a drive or directory, the directories listed in [PATH$](../basic/func/#path) are searched, and if the name has no extension, .BAS is added.  At the prompt, RUN loads the file (replacing any loaded program) and runs it, so it remains loaded when it ends.  In a program, RUN replaces the program, as [CHAIN](../basic/#chain) *file* does, except that any open files are closed first; a program run by name instead (eg, `MENU`) returns to the program that ran it.  *file* can be written as is, quoted, or as a string variable (see [Command Arguments](../../lang/#command-arguments)), and an empty string variable is the same as no file.  If the file can't be found, RUN fails like any other command, so the program continues, with ERRORLEVEL set to 1.  RUN *line* and the R option (which keeps files open) aren't supported, and RUN *file* and RUN in a program aren't available on low memory systems.

### START

> START [*program* [*arguments*]]

`START` alone lists every session that's running a program: its number, its console, and its program, with `*` marking the current session:

	C:\>START
	* 1 VKD$     COMMAND
	  2 COM1     COMMAND

`START` *program* runs *program* (a COM or EXE file, found the way any external command is, including in the directories of PATH$) with any *arguments* (and their switches) in a new session, on a new full-screen console, which gets the focus (press **Shift-Tab** to switch back).  When the program ends, its session and its console close, and if that console had the focus, it goes back to the console that had it before (or if that console has closed, to the console that one got it from, and so on).  For example, `START COMMAND` starts another command shell, which, unlike the shell that a [SHELL=](../../cfg/#shell) line starts, can [EXIT](#exit).

Like a session that CONFIG.SYS starts, the new session doesn't get the current session's handles (eg, its redirection) or environment, but it does start on the current drive and in the current directories.  A new COMMAND.COM (or [V86](../external/v86/)) does get the current [PATH$](../basic/func/#path), which START puts ahead of any *arguments*, as a SHELL= line can (eg, `START COMMAND FIBO.BAS` runs `COMMAND PATH$="A:\;A:\EXT":FIBO.BAS`), so a PATH$ assignment in its arguments (eg, `START COMMAND PATH$="A:\"`) replaces it.  The tail of a command line holds at most 126 characters, and a COMMAND /C argument must come first, so START COMMAND /C isn't supported.  In protected mode, its programs' memory is in an LDT of its own (see [Protected Mode](../../../bdtech/mmu/)).

Each START needs a free session (see [SESSIONS=](../../cfg/#sessions)), and its console needs a page of video memory, or a virtual page of system memory (see [CON=](../../cfg/#con)).  Errors include "No sessions available to run *program*" and "Unable to load *program*".

### VER

> VER

Displays the BASIC-DOS version number.

	VER
	BASIC-DOS 2.00

{% include footer.html prev="WC:../external/wc/" next="BASIC-DOS Programming:../../lang/" %}
