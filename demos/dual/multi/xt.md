---
layout: page
title: BASIC-DOS on an IBM PC XT with Dueling Monitors
permalink: /demos/dual/multi/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-dual-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Multi-Console"
    autoType: $date\r$time\r
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, two monitors (a Monochrome Display and a Color Display), two diskette drives, and a 10Mb hard disk.  It boots the BASIC-DOS Multi-Console diskette and runs FOUR consoles, two on each monitor.  The boot sector first displays `System starting...` on the Monochrome Display; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC XT has no clock to keep the date and time, so BASIC-DOS prompts for them at startup, and this page types the current date and time.

{% include machine.html id="ibm5160" %}

Use **SHIFT-TAB** to move keyboard focus from one console to the next.

Additional demo configurations: [IBM PC](../pc/), [IBM PC AT](../at/), and [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="xt" %}
