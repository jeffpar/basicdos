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
| [DRAW](device/graphics/#draw) | Graphics | [RESTART](system/#restart) | System |
| [ECHO](device/screen/#echo) | Screen | [RESTORE](basic/#restore) | BASIC |
| [EDIT](system/#edit) | System | [RESUME](basic/#resume) | BASIC |
| [END](basic/#end) | BASIC | [RETURN](basic/return/) | BASIC |
| [ERASE](basic/#erase) | BASIC | [RUN](system/#run) | System |
| [ERROR](basic/#error) | BASIC | [SAVE](disk/#save) | Disk |
| [EXIT](system/#exit) | System | [SCREEN](device/screen/#screen) | Screen |
| [FOR](basic/#for) | BASIC | [SOUND](device/sound/#sound) | Sound |
| [GET](device/graphics/#get) | Graphics | [STOP](basic/#end) | BASIC |
| [GOSUB](basic/#gosub) | BASIC | [TIME](device/clock/#time) | Clock |
| [GOTO](basic/goto/) | BASIC | [TYPE](disk/#type) | Disk |
| [HELP](system/#help) | System | [VER](system/#ver) | System |
| [IF](basic/if/) | BASIC | [WEND](basic/#while) | BASIC |
| [KEY](device/keyboard/#key) | Keyboard | [WHILE](basic/#while) | BASIC |
| [KEYS](system/#keys) | System | [WIDTH](device/screen/#width) | Screen |

See [BASIC Functions](basic/func/) for the list of functions and predefined constants.

### Not Yet Supported

The following commands and statements from PC DOS and IBM PC BASIC aren't supported yet:

- PC DOS commands: CHKDSK, DISKCOPY, FORMAT, PAUSE, REN, SYS, and directory commands (CHDIR, MKDIR, RMDIR)
- BASIC statements: INPUT, LINE INPUT, the MID$ statement, and file I/O statements (eg, OPEN, CLOSE, PRINT #, and INPUT #)

{% include footer.html prev="Contents:../" next="BASIC Commands:basic/" %}
