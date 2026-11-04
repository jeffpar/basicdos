---
layout: sheet
title: COMP
permalink: /docs/bdman/cmd/external/comp/
---

{% include header.html %}

> COMP *file1* *file2*

Compares each file matching *file1* (which can contain wildcards, but doesn't match hidden files) with *file2*, or if *file2* is a drive or directory, with the file there that has the same name.

For each pair of files, COMP displays their names, followed by the result.  As in PC DOS, files of different sizes aren't compared, and each difference is reported with its offset (in hex) and the byte from each file (also in hex), until 10 differences have been found.

	COMP NAMES.TXT B:
	NAMES.TXT and B:NAMES.TXT
	Compare error at OFFSET 2
	File 1 = 65
	File 2 = 6F

	COMP *.BAS B:

The results are:

- `Files compare ok`
- `Compare error at OFFSET` *offset*, followed by `File 1 =` and `File 2 =` lines with the bytes
- `10 Mismatches - ending compare`, after the tenth difference
- `Files are different sizes`
- `Unable to find` *file*, if *file1* matches nothing or the file to compare with doesn't exist
- `Invalid drive`, if the drive of either file doesn't exist
- `Unable to open both files (the same file?)`: a file that isn't read-only can't be compared with itself, since it can't be opened twice for random access
- `Unable to compare (error` *n*`)`, for any other error

COMP compares at most 201 files at a time, and if either file name is missing, it displays its usage.

Source: [COMP.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/COMP.BAS)

{% include footer.html prev="COMMAND.COM:../command/" next="DEBUG:../debug/" %}
