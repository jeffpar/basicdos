---
layout: sheet
title: BASIC Functions
permalink: /docs/bdman/cmd/basic/func/
---

{% include header.html %}

Functions can be used in any expression, in BASIC programs or at the prompt (eg, `PRINT SQR(2)`).  Functions whose names end with `$` return strings; all others return numbers.

- Numeric functions: [ABS](#abs), [ATN](#atn), [COS](#cos), [EXP](#exp), [FIX](#fix), [INT](#int), [LOG](#log), [RND](#rnd), [RND%](#rnd-int), [SIN](#sin), [SQR](#sqr), [TAN](#tan)
- String functions: [ASC](#asc), [CHR$](#chr), [HEX$](#hex), [INSTR](#instr), [LCASE$](#lcase), [LEFT$](#left), [LEN](#len), [MID$](#mid), [OCT$](#oct), [RIGHT$](#right), [SPACE$](#space), [STR$](#str), [STRING$](#string), [UCASE$](#ucase), [VAL](#val)
- System functions: [ARG$](#arg), [DATE$](#date), [ERR](#err), [FRE](#fre), [INKEY$](#inkey), [MOUSE](#mouse), [PEEK](#peek), [TIME$](#time)
- Predefined constants: [ERRORLEVEL](#errorlevel), [MAXINT](#maxint)

You can also define your own functions with [DEF](../def/).

### Numeric Functions

The trigonometric functions use radians, and all floating-point calculations use 64-bit (double-precision) values, with about 15 significant digits.  If floating-point support is disabled (see [Starting BASIC-DOS](../../../intro/#starting-basic-dos)), numeric variables default to integers, and `/` and `^` are integer operations.

#### ABS {#abs}

> ABS(*x*)

Returns the absolute value of *x*.

#### ATN {#atn}

> ATN(*x*)

Returns the arctangent of *x*, in radians (eg, `4*ATN(1)` is pi).

#### COS {#cos}

> COS(*x*)

Returns the cosine of *x*, where *x* is in radians.

#### EXP {#exp}

> EXP(*x*)

Returns e (2.71828...) raised to the power of *x*.

#### FIX {#fix}

> FIX(*x*)

Returns *x* truncated to an integer (eg, `FIX(-2.5)` is -2).  See also [INT](#int).

#### INT {#int}

> INT(*x*)

Returns the largest integer less than or equal to *x* (eg, `INT(-2.5)` is -3).  See also [FIX](#fix).

#### LOG {#log}

> LOG(*x*)

Returns the natural logarithm of *x*, which must be greater than zero.

#### RND {#rnd}

> RND[(*n*)]

Returns a random number from 0 up to (but not including) 1.  *n* has the same effect as with [RND%](#rnd-int).

#### RND% {#rnd-int}

> RND%[(*n*)]

Returns a random integer between 0 and [MAXINT](#maxint), inclusive.  If *n* is negative, the generator is reseeded first, and if *n* is zero, the previous random integer is returned.

#### SIN {#sin}

> SIN(*x*)

Returns the sine of *x*, where *x* is in radians.

#### SQR {#sqr}

> SQR(*x*)

Returns the square root of *x*, which must not be negative.

#### TAN {#tan}

> TAN(*x*)

Returns the tangent of *x*, where *x* is in radians.

### String Functions

Strings can contain up to 255 characters.  Character positions start at 1.

#### ASC {#asc}

> ASC(*string*)

Returns the character code (0-255) of the first character of *string* (or 0 if *string* is empty).

#### CHR$ {#chr}

> CHR$(*code*)

Returns a one-character string containing the character with the specified *code* (0-255).

#### HEX$ {#hex}

> HEX$(*n*)

Returns the hexadecimal representation of the integer *n*.  Negative values are treated as unsigned 32-bit values (eg, `HEX$(-1)` is "FFFFFFFF").

#### INSTR {#instr}

> INSTR([*start*,]*string1*,*string2*)

Returns the position of *string2* within *string1*, searching from position *start* (default 1), or 0 if not found.

#### LCASE$ {#lcase}

> LCASE$(*string*)

Returns *string* with all upper-case letters converted to lower-case.

#### LEFT$ {#left}

> LEFT$(*string*,*n*)

Returns the leftmost *n* characters of *string*.

#### LEN {#len}

> LEN(*string*)

Returns the number of characters in *string* (0-255).

#### MID$ {#mid}

> MID$(*string*,*start*[,*n*])

Returns *n* characters of *string*, beginning at position *start* (or the rest of *string* if *n* is omitted).  The MID$ statement (eg, `MID$(A$,2) = "X"`) isn't supported yet.

#### OCT$ {#oct}

> OCT$(*n*)

Returns the octal representation of the integer *n*.

#### RIGHT$ {#right}

> RIGHT$(*string*,*n*)

Returns the rightmost *n* characters of *string*.

#### SPACE$ {#space}

> SPACE$(*n*)

Returns a string of *n* spaces.

#### STR$ {#str}

> STR$(*x*)

Returns *x* as a string, with a leading space if *x* is not negative.

#### STRING$ {#string}

> STRING$(*n*,*char*)

Returns a string of *n* copies of *char*, which can be either a character code or a string (whose first character is used).

#### UCASE$ {#ucase}

> UCASE$(*string*)

Returns *string* with all lower-case letters converted to upper-case.

#### VAL {#val}

> VAL(*string*)

Returns the numeric value of *string*, ignoring any blanks.  If *string* does not begin with a number, the result is 0.  Like numeric constants, *string* can use the `&H` (hexadecimal) and `&O` (octal) prefixes; `&` alone also means octal (eg, `VAL("&HFF")` is 255, and `VAL("&17")` is 15).

### System Functions

#### ARG$ {#arg}

> ARG$[(*n*)]

Returns an argument from the command line that ran the current BAS or BAT file: `ARG$(0)` is the file's name (as typed), `ARG$(1)` is the first argument, and so on, and `ARG$` alone returns all the arguments.  Arguments are separated by spaces, and a quoted argument (eg, `"two words"`) can contain spaces; the quotes aren't included.  The result is an empty string if there's no such argument, or if no BAS or BAT file is running (eg, at the prompt).  A BAS or BAT file run by another one has its own arguments.  For example, if SHOW.BAS contains:

	PRINT ARG$(0); " has "; ARG$(1); " and "; ARG$(2)

then typing `SHOW one "two three"` displays `SHOW has one and two three`.

#### DATE$ {#date}

> DATE$

Returns the current date as a string in the form MM-DD-YYYY.

#### ERR {#err}

> ERR

Returns the number of the last error (see [ON ERROR](../#on-error)).

#### FRE {#fre}

> FRE(*x*)

Compacts string memory and returns the number of bytes available.  The argument is ignored.

#### INKEY$ {#inkey}

> INKEY$

Returns the next key pressed, without waiting (an empty string if no key was pressed).  Extended keys (eg, cursor keys) return two characters: a null and the key's scan code.

	10 LET K$ = INKEY$:IF K$ = "" THEN GOTO 10
	PRINT "You pressed "; K$

#### MOUSE {#mouse}

> MOUSE(*n*)

Returns the next mouse button event (*n* = 0), the position of that event (1 and 2), or the current position (3 and 4) or buttons (5).  See [MOUSE](../../device/mouse/#mouse-function) for details.

#### PEEK {#peek}

> PEEK(*offset*)

Returns the byte at *offset* in the segment set by [DEF SEG](../#def-seg).  For example, this returns the low byte of the BIOS timer tick count:

	DEF SEG=0:PRINT PEEK(&H46C)

#### TIME$ {#time}

> TIME$

Returns the current time as a string in the form HH:MM:SS.

### Predefined Constants

#### ERRORLEVEL {#errorlevel}

Equal to the return code from the last program executed, or for an internal command (eg, COPY or DEL), 0 if it succeeded or 1 if it failed (eg, `IF ERRORLEVEL = 1 THEN PRINT "Failed"`).

#### MAXINT {#maxint}

Equal to the largest positive integer (2147483647).

{% include footer.html prev="RETURN:../return/" next="Device Commands:../../device/" %}
