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
      A: "BASIC-DOS Dual Monitor Demo"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, two monitors (a Monochrome Display and a Color Display), a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk.  It boots the BASIC-DOS Dual Monitor Demo diskette and runs one session on each monitor: PRIMES.BAT on the Monochrome Display, while the Color Display switches to the hard disk's **SRC** directory and runs **MK** to build BASIC-DOS itself, with MAKE, MASM, and LINK.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...` on the Monochrome Display; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Unlike the PC and PC XT, the PC AT has a battery-powered real-time clock, so BASIC-DOS starts with the current date and time (type `DATE` or `TIME` to see them).

{% include machine.html id="ibm5170" %}

Use **SHIFT-TAB** to move keyboard focus from one session to the next.  For even more sessions, try the [Dueling Monitors](../multi/at/) demo, which runs FOUR sessions, two on each monitor.

This demo is also available on an [IBM PC](../pc/), an [IBM PC XT](../xt/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="at" %}
