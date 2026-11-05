---
layout: sheet
title: ATTRIB
permalink: /docs/bdman/cmd/external/attrib/
---

{% include header.html %}

> ATTRIB [+R\|-R] [+H\|-H] [+S\|-S] [+A\|-A] [*filespec*]

Displays the attributes of each file matching *filespec* (or every file in the current directory), including hidden and system files, after making any changes that are specified.  Each attribute that a file has is displayed in its own column, followed by the file's name.  Directories aren't listed.

| Attribute | Meaning |
|-----------|---------|
| `A` | Archive |
| `S` | System |
| `H` | Hidden: the file is left out of DIR listings, unless [DIR /A](../../disk/#dir) is used |
| `R` | Read-only: the file can't be opened for writing, replaced, or deleted |

Unlike PC DOS, DIR lists system files that aren't hidden.

Attributes given with `+` are set, and those given with `-` are cleared; if the same attribute is given with both, it's set.  One `+` or `-` can be followed by several attributes (eg, `ATTRIB +RS *.COM`), and they can be in upper or lower case.

	ATTRIB
	     SHR     BASDEV.COM
	     SHR     BASDOS.COM
	     S R     COMMAND.COM
	  A          CONFIG.SYS
	ATTRIB -R COMMAND.COM

If no file matches, ATTRIB displays `Unable to find` and the *filespec*, or if its drive doesn't exist, `Invalid drive`.  A `+` or `-` by itself, or followed by anything other than these attributes, displays `Syntax error`, as does a switch or a second *filespec*.

ATTRIB sets attributes with DOS function 4301h (see [DOS](../../basic/#dos)), so a file whose attributes can't be changed (eg, while its volume is open) is a "Permission denied" error.

Source: [ATTRIB.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/ATTRIB.BAS)

{% include footer.html prev="External Commands:../" next="CHKDSK:../chkdsk/" %}
