The BASICDOS-DISK2 diskette's **CONFIG.SYS** defines two 40-column consoles side by side, each running its own copy of COMMAND.COM.  The left session runs HELLO.BAT, a batch file that displays the BASIC-DOS version and a colorful greeting, while the right session runs BD3.BAT, which pipes the output of DIR through the CASE filter over and over (press CTRL-C in that session to stop it).

Both sessions are configured with borders, and a double-wide border indicates which session has keyboard focus.  Use **SHIFT-TAB** to toggle focus.

### **CONFIG.SYS** from the BASICDOS-DISK2 Diskette

```
{% include_relative CONFIG.SYS %}
```
