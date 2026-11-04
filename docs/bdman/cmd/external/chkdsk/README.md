---
layout: sheet
title: CHKDSK
permalink: /docs/bdman/cmd/external/chkdsk/
---

{% include header.html %}

> CHKDSK [*drive*:] [/V]

Checks the FAT and directories of *drive* (or the current drive): every file's and directory's cluster chain is followed, and any problems are reported.  Then CHKDSK reports the volume label (with its date and time) and the space on the drive: the total, the bad sectors, the hidden files, directories, and user files (each in whole clusters), the lost clusters, and the space available.  Lines that would report nothing (eg, bad sectors, on most disks) aren't displayed.

`/V` lists the name of every file and directory as it's checked.

	CHKDSK A:

	Volume BD-D40      created 10-23-2026 12:08a

	      362496 bytes total disk space
	       46080 bytes in 2 hidden files
	        3072 bytes in 3 directories
	      214016 bytes in 53 user files
	       99328 bytes available on disk

Unlike PC DOS, CHKDSK only reports problems (there's no `/F` to fix them), and it doesn't report memory (see [MEM](../../system/#mem)).

### Problems

CHKDSK can report these problems with a drive, and if it reports any of them, it follows them with `Errors found (CHKDSK reports them, but can't fix them)`:

- *file* `is cross-linked on cluster` *n*: the chain shares a cluster with another chain
- *file* `allocation error (size` *n* `but` *n* `clusters)`: the chain doesn't match the file's size
- *file* `has an invalid cluster` *n*: the chain contains a cluster that isn't on the drive
- *n* `lost clusters found in` *n* `chains`: these clusters are in use, but in no file's chain

### Limits and Other Messages

CHKDSK reads the volume directly (see [OPEN](../../basic/#open)), so it can't check directories beyond the first 14Mb of a volume, which it reports (*path* `is beyond the first 14Mb (not checked)`).  It also keeps track of only 300 subdirectories; any others aren't checked, so their clusters may be reported as lost.

CHKDSK can't check a drive if it finds one of these problems:

- `Drive not ready`
- `Invalid drive`
- `Drive` *drive* `doesn't have a FAT volume`
- `Unable to check drive` *drive* `(error` *n*`)`, for any other error

Any argument other than a drive and `/V`, or more than one drive, displays CHKDSK's usage.

Source: [CHKDSK.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/CHKDSK.BAS)

{% include footer.html prev="ATTRIB:../attrib/" next="COMMAND.COM:../command/" %}
