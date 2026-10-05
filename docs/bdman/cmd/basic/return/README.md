---
layout: sheet
title: BASIC-DOS BASIC Commands
permalink: /docs/bdman/cmd/basic/return/
---

{% include header.html topic="RETURN" %}

The **RETURN** statement returns from a [GOSUB](../#gosub) subroutine, or returns the value of *expression* from a multi-line function (see [DEF](../def/)):

> RETURN [*expression*]

A multi-line function must end with a RETURN statement, and it may contain additional RETURN statements (eg, within IF statements).

{% include footer.html prev="LET:../let/" next="BASIC Functions:../func/" %}
