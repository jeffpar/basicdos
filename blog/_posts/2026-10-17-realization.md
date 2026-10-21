---
layout: post
title: Realization
date: 2026-10-17 11:00:00
permalink: /blog/2026/10/17/
preview: /assets/images/BASIC-DOS-Cover.gif
---

The last post here was written in early 2021, a month after the first [Preview](/preview/) of BASIC-DOS.  That preview demonstrated the potential of BASIC-DOS, but it also demonstrated the limits of what one person, building an operating system one assembly-language instruction at a time, could realistically hope to finish.

Then AI agents like Claude Code arrived, and I discovered that one person with a virtual sidekick could actually finish this project.  The architecture described in [Inspiration](/blog/2020/05/17/) and [Perspiration](/blog/2020/12/12/) hasn't changed, and neither have the constraints: BASIC-DOS is still built with MASM 4.0, it still runs on a 4.77Mhz 8088, and it still fits in 64K.  But the gaping holes that remained after the preview have now been filled, so this post brings the state of the world up to date.

### A Unified Command Processor

COMMAND.COM was always intended to be a single, interactive DOS and BASIC command interpreter, and now it is one.  Every BASIC program is compiled into 8086 code before it runs, which is why PRIMES.BAS runs about 10 times faster in BASIC-DOS than in BASICA or GW-BASIC.  The [benchmarks](/preview/part6/) have the other results.

The BASIC-DOS language now supports 32-bit integers, strings, arrays, FOR/NEXT, WHILE/WEND, GOSUB, DATA and READ, sequential and random access files, ON ERROR, the SCREEN, PSET, LINE, CIRCLE, PAINT, DRAW, GET, and PUT graphics statements, PLAY and SOUND, and even MOUSE statements.  It runs DONKEY.BAS and the rest of the PC DOS 1.00 sample programs, drawing the same pixels that BASICA draws, and it loads the *tokenized* files that BASICA and GW-BASIC saved, converting them back to text on the way in.

Floating-point support was one of the more daunting gaps to fill, which is why my original plan was to port the floating-point code from Microsoft BASIC.  But that code was difficult to adapt, and it used MBF (Microsoft Binary Format), which isn't compatible with the IEEE 754 format of the 8087 math coprocessor, so it would have ruled out using an 8087.  So I decided to adopt the IEEE standard, use 64-bit doubles exclusively, and build a new FPU$ device driver that uses an 8087 when one is installed and emulates one in software otherwise.  BASICA and GW-BASIC can't use an 8087 at all, so on a machine with one, the floating-point benchmarks run 8 to 19 times faster in BASIC-DOS than in GW-BASIC.

Because BASIC-DOS batch files are BASIC programs, there's no separate batch language to learn.  There are no replaceable parameters, no SET, no IF EXIST, and no FOR ... IN ... DO, because ARG$, ordinary variables, the EXISTS function, and IF ... THEN ... ELSE already do those jobs.  Several commands can share a line (`DIR *.BAS : PRINT "done"`), and the output of an entire line, BASIC statements included, can be redirected with `:>`.

### Sessions and Pipes

Preemptive multitasking was the headline feature of the preview, and it still is.  Sessions can split a screen in half, or switch between video pages on a single screen, or take over two monitors, or run on a VT100 terminal attached to a serial port -- or all of the above.  New commands such as `LIST SESSIONS` and `RESTART` let you see and reset them.  Pipes still go through the PIPE$ driver instead of temporary files, so a pipeline's filters run *simultaneously* and the amount of piped data is unlimited.  BASIC-DOS now ships CASE, FIND, MORE, and SORT filters, pipelines can chain as many of them as you like, and `>` and `>>` redirect the output of any command or pipeline.

### The File System

The preview's file system was read-only.  Today, every handle-based and FCB-based function that BASIC-DOS needs is implemented: files are created, written, truncated, renamed, deleted, and shared according to rules that PC DOS didn't have until SHARE arrived in version 3.0.  Subdirectories work everywhere, with a current directory per drive *per session*, and RENAME (or MV) moves files and whole directories between directories on the same drive, which the PC DOS RENAME command never allowed.  There's a configurable cache of FAT and directory sectors (BUFFERS=), and instead of the INT 25h and INT 26h absolute disk interfaces, a volume can simply be opened as a file (eg, `C:`), even when it's unformatted.

