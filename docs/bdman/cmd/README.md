---
layout: sheet
title: BASIC-DOS Commands
permalink: /docs/bdman/cmd/
---

{% include header.html %}

BASIC-DOS has a single command processor for both DOS commands (eg, DIR) and BASIC statements (eg, PRINT), so any command can be typed at the prompt or used in a BASIC program.  Commands are organized as follows:

- [BASIC Commands](basic/): statements for variables, control flow, error handling, and memory
- [BASIC Functions](basic/func/): numeric, string, and system functions, and predefined constants
- [Device Commands](device/): clock, keyboard, screen, graphics, and sound
- [Disk Commands](disk/): copying, deleting, listing, loading, and displaying files
- [External Commands](external/): COM, EXE, BAT, and BAS programs
- [System Commands](system/): help, memory, program management, and system control

In the descriptions that follow, *italics* indicate values that you supply, brackets (`[` `]`) indicate optional items, and a vertical bar (`|`) separates alternatives.

### Commands A-Z

| Command | Category | Command | Category |
|---------|----------|---------|----------|
| [AUTO](system/#auto) | System | [LET](basic/let/) | BASIC |
| [CHAIN](basic/#chain) | BASIC | [LINE](device/graphics/#line) | Graphics |
| [CIRCLE](device/graphics/#circle) | Graphics | [LIST](system/#list) | System |
| [CLEAR](basic/#clear) | BASIC | [LOAD](disk/#load) | Disk |
| [CLS](device/screen/#cls) | Screen | [LOCATE](device/screen/#locate) | Screen |
| [COLOR](device/screen/#color) | Screen | [MEM](system/#mem) | System |
| [COPY](disk/#copy) | Disk | [NEW](system/#new) | System |
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
| [DIR](disk/#dir) | Disk | [REM](basic/#rem) | BASIC |
| [DRAW](device/graphics/#draw) | Graphics | [RESTART](system/#restart) | System |
| [ECHO](device/screen/#echo) | Screen | [RESUME](basic/#resume) | BASIC |
| [EDIT](system/#edit) | System | [RETURN](basic/return/) | BASIC |
| [END](basic/#end) | BASIC | [RUN](system/#run) | System |
| [ERASE](basic/#erase) | BASIC | [SAVE](disk/#save) | Disk |
| [ERROR](basic/#error) | BASIC | [SCREEN](device/screen/#screen) | Screen |
| [EXIT](system/#exit) | System | [SOUND](device/sound/#sound) | Sound |
| [FOR](basic/#for) | BASIC | [STOP](basic/#end) | BASIC |
| [GET](device/graphics/#get) | Graphics | [TIME](device/clock/#time) | Clock |
| [GOSUB](basic/#gosub) | BASIC | [TYPE](disk/#type) | Disk |
| [GOTO](basic/goto/) | BASIC | [VER](system/#ver) | System |
| [HELP](system/#help) | System | [WEND](basic/#while) | BASIC |
| [IF](basic/if/) | BASIC | [WHILE](basic/#while) | BASIC |
| [KEY](device/keyboard/#key) | Keyboard | [WIDTH](device/screen/#width) | Screen |
| [KEYS](system/#keys) | System |  |  |

See [BASIC Functions](basic/func/) for the list of functions and predefined constants.

### Not Yet Supported

The following commands and statements from PC DOS and IBM PC BASIC aren't supported yet:

- PC DOS commands: CHKDSK, DISKCOPY, FORMAT, PAUSE, REN, SYS, and directory commands (CHDIR, MKDIR, RMDIR)
- BASIC statements: DATA, INPUT, LINE INPUT, READ, RESTORE, the MID$ statement, and file I/O statements (eg, OPEN, CLOSE, PRINT #, and INPUT #)

{% include footer.html prev="Contents:../" next="BASIC Commands:basic/" %}
