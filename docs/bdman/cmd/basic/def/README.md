---
layout: sheet
title: BASIC-DOS BASIC Commands
permalink: /docs/bdman/cmd/basic/def/
---

{% include header.html topic="DEF" %}

The **DEF** statement defines single-line functions ("function expressions"):

> DEF *name*[(*parameter*[,*parameter*]...)]=*expression*

The **DEF** statement can also define multi-line functions ("function blocks"), but only from within a BASIC program:

> DEF *name*[(*parameter*[,*parameter*]...)]  
> *statement(s)*  
> RETURN *expression*

Function and parameter names follow the same rules as variable names, so a name ending with `$` defines a string function or parameter, and a name ending with `%` defines an integer function or parameter.

Example:

	LET PI = 3.141593
	DEF AREA(R) = PI * R^2
	PRINT "Area is "; AREA(2)
	Area is  12.566372

Example (in a BAS file):

	DEF HYP(A,B)
	LET C = A*A + B*B
	RETURN SQR(C)
	PRINT HYP(3,4); C
	 5  25

A function block ends with its first RETURN statement, so RETURN can't be used conditionally (eg, `IF N < 0 THEN RETURN 0`).  Parameters can't be assigned new values, and any other variables used in a function block are shared with the rest of the program (like C above).

Like variables, functions defined within a BASIC program remain defined after the program ends and can be used in commands typed at the prompt:

	PRINT "Area is "; AREA(3)
	Area is  28.274337

The [DEF SEG](../#def-seg) statement is unrelated; it sets the segment used by PEEK and POKE.

### Differences from Microsoft BASIC

BASIC-DOS does *not* require function names to begin with the letters **FN**, it allows single-line functions to be defined immediately (in "Direct Mode"), and it allows multi-line functions.

Note that `DEF FN X=...` (with a space after FN) is not the same as `DEF FNX=...`: BASIC-DOS treats it as the start of a function block, which then swallows the rest of the program.

{% include footer.html prev="BASIC Commands:../" next="GOTO:../goto/" %}
