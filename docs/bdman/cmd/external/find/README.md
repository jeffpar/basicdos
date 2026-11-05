---
layout: sheet
title: FIND
permalink: /docs/bdman/cmd/external/find/
---

{% include header.html %}

> FIND [/C] [/I] [/N] [/R] [/V] *string* [*file*]...

A [filter](../#filters) that displays the lines of input (or of each *file*, or with wildcards (`?` and `*`), every matching file) that contain *string* (eg, `DIR | FIND BAS`).  FIND accepts up to 8 arguments that aren't switches, including *string* if it isn't quoted (more displays `Syntax error`); each can match any number of files.

*string* needs quotes only if it contains spaces or starts with the switch character (eg, `FIND "BASIC-DOS 2" *.TXT`); without quotes, it's the first argument that isn't a switch.  It can also be a string variable, whose value is used, even if it contains spaces (eg, `S$ = "BASIC-DOS 2"` and then `FIND S$ *.TXT`; see [Command Arguments](../../../lang/#command-arguments)).

- `/C` displays only the number of lines
- `/I` ignores case
- `/N` puts each line's number in front of it (eg, `[3]`)
- `/R` treats *string* as a [regular expression](../#regular-expressions) (eg, `DIR | FIND /R "^[A-M]"` displays the lines that start with A through M)
- `/V` displays the lines that do *not* contain *string*

When files are specified, the lines from each file follow a blank line and a line containing its name, and with `/C`, the name is followed by the file's count:

	FIND /IN T NAMES.TXT

	---------- NAMES.TXT
	[2]Two
	[3]Two
	[4]three
	FIND /C T NAMES.TXT

	---------- NAMES.TXT: 2

ERRORLEVEL is set to 0 if any lines were displayed (or counted), 1 if none, and 2 if a switch isn't valid or *string* is missing (`Syntax error`), the regular expression is invalid (`Invalid expression`), or a file couldn't be opened (eg, `Unable to find X.TXT`).

Source: [find.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/find.asm)

{% include footer.html prev="DISKCOPY:../diskcopy/" next="FORMAT:../format/" %}
