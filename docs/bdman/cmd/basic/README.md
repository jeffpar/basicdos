---
layout: sheet
title: BASIC Commands
permalink: /docs/bdman/cmd/basic/
---

{% include header.html %}

BASIC programs can use any BASIC-DOS [command](../) in combination with the BASIC statements described below, along with any of the [BASIC Functions](func/).  See [BASIC-DOS Programming](../../lang/) for an overview of programs, variables, and expressions.

- Variables and types: [CLEAR](#clear), [DEF](def/), [DEFDBL](#defdbl), [DEFINT](#defint), [DEFSNG](#defsng), [DEFSTR](#defstr), [DIM](#dim), [ERASE](#erase), [LET](let/), [OPTION BASE](#option-base), [RANDOMIZE](#randomize), [SWAP](#swap)
- Control flow: [CHAIN](#chain), [END](#end), [FOR](#for)/[NEXT](#for), [GOSUB](#gosub), [GOTO](goto/), [IF](if/), [ON](#on), [RETURN](return/), [STOP](#end), [SYSTEM](#end), [WHILE](#while)/[WEND](#while)
- Error handling: [ERROR](#error), [ON ERROR](#on-error), [RESUME](#resume)
- Data: [DATA](#data), [READ](#read), [RESTORE](#restore)
- Input: [INPUT](#input), [LINE INPUT](#line-input)
- Files: [OPEN](#open), [CLOSE](#close) (or RESET), [INPUT #](#input), [LINE INPUT #](#line-input), [PRINT #](#print), [WRITE](#write), and the [file functions](func/#file-functions)
- Random access files: [FIELD](#field), [GET #](#get), [PUT #](#put), [LSET](#lset), [RSET](#lset)
- Memory: [DEF SEG](#def-seg), [POKE](#poke)
- Remarks: [REM](#rem)

### CHAIN

> CHAIN *file*[,*line*]

Runs the specified BAS file and then ends the program.  The *line* is currently ignored, and other CHAIN options (eg, ALL and MERGE) are not supported.

### CLEAR

> CLEAR [[*n*][,[*m*][,*k*]]]

Resets all numeric variables to zero and all string variables to empty strings, and erases all arrays.  The values are accepted for compatibility with Microsoft BASIC, but are ignored.

### CLOSE

> CLOSE [[#]*n*[,[#]*n*]...]

Closes the specified files, or all files if none are specified (see [OPEN](#open)).  Closing a file that isn't open does nothing.  RESET is the same as CLOSE without file numbers.

### DATA

> DATA *item*[,*item*]...

Defines items for [READ](#read) to assign to variables.  DATA statements aren't executed (but a DATA statement can be followed by other statements on the same line, after a colon), and READ uses their items in the order they appear in the program.  An item can be a number or a string; a string can be in quotes (and can then contain commas and colons), and an unquoted string has any leading and trailing spaces removed.

	READ NAME$, AGE
	PRINT NAME$; " is"; AGE
	DATA "SMITH, JOHN", 42

### DEF

> DEF *function*[(*parameters*)]=*expression*

Defines a function.  See [DEF](def/).

### DEF SEG

> DEF SEG[=*segment*]

Sets the segment that [PEEK](func/#peek) and [POKE](#poke) use.  Without a *segment*, BASIC-DOS's own data segment is used.

### DEFDBL

> DEFDBL [*letter(s)*]

Defines the first letter(s) of variables that will default to double-precision (64-bit) floating-point values (eg, `DEFDBL A-F,X`).  Variables default to double-precision unless DEFINT or DEFSTR is used (or floating-point support is disabled).  Every program starts with these defaults, as in Microsoft BASIC, so DEFDBL, DEFINT, and DEFSTR statements from another program (or typed at the prompt) don't carry over.

### DEFINT

> DEFINT [*letter(s)*]

Defines the first letter(s) of variables that will default to integer (32-bit) values (eg, `DEFINT A-Z`).  Integer operations are much faster than floating-point operations, so programs that don't need fractions should use DEFINT.

### DEFSNG

> DEFSNG [*letter(s)*]

Same as DEFDBL, since all floating-point values are double-precision.

### DEFSTR

> DEFSTR [*letter(s)*]

Defines the first letter(s) of variables that will default to string values.  Unless DEFSTR is used, all string variables must be defined using the `$` suffix.

### DIM

> DIM *array*(*bounds*)[,*array*(*bounds*)]...

Dimensions one or more arrays, with up to 255 dimensions each (eg, `DIM A(10), B$(5,5)`).  Each bound is the largest subscript for that dimension.  Arrays that are used without DIM have a largest subscript of 10.

Using a subscript outside an array's bounds causes a "Subscript out of range" error, and dimensioning an array that's already dimensioned causes a "Duplicate definition" error (use [ERASE](#erase) first).

### END

> END  
> STOP  
> SYSTEM

Ends the program.  STOP and SYSTEM are currently the same as END.

### ERASE

> ERASE *array*[,*array*]...

Erases the specified arrays, so that they can be dimensioned again.  If the first name is not an array, ERASE is the same as [DEL](../disk/#del).

### ERROR

> ERROR *n*

Simulates error *n* (1-255).  If an [ON ERROR](#on-error) handler is active, it's called; otherwise, the program ends with an error message.

### FIELD

> FIELD [#]*n*,*width* AS *variable$*[,*width* AS *variable$*]...

Divides each record of random access file *n* into fields (up to 16), which must fit in the record length (see [OPEN](#open)), or it's a "FIELD overflow" error (50).  [GET #](#get) then sets each variable to its part of the record, and [PUT #](#put) writes each variable to its part of the record, padded with spaces (or truncated) to its width; use [LSET](#lset) or [RSET](#lset) to set the variables.  Unlike Microsoft BASIC, the variables are ordinary string variables (assigning one with LET doesn't detach it from its field), and only one FIELD statement per file is in effect at a time.

### FOR

> FOR *variable*=*start* TO *limit* [STEP *step*]  
> *statement(s)*  
> NEXT [*variable*[,*variable*]...]

Executes the statements up to the matching NEXT repeatedly, adding *step* (default 1) to the *variable* each time, until it passes the *limit*.  If the *start* is already past the *limit*, the statements are skipped.

NEXT without a *variable* ends the innermost FOR loop; otherwise, it ends the FOR loop for each *variable* listed.  FOR loops with integer variables (eg, after `DEFINT A-Z`) are much faster than those with floating-point variables.

	FOR I = 10 TO 1 STEP -3:PRINT I;:NEXT
	 10  7  4  1

### GET # {#get}

> GET [#]*n*[,*record*]

Reads the specified record of random access file *n* (or the record after the last one used, if *record* is omitted) and sets each [FIELD](#field) variable to its part of the record.  Records are numbered from 1; any part of a record past the end of the file is zeros.  An invalid *record* is a "Bad record number" error (63).  `GET (x1,y1)-(x2,y2),array` is the [graphics GET](../device/graphics/#get).

### GOSUB

> GOSUB *label*

Calls the subroutine at the line with the specified label number; the subroutine ends with [RETURN](return/).

	GOSUB 100
	PRINT "Back"
	END
	100 PRINT "In subroutine"
	RETURN

### GOTO

> GOTO *label*

Transfers program control to the line with the specified label number.  See [GOTO](goto/).

### IF

> IF *expression* THEN *statement(s)* [ELSE *statement(s)*]

Executes statements based on the value of an expression.  See [IF](if/).

### INPUT {#input}

> INPUT [*prompt*;|,]*variable*[,*variable*]...  
> INPUT #*n*,*variable*[,*variable*]...

Reads the next item of file *n* (which must be open for INPUT) into each variable, as [READ](#read) does with DATA items.  Leading spaces, tabs, and line breaks are skipped, and an item ends at a comma or line break, or for a numeric variable, at a space or tab, too.  A quoted item ends at its closing quote, and can contain commas.  This means INPUT # can read back what PRINT # (or [WRITE](#write)) wrote.  Reading past the end of the file is an "Input past end" error (see [EOF](func/#eof)).

Without #*n*, INPUT displays the *prompt* (if any), followed by "? " (unless a comma follows the prompt), reads a line from the keyboard, and takes the items from that line the same way.  Unlike Microsoft BASIC, missing items are simply empty (or zero), and extra items are ignored, instead of displaying "Redo from start".

	INPUT "Name and age"; N$, A

### LET

> [LET] *variable*=*expression*

Assigns the value of an expression to a variable.  See [LET](let/).

### LINE INPUT {#line-input}

> LINE INPUT [*prompt*;]*variable$*  
> LINE INPUT #*n*,*variable$*

Reads the next line of file *n* (which must be open for INPUT), or without #*n*, displays the *prompt* (if any) and reads a line from the keyboard, into the string variable.  The line ends at a CR, LF, or CRLF, which isn't included.  A line longer than 255 characters is read 255 characters at a time.

### LSET {#lset}

> LSET *variable$*=*string*  
> RSET *variable$*=*string*

Sets the variable to *string*, left-justified (LSET) or right-justified (RSET), padded with spaces or truncated to the variable's [FIELD](#field) width (or if it isn't a FIELD variable, to its current length).  Use [MKI$, MKL$, and MKD$](func/#mki) to store numbers in fields, and [CVI, CVL, and CVD](func/#cvi) to convert them back.

### ON

> ON *expression* GOTO *label*[,*label*]...  
> ON *expression* GOSUB *label*[,*label*]...

Transfers program control to (or calls) the Nth label, where N is the value of the *expression*.  If N is zero or greater than the number of labels, the program continues with the next statement.

### ON ERROR

> ON ERROR GOTO *label*  
> ON ERROR GOTO 0

Transfers program control to the label when a runtime error occurs, where the [ERR](func/#err) function returns the error number, and [RESUME](#resume) continues the program.  ON ERROR GOTO 0 disables error handling.

Error numbers are the same as Microsoft BASIC's (eg, 5 for "Illegal function call", 7 for "Out of memory", and 9 for "Subscript out of range").

	ON ERROR GOTO 100
	ERROR 5
	END
	100 PRINT "Error"; ERR
	RESUME 200
	200 PRINT "Done"

### OPEN

> OPEN *file* [FOR INPUT|OUTPUT|APPEND|RANDOM] AS [#]*n* [LEN=*reclen*]

Opens *file* as file number *n* (1-4): FOR INPUT reads an existing file, FOR OUTPUT creates the file (or truncates it if it exists), and FOR APPEND adds to the end of the file (creating it if necessary).  FOR RANDOM (or no FOR at all) opens the file for random access (creating it if necessary), with records of *reclen* bytes (1-255; the default is 128), using [FIELD](#field), [GET #](#get), and [PUT #](#put).  Files that a program leaves open are closed when it ends.  A file can be open for INPUT more than once, but a file open for OUTPUT or APPEND can't be opened again, in this session or any other ("File already open").

A *file* that is only a drive letter and colon (eg, `"C:"`) opens the drive's entire volume, so that its sectors can be read (and written, FOR RANDOM) as records: with a record length of 128, for example, sector *n* begins at record *n* * 4 + 1.  A volume can be opened FOR INPUT only if no file on it is open for writing, and FOR RANDOM only if no file on it is open at all; while the volume is open, conflicting opens, as well as creating, deleting, or renaming files and directories on it, fail.  Since record numbers range from 1 to 65535, only the first 65535 records of a volume are accessible.

Errors are runtime errors that [ON ERROR](#on-error) can handle: "FIELD overflow" (50), "Bad file number" (52) for a number other than 1-4 or a file that isn't open, "File not found" (53), "Bad file mode" (54) for using a file in a way its mode doesn't allow (eg, reading a file opened for output), "File already open" (55), "Input past end" (62), "Bad record number" (63), and "Path/File access error" (75).  An invalid record length is an "Illegal function call" (5).

	OPEN "SCORES.DAT" FOR OUTPUT AS #1
	PRINT #1, "Alice"; 90
	CLOSE #1
	OPEN "SCORES.DAT" FOR INPUT AS #1
	WHILE NOT EOF(1)
	INPUT #1, N$, S
	PRINT N$, S
	WEND
	CLOSE

### OPTION BASE

> OPTION BASE 0|1

Sets the smallest subscript (0 or 1) of arrays dimensioned afterward.  The default is 0.

### POKE

> POKE *offset*,*value*

Stores *value* (0-255) at *offset* in the segment set by [DEF SEG](#def-seg).

### PRINT # {#print}

> PRINT #*n*,[*expression*][;|,][*expression*]...

Writes values to file *n* (which must be open for OUTPUT or APPEND) exactly as [PRINT](../device/screen/#print) would display them.

### PUT # {#put}

> PUT [#]*n*[,*record*]

Writes each [FIELD](#field) variable to its part of the specified record of random access file *n* (or the record after the last one used, if *record* is omitted), padded with spaces.  `PUT (x,y),array` is the [graphics PUT](../device/graphics/#put).

	OPEN "PHONES.DAT" AS #1 LEN=30
	FIELD #1, 20 AS N$, 10 AS P$
	LSET N$ = "Alice" : LSET P$ = "555-1234"
	PUT #1, 1
	GET #1, 1
	PRINT N$; P$
	CLOSE

### RANDOMIZE

> RANDOMIZE [*seed*]

Reseeds the random number generator (see [RND](func/#rnd)), so that the same *seed* always produces the same sequence of numbers.  Without a *seed*, the BIOS tick count is used (Microsoft BASIC would prompt for one instead).

### READ

> READ *variable*[,*variable*]...

Assigns the next [DATA](#data) item to each variable (or array element).  A numeric variable gets the item's numeric value (like [VAL](func/#val)), rounded if the variable is an integer.  Reading past the last item causes an "Out of DATA" error (error 4).

### REM

> REM *remark*  
> ' *remark*

Used for program remarks.  The rest of the line is not executed.  An apostrophe outside of quotes is the same as REM, and can follow other statements on the same line (eg, `POKE 106,0 'CLEAR KEYBOARD BUFFER`).

### RESTORE

> RESTORE [*line*]

Makes the first [DATA](#data) item the next item that [READ](#read) assigns, or with a *line* number, the first DATA item at or after that line (which must exist, or an "Undefined line number" error occurs).  Every program starts with RESTORE in effect.

### RESUME

> RESUME *label*

Ends the handling of a runtime error (see [ON ERROR](#on-error)) and continues at the specified label.  RESUME without a label and RESUME NEXT aren't supported yet.  The handler can use [ERR](func/#err) and [ERL](func/#erl) to find out which error occurred, and where.

### RETURN

> RETURN [*expression*]

Returns from a GOSUB subroutine, or ends a function block and returns the specified *expression*.  See [RETURN](return/).

### SWAP

> SWAP *variable1*,*variable2*

Exchanges the values of two variables (or array elements) of the same type.

### WHILE

> WHILE *expression*  
> *statement(s)*  
> WEND

Executes the statements up to the matching WEND repeatedly, as long as the *expression* is TRUE (non-zero).

	LET I = 1
	WHILE I < 100:PRINT I;:LET I = I * 2:WEND
	 1  2  4  8  16  32  64

### WRITE

> WRITE [#*n*,][*expression*[,*expression*]...]

Prints the values (or with #*n*, writes them to file *n*), separated by commas, with strings in quotes and numbers without leading or trailing spaces, and then ends the line, so that [INPUT #](#input) can read the values back (eg, `WRITE #1, "Smith, Jo", 42` writes `"Smith, Jo",42`).

{% include footer.html prev="BASIC-DOS Commands:../" next="DEF:def/" %}
