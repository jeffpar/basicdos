---
layout: page
title: BASIC-DOS on a COMPAQ DeskPro 386 with Extended Memory and Debugger
permalink: /demos/mmu/386/debugger/
machines:
  - id: deskpro386
    type: pcx86
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-2mb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS Extended Memory"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="deskpro386" %}
