---
layout: page
title: BASIC-DOS on an IBM PC XT with Debugger on Serial Port
permalink: /machines/demos/bd/debug/xt/
redirect_from:
  - /demos/bd/debug/xt/
  - /demos/debug/xt/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    avo: true
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5160.com2
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-ega-640kb.json
    debugger: available
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Serial Debugger"
      B: "BASIC-DOS Tests"
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, an Enhanced Color Display, two diskette drives, and a 20Mb hard disk.  It boots the BASIC-DOS Serial Debugger diskette with a local console and a debugger on a DEC VT100 connected to COM2 at 9600 baud.  Wait for the debugger's startup message on the VT100, then click its screen and press **Ctrl-C** to stop the machine; type `?` for help, or `G` to resume.  The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC XT has no clock to keep the date and time, so PCjs supplies them at startup.

{% include vt100-demo.html id="ibm5160" %}

Additional hardware options:

- [VT100 Debugger on IBM PC](../pc/)
- [VT100 Debugger on IBM PC AT](../at/)
- [VT100 Debugger on COMPAQ DeskPro 386](../386/)

{% include_relative _overview.md hw="xt" %}
