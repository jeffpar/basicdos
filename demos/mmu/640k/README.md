---
layout: page
title: BASIC-DOS in Protected Mode with 640K
permalink: /demos/mmu/640k/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Protected Mode"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of conventional memory, no extended memory, a Color Display, a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk.  It boots the BASIC-DOS Protected Mode diskette, which runs the same three consoles as the [2Mb Protected Mode](../) demo, each on its own page of video memory.  Use **SHIFT-TAB** to switch between them.

Protected mode needs only 256K of conventional memory; any extended memory is a bonus.  See [Supported Machines](/docs/bdtech/mmu/#machines) and [The System Area](/docs/bdtech/mmu/#sysarea) for more details.

{% include machine.html id="ibm5170" %}

The diskette's **CONFIG.SYS** defines three full-screen 80-column consoles, each running its own copy of COMMAND.COM: HELLO.BAT in the first, FIBO.BAT in the second, and PRIMES.BAS in the third.  Each session's memory is in its own LDT (local descriptor table), so a session's programs can't name another session's memory.  Only the page of the console with keyboard focus is displayed, but every console keeps running.

The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Note that bypassing the diskette and booting from the hard disk will give you only one full-screen console.

### **CONFIG.SYS** from the BASIC-DOS Protected Mode Diskette

```
{{ site.data.pcx86.basicdos-configs["BASICDOS-360K-P80PM"] }}
```
