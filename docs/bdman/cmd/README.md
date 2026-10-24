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
| [CLS](device/screen/#cls) | Screen | [MERGE](disk/#merge) | Disk |
| [COLOR](device/screen/#color) | Screen | [MOUSE](device/mouse/#mouse) | Mouse |
| [COPY](disk/#copy) | Disk | [MV](disk/#ren) | Disk |
| [DATA](basic/#data) | BASIC | [NEW](system/#new) | System |
| [DATE](device/clock/#date) | Clock | [NEXT](basic/#for) | BASIC |
| [DEF](basic/def/) | BASIC | [ON](basic/#on) | BASIC |
| [DEF SEG](basic/#def-seg) | BASIC | [OPTION BASE](basic/#option-base) | BASIC |
| [DEFDBL](basic/#defdbl) | BASIC | [PAINT](device/graphics/#paint) | Graphics |
| [DEFINT](basic/#defint) | BASIC | [PLAY](device/sound/#play) | Sound |
| [DEFSNG](basic/#defsng) | BASIC | [POKE](basic/#poke) | BASIC |
| [DEFSTR](basic/#defstr) | BASIC | [PRESET](device/graphics/#preset) | Graphics |
| [DEL](disk/#del) | Disk | [PRINT](device/screen/#print) | Screen |
| [DELETE](system/#delete) | System | [PSET](device/graphics/#pset) | Graphics |
| [DIM](basic/#dim) | BASIC | [PUT](device/graphics/#put) | Graphics |
| [DIR](disk/#dir) | Disk | [READ](basic/#read) | BASIC |
| [DRAW](device/graphics/#draw) | Graphics | [REM](basic/#rem) | BASIC |
| [ECHO](device/screen/#echo) | Screen | [REN](disk/#ren) | Disk |
| [EDIT](system/#edit) | System | [RENAME](disk/#ren) | Disk |
| [END](basic/#end) | BASIC | [RESTART](system/#restart) | System |
| [ERASE](basic/#erase) | BASIC | [RESTORE](basic/#restore) | BASIC |
| [ERROR](basic/#error) | BASIC | [RESUME](basic/#resume) | BASIC |
| [EXIT](system/#exit) | System | [RETURN](basic/return/) | BASIC |
| [FOR](basic/#for) | BASIC | [RUN](system/#run) | System |
| [GET](device/graphics/#get) | Graphics | [SAVE](disk/#save) | Disk |
| [GOSUB](basic/#gosub) | BASIC | [SCREEN](device/screen/#screen) | Screen |
| [GOTO](basic/goto/) | BASIC | [SOUND](device/sound/#sound) | Sound |
| [HELP](system/#help) | System | [STOP](basic/#end) | BASIC |
| [IF](basic/if/) | BASIC | [TIME](device/clock/#time) | Clock |
| [IOCTL](basic/#ioctl) | BASIC | [TYPE](disk/#type) | Disk |
| [KEY](device/keyboard/#key) | Keyboard | [VER](system/#ver) | System |
| [KEYS](system/#keys) | System | [VIEW](device/graphics/#view) | Graphics |
| [LET](basic/let/) | BASIC | [WEND](basic/#while) | BASIC |
| [LINE](device/graphics/#line) | Graphics | [WHILE](basic/#while) | BASIC |
| [LIST](system/#list) | System | [WIDTH](device/screen/#width) | Screen |
| [LLIST](system/#llist) | System | [WINDOW](device/graphics/#window) | Graphics |
See [BASIC Functions](basic/func/) for the list of functions and predefined constants.

REN (RENAME) and MV share the same file and directory rename and move command; see [REN](disk/#ren).

### Not Yet Supported

The following commands, statements, and functions from PC DOS and IBM PC BASIC aren't supported yet:

- PC DOS commands: DISKCOMP and PRINT (background printing); the other PC DOS 1.00 utilities (eg, CHKDSK, DISKCOPY, FORMAT, and SYS) are BASIC programs in the EXT directory (see [External Commands](external/))
- BASIC statements: BEEP, BLOAD, BSAVE, CALL, CHAIN's DELETE option, COMMON, CONT, DEF USR, OUT, PCOPY, RUN *file*, TRON, TROFF, WAIT, WIDTH LPRINT, and event trapping (eg, ON TIMER(*n*) GOSUB)
- BASIC functions: INP, STICK, STRIG, TIMER, USR, VARPTR, and VARPTR$

Some features of PC DOS and IBM PC BASIC aren't planned at all, such as PAUSE and the rest of PC DOS's batch file syntax (BAT files are BASIC programs; see [Batch Files](../lang/#batch-files)), CTTY (see [CONSOLE=](../cfg/#console)), and PRINT USING (see [How to replace PRINT USING](device/screen/#how-to-replace-print-using)).

{% include footer.html prev="Contents:../" next="BASIC Commands:basic/" %}
