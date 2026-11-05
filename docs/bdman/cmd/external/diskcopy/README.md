---
layout: sheet
title: DISKCOPY
permalink: /docs/bdman/cmd/external/diskcopy/
---

{% include header.html %}

> DISKCOPY [*drive1*: [*drive2*:]]

Copies the diskette in *drive1* (or the current drive) to the diskette in *drive2* (or *drive1*), track by track, formatting each of the target's tracks (with the source's parameters) as it goes, so the target doesn't have to be formatted first.

DISKCOPY first asks for the diskettes and waits for a key, and after each copy, it asks whether to copy another:

	DISKCOPY A: B:
	Insert SOURCE diskette in drive A:
	Insert TARGET diskette in drive B:
	Press any key when ready...
	Copying 40 tracks, 9 sectors per track, 2 side(s)
	Copy complete
	Copy another diskette (Y/N)?

If both drives are the same, DISKCOPY reads as many tracks as memory allows, then asks for the target diskette, writes them, and asks for the source diskette again, until the whole diskette has been copied.

DISKCOPY copies diskettes of any size its drives support, including PC DOS 1.x diskettes (whose sizes come from the media ID in their FATs), and it refuses hard disks.

### Messages

DISKCOPY stops if it displays any of these messages:

- `DISKCOPY works only with diskettes in a known format`: the drive is a hard disk, or the diskette's format isn't recognized
- `Not enough memory`: there isn't room for even one track, for a copy with one drive
- `Write protect error`
- `Drive not ready`
- `Unrecoverable read or format error`
- `Invalid drive`
- `Copy failed (error` *n*`)`, for any other error

An argument that isn't a drive displays `Syntax error`.

Source: [DISKCOPY.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/DISKCOPY.BAS)

{% include footer.html prev="DEBUG:../debug/" next="FIND:../find/" %}
