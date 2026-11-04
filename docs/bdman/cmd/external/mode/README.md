---
layout: sheet
title: MODE
permalink: /docs/bdman/cmd/external/mode/
---

{% include header.html %}

> MODE 40\|80\|BW40\|BW80\|CO40\|CO80  
> MODE COM*n*:*baud*[,*parity*[,*data*[,*stop*]]]  
> MODE LPT*n*:[*cols*][,*lines*]

Sets the display, a serial port, or a printer.  Any other argument, or none at all, displays MODE's usage.

### Display

Sets the display to 40 or 80 columns.  BW turns color off, as `SCREEN 0,0` does, and CO turns it on.

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
