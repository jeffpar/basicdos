---
layout: page
title: Preview
permalink: /preview/part2/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    autoType: CD TESTS\rDIR PRIMES.*\rMSBASIC PRIMES\r
---

### Part 2: BASIC Operations

The machine below boots the `BASICDOS-DISK1` diskette, changes to its **TESTS** directory, lists the PRIMES files there, and then runs **PRIMES.BAS** with **MSBASIC**, which computes all the primes under 1000 on a 4.77Mhz IBM PC.

{% include machine.html id="ibm5150" %}

At the moment, the set of available BASIC commands is *very* basic: CLS, COLOR, DEF, GOTO, IF ... THEN, LET, and PRINT.  But those are enough to write some simple programs.  Numeric support is limited to integer constants, variables, and operators (no floating-point yet).  String variables can be created and printed, but no string operations are available yet either.

**PRIMES.BAS** was the first BASIC program written to run in both BASIC-DOS and **MSBASIC**, so the machine above runs it with **MSBASIC** first.  After it prints:

    TOTAL PRIMES < 1000:  168

type `SYSTEM` to return to the BASIC-DOS prompt.

Next, type `PRIMES.BAS` to load and run the same program with BASIC-DOS.

Notice how much *faster* BASIC-DOS execution is.  And BASIC-DOS is performing full 32-bit integer operations (MSBASIC integer operations are only 16-bit).

### Next: [Part 3: BASIC Files vs. Batch Files](../part3/)
