---
layout: page
title: Wolfenstein 3D on an IBM PC AT Running BASIC-DOS with Debugger
permalink: /demos/bd/wolf3d/at/debugger/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-vga-640kb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS Wolf3D"
---

{% include machine.html id="ibm5170" %}
