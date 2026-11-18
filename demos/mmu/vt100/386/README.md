---
layout: page
title: BASIC-DOS with Extended Memory (VT100 Debugger) on a COMPAQ DeskPro 386
permalink: /demos/mmu/vt100/386/
machines:
  - id: deskpro386
    type: pcx86
    name: COMPAQ DeskPro 386 with VGA and Serial Mouse
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-2mb.json
    debugger: available
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Extended Memory VT100"
      B: "BASIC-DOS Tests"
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    avo: true
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->deskpro386.com2
---

The machine below is a COMPAQ DeskPro 386 with a 16Mhz 80386, 2Mb of memory (640K of conventional memory and 1Mb of extended memory, plus 384K that ends at 16Mb: the last 128K holds the ROM BIOS's copy of the ROMs, and BASIC-DOS uses the other 256K, at FA0000h), a VGA Color Display, a 1.2Mb and a 1.44Mb diskette drive, a 10Mb hard disk, a serial mouse on COM1, and a DEC VT100 on COM2 for BASIC-DOS's own debugger.  It boots the same BASIC-DOS Extended Memory VT100 diskette as the [PC AT](../) version of this demo, which runs the same three consoles as the [DeskPro 386 Extended Memory](../../386/) demo, each on its own page of video memory, with the 80386's features, and loads DEBUG.COM as a driver on COM2.  Use **SHIFT-TAB** to switch between them.  Type `PAINT` in any console to draw with the mouse (click the screen to capture the mouse, and press **Esc** twice to exit); while PAINT's graphics mode is on the screen, the other consoles wait.

See [The CPU$ Drivers](/docs/bdtech/mmu/#cpu) and [Debugging](/docs/bdtech/mmu/#pmdebug) for more details.

{% include vt100-demo.html id="deskpro386" %}

The diskette's **CONFIG.SYS** defines three full-screen 80-column consoles, each running its own copy of COMMAND.COM: HELLO.BAT in the first, FIBO.BAT in the second, and PRIMES.BAS in the third.  Each session's memory is in its own LDT (local descriptor table), so a session's programs can't name another session's memory.  Only the page of the console with keyboard focus is displayed, but every console keeps running.

The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Note that bypassing the diskette and booting from the hard disk will give you only one full-screen console.

Additional hardware options:

- [Extended Memory (Debugger) on IBM PC AT](../)
- [Extended Memory (Empty HD and Debugger) on IBM PC AT](../47mb/)

### **CONFIG.SYS** from the BASIC-DOS Extended Memory VT100 Diskette

```
{{ site.data.pcx86.basicdos-configs["BASICDOS-360K-MMU"] }}
```
