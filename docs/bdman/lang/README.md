---
layout: sheet
title: BASIC-DOS Programming
permalink: /docs/bdman/lang/
---

{% include header.html %}

The BASIC-DOS programming language is based on the BASIC language of the IBM PC (Microsoft BASIC), and can be used to build BASIC programs directly from the BASIC-DOS command prompt.  Topics include:

- [Programs](#programs)
- [Batch Files](#batch-files)
- [Variables and Types](#variables-and-types)
- [Constants](#constants)
- [Arrays](#arrays)
- [Operators](#operators)
- [Functions](#functions)
- [Control Flow](#control-flow)
- [Error Handling](#error-handling)
- [Graphics and Sound](#graphics-and-sound)
- [Differences from Microsoft BASIC](#differences-from-microsoft-basic)

### Programs

A BASIC program is a text file with a BAS or BAT extension, which you can create with any text editor.  BASIC-DOS can also load BAS files saved by IBM PC BASIC (BASICA) or GW-BASIC, which are usually *tokenized* (a binary format); they're converted back to text as they're loaded, so LIST displays them as BASICA would.  Protected BAS files (saved with the P option) can't be loaded.  Each line contains one or more commands, separated by colons, and any line may begin with a *line number*, which serves as a label for [GOTO](../cmd/basic/goto/), [GOSUB](../cmd/basic/#gosub), and other statements that transfer control.  Lines that aren't the target of a transfer don't need line numbers, and line numbers don't need to be in order.

	REM Print the powers of 2 below 1000
	DEFINT A-Z
	LET N = 1
	10 PRINT N;
	N = N * 2
	IF N < 1000 THEN GOTO 10

Programs can use any BASIC-DOS command (eg, `DIR` or `COLOR`), and can run other programs (including other BAT and BAS files) by name.  Keywords and names can be typed in upper or lower case.  [REM](../cmd/basic/#rem), or an apostrophe outside of quotes, starts a remark that continues to the end of the line.

To run a program, type its name (see [Running Programs](../intro/#running-programs)).  BASIC-DOS first compiles the entire program into 8086 machine code, and then runs it, which is why BASIC-DOS programs run much faster than Microsoft BASIC programs.  It also means that a statement BASIC-DOS doesn't support causes a syntax error before the program starts, even if the program would never reach it.

When a BAS program that you ran from the prompt ends, it remains loaded, along with its functions and variables, so you can [LIST](../cmd/system/#list) it, examine its variables at the prompt (eg, `PRINT N`), or [RUN](../cmd/system/#run) it again.  [NEW](../cmd/system/#new) erases the program and its variables.

BAT files differ from BAS files in two ways: BAT files [ECHO](../cmd/device/screen/#echo) their lines as they run (unless ECHO OFF is used), and BAT files don't remain loaded after they end.  See [Batch Files](#batch-files) for how BASIC-DOS batch files differ from PC DOS batch files.

### Batch Files

A BAT file is a BASIC-DOS program too, so it can contain any BASIC-DOS command or BASIC statement, and it's compiled before it runs (so a syntax error anywhere in the file is reported before any of it runs).  This makes BASIC-DOS batch files more powerful than PC DOS batch files, but some PC DOS batch file features work differently:

| PC DOS | BASIC-DOS |
|--------|-----------|
| `:LOOP` labels, and `GOTO LOOP` | Line numbers (eg, `10 DIR`), and `GOTO 10` |
| `ECHO message` | `PRINT "message"` (ECHO only accepts ON or OFF) |
| `IF ERRORLEVEL 1 GOTO FAIL` (true if ERRORLEVEL is 1 or more) | `IF ERRORLEVEL >= 1 THEN GOTO 100` |
| `SET N=5` and `%N%` (environment variables) | BASIC variables (eg, `N = 5` and `PRINT N`) |
| `%1` through `%9` (replaceable parameters) | Not supported yet |
| `IF EXIST file`, `IF "%1"=="x"` | Not supported yet (but any BASIC expression can be used, eg, `IF A$ = "X" THEN ...`) |
| `CALL OTHER` (to run another batch file and then continue) | `OTHER` (a batch file always continues after running another one) |
| `FOR %%F IN (*.TXT) DO ...`, `SHIFT`, and `PAUSE` | Not supported yet (FOR ... NEXT loops can be used for counting) |

ECHO OFF and the `@` prefix work as they do in PC DOS, and every BAT file run from the prompt starts with ECHO ON; however, echoed lines are displayed with a `@` in front instead of a prompt (see [ECHO](../cmd/device/screen/#echo)).  REM (or an apostrophe) starts a remark.

For example, this batch file runs a program up to three times, stopping if the program reports an error:

	@ECHO OFF
	REM Run SLEEP three times, stopping if it fails
	N = 1
	10 SLEEP 1
	IF ERRORLEVEL <> 0 THEN PRINT "SLEEP failed" : END
	N = N + 1
	IF N <= 3 THEN GOTO 10
	PRINT "SLEEP ran"; N - 1; "times"

Unlike a BAS file, a BAT file doesn't remain loaded when it ends.

### Variables and Types

Variable names begin with a letter, followed by any letters and digits, and an optional type suffix.  BASIC-DOS has three types of values:

| Type | Suffix | Range |
|------|--------|-------|
| Integer | `%` | 32-bit, from -2147483648 to 2147483647 ([MAXINT](../cmd/basic/func/#maxint)) |
| Double | `#` or `!` | 64-bit IEEE 754 floating-point, with about 15 significant digits |
| String | `$` | 0 to 255 characters |

A variable without a suffix uses the default type for its first letter, which is double unless [DEFINT](../cmd/basic/#defint) or [DEFSTR](../cmd/basic/#defstr) changes it (eg, `DEFINT A-Z` makes all unsuffixed variables integers).  If floating-point support is disabled, the default type is integer.

The type is part of a variable's identity, so `A%`, `A#`, and `A$` are three different variables.  Likewise, after `DEFINT A-Z` and then `DEFDBL A-Z`, `A` refers to a new variable, separate from the `A` used before (which is still `A%`).

Numeric variables start with a value of zero, and string variables start empty.  Values are converted automatically between integers and doubles as needed; a double converted to an integer is rounded (with halves rounded away from zero, so 2.5 becomes 3 and -2.5 becomes -3).

Integer arithmetic is much faster than floating-point arithmetic, so programs that don't need fractions should begin with `DEFINT A-Z`.

The predefined variables [ERRORLEVEL](../cmd/basic/func/#errorlevel) and [MAXINT](../cmd/basic/func/#maxint) can't be assigned new values.

### Constants

- Integers: `123`, `-5`
- Doubles: `1.5`, `.25`, `6.02E23`, `1D-10`; any number with a decimal point or exponent is a double
- Hexadecimal and octal integers: `&H1F`, `&O17`
- Strings: `"Hello"`; a string at the end of a line doesn't need a closing quote

A numeric constant can also have a type suffix: `#` or `!` makes it a double (eg, `2!`), and `%` keeps it an integer (eg, `7%`).

### Arrays

Arrays of integers, doubles, or strings can have up to 255 dimensions, and are created with [DIM](../cmd/basic/#dim):

	DIM SCORES%(100), NAMES$(10), GRID(9,9)

An array that's used without DIM is created automatically, with a largest subscript of 10 in each dimension.  The smallest subscript is 0, unless [OPTION BASE](../cmd/basic/#option-base) 1 is used.  [ERASE](../cmd/basic/#erase) deletes arrays, so that they can be dimensioned again.

Each array must fit in a single 64K memory block.

### Operators

Operators are listed below from highest to lowest precedence; operators on the same line have the same precedence and are evaluated from left to right.  Parentheses can be used to change the order of evaluation.

| Operator | Meaning |
|----------|---------|
| `^` | Exponentiation |
| `-`, `+` | Negation, unary plus |
| `*`, `/` | Multiplication, division |
| `\` | Integer division (eg, `7\2` is 3) |
| `MOD` | Remainder of integer division (eg, `7 MOD 3` is 1) |
| `+`, `-` | Addition (or string concatenation), subtraction |
| `<<`, `>>` | Arithmetic shift left, right (eg, `1<<4` is 16) |
| `=`, `<>`, `<`, `>`, `<=`, `>=` | Relational (`==` is the same as `=`) |
| `NOT` | Bitwise NOT |
| `AND` | Bitwise AND |
| `OR` | Bitwise OR |
| `XOR` | Bitwise exclusive OR |
| `EQV` | Bitwise equivalence |
| `IMP` | Bitwise implication |

Relational operators return -1 for TRUE and 0 for FALSE, and they compare strings as well as numbers.  The logical operators operate on all 32 bits of their integer operands, so `NOT 0` is -1 (TRUE).

The `/` operator always produces a double (eg, `7/2` is 3.5), unless floating-point support is disabled.  The `<<` and `>>` operators are BASIC-DOS extensions.

### Functions

BASIC-DOS includes many [predefined functions](../cmd/basic/func/), and [DEF](../cmd/basic/def/) defines new functions, which can be single-line expressions or multi-line blocks:

	DEF CUBE(X) = X^3
	DEF HYP(A,B)
	LET C = A*A + B*B
	RETURN SQR(C)

Function names don't need to begin with FN.

### Control Flow

- [IF](../cmd/basic/if/) *expression* THEN *statements* [ELSE *statements*]
- [GOTO](../cmd/basic/goto/) *label* and [ON](../cmd/basic/#on) *expression* GOTO *labels*
- [GOSUB](../cmd/basic/#gosub) *label* and [RETURN](../cmd/basic/return/), and ON *expression* GOSUB *labels*
- [FOR](../cmd/basic/#for) ... [NEXT](../cmd/basic/#for) and [WHILE](../cmd/basic/#while) ... [WEND](../cmd/basic/#while)
- [END](../cmd/basic/#end) (or STOP), and [CHAIN](../cmd/basic/#chain) to run another BAS file

Press **Ctrl-C** to stop a running program.

### Error Handling

When a runtime error occurs (eg, "Illegal function call" or "Subscript out of range"), the program ends with an error message, unless an [ON ERROR GOTO](../cmd/basic/#on-error) handler is active.  The handler can use [ERR](../cmd/basic/func/#err) to get the error number, and [RESUME](../cmd/basic/#resume) *label* to continue the program.  Error numbers are the same as Microsoft BASIC's, and [ERROR](../cmd/basic/#error) *n* simulates an error.

### Graphics and Sound

On a color adapter, [SCREEN](../cmd/device/screen/#screen) 1 or 2 selects a graphics mode, where the [graphics commands](../cmd/device/graphics/) (CIRCLE, DRAW, GET, LINE, PAINT, PRESET, PSET, and PUT) can be used.  [PLAY](../cmd/device/sound/#play) plays music, and [SOUND](../cmd/device/sound/#sound) plays tones.

When a BAS program ends, BASIC-DOS restores the video mode it started with.

### Differences from Microsoft BASIC

BASIC-DOS runs many IBM PC BASIC programs unchanged (eg, DONKEY.BAS, from the original PC DOS 1.00 diskette), but there are differences:

- Programs are text files, edited with a text editor, rather than typed and saved from within BASIC; there are no AUTO, EDIT, RENUM, or SAVE commands, although tokenized BAS files saved by BASICA and GW-BASIC can be loaded
- Line numbers are optional, and only needed on lines that are targets of GOTO, GOSUB, etc
- LET is required for assignments typed at the prompt (but not in programs)
- Single-precision values are double-precision (DEFSNG is the same as DEFDBL), and integers are 32-bit, not 16-bit
- Function names don't need to begin with FN, and functions can have multiple lines
- Since programs are compiled first, unsupported statements are reported before the program runs
- PRINT commas print a tab instead of advancing to the next print zone
- Not supported yet: INPUT, LINE INPUT, READ, DATA, RESTORE, file I/O statements (eg, OPEN and PRINT #), the MID$ statement, PRINT USING, RESUME without a label, RESUME NEXT, ERL, POINT, and STEP coordinates

{% include footer.html prev="System Commands:../cmd/system/" next="Configuring BASIC-DOS:../cfg/" %}
