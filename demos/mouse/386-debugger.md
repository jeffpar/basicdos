---
layout: page
title: BASIC-DOS on a COMPAQ DeskPro 386 with a Mouse and Debugger
permalink: /demos/mouse/386/debugger/
machines:
  - id: deskpro386
    type: pcx86
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-1mb-mouse.json
    debugger: true
    autoMount:
      A: "BASIC-DOS 80-Column Demo"
    autoType: PAINT\r
---

{% include machine.html id="deskpro386" %}
