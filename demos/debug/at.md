---
layout: page
title: BASIC-DOS on an IBM PC AT with Debugger on Serial Port
permalink: /demos/debug/at/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com2
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb.json
    debugger: available
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Serial Debugger Demo"
      B: "BASIC-DOS Tests"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, a Color Display, a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk.  It boots the BASIC-DOS Serial Debugger Demo diskette with a local console and a debugger on a DEC VT100 connected to COM2 at 9600 baud.  Wait for the debugger's startup message on the VT100, then click its screen and press **Ctrl-C** to stop the machine; type `?` for help, or `G` to resume.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Unlike the PC and PC XT, the PC AT has a battery-powered real-time clock, so BASIC-DOS starts with the current date and time (type `DATE` or `TIME` to see them).

{% include vt100-demo.html id="ibm5170" %}

This demo is also available on an [IBM PC](../pc/), an [IBM PC XT](../xt/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="at" %}
