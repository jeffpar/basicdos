---
layout: page
title: BASIC-DOS with Extended Memory (VT100 Debugger), an Empty Hard Disk, and PCjs Debugger
permalink: /machines/demos/bd/mmu/vt100/47mb/debugger/
redirect_from:
  - /demos/bd/mmu/vt100/47mb/debugger/
  - /demos/mmu/vt100/47mb/debugger/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    avo: true
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com2
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-ega-2mb.json
    debugger: true
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Serial Debugger"
      B: "BASIC-DOS Tests"
---

{% include vt100-demo.html id="ibm5170" %}
