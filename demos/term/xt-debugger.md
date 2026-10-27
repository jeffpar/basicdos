---
layout: page
title: BASIC-DOS on an IBM PC XT with 640K, No Video, a VT100 Terminal, and Debugger
permalink: /demos/term/xt/debugger/
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
    debugger: true
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASIC-DOS HD Terminal Only Demo"
---

{% include vt100-demo.html id="ibm5160" headless=true %}
