---
layout: sheet
title: BASIC Commands
permalink: /docs/pcx86/bdman/cmd/basic/
---

{% include header.html %}

BASIC-DOS supports a subset of the BASIC programming language, enabling
the creation of simple BASIC programs.

BASIC programs can use any BASIC-DOS [Commands](../) in combination with any
BASIC commands using the following BASIC language elements:

- [Statements](#statements)
- [Functions](#functions)
- [Variables](#variables)

### Statements

- [DEF](def/) *function*
- [GOTO](goto/) *line*
- [IF](if/) *expression* THEN *statement(s)*
- [LET](let/) *variable* = *expression*
- [RETURN](return/) [*expression*]

### Functions

Predefined functions include:

- RND%

### Variables

Predefined variables include:

- ERRORLEVEL
- MAXINT

{% include footer.html prev="BASIC-DOS Commands:../" next="Device Commands:../device/" %}
