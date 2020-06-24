    @ECHO off

    IF "%2" == ""  GOTO help

    ECHO --------!---%1----------------------- >> interrup.lst
    COPY interrup.lst + %2 interrup.lst
    GOTO done

:HELP
    ECHO.
    ECHO                        Interrupt Helper ADDTOPIC utility
    ECHO.
    ECHO                                                 by Gary Chanson
    ECHO                                                 (C) 1994
    ECHO.
    ECHO         Adds additional topic entries to Ralf Brown's INTERRUP.LST.
    ECHO.
    ECHO     usage:
    ECHO.
    ECHO         ADDTOPIC title_text source_file
    ECHO.
    ECHO     WARNING:
    ECHO.
    ECHO         Any text which contains lines of dashes as topic separators
    ECHO         must conform to the INTERRUPT.LST separator format or INTERHLP
    ECHO         will fail during mapping.  If troble is experienced, change
    ECHO         these lines to some other character!
    ECHO.

:DONE
