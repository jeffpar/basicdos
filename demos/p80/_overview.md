The BASICDOS-360K-P80 diskette's **CONFIG.SYS** defines three full-screen 80-column consoles, each running its own copy of COMMAND.COM: HELLO.BAT in the first, FIBO.BAT in the second, and PRIMES.BAT in the third.

Consoles fill the screen from the top left corner, so once the first console fills the screen, the next one is placed on the next page of video memory, and so on (BASIC-DOS uses four pages on a color adapter, while a monochrome adapter has only one).  Only the page of the session with keyboard focus is displayed, but every session keeps running, whether its page is displayed or not.  Use **SHIFT-TAB** to move focus to the next session and display its page.

### **CONFIG.SYS** from the BASICDOS-360K-P80 Diskette

```
{% include_relative CONFIG.SYS %}
```
