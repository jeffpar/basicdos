---
layout: page
title: BASIC-DOS on an IBM PC with 64K, No Video, a VT100 Terminal, and Debugger
permalink: /demos/term/pc/debugger/
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
    debugger: true
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Terminal Only Demo"
---

{% include vt100-demo.html id="ibm5150" headless=true %}
