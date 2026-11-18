---
layout: page
title: BASIC-DOS on an IBM PC AT with Dual Monitors
permalink: /demos/dual/at/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-dual-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Dual Monitor"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, two monitors (a Monochrome Display and a Color Display), a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk.  It boots the BASIC-DOS Dual Monitor diskette and runs one console on each monitor: PRIMES.BAS on the Monochrome Display and PIPES.BAT on the Color Display, which pipes the output of DIR through the TR filter (converting it to upper-case) over and over.  The boot sector first displays `System starting...` on the Monochrome Display; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Unlike the PC and PC XT, the PC AT has a battery-powered real-time clock, so BASIC-DOS starts with the current date and time (type `DATE` or `TIME` to see them).

{% include machine.html id="ibm5170" %}

Use **SHIFT-TAB** to move keyboard focus from one console to the next.  For even more consoles, try the [Dueling Monitors](../multi/at/) demo, which runs FOUR consoles, two on each monitor.

Additional demo configurations:

- [Dual Monitors on IBM PC](../pc/)
- [Dual Monitors on IBM PC XT](../xt/)
- [Dual Monitors on COMPAQ DeskPro 386](../386/)
- [Dueling Monitors on IBM PC AT](../multi/at/)

{% include_relative _overview.md hw="at" %}
