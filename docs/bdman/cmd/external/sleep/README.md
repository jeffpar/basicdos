---
layout: sheet
title: SLEEP
permalink: /docs/bdman/cmd/external/sleep/
---

{% include header.html %}

> SLEEP *seconds*

Waits the specified number of *seconds*, a whole number in decimal (eg, `SLEEP 5`).  CTRL-C stops it early.

If *seconds* is missing, or negative, SLEEP displays `Usage: SLEEP seconds`, and ERRORLEVEL is set to 1.

Source: [sleep.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/sleep.asm)

{% include footer.html prev="SED:../sed/" next="SORT:../sort/" %}
