These machines have a serial mouse on COM2, which the MOUSE$ driver finds at boot.  They boot the BASICDOS-360K-S80 diskette and run **PAINT.BAS**, which switches the display to SCREEN 2 (640x200) and turns the mouse on with `MOUSE ON`.

The screen has a banner at the top and a status line at the bottom, and everything between the two lines is a black canvas.  Click the screen to capture the mouse, then hold the left button down to draw with white pixels.  The mouse's X,Y position is always displayed in the lower left corner.

To exit, press **Esc** once to release the mouse, and then press **Esc** again to end the program; BASIC-DOS restores the original display mode.  Type `PAINT` to run it again.

PAINT.BAS reads the current mouse position and buttons with `MOUSE(3)`, `MOUSE(4)`, and `MOUSE(5)`, and while the left button is down, it draws a line from the previous position to the current one, so that fast mouse movements leave no gaps.  It updates the position display only when the mouse moves.

### **PAINT.BAS** from the BASICDOS-360K-S80 Diskette

```
{% include_relative PAINT.BAS %}
```
