---
layout: page
title: BASIC-DOS with Extended Memory (VT100 Debugger) and an Empty Hard Disk
permalink: /demos/mmu/vt100/47mb/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    avo: true
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com2
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-ega-2mb.json
    debugger: available
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Serial Debugger"
      B: "BASIC-DOS Tests"
---

The machine below is an IBM PC AT (Model 5170) with the original 1984 ROM BIOS, a 6Mhz 80286, 2Mb of memory (640K of conventional memory and 1408K of extended memory), an Enhanced Color Display, two 1.2Mb diskette drives, an empty (unpartitioned and unformatted) 47Mb hard disk, a serial mouse on COM1, and a DEC VT100 on COM2 for BASIC-DOS's own debugger.  It boots the BASIC-DOS Serial Debugger diskette, which runs one console and loads DEBUG.COM as a driver on COM2.

See [Protected-Mode Initialization](/docs/bdtech/mmu/#pminit) for more details.

{% include vt100-demo.html id="ibm5170" %}

To set up the hard disk, type `FORMAT C: /S`: since the disk has no partition table, FORMAT offers to create one, with a single volume of up to 32Mb, and then formats the volume and copies the system files to it.  Then reset the machine and press **Esc** at the boot message to boot from the hard disk.  Changes to the hard disk are lost when you leave the page; use **Save HD** to download a copy as an IMG file.

The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette.

Additional demo configurations:

- [Extended Memory (Debugger) on IBM PC AT](../) with a 10Mb hard disk
- [Extended Memory (Debugger) on COMPAQ DeskPro 386](../386/) (using the 80386's features)

### **CONFIG.SYS** from the BASIC-DOS Serial Debugger Diskette

```
{{ site.data.pcx86.basicdos-configs["BASICDOS-360K-DEBUG"] }}
```
