DEL A:*.COM
MAKE MAKEFILE
IF ERRORLEVEL 1 GOTO END
COPY DEV\IBMBIO.COM A:
COPY DOS\IBMDOS.COM A:
ECHO CON=SCR,KBD>A:CONFIG.SYS
:END
