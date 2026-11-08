---
layout: page
title: BASIC-DOS on an IBM PC AT with 640K, No Video, Two VT100 Terminals, and Debugger
permalink: /demos/term/at/debugger/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 (COM1)
    title: VT100 Terminal (COM1)
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com1
  - id: vt100b
    type: vt100
    name: DEC VT100 (COM2)
    title: VT100 Terminal (COM2)
    config: /machines/dec/vt100/vt100b.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com2
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-novideo-640kb.json
    debugger: true
    connection: com1->vt100.serialPort,com2->vt100b.serialPort
    autoMount:
      A: "BASIC-DOS HD Dual Terminal Demo"
---

{% include vt100-demo.html id="ibm5170" headless=true terminal2="vt100b" %}
