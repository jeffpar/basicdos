---
layout: page
title: BASIC-DOS with a Serial Port and Debugger
permalink: /demos/serial/debugger/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-serial-640kb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS HD Serial Port Demo"
    autoType: DATE $date\rTIME $time\r
---

{% include machine.html id="ibm5160" %}
