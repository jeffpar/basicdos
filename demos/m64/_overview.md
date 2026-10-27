
### BASIC Samples

The {% if include.hw == "xt" %}hard disk's{% else %}diskette's{% endif %} **SAMPLES** directory contains text copies of the BASIC samples from the IBM PC DOS 1.00 diskette, but most of them use graphics{% if include.hw != "xt" %} (and some use floating-point){% endif %}, so try the [Color Graphics](../../s80/{{ include.hw }}/) machine demo instead.

### **CONFIG.SYS** from the BASIC-DOS {% if include.hw == "xt" %}640K {% endif %}Monochrome Demo Diskette

```
{% if include.hw == "xt" %}{% include_relative m640/CONFIG.SYS %}{% else %}{% include_relative CONFIG.SYS %}{% endif %}
```
