---
layout: page
title: BASIC-DOS Preview
permalink: /maplebar/preview/part4/
machines:
  - id: ibm5150-2
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    sizeRAM: 128
    autoMount:
      A: "BASIC-DOS2"
  - id: ibm5150-3
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    sizeRAM: 128
    autoMount:
      A: "BASIC-DOS3"
    autoType: MEM /S\r
---

### Pipes and Sessions

In PC DOS, pipes require a writable disk with enough disk space to contain the
entire pipe output; in other words, pipe operations are really just "faked"
using temporary files.  So you might wonder how BASIC-DOS can support pipes if
it the file system doesn't support write operations (yet).

Well, it can, thanks to two features that PC DOS never included:

 1. A PIPE driver
 2. Background sessions

For a command such as:

    TYPE PRIMES.BAS | CASE

the interpreter opens a `PIPE$` handle to create a FIFO queue and passes
the handle as STDIN for a new background session running CASE.COM, a simple
BASIC-DOS I/O filter program that upper-cases letters.

### What is a Session?

BASIC-DOS supports a tasking unit known as a "session".  Sessions represent
separate execution environments, each of which can run a separate DOS program.
Each program can open its own files, allocate its own memory, define its own
signal handlers, etc, and BASIC-DOS smoothly multitasks between them.

BASIC-DOS maintains session state using internal structures called Session
Control Blocks (SCBs).  These contain all per-session kernel state.  You can
dump active SCBs using the `MEM /S` command (see `HELP MEM` for more options).

Sessions can run entirely in the *background*, or they can be assigned to
specific regions of the screen.  The next two machines illustrate how this
works, using two side-by-side *foreground* sessions.

The CONFIG.SYS of the first machine has defined two 40-column foreground
sessions.  Use SHIFT-TAB to toggle keyboard focus between them.  Notice how
the border changes to indicate which session has focus.  Feel free to type
CTRL-C to kill the looping DIR command in the first session.

{% include machine.html id="ibm5150-2" %}

The CONFIG.SYS of the next machine has defined two 80-column foreground
sessions.

{% include machine.html id="ibm5150-3" %}

Next: [Were Dual Monitors Ever This Cool?](../part5/)