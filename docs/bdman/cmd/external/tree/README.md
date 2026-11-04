---
layout: sheet
title: TREE
permalink: /docs/bdman/cmd/external/tree/
---

{% include header.html %}

> TREE [*drive*:][*path*] [/F] [/A]

Displays the directories below *path* (or the current directory), each one connected to its parent by line-drawing characters.

- `/A` uses ASCII characters instead (eg, for a printer)
- `/F` lists each directory's files, too, before its subdirectories

If there are no subdirectories, TREE displays `No subdirectories exist`.

	TREE C:\ /A
	Directory PATH listing for Volume BD-10MB
	C:\
	+---EXT
	+---DEMOS
	|   \---WOLF3D
	+---SAMPLES
	+---SRC
	|   +---BOOT
	|   |   \---OBJ
	|   +---CMD
	|   |   \---OBJ
	...

TREE follows directories up to 32 levels deep, and remembers up to 400 subdirectory names at a time; any others aren't listed.  A drive that doesn't exist displays `Invalid drive`, and an unknown switch, or a second path, displays TREE's usage.

Source: [TREE.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/TREE.BAS)

{% include footer.html prev="TR:../tr/" next="UNIQ:../uniq/" %}
