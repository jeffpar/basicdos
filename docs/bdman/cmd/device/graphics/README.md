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
- [PMAP](#pmap)
- [POINT](#point)
- [PRESET](#preset)
- [PSET](#pset)
- [PUT](#put)
- [VIEW](#view)
- [WINDOW](#window)

Graphics commands require a color adapter in a graphics mode (see [SCREEN](../screen/#screen)).  Coordinates are pixels, where (0,0) is the top left corner, *x* increases to the right (0-319 in SCREEN 1, 0-639 in SCREEN 2), and *y* increases downward (0-199).  Points outside the screen (or the viewport that [VIEW](#view) defines) are clipped, and coordinates that aren't integers are rounded.  [WINDOW](#window) can define world coordinates instead.

Any point (*x*,*y*) can be STEP (*x*,*y*) instead, which is relative to the last point referenced.  As in Microsoft BASIC, every point that a command uses becomes the last point referenced, so the second point of LINE or GET can be relative to the first (eg, `LINE (10,10)-STEP(20,0)`), and a PSET, CIRCLE, PAINT, or PUT point becomes the starting point of the next DRAW.

Colors are 0-3 in SCREEN 1 (0 is the background color, and 1-3 come from the current palette; see [COLOR](../screen/#color)), and 0-1 in SCREEN 2.  When a color is omitted, the foreground color (3 in SCREEN 1, 1 in SCREEN 2) is used.

BASIC-DOS draws the same pixels as Microsoft BASIC.  PCOPY isn't supported yet.

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
- M *x*,*y*: move to *x*,*y* (or relative to the last point, if *x* begins with + or -); like other points, *x*,*y* is relative to the viewport, if any (see [VIEW](#view)), but DRAW doesn't use world coordinates (see [WINDOW](#window))
- B: prefix; move without drawing
- N: prefix; draw without moving
- C *n*: set the color
- S *n*: set the scale, in quarters (eg, S8 doubles all distances); the default is 4
- A *n*: set the angle to *n* (0-3) 90-degree turns, counterclockwise
- TA *n*: set the angle to *n* degrees (-360 to 360), counterclockwise
- P *paint*,*border*: paint the area around the last point (see [PAINT](#paint))
- X*variable*; : draw the commands in a string variable (eg, `DRAW "XBOX$;"`)

Any number can also be given as =*variable*; to use the value of a numeric variable (eg, `DRAW "M=X;,=Y;"`), and commands can be separated by semicolons.  Every relative move (all of them except an M without a sign) is rotated by the angle, and its distances are adjusted for the shape of the pixels, so a rotated figure keeps its shape; like Microsoft BASIC, A uses integer arithmetic, so rotations by multiples of 90 degrees draw the same pixels.  The color, scale, and angle remain in effect for later DRAW commands.

Example:

	DRAW "C1 U20 R20 D20 L20 BM+30,0 E10 F10 L20"

### GET

> GET (*x1*,*y1*)-(*x2*,*y2*),*array*

Stores the pixels of the specified rectangle in an integer or double *array* (eg, `DIM A%(100)`), so that they can be drawn later with [PUT](#put).  (`GET #n` reads a record of a random access file; see [GET #](../../basic/#get).)  The image format is the same as Microsoft BASIC's: two 16-bit words containing the width (in bits) and height, followed by the pixel rows, packed into bytes, with each row starting on a byte boundary.  Each element of an integer array holds one 16-bit word (so it has the same value as in Microsoft BASIC), and each element of a double array holds 8 bytes of the image, as Microsoft BASIC's single-precision arrays hold 4 (so an array dimensioned for Microsoft BASIC is large enough).

### LINE

> LINE [(*x1*,*y1*)]-(*x2*,*y2*)[,[*color*][,B|BF]]

Draws a line from (*x1*,*y1*) to (*x2*,*y2*), or with B, a box with those corners, or with BF, a filled box.  If the first point is omitted, the last point drawn is used.

### PAINT

> PAINT (*x*,*y*)[,[*paint*][,[*border*][,*background*]]]

Fills the area around (*x*,*y*) with the *paint* color, up to the *border* color (which defaults to the *paint* color).  Like Microsoft BASIC, PAINT also fills through pixels that already have the paint color.

*paint* can also be a tile string of 1 to 64 bytes, which fills the area with a pattern: each byte is a row of the pattern (4 pixels of 2 bits each in SCREEN 1, or 8 pixels of 1 bit each in SCREEN 2), and the rows repeat down the screen (row *y* uses byte *y* MOD the length), aligned with the screen's bytes, so adjacent fills with the same tile line up.  The default *border* is then the foreground color.  PAINT stops filling where a row already matches its tile byte, except for rows whose byte is *background* (a string whose first byte is used; the default is CHR$(0)), since an unpainted area matches that byte, too; a tile with more than two consecutive *background* bytes is an "Illegal function call".

	SCREEN 1
	CIRCLE (160,100),80,3
	PAINT (160,100),CHR$(&H1B)+CHR$(&HE4),3

### PMAP

> PMAP(*v*,*n*)

Maps a world coordinate (see [WINDOW](#window)) to a physical coordinate, or vice versa:

- *n* = 0: maps the world x coordinate *v* to a physical x coordinate
- *n* = 1: maps the world y coordinate *v* to a physical y coordinate
- *n* = 2: maps the physical x coordinate *v* to a world x coordinate
- *n* = 3: maps the physical y coordinate *v* to a world y coordinate

Physical coordinates are relative to the viewport, unless it was defined with VIEW SCREEN (see [VIEW](#view)).  Without WINDOW, PMAP returns *v*.

### POINT

> POINT(*x*,*y*) or POINT(*n*)

Returns the color of the pixel at (*x*,*y*), or -1 if it's off the screen (or outside the viewport).  POINT(*n*) returns the physical x (*n* = 0) or y (*n* = 1) coordinate of the last point referenced (eg, by PSET or DRAW), or its world x (*n* = 2) or y (*n* = 3) coordinate (see [WINDOW](#window)), rounded to an integer; without WINDOW, POINT(2) and POINT(3) are the same as POINT(0) and POINT(1).  POINT doesn't change the last point.

### PRESET

> PRESET (*x*,*y*)[,*color*]

Same as PSET, except that the default color is the background color (0).

### PSET

> PSET (*x*,*y*)[,*color*]

Draws a point, using the foreground color if no *color* is specified.

### PUT

> PUT (*x*,*y*),*array*[,PSET|PRESET|XOR|OR|AND]

Draws an image stored by [GET](#get) (`PUT #n` writes a record of a random access file; see [PUT #](../../basic/#put)) with its top left corner at (*x*,*y*), combining it with the screen using XOR, unless another action is specified:

- PSET: draws the image as-is
- PRESET: draws the inverse of the image
- XOR: inverts the screen wherever the image has pixels set (so a second PUT restores the screen)
- OR: adds the image to the screen
- AND: keeps only the screen pixels that the image also has set

### VIEW

> VIEW [[SCREEN] (*x1*,*y1*)-(*x2*,*y2*)[,[*fill*][,*border*]]]

Defines a viewport, a rectangle of the screen that all drawing is clipped to, after filling it with the *fill* color and drawing a box around it with the *border* color (if there's room), if those colors are specified.  Points are relative to the top left corner of the viewport, unless SCREEN is specified, in which case they're still relative to the screen.  The corners must be on the screen.  VIEW alone makes the whole screen the viewport again.  The viewport also ends when the program ends or SCREEN changes the mode.

	SCREEN 1
	VIEW (60,40)-(259,159),1,3
	CIRCLE (100,60),80,2

### WINDOW

> WINDOW [[SCREEN] (*x1*,*y1*)-(*x2*,*y2*)]

Defines the world coordinates of the viewport (or the screen), which all graphics commands (except DRAW) use instead of pixels.  The smaller *x* is at the left edge and the larger *x* at the right edge; the smaller *y* is at the bottom and the larger *y* at the top (as in mathematics), unless SCREEN is specified, in which case the smaller *y* is at the top.  STEP points are relative to the last point's world coordinates.  WINDOW requires floating-point (see [MEM](../../system/#mem)), and *x1* and *x2* (or *y1* and *y2*) can't be equal.  WINDOW alone ends world coordinates, which also end when the program ends or SCREEN changes the mode.  See also [PMAP](#pmap).

	SCREEN 2
	WINDOW (-3.2,-1.2)-(3.2,1.2)
	LINE (-3.2,0)-(3.2,0)
	PSET (-3.2,SIN(-3.2))
	FOR X = -3.2 TO 3.2 STEP .05 : LINE -(X,SIN(X)) : NEXT

{% include footer.html prev="Screen Commands:../screen/" next="Sound Commands:../sound/" %}
