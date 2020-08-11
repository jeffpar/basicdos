---
layout: page
title: BASIC-DOS with Dual Monitors
permalink: /maplebar/dual/
machines:
  - id: ibm5150
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-dual-256kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS4"
---

The machine below is configured with both MDA and CGA adapters, each
connected to its own monitor.

Other dual-monitor configurations include:

  - [Dual Monitor Development Machine](dev/)
  - [Dual Monitor Multiple Session Demo](multi/)

In this demo, BASIC-DOS has been configured for two sessions, with each
session assigned to its own monitor.  At first glance, it might appear there
are two machines running, but it really is just a single IBM PC running two
BASIC-DOS sessions.

Like all the other [BASIC-DOS Demos](../), use **SHIFT-TAB** to toggle
keyboard focus between sessions.  Since these sessions don't use borders,
the presence of a blinking cursor indicates which session has focus.

Also, while the machine is configured for 256K, if you **TYPE CONFIG.SYS**,
you'll see that it contains a **MEMSIZE=128** line which limits total BASIC-DOS
memory usage to 128K.  You can use the **MEM** command to display current
memory usage.

You might be tempted to think that **MEMSIZE** is a way to "partition" memory,
so that each session has a dedicated amount, but no -- **MEMSIZE** is simply
a means of testing BASIC-DOS with different memory sizes.  And in any case,
partitioning memory would not be a good strategy.

{% include machine.html id="ibm5150" %}
