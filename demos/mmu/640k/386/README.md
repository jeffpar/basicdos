---
layout: page
title: BASIC-DOS in Protected Mode with 640K on a COMPAQ DeskPro 386
permalink: /demos/mmu/640k/386/
machines:
  - id: deskpro386
    type: pcx86
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-1mb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Protected Mode (80386)"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is a COMPAQ DeskPro 386 with a 16Mhz 80386, 1Mb of memory (640K of conventional memory, plus 384K that COMPAQ reserves at FA0000h, so no extended memory), a VGA Color Display, a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk.  It boots the BASIC-DOS Protected Mode (80386) diskette, which runs the same three consoles as the [2Mb DeskPro 386](../../386/) demo, each on its own page of video memory, with the 80386's features.  Use **SHIFT-TAB** to switch between them.

Protected mode can run in as little as 256K of conventional memory; any additional conventional or extended memory is just a bonus.  See [Supported Machines](/docs/bdtech/mmu/#machines) and [The System Area](/docs/bdtech/mmu/#sysarea) for more details.

{% include machine.html id="deskpro386" %}

The diskette's **CONFIG.SYS** defines three full-screen 80-column consoles, each running its own copy of COMMAND.COM: HELLO.BAT in the first, FIBO.BAT in the second, and PRIMES.BAS in the third.  Each session's memory is in its own LDT (local descriptor table), so a session's programs can't name another session's memory.  Only the page of the console with keyboard focus is displayed, but every console keeps running.

The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Note that bypassing the diskette and booting from the hard disk will give you only one full-screen console.

This demo is also available on an [IBM PC AT](../).

### **CONFIG.SYS** from the BASIC-DOS Protected Mode (80386) Diskette

```
{{ site.data.pcx86.basicdos-configs["BASICDOS-360K-PM386"] }}
```
