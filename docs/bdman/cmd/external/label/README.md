---
layout: sheet
title: LABEL
permalink: /docs/bdman/cmd/external/label/
---

{% include header.html %}

> LABEL [*drive*:][*label*]

Gives *drive* (or the current drive) a volume label of up to 11 characters, which can include spaces, but not `* ? / \ | . , ; : + = [ ] < >` or `"`.  Lower-case letters are converted to upper case.

	LABEL A:SAVED FILES

Without a *label*, LABEL displays the current label and asks for a new one; pressing ENTER deletes the current label (after asking):

	LABEL
	 Volume in drive A is BD-D40
	Volume label (11 characters, ENTER for none)?
	Delete current volume label (Y/N)?

To display a label without changing it, use [VOL](../vol/).

The label is a root directory entry with the volume attribute, which LABEL writes directly (see [OPEN](../../basic/#open)), so the drive can't have any files open.

### Messages

- `Syntax error` (a switch, which LABEL doesn't have)
- `Too many characters in volume label`
- `Invalid characters in volume label`
- `Root directory full`
- `Write protect error`
- `Drive not ready`
- `Invalid drive`
- `Unable to label drive` *drive* `(error` *n*`)`, for any other error

Source: [LABEL.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/LABEL.BAS)

{% include footer.html prev="HEXDUMP:../hexdump/" next="LS:../ls/" %}
