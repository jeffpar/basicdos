---
layout: sheet
title: BASIC Commands
permalink: /docs/bdman/cmd/basic/
---

{% include header.html %}

BASIC programs can use any BASIC-DOS [command](../) in combination with the BASIC statements described below, along with any of the [BASIC Functions](func/).  See [BASIC-DOS Programming](../../lang/) for an overview of programs, variables, and expressions.

- Variables and types: [CLEAR](#clear), [DEF](def/), [DEFDBL](#defdbl), [DEFINT](#defint), [DEFSNG](#defsng), [DEFSTR](#defstr), [DIM](#dim), [ERASE](#erase), [LET](let/), [OPTION BASE](#option-base)
- Control flow: [CHAIN](#chain), [END](#end), [FOR](#for)/[NEXT](#for), [GOSUB](#gosub), [GOTO](goto/), [IF](if/), [ON](#on), [RETURN](return/), [STOP](#end), [WHILE](#while)/[WEND](#while)
- Error handling: [ERROR](#error), [ON ERROR](#on-error), [RESUME](#resume)
- Data: [DATA](#data), [READ](#read), [RESTORE](#restore)
- Memory: [DEF SEG](#def-seg), [POKE](#poke)
- Remarks: [REM](#rem)

### CHAIN

> CHAIN *file*[,*line*]

Runs the specified BAS file and then ends the program.  The *line* is currently ignored, and other CHAIN options (eg, ALL and MERGE) are not supported.

### CLEAR

> CLEAR [[*n*][,[*m*][,*k*]]]

Resets all numeric variables to zero and all string variables to empty strings, and erases all arrays.  The values are accepted for compatibility with Microsoft BASIC, but are ignored.

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

Defines the first letter(s) of variables that will default to double-precision (64-bit) floating-point values (eg, `DEFDBL A-F,X`).  Variables default to double-precision unless DEFINT or DEFSTR is used (or floating-point support is disabled).

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

Ends the program.  STOP is currently the same as END.

### ERASE

> ERASE *array*[,*array*]...

Erases the specified arrays, so that they can be dimensioned again.  If the first name is not an array, ERASE is the same as [DEL](../disk/#del).

### ERROR

> ERROR *n*

Simulates error *n* (1-255).  If an [ON ERROR](#on-error) handler is active, it's called; otherwise, the program ends with an error message.

### FOR

> FOR *variable*=*start* TO *limit* [STEP *step*]  
> *statement(s)*  
> NEXT [*variable*[,*variable*]...]

Executes the statements up to the matching NEXT repeatedly, adding *step* (default 1) to the *variable* each time, until it passes the *limit*.  If the *start* is already past the *limit*, the statements are skipped.

NEXT without a *variable* ends the innermost FOR loop; otherwise, it ends the FOR loop for each *variable* listed.  FOR loops with integer variables (eg, after `DEFINT A-Z`) are much faster than those with floating-point variables.

	FOR I = 10 TO 1 STEP -3:PRINT I;:NEXT
	 10  7  4  1

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

### LET

> [LET] *variable*=*expression*

Assigns the value of an expression to a variable.  See [LET](let/).

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

### OPTION BASE

> OPTION BASE 0|1

Sets the smallest subscript (0 or 1) of arrays dimensioned afterward.  The default is 0.

### POKE

> POKE *offset*,*value*

Stores *value* (0-255) at *offset* in the segment set by [DEF SEG](#def-seg).

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

Ends the handling of a runtime error (see [ON ERROR](#on-error)) and continues at the specified label.  RESUME without a label and RESUME NEXT aren't supported yet.

### RETURN

> RETURN [*expression*]

Returns from a GOSUB subroutine, or ends a function block and returns the specified *expression*.  See [RETURN](return/).

### WHILE

> WHILE *expression*  
> *statement(s)*  
> WEND

Executes the statements up to the matching WEND repeatedly, as long as the *expression* is TRUE (non-zero).

	LET I = 1
	WHILE I < 100:PRINT I;:LET I = I * 2:WEND
	 1  2  4  8  16  32  64

{% include footer.html prev="BASIC-DOS Commands:../" next="DEF:def/" %}
