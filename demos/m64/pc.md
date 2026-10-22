---
layout: page
title: BASIC-DOS on an IBM PC with 64K and a Monochrome Display
permalink: /demos/m64/pc/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-mda-64kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Monochrome Demo"
      B: "PC DOS 1.00"
---

With only 64K of memory, there isn't room for all of COMMAND.COM, so BASIC-DOS loads only its *core*: the graphics statements (CIRCLE, DRAW, GET, LINE, PAINT, PRESET, PSET, and PUT), the sound statements (PLAY and SOUND), the file statements (eg, OPEN and CLOSE), and LOAD's support for tokenized BAS files (like the originals on the PC DOS 1.00 diskette in drive B:) are left out, and using one of them reports `Not enough memory`.  The FPU$ driver is skipped as well (see CONFIG.SYS below), so there is no floating-point: numbers are 32-bit integers, and numeric functions like SQR are unavailable.

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088, 64K of memory, a Monochrome Display (appropriate for a configuration without graphics), and two diskette drives.  It boots the BASIC-DOS Monochrome Demo diskette and runs a single 80-column session.  Use the **MEM** command to display current memory usage.

{% include machine.html id="ibm5150" %}

{% include_relative _overview.md hw="pc" %}
