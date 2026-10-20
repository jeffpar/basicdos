---
layout: page
title: BASIC-DOS on a COMPAQ DeskPro 386 with Multiple Video Pages and Debugger
permalink: /demos/p80/386/debugger/
machines:
  - id: deskpro386
    type: pcx86
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-1mb.json
    debugger: true
    autoMount:
      A: "BASICDOS-360K-P80"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="deskpro386" %}
