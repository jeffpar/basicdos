---
layout: sheet
title: BASIC-DOS Graphics Commands
permalink: /docs/bdman/cmd/device/graphics/
---

{% include header.html %}

Graphics commands include:

- [CIRCLE](#circle)
- [DRAW](#draw)
- [GET](#get)
- [LINE](#line)
- [PAINT](#paint)
- [PRESET](#preset)
- [PSET](#pset)
- [PUT](#put)

Graphics commands require a color adapter in a graphics mode (see [SCREEN](../screen/#screen)).  Coordinates are pixels, where (0,0) is the top left corner, *x* increases to the right (0-319 in SCREEN 1, 0-639 in SCREEN 2), and *y* increases downward (0-199).  Points outside the screen are clipped.

Colors are 0-3 in SCREEN 1 (0 is the background color, and 1-3 come from the current palette; see [COLOR](../screen/#color)), and 0-1 in SCREEN 2.  When a color is omitted, the foreground color (3 in SCREEN 1, 1 in SCREEN 2) is used.

BASIC-DOS draws the same pixels as Microsoft BASIC.  These features aren't supported yet: STEP (relative) coordinates, the POINT function, DRAW's A, TA, X, and "=variable" commands, and GET/PUT with floating-point arrays.

	SCREEN 1
	LINE (0,0)-(319,199),3,B
	CIRCLE (160,100),60,1
	PAINT (160,100),2,1

### CIRCLE

> CIRCLE (*x*,*y*),*r*[,[*color*][,[*start*][,[*end*][,*aspect*]]]]

Draws a circle (or ellipse) with radius *r*, or an arc from the *start* angle to the *end* angle (in radians, from 0 to 2*pi), with lines to the center for negative angles.  If *aspect* (the ratio of the y radius to the x radius) is omitted, the circle looks round on a standard display.

### DRAW

> DRAW *string*

Draws lines from the last point, using these commands:

- U, D, L, R [*n*]: move up, down, left, or right *n* points (default 1)
- E, F, G, H [*n*]: move diagonally up and right, down and right, down and left, or up and left
- M *x*,*y*: move to *x*,*y* (or relative to the last point, if *x* begins with + or -)
- B: prefix; move without drawing
- N: prefix; draw without moving
- C *n*: set the color
- S *n*: set the scale, in quarters (eg, S8 doubles all distances); the default is 4

Example:

	DRAW "C1 U20 R20 D20 L20 BM+30,0 E10 F10 L20"

### GET

> GET (*x1*,*y1*)-(*x2*,*y2*),*array*

Stores the pixels of the specified rectangle in an integer *array* (eg, `DIM A%(100)`), so that they can be drawn later with [PUT](#put).  The image format is the same as Microsoft BASIC's: two 16-bit words containing the width (in bits) and height, followed by the pixel rows, packed into bytes, with each row starting on a byte boundary.  Each array element holds one 16-bit word.

### LINE

> LINE [(*x1*,*y1*)]-(*x2*,*y2*)[,[*color*][,B|BF]]

Draws a line from (*x1*,*y1*) to (*x2*,*y2*), or with B, a box with those corners, or with BF, a filled box.  If the first point is omitted, the last point drawn is used.

### PAINT

> PAINT (*x*,*y*)[,[*paint*][,*border*]]

Fills the area around (*x*,*y*) with the *paint* color, up to the *border* color (which defaults to the *paint* color).  Like Microsoft BASIC, PAINT also fills through pixels that already have the paint color.

### PRESET

> PRESET (*x*,*y*)[,*color*]

Same as PSET, except that the default color is the background color (0).

### PSET

> PSET (*x*,*y*)[,*color*]

Draws a point, using the foreground color if no *color* is specified.

### PUT

> PUT (*x*,*y*),*array*[,PSET|PRESET|XOR|OR|AND]

Draws an image stored by [GET](#get) with its top left corner at (*x*,*y*), combining it with the screen using XOR, unless another action is specified:

- PSET: draws the image as-is
- PRESET: draws the inverse of the image
- XOR: inverts the screen wherever the image has pixels set (so a second PUT restores the screen)
- OR: adds the image to the screen
- AND: keeps only the screen pixels that the image also has set

{% include footer.html prev="Screen Commands:../screen/" next="Sound Commands:../sound/" %}
