---
layout: page
title: BASIC-DOS with Extended Memory on a COMPAQ DeskPro 386
permalink: /demos/bd/mmu/386/
machines:
  - id: deskpro386
    type: pcx86
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-2mb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Extended Memory"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is a COMPAQ DeskPro 386 with a 16Mhz 80386, 2Mb of memory (640K of conventional memory and 1Mb of extended memory, plus 384K that ends at 16Mb: the last 128K holds the ROM BIOS's copy of the ROMs, and BASIC-DOS uses the other 256K, at FA0000h), a VGA Color Display, a Sound Blaster, a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk.  It boots the same BASIC-DOS Extended Memory diskette as the [PC AT](../) version of this demo, which runs three consoles, each on its own page of video memory, with their shells on the hard disk, and DOS can also allocate memory from extended memory.  It runs in protected mode, the default on a DeskPro 386, with the 80386's features: an 80386 TSS, selectors that can cover more than 64K, paging, and V86 machines, which [V86](/docs/bdman/cmd/external/v86/) uses to run real-mode COM programs.  Use **SHIFT-TAB** to switch between consoles.

See [The CPU$ Drivers](/docs/bdtech/mmu/#cpu) and [Protected-Mode Initialization](/docs/bdtech/mmu/#pminit) for more details.

{% include machine.html id="deskpro386" %}

The diskette's **CONFIG.SYS** defines three full-screen 80-column consoles, each running its own copy of COMMAND.COM: HELLO.BAT in the first, FIBO.BAT in the second, and PRIMES.BAS in the third.  Each session's memory is in its own LDT (local descriptor table), so a session's programs can't name another session's memory.  Only the page of the console with keyboard focus is displayed, but every console keeps running.

The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Note that bypassing the diskette and booting from the hard disk will give you only one full-screen console.

Additional hardware options:

- [Extended Memory (2Mb) on IBM PC AT](../)

### **CONFIG.SYS** from the BASIC-DOS Extended Memory Diskette

```
{{ site.data.pcx86.basicdos-configs["BASICDOS-360K-P80PM"] }}
```
