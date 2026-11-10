---
layout: page
title: BASIC-DOS in Protected Mode (2Mb)
permalink: /demos/mmu/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-2mb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Protected Mode"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 2Mb of memory (640K of conventional memory and 1408K of extended memory), a Color Display, a 1.2Mb and a 1.44Mb diskette drive, a 10Mb hard disk, and a serial mouse on COM1.  It boots the BASIC-DOS Protected Mode diskette, which runs the same three consoles as the [Multiple Pages](../p80/at/) demo, each on its own page of video memory, but in protected mode.  Use **SHIFT-TAB** to switch between them.  Type `PAINT` in any console to draw with the mouse (click the screen to capture the mouse, and press **Esc** twice to exit); while PAINT's graphics mode is on the screen, the other consoles wait.

See [Protected-Mode Initialization](/docs/bdtech/mmu/#pminit) for more details.

{% include machine.html id="ibm5170" %}

The diskette's **CONFIG.SYS** defines three full-screen 80-column consoles, each running its own copy of COMMAND.COM: HELLO.BAT in the first, FIBO.BAT in the second, and PRIMES.BAS in the third.  Each session's memory is in its own LDT (local descriptor table), so a session's programs can't name another session's memory.  Only the page of the console with keyboard focus is displayed, but every console keeps running.

The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Note that bypassing the diskette and booting from the hard disk will give you only one full-screen console.

This demo is also available on a [COMPAQ DeskPro 386](386/), where it uses the 80386's features.

### **CONFIG.SYS** from the BASIC-DOS Protected Mode Diskette

```
{% include_relative CONFIG.SYS %}
```
