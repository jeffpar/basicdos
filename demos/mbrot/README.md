---
layout: page
title: BASIC-DOS Drawing the Mandelbrot Set
permalink: /demos/mbrot/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-256kb.json
    autoMount:
      A: "BASICDOS-DISK6"
      B: "PC DOS 1.00"
    autoType: MBROT\r
---

The machine below boots the BASICDOS-DISK6 diskette and runs **MBROT.BAS**, which switches the display to SCREEN 2 (640x200), and then calculates and draws the classic image of the Mandelbrot set.  Points inside the set are drawn solid, and points just outside it are drawn in alternating bands, based on how many iterations each point takes to escape, leaving the rest of the screen black.

Calculating the image in full detail (64,000 points, since the bottom half mirrors the top) takes over 250,000 iterations (about 10 minutes on a 4.77MHz IBM PC), so by default, MBROT.BAS calculates only every other pixel in each direction and draws each result as a 2x2 block, which is four times faster.  You can choose a different block size with an argument:

    MBROT 1

draws the image in full detail, and `MBROT 4` draws a coarser image in well under a minute.

The original IBM PC had no floating-point hardware (unless you added an 8087), so MBROT.BAS does all its math with 32-bit integers instead, treating them as fixed-point numbers with 12 fraction bits (so 4096 represents 1.0), and it uses the BASIC-DOS `>>` operator to rescale each product.  It also skips the points inside the two largest regions of the set (the main cardioid and the circle to its left), which would otherwise take the most time, and since the image is symmetric, it draws each row and its mirror image at the same time.

If the machine has a mouse (like the [hard disk demo](/demos/hd/)), MBROT.BAS turns it on with `MOUSE ON`, so you can move the mouse pointer around while the image is drawn, and whenever you click a mouse button, the pointer's X,Y position is displayed in the lower left corner.

When the image is complete, press **ESC** to exit (you can also press ESC between rows to stop early), and BASIC-DOS will restore the original display mode.  Type `MBROT` to run it again (or `MBROT 1` or `MBROT 4`).

{% include machine.html id="ibm5150" %}

### **MBROT.BAS** from the BASICDOS-DISK6 Diskette

```
{% include_relative MBROT.BAS %}
```
