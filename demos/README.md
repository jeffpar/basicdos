---
layout: page
heading: BASIC-DOS Demos
permalink: /demos/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    debugger: available
---

There are currently nine BASIC-DOS demo configurations:

 1. [Single 25x80 session](s80/) (see below)
 2. [Two 40-column sessions](d40/)
 3. [Two 80-column sessions](d80/)
 4. [Dual monitors with single sessions](dual/)
 5. [Dual monitors with multiple sessions](dual/multi/)
 6. [BASIC-DOS running DONKEY.BAS](basic/)
 7. [BASIC-DOS on a Hard Disk](hd/)
 8. [BASIC-DOS with a Serial Terminal](serial/)
 9. [BASIC-DOS with a VT100 Terminal](vt100/)
10. [BASIC-DOS drawing the Mandelbrot set](mbrot/)

In the demos with multiple sessions, use **SHIFT-TAB** to toggle keyboard focus between sessions.

The machine below is the single-session demo: an IBM PC that boots the `BASICDOS-DISK1` diskette and runs one 80-column session.

{% include machine.html id="ibm5150" %}
