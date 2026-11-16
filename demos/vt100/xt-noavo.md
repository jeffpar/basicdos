---
layout: page
title: BASIC-DOS on an IBM PC XT with a VT100 Terminal (No AVO)
permalink: /demos/vt100/xt/noavo/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Terminal
    config: /machines/dec/vt100/vt100.json
    avo: false
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5160.com1
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-ega-640kb.json
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASIC-DOS HD VT100"
    autoType: DATE $date\rTIME $time\r
---

This is the [VT100 Terminal demo](../) on an IBM PC XT, with a DEC VT100 that doesn't have the Advanced Video Option (AVO).

{% include vt100-demo.html id="ibm5160" %}

Press any key on the Enhanced Color Display at the boot message (or wait 2 seconds) to start the diskette, and then click the VT100 screen to use its console.

Without the AVO, a VT100 has no bold or blinking characters, and only one other character attribute: reverse video or underline, whichever its SET-UP cursor selection (block or underline) displays.  So `COLOR 0,7` and `COLOR 1` both produce reverse video here, and `COLOR 15` and `COLOR 23` look like `COLOR 7`.

It also has less screen memory, so `WIDTH 132` displays only 14 rows of 132 columns instead of 24.  BASIC-DOS asks the terminal which options it has, so commands like `DIR`, `MORE`, `HELP`, and `VI` use 14 rows until `WIDTH 80` (or `WIDTH 40`) restores all 24.
