---
layout: page
title: BASIC-DOS on a Hard Disk
permalink: /demos/hd/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-128kb.json
    debugger: available
---

The machine below is an IBM PC XT with no diskettes loaded; instead, it boots BASIC-DOS from its 10Mb hard disk (drive C:), which contains the BASIC-DOS system files in the root directory, and DONKEY.BAS and the other BASIC samples (along with BENCH.BAS and PRIMES.BAS) in a **BASIC** subdirectory.

The prompt displays the current directory, so it starts as `C:/>`.  To go into the **BASIC** directory, list its files, and run a program, type:

    CD BASIC
    DIR
    DONKEY

Press the space bar to switch lanes in DONKEY, and ESC to exit.  To go back to the root directory, type `CD ..` (or `CD /`).  You can also create and remove your own directories with **MD** and **RD**, and use paths anywhere a file name is expected (eg, `TYPE /BASIC/PRIMES.BAS` or, from the **BASIC** directory, `DIR ..`).  Like the rest of BASIC-DOS, paths use `/` to separate directory names, so switches use `-` instead (eg, `DIR -P`).

The machine also has a serial mouse on COM2, which the MOUSE$ driver finds at boot.  Click the screen to capture the mouse, and then run `MBROT` from the **BASIC** directory to see the mouse pointer while the Mandelbrot set is drawn (BASIC programs use the mouse with [MOUSE ON and the MOUSE function](/docs/bdman/cmd/device/mouse/)).

Any changes you make to the hard disk are lost when you leave the page.

{% include machine.html id="ibm5160" %}

### **CONFIG.SYS** from the BASICDOS-HD Hard Disk

```
{% include_relative CONFIG.SYS %}
```
