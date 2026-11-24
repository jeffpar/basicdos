---
layout: page
title: BASIC-DOS on an IBM PC XT with 640K, a Monochrome Display, and Debugger
permalink: /machines/demos/bd/m64/xt/debugger/
redirect_from:
  - /demos/bd/m64/xt/debugger/
  - /demos/m64/xt/debugger/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-mda-640kb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS HD Real Mode"
      B: "PC DOS 1.00"
---

{% include machine.html id="ibm5160" %}
