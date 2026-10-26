---
layout: page
title: BASIC-DOS on an IBM PC XT with a VT100 Terminal and Debugger
permalink: /demos/vt100/xt/debugger/
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
    config: /machines/pcx86/ibm/ibm-5160-ega-640kb.json
    debugger: true
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASIC-DOS HD VT100 Demo"
    autoType: DATE $date\rTIME $time\r
---

{% include vt100-demo.html id="ibm5160" %}
