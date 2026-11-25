---
layout: page
title: BASIC-DOS on an IBM PC XT Hard Disk
permalink: /machines/demos/bd/hd/xt/
redirect_from:
  - /demos/bd/hd/xt/
  - /demos/hd/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-ega-640kb.json
    debugger: available
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, an Enhanced Color Display, two diskette drives, and a 20Mb hard disk.  It has no diskettes loaded; instead, it boots BASIC-DOS from its hard disk (drive C:) and runs one full-screen 80x25 console.  The PC XT has no clock to keep the date and time, so PCjs supplies them at startup.

{% include machine.html id="ibm5160" %}
{% include claude.html id="ibm5160" %}

Any changes you make to the hard disk are lost when you leave the page, unless you first click **Save HD** to download the hard disk as an IMG file.

Additional hardware options:

- [20Mb Hard Disk on IBM PC AT](../at/)
- [20Mb Hard Disk on COMPAQ DeskPro 386](../386/)

{% include_relative _overview.md hw="xt" %}
