---
layout: page
title: BASIC-DOS on an IBM PC AT with 640K, No Video, and Two VT100 Terminals
permalink: /demos/term/at/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 (COM1)
    title: VT100 Terminal (COM1)
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com1
  - id: vt100b
    type: vt100
    name: DEC VT100 (COM2)
    title: VT100 Terminal (COM2)
    config: /machines/dec/vt100/vt100b.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com2
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-novideo-640kb.json
    debugger: available
    connection: com1->vt100.serialPort,com2->vt100b.serialPort
    autoMount:
      A: "BASIC-DOS HD Dual Terminal Demo"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, a 1.2Mb and a 1.44Mb diskette drive, a 10Mb hard disk, two serial ports, and no video adapter: its only displays are two DEC VT100 terminals, one connected to COM1 and the other to COM2, at 9600 baud.  It boots the BASIC-DOS HD Dual Terminal Demo diskette and runs a console on each VT100, both starting on drive C:, the hard disk, with the BASIC-DOS source code, tests, and tools.

{% include vt100-demo.html id="ibm5170" headless=true terminal2="vt100b" %}

Wait a few seconds for the BASIC-DOS banner to appear on both VT100s, then click either one and type a command, such as `DIR` or `PRINT "Hello from the VT100"`.  Each VT100 has its own keyboard, so there's no need for **SHIFT-TAB**: click a terminal's screen to type at it.  The PC has no screen of its own, so its diskette drive, hard disk, and Reset controls are below the VT100s.

Any changes you make to the hard disk are lost when you leave the page, unless you first click **Save HD** to download the hard disk as an IMG file.

This demo is also available, with one VT100, on an [IBM PC](../pc/) with 64K and no hard disk, and an [IBM PC XT](../xt/) with 640K and a 10Mb hard disk.

{% include_relative _overview.md hw="at" %}
