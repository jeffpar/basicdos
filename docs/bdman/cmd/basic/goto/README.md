---
layout: sheet
title: BASIC-DOS BASIC Commands
permalink: /docs/bdman/cmd/basic/goto/
---

{% include header.html topic="GOTO" %}

The **GOTO** statement transfers control to another line:

> GOTO *label*

where *label* is the line number of a line within the current program.

Example:

	LET R = 1
	10 PRINT "R ="; R, "AREA ="; 3.14 * R^2
	LET R = R + 1
	IF R <= 3 THEN GOTO 10

	R = 1   AREA = 3.14
	R = 2   AREA = 12.56
	R = 3   AREA = 28.26

### Differences from Microsoft BASIC

BASIC-DOS does *not* require all lines within a program to begin with a line number.  Only those lines that are the target of a GOTO (or GOSUB, RESUME, etc) must be numbered, and line numbers don't need to be in any particular order.

When an error occurs on a numbered line, error messages report the line number (eg, "Syntax error in line 1160").

{% include footer.html prev="DEF:../def/" next="IF:../if/" %}
