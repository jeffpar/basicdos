---
layout: page
title: BASIC-DOS with a VT100 Terminal
permalink: /demos/vt100/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5160.com1
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-vt100-640kb.json
    connection: com1->vt100.serialPort
    autoMount:
      A: "BASICDOS-VT100"
---

This IBM PC XT boots BASIC-DOS from the BASICDOS-VT100 diskette and runs two independent sessions: an 80x25 console on the Color Display, and a console on a DEC VT100 terminal connected to COM1 at 9600 baud.

<div class="vt100-demo">
<div class="vt100-demo-pc">
{% include machine.html id="ibm5160" %}
</div>
<div class="vt100-demo-terminal">
{% include machine.html id="vt100" %}
</div>
</div>

<style>
.vt100-demo { display: flex; flex-wrap: wrap; gap: 16px; align-items: flex-start; }
.vt100-demo > div { flex: 1 1 484px; min-width: 0; }
.pcjs-vt100-header { display: flex; justify-content: space-between; align-items: center; padding-bottom: 4px; }
.pcjs-vt100-header .pcjs-title { float: none; padding-bottom: 0; }
.pcjs-vt100-buttons { display: flex; gap: 8px; }
.pcjs-vt100-row { display: flex; flex-wrap: wrap; justify-content: flex-end; align-items: center; gap: 4px 0; margin-top: 8px; }
.pcjs-vt100-row .pcjs-block-control { display: block; }
#ibm5160 .pcjs-chassis { display: flex; flex-wrap: wrap; align-items: center; }
#ibm5160 .pcjs-chassis > div { order: 30; }
#ibm5160 .pcjs-chassis > .pcjs-video { order: 10; flex-basis: 100%; }
#ibm5160 .pcjs-fdc, #ibm5160 .pcjs-fdc > .pcjs-group { display: contents; }
#ibm5160 .pcjs-fdc .pcjs-control { order: 12; padding-bottom: 8px; }
#ibm5160 .pcjs-fdc [id="ibm5160.descDisk"], #ibm5160 .pcjs-fdc [id="ibm5160.mountDisk"] { order: 20; }
#ibm5160 .pcjs-keyboard, #ibm5160 .pcjs-keyboard > .pcjs-group { display: contents; }
#ibm5160 .pcjs-keyboard .pcjs-control { order: 40; padding-bottom: 8px; }
#ibm5160 .pcjs-keyboard .pcjs-control, #ibm5160 .pcjs-fdc .pcjs-control { line-height: 22px; }
#ibm5160 .pcjs-keyboard [id="ibm5160.caps-lock"], #ibm5160 .pcjs-keyboard [id="ibm5160.num-lock"], #ibm5160 .pcjs-keyboard [id="ibm5160.scroll-lock"] { order: 15; }
#ibm5160 .pcjs-chassis > .pcjs-serial { order: 16; flex-basis: 100%; }
#ibm5160 .pcjs-fdc [id="ibm5160.saveDisk"] { padding-right: 0 !important; }
#ibm5160 .pcjs-fdc [id="ibm5160.descDisk"]:has(> .pcjs-description:empty) { display: none; }
#ibm5160 .pcjs-keyboard [id="ibm5160.num-lock"], #ibm5160 .pcjs-keyboard [id="ibm5160.scroll-lock"] { padding-left: 6px !important; }
#ibm5160 .pcjs-keyboard [id="ibm5160.caps-lock"] { margin-left: auto; }
#ibm5160 .pcjs-keyboard [id="ibm5160.shift-tab"] { margin-left: auto; }
#ibm5160 .pcjs-keyboard [id="ibm5160.keys"] { order: 35; }
#ibm5160 .pcjs-chassis > .pcjs-computer { order: 25; flex-basis: 100%; }
#ibm5160 .pcjs-soft-keyboard, #ibm5160 .pcjs-soft-keyboard-mobile { order: 50; flex-basis: 100%; }
</style>

Press any key on the Color Display at the boot prompt to start the diskette.  Then click the VT100 screen and type a command, such as `DIR` or `PRINT "Hello from the VT100"`; click the Color Display to use the local session.  Both sessions start on drive C:, the [hard disk](../hd/), and share its programs and files.

The VT100 console uses the COM driver's VT100 terminal type, so commands like `CLS` and `LOCATE` use VT100 escape sequences, the VT100's DELETE key erases the previous character (like the PC's BACKSPACE key), and XON/XOFF flow control is enabled, which the VT100 relies on whenever it falls behind (eg, while smooth scrolling).

### CONFIG.SYS from the BASICDOS-VT100 diskette

```
{% include_relative CONFIG.SYS %}
```

Changes to the hard disk are lost when you leave the page.