Hard disks are supported, too.  BASIC-DOS reads and writes the FAT12 and FAT16 volumes of up to two PC XT or PC AT hard disks, and it boots from a hard disk partition as readily as from a diskette.  When a block device fails, the session's critical error handler is called with the same inputs that PC DOS provided, and the default handler asks the familiar question, including the *Fail* response that PC DOS didn't offer until version 3.3.  That handler is also the one place where BASIC-DOS switches stacks, as PC DOS did, because the program that triggered the error may not have much stack to spare.

### Device Drivers

The CON and COM drivers are still interrupt-driven and asynchronous, and installable drivers (DEVICE= in CONFIG.SYS) finally exist.  CLOCK$ reads the PC AT's real-time clock, SKIP= unloads any built-in driver you don't want, and the drivers for hardware that isn't present (serial and parallel ports, mice, hard disks) unload themselves, which is how BASIC-DOS still boots in a [64K machine](/demos/m64/pc/).

Two drivers deserve special mention.  MOUSE$ detects a Microsoft-compatible serial mouse at boot, draws a pointer in text and graphics modes, implements the core of the INT 33h interface, and feeds the BASIC MOUSE statements.  And DEBUG.COM is a dual-mode binary: run it as a program and it's a conventional debugger that can load and step through another program; load it with DEVICE= on a serial port and it becomes a *kernel* debugger, with an 8086 disassembler, breakpoints, single-stepping, and SYMDEB-style memory dumps, all available from a terminal while BASIC-DOS keeps running.

### System Utilities in BASIC

Given the built-in capabilities of BASIC, I decided that some of the utilities normally included with DOS could easily be written in BASIC.  So, on every BASIC-DOS disk, you will find a BIN directory of utilities, some of which are still written in assembly language (eg, the filters, SLEEP, VI, and DEBUG) while others are now written in BASIC.  FORMAT.BAS and MODE.BAS are the first ones, with CHKDSK, SYS, DISKCOPY, TREE, and others as likely candidates.

FORMAT formats and verifies diskettes (including single-sided and 8-sector formats, and /S to copy the system files), formats hard disk volumes, and when it finds a disk with no partition table at all, offers to create one, so there's no separate FDISK.  MODE sets display modes and colors, configures serial ports, and sets printer columns and line spacing.  Both are commented programs that anyone can LIST, learn from, and modify, and when a utility needed something the language didn't have, like `IOCTL #` to talk to a driver or the ability to open an unformatted volume, the interpreter grew to provide it.  The utility *is* its source code, which seems exactly right for an operating system named after a language.

VI, incidentally, is a subset of the UNIX editor, and it works on serial terminals (eg, a VT100) as well as on the PC's own display.

### Building BASIC-DOS

BASIC-DOS can now build itself.  The `mk.sh` script boots BASIC-DOS from a hard disk and runs MAKE, MASM 4.0, and LINK, producing binaries identical to the ones built on MS-DOS, and the [Dual Monitors](/demos/dual/xt/) demo does exactly that on its Color Display while PRIMES.BAT runs on the Monochrome Display.  That's as good a compatibility test as I could ask for: PC DOS programs that confine themselves to DOS APIs generally just work.

### Everything Else

There's an unattended test suite that boots BASIC-DOS with and without an 8087 and runs a dozen test programs.  There's a [BASIC-DOS Manual](/docs/bdman/) and a [Technical Reference](/docs/bdtech/), and HELP finds every command and function by searching HELP.TXT.  And the [Demos](/demos/) now run on an IBM PC, PC XT, PC AT, and COMPAQ DeskPro 386.

What's left?  Input redirection, file attributes and dates, a few BASIC features (the MID$ statement, comma print zones, RESUME NEXT), popup sessions, TSRs, and more utilities in BASIC.  The [Project Status](/#project-status) on the home page has the complete list.  But the project has crossed the line from a demonstration of what *could* have been to a system that actually does those things, which is a milestone I honestly wasn't sure I'd reach.  The [Preview](/preview/) pages have been updated accordingly, so if you haven't looked at BASIC-DOS in a while, now would be a good time.
