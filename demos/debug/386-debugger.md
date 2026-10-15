---
layout: page
title: BASIC-DOS on a COMPAQ DeskPro 386 with Serial and PCjs Debuggers
permalink: /demos/debug/386/debugger/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->deskpro386.com2
  - id: deskpro386
    type: pcx86
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-1mb.json
    debugger: true
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASICDOS-360K-DEBUG"
      B: "BASICDOS-360K-TESTS"
---

{% include vt100-demo.html id="deskpro386" %}
