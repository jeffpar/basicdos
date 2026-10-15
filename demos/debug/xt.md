---
layout: page
title: BASIC-DOS on an IBM PC XT with Debugger on Serial Port
permalink: /demos/debug/xt/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5160.com2
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASICDOS-DEBUG"
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, a Color Display, two diskette drives, and a 10Mb hard disk.  It boots the BASICDOS-DEBUG diskette with a local console and a debugger on a DEC VT100 connected to COM2 at 9600 baud.  Wait for the debugger's startup message on the VT100, then click its screen and press **Ctrl-C** to stop the machine; type `?` for help, or `G` to resume.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 5 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.

{% include vt100-demo.html id="ibm5160" %}

This demo is also available on an [IBM PC](../pc/) and an [IBM PC AT](../at/).

{% include_relative _overview.md hw="xt" %}
