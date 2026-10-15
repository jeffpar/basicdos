---
layout: page
title: BASIC-DOS on an IBM PC with Debugger on Serial Port
permalink: /demos/debug/pc/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5150.com2
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASICDOS-DEBUG"
---

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088, 128K of memory, a Color Display, and two diskette drives.  It boots the BASICDOS-DEBUG diskette with a local console and a debugger on a DEC VT100 connected to COM2 at 9600 baud.  Wait for the debugger's startup message on the VT100, then click its screen and press **Ctrl-C** to stop the machine; type `?` for help, or `G` to resume.

{% include vt100-demo.html id="ibm5150" %}

This demo is also available on an [IBM PC XT](../xt/) and an [IBM PC AT](../at/).

{% include_relative _overview.md hw="pc" %}
