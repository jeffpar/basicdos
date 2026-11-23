---
layout: sheet
title: MODE
permalink: /docs/bdman/cmd/external/mode/
---

{% include header.html %}

> MODE 40\|80\|132\|BW40\|BW80\|CO40\|CO80[,*rows*]  
> MODE COM*n*:*baud*[,*parity*[,*data*[,*stop*]]]  
> MODE LPT*n*:[*cols*][,*lines*]

Sets the display, a serial port, or a printer.  Any other argument, or none at all, is a [usage error](../../#usage-errors).

### Display

Sets the display to 40 or 80 columns.  BW turns color off, as `SCREEN 0,0` does, and CO turns it on.  `MODE 132` selects 132 columns, which only a console on a VT100 terminal has (with 24 rows if the terminal has the Advanced Video Option, or 14 rows if not).  The display is always cleared, with the default colors (white on black), even if its mode doesn't change (eg, `MODE CO80` on a display that's already in 80-column color mode), whereas SCREEN and WIDTH do nothing then.

In a console that shares the screen with others (eg, one of two 40-column consoles side by side), `MODE 40` (or `BW40` or `CO40`) leaves the other consoles alone: the console is cleared and loses its border, so programs can use all of its columns and rows.  [CLS](../../device/screen/#cls) at the prompt restores the border.

*rows* is the number of rows, which depends on the display adapter:

| Adapter | Columns | Rows |
|---|---|---|
| MDA | 80 | 25 |
| CGA | 40 or 80 | 25 |
| EGA | 40 or 80 | 25 or 43 |
| VGA | 40 or 80 | 25, 43, or 50 |
| VT100 terminal | 40, 80, or 132 | 24 (14 with 132 columns and no Advanced Video Option) |

For example, `MODE CO80,43` selects 80 columns and 43 rows, and `MODE 80,25` returns to 25 rows.  Without *rows*, the rows change only if the columns or color do (to 25).  Any other number of rows is a [usage error](../../#usage-errors), and a combination that the adapter doesn't support (eg, `MODE 80,50` on an EGA, or `MODE 40` on an MDA) displays `Illegal function call`.  See [WIDTH](../../device/screen/#width), which MODE uses, for details.

### Serial Ports

Sets a serial port's parameters:

- *baud* is the baud rate; two digits abbreviate a rate (eg, 96 for 9600, or 11 for 110)
- *parity* is N, O, or E; the default is N
- *data* is the number of data bits; the default is 8
- *stop* is the number of stop bits; the default is 1

For example, `MODE COM1:96` is the same as `MODE COM1:9600,N,8,1`.

A serial port is set by opening it with its parameters and an input buffer length of 0 (see [COM](../../../cfg/#con)), which initializes the port and releases it again, so a port that's already open (eg, the console) isn't changed.

### Printers

Sends an IBM/Epson printer its print codes:

- *cols* is 132 for condensed print, or 80 for normal print
- *lines* is 8 or 6 lines per inch

Any other value, or a value that's omitted, sends nothing for that setting (eg, `MODE LPT1:,8` sets only the lines per inch).

Source: [MODE.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/MODE.BAS)

{% include footer.html prev="LS:../ls/" next="MORE:../more/" %}
