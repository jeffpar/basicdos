The BASICDOS-360K-M64 diskette's **CONFIG.SYS** skips the FPU$ driver and every other driver that a single full-screen session doesn't need (the serial ports, the mouse, the hard disk, the second and third printers, and pipes), and asks for the minimum numbers of buffers, files, and sessions, so that BASIC-DOS fits in 64K with about 3K to spare.  Since there isn't room for all of COMMAND.COM, the loader loads only its core, which leaves out graphics, sound, and tokenized BAS files (see [COMDATA](/docs/bdtech/data/#comdata) for how a program declares its core), and COMMAND.COM reports `Not enough memory` for the statements that were left out.  Unlike the other demos, COMMAND.COM doesn't run **HELLO.BAT** here (its colors mean nothing on a monochrome display, and the first command after boot has about 1K less to work with than later ones, since the prompt's own code and variable blocks haven't been set up yet); type **HELP** for a list of commands, **DIR** to list the files on the diskette, and **PRIMES.BAS** to run the BASIC version of PRIMES.

### BASIC Samples

The diskette's **SAMPLES** directory contains text copies of the BASIC samples from the IBM PC DOS 1.00 diskette, but most of them use graphics (and some use floating-point), so they can't run here; the [Color (with FPU)](../../s80/pc/) demo runs them.  The PC DOS 1.00 diskette in drive B: holds the original *tokenized* copies, which this configuration can't load at all (`Invalid file format`).

### **CONFIG.SYS** from the BASICDOS-360K-M64 Diskette

```
{% include_relative CONFIG.SYS %}
```
