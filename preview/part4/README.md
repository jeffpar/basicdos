---
layout: page
title: Preview
permalink: /preview/part4/
machines:
  - id: ibm5150-2
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    autoMount:
      A: "BASICDOS-360K-D40"
  - id: ibm5150-3
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    autoMount:
      A: "BASICDOS-360K-D80"
    autoType: MEM -D\r
---

### Part 4: Pipes and Sessions

The two machines below each run two *foreground* sessions on the same screen.  The first boots the `BASICDOS-360K-D40` diskette, whose CONFIG.SYS defines two 40-column sessions side by side; use **SHIFT-TAB** to toggle keyboard focus between them, and notice how the border changes to indicate which session has focus (the second session runs `DIR | CASE` in a loop, which you can stop with CTRL-C).  The second boots the `BASICDOS-360K-D80` diskette, whose CONFIG.SYS defines two 80-column sessions, one above the other, and runs `MEM -D` to display memory usage.

{% include machine.html id="ibm5150-2" %}

{% include machine.html id="ibm5150-3" %}

In PC DOS, pipes require a writable disk with enough disk space to contain the entire pipe output; in other words, pipe operations are really just "faked" using temporary files.  BASIC-DOS doesn't need any disk space for pipes, thanks to two features that PC DOS never included:

 1. A PIPE driver
 2. Background sessions

For a command such as:

    TYPE PRIMES.BAS | CASE

the interpreter opens a `PIPE$` handle to create a FIFO queue and passes the handle as STDIN for a new background session running CASE.COM, a simple BASIC-DOS I/O filter program that upper-cases letters.

### What is a Session?

BASIC-DOS supports a tasking unit known as a "session".  Sessions represent separate execution environments, each of which can run a separate DOS program. Each program can open its own files, allocate its own memory, define its own signal handlers, etc, and BASIC-DOS smoothly multitasks between them.

BASIC-DOS maintains session state using internal structures called Session Control Blocks (SCBs).  These contain all per-session kernel state.  In DEBUG builds of BASIC-DOS, you can dump active SCBs using the `MEM -S` command (see `HELP MEM` for more options).

Sessions can run entirely in the *background*, or they can be assigned to specific regions of the screen, like the *foreground* sessions in the machines above.

### Next: [Part 5: Were Dual Monitors Ever This Cool?](../part5/)
