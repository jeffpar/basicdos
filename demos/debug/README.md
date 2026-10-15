---
layout: page
title: BASIC-DOS with Debugger on Serial Port
permalink: /demos/debug/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5160.com2
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-debug-640kb.json
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASICDOS-DEBUG"
---

This IBM PC XT boots the BASICDOS-DEBUG diskette with a local console and a debugger on a DEC VT100 connected to COM2 at 9600 baud. `DEBUG.COM` is loaded by `DEVICE=` in CONFIG.SYS, independently of BASDEV. It opens and exclusively claims COM2; subsequent attempts to open that port fail.

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

Wait for the debugger's startup message on the VT100, then click its screen and press **Ctrl-C** (or BREAK). The local machine stops and the terminal displays the interrupted registers and a `-` prompt. Type `?` for help, `R` to display registers, or `G` to resume the local session. INT 1 and INT 3 also enter the debugger.

Memory dumps use SYMDEB's segmented addresses, uppercase hex, groups of eight bytes, and an ASCII column. All numbers are hexadecimal:

- `D 0:400 L 80` displays 128 bytes of BIOS data.
- `D CS:0 L 40` displays 64 bytes at the interrupted code segment.
- `D B800:0 FF` displays the first 256 bytes of color display memory.
- `D` continues the preceding dump for another 128 bytes.

The debugger supports read-only memory and register inspection. It does not disassemble instructions, modify registers or memory, or set software breakpoints. While stopped, interrupts and the scheduler are suspended; `G` restores the interrupted state. XON/XOFF and optional RTS/CTS are honored by the polling serial output. Ordinary characters typed while running are ignored.

The resident driver uses local string and hex formatting with polling serial I/O. The kernel's public `SPRINTF` and `ITOA` utilities enable interrupts and enter through the DOS dispatcher, so they are unsafe when the debugger has stopped inside DOS or an IRQ handler. This deliberately duplicates a small amount of formatting code to keep inspection independent of the suspended kernel. A selectable kernel formatter would first need a reentrant entry point that keeps interrupts disabled. Only initialization calls DOS.

### CONFIG.SYS from the BASICDOS-DEBUG diskette

```
{% include_relative CONFIG.SYS %}
```

Run `DBGTEST` on the local console to check that COM2 is reserved and registers and flags survive INT 3; resume with `G` at each of its two stops. The local console should report `DBGTEST passed`.

Build with `./mk.sh` or `./mk.sh debug`, then regenerate this disk with `npx gulp BUILD-BASICDOS-DEBUG`. DEBUG kernel builds provide runtime assertions; the driver also works with release builds. If the full DEBUG build reaches MASM's symbol-space limit in the command processor, the kernel and driver can still be built separately and used with the release command processor.
