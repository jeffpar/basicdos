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

There are currently eight BASIC-DOS demo configurations:

 1. [Single 25x80 session](s80/)
 2. [Two 40-column sessions](d40/)
 3. [Two 80-column sessions](d80/)
 4. [Dual monitors with single sessions](dual/)
 5. [Dual monitors with multiple sessions](dual/multi/)
 6. [BASIC-DOS running DONKEY.BAS](basic/)
 7. [BASIC-DOS on a Hard Disk](hd/)
 8. [BASIC-DOS Multitasking Stress Tests](stress/)

The machine below is the single-session demo.  In the demos with multiple sessions, use **SHIFT-TAB** to toggle keyboard focus between sessions.

{% include machine.html id="ibm5150" %}
