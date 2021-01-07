---
layout: sheet
title: BASIC-DOS Program Commands
permalink: /docs/pcx86/bdman/ops/program/cmd/def/
---

{% include header.html topic="DEF" %}

The **DEF** statement defines single-line functions:

> DEF *name*[(*argument*[,*argument*]...)]=*expression*

The **DEF** statement can also define multi-line functions, but only from
within a BASIC program:

> DEF *name*[(*argument*[,*argument*]...)]  
> *statement(s)*  
> RETURN *expression*

Example:

	10 LET PI = 3.141593  
	20 DEF AREA(R) = PI * R^2  
	30 INPUT "Radius? ", RADIUS  
	40 PRINT "Area is "; AREA(RADIUS)  
	RUN  
	Radius? 2  
	Area is 12.56637  

Like variables, functions defined within a BASIC program remain defined after
the program terminates and can be used in immediate ("Direct Mode") expressions:

	PRINT "Area is "; AREA(2)  
	Area is 12.56637  

### Differences from Microsoft BASIC

BASIC-DOS does *not* require function names to begin with the letters **FN**,
it allows single-line functions to be defined immediately (in "Direct Mode"),
and it allows multi-line functions.

{% include footer.html prev="Programming:../../" next="GOTO:../goto/" %}
