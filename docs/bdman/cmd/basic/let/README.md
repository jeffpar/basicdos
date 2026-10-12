---
layout: sheet
title: BASIC-DOS BASIC Commands
permalink: /docs/bdman/cmd/basic/let/
---

{% include header.html topic="LET" %}

The **LET** statement assigns the value of *expression* to *variable*:

> [LET] *variable*=*expression*

Values cannot be assigned to predefined variables (eg, ERRORLEVEL and MAXINT).

As in IBM PC BASIC, the LET keyword is optional (eg, `A = 1`), in BAS and BAT files and at the prompt.  At the prompt, a name followed by `=` (or by a subscript and `=`, eg, `A(1) = 2`) is an assignment, rather than the name of a program to run.

If the *expression* and *variable* are different numeric types, the value is converted to the variable's type; floating-point values assigned to integer variables are rounded (eg, `LET A% = 2.5` sets A% to 3).

Example:

	LET A$ = "HELLO":LET N = LEN(A$) * 2
	PRINT A$; N
	HELLO 10

{% include footer.html prev="IF:../if/" next="RETURN:../return/" %}
