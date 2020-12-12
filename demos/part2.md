---
layout: page
title: BASIC-DOS Preview
permalink: /maplebar/preview/part2/
machines:
  - id: ibm5150
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    sizeRAM: 128
    autoType: MSBASIC PRIMES\r
---

### BASIC Operations

At the moment, the set of available BASIC commands is *very* basic: CLS, COLOR,
DEF, GOTO, IF ... THEN, LET, and PRINT.  But those are enough to write some
simple programs.  Numeric support is limited to integer constants, variables,
and operators (no floating-point yet).  String variables can be created and
printed, but no string operations are available yet either.

**PRIMES.BAS** was the first BASIC program written to run in both BASIC-DOS and
**MSBASIC**.  It computes all primes under 1000.  Let's watch it run under
**MSBASIC** first.

{% include machine.html id="ibm5150" %}

After it prints:

    TOTAL PRIMES < 1000:  168

type `SYSTEM` to return to the BASIC-DOS prompt.

Next, type `PRIMES.BAS` to load and run the same program directly within
BASIC-DOS.

Notice how much *faster* BASIC-DOS execution is.  And BASIC-DOS is performing
full 32-bit integer operations -- twice the precision of MSBASIC integer
operations.

### Next: [BASIC Files vs. Batch Files](../part3/)
