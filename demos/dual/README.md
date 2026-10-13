---
layout: page
title: BASIC-DOS with Dual Monitors
permalink: /demos/dual/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-dual-640kb.json
    debugger: available
    autoMount:
      A: "BASICDOS-DISK4"
---

The machine below is an IBM PC XT with 640K of memory and two monitors (MDA and CGA), and BASIC-DOS runs one session on each monitor: PRIMES.BAT on the Monochrome Display, and a build of BASIC-DOS itself (from the hard disk's SRC directory) on the Color Display.  When `Press a key to start...` appears on the Monochrome Display, press any key (or wait 5 seconds) to boot the BASICDOS-DISK4 diskette.

{% include machine.html id="ibm5160" %}

At first glance, it might appear there are two machines running, but it really is just a single IBM PC XT running two BASIC-DOS sessions.  The machine also has the 10Mb [BASIC-DOS hard disk](../hd/) (drive C:), which is why the boot sector stops to ask; press **ESC** at that prompt to boot from the hard disk instead.

Like all the other [BASIC-DOS Demos](../), use **SHIFT-TAB** to toggle keyboard focus between sessions.  Since these sessions don't use borders, the presence of a blinking cursor indicates which session has focus.

The machine is configured for 640K, and you can use the **MEM** command to display current memory usage and **MEM -D** for detailed memory usage.

A **MEMSIZE** line in **CONFIG.SYS** (eg, **MEMSIZE=128**) can limit the total memory used by BASIC-DOS.  You might be tempted to think that **MEMSIZE** is a way to "partition" memory, so that each session has a dedicated amount, but no -- **MEMSIZE** is simply a means of testing BASIC-DOS with different memory sizes.  And in any case, partitioning memory would not be a good strategy.

### **CONFIG.SYS** from the BASICDOS-DISK4 Diskette

```
{% include_relative CONFIG.SYS %}
```
