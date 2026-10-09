---
layout: sheet
title: BASIC-DOS Screen Commands
permalink: /docs/bdman/cmd/device/screen/
---

{% include header.html %}

Screen commands include:

- [CLS](#cls)
- [COLOR](#color)
- [ECHO](#echo)
- [LOCATE](#locate)
- [PRINT](#print)
- [SCREEN](#screen)
- [WIDTH](#width)

Each session has its own console, which may occupy only part of the screen (see [Sessions](../../../intro/#sessions)).  Screen commands operate on the current session's console, and coordinates are relative to the console, not the screen.

When a BAS program ends (or is aborted), the video mode it started with is restored, undoing any SCREEN or WIDTH changes, and the console's original size and border are restored as well.

### CLS

> CLS

Clears the console using the background color and moves the cursor to the top left corner.

### COLOR

> COLOR [*foreground*][,[*background*][,*border*]]

Sets the foreground (0-15), background (0-15), and border (0-255) colors of the console.  For blinking colors, use 16-31 for *foreground*, 8-15 for *background*, and 128-255 for *border*.  Omitted values are unchanged (eg, `COLOR ,1`).

In SCREEN 1, the values are the background color (0-15) and palette (0 or 1) instead.

The colors are:

| 0 Black | 4 Red | 8 Gray | 12 Light Red |
| 1 Blue | 5 Magenta | 9 Light Blue | 13 Light Magenta |
| 2 Green | 6 Brown | 10 Light Green | 14 Yellow |
| 3 Cyan | 7 White | 11 Light Cyan | 15 Bright White |

### ECHO

> ECHO [ON|OFF]

Controls the echo of lines in a BAT file.  After ECHO ON, a BAT file echoes each line before running it, until ECHO OFF is used; a line beginning with `@` is never echoed (eg, `@ECHO ON`).  Echoed lines are displayed with a `@` in front (eg, `@REM Starting`), where PC DOS would display a prompt.  ECHO without ON or OFF displays the current setting.

Every BAT file run from the prompt (or by a startup command) starts with ECHO OFF, unlike PC DOS, so BAT files behave like BAS files unless ECHO ON is used; the setting remains in effect when one BAT file runs another.  BAS files never echo their lines.  A `@` at the start of a command typed at the prompt is ignored, as in later versions of PC DOS.

### LOCATE

> LOCATE [*row*][,[*col*][,*cursor*]]

Moves the cursor to the specified *row* and *col* (starting at 1,1), and hides (0) or shows (1) the cursor.  The cursor remains hidden until the next input.  Omitted values are unchanged.

### PRINT

> PRINT [*expression*][;|,][*expression*]...

Prints a series of values, separated by semicolons or commas.  A semicolon prints the next value immediately after the previous one, and a comma prints a tab.  Numbers are printed with a leading space (or minus sign) and a trailing space.  If the list ends with a semicolon or comma, the cursor remains on the same line; otherwise, PRINT moves to the next line.  [PRINT #](../../basic/#print) writes the same output to a file.

	PRINT "A"; 1; "B", 2
	A 1 B	 2

Comma print zones aren't supported yet (commas currently print a tab), and neither is PRINT USING.

### SCREEN

> SCREEN [*mode*][,*burst*]

Sets the screen mode on a color adapter:

- 0: text
- 1: 320x200 graphics (4 colors)
- 2: 640x200 graphics (2 colors)

A *burst* of 0 disables color in mode 0, and a *burst* of 1 disables color in mode 1.  Changing the mode clears the screen and removes the console's border, if any, so the console occupies the entire screen.  Text output (eg, PRINT) works in all modes.

### WIDTH

> WIDTH 40|80

Sets the number of columns in text mode (which clears the screen).  In SCREEN 1, WIDTH 80 selects SCREEN 2, and in SCREEN 2, WIDTH 40 selects SCREEN 1.

{% include footer.html prev="Mouse Commands:../mouse/" next="Graphics Commands:../graphics/" %}
