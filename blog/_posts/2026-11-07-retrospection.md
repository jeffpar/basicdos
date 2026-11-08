---
layout: post
title: Retrospection
date: 2026-11-07 11:00:00
permalink: /blog/2026/11/07/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    autoMount:
      A:
        name: "BASIC-DOS2 (2021)"
        path: "/software/disks/2021/BASIC-DOS2.json"
---

In 2021, my final BASIC-DOS [Preview](/preview/) highlighted an IBM PC running two DOS sessions side by side, each in its own 40-column half of a CGA screen.  That was May 2021, three months before the PC's 40th anniversary, at which point I had run out of steam.  The demo fit on a single-sided 160K diskette, the same kind that PC DOS 1.00 shipped on, and the machine was a 4.77Mhz IBM PC with 128K of memory and a Color Display.

The left session is running `DIR` in a loop (type CTRL-C to stop it), while the right session waits at a prompt.  Use **SHIFT-TAB** to move keyboard focus between them; the session with focus has the double-wide border.  In the right session, try `PRIMES.BAS`, or `TYPE PRIMES.BAS | CASE` to send the program through a pipe to the CASE filter, which upper-cases it, or type `HELP` to see every command that the 2021 version of BASIC-DOS understood.

For comparison, here is a [similar demo](/demos/d40/pc/) running the latest version of BASIC-DOS.

{% include machine.html id="ibm5150" %}

### What's Gone

The multitasking was real, and the device driver model and overall system architecture hasn't changed much, so the design has held up well.  Here are some of the major limitations of the 2021 preview, all of which are now gone:

 1. **The file system was read-only.**  Files could be read, but not created, written, renamed, or deleted, so COPY, DEL, REN, and SAVE couldn't modify anything.  There were no subdirectory functions either, and no hard disk support.  Today, BASIC-DOS creates, writes, renames, and deletes files, makes and removes subdirectories (with a current directory per drive *per session*), caches FAT and directory sectors, formats diskettes, and reads and writes FAT12 and FAT16 volumes on up to two hard disks, from which it can also boot.

 2. **BASIC commands were extremely limited.**  COMMAND.COM recognized about 30 keywords in 2021, and BASIC accounted for only LET, PRINT, IF, GOTO, DEF, and a few others.  There was no FOR/NEXT, no WHILE/WEND, no GOSUB, no arrays, no file I/O, no error handling, and no graphics or sound.  The DEFDBL and DEFSNG entries in HELP admit that there was no floating-point support either.  Now BASIC-DOS has all of those things, including 64-bit floating-point that uses an 8087 when one is installed, and it runs the PC DOS 1.00 BASIC samples, like DONKEY.BAS, drawing the same pixels that BASICA draws.

 3. **Batch files and BASIC were not unified.**  A batch file could contain BASIC statements, and BASIC programs were already compiled into 8086 code, but a batch file still couldn't get its arguments, test for a file, or recover from an error.  Today every BAT file is a BASIC program, with ARG$, EXISTS, and ON ERROR, and several of the DOS utilities (eg, FORMAT, CHKDSK, DISKCOPY, and MODE) are themselves written in BASIC.

 4. **There were very few utilities and filters.**  The 2021 diskette had DIR, TYPE, COPY (which could only copy to a device), DATE, TIME, MEM, and a few others, plus a CASE filter for testing pipes.  Now there are internal and external commands for everything a DOS user expects, along with filters (FIND, MORE, SORT, SED, TR, and more), output and input redirection, a VI editor, and a DEBUG that runs either as a program or as a kernel debugger on a serial port.

 5. **Most PC DOS programs didn't work.**  The 2021 preview called MSBASIC a "happy coincidence", because most PC DOS programs used interfaces that BASIC-DOS didn't implement, or had stacks that were too small, or both.  BASIC-DOS now implements the PC DOS 2.x file, FCB, and memory functions that programs actually use, along with critical error handling, so programs that stick to DOS interfaces generally just work.  The best proof of that is BASIC-DOS building itself, with the same MASM, LINK, and MAKE that build it on MS-DOS, and producing identical binaries.

 6. **Screen sessions had to be laid out by hand.**  The 2021 CONFIG.SYS (type `TYPE CONFIG.SYS` in either session to see it) had to give each console's exact screen position, and every session lasted until the system was restarted.  Today a CON= line names a driver and a size, and BASIC-DOS places the consoles itself, whether that's two halves of a screen, separate video pages, multiples monitors, or VT100 terminals on serial ports.  Sessions start and end as programs come and go, and KILL lists them and ends any one of them.

 7. **It was strictly a real-mode operating system.**  That was always the initial target, and BASIC-DOS still boots in a [64K machine](/demos/m64/pc/).  But on an 80286 or 80386, BASIC-DOS can now run in protected mode, using extended memory and running COMMAND.COM and its programs at ring 3, where a misbehaving program can't overwrite memory that isn't its own.

There are still a few items on the [Project Status](/#project-status) list, but compared to the machine above, that list is short.  The 2021 preview showed what BASIC-DOS *could* be, and I'm happy to report that it's now very close to being exactly that.
