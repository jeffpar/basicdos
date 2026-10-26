### No Video Required

The IBM PC doesn't require a video adapter.  SW1 switches 5 and 6 tell the BIOS which display is installed, and when both are ON (the setting an EGA uses, since it has its own BIOS), POST skips its video tests and initialization.  The BIOS video functions still run, but with no display to update, the BIOS has nothing to show until BASIC-DOS opens COM1.

BASIC-DOS doesn't require one either.  The diskette's CONFIG.SYS skips the CON driver, along with FPU$ and PIPE$ (as on the [Monochrome](../../m64/pc/) demo), and opens the only console on COM1 with the COM driver's VT100 terminal type.  Commands like `CLS` and `LOCATE` use VT100 escape sequences, the VT100's DELETE key erases the previous character (like the PC's BACKSPACE key), and XON/XOFF flow control is enabled, which the VT100 relies on whenever it falls behind (eg, while smooth scrolling).

### BASIC Samples

The diskette's **SAMPLES** directory contains text copies of the BASIC samples from the IBM PC DOS 1.00 diskette, but most of them use graphics (and some use floating-point), so try the [Color (with FPU)](../../s80/pc/) machine demo instead.

### **CONFIG.SYS** from the BASIC-DOS Terminal Only Demo Diskette

```
{% include_relative CONFIG.SYS %}
```
