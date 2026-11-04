---
layout: page
title: BASIC-DOS on an IBM PC AT with Multiple Video Pages in Protected Mode
permalink: /demos/p80/pm/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-2mb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS PM Multi-Page Demo"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 2Mb of memory (640K of conventional memory and 1408K of extended memory), a Color Display, a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk.  It boots the BASIC-DOS PM Multi-Page Demo diskette, which runs the same three sessions as the [Multiple Pages](../at/) demo, each on its own page of video memory, but in protected mode: its CONFIG.SYS has no `CPU=8088` line, so BASIC-DOS switches the 80286 to protected mode, manages all memory (including extended memory), and runs each session's programs at ring 3.  Use **SHIFT-TAB** to switch between them.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC AT has a battery-powered real-time clock, so BASIC-DOS starts with the current date and time (type `DATE` or `TIME` to see them).

{% include machine.html id="ibm5170" %}

The diskette's **CONFIG.SYS** defines three full-screen 80-column consoles, each running its own copy of COMMAND.COM: HELLO.BAT in the first, FIBO.BAT in the second, and PRIMES.BAS in the third.  Each session's memory is in its own LDT (local descriptor table), so a session's programs can't name another session's memory.  Only the page of the session with keyboard focus is displayed, but every session keeps running.  See [Protected-Mode Initialization](/docs/bdtech/mmu/#pminit) for more details.

### **CONFIG.SYS** from the BASIC-DOS PM Multi-Page Demo Diskette

```
{% include_relative CONFIG.SYS %}
```
