---
layout: sheet
title: SORT
permalink: /docs/bdman/cmd/external/sort/
---

{% include header.html %}

> SORT [/R] [/+*n*] [*file*]

A [filter](../#filters) that displays the lines of input (or *file*) in sorted order, ignoring case (eg, `DIR | SORT`).

- `/R` sorts in reverse order
- `/+n` sorts on the characters starting at column *n* (eg, `DIR | SORT /+10` sorts a directory listing by extension); the first column is 1, and a line that's too short sorts as if it were empty

Lines that differ only in case, or that match from column *n* on, can be displayed in any order.

	SORT NAMES.TXT
	Four five
	One
	three
	Two
	Two

Up to 64K of text can be sorted, including 2 bytes for each line.  If there's more than that, or more than memory allows, SORT displays `Not enough memory`, and ERRORLEVEL is set to 1.  ERRORLEVEL is set to 2 if *file* couldn't be opened (eg, `Unable to find X.TXT`), and otherwise to 0.

Source: [sort.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/sort.asm)

{% include footer.html prev="SLEEP:../sleep/" next="SYS:../sys/" %}
