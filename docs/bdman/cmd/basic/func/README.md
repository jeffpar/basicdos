---
layout: sheet
title: BASIC Functions
permalink: /docs/bdman/cmd/basic/func/
---

{% include header.html %}

Functions can be used in any expression, in BASIC programs or at the prompt (eg, `PRINT SQR(2)`).  Functions whose names end with `$` return strings; all others return numbers.

- Numeric functions: [ABS](#abs), [ATN](#atn), [CDBL](#cdbl), [CINT](#cint), [COS](#cos), [CSNG](#cdbl), [EXP](#exp), [FIX](#fix), [INT](#int), [LOG](#log), [RND](#rnd), [RND%](#rnd-int), [SGN](#sgn), [SIN](#sin), [SQR](#sqr), [TAN](#tan)
- String functions: [ASC](#asc), [CHR$](#chr), [HEX$](#hex), [INSTR](#instr), [LCASE$](#lcase), [LEFT$](#left), [LEN](#len), [MID$](#mid), [OCT$](#oct), [RIGHT$](#right), [SPACE$](#space), [SPC](#space), [STR$](#str), [STRING$](#string), [TAB](#tab), [UCASE$](#ucase), [VAL](#val)
- File functions: [CVD](#cvi), [CVI](#cvi), [CVL](#cvi), [DIR$](#dir), [EOF](#eof), [EXISTS](#exists), [INPUT$](#input), [LOC](#loc), [LOF](#lof), [MKD$](#mki), [MKI$](#mki), [MKL$](#mki)
- System functions: [ARG$](#arg), [CSRLIN](#csrlin), [CURDIR$](#curdir), [DATE$](#date), [DOS](#dos), [ERL](#erl), [ERR](#err), [FRE](#fre), [INKEY$](#inkey), [MOUSE](#mouse), [PATH$](#path), [LPOS](#lpos), [PEEK](#peek), [POS](#pos), [SCREEN](#screen), [TIME$](#time), [TIMER](#timer)
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

#### CDBL, CSNG {#cdbl}

> CDBL(*x*)  
> CSNG(*x*)

Returns *x* as a double (since all floating-point values are double-precision, CSNG is the same as CDBL).

#### CINT {#cint}

> CINT(*x*)

Returns *x* rounded to an integer, the same way that assigning *x* to an integer variable rounds it (eg, `CINT(2.6)` is 3).  Unlike Microsoft BASIC, the result is a 32-bit integer.

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

#### SGN {#sgn}

> SGN(*x*)

Returns -1 if *x* is negative, 0 if *x* is zero, or 1 if *x* is positive.

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

Returns the character code (0-255) of the first character of *string*.  As in MSBASIC, an empty *string* is an "Illegal function call" error.

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

Returns *n* characters of *string*, beginning at position *start* (or the rest of *string* if *n* is omitted).

> MID$(*variable$*,*start*[,*n*]) = *string*

The MID$ statement replaces characters of a string variable (or array element), beginning at position *start*, with the characters of *string*, but never more than *n* characters (if specified) or more than fit, since the variable's length doesn't change (eg, after `A$ = "HELLO WORLD" : MID$(A$,7) = "THERE"`, A$ is "HELLO THERE").  As in Microsoft BASIC, *start* must be 1 to 255 and no greater than the variable's length, and *n* must be 0 to 255, or an "Illegal function call" occurs.  The MID$ statement isn't available on low memory systems (see [Low Memory](../../../lang/#low-memory)).

#### OCT$ {#oct}

> OCT$(*n*)

Returns the octal representation of the integer *n*.

#### RIGHT$ {#right}

> RIGHT$(*string*,*n*)

Returns the rightmost *n* characters of *string*.

#### SPACE$, SPC {#space}

> SPACE$(*n*)  
> SPC(*n*)

Returns a string of *n* spaces.  SPC is the same (eg, `PRINT "A"; SPC(5); "B"`).

#### STR$ {#str}

> STR$(*x*)

Returns *x* as a string, with a leading space if *x* is not negative.

#### STRING$ {#string}

> STRING$(*n*,*char*)

Returns a string of *n* copies of *char*, which can be either a character code or a string (whose first character is used).

#### TAB {#tab}

> TAB(*n*)

Returns enough spaces to move the cursor to column *n* (1-254), for PRINT (eg, `PRINT "A"; TAB(10); "B"`); if the cursor is already past column *n*, the spaces start on the next line.

#### UCASE$ {#ucase}

> UCASE$(*string*)

Returns *string* with all lower-case letters converted to upper-case.

#### VAL {#val}

> VAL(*string*)

Returns the numeric value of *string*, ignoring any blanks.  If *string* does not begin with a number, the result is 0.  Like numeric constants, *string* can use the `&H` (hexadecimal) and `&O` (octal) prefixes; `&` alone also means octal (eg, `VAL("&HFF")` is 255, and `VAL("&17")` is 15).  Without floating-point (eg, when the FPU$ driver isn't loaded; see [MEM](../../system/#mem)), the result is an integer (eg, `VAL("3.9")` is 3).

### File Functions {#file-functions}

#### CVI, CVL, CVD {#cvi}

> CVI(*string*)  
> CVL(*string*)  
> CVD(*string*)

Return the integer stored in the first 2 bytes of *string* by MKI$ (-32768 to 32767), the integer stored in the first 4 bytes by MKL$, or the double stored in the first 8 bytes by MKD$; a shorter string is an "Illegal function call" error.  Use them to read numbers from random access files (see [FIELD](../#field)).

#### DIR$ {#dir}

> DIR$[(*filespec*[,*attributes*])]

Returns the first file or directory matching *filespec* (which may contain wildcards), or if *filespec* is omitted (or empty), the next match.  An empty string means there are no (more) matches.  The default *attributes* (&H16) include hidden, system, and directory entries; use &H10 to skip hidden and system files as [DIR](../../disk/#dir) does, or 8 to find the volume label.

Each match is a string that contains the entry's directory information, followed by its name:

| Position | Length | Contents | Example |
|---|---|---|---|
| 1 | 1 | attributes | `ASC(F$)` (&H10 = directory) |
| 2 | 2 | time | `CVI(MID$(F$,2))` |
| 4 | 2 | date | `CVI(MID$(F$,4))` |
| 6 | 4 | size | `CVL(MID$(F$,6))` |
| 10 | 1-12 | name | `MID$(F$,10)` |

The time and date are in PC DOS directory format (add 65536 to a negative value first): the hour is time `\ 2048`, the minute is `(time \ 32) AND 63`, the year is date `\ 512 + 1980`, the month is `(date \ 32) AND 15`, and the day is date `AND 31`.  For example:

    F$ = DIR$("*.BAS")
    WHILE F$ <> "" : PRINT MID$(F$,10), CVL(MID$(F$,6)) : F$ = DIR$ : WEND

Commands that search for files (eg, DIR, or COPY, DEL, and TYPE with wildcards) start searches of their own, so call DIR$ with a *filespec* again after using one.  The DEMOS folder's DIR.BAS displays a listing like DIR's, using DIR$.

#### EOF {#eof}

> EOF(*n*)

Returns -1 (true) if file *n*, which must be open for INPUT or RANDOM (see [OPEN](../#open)), is at its end (or at a CTRL-Z), or 0 (false) if not (eg, `WHILE NOT EOF(1)`).  For a serial port opened without FOR (eg, `OPEN "COM1:" AS #1`), it's true if no characters are waiting to be read, as in Microsoft BASIC.

#### EXISTS {#exists}

> EXISTS(*filespec*)

Returns -1 (true) if a file or directory matching *filespec* exists, or 0 (false) if not; *filespec* may contain wildcards (eg, `EXISTS("C:\SAMPLES\*.BAS")`).  For example, a batch file can create a directory only if it doesn't already exist:

    IF NOT EXISTS("OBJ") THEN MD OBJ

PC DOS batch files use `IF EXIST` (and `IF NOT EXIST`) for the same purpose.

#### INPUT$ {#input}

> INPUT$(*n*[,[#]*f*])

Returns *n* characters (1-255) read from file *f*, which must be open for INPUT or be a device opened without FOR (see [OPEN](../#open)), or if *f* is omitted, from the keyboard.  Unlike [INPUT](../#input), keys aren't displayed, and every key is a character (eg, ENTER is CHR$(13)); an extended key is two characters, a null and the key's scan code, as with [INKEY$](#inkey).  INPUT$ waits until all *n* characters have been read (from the keyboard, or from a serial port; use [LOC](#loc) to find out how many are waiting).  Reading past the end of a file is an "Input past end" error (62).

	PRINT "Continue (Y/N)?";
	K$ = INPUT$(1) : PRINT K$

#### IOCTL$ {#ioctl}

> IOCTL$(*n*,*code*[,*value*])

Sends an IOCTL request with the specified *code* (and *value* in DX) to the device or volume open as file *n* (see the [IOCTL #](../#ioctl) statement), and returns the data (up to 255 bytes) that the driver stored in response, or an empty string if it stored nothing.  For example, FORMAT.BAS gets a hard disk's geometry and partition table with the hard disk driver's IOCTL_GETPART (&HF3) request, which the diskette driver answers with an empty string.  Errors are the same as for IOCTL #.

#### LOC {#loc}

> LOC(*n*)

Returns the last record number used by [GET #](../#get) or [PUT #](../#put) for file *n*, or for a sequential file, its position divided by 128.  For a serial port opened without FOR (eg, `OPEN "COM1:" AS #1`), it returns the number of characters waiting to be read (up to 255), as in Microsoft BASIC, so `A$ = INPUT$(LOC(1),#1)` reads them all.

#### LOF {#lof}

> LOF(*n*)

Returns the size of file *n*, in bytes.

#### MKI$, MKL$, MKD$ {#mki}

> MKI$(*n*)  
> MKL$(*n*)  
> MKD$(*x*)

Return a 2-byte string containing the integer *n* (its low 16 bits), a 4-byte string containing *n*, or an 8-byte string containing the double *x*, for storing numbers in random access files (see [LSET](../#lset)).  Doubles are stored in IEEE format, not the MBF format used by Microsoft BASIC, so Microsoft BASIC files that contain MKS$ or MKD$ values can't be read with CVD (and MKS$ and CVS aren't supported).

### System Functions

#### ARG$ {#arg}

> ARG$[(*n*)]

Returns an argument from the command line that ran the current BAS or BAT file: `ARG$(0)` is the file's name (as typed), `ARG$(1)` is the first argument, and so on, and `ARG$` alone returns all the arguments.  Arguments are separated by spaces, and a quoted argument (eg, `"two words"`) can contain spaces; the quotes aren't included.  Any string variable in the command line has already been replaced by its value (see [Command Arguments](../../../lang/#command-arguments)).  The result is an empty string if there's no such argument, or if no BAS or BAT file is running (eg, at the prompt).  A BAS or BAT file run by another one has its own arguments.  For example, if SHOW.BAS contains:

	PRINT ARG$(0); " has "; ARG$(1); " and "; ARG$(2)

then typing `SHOW one "two three"` displays `SHOW has one and two three`.

#### CSRLIN {#csrlin}

> CSRLIN

Returns the cursor's row, starting at 1 (see [POS](#pos) and [LOCATE](../../device/screen/#locate)).

#### CURDIR$ {#curdir}

> CURDIR$

Returns the current drive and directory as a string, in the same form that [CD](../../disk/#cd) displays (eg, `C:\BASIC`, or `C:\` in the root directory).  `LEFT$(CURDIR$,1)` is the current drive letter.

#### DATE$ {#date}

> DATE$

Returns the current date as a string in the form MM-DD-YYYY.

#### DOS {#dos}

> DOS(*n*)

Returns register AX (*n* = 0), BX (1), CX (2), or DX (3), as DOS returned it to the last [DOS](../#dos) statement, as a value from 0 to 65535.  Any other *n* is an "Illegal function call".  For example, after `DOS &H3600, 0, 0, 0` (get disk info for the current drive), `DOS(0) * DOS(1) * DOS(2)` is the number of bytes free.

#### ERL {#erl}

> ERL

Returns the line number of the last error (see [ON ERROR](../#on-error)), or 0 if it occurred in a program without line numbers.

#### ERR {#err}

> ERR

Returns the number of the last error (see [ON ERROR](../#on-error)).

#### FRE {#fre}

> FRE(*x*)

Compacts string memory and returns the number of bytes available, or if *x* is negative (eg, `FRE(-1)`), the number of bytes of memory owned by the current session (its command processor's memory blocks, including its program, variables, and strings).  Other sessions can't change that amount, so it's useful for checking for memory leaks while other sessions are running.

#### INKEY$ {#inkey}

> INKEY$

Returns the next key pressed, without waiting (an empty string if no key was pressed).  Extended keys (eg, cursor keys) return two characters: a null and the key's scan code.

	10 LET K$ = INKEY$:IF K$ = "" THEN GOTO 10
	PRINT "You pressed "; K$

#### MOUSE {#mouse}

> MOUSE(*n*)

Returns the next mouse button event (*n* = 0), the position of that event (1 and 2), or the current position (3 and 4) or buttons (5).  See [MOUSE](../../device/mouse/#mouse-function) for details.

#### PATH$ {#path}

> PATH$
> PATH$ = *string*

Returns (or sets) the directories, separated by semicolons, that are searched for a program (or a file to [LOAD](../../disk/#load)) that isn't in the current directory (eg, `PATH$ = "A:\;A:\EXT;A:\DEMOS;A:\SAMPLES"`); see [Running Programs](../../../intro/#running-programs).  Unlike other variables, PATH$ keeps its value when variables are cleared (eg, by [NEW](../../system/#new) or [CLEAR](../#clear)), and each session has its own.  It's usually set on a [SHELL](../../../cfg/#shell) line in CONFIG.SYS, and it's limited to 120 characters.

#### LPOS {#lpos}

> LPOS(*n*)

Returns the printer's current column, starting at 1 (*n* is ignored), as PRN (normally LPT1) tracks it: a carriage return returns it to 1, a backspace backs it up, and other control characters don't move it (see [LPRINT](../../device/screen/#lprint)).  Without a printer, LPOS returns 1.  LPOS isn't available on low memory systems.

#### PEEK {#peek}

> PEEK(*offset*)

Returns the byte at *offset* in the segment set by [DEF SEG](../#def-seg).  For example, this returns the low byte of the BIOS timer tick count:

	DEF SEG=0:PRINT PEEK(&H46C)

#### POS {#pos}

> POS(*n*)

Returns the cursor's column, starting at 1 (*n* is ignored).

#### SCREEN {#screen}

> SCREEN(*row*,*col*[,*z*])

Returns the character code at *row* and *col* (starting at 1), or if *z* is non-zero, its attributes (eg, `SCREEN(1,1,1)` returns 7 for a white-on-black character).  A position outside the console is an illegal function call.  For the SCREEN statement, see [SCREEN](../../device/screen/#screen).

#### TIME$ {#time}

> TIME$

Returns the current time as a string in the form HH:MM:SS.

#### TIMER {#timer}

> TIMER

Returns the number of seconds since midnight, with hundredths (eg, 45296.17), from the same clock as TIME$, so (as in MSBASIC) `RANDOMIZE TIMER` seeds the random numbers differently each time.  Without the FPU$ driver (and therefore doubles), TIMER returns whole seconds.  Event trapping (ON TIMER) isn't supported.

### Predefined Constants

#### ERRORLEVEL {#errorlevel}

Equal to the return code from the last program executed, or for an internal command (eg, COPY or DEL), 0 if it succeeded or 1 if it failed (eg, `IF ERRORLEVEL THEN PRINT "Failed"`).

#### MAXINT {#maxint}

Equal to the largest positive integer (2147483647).

{% include footer.html prev="RETURN:../return/" next="Device Commands:../../device/" %}
