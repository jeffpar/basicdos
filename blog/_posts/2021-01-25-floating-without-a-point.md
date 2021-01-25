---
layout: post
title: Floating Without a Point
date: 2021-01-25 11:00:00
permalink: /blog/2021/01/25/
preview: /assets/images/Screenshot_2021-01-25.png
---

It's been a month since I rolled out the first preview of BASIC-DOS, and
apparently I needed a break, because I couldn't muster much energy to do more
development on the project... until now.

Part of the dilemma was deciding what to focus on next.  There's no shortage
of gaping holes left to fill in, such as:

- Tons of missing BASIC language functionality
- No file system support for creating, writing, renaming, or deleting files
- Session improvements, including support for popup sessions
- Hard error support

Within BASIC language support alone, there's a lot of work left to do.
Probably the most important features are:

- More "basic" commands (eg, INPUT, READ, DATA)
- String functions
- Floating-point support

Floating-point opens another can of worms, which is why I've already decided to
port most of that support from [Microsoft BASIC](https://github.com/microsoft/GW-BASIC),
and why there's already a complete (built and working) copy of
[GW-BASIC sources](https://github.com/jeffpar/basicdos/tree/master/software/pcx86/bdsrc/msb)
checked into the project.

To further reduce the scope of the work, I've decided to support only
double-precision (64-bit) floating-point numbers.  Single-precision is obviously
faster, but given the choice between greater speed and greater accuracy, the
latter is more appealing.

So to that end, I've started working on the necessary parsing changes, which
will then be followed by changes to the expression generator.

Floating-point constants need to be differentiated from integers, and by
pressing a special key ('t') at boot, you can enable "token" messages, which
show that the BASIC-DOS parser now identifies numbers with decimal points as
a new token class.  It's a trivial change, and just the first of many (probably
hundreds) of steps to fully support floating-point operations.

I would love to work on multiple features simultaneously, but I'm a lousy
multitasker, and I have to choose something, so I choose floating-point.

![Screenshot](/assets/images/Screenshot_2021-01-25.png)
