---
layout: page
title: Wolfenstein 3D on an IBM PC AT Running BASIC-DOS
permalink: /demos/wolf3d/at/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-vga-640kb.json
    debugger: available
    autoType: WOLF3D\r
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, a VGA Color Display, a Sound Blaster, two 1.2Mb diskette drives, and a 10Mb hard disk.  It boots BASIC-DOS from its hard disk (drive C:) and then types `WOLF3D` at the prompt, which runs the shareware version (1.4) of [Wolfenstein 3D](https://www.pcjs.org/software/pcx86/game/id/wolf3d/) from the hard disk's DEMOS\WOLF3D directory.

{% include machine.html id="ibm5170" %}

Click the screen to give the game the keyboard.  Press any key to get past the opening screens, use the arrow keys to move, **Ctrl** to fire, **Space** to open doors, and **Esc** for the menu; quitting the game returns to the BASIC-DOS prompt.  Any changes you make to the hard disk are lost when you leave the page.

This demo is also available on a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="at" %}
