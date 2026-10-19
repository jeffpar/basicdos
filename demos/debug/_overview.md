The BASICDOS-360K-DEBUG diskette boots with a local console and a debugger on a DEC VT100 connected to COM2 at 9600 baud.  `DEBUG.COM` (in the **BIN** directory) is loaded by `DEVICE=` in CONFIG.SYS, independently of BASDEV.  It opens and exclusively claims COM2; subsequent attempts to open that port fail.

Wait for the debugger's startup message on the VT100, then click its screen and press **Ctrl-C** (or BREAK).  The local machine stops and the terminal displays the interrupted registers, the current instruction, and a `-` prompt.  Type `?` for help, `R` to display registers, `U` to disassemble, `T` to single-step, or `G` to resume the local session.  Breakpoints and any other INT 1 or INT 3 also enter the debugger.

Memory dumps use SYMDEB's segmented addresses, uppercase hex, groups of eight bytes, and an ASCII column.  All numbers are hexadecimal:

- `D 0:400 L 80` displays 128 bytes of BIOS data.
- `D CS:0 L 40` displays 64 bytes at the interrupted code segment.
- `D B800:0 FF` displays the first 256 bytes of color display memory.
- `D` continues the preceding dump for another 128 bytes.

Other commands, as in DEBUG and SYMDEB:

- `U CS:IP` disassembles 32 bytes of 8086 instructions; `U` continues.
- `BP1 1234:0100` sets breakpoint 1 of 9 (without the number, BP picks a free one), `BL` lists them, and `BC 1` (or `BC *`) clears them.
- `G 0123:0456` resumes with a temporary breakpoint; a breakpoint at CS:IP is stepped past first.
- `T 5` executes 5 instructions, displaying the registers after each.
- `E DS:200 41 42 "text"` stores bytes; `E DS:200` prompts for each byte.
- `R AX 1234` changes AX; `R CS`, `R IP`, and even `R SS` and `R SP` work (prompting if no value is given), and `R F` prompts for flag names such as `CY ZR`.

Breakpoints use INT 3, so they work only in RAM.  While stopped, interrupts and the scheduler are suspended; `G` restores the interrupted state.  XON/XOFF and optional RTS/CTS are honored by the polling serial output.  Ordinary characters typed while running are ignored.

The resident driver uses local string and hex formatting with polling serial I/O.  The kernel's public `SPRINTF` and `ITOA` utilities enable interrupts and enter through the DOS dispatcher, so they are unsafe when the debugger has stopped inside DOS or an IRQ handler.  This deliberately duplicates a small amount of formatting code to keep inspection independent of the suspended kernel.  A selectable kernel formatter would first need a reentrant entry point that keeps interrupts disabled.  Only initialization calls DOS.

### **CONFIG.SYS** from the BASICDOS-360K-DEBUG diskette

```
{% include_relative CONFIG.SYS %}
```

The BASICDOS-360K-TESTS diskette in drive B: has DBGTEST.  Run `B:\TESTS\MISC\DBGTEST` on the local console to check that COM2 is reserved and registers and flags survive INT 3; resume with `G` at each of its two stops.  The local console should report `DBGTEST passed`.

A successful build (`./mkdos.sh` or `./mk.sh`, with or without `debug`) updates this disk automatically (if PCJS is set; see gulpfile.js).  DEBUG kernel builds provide runtime assertions; the driver also works with release builds.  If the full DEBUG build reaches MASM's symbol-space limit in the command shell, the kernel and driver can still be built separately and used with the release shell.
