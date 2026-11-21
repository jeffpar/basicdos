---
layout: page
title: Preview
permalink: /preview/part2/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    autoMount:
      A: "BASIC-DOS Single"
      B: "BASIC-DOS Tests"
---

### Part 2: BASIC Operations

The machine below boots the `BASICDOS-360K-S80` diskette, with the `BASICDOS-360K-TESTS` diskette in drive B:.  Type `CD DEMOS` to change to its **DEMOS** directory, `DIR PRIMES.*` to list the PRIMES files there, and `B:\TOOLS\MSBASIC PRIMES` to run **PRIMES.BAS** with **MSBASIC**, which computes all the primes under 1000 on a 4.77Mhz IBM PC.

{% include machine.html id="ibm5150" %}

**PRIMES.BAS** was the first BASIC program written to run in both BASIC-DOS and **MSBASIC**, so run it with **MSBASIC** first.  After it prints:

    TOTAL PRIMES < 1000:  168

type `SYSTEM` to return to the BASIC-DOS prompt.

Next, type `PRIMES.BAS` to load and run the same program with BASIC-DOS.

Notice how much *faster* BASIC-DOS execution is, because BASIC-DOS compiles each program into 8086 code before running it.  And BASIC-DOS is performing full 32-bit integer operations (MSBASIC integer operations are only 16-bit).

PRIMES.BAS needs only integers, but BASIC-DOS also supports IEEE double-precision floating-point (with or without an 8087), strings, arrays, file I/O, graphics, and sound; see the [BASIC-DOS Manual](/docs/bdman/) for the full list of commands and functions, and [Part 6](../part6/) for benchmarks.

### Next: [Part 3: BASIC Files vs. Batch Files](../part3/)
