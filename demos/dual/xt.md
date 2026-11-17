---
layout: page
title: BASIC-DOS on an IBM PC XT with Dual Monitors
permalink: /demos/dual/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-dual-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Dual Monitor"
    autoType: $date\r$time\r
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, two monitors (a Monochrome Display and a Color Display), two diskette drives, and a 10Mb hard disk.  It boots the BASIC-DOS Dual Monitor diskette and runs one console on each monitor: PRIMES.BAS on the Monochrome Display and PIPES.BAT on the Color Display, which pipes the output of DIR through the TR filter (converting it to upper-case) over and over.  The boot sector first displays `System starting...` on the Monochrome Display; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC XT has no clock to keep the date and time, so BASIC-DOS prompts for them at startup, and this page types the current date and time.

{% include machine.html id="ibm5160" %}

Use **SHIFT-TAB** to move keyboard focus from one console to the next.  For even more consoles, try the [Dueling Monitors](../multi/xt/) demo, which runs FOUR consoles, two on each monitor.

Additional demo configurations: [IBM PC](../pc/), [IBM PC AT](../at/), and [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="xt" %}
