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
| [AUTO](system/#auto) | System | [LOCATE](device/screen/#locate) | Screen |
| [CD](disk/#cd) | Disk | [LPRINT](device/screen/#lprint) | Screen |
| [CHAIN](basic/#chain) | BASIC | [MD](disk/#md) | Disk |
| [CIRCLE](device/graphics/#circle) | Graphics | [MEM](system/#mem) | System |
| [CLEAR](basic/#clear) | BASIC | [MERGE](disk/#merge) | Disk |
| [CLS](device/screen/#cls) | Screen | [MOUSE](device/mouse/#mouse) | Mouse |
| [COLOR](device/screen/#color) | Screen | [NEW](system/#new) | System |
| [COPY](disk/#copy) | Disk | [NEXT](basic/#for) | BASIC |
| [DATA](basic/#data) | BASIC | [ON](basic/#on) | BASIC |
| [DATE](device/clock/#date) | Clock | [OPTION BASE](basic/#option-base) | BASIC |
| [DEF](basic/def/) | BASIC | [PAINT](device/graphics/#paint) | Graphics |
| [DEF SEG](basic/#def-seg) | BASIC | [PLAY](device/sound/#play) | Sound |
| [DEFDBL](basic/#defdbl) | BASIC | [POKE](basic/#poke) | BASIC |
| [DEFINT](basic/#defint) | BASIC | [PRESET](device/graphics/#preset) | Graphics |
| [DEFSTR](basic/#defstr) | BASIC | [PRINT](device/screen/#print) | Screen |
| [DEL](disk/#del) | Disk | [PSET](device/graphics/#pset) | Graphics |
| [DELETE](system/#delete) | System | [PUT](device/graphics/#put) | Graphics |
| [DIM](basic/#dim) | BASIC | [RD](disk/#rd) | Disk |
| [DIR](disk/#dir) | Disk | [READ](basic/#read) | BASIC |
| [DRAW](device/graphics/#draw) | Graphics | [REM](basic/#rem) | BASIC |
| [ECHO](device/screen/#echo) | Screen | [REN](disk/#ren) | Disk |
| [EDIT](system/#edit) | System | [RESTORE](basic/#restore) | BASIC |
| [END](basic/#end) | BASIC | [RESUME](basic/#resume) | BASIC |
| [ERASE](basic/#erase) | BASIC | [RETURN](basic/return/) | BASIC |
| [ERROR](basic/#error) | BASIC | [RUN](system/#run) | System |
| [EXIT](system/#exit) | System | [SAVE](disk/#save) | Disk |
| [FOR](basic/#for) | BASIC | [SCREEN](device/screen/#screen) | Screen |
| [GET](device/graphics/#get) | Graphics | [SOUND](device/sound/#sound) | Sound |
| [GOSUB](basic/#gosub) | BASIC | [START](system/#start) | System |
| [GOTO](basic/goto/) | BASIC | [STOP](basic/#end) | BASIC |
| [IF](basic/if/) | BASIC | [TIME](device/clock/#time) | Clock |
| [IOCTL](basic/#ioctl) | BASIC | [TYPE](disk/#type) | Disk |
| [KEY](device/keyboard/#key) | Keyboard | [VER](system/#ver) | System |
| [KILL](system/#kill) | System | [VIEW](device/graphics/#view) | Graphics |
| [LET](basic/let/) | BASIC | [WEND](basic/#while) | BASIC |
| [LINE](device/graphics/#line) | Graphics | [WHILE](basic/#while) | BASIC |
| [LIST](system/#list) | System | [WIDTH](device/screen/#width) | Screen |
| [LLIST](system/#llist) | System | [WINDOW](device/graphics/#window) | Graphics |
| [LOAD](disk/#load) | Disk | | |
See [BASIC Functions](basic/func/) for the list of functions and predefined constants.

### Not Yet Supported

The following commands, statements, and functions from PC DOS and IBM PC BASIC aren't supported yet:

- PC DOS commands: DISKCOMP and PRINT (background printing); the other PC DOS 1.00 utilities (eg, CHKDSK, DISKCOPY, FORMAT, and SYS) are BASIC programs in the EXT directory (see [External Commands](external/))
- BASIC statements: BEEP, BLOAD, BSAVE, CALL, CHAIN's DELETE option, COMMON, CONT, DEF USR, OUT, PCOPY, RUN *line* (and RUN's R option), TRON, TROFF, WAIT, WIDTH LPRINT, and event trapping (eg, ON TIMER(*n*) GOSUB)
- BASIC functions: INP, STICK, STRIG, USR, VARPTR, and VARPTR$

Some features of PC DOS and IBM PC BASIC aren't planned at all, such as PAUSE and the rest of PC DOS's batch file syntax (BAT files are BASIC programs; see [Batch Files](../lang/#batch-files)), CTTY (see [CON=](../cfg/#con)), and PRINT USING (see [How to replace PRINT USING](device/screen/#how-to-replace-print-using)).

{% include footer.html prev="Contents:../" next="BASIC Commands:basic/" %}
