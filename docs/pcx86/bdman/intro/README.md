---
layout: sheet
title: Using BASIC-DOS
permalink: /docs/pcx86/bdman/intro/
---

{% include header.html %}

### Starting BASIC-DOS

Insert a BASIC-DOS diskette in drive A: of an IBM PC and turn the machine on.
The following messages should appear on your screen:

	BASIC-DOS 1.00 for the IBM PC
	Copyright (c) PCJS.ORG 1981-2021

	BASIC-DOS Interpreter

	A>

The `A>` is the BASIC-DOS prompt.  The prompt displays which
diskette drive is the default and indicates that BASIC-DOS is ready to accept
[commands](../cmd/) from the keyboard.

### Typing Commands

The BASIC-DOS prompt accepts commands up to 254 characters long.  Any characters
typed beyond that limit are ignored.  Press the **Enter** key to submit all
characters currently displayed as the next command.

Other special keys include:

- **Backspace** deletes the previous character
- **Esc** erases the entire line
- **Up Arrow** displays the previous line (also: **Ctrl-E**)
- **Down Arrow** displays the next line (also: **Ctrl-X**)
- **Left Arrow** moves the cursor left one character (also: **Ctrl-S**)
- **Right Arrow** moves the cursor right one character (also: **Ctrl-D**)
- **Home** moves the cursor to the beginning of the line (also: **Ctrl-W**)
- **End** moves the cursor to the end of the line (also: **Ctrl-R**)
- **Ctrl-Left Arrow** moves the cursor left one word (also: **Ctrl-A**)
- **Ctrl-Right Arrow** moves the cursor right one word (also: **Ctrl-F**)
- **Del** deletes the current character (also: **Ctrl-G**)
- **Ins** toggles the current Insert/Overwrite mode (also: **Ctrl-V**)
- **Ctrl-End** deletes all characters to the end of the line (also: **Ctrl-K**)

Other special key sequences that can be typed at any time include:

- **Ctrl-Break** aborts the current operation (also: **Ctrl-C**)
- **Ctrl-Alt-Del** terminates the current program

You can also use the [HELP KEYS](../cmd/system/#help) command to display a brief
summary of special keys.

{% include footer.html prev="Contents:../" next="BASIC-DOS Commands:../cmd/" %}
