---
layout: sheet
title: BASIC-DOS Clock Commands
permalink: /docs/bdman/cmd/device/clock/
---

{% include header.html %}

Clock commands include:

- [DATE](#date)
- [TIME](#time)

The [DATE$](../../basic/func/#date) and [TIME$](../../basic/func/#time) functions return the current date and time as strings.

### DATE

> DATE [*date*] [/P]

Sets the system date (or prompts for a date if /P is specified) and then displays the date.

The date must be entered as M-D-Y or M/D/Y, where M is 1-12, D is 1-31, and Y is 0-99 or 1980-2099.  If D or Y are omitted, current values are assumed.

	DATE 10-5-26
	Current date is Mon 10-05-2026

### TIME

> TIME [*time*] [/D] [/P]

Sets the system time (or prompts for a time if /P is specified) and then displays the time.  /D displays the elapsed time.

The time must be entered as H:M:S.D, where H is 0-23, M is 0-59, S is 0-59, and D is 0-99 (hundredths of a second).  If M, S, or D are omitted, zeros are assumed.

	TIME 13:30
	Current time is 13:30:00.00

{% include footer.html prev="Device Commands:../" next="Keyboard Commands:../keyboard/" %}
