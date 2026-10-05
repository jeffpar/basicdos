---
layout: page
title: Preview
permalink: /preview/part7/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-256kb.json
    autoMount:
      A: "BASIC-DOS6"
---

### Part 7: Performance

How does BASIC-DOS compare with the BASIC interpreters that IBM PC users actually had?  To find out, we wrote a set of benchmarks, [BENCH.BAS]({{ site.github.repository_url }}/blob/master/software/pcx86/src/tests/misc/BENCH.BAS), that runs unchanged in all three environments:

  - **BASICA**: IBM Advanced BASIC A2.00 from PC DOS 2.00, running with the IBM PC's ROM BASIC
  - **GW-BASIC**: **MSBASIC.EXE**, built from Microsoft's open-source [GW-BASIC](https://github.com/microsoft/GW-BASIC) files, also running on PC DOS 2.00
  - **BASIC-DOS**: BASIC-DOS's own COMMAND.COM, which compiles each BASIC program into 8086 code before running it

Each test was run on a 4.77Mhz IBM PC XT with a Color Graphics Adapter, both without and with an 8087 math coprocessor, and timed by BENCH.BAS itself, using the BIOS timer tick count.  The BASIC-DOS results are from a release (non-DEBUG) build.  Times are in seconds (smaller is better), and the fastest time for each test is in bold.

| Test | BASICA | BASICA<br>w/8087 | GW-BASIC | GW-BASIC<br>w/8087 | BASIC-DOS | BASIC-DOS<br>w/8087 |
|---|--:|--:|--:|--:|--:|--:|
| Integer math | 30.1 | 30.1 | 27.3 | 27.3 | **5.0** | **5.0** |
| Floating-point math (64-bit) | 42.0 | 42.0 | 14.0 | 14.0 | 10.6 | **1.7** |
| Math functions | 11.8 | 11.8 | 9.7 | 9.7 | 16.0 | **0.5** |
| String functions | 7.4 | 7.4 | 6.5 | 6.5 | 2.9 | **2.7** |
| Arrays and subroutines | 3.5 | 3.5 | 3.1 | 3.1 | 1.2 | **0.7** |
| Primes | 78.9 | 78.9 | 73.6 | 73.6 | **6.9** | **6.9** |
| Screen output | 7.6 | 7.6 | 8.5 | 8.5 | **3.6** | **3.6** |
| Graphics: PSET | 19.9 | 19.9 | 17.5 | 17.5 | **3.7** | **3.7** |
| Graphics: LINE | 4.2 | 4.2 | 5.7 | 5.7 | **1.1** | **1.1** |
| CIRCLE.BAS | 9.1 | 9.1 | 8.4 | 8.4 | 5.6 | **5.3** |

### The Tests

  - **Integer math**: 5,000 iterations of integer multiplication, division, MOD, and AND
  - **Floating-point math**: 2,000 iterations of double-precision multiplication, division, addition, and subtraction
  - **Math functions**: 200 iterations of SQR, SIN, COS, ATN, LOG, and EXP
  - **String functions**: 500 iterations of STR$, LEFT$, MID$, RIGHT$, LEN, ASC, INSTR, and string concatenation
  - **Arrays and subroutines**: filling a 500-element array, and then summing it with 500 GOSUBs
  - **Primes**: counting the primes below 3000 by trial division
  - **Screen output**: printing 100 lines of text
  - **Graphics: PSET**: plotting 5,440 points in 320x200 graphics mode
  - **Graphics: LINE**: drawing 130 lines
  - **CIRCLE.BAS**: one pass of the drawing loop from **CIRCLE.BAS**, the PC DOS 1.00 sample program: 48 arcs, followed by a PAINT of the center, using the original (single-precision) code

### The Results

For programs that do most of their work with integers, which includes most games, utilities, and of course PRIMES, BASIC-DOS is typically 5 to 11 times faster than BASICA and GW-BASIC.

BASICA and GW-BASIC are also unable to use an 8087, because internally, they use a floating-point format known as MBF (Microsoft Binary Format).  BASIC-DOS performs all floating-point operations using IEEE 64-bit precision, automatically using an 8087 when one is installed and software emulation otherwise.

### Try It Yourself

The machine below boots the `BASIC-DOS6` diskette, which includes BENCH.BAS. Type `BENCH` to run the benchmarks with BASIC-DOS, or `MSBASIC BENCH` to run them with GW-BASIC (type `SYSTEM` to return to BASIC-DOS afterward).  The full set of tests takes a few minutes, and each result is displayed as it completes.

{% include machine.html id="ibm5150" %}

That's the end of the current preview.  All the demos featured in the preview are also available in our set of [Demo Configurations](/demos/).
