---
layout: page
title: BASIC-DOS on an IBM PC XT with 640K, No Video, and a VT100 Terminal
permalink: /demos/term/xt/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5160.com1
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-novideo-640kb.json
    debugger: available
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASIC-DOS HD Terminal Only Demo"
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, two diskette drives, a 10Mb hard disk, a serial port, and no video adapter: its only display is a DEC VT100 terminal connected to COM1 at 9600 baud.  It boots the BASIC-DOS HD Terminal Only Demo diskette and runs a single session on the VT100, which starts on drive C:, the hard disk, with the BASIC-DOS source code, tests, and tools.

{% include vt100-demo.html id="ibm5160" headless=true %}

Wait a few seconds for the BASIC-DOS banner to appear on the VT100 (with no display, the boot sector's `Press a key to start...` prompt isn't visible, so it waits 2 seconds before booting the diskette), then type a command, such as `DIR` or `PRINT "Hello from the VT100"` (the VT100 has keyboard focus when the page loads; click its screen to give it focus again).  The PC XT has no clock to keep the date and time, so use the `DATE` and `TIME` commands to set them.  The PC has no screen of its own, so its diskette drive, hard disk, and Reset controls are below the VT100.

Any changes you make to the hard disk are lost when you leave the page, unless you first click **Save HD** to download the hard disk as an IMG file.

This demo is also available on an [IBM PC](../pc/) with 64K and no hard disk.

{% include_relative _overview.md hw="xt" %}
