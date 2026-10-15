The BASICDOS-360K-VT100 diskette's **CONFIG.SYS** creates two independent sessions: an 80x25 console on the Color Display, and a console on a DEC VT100 terminal connected to COM1 at 9600 baud.  Both sessions start on drive C:, the [hard disk](../../hd/{{ include.hw }}/), and share its programs and files.

The VT100 console uses the COM driver's VT100 terminal type, so commands like `CLS` and `LOCATE` use VT100 escape sequences, the VT100's DELETE key erases the previous character (like the PC's BACKSPACE key), and XON/XOFF flow control is enabled, which the VT100 relies on whenever it falls behind (eg, while smooth scrolling).

There's also a [Serial Display](../../serial/) demo, which uses a simple text pane on COM1 instead of a terminal.

### **CONFIG.SYS** from the BASICDOS-360K-VT100 Diskette

```
{% include_relative CONFIG.SYS %}
```
