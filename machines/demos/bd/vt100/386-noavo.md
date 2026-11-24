---
layout: page
title: BASIC-DOS on a COMPAQ DeskPro 386 with a VT100 Terminal (No AVO)
permalink: /machines/demos/bd/vt100/386/noavo/
redirect_from:
  - /demos/bd/vt100/386/noavo/
  - /demos/vt100/386/noavo/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Terminal
    config: /machines/dec/vt100/vt100.json
    avo: false
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->deskpro386.com1
  - id: deskpro386
    type: pcx86
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-1mb.json
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASIC-DOS HD VT100"
---

This is the [VT100 Terminal demo](../) on a COMPAQ DeskPro 386, with a DEC VT100 that doesn't have the Advanced Video Option (AVO).

{% include vt100-demo.html id="deskpro386" %}

Press any key on the Color Display at the boot message (or wait 2 seconds) to start the diskette, and then click the VT100 screen to use its console.

Without the AVO, a VT100 has no bold or blinking characters, and only one other character attribute: reverse video or underline, whichever its SET-UP cursor selection (block or underline) displays.  So `COLOR 0,7` and `COLOR 1` both produce reverse video here, and `COLOR 15` and `COLOR 23` look like `COLOR 7`.

It also has less screen memory, so `WIDTH 132` displays only 14 rows of 132 columns instead of 24.  BASIC-DOS asks the terminal which options it has, so commands like `DIR`, `MORE`, `HELP`, and `VI` use 14 rows until `WIDTH 80` (or `WIDTH 40`) restores all 24.
