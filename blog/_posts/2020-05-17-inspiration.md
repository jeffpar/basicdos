---
layout: post
title: Inspiration
date: 2020-05-17 11:00:00
permalink: /blog/2020/05/17/
---

This is the "history" of the BASIC-DOS, the first version of DOS that *might*
have been created for the IBM PC.

In this alternate timeline, the year is 1980, and we know that in a little
over a year, on August 12, 1981, the IBM PC will be introduced, and we really
want to make the first PC operating system as compelling and powerful as
possible.

So, we have more time to prepare than Microsoft originally did, and we have
the benefit of hindsight (or foresight, since it's 1980).

For example, we know that higher capacity diskettes and hard disks will soon
become available, so maybe we can make some early design decisions about the
FAT file system that will smooth the way for those improvements.

We also know that people will be looking for ways to be as productive as
possible with their PCs, to maximize their investment.  Being able to run
programs in the background (like TSRs) sounds nice, but perhaps a machine with
a 16-bit processor and 20-bit address bus could also run several foreground
programs simultaneously, too.

And as we're designing the DOS command interpreter along with the BASIC
interpreter, it becomes clear that a "batch language" with support for
"environment variables" is remarkably similar to features that BASIC already
provides.  Perhaps a "unified" interpreter could eliminate the need for those
extra features, allow us to leverage the editing and debugging capabilities
of BASIC, and produce a tool more powerful than either interpreter by itself.

At the same time, perhaps we could find ways to make this unified interpreter
faster, with support for programs larger than 64K, and support for integers
larger than 16-bit -- to create programs that take *full* advantage of this new
processor, instead of perpetuating limitations found on other older platforms
(eg, 6502 and 8080-based systems).

And what should we call this operating system?  DOS-BASIC?  BASIC-DOS?

Let's see what [the future](/blog/2020/05/17/) holds.
