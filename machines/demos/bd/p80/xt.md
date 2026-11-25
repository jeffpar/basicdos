---
layout: page
title: BASIC-DOS on an IBM PC XT with Multiple Video Pages
permalink: /machines/demos/bd/p80/xt/
redirect_from:
  - /demos/bd/p80/xt/
  - /demos/p80/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Multi-Page"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, a Color Display, two diskette drives, and a 20Mb hard disk.  It boots the BASIC-DOS Multi-Page diskette and runs Multiple Video Pages, each on its own page of video memory; use **SHIFT-TAB** to switch between them.  The boot sector first displays `Diskette loading...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC XT has no clock to keep the date and time, so PCjs supplies them at startup.

{% include machine.html id="ibm5160" %}

Additional hardware options:

- [Multiple Video Pages on IBM PC](../pc/)
- [Multiple Video Pages on IBM PC AT](../at/)
- [Multiple Video Pages on COMPAQ DeskPro 386](../386/)

Additional IBM PC XT configurations:

- [Parallel Printer on LPT1](../../parallel/)
- [Serial Console on COM1](../../serial/)

{% include_relative _overview.md hw="xt" %}
