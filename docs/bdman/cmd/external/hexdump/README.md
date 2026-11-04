---
layout: sheet
title: HEXDUMP
permalink: /docs/bdman/cmd/external/hexdump/
---

{% include header.html %}

> HEXDUMP *file* [/S *offset*] [/N *length*]

Displays the bytes of *file*, 16 per line, in the same format as [DEBUG](../debug/)'s DB command: an address, the bytes in hexadecimal (with a dash after the 8th), and the same bytes as characters (with a period for each byte outside 20h-7Eh).  The address is the file offset, written as a segment and an offset, where the segment is 1000h for each 64K (eg, offset 65536 is `1000:0000`).

- `/S` starts at a decimal *offset* (by default, 0)
- `/N` displays at most *length* bytes (by default, the rest of the file)

As with DB, lines begin at multiples of 16, so the first and last lines can be partial.

	HEXDUMP NAMES.TXT /N 24
	0000:0000 4F 6E 65 0D 0A 54 77 6F-0D 0A 54 77 6F 0D 0A 74  One..Two..Two..t
	0000:0010 68 72 65 65 0D 0A 46 6F-                         hree..Fo
	HEXDUMP NAMES.TXT /S 5 /N 3
	0000:0000                54 77 6F-                              Two

If *file* doesn't exist, HEXDUMP displays `Unable to find` and its name, or if its drive doesn't exist, `Invalid drive`.  A missing file name, a second file name, an unknown switch, or a negative *offset* displays HEXDUMP's usage, and a negative *length* is the same as no `/N`.

Source: [HEXDUMP.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/HEXDUMP.BAS)

{% include footer.html prev="HELP:../help/" next="LABEL:../label/" %}
