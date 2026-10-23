---
layout: page
title: Preview
permalink: /preview/part5/
machines:
  - id: ibm5150-4
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-dual-640kb.json
    debugger: /demos/dual/xt/debugger
    autoMount:
      A: "BASICDOS-360K-DUAL"
---

### Part 5: Were Dual Monitors Ever This Cool?

The machine below is an IBM PC XT with 640K of memory and two monitors: a Monochrome Display and a Color Display.  It boots the `BASICDOS-360K-DUAL` diskette, but since the machine also has the BASIC-DOS hard disk (drive C:), the boot sector first displays `Press a key to start...` on the Monochrome Display; press any key to boot from the diskette.  BASIC-DOS then runs one session on each monitor: **PRIMES.BAS** on the Monochrome Display, while the Color Display switches to the hard disk's **SRC** directory and runs **MK** to build BASIC-DOS itself, with MAKE, MASM, and LINK.  Use SHIFT-TAB to switch focus between the two displays, and appreciate how well an IBM PC could actually run two programs simultaneously.

{% include machine.html id="ibm5150-4" %}

Foreground sessions are even more useful on Dual Monitor systems, like the one above, because each session has exclusive access to an entire screen.

There's also a "[Dueling Monitors](../../demos/dual/multi/xt/)" demo featuring FOUR active sessions (two per monitor).  This may be pushing the IBM PC a bit too far, but any session that's waiting for input has no impact on performance.

It's important to note that BASIC-DOS is *not* attempting to emulate a "virtual machine" within each session.  That would require swapping global memory (eg, ROM BIOS Data) on every context-switch, which would be error-prone and slow.  And it's completely unnecessary, as long as BASIC-DOS apps rely exclusively on BASIC-DOS APIs.  Realistically, ROM BIOS APIs and data should only be used by BASIC-DOS itself (ie, BASIC-DOS device drivers).

PC DOS applications that rely on DOS APIs, like the MASM, LINK, and MAKE tools building BASIC-DOS above, generally work.  Those that don't usually 1) use interfaces that BASIC-DOS has not implemented (and may *never* implement), 2) use BIOS interfaces that only BASIC-DOS should be using, or 3) have a stack so small that crashing is inevitable.

The fact that **MSBASIC** works, despite the fact that it's "breaking the rules" and accessing the BIOS and hardware directly, is a happy coincidence.  By no means is it working perfectly.  For example, if you type CTRL-BREAK while the Monochrome Display has focus, **MSBASIC** will intercept it, because it's relying on the BIOS rather than BASIC-DOS "hot key" notifications.

The "stack" issue is another major difference between BASIC-DOS and PC DOS. BASIC-DOS APIs *never* switch stacks.  The BASIC-DOS philosophy is simple: BASIC-DOS APIs should be re-entrant and apps should provide as much stack space as their calls require.  (The one exception is the critical error handler, which is called on a DOS stack, as in PC DOS, since the program that triggered the error may have little stack to spare.)  PC DOS, by contrast, evolved complicated stack switching procedures and re-entrancy rules that slowed the operating system down, wasted memory, and were generally painful.

Let's just say that BASIC-DOS will never support a `STACKS` keyword in CONFIG.SYS.

### Next: [Part 6: Performance](../part6/)
