---
layout: page
title: BASIC-DOS Demos
permalink: /maplebar/
machines:
  - id: ibm5150
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    debugger: available
---

{% include machine.html id="ibm5150" %}

There are currently four BASIC-DOS demo configurations:

 1. [Single (boring) session](?autoStart=true)
 2. [Two wide 80-column sessions](?autoMount={A:{name:"BASIC-DOS2"}})
 3. [Two skinny 40-column sessions](?autoMount={A:{name:"BASIC-DOS3"}})
 4. [Dual monitors](dual/) with independent full-screen sessions

The wide and skinny demos are configured with borders.  A double-wide border
indicates which session has keyboard focus.  Use **SHIFT-TAB** to toggle focus.

BASIC-DOS development was performed on this [PC XT Development Machine](dev/).
There's also a [blog](blog/), but I haven't been keeping it up-to-date with
development.
