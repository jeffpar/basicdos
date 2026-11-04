---
layout: sheet
title: MORE
permalink: /docs/bdman/cmd/external/more/
---

{% include header.html %}

> MORE [*file*]

A [filter](../#filters) that displays input (or *file*) one screen at a time (eg, `TYPE README.TXT | MORE`).  After each screen, it displays `-- More --` and waits for a key (read from STDERR, since STDIN is the pipe or file); press any key to continue, or CTRL-C to stop.

MORE gets the screen's size from the console, and counts the rows each line will occupy, allowing for lines that wrap and tabs that stop every 8 columns.  If its output doesn't support that (eg, it's a file), it assumes 80 columns and 25 rows.

ERRORLEVEL is set to 0, or 2 if *file* couldn't be opened (eg, `Unable to find X.TXT`).

Source: [more.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/more.asm)

{% include footer.html prev="MODE:../mode/" next="SED:../sed/" %}
