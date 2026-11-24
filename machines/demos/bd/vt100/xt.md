---
layout: page
title: BASIC-DOS on an IBM PC XT with a VT100 Terminal
permalink: /machines/demos/bd/vt100/xt/
redirect_from:
  - /demos/bd/vt100/xt/
  - /demos/vt100/xt/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Terminal
    config: /machines/dec/vt100/vt100.json
    avo: true
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5160.com1
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-ega-640kb.json
    debugger: available
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASIC-DOS HD VT100"
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, an Enhanced Color Display, two diskette drives, and a 20Mb hard disk.  It boots the BASIC-DOS HD VT100 diskette and runs two independent consoles: an 80x25 console on the Enhanced Color Display, and a console on a DEC VT100 terminal connected to COM1.  The PC XT has no clock to keep the date and time, so PCjs supplies them at startup.

{% include vt100-demo.html id="ibm5160" %}

Press any key on the Enhanced Color Display at the boot message (or wait 2 seconds) to start the diskette.  Then click the VT100 screen and type a command, such as `DIR` or `PRINT "Hello from the VT100"`; click the Enhanced Color Display to use the local console.  Changes to the hard disk are lost when you leave the page.

The VT100 has DEC's Advanced Video Option (AVO), which gives it bold, blinking, and underlined characters, and 24 rows in 132-column mode (try `WIDTH 132`).  A [VT100 without the AVO](noavo/) is also available.

Additional hardware options:

- [20Mb Hard Disk (VT100 Console) on IBM PC AT](../at/)
- [20Mb Hard Disk (VT100 Console) on COMPAQ DeskPro 386](../386/)

{% include_relative _overview.md hw="xt" %}
