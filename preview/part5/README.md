---
layout: page
title: Preview
permalink: /preview/part5/
machines:
  - id: ibm5150-4
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-dual-256kb.json
    debugger: /demos/dual/debugger
    autoMount:
      A: "BASIC-DOS4"
      B: "PC DOS 2.00 (Disk 2)"
---

### Part 5: Were Dual Monitors Ever This Cool?

Foreground sessions are even more useful on Dual Monitor systems, like the
one below, because each session has exclusive access to an entire screen.

Use SHIFT-TAB to switch to the Color Display, press SPACE to start `DONKEY`,
and appreciate how well an IBM PC could actually run two programs simultaneously.

{% include machine.html id="ibm5150-4" %}

There's also a "[Dueling Monitors](../../demos/dual/multi/)" demo featuring
FOUR active sessions (two per monitor).  This may be pushing the IBM PC a bit
too far, but any session that's waiting for input has no impact on performance.

It's important to note that BASIC-DOS is *not* attempting to emulate a
"virtual machine" within each session.  That would require swapping global
memory (eg, ROM BIOS Data) on every context-switch, which would be error-prone
and slow.  And it's completely unnecessary, as long as BASIC-DOS apps rely
exclusively on BASIC-DOS APIs.  Realistically, ROM BIOS APIs and data should
only be used by BASIC-DOS itself (ie, BASIC-DOS device drivers).

Even though in selected demos I will sometimes run PC DOS applications like
**MSBASIC**, the fact that they work is a happy coincidence.  Most actually do
*not* work, either because they 1) use interfaces that BASIC-DOS has not yet
implemented (and may *never* implement), 2) use BIOS interfaces that only
BASIC-DOS should be using, or 3) have a stack so small that crashing is
inevitable.

The fact that **MSBASIC** works at all, despite the fact that it's "breaking
the rules" and accessing the BIOS and hardware directly, is just another happy
coincidence.  By no means is it working perfectly.  For example, if you type
CTRL-BREAK while the Monochrome Display has focus, **MSBASIC** will intercept
it, because it's relying on the BIOS rather than BASIC-DOS "hot key" notifications.

The "stack" issue is another major difference between BASIC-DOS and PC DOS.
BASIC-DOS *never* switches stacks within a session.  The BASIC-DOS philosophy
is simple: BASIC-DOS APIs should be re-entrant and apps should provide as much
stack space as their calls require.  PC DOS, by contrast, evolved complicated
stack switching procedures and re-entrancy rules that slowed the operating
system down, wasted memory, and were generally painful.

Let's just say that BASIC-DOS will never support a `STACKS` keyword in CONFIG.SYS.

That's the end of the current preview.  Enjoy the [Demos](/demos/).
