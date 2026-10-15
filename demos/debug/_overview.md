The BASICDOS-DEBUG diskette boots with a local console and a debugger on a DEC VT100 connected to COM2 at 9600 baud.  `DEBUG.COM` is loaded by `DEVICE=` in CONFIG.SYS, independently of BASDEV.  It opens and exclusively claims COM2; subsequent attempts to open that port fail.

Wait for the debugger's startup message on the VT100, then click its screen and press **Ctrl-C** (or BREAK).  The local machine stops and the terminal displays the interrupted registers and a `-` prompt.  Type `?` for help, `R` to display registers, or `G` to resume the local session.  INT 1 and INT 3 also enter the debugger.

Memory dumps use SYMDEB's segmented addresses, uppercase hex, groups of eight bytes, and an ASCII column.  All numbers are hexadecimal:

- `D 0:400 L 80` displays 128 bytes of BIOS data.
- `D CS:0 L 40` displays 64 bytes at the interrupted code segment.
- `D B800:0 FF` displays the first 256 bytes of color display memory.
- `D` continues the preceding dump for another 128 bytes.

The debugger supports read-only memory and register inspection.  It does not disassemble instructions, modify registers or memory, or set software breakpoints.  While stopped, interrupts and the scheduler are suspended; `G` restores the interrupted state.  XON/XOFF and optional RTS/CTS are honored by the polling serial output.  Ordinary characters typed while running are ignored.

The resident driver uses local string and hex formatting with polling serial I/O.  The kernel's public `SPRINTF` and `ITOA` utilities enable interrupts and enter through the DOS dispatcher, so they are unsafe when the debugger has stopped inside DOS or an IRQ handler.  This deliberately duplicates a small amount of formatting code to keep inspection independent of the suspended kernel.  A selectable kernel formatter would first need a reentrant entry point that keeps interrupts disabled.  Only initialization calls DOS.

### **CONFIG.SYS** from the BASICDOS-DEBUG diskette

```
{% include_relative CONFIG.SYS %}
```

Run `DBGTEST` on the local console to check that COM2 is reserved and registers and flags survive INT 3; resume with `G` at each of its two stops.  The local console should report `DBGTEST passed`.

Build with `./mk.sh` or `./mk.sh debug`, then regenerate this disk with `npx gulp BUILD-BASICDOS-DEBUG`.  DEBUG kernel builds provide runtime assertions; the driver also works with release builds.  If the full DEBUG build reaches MASM's symbol-space limit in the command processor, the kernel and driver can still be built separately and used with the release command processor.
