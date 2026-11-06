---
layout: page
title: BASIC-DOS in Protected Mode (VT100)
permalink: /demos/mmu/vt100/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com2
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-2mb.json
    debugger: available
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Protected Mode with VT100"
      B: "BASIC-DOS Tests"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 2Mb of memory (640K of conventional memory and 1408K of extended memory), a Color Display, a 1.2Mb and a 1.44Mb diskette drive, a 10Mb hard disk, and a DEC VT100 on COM2 for BASIC-DOS's own debugger.  It boots the BASIC-DOS Protected Mode with VT100 diskette, which runs the same three consoles as the [Protected Mode](../) demo, each on its own page of video memory, and loads DEBUG.COM as a driver on COM2.  Use **SHIFT-TAB** to switch between them.

See [Protected-Mode Initialization](/docs/bdtech/mmu/#pminit) for more details.

{% include vt100-demo.html id="ibm5170" %}

The diskette's **CONFIG.SYS** defines three full-screen 80-column consoles, each running its own copy of COMMAND.COM: HELLO.BAT in the first, FIBO.BAT in the second, and PRIMES.BAS in the third.  Each session's memory is in its own LDT (local descriptor table), so a session's programs can't name another session's memory.  Only the page of the console with keyboard focus is displayed, but every console keeps running.

Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Note that bypassing the diskette and booting from the hard disk will give you only one full-screen console.

### **CONFIG.SYS** from the BASIC-DOS Protected Mode with VT100 Diskette

```
{% include_relative CONFIG.SYS %}
```
