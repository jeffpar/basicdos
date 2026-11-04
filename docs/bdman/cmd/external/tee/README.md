---
layout: sheet
title: TEE
permalink: /docs/bdman/cmd/external/tee/
---

{% include header.html %}

> TEE [/A] *file*

A [filter](../#filters) that copies input to its output and to *file* (eg, `DIR | TEE DIR.TXT | MORE`).  *file* is replaced, or with `/A`, appended to (and created if it doesn't exist).

ERRORLEVEL is set to 0, or 2 if *file* is missing (`Missing file name`), or couldn't be opened (eg, `Unable to open`) or written (`Unable to write`, which includes running out of disk space).

Source: [tee.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/tee.asm)

{% include footer.html prev="SYS:../sys/" next="TR:../tr/" %}
