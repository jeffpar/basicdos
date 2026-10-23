---
layout: sheet
title: BASIC-DOS Commands
permalink: /docs/bdman/cmd/
---

{% include header.html %}

BASIC-DOS has a single command shell for both DOS commands (eg, DIR) and BASIC statements (eg, PRINT), so any command can be typed at the prompt or used in a BASIC program.  Commands are organized as follows:

- [BASIC Commands](basic/): statements for variables, control flow, error handling, and memory
- [BASIC Functions](basic/func/): numeric, string, and system functions, and predefined constants
- [Device Commands](device/): clock, keyboard, screen, graphics, and sound
- [Disk Commands](disk/): copying, deleting, listing, loading, and displaying files
- [External Commands](external/): COM, EXE, BAT, and BAS programs
- [System Commands](system/): help, memory, program management, and system control

In the descriptions that follow, *italics* indicate values that you supply, brackets (`[` `]`) indicate optional items, and a vertical bar (`|`) separates alternatives.

As in MS-DOS, a DOS command typed as one word with a path (eg, `CD\`, `CD\EXT`, or `DIR\HELP.TXT`) doesn't need a space before the path.  Unlike MS-DOS, however, a command followed by a path that begins with `.` (eg, `CD..`) still needs a space (eg, `CD ..`).

### Commands A-Z

| Command | Category | Command | Category |
|---------|----------|---------|----------|
| [AUTO](system/#auto) | System | [LOAD](disk/#load) | Disk |
| [CHAIN](basic/#chain) | BASIC | [LOCATE](device/screen/#locate) | Screen |
| [CIRCLE](device/graphics/#circle) | Graphics | [LPRINT](device/screen/#lprint) | Screen |
| [CLEAR](basic/#clear) | BASIC | [MEM](system/#mem) | System |
| [CLS](device/screen/#cls) | Screen | [MOUSE](device/mouse/#mouse) | Mouse |
| [COLOR](device/screen/#color) | Screen | [MV](disk/#ren) | Disk |
| [COPY](disk/#copy) | Disk | [NEW](system/#new) | System |
| [DATA](basic/#data) | BASIC | [NEXT](basic/#for) | BASIC |
| [DATE](device/clock/#date) | Clock | [ON](basic/#on) | BASIC |
| [DEF](basic/def/) | BASIC | [OPTION BASE](basic/#option-base) | BASIC |
| [DEF SEG](basic/#def-seg) | BASIC | [PAINT](device/graphics/#paint) | Graphics |
| [DEFDBL](basic/#defdbl) | BASIC | [PLAY](device/sound/#play) | Sound |
| [DEFINT](basic/#defint) | BASIC | [POKE](basic/#poke) | BASIC |
| [DEFSNG](basic/#defsng) | BASIC | [PRESET](device/graphics/#preset) | Graphics |
| [DEFSTR](basic/#defstr) | BASIC | [PRINT](device/screen/#print) | Screen |
| [DEL](disk/#del) | Disk | [PSET](device/graphics/#pset) | Graphics |
| [DELETE](system/#delete) | System | [PUT](device/graphics/#put) | Graphics |
| [DIM](basic/#dim) | BASIC | [READ](basic/#read) | BASIC |
| [DIR](disk/#dir) | Disk | [REM](basic/#rem) | BASIC |
| [DRAW](device/graphics/#draw) | Graphics | [REN](disk/#ren) | Disk |
| [ECHO](device/screen/#echo) | Screen | [RENAME](disk/#ren) | Disk |
| [EDIT](system/#edit) | System | [RESTART](system/#restart) | System |
| [END](basic/#end) | BASIC | [RESTORE](basic/#restore) | BASIC |
| [ERASE](basic/#erase) | BASIC | [RESUME](basic/#resume) | BASIC |
| [ERROR](basic/#error) | BASIC | [RETURN](basic/return/) | BASIC |
| [EXIT](system/#exit) | System | [RUN](system/#run) | System |
| [FOR](basic/#for) | BASIC | [SAVE](disk/#save) | Disk |
| [GET](device/graphics/#get) | Graphics | [SCREEN](device/screen/#screen) | Screen |
| [GOSUB](basic/#gosub) | BASIC | [SOUND](device/sound/#sound) | Sound |
| [GOTO](basic/goto/) | BASIC | [STOP](basic/#end) | BASIC |
| [HELP](system/#help) | System | [TIME](device/clock/#time) | Clock |
| [IF](basic/if/) | BASIC | [TYPE](disk/#type) | Disk |
| [IOCTL](basic/#ioctl) | BASIC | [VER](system/#ver) | System |
| [KEY](device/keyboard/#key) | Keyboard | [VIEW](device/graphics/#view) | Graphics |
| [KEYS](system/#keys) | System | [WEND](basic/#while) | BASIC |
| [LET](basic/let/) | BASIC | [WHILE](basic/#while) | BASIC |
| [LINE](device/graphics/#line) | Graphics | [WIDTH](device/screen/#width) | Screen |
| [LIST](system/#list) | System | [WINDOW](device/graphics/#window) | Graphics |
| [LLIST](system/#llist) | System |  |  |
See [BASIC Functions](basic/func/) for the list of functions and predefined constants.

REN (RENAME) and MV share the same file and directory rename and move command; see [REN](disk/#ren).

### Not Yet Supported

The following commands, statements, and functions from PC DOS and IBM PC BASIC aren't supported yet:

- PC DOS commands: DISKCOMP and PRINT (background printing); the other PC DOS 1.00 utilities (eg, CHKDSK, DISKCOPY, FORMAT, and SYS) are BASIC programs in the EXT directory (see [External Commands](external/))
- BASIC statements: BEEP, BLOAD, BSAVE, CALL, CHAIN MERGE, COMMON, CONT, DEF USR, KEY *n*,*string*, MERGE, OUT, PCOPY, RESUME without a line number, RESUME NEXT, RUN *file*, TRON, TROFF, WAIT, WIDTH LPRINT, and event trapping (eg, ON TIMER(*n*) GOSUB)
- BASIC functions: INP, INPUT$, STICK, STRIG, TIMER, USR, VARPTR, and VARPTR$

Some features of PC DOS and IBM PC BASIC aren't planned at all, such as PAUSE and the rest of PC DOS's batch file syntax (BAT files are BASIC programs; see [Batch Files](../lang/#batch-files)), CTTY (see [CONSOLE=](../cfg/#console)), and PRINT USING (see [How to replace PRINT USING](device/screen/#how-to-replace-print-using)).

{% include footer.html prev="Contents:../" next="BASIC Commands:basic/" %}
