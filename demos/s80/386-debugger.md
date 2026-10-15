---
layout: page
title: BASIC-DOS on a COMPAQ DeskPro 386 with a Single Session and Debugger
permalink: /demos/s80/386/debugger/
machines:
  - id: deskpro386
    type: pcx86
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-1mb.json
    debugger: true
    autoMount:
      A: "BASICDOS-360K-S80"
      B: "PC DOS 1.00"
---

{% include machine.html id="deskpro386" %}
