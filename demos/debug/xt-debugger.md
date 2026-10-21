---
layout: page
title: BASIC-DOS on an IBM PC XT with Serial and PCjs Debuggers
permalink: /demos/debug/xt/debugger/
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
    debugger: true
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Serial Debugger Demo"
      B: "BASIC-DOS Tests"
---

{% include vt100-demo.html id="ibm5160" %}
