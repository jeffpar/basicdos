---
layout: sheet
title: BASIC-DOS Sound Commands
permalink: /docs/bdman/cmd/device/sound/
---

{% include header.html %}

Sound commands include:

- [PLAY](#play)
- [SOUND](#sound)

### PLAY

> PLAY *string*

Plays music, using these commands:

- A-G [#|+|-] [*n*] [.]: plays a note, optionally sharp (# or +) or flat (-), with an optional length *n* (eg, 4 for a quarter note), and with optional dots (each dot increases the length by half)
- N *n*: plays note *n* (0-84, where 0 is a rest)
- O *n*: sets the octave (0-6); the default is 4
- < and >: moves down or up one octave
- L *n*: sets the default length (1-64); the default is 4
- P *n*: pauses for length *n*
- T *n*: sets the tempo, in quarter notes per minute (32-255); the default is 120
- MN, ML, MS: plays notes normally, legato (full length), or staccato (three-quarter length)

The octave, length, tempo, and mode persist from one PLAY to the next.  MF and MB are ignored, since music always plays in the foreground (PLAY returns when the music ends).

	PLAY "T160 O3 L8 C D E F G4 G4 A A A A G2"

### SOUND

> SOUND *frequency*,*duration*

Plays a tone of the specified *frequency* (37-32767 Hz) for *duration* clock ticks (18.2 per second).

The program continues while the tone plays, but the next SOUND waits for it to finish, unless its *duration* is 0, which stops the tone.

	FOR F = 200 TO 1000 STEP 100:SOUND F,2:NEXT

{% include footer.html prev="Graphics Commands:../graphics/" next="Disk Commands:../../disk/" %}
