---
layout: sheet
title: BASIC-DOS Programming
permalink: /docs/pcx86/bdman/ops/program/cmd/def/
---

{% include header.html topic="DEF" %}

The **DEF** command can define single-line functions, similar to the Microsoft
BASIC **DEF FN** command:

> DEF *name*[(*argument*[,*argument*]...)]=*expression*

BASIC-DOS does not require function names to begin with the letters **FN**,
and it allows functions to be defined immediately, from the BASIC-DOS
prompt.

The **DEF** command can also define multi-line functions, but such functions
can only be defined within a BASIC program:

> DEF *name*[(*argument*[,*argument*]...)]  
*statement(s)*  
RETURN *expression*

### Microsoft BASIC Differences

Microsoft BASIC requires all function names to begin with the letters **FN**,
it does not support multi-line functions, and it does not allow immediate
("Direct Mode") function definitions.

However, like BASIC-DOS, functions defined within a BASIC program remain
defined after the program terminates and can be used in immediate ("Direct
Mode") expressions.

{% include footer.html prev="Programming:../../" next="System Commands:../../../system/" %}
