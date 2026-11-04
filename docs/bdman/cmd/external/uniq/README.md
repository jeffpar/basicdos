---
layout: sheet
title: UNIQ
permalink: /docs/bdman/cmd/external/uniq/
---

{% include header.html %}

> UNIQ [/C] [/D] [/I] [/U] [*file*]

A [filter](../#filters) that displays input (or *file*), with each run of identical lines displayed only once, like the UNIX `uniq` command.  Only adjacent lines are compared, so input is usually sorted first (eg, `SORT NAMES.TXT | UNIQ`, or since SORT ignores case, `SORT NAMES.TXT | UNIQ /I`).

- `/C` puts the number of times each line occurred in front of it
- `/D` displays only the lines that were repeated
- `/I` ignores case (displaying the first line of each run)
- `/U` displays only the lines that weren't repeated

For example:

	UNIQ /C NAMES.TXT
	      1 One
	      2 Two
	      1 three
	      1 Four five
	UNIQ /D NAMES.TXT
	Two

ERRORLEVEL is set to 0, or 2 if *file* couldn't be opened (eg, `Unable to find X.TXT`).

Source: [uniq.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/uniq.asm)

{% include footer.html prev="TREE:../tree/" next="VI:../vi/" %}
