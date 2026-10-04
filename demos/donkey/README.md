---
layout: page
title: BASIC-DOS with DONKEY.BAS
permalink: /demos/donkey/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-256kb.json
    autoMount:
      A: "BASIC-DOS6"
      B: "PC DOS 1.00"
---

The machine below boots the BASIC-DOS6 diskette, which contains text copies
of DONKEY.BAS and the other BASIC samples from the IBM PC DOS 1.00 diskette
(whose copies, in drive B:, are in the tokenized format that only IBM BASIC
can load).  To try it, type:

    DONKEY

or CIRCLE, or the name of any other sample.  Not all of them run yet.

Press the space bar to switch lanes, and ESC to exit.  See the DONKEY.BAS
checklist in the [Project Status](/#donkeybas) for what was needed to run it,
and what remains (eg, performance).

{% include machine.html id="ibm5150" %}

### **DONKEY.BAS** from the BASIC-DOS6 Diskette

```
{% include_relative DONKEY.BAS %}
```
