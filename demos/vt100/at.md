---
layout: page
title: BASIC-DOS on an IBM PC AT with a VT100 Terminal
permalink: /demos/vt100/at/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com1
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb.json
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASICDOS-VT100"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, a Color Display, two diskette drives, and a 10Mb hard disk.  It boots BASIC-DOS from the BASICDOS-VT100 diskette and runs two independent sessions: an 80x25 console on the Color Display, and a console on a DEC VT100 terminal connected to COM1.  Unlike the PC and PC XT, the PC AT has a battery-powered real-time clock, so BASIC-DOS starts with the current date and time (type `DATE` or `TIME` to see them).

{% include vt100-demo.html id="ibm5170" %}

Press any key on the Color Display at the boot prompt (or wait 5 seconds) to start the diskette.  Then click the VT100 screen and type a command, such as `DIR` or `PRINT "Hello from the VT100"`; click the Color Display to use the local session.  Changes to the hard disk are lost when you leave the page.

This demo is also available on an [IBM PC XT](../xt/).

{% include_relative _overview.md hw="at" %}
