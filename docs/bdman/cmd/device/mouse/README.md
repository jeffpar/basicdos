---
layout: sheet
title: BASIC-DOS Mouse Commands
permalink: /docs/bdman/cmd/device/mouse/
---

{% include header.html %}

Mouse commands include:

- [MOUSE](#mouse)

along with the [MOUSE](#mouse-function) function, which returns mouse events, the mouse position, and the mouse buttons.

BASIC-DOS supports a Microsoft-compatible serial mouse on any COM port.  At boot, the MOUSE$ driver looks for a mouse on each COM port, and if none responds, the driver isn't loaded (and uses no memory).  The mouse pointer is drawn in MDA and CGA modes only: in text modes, it inverts the colors of a character cell, and in graphics modes (SCREEN 1 and 2), it's a small arrow.

### MOUSE

> MOUSE ON|OFF

MOUSE ON resets the mouse, discards any pending events, and displays the mouse pointer (in the center of the screen).  MOUSE OFF resets the mouse and hides the pointer.  Like MSBASIC's PEN ON, MOUSE ON does nothing if there's no mouse, and the MOUSE function then returns only zeros.

When a BAS program ends, the mouse is turned off if it was turned on.  SCREEN and WIDTH keep the pointer displayed (in the new mode).

So that graphics statements (eg, GET and PAINT) never see the pointer, it's hidden whenever one runs, and it stays hidden until the next MOUSE function, so a program that draws in a loop should use the MOUSE function in that loop, too (as [MBROT.BAS](/demos/mbrot/) does).  Text that's printed or scrolled over the pointer is preserved when the pointer moves.

### MOUSE Function {#mouse-function}

> MOUSE(*n*)

Like MSBASIC's PEN function, *n* (0-5) selects the value to return:

| *n* | Value |
|-----|-------|
| 0 | The next button event: 0 if none, 1 = left button pressed, 2 = left button released, 3 = right button pressed, or 4 = right button released |
| 1 | The x position of the event last returned by MOUSE(0) |
| 2 | The y position of the event last returned by MOUSE(0) |
| 3 | The current x position |
| 4 | The current y position |
| 5 | The current buttons: 1 = left, 2 = right, 3 = both |

Positions are pixels in graphics modes (eg, 0-319 and 0-199 in SCREEN 1), or a column and row (starting at 1, like LOCATE) in text modes.  Up to 8 button events are saved until they're read.  For example, this program draws a point wherever the left button is pressed, and ends when the right button is pressed:

	SCREEN 1:MOUSE ON
	10 E = MOUSE(0)
	IF E = 1 THEN PSET (MOUSE(1),MOUSE(2))
	IF E <> 3 THEN GOTO 10

{% include footer.html prev="Keyboard Commands:../keyboard/" next="Screen Commands:../screen/" %}
