---
layout: sheet
title: VOL
permalink: /docs/bdman/cmd/external/vol/
---

{% include header.html %}

> VOL [*drive*:]

Displays the volume label of *drive* (or the current drive), as DIR does at the start of a listing.  To change a label, use [LABEL](../label/).

	VOL
	 Volume in drive A is BD-D40
	VOL B:
	 Volume in drive B has no label

A drive that doesn't exist displays `Invalid drive`, and an argument that isn't a drive displays `Syntax error`.

Source: [VOL.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/VOL.BAS)

{% include footer.html prev="VI:../vi/" next="WC:../wc/" %}
