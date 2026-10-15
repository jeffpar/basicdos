---
layout: page
title: BASIC-DOS on a COMPAQ DeskPro 386 with a VT100 Terminal and Debugger
permalink: /demos/vt100/386/debugger/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->deskpro386.com1
  - id: deskpro386
    type: pcx86
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-1mb.json
    debugger: true
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASICDOS-360K-VT100"
---

{% include vt100-demo.html id="deskpro386" %}
