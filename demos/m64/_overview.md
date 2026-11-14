
### BASIC Samples

{% if include.hw == "xt" %}The hard disk's **TESTS\SAMPLES** directory contains text copies of the BASIC samples from the IBM PC DOS 1.00 diskette (and DONKEY.BAS is in **DEMOS**), but most of them use graphics{% else %}The diskette's **DEMOS** directory contains DONKEY.BAS, a text copy of the BASIC game from the IBM PC DOS 1.00 diskette, but it uses graphics{% endif %}, so try the [Color Graphics](../../s80/{{ include.hw }}/) machine demo instead.

### **CONFIG.SYS** from the BASIC-DOS {% if include.hw == "xt" %}640K {% endif %}Monochrome Demo Diskette

```
{% if include.hw == "xt" %}{% include_relative m640/CONFIG.SYS %}{% else %}{% include_relative CONFIG.SYS %}{% endif %}
```
