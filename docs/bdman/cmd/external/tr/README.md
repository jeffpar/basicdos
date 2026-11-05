---
layout: sheet
title: TR
permalink: /docs/bdman/cmd/external/tr/
---

{% include header.html %}

> TR [/C] [/D] [/S] *set1* [*set2*]

A [filter](../#filters) that copies input to output, replacing each character in *set1* with the matching character in *set2*; if *set2* is shorter, its last character repeats.  TR doesn't accept file names, so its input must come from a pipe or a redirected file (eg, `TR a-z A-Z < NAMES.TXT`).

- `/C` uses every character *not* in *set1* (in ascending order)
- `/D` deletes the characters in *set1*, instead of replacing them
- `/S` squeezes each run of a character in the last set given into a single character

A set can contain ranges (eg, `a-z`) and these escapes:

- `\t` for TAB
- `\n` for LF
- `\r` for CR
- `\` before any other character for that character (eg, `\-` or `\\`)

A set that contains spaces, or starts with the switch character and a letter, must be quoted.

	DIR | TR a-z A-Z
	TYPE README.TXT | TR /D \r
	DIR | TR /S " "

ERRORLEVEL is set to 0, or 2 if a switch isn't valid or a set is missing (or only *set1* is given, without `/D` or `/S`), which TR reports (`Syntax error`).

Source: [tr.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/tr.asm)

{% include footer.html prev="TEE:../tee/" next="TREE:../tree/" %}
