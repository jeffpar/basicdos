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
| [CHAIN](basic/#chain) | BASIC | [LIST](system/#list) | System |
| [CIRCLE](device/graphics/#circle) | Graphics | [LOAD](disk/#load) | Disk |
| [CLEAR](basic/#clear) | BASIC | [LOCATE](device/screen/#locate) | Screen |
| [CLS](device/screen/#cls) | Screen | [MEM](system/#mem) | System |
| [COLOR](device/screen/#color) | Screen | [NEW](system/#new) | System |
| [COPY](disk/#copy) | Disk | [NEXT](basic/#for) | BASIC |
| [DATE](device/clock/#date) | Clock | [ON](basic/#on) | BASIC |
| [DEF](basic/def/) | BASIC | [OPTION BASE](basic/#option-base) | BASIC |
| [DEF SEG](basic/#def-seg) | BASIC | [PAINT](device/graphics/#paint) | Graphics |
| [DEFDBL](basic/#defdbl) | BASIC | [PLAY](device/sound/#play) | Sound |
| [DEFINT](basic/#defint) | BASIC | [POKE](basic/#poke) | BASIC |
| [DEFSNG](basic/#defsng) | BASIC | [PRESET](device/graphics/#preset) | Graphics |
| [DEFSTR](basic/#defstr) | BASIC | [PRINT](device/screen/#print) | Screen |
| [DEL](disk/#del) | Disk | [PSET](device/graphics/#pset) | Graphics |
| [DIM](basic/#dim) | BASIC | [PUT](device/graphics/#put) | Graphics |
| [DIR](disk/#dir) | Disk | [REM](basic/#rem) | BASIC |
| [DRAW](device/graphics/#draw) | Graphics | [RESTART](system/#restart) | System |
| [ECHO](device/screen/#echo) | Screen | [RESUME](basic/#resume) | BASIC |
| [END](basic/#end) | BASIC | [RETURN](basic/return/) | BASIC |
| [ERASE](basic/#erase) | BASIC | [RUN](system/#run) | System |
| [ERROR](basic/#error) | BASIC | [SCREEN](device/screen/#screen) | Screen |
| [EXIT](system/#exit) | System | [SOUND](device/sound/#sound) | Sound |
| [FOR](basic/#for) | BASIC | [STOP](basic/#end) | BASIC |
| [GET](device/graphics/#get) | Graphics | [TIME](device/clock/#time) | Clock |
| [GOSUB](basic/#gosub) | BASIC | [TYPE](disk/#type) | Disk |
| [GOTO](basic/goto/) | BASIC | [VER](system/#ver) | System |
| [HELP](system/#help) | System | [WEND](basic/#while) | BASIC |
| [IF](basic/if/) | BASIC | [WHILE](basic/#while) | BASIC |
| [KEY](device/keyboard/#key) | Keyboard | [WIDTH](device/screen/#width) | Screen |
| [KEYS](system/#keys) | System | | |
| [LET](basic/let/) | BASIC | | |
| [LINE](device/graphics/#line) | Graphics | | |

See [BASIC Functions](basic/func/) for the list of functions and predefined constants.

### Not Yet Supported

The following commands and statements from PC DOS and IBM PC BASIC aren't supported yet:

- PC DOS commands: CHKDSK, DISKCOPY, FORMAT, PAUSE, REN, SYS, and directory commands (CHDIR, MKDIR, RMDIR)
- BASIC statements: DATA, INPUT, LINE INPUT, READ, RESTORE, SAVE, the MID$ statement, and file I/O statements (eg, OPEN, CLOSE, PRINT #, and INPUT #)

{% include footer.html prev="Contents:../" next="BASIC Commands:basic/" %}
