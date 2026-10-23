---
layout: page
title: BASIC-DOS with a Parallel Port
permalink: /demos/parallel/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-parallel-640kb.json
    autoMount:
      A: "BASIC-DOS 80-Column Demo"
---

This IBM PC XT boots the BASIC-DOS 80-Column Demo diskette and runs a single 80x25 session on the Color Display, with its parallel port (LPT1) connected to the **Printer** pane, which shows everything the machine prints.  BASIC-DOS's printer device, PRN, is LPT1.

Type `LPRINT "Hello from LPT1"`, or enter a few program lines and type `LLIST`, or run `CALENDAR` (one of the PC DOS 1.00 samples) and choose a year to print a two-month-per-page calendar.  Since the Printer pane is plain text, it shows control characters by name (eg, `<ESC>` for the escape sequences that CALENDAR sends to IBM's printer) and the printer's block graphics characters as asterisks.

<style>
#ibm5160 .pcjs-chassis { display: flow-root; }
#ibm5160 .pcjs-video { float: left; width: 49%; }
#ibm5160 .pcjs-parallel { float: right; width: 49%; }
#ibm5160 .pcjs-parallel .pcjs-title { float: none; }
#ibm5160 .pcjs-parallel .pcjs-control { float: none; clear: both; width: 100%; }
#ibm5160 .pcjs-parallel textarea { display: block; box-sizing: border-box; margin: 0; padding: 4px; border: 1px solid #666; font-family: monospace; color: #111; background: #f4f1e8; }
#ibm5160 .pcjs-fdc { clear: both; }
@media (max-width: 700px) {
  #ibm5160 .pcjs-video, #ibm5160 .pcjs-parallel { float: none; width: 100%; }
}
</style>

{% include machine.html id="ibm5160" %}

<script src="/assets/js/serial-terminal.js" defer></script>

Press any key at the boot prompt (or wait 2 seconds) to start the diskette, or press **Esc** to boot from the [hard disk](../hd/xt/) instead.

If there's no printer (eg, on a machine without a parallel port), LPRINT, LLIST, and PRINT # to PRN report "Device timeout", as in Microsoft BASIC.
