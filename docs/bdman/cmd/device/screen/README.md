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

When a BAS program that used a graphics mode ends (or is aborted), the video mode it started with is restored, along with the console's original size and border, even if the program returned to a text mode first (eg, DONKEY.BAS, whose SCREEN 0 leaves 40 columns); otherwise, text-mode changes (eg, WIDTH 40 or SCREEN 0,0) persist, as in Microsoft BASIC.

### CLS

> CLS

Clears the console using the background color and moves the cursor to the top left corner.

### COLOR

> COLOR [*foreground*][,[*background*][,*border*]]

Sets the foreground (0-15), background (0-7), and border (0-255) colors of the console.  For blinking colors, use 16-31 for *foreground* and 128-255 for *border*; as in MSBASIC, a *background* of 8-15 is the same as 0-7 (it doesn't make the foreground blink).  Omitted values are unchanged (eg, `COLOR ,1`).

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

On the PC's display, as in PC DOS, control characters other than BELL (7, which beeps), BACKSPACE (8), TAB (9), LINEFEED (10), and RETURN (13) are displayed as the PC's graphic characters (eg, `PRINT CHR$(14)` displays a musical note); unlike IBM PC BASIC, characters such as CHR$(12) and CHR$(28)-CHR$(31) don't clear the screen or move the cursor.  On a serial console, they're sent to the terminal as they are.

### PRINTF

> PRINTF USING *format*;[*value*][,|;][*value*]...

Prints the values using the C-style specifiers in *format*, as a simpler alternative to the PRINT USING of other BASICs.  Each `%` specifier takes the next value: `%d` or `%u` prints a number (`%x` in hexadecimal, and `%#d` with a leading space for positive numbers, like PRINT), `%f` prints a double (BASIC-style unless a precision is given), `%s` prints a string, and `%c` prints a character (from a number or the first character of a string).  Specifiers accept the `-` flag (left-justify), a width, and a precision (eg, `%5d`, `%-8.3s`, `%.2f`), and `%%` prints a percent sign.  Other specifiers print part of a number that holds a packed DOS date or time (eg, from a [DIR$](../../basic/func/#dir) entry): `%M`, `%D`, and `%Y` print a date's month, day, and year (`%X` prints the year with 2 digits), `%F` and `%W` print the names of its month and day of the week (eg, `%.3F` prints `Oct`), and `%H`, `%N`, and `%S` print a time's hour, minute, and second (`%G` prints a 12-hour hour, and `%A` prints `a` or `p`).  Since the values carry their own types, size modifiers like `l` are unnecessary, and a value of the wrong type prints its specifier unchanged.  As with PRINT, the cursor moves to the next line unless the list ends with a semicolon or comma.  [PRINTF #](../../basic/#printf) writes the same output to a file.

	PRINTF USING "%-6s|%5d|%.2f"; "abc", 42, 3.14159
	abc   |   42|3.14

Comma print zones aren't supported yet (commas currently print a tab).  PRINT USING isn't supported, and won't be, since PRINTF USING covers the same needs (see below).

#### How to replace PRINT USING

The PRINT USING (and LPRINT USING) statement of other BASICs formats values with templates, such as `"###.##"`.  To convert one to PRINTF USING, replace each field of the template with the corresponding specifier:

| PRINT USING | PRINTF USING | Notes |
|-------------|--------------|-------|
| `!` | `%.1s` or `%c` | The first character of a string |
| `\  \` | `%-4.4s` | The first *n* characters of a string (here, 4), padded with spaces to *n* |
| `&` | `%s` | The entire string |
| `###` | `%3d` or `%3.0f` | A number, right-justified in a field as wide as the `#`s; `%d` for an integer, `%f` for a double |
| `###.##` | `%6.2f` | A double, with as many decimal places as `#`s after the point (the width includes the point) |
| `+###` or `###-` | None | PRINTF has no `+` flag; `%#d` prints a space before a positive integer, as PRINT does |
| `**###.##` | None | PRINTF can't fill with asterisks; `%06.2f` fills with zeros instead |
| `$$###.##` | `$%.2f` | A dollar sign right before the number (but without a fixed width); `$%7.2f` puts it at the start of the field instead |
| `#,###.##` | None | PRINTF doesn't insert thousands separators |
| `##.##^^^^` | `%f` | PRINTF has no exponential format, but `%f` without a precision prints very large or small numbers in exponential form (eg, `1E+20`), as PRINT does |
| `_` | Omit it | `_` prints the next character literally, which PRINTF does anyway (except `%`, which must be `%%`) |
| Other characters | Same | Literal text |

The other differences to watch for:

- **Repeating fields**: PRINT USING reuses its template for each value, but PRINTF USING uses each specifier once (and ignores extra values), so repeat the specifiers instead (eg, `PRINT USING "###";A;B;C` becomes `PRINTF USING "%3d%3d%3d";A;B;C`).
- **Types**: `%d` requires an integer and `%f` requires a double, and a value of the wrong type prints its specifier as-is.  Variables without a suffix are doubles in BAS files but integers in BAT files, and constants without a decimal point or exponent (eg, `42`) are integers (see [Variables and Types](../../../lang/#variables-and-types)), so use CINT or CDBL to convert a value when necessary (eg, `PRINTF USING "%3d";CINT(I)`).
- **Overflow**: when a number doesn't fit in its field, PRINT USING prints a `%` before it, but PRINTF simply widens the field.
- **Rounding**: PRINTF rounds a number that's exactly halfway to the nearest even digit (eg, `%.0f` prints 2.5 as 2), whereas PRINT USING rounds it up.

For example, the MORTGAGE.BAS sample (in the SAMPLES directory) printed its amortization table with:

	2730 PRINT USING "### ";I;
	2740 PRINT USING "  ######.##";PF-AMORT(I,2);AMORT(I,2);AMORT(I,1)

and now prints it with:

	2730 PRINTF USING "%3.0f ";I;
	2740 PRINTF USING "  %9.2f  %9.2f  %9.2f";PF-AMORT(I,2);AMORT(I,2);AMORT(I,1)

### LPRINT

> LPRINT [*expression*][;|,][*expression*]...

Prints like [PRINT](#print), but to the printer (PRN, which is the first parallel port, LPT1, unless [PRN=](../../../cfg/#prn) in CONFIG.SYS chooses another device).  If there's no PRN device (eg, the machine has no parallel port), a "Device unavailable" error occurs after the statement, and a printer can report "Device timeout" (eg, if it's offline), "Out of paper", or "Device fault"; [PRINT #](../../basic/#print) to a printer (eg, a file opened as "PRN" or "LPT2") reports the same errors.  See also [LLIST](../../system/#llist) and [LPOS](../../basic/func/#lpos).  LPRINT USING isn't supported; to format output for the printer, open PRN as a file and use PRINTF #*n* (see [How to replace PRINT USING](#how-to-replace-print-using)).  LPRINT isn't available on low memory systems.

	LPRINT "Total:"; T

### SCREEN

> SCREEN [*mode*][,*burst*]

Sets the screen mode on a color adapter:

- 0: text
- 1: 320x200 graphics (4 colors)
- 2: 640x200 graphics (2 colors)

A *burst* of 0 disables color in mode 0, and a *burst* of 1 disables color in mode 1.  Changing the mode clears the screen and removes the console's border, if any, so the console occupies the entire screen.  Text output (eg, PRINT) works in all modes.

While a session is in any mode other than its original mode (eg, a graphics mode, or 40 columns in an 80-column session), it uses the entire screen, so other sessions on the same display are paused: any output they produce waits until that session returns to its original mode (eg, when its BAS program ends, which restores the mode), and then their borders are redrawn and their output continues.  Their earlier screen contents are not restored.

### WIDTH

> WIDTH 40|80  
> WIDTH *device*,*width*

Sets the number of columns in text mode (which clears the screen).  In SCREEN 1, WIDTH 80 selects SCREEN 2, and in SCREEN 2, WIDTH 40 selects SCREEN 1.

With a *device* name (a string), `WIDTH "SCRN:",`*width* is the same as WIDTH *width*.  For any other device (eg, `WIDTH "COM1:",255`), Microsoft BASIC sets the line width of the device's output (where 255 means lines are never broken), but BASIC-DOS never breaks a device's output into lines, so the *width* (1-255) is only checked, for compatibility.  WIDTH *device* isn't available on low memory systems (see [Low Memory](../../../lang/#low-memory)).

{% include footer.html prev="Mouse Commands:../mouse/" next="Graphics Commands:../graphics/" %}
