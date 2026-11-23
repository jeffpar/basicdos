The BASIC-DOS Dual Monitor diskette's **CONFIG.SYS** runs one full-screen console on each monitor: PRIMES.BAS on the Monochrome Display, and DONKEY.BAS (from the PC DOS 1.00 diskette) on the Color Display, which waits at its title screen for the space bar.

At first glance, it might appear there are two machines running, but it really is just a single machine running two BASIC-DOS consoles.  The Color Display's console starts with the keyboard focus, so press the space bar to start DONKEY, and again to move its car between lanes (or ESC to end it), and use **SHIFT-TAB** to toggle keyboard focus between the consoles.  Since these consoles don't use borders, the presence of a blinking cursor indicates which console has focus.

A **MEMSIZE** line in **CONFIG.SYS** (eg, **MEMSIZE=128**) can limit the total memory used by BASIC-DOS.  You might be tempted to think that **MEMSIZE** is a way to "partition" memory, so that each session has a dedicated amount, but no -- **MEMSIZE** is simply a means of testing BASIC-DOS with different memory sizes.  And in any case, partitioning memory would not be a good strategy.

### **CONFIG.SYS** from the BASIC-DOS Dual Monitor Diskette

```
{% include_relative CONFIG.SYS %}
```
