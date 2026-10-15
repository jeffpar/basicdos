---
layout: page
title: BASIC-DOS with a Serial Display
permalink: /demos/serial/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-serial-640kb.json
    autoMount:
      A: "BASICDOS-360K-SERIAL"
---

This IBM PC XT boots BASIC-DOS from the BASICDOS-360K-SERIAL diskette and runs two independent sessions: an 80x25 console on the Color Display and a serial console on COM1 at 9600 baud, with no parity, eight data bits, and one stop bit.  The serial console uses the GENERIC terminal mode for this text pane.

Click the **Serial Display** pane to the right of the machine and type a command, such as `DIR` or `PRINT "Hello from COM1"`.  Click the Color Display to use the local session.  Both sessions share the same hard disk.

<style>
#ibm5160 .pcjs-chassis { display: flow-root; }
#ibm5160 .pcjs-video { float: left; width: 49%; }
#ibm5160 .pcjs-serial { float: right; width: 49%; }
#ibm5160 .pcjs-serial .pcjs-title { float: none; }
#ibm5160 .pcjs-serial .pcjs-control { float: none; clear: both; width: 100%; }
#ibm5160 .pcjs-serial textarea { display: block; box-sizing: border-box; margin: 0; padding: 4px; border: 1px solid #666; font-family: monospace; color: #eee; background: #111; }
#ibm5160 .pcjs-fdc { clear: both; }
@media (max-width: 700px) {
  #ibm5160 .pcjs-video, #ibm5160 .pcjs-serial { float: none; width: 100%; }
}
</style>

{% include machine.html id="ibm5160" %}

<script src="/assets/js/serial-terminal.js" defer></script>

Press any key at the boot prompt (or wait 5 seconds) to start the diskette.  Its CONFIG.SYS creates both consoles and launches `C:COMMAND.COM` for each.  Each session starts on the drive named in its SHELL line, so both sessions start on C:.  The [hard disk](../hd/xt/) supplies programs and files.

### CONFIG.SYS from the BASICDOS-360K-SERIAL diskette

```
{% include_relative CONFIG.SYS %}
```

Changes to the hard disk are lost when you leave the page.  Use **Save HD** to download a copy as an IMG file.
