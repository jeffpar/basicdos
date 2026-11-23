---
layout: sheet
title: WC
permalink: /docs/bdman/cmd/external/wc/
---

{% include header.html %}

> WC [/B] [/L] [/W] [/C] [*file*]...

A [filter](../#filters) that displays the number of lines, words, and bytes of input (or of each *file*, or with wildcards (`?` and `*`), every matching file, followed by their totals if there's more than one), along with each file's name (eg, `DIR | WC /L` or `WC *.BAS`).  WC accepts up to 8 file names (more is a [usage error](../../#usage-errors)); each can match any number of files.

- `/L` displays only the line counts
- `/W` displays only the word counts
- `/C` displays only the byte counts

Without any of them, all three are displayed.  Lines are counted by their line feeds, and words are separated by spaces and control characters (eg, tabs and line breaks).

`/B` counts only BASIC code, along with any of the other switches (eg, `WC /B /L *.BAS` counts lines of code).  A line is counted only if it contains something besides whitespace, a line number, and a comment (`REM` or `'`), and only its words and bytes up to the comment are counted, without trailing spaces or colons (but with its CR and LF).  A comment is a `'` anywhere outside quotes, or `REM` at the start of a statement (after the line number or a colon).  `/B` works with any text file (eg, BAT files, which also use `REM`), although in other kinds of files, it could mistake other uses of `'` for comments.

	WC NAMES.TXT CONFIG.SYS
	       5       6      33 NAMES.TXT
	       6       7     103 CONFIG.SYS
	      11      13     136 total
	WC /L NAMES.TXT
	       5 NAMES.TXT

A switch that isn't valid, or too many file names, is a [usage error](../../#usage-errors).  Otherwise, ERRORLEVEL is set to 0, or 2 if a file couldn't be opened (eg, `Unable to find X.TXT`).

Source: [wc.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/wc.asm)

{% include footer.html prev="VOL:../vol/" next="System Commands:../../system/" %}
