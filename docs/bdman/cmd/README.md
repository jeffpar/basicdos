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

As in MS-DOS, a DOS command typed as one word with a path (eg, `CD\`, `CD\BIN`, or `DIR\HELP.TXT`) doesn't need a space before the path.  Unlike MS-DOS, however, a command followed by a path that begins with `.` (eg, `CD..`) still needs a space (eg, `CD ..`).

### Commands A-Z

| Command | Category | Command | Category |
|---------|----------|---------|----------|
| [AUTO](system/#auto) | System | [LIST](system/#list) | System |
| [CHAIN](basic/#chain) | BASIC | [LOAD](disk/#load) | Disk |
| [CIRCLE](device/graphics/#circle) | Graphics | [LOCATE](device/screen/#locate) | Screen |
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
| [KEY](device/keyboard/#key) | Keyboard | [WEND](basic/#while) | BASIC |
| [KEYS](system/#keys) | System | [WHILE](basic/#while) | BASIC |
| [LET](basic/let/) | BASIC | [WIDTH](device/screen/#width) | Screen |
| [LINE](device/graphics/#line) | Graphics |  |  |
See [BASIC Functions](basic/func/) for the list of functions and predefined constants.

REN (RENAME) and MV share the same file and directory rename and move command; see [REN](disk/#ren).

### Not Yet Supported

The following commands and statements from PC DOS and IBM PC BASIC aren't supported yet:

- PC DOS commands: CHKDSK, DISKCOPY, PAUSE, and SYS (FORMAT and MODE are BASIC programs in the BIN directory; see [External Commands](external/))
- BASIC statements: the MID$ statement

{% include footer.html prev="Contents:../" next="BASIC Commands:basic/" %}
