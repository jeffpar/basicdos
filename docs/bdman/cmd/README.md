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
- [External Commands](external/): COM, EXE, BAT, and BAS programs (including [HELP](external/help/))
- [System Commands](system/): memory, program management, and system control

In the descriptions that follow, *italics* indicate values that you supply, brackets (`[` `]`) indicate optional items, a vertical bar (`|`) separates alternatives, and `...` means that the item before it can be repeated.  A statement with more than one form shows each form on a line of its own.  A file number is written #*n*: in OPEN, CLOSE, FIELD, GET, PUT, IOCTL, and INPUT$, the # is optional, and as in Microsoft BASIC, the space before a # is optional, too (eg, `PRINT#1,X`).

As in MS-DOS, a DOS command typed as one word with a path (eg, `CD\`, `CD\EXT`, or `DIR\EXT`) doesn't need a space before the path.  Unlike MS-DOS, however, a command followed by a path that begins with `.` (eg, `CD..`) still needs a space (eg, `CD ..`).

A command given a switch it doesn't accept (eg, `DIR /Z` or `CD ../..`), or arguments that aren't valid, displays `Syntax error`, and to see how to use any command, type [HELP](external/help/) followed by its name.

### Commands A-Z

| Command | Category | Command | Category |
|---------|----------|---------|----------|
| [AUTO](system/#auto) | System | [LOAD](disk/#load) | Disk |
| [CD](disk/#cd) | Disk | [LOCATE](device/screen/#locate) | Screen |
| [CHAIN](basic/#chain) | BASIC | [LPRINT](device/screen/#lprint) | Screen |
| [CIRCLE](device/graphics/#circle) | Graphics | [MD](disk/#md) | Disk |
| [CLEAR](basic/#clear) | BASIC | [MEM](system/#mem) | System |
| [CLS](device/screen/#cls) | Screen | [MERGE](disk/#merge) | Disk |
| [COLOR](device/screen/#color) | Screen | [MOUSE](device/mouse/#mouse) | Mouse |
| [COPY](disk/#copy) | Disk | [NEW](system/#new) | System |
| [DATA](basic/#data) | BASIC | [NEXT](basic/#for) | BASIC |
| [DATE](device/clock/#date) | Clock | [ON](basic/#on) | BASIC |
| [DEF](basic/def/) | BASIC | [OPTION BASE](basic/#option-base) | BASIC |
| [DEF SEG](basic/#def-seg) | BASIC | [PAINT](device/graphics/#paint) | Graphics |
| [DEFDBL](basic/#defdbl) | BASIC | [PLAY](device/sound/#play) | Sound |
| [DEFINT](basic/#defint) | BASIC | [POKE](basic/#poke) | BASIC |
| [DEFSTR](basic/#defstr) | BASIC | [PRESET](device/graphics/#preset) | Graphics |
| [DEL](disk/#del) | Disk | [PRINT](device/screen/#print) | Screen |
| [DELETE](system/#delete) | System | [PSET](device/graphics/#pset) | Graphics |
| [DIM](basic/#dim) | BASIC | [PUT](device/graphics/#put) | Graphics |
| [DIR](disk/#dir) | Disk | [RD](disk/#rd) | Disk |
| [DRAW](device/graphics/#draw) | Graphics | [READ](basic/#read) | BASIC |
| [ECHO](device/screen/#echo) | Screen | [REM](basic/#rem) | BASIC |
| [EDIT](system/#edit) | System | [REN](disk/#ren) | Disk |
| [END](basic/#end) | BASIC | [RESTORE](basic/#restore) | BASIC |
| [ERASE](basic/#erase) | BASIC | [RESUME](basic/#resume) | BASIC |
| [ERROR](basic/#error) | BASIC | [RETURN](basic/return/) | BASIC |
| [EXIT](system/#exit) | System | [RUN](system/#run) | System |
| [FOR](basic/#for) | BASIC | [SAVE](disk/#save) | Disk |
| [GET](device/graphics/#get) | Graphics | [SCREEN](device/screen/#screen) | Screen |
| [GOSUB](basic/#gosub) | BASIC | [SOUND](device/sound/#sound) | Sound |
| [GOTO](basic/goto/) | BASIC | [STOP](basic/#end) | BASIC |
| [IF](basic/if/) | BASIC | [TIME](device/clock/#time) | Clock |
| [IOCTL](basic/#ioctl) | BASIC | [TYPE](disk/#type) | Disk |
| [KEY](device/keyboard/#key) | Keyboard | [VER](system/#ver) | System |
| [KILL](system/#kill) | System | [VIEW](device/graphics/#view) | Graphics |
| [LET](basic/let/) | BASIC | [WEND](basic/#while) | BASIC |
| [LINE](device/graphics/#line) | Graphics | [WHILE](basic/#while) | BASIC |
| [LIST](system/#list) | System | [WIDTH](device/screen/#width) | Screen |
| [LLIST](system/#llist) | System | [WINDOW](device/graphics/#window) | Graphics |
See [BASIC Functions](basic/func/) for the list of functions and predefined constants.

### Not Yet Supported

The following commands, statements, and functions from PC DOS and IBM PC BASIC aren't supported yet:

- PC DOS commands: DISKCOMP and PRINT (background printing); the other PC DOS 1.00 utilities (eg, CHKDSK, DISKCOPY, FORMAT, and SYS) are BASIC programs in the EXT directory (see [External Commands](external/))
- BASIC statements: BEEP, BLOAD, BSAVE, CALL, CHAIN's DELETE option, COMMON, CONT, DEF USR, OUT, PCOPY, RUN *line* (and RUN's R option), TRON, TROFF, WAIT, WIDTH LPRINT, and event trapping (eg, ON TIMER(*n*) GOSUB)
- BASIC functions: INP, STICK, STRIG, USR, VARPTR, and VARPTR$

Some features of PC DOS and IBM PC BASIC aren't planned at all, such as PAUSE and the rest of PC DOS's batch file syntax (BAT files are BASIC programs; see [Batch Files](../lang/#batch-files)), CTTY (see [CON=](../cfg/#con)), and PRINT USING (see [How to replace PRINT USING](device/screen/#how-to-replace-print-using)).

{% include footer.html prev="Contents:../" next="BASIC Commands:basic/" %}
