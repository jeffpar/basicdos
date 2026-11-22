---
layout: page
title: BASIC-DOS on an IBM PC AT with a VT100 Terminal
permalink: /demos/bd/vt100/at/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Terminal
    config: /machines/dec/vt100/vt100.json
    avo: true
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com1
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-ega-640kb.json
    debugger: available
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASIC-DOS HD VT100"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, an Enhanced Color Display, a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk.  It boots the BASIC-DOS HD VT100 diskette and runs two independent consoles: an 80x25 console on the Enhanced Color Display, and a console on a DEC VT100 terminal connected to COM1.  Unlike the PC and PC XT, the PC AT has a battery-powered real-time clock, so BASIC-DOS starts with the current date and time (type `DATE` or `TIME` to see them).

{% include vt100-demo.html id="ibm5170" %}

Press any key on the Enhanced Color Display at the boot message (or wait 2 seconds) to start the diskette.  Then click the VT100 screen and type a command, such as `DIR` or `PRINT "Hello from the VT100"`; click the Enhanced Color Display to use the local console.  Changes to the hard disk are lost when you leave the page.

The VT100 has DEC's Advanced Video Option (AVO), which gives it bold, blinking, and underlined characters, and 24 rows in 132-column mode (try `WIDTH 132`).  A [VT100 without the AVO](noavo/) is also available.

Additional hardware options:

- [10Mb Hard Disk (VT100 Console) on IBM PC XT](../xt/)
- [10Mb Hard Disk (VT100 Console) on COMPAQ DeskPro 386](../386/)

{% include_relative _overview.md hw="at" %}
