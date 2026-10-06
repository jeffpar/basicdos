---
layout: page
title: BASIC-DOS with DONKEY.BAS
permalink: /demos/basic/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    autoMount:
      A: "BASIC-DOS6"
      B: "PC DOS 1.00"
---

**DONKEY.BAS**, the game that Bill Gates and Neil Konzen wrote for the IBM PC in 1981, was the first BASIC sample from the PC DOS 1.00 diskette that BASIC-DOS was able to load and run to completion.  That was a major milestone: BASIC-DOS is no longer limited to small test programs, but can run real, full-featured BASIC programs, with graphics (SCREEN, LINE, PSET, GET, PUT, DRAW), sound (SOUND, PLAY), error handling (ON ERROR), and all the other statements and functions that DONKEY relies on.

And it runs them with better overall performance than BASICA, GW-BASIC, and other more conventional BASIC interpreters (see [Performance](/preview/part6/)), because BASIC-DOS doesn't interpret BASIC at all: it compiles each program into native 8086 code before running it, and its graphics statements write directly to video memory.

It also offers better DOS integration.  There's no separate BASIC environment to load: BASIC programs are just another kind of command, run directly from the DOS prompt, alongside COM, EXE, and BAT files, and a BASIC program can run other BASIC programs and batch files, too.

The machine below boots the BASIC-DOS6 diskette, which contains text copies of DONKEY.BAS and the other BASIC samples from the IBM PC DOS 1.00 diskette (whose copies, in drive B:, are in the tokenized format that only IBM BASIC can load).  To try it, type:

    DONKEY

Press the space bar to switch lanes, and ESC to exit.  When the program ends, BASIC-DOS restores the original display mode.

Then try CIRCLE, or the name of any other sample (type `DIR` to list them).  Not all of them run yet, but the list is growing.  See the DONKEY.BAS checklist in the [Project Status](/#donkeybas) for what was needed to run it.

For comparison, **MSBASIC** (built from Microsoft's GW-BASIC sources) is also on the diskette, so you can type `MSBASIC CIRCLE`, for example, to run the same program the conventional way, and then type `SYSTEM` to return to BASIC-DOS.

{% include machine.html id="ibm5150" %}

### **DONKEY.BAS** from the BASIC-DOS6 Diskette

```
{% include_relative DONKEY.BAS %}
```
