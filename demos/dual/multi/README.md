---
layout: page
title: BASIC-DOS with "Dueling Monitors"
permalink: /demos/dual/multi/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-dual-640kb.json
    debugger: available
    autoMount:
      A: "BASICDOS-DISK5"
---

The machine below is an IBM PC XT with 640K of memory and two monitors (MDA and CGA), and BASIC-DOS runs FOUR sessions, two on each monitor.  When `Press a key to start...` appears on the Monochrome Display, press any key to boot the BASICDOS-DISK5 diskette.

{% include machine.html id="ibm5160" %}

Use **SHIFT-TAB** to move keyboard focus from one session to the next.  The machine also has the 10Mb [BASIC-DOS hard disk](../../hd/) (drive C:), which is why the boot sector stops to ask; press **ESC** at that prompt to boot from the hard disk instead.

### **CONFIG.SYS** from the BASICDOS-DISK5 Diskette

```
{% include_relative CONFIG.SYS %}
```
