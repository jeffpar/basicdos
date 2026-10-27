---
layout: page
title: BASIC-DOS on an IBM PC with 64K, No Video, and a VT100 Terminal
permalink: /demos/term/pc/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5150.com1
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-novideo-64kb.json
    debugger: available
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Terminal Only Demo"
---

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088, 64K of memory, two diskette drives, a serial port, and no video adapter: its only display is a DEC VT100 terminal connected to COM1 at 9600 baud.  It boots the BASIC-DOS Terminal Only Demo diskette and runs a single session on the VT100.

{% include vt100-demo.html id="ibm5150" headless=true %}

Wait a few seconds for the BASIC-DOS banner to appear on the VT100, then type a command, such as `DIR` or `PRINT "Hello from the VT100"` (the VT100 has keyboard focus when the page loads; click its screen to give it focus again).  Use the **MEM** command to display current memory usage.  The PC has no screen of its own, so its diskette drive and Reset controls are below the VT100.

With only 64K of memory, there isn't room for all of COMMAND.COM, so BASIC-DOS loads only its *core*: the graphics statements (CIRCLE, DRAW, GET, LINE, PAINT, PRESET, PSET, and PUT), the sound statements (PLAY and SOUND), the file statements (eg, OPEN and CLOSE), and LOAD's support for tokenized BAS files are left out, and using one of them reports `Not enough memory`.  There is no floating-point either: numbers are 32-bit integers, and numeric functions like SQR are unavailable.

This demo is also available on an [IBM PC XT](../xt/) with 640K and a 10Mb hard disk.

{% include_relative _overview.md hw="pc" %}
