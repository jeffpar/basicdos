---
layout: page
title: BASIC-DOS Protected Mode (VT100) on a COMPAQ DeskPro 386 with Debugger
permalink: /demos/mmu/vt100/386/debugger/
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
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-2mb.json
    debugger: true
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Protected Mode (80386) with VT100"
      B: "BASIC-DOS Tests"
---

{% include vt100-demo.html id="deskpro386" %}
