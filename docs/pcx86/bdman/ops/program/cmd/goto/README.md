---
layout: sheet
title: BASIC-DOS Program Commands
permalink: /docs/pcx86/bdman/ops/program/cmd/goto/
---

{% include header.html topic="GOTO" %}

The **GOTO** statement transfers control to another line:

> GOTO *line*

where *line* is a line number within the current program.

Example:

	5 DATA 5, 7, 12  
	10 READ R  
	20 PRINT "R ="; R,  
	30 LET A = 3.14 * R^2  
	40 PRINT "AREA ="; A  
	50 GOTO 5  
	RUN  
	R = 5          AREA = 78.5  
	R = 7          AREA = 153.86  
	R = 12         AREA = 452.16  
	Out of data in 10

### Differences from Microsoft BASIC

BASIC-DOS does *not* require all lines within a program to begin with a line
number.  Only those lines that are the target of a GOTO statement must be numbered.

{% include footer.html prev="DEF:../def/" next="IF:../if/" %}
