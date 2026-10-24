---
layout: sheet
title: BASIC-DOS Keyboard Commands
permalink: /docs/bdman/cmd/device/keyboard/
---

{% include header.html %}

Keyboard commands include:

- [KEY](#key)

To read keys from a BASIC program, use the [INKEY$](../../basic/func/#inkey) function.  For a summary of the keys used to edit commands, see [Typing Commands](../../../intro/#typing-commands) or type [KEYS](../../system/#keys).

To read a line from the keyboard, use the [INPUT](../../basic/#input) or [LINE INPUT](../../basic/#line-input) statement.

### KEY

> KEY ON|OFF  
> KEY *n*,*string*

KEY ON and KEY OFF are accepted for compatibility with Microsoft BASIC, but do nothing, since BASIC-DOS doesn't display function keys.

In Microsoft BASIC, KEY *n*,*string* makes function key *n* (1-10) type the *string*.  BASIC-DOS accepts it, too (a key number other than 1-10 is an "Illegal function call"), but doesn't assign strings to the function keys: they always return their key codes (eg, F1 is CHR$(0)+CHR$(59) for [INKEY$](../../basic/func/#inkey)), as they do in Microsoft BASIC after KEY *n*,"" (which is how programs like COMM.BAS free the function keys for their own use).  KEY *n*,*string* isn't available on low memory systems (see [Low Memory](../../../lang/#low-memory)).

{% include footer.html prev="Clock Commands:../clock/" next="Mouse Commands:../mouse/" %}
