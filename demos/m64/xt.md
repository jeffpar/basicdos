---
layout: page
title: BASIC-DOS on an IBM PC XT with 640K and a Monochrome Display
permalink: /demos/m64/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-mda-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS 640K Monochrome Demo"
      B: "PC DOS 1.00"
    autoType: DATE $date\rTIME $time\r
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, a Monochrome Display, two diskette drives, and a 10Mb hard disk.  It boots the BASIC-DOS 640K Monochrome Demo diskette and runs a single 80-column session, which starts on drive C:, the hard disk, with the BASIC-DOS source code, tests, and tools.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC XT has no clock to keep the date and time, so this page types `DATE` and `TIME` commands with the current date and time at the first prompt.

{% include machine.html id="ibm5160" %}

Unlike the 64K version of this demo, there's room for all of COMMAND.COM and the FPU$ driver, so floating-point, the sound and file statements, and LOAD's support for tokenized BAS files (like the originals on the PC DOS 1.00 diskette in drive B:) are all available; the graphics statements are too, but without a graphics adapter, they report `Illegal function call`.  To build BASIC-DOS, type `CD \SRC` and then `MK` to rebuild whatever has changed, or `MK FINAL CLEAN` to rebuild everything.

Any changes you make to the hard disk are lost when you leave the page, unless you first click **Save HD** to download the hard disk as an IMG file.

This demo is also available on an [IBM PC](../pc/) with 64K and no hard disk.

{% include_relative _overview.md hw="xt" %}
