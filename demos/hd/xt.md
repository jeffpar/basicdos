---
layout: page
title: BASIC-DOS on an IBM PC XT Hard Disk
permalink: /demos/hd/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    debugger: available
    autoType: DATE $date\rTIME $time\r
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, a Color Display, two diskette drives, and a 10Mb hard disk.  It has no diskettes loaded; instead, it boots BASIC-DOS from its hard disk (drive C:) and runs one full-screen 80x25 session.  The PC XT has no clock to keep the date and time, so this page types `DATE` and `TIME` commands with the current date and time at the first prompt.

{% include machine.html id="ibm5160" %}

Any changes you make to the hard disk are lost when you leave the page, unless you first click **Save HD** to download the hard disk as an IMG file.

This demo is also available on an [IBM PC AT](../at/).

{% include_relative _overview.md hw="xt" %}
