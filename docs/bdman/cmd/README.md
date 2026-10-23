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
| [CIRCLE](device/graphics/#circle) | Graphics | [MEM](system/#mem) | System |
| [CLEAR](basic/#clear) | BASIC | [MOUSE](device/mouse/#mouse) | Mouse |
| [CLS](device/screen/#cls) | Screen | [MV](disk/#ren) | Disk |
| [COLOR](device/screen/#color) | Screen | [NEW](system/#new) | System |
| [COPY](disk/#copy) | Disk | [NEXT](basic/#for) | BASIC |
| [DATA](basic/#data) | BASIC | [ON](basic/#on) | BASIC |
| [DATE](device/clock/#date) | Clock | [OPTION BASE](basic/#option-base) | BASIC |
| [DEF](basic/def/) | BASIC | [PAINT](device/graphics/#paint) | Graphics |
| [DEF SEG](basic/#def-seg) | BASIC | [PLAY](device/sound/#play) | Sound |
| [DEFDBL](basic/#defdbl) | BASIC | [POKE](basic/#poke) | BASIC |
| [DEFINT](basic/#defint) | BASIC | [PRESET](device/graphics/#preset) | Graphics |
| [DEFSNG](basic/#defsng) | BASIC | [PRINT](device/screen/#print) | Screen |
| [DEFSTR](basic/#defstr) | BASIC | [PSET](device/graphics/#pset) | Graphics |
| [DEL](disk/#del) | Disk | [PUT](device/graphics/#put) | Graphics |
| [DELETE](system/#delete) | System | [READ](basic/#read) | BASIC |
| [DIM](basic/#dim) | BASIC | [REM](basic/#rem) | BASIC |
| [DIR](disk/#dir) | Disk | [REN](disk/#ren) | Disk |
| [DRAW](device/graphics/#draw) | Graphics | [RENAME](disk/#ren) | Disk |
| [ECHO](device/screen/#echo) | Screen | [RESTART](system/#restart) | System |
| [EDIT](system/#edit) | System | [RESTORE](basic/#restore) | BASIC |
| [END](basic/#end) | BASIC | [RESUME](basic/#resume) | BASIC |
| [ERASE](basic/#erase) | BASIC | [RETURN](basic/return/) | BASIC |
| [ERROR](basic/#error) | BASIC | [RUN](system/#run) | System |
| [EXIT](system/#exit) | System | [SAVE](disk/#save) | Disk |
| [FOR](basic/#for) | BASIC | [SCREEN](device/screen/#screen) | Screen |
| [GET](device/graphics/#get) | Graphics | [SOUND](device/sound/#sound) | Sound |
| [GOSUB](basic/#gosub) | BASIC | [STOP](basic/#end) | BASIC |
| [GOTO](basic/goto/) | BASIC | [TIME](device/clock/#time) | Clock |
| [HELP](system/#help) | System | [TYPE](disk/#type) | Disk |
| [IF](basic/if/) | BASIC | [VER](system/#ver) | System |
| [IOCTL](basic/#ioctl) | BASIC | [VIEW](device/graphics/#view) | Graphics |
| [KEY](device/keyboard/#key) | Keyboard | [WEND](basic/#while) | BASIC |
| [KEYS](system/#keys) | System | [WHILE](basic/#while) | BASIC |
| [LET](basic/let/) | BASIC | [WIDTH](device/screen/#width) | Screen |
| [LINE](device/graphics/#line) | Graphics | [WINDOW](device/graphics/#window) | Graphics |
| [LIST](system/#list) | System |  |  |
See [BASIC Functions](basic/func/) for the list of functions and predefined constants.

REN (RENAME) and MV share the same file and directory rename and move command; see [REN](disk/#ren).

### Not Yet Supported

The following commands and statements from PC DOS and IBM PC BASIC aren't supported yet:

- PC DOS commands: CHKDSK, DISKCOPY, PAUSE, and SYS (FORMAT and MODE are BASIC programs in the EXT directory; see [External Commands](external/))
- BASIC statements: the MID$ statement

{% include footer.html prev="Contents:../" next="BASIC Commands:basic/" %}
