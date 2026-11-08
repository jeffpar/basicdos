{%- if include.hw == "pc" -%}{%- assign hd = false -%}{%- else -%}{%- assign hd = true -%}{%- endif -%}
### No Video Required

{% if include.hw == "at" %}The IBM PC AT almost doesn't require a video adapter.  Its CMOS setup records the primary display, and when that's 00 (the setting an EGA uses, since it has its own BIOS), POST skips its video tests and initialization, but it also requires a video ROM, and without one, it reports a 162 configuration error and waits for the F1 key.  So this machine has a [stub ROM](https://www.pcjs.org/machines/pcx86/ibm/video/none/) at C0000h, which isn't real hardware: just enough of an option ROM (512 bytes, with a signature and an initialization entry point that simply returns) to satisfy POST.  The BIOS video functions do nothing, so the BIOS has nothing to show until BASIC-DOS opens COM1 and COM2.{% else %}The IBM PC {% if include.hw == "xt" %}XT {% endif %}doesn't require a video adapter.  SW1 switches 5 and 6 tell the BIOS which display is installed, and when both are ON (the setting an EGA uses, since it has its own BIOS), POST skips its video tests and initialization.  The BIOS video functions still run, but with no display to update, the BIOS has nothing to show until BASIC-DOS opens COM1.{% endif %}

BASIC-DOS doesn't require one either.  {% if include.hw == "at" %}The diskette's CONFIG.SYS skips the VKD$ (video and keyboard) driver, opens a console on COM1 and another on COM2, both with the COM driver's VT100 terminal type, and starts each console's shell on drive C:, the [hard disk](../../hd/at/), so all of its programs and files are available.{% elsif include.hw == "xt" %}The diskette's CONFIG.SYS skips the VKD$ (video and keyboard) driver, opens the only console on COM1 with the COM driver's VT100 terminal type, and starts the shell on drive C:, the [hard disk](../../hd/xt/), so all of its programs and files are available.{% else %}The diskette's CONFIG.SYS skips the VKD$ (video and keyboard) and PIPE$ drivers (FPU$ unloads itself at 64K, as on the [Monochrome](../../m64/pc/) demo), and opens the only console on COM1 with the COM driver's VT100 terminal type.{% endif %}  Commands like `CLS` and `LOCATE` use VT100 escape sequences, the VT100's DELETE key erases the previous character (like the PC's BACKSPACE key), and XON/XOFF flow control is enabled, which the VT100 relies on whenever it falls behind (eg, while smooth scrolling).

### BASIC Samples

The {% if hd %}hard disk's{% else %}diskette's{% endif %} **SAMPLES** directory contains text copies of the BASIC samples from the IBM PC DOS 1.00 diskette, but most of them use graphics{% unless hd %} (and some use floating-point){% endunless %}, so try the [Color (with FPU)](../../s80/{{ include.hw }}/) machine demo instead.

### **CONFIG.SYS** from the BASIC-DOS {% if include.hw == "at" %}HD Dual Terminal{% elsif hd %}HD Terminal Only{% else %}Terminal Only{% endif %} Demo Diskette

```
{% if include.hw == "at" %}{% include_relative dual/CONFIG.SYS %}{% elsif hd %}{% include_relative hd/CONFIG.SYS %}{% else %}{% include_relative CONFIG.SYS %}{% endif %}
```
