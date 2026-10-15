---
layout: page
title: BASIC-DOS on an IBM PC XT with a VT100 Terminal
permalink: /demos/vt100/xt/
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
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    debugger: available
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASICDOS-360K-VT100"
    autoType: DATE $date\rTIME $time\r
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, a Color Display, two diskette drives, and a 10Mb hard disk.  It boots BASIC-DOS from the BASICDOS-360K-VT100 diskette and runs two independent sessions: an 80x25 console on the Color Display, and a console on a DEC VT100 terminal connected to COM1.  The PC XT has no clock to keep the date and time, so this page types `DATE` and `TIME` commands with the current date and time at the first prompt.

{% include vt100-demo.html id="ibm5160" %}

Press any key on the Color Display at the boot prompt (or wait 5 seconds) to start the diskette.  Then click the VT100 screen and type a command, such as `DIR` or `PRINT "Hello from the VT100"`; click the Color Display to use the local session.  Changes to the hard disk are lost when you leave the page.

This demo is also available on an [IBM PC AT](../at/) and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="xt" %}
