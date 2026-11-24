---
layout: page
title: BASIC-DOS on an IBM PC XT with Dual Monitors
permalink: /machines/demos/bd/dual/xt/
redirect_from:
  - /demos/bd/dual/xt/
  - /demos/dual/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-dual-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Dual Monitor"
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, two monitors (a Monochrome Display and a Color Display), two diskette drives, and a 20Mb hard disk.  It boots the BASIC-DOS Dual Monitor diskette and runs one console on each monitor: PRIMES.BAS on the Monochrome Display and DONKEY.BAS (from the PC DOS 1.00 diskette) on the Color Display.  The boot sector first displays `System starting...` on the Monochrome Display; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC XT has no clock to keep the date and time, so PCjs supplies them at startup.

{% include machine.html id="ibm5160" %}

Use **SHIFT-TAB** to move keyboard focus from one console to the next.  For even more consoles, try the [Dueling Monitors](../multi/xt/) demo, which runs FOUR consoles, two on each monitor.

Additional hardware options:

- [Dual Monitors on IBM PC](../pc/)
- [Dual Monitors on IBM PC AT](../at/)
- [Dual Monitors on COMPAQ DeskPro 386](../386/)

Additional IBM PC XT configurations:

- [Four Consoles on Two Monitors](../multi/xt/)

{% include_relative _overview.md hw="xt" %}
