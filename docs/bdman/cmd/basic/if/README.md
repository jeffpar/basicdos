---
layout: sheet
title: BASIC-DOS BASIC Commands
permalink: /docs/bdman/cmd/basic/if/
---

{% include header.html topic="IF" %}

The **IF** statement evaluates *expression*, and if the result is TRUE (non-zero), it executes the *statement(s)* following the **THEN** keyword; otherwise, it executes the *statement(s)* following the **ELSE** keyword, if any:

> IF *expression* THEN *statement(s)* [ELSE *statement(s)*]

Multiple statements are separated by colons, and they all belong to the IF statement, up to the ELSE keyword (or the end of the line).

Relational operators (eg, `=`, `<>`, `<`, and `>=`) produce -1 for TRUE and 0 for FALSE, and logical operators (`AND`, `OR`, `XOR`, `EQV`, `IMP`, and `NOT`) operate on all the bits of their operands.  See [Operators](../../../lang/#operators).

Example:

	IF A$ = "Y" THEN PRINT "Yes" ELSE PRINT "No":GOTO 100

As in Microsoft BASIC, a line number by itself after THEN (eg, `IF X THEN 100`) is the same as `THEN GOTO 100`.

{% include footer.html prev="GOTO:../goto/" next="LET:../let/" %}
