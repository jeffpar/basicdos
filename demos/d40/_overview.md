The BASIC-DOS 40-Column Demo diskette's **CONFIG.SYS** defines two 40-column consoles side by side, each running its own copy of COMMAND.COM.  The left console runs HELLO.BAT, a batch file that displays a colorful greeting, while the right console runs PIPES.BAT, which pipes the output of DIR through the TR filter (converting it to upper-case) over and over (press CTRL-C in that console to stop it).

Both consoles are configured with borders, and a double-wide border indicates which console has keyboard focus.  Use **SHIFT-TAB** to toggle focus.

### **CONFIG.SYS** from the BASIC-DOS 40-Column Demo Diskette

```
{% include_relative CONFIG.SYS %}
```
