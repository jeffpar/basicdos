---
layout: sheet
title: WC
permalink: /docs/bdman/cmd/external/wc/
---

{% include header.html %}

> WC [/L] [/W] [/C] [*file*]...

A [filter](../#filters) that displays the number of lines, words, and bytes of input (or of each *file*, or with wildcards (`?` and `*`), every matching file, followed by their totals if there's more than one), along with each file's name (eg, `DIR | WC /L` or `WC *.BAS`).  WC accepts up to 8 file names (more displays `Syntax error`); each can match any number of files.

- `/L` displays only the line counts
- `/W` displays only the word counts
- `/C` displays only the byte counts

Without any of them, all three are displayed.  Lines are counted by their line feeds, and words are separated by spaces and control characters (eg, tabs and line breaks).

	WC NAMES.TXT CONFIG.SYS
	       5       6      33 NAMES.TXT
	       6       7     103 CONFIG.SYS
	      11      13     136 total
	WC /L NAMES.TXT
	       5 NAMES.TXT

ERRORLEVEL is set to 0, or 2 if a switch isn't valid or there are too many file names (`Syntax error`), or a file couldn't be opened (eg, `Unable to find X.TXT`).

Source: [wc.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/wc.asm)

{% include footer.html prev="VOL:../vol/" next="System Commands:../../system/" %}
