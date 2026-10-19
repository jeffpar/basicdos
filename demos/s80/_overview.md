The BASICDOS-360K-S80 diskette's **CONFIG.SYS** doesn't define any consoles, so BASIC-DOS creates a single 80-column, 25-row session, running COMMAND.COM, which runs **HELLO.BAT** to display a colorful greeting.  Type **HELP** for a list of commands, **DIR** to list the files on the diskette, and **PRIMES.BAS** to run the BASIC version of PRIMES.

### BASIC Samples

The diskette's **SAMPLES** directory contains text copies of DONKEY.BAS and the other BASIC samples from the IBM PC DOS 1.00 diskette, and CONFIG.SYS sets PATH$ so that they can be run from any directory.  To try one, type `DONKEY`, press the space bar to switch lanes, and press ESC to exit.  When DONKEY ends, BASIC-DOS restores the original display mode.  Then try CIRCLE, or the name of any other sample (type `DIR SAMPLES` to list them).  Not all of them run yet, but the list is growing.  See the DONKEY.BAS checklist in the [Project Status](/#donkeybas) for what was needed to run it.

The machines also have the PC DOS 1.00 diskette in drive B:, whose original copies of the samples are in the *tokenized* format that IBM BASIC saves; BASIC-DOS can load and run those, too (eg, `B:DONKEY`).

For comparison, **MSBASIC** (built from Microsoft's GW-BASIC sources) is on the BASICDOS-360K-TESTS diskette, in its **TOOLS** directory, so you can load that diskette in drive B:, type `CD SAMPLES`, and then `B:\TOOLS\MSBASIC CIRCLE`, for example, to run the same program the conventional way, and then type `SYSTEM` to return to BASIC-DOS.

**DONKEY.BAS**, the game that Bill Gates and Neil Konzen wrote for the IBM PC in 1981, was the first BASIC sample from the PC DOS 1.00 diskette that BASIC-DOS was able to load and run to completion.  BASIC-DOS doesn't interpret BASIC at all: it compiles each program into native 8086 code before running it, and its graphics statements write directly to video memory, so it runs them with better overall performance than BASICA, GW-BASIC, and other more conventional BASIC interpreters (see [Performance](/preview/part6/)).  BASIC programs are also just another kind of command, run directly from the DOS prompt, alongside COM, EXE, and BAT files.

### **CONFIG.SYS** from the BASICDOS-360K-S80 Diskette

```
{% include_relative CONFIG.SYS %}
```
