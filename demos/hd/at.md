---
layout: page
title: BASIC-DOS on an IBM PC AT Hard Disk
permalink: /demos/hd/at/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-ega-640kb.json
    debugger: available
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, an Enhanced Color Display, a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk.  It has no diskettes loaded; instead, it boots BASIC-DOS from its hard disk (drive C:) and runs one full-screen 80x25 session.  Unlike the PC and PC XT, the PC AT has a battery-powered real-time clock, so BASIC-DOS starts with the current date and time (type `DATE` or `TIME` to see them).

{% include machine.html id="ibm5170" %}

Any changes you make to the hard disk are lost when you leave the page, unless you first click **Save HD** to download the hard disk as an IMG file.

This demo is also available on an [IBM PC XT](../xt/) and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="at" %}
