The BASICDOS-360K-DUAL diskette's **CONFIG.SYS** runs one full-screen session on each monitor: PRIMES.BAT on the Monochrome Display, and on the Color Display, a build of BASIC-DOS itself (with MAKE, MASM, and LINK) from the hard disk's SRC directory.  If there's no hard disk (eg, on an IBM PC), the Color Display session runs PIPES.BAT instead, which pipes the output of DIR through the CASE filter over and over.

At first glance, it might appear there are two machines running, but it really is just a single machine running two BASIC-DOS sessions.  Use **SHIFT-TAB** to toggle keyboard focus between them.  Since these sessions don't use borders, the presence of a blinking cursor indicates which session has focus.

A **MEMSIZE** line in **CONFIG.SYS** (eg, **MEMSIZE=128**) can limit the total memory used by BASIC-DOS.  You might be tempted to think that **MEMSIZE** is a way to "partition" memory, so that each session has a dedicated amount, but no -- **MEMSIZE** is simply a means of testing BASIC-DOS with different memory sizes.  And in any case, partitioning memory would not be a good strategy.

### **CONFIG.SYS** from the BASICDOS-360K-DUAL Diskette

```
{% include_relative CONFIG.SYS %}
```
