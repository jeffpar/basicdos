---
layout: post
title: Generation
date: 2026-10-23 11:00:00
permalink: /blog/2026/10/23/
---

Every BASIC program that BASIC-DOS runs is compiled into 8086 code, and that code is generated and executed one line at a time.  To illustrate the process, I ran [PRIMES.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/tests/primes/PRIMES.BAS) with breakpoints in the code generator, and captured the code and the variables that each line produced.

Here's the program.  It prints the primes below 1000 (or below the number on its command line), by trial division with odd divisors up to the square root of each candidate:

    10 defint a-z
    11 let limit=val(arg$(1))
    13 if limit=0 then let limit=1000
    14 let maxdivisor=2:let maxsquared=4:let advsquared=5:let primes=0:let printed=0:let dividend=2
    15 let divisor=3
    20 if divisor >= maxdivisor then goto 30
    21 if dividend mod divisor = 0 then goto 40
    22 let divisor = divisor+2:goto 20
    30 print dividend;:let printed = printed+1
    31 let primes=primes+1
    32 if printed < 5 then goto 40
    33 print:let printed=0
    40 let dividend = (dividend+1) or 1
    41 if dividend >= limit then goto 90
    50 if dividend < maxsquared then goto 15
    51 let maxdivisor = maxdivisor+1
    52 let maxsquared = maxsquared+advsquared
    53 let advsquared = advsquared+2
    55 goto 15
    90 print:print "TOTAL PRIMES < ";mid$(str$(limit),2);": ";primes

### How to Read the Boxes

Each line of the program appears below, followed by two boxes.  When a line has more than one command, a blank line separates the code for each command.  The box on the left is the code generated for the line, disassembled from the program's code block (segment 3DFF in this run).  The box on the right is a dump of the program's variable block (segment 3CFE), taken right after the line was generated but *before* it ran, so the variables hold whatever the previous lines left in them.  Bytes that changed since the previous line are highlighted.

When the generated code runs, CS is the code block, DS is the variable block, and SS is COMMAND.COM's stack.  So a variable is just a 16-bit offset in DS, which the generator knows as soon as it adds the variable to the block.  Everything else the code needs is a far call away, either in COMMAND.COM (segment 0967), whose functions I've labeled using COMMAND.MAP, or in the FPU$ driver (segment 029B), which does all the floating-point work.

The variable block starts with an 8-byte header: the next block in the chain (0000), the size of the block (1000h), the offset of the next free byte, and a signature ('V').  Each variable starts with a byte that combines its type (40h for an integer) with the length of its name, followed by the name (in upper case) and the variable's data, which is 4 bytes for an integer.

The generated code is stack-based.  Every value on the stack is 4 bytes: either a 32-bit integer (with the low word on top) or a far pointer to a string or a double.  A variable is pushed with MOV SI and a pair of LODSW instructions, a constant is pushed with MOV AX and CWD, and each operator is a far call to a function like `evalAddLong`, which pops two values and pushes the result.

### The Starting Point

When you type PRIMES, COMMAND.COM loads PRIMES.BAS and calls `genCode`, which allocates a 4K code block and generates exactly two instructions:

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>000A  89E5        MOV   BP,SP
000C  9A2B326709  CALL  0967:322B   ; genMore</pre></div>
</div>

The CALL is a *cap*, marking the end of the code generated so far.  `genCode` calls the code block, and the cap calls `genMore`, which generates lines until the cap has been overwritten, adds a new cap at the end, and returns to the address of the old one, which is now the start of the new code.

The same trick works for any jump whose target hasn't been generated yet: the generator fills the jump's 5 bytes with a CALL to `genMore`, and if the program reaches it first, `genMore` generates lines until the jump has been patched.  The MOV BP,SP, by the way, gives END an easy way to reset the stack and return.

#### `10 defint a-z`

DEFINT generates no code at all; it just tells the generator that every variable from A to Z is a 32-bit integer (or a *long*, as BASIC-DOS calls it).  The cap is still in place, so `genMore` moves on to the next line.  There isn't even a variable block yet, since one isn't allocated until the first variable is added.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>(no code)</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>(no variables yet)</pre></div>
</div>

#### `11 let limit=val(arg$(1))`

The first real code overwrites the cap at 000C.  LET pushes the address of LIMIT, which the generator has just added to the variable block (with a value of zero), and then the expression is generated from the outside in.  VAL returns a double, and since doubles are always passed by reference, the generator reserves an 8-byte slot inside the code (the JMP SHORT skips over it) and pushes the slot's address as VAL's return value.  ARG$ returns a string, so two PUSH AX instructions reserve 4 bytes for its result (what's pushed doesn't matter), followed by ARG$'s parameter, 1.

Then come the calls: `strArg` (ARG$) pops its parameter and leaves a string in the space reserved for it, `strVal` (VAL) pops that string and stores its value in the slot, FPU_CVT1DL replaces the pointer to the slot with the equivalent long (since LIMIT is an integer), and `setVarLong` pops the long and the address of LIMIT, and stores one at the other.

`genMore` sees that the cap has been overwritten, so it adds a new cap at 003C and returns to 000C, and line 11 runs for the first time.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>000C  1E          PUSH  DS
000D  B80E00      MOV   AX,000E     ; LIMIT
0010  50          PUSH  AX
0011  EB08        JMP   SHORT 001B
0013  00000000    DQ    0           ; slot
      00000000
001B  0E          PUSH  CS
001C  B81300      MOV   AX,0013     ; slot
001F  50          PUSH  AX
0020  50          PUSH  AX
0021  50          PUSH  AX
0022  B80100      MOV   AX,0001
0025  99          CWD
0026  52          PUSH  DX
0027  50          PUSH  AX
0028  9A9F686709  CALL  0967:689F   ; strArg
002D  9A546B6709  CALL  0967:6B54   ; strVal
0032  9A04029B02  CALL  029B:0204   ; FPU_CVT1DL
0037  9A5F616709  CALL  0967:615F   ; setVarLong</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  <span class="cg-hl">00</span> <span class="cg-hl">00</span> <span class="cg-hl">00</span> <span class="cg-hl">10</span> <span class="cg-hl">12</span> <span class="cg-hl">00</span> <span class="cg-hl">56</span> <span class="cg-hl">00</span>  ......V.
0008  <span class="cg-hl">45</span> <span class="cg-hl">4C</span> <span class="cg-hl">49</span> <span class="cg-hl">4D</span> <span class="cg-hl">49</span> <span class="cg-hl">54</span> <span class="cg-hl">00</span> <span class="cg-hl">00</span>  ELIMIT..
0010  <span class="cg-hl">00</span> <span class="cg-hl">00</span> <span class="cg-hl">00</span>                 ...</pre></div>
</div>

#### `13 if limit=0 then let limit=1000`

When line 11 finishes, the program reaches the cap at 003C, and `genMore` generates line 13.  LIMIT is still zero, since PRIMES was run without an argument.  IF generates its expression (`evalEQLong` leaves -1 if the values are equal and 0 if not), pops the result into DX:AX, and jumps to the THEN block if it's non-zero; otherwise, the JMP skips the block.

That JMP started out as a 5-byte placeholder (a CALL to `genMore`), because a block can continue in another code block, which would require a 5-byte far JMP.  Once the THEN block was generated, the placeholder was patched with a 3-byte near JMP, leaving the last 2 bytes of the CALL (67 09, the segment of `genMore`) behind, where they'll never run.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>003C  BE0E00      MOV   SI,000E     ; LIMIT
003F  AD          LODSW
0040  92          XCHG  AX,DX
0041  AD          LODSW
0042  50          PUSH  AX
0043  52          PUSH  DX
0044  31C0        XOR   AX,AX
0046  50          PUSH  AX
0047  50          PUSH  AX
0048  9AAE5F6709  CALL  0967:5FAE   ; evalEQLong
004D  58          POP   AX
004E  5A          POP   DX
004F  09D0        OR    AX,DX
0051  7505        JNZ   0058
0053  E91200      JMP   0068
0056  6709        DB    67,09       ; unused
0058  1E          PUSH  DS
0059  B80E00      MOV   AX,000E     ; LIMIT
005C  50          PUSH  AX
005D  B8E803      MOV   AX,03E8     ; 1000
0060  99          CWD
0061  52          PUSH  DX
0062  50          PUSH  AX
0063  9A5F616709  CALL  0967:615F   ; setVarLong</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 12 00 56 00  ......V.
0008  45 4C 49 4D 49 54 00 00  ELIMIT..
0010  00 00 00                 ...</pre></div>
</div>

#### `14 let maxdivisor=2:let maxsquared=4:let advsquared=5:let primes=0:let printed=0:let dividend=2`

Six LET commands, six new variables, and six calls to `setVarLong`.  Each constant is pushed with MOV AX, CWD (which sign-extends AX into DX), PUSH DX, and PUSH AX, except for zero, which takes a shorter XOR AX,AX.  And since line 13 found LIMIT equal to zero, it's now 1000 (E8 03 00 00).

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>0068  1E          PUSH  DS
0069  B81D00      MOV   AX,001D     ; MAXDIVISOR
006C  50          PUSH  AX
006D  B80200      MOV   AX,0002
0070  99          CWD
0071  52          PUSH  DX
0072  50          PUSH  AX
0073  9A5F616709  CALL  0967:615F   ; setVarLong

0078  1E          PUSH  DS
0079  B82C00      MOV   AX,002C     ; MAXSQUARED
007C  50          PUSH  AX
007D  B80400      MOV   AX,0004
0080  99          CWD
0081  52          PUSH  DX
0082  50          PUSH  AX
0083  9A5F616709  CALL  0967:615F   ; setVarLong

0088  1E          PUSH  DS
0089  B83B00      MOV   AX,003B     ; ADVSQUARED
008C  50          PUSH  AX
008D  B80500      MOV   AX,0005
0090  99          CWD
0091  52          PUSH  DX
0092  50          PUSH  AX
0093  9A5F616709  CALL  0967:615F   ; setVarLong

0098  1E          PUSH  DS
0099  B84600      MOV   AX,0046     ; PRIMES
009C  50          PUSH  AX
009D  31C0        XOR   AX,AX
009F  50          PUSH  AX
00A0  50          PUSH  AX
00A1  9A5F616709  CALL  0967:615F   ; setVarLong

00A6  1E          PUSH  DS
00A7  B85200      MOV   AX,0052     ; PRINTED
00AA  50          PUSH  AX
00AB  31C0        XOR   AX,AX
00AD  50          PUSH  AX
00AE  50          PUSH  AX
00AF  9A5F616709  CALL  0967:615F   ; setVarLong

00B4  1E          PUSH  DS
00B5  B85F00      MOV   AX,005F     ; DIVIDEND
00B8  50          PUSH  AX
00B9  B80200      MOV   AX,0002
00BC  99          CWD
00BD  52          PUSH  DX
00BE  50          PUSH  AX
00BF  9A5F616709  CALL  0967:615F   ; setVarLong</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 <span class="cg-hl">63</span> 00 56 00  ....c.V.
0008  45 4C 49 4D 49 54 <span class="cg-hl">E8</span> <span class="cg-hl">03</span>  ELIMIT..
0010  00 00 <span class="cg-hl">4A</span> <span class="cg-hl">4D</span> <span class="cg-hl">41</span> <span class="cg-hl">58</span> <span class="cg-hl">44</span> <span class="cg-hl">49</span>  ..JMAXDI
0018  <span class="cg-hl">56</span> <span class="cg-hl">49</span> <span class="cg-hl">53</span> <span class="cg-hl">4F</span> <span class="cg-hl">52</span> 00 00 00  VISOR...
0020  00 <span class="cg-hl">4A</span> <span class="cg-hl">4D</span> <span class="cg-hl">41</span> <span class="cg-hl">58</span> <span class="cg-hl">53</span> <span class="cg-hl">51</span> <span class="cg-hl">55</span>  .JMAXSQU
0028  <span class="cg-hl">41</span> <span class="cg-hl">52</span> <span class="cg-hl">45</span> <span class="cg-hl">44</span> 00 00 00 00  ARED....
0030  <span class="cg-hl">4A</span> <span class="cg-hl">41</span> <span class="cg-hl">44</span> <span class="cg-hl">56</span> <span class="cg-hl">53</span> <span class="cg-hl">51</span> <span class="cg-hl">55</span> <span class="cg-hl">41</span>  JADVSQUA
0038  <span class="cg-hl">52</span> <span class="cg-hl">45</span> <span class="cg-hl">44</span> 00 00 00 00 <span class="cg-hl">46</span>  RED....F
0040  <span class="cg-hl">50</span> <span class="cg-hl">52</span> <span class="cg-hl">49</span> <span class="cg-hl">4D</span> <span class="cg-hl">45</span> <span class="cg-hl">53</span> 00 00  PRIMES..
0048  00 00 <span class="cg-hl">47</span> <span class="cg-hl">50</span> <span class="cg-hl">52</span> <span class="cg-hl">49</span> <span class="cg-hl">4E</span> <span class="cg-hl">54</span>  ..GPRINT
0050  <span class="cg-hl">45</span> <span class="cg-hl">44</span> 00 00 00 00 <span class="cg-hl">48</span> <span class="cg-hl">44</span>  ED....HD
0058  <span class="cg-hl">49</span> <span class="cg-hl">56</span> <span class="cg-hl">49</span> <span class="cg-hl">44</span> <span class="cg-hl">45</span> <span class="cg-hl">4E</span> <span class="cg-hl">44</span> 00  IVIDEND.
0060  00 00 00 00              ....</pre></div>
</div>

#### `15 let divisor=3`

The values that line 14 assigned are now in the dump, and DIVISOR is the last variable the program will add.  Its data is at offset 006B, which is all the code ever needs to know about it.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>00C4  1E          PUSH  DS
00C5  B86B00      MOV   AX,006B     ; DIVISOR
00C8  50          PUSH  AX
00C9  B80300      MOV   AX,0003
00CC  99          CWD
00CD  52          PUSH  DX
00CE  50          PUSH  AX
00CF  9A5F616709  CALL  0967:615F   ; setVarLong</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 <span class="cg-hl">6F</span> 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 <span class="cg-hl">02</span> 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 <span class="cg-hl">04</span> 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 <span class="cg-hl">05</span> 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 00 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 00 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 <span class="cg-hl">02</span>  IVIDEND.
0060  00 00 00 <span class="cg-hl">47</span> <span class="cg-hl">44</span> <span class="cg-hl">49</span> <span class="cg-hl">56</span> <span class="cg-hl">49</span>  ...GDIVI
0068  <span class="cg-hl">53</span> <span class="cg-hl">4F</span> <span class="cg-hl">52</span> 00 00 00 00 00  SOR.....</pre></div>
</div>

#### `20 if divisor >= maxdivisor then goto 30`

Line 30 hasn't been generated yet, so GOTO 30 is a forward reference: the generator adds it to a table of labels (see [Labels](#labels) below) and leaves a placeholder at 00F4.  And as it happens, DIVISOR (3) is greater than MAXDIVISOR (2), so as soon as line 20 runs, it calls `genMore` from that placeholder.  This time, `genMore` can't stop after the next line; it has to keep going until a line defines label 30 and the placeholder gets patched.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>00D4  BE6B00      MOV   SI,006B     ; DIVISOR
00D7  AD          LODSW
00D8  92          XCHG  AX,DX
00D9  AD          LODSW
00DA  50          PUSH  AX
00DB  52          PUSH  DX
00DC  BE1D00      MOV   SI,001D     ; MAXDIVISOR
00DF  AD          LODSW
00E0  92          XCHG  AX,DX
00E1  AD          LODSW
00E2  50          PUSH  AX
00E3  52          PUSH  DX
00E4  9A1E606709  CALL  0967:601E   ; evalGELong
00E9  58          POP   AX
00EA  5A          POP   DX
00EB  09D0        OR    AX,DX
00ED  7505        JNZ   00F4
00EF  E90700      JMP   00F9
00F2  6709        DB    67,09       ; unused
00F4  9A2B326709  CALL  0967:322B   ; genMore</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 02 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 00 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 00 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 02  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 <span class="cg-hl">03</span> 00 00 00 00  SOR.....</pre></div>
</div>

#### `21 if dividend mod divisor = 0 then goto 40`

This line is generated only because line 20 jumped ahead; it won't actually run until DIVIDEND reaches 9.  `evalModLong` and `evalEQLong` do the work, and another forward GOTO leaves another placeholder, at 0122.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>00F9  BE5F00      MOV   SI,005F     ; DIVIDEND
00FC  AD          LODSW
00FD  92          XCHG  AX,DX
00FE  AD          LODSW
00FF  50          PUSH  AX
0100  52          PUSH  DX
0101  BE6B00      MOV   SI,006B     ; DIVISOR
0104  AD          LODSW
0105  92          XCHG  AX,DX
0106  AD          LODSW
0107  50          PUSH  AX
0108  52          PUSH  DX
0109  9A925E6709  CALL  0967:5E92   ; evalModLong
010E  31C0        XOR   AX,AX
0110  50          PUSH  AX
0111  50          PUSH  AX
0112  9AAE5F6709  CALL  0967:5FAE   ; evalEQLong
0117  58          POP   AX
0118  5A          POP   DX
0119  09D0        OR    AX,DX
011B  7505        JNZ   0122
011D  E90700      JMP   0127
0120  6709        DB    67,09       ; unused
0122  9A2B326709  CALL  0967:322B   ; genMore</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 02 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 00 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 00 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 02  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

#### `22 let divisor = divisor+2:goto 20`

GOTO 20 is a backward reference, so the generator knows the address (00D4) and generates a JMP right away, followed by two NOPs, because every GOTO occupies 5 bytes (enough for a far JMP).  The placeholder at 00F4 is still waiting, so `genMore` keeps going.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>0127  1E          PUSH  DS
0128  B86B00      MOV   AX,006B     ; DIVISOR
012B  50          PUSH  AX
012C  BE6B00      MOV   SI,006B     ; DIVISOR
012F  AD          LODSW
0130  92          XCHG  AX,DX
0131  AD          LODSW
0132  50          PUSH  AX
0133  52          PUSH  DX
0134  B80200      MOV   AX,0002
0137  99          CWD
0138  52          PUSH  DX
0139  50          PUSH  AX
013A  9A3C5D6709  CALL  0967:5D3C   ; evalAddLong
013F  9A5F616709  CALL  0967:615F   ; setVarLong

0144  E98DFF      JMP   00D4
0147  90          NOP
0148  90          NOP</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 02 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 00 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 00 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 02  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

#### `30 print dividend;:let printed = printed+1`

PRINT pushes an end marker (VAR_NONE), followed by each value, its type (VAR_LONG), and the separator that follows it (VAR_SEMI); `printArgs` then walks the stack back to the marker and prints the values in order, ending with a new line unless the last item is a separator.

More importantly, line 30 is the line that GOTO 30 was waiting for.  When the generator defined label 30, it found the pending reference and replaced the CALL at 00F4 with a JMP to 0149 (leaving 2 unused bytes again).  So `genMore` stops here, caps the code at 017C, and returns to 00F4, which now jumps to line 30.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>0149  B000        MOV   AL,00       ; VAR_NONE
014B  50          PUSH  AX
014C  BE5F00      MOV   SI,005F     ; DIVIDEND
014F  AD          LODSW
0150  92          XCHG  AX,DX
0151  AD          LODSW
0152  50          PUSH  AX
0153  52          PUSH  DX
0154  B040        MOV   AL,40       ; VAR_LONG
0156  50          PUSH  AX
0157  B002        MOV   AL,02       ; VAR_SEMI
0159  50          PUSH  AX
015A  9A165A6709  CALL  0967:5A16   ; printArgs

015F  1E          PUSH  DS
0160  B85200      MOV   AX,0052     ; PRINTED
0163  50          PUSH  AX
0164  BE5200      MOV   SI,0052     ; PRINTED
0167  AD          LODSW
0168  92          XCHG  AX,DX
0169  AD          LODSW
016A  50          PUSH  AX
016B  52          PUSH  DX
016C  B80100      MOV   AX,0001
016F  99          CWD
0170  52          PUSH  DX
0171  50          PUSH  AX
0172  9A3C5D6709  CALL  0967:5D3C   ; evalAddLong
0177  9A5F616709  CALL  0967:615F   ; setVarLong</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 02 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 00 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 00 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 02  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

<div class="codegen">
<div><div class="cg-title">Placeholder before</div><pre>00F4  9A2B326709  CALL  0967:322B   ; genMore</pre></div>
<div><div class="cg-title">Placeholder after</div><pre>00F4  E95200      JMP   0149
00F7  6709        DB    67,09       ; unused</pre></div>
</div>

#### `31 let primes=primes+1`

Line 30 has run once by now (printing 2), so PRINTED is 1.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>017C  1E          PUSH  DS
017D  B84600      MOV   AX,0046     ; PRIMES
0180  50          PUSH  AX
0181  BE4600      MOV   SI,0046     ; PRIMES
0184  AD          LODSW
0185  92          XCHG  AX,DX
0186  AD          LODSW
0187  50          PUSH  AX
0188  52          PUSH  DX
0189  B80100      MOV   AX,0001
018C  99          CWD
018D  52          PUSH  DX
018E  50          PUSH  AX
018F  9A3C5D6709  CALL  0967:5D3C   ; evalAddLong
0194  9A5F616709  CALL  0967:615F   ; setVarLong</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 02 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 00 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 <span class="cg-hl">01</span> 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 02  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

#### `32 if printed < 5 then goto 40`

Another forward GOTO, another placeholder (at 01B7), and since PRINTED (1) is less than 5, another jump straight into it, so `genMore` generates line 33 and then line 40.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>0199  BE5200      MOV   SI,0052     ; PRINTED
019C  AD          LODSW
019D  92          XCHG  AX,DX
019E  AD          LODSW
019F  50          PUSH  AX
01A0  52          PUSH  DX
01A1  B80500      MOV   AX,0005
01A4  99          CWD
01A5  52          PUSH  DX
01A6  50          PUSH  AX
01A7  9A0F606709  CALL  0967:600F   ; evalLTLong
01AC  58          POP   AX
01AD  5A          POP   DX
01AE  09D0        OR    AX,DX
01B0  7505        JNZ   01B7
01B2  E90700      JMP   01BC
01B5  6709        DB    67,09       ; unused
01B7  9A2B326709  CALL  0967:322B   ; genMore</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 02 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 <span class="cg-hl">01</span> 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 01 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 02  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

#### `33 print:let printed=0`

A PRINT without any values is just the end marker and a call to `printArgs`, which prints a new line.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>01BC  B000        MOV   AL,00       ; VAR_NONE
01BE  50          PUSH  AX
01BF  9A165A6709  CALL  0967:5A16   ; printArgs

01C4  1E          PUSH  DS
01C5  B85200      MOV   AX,0052     ; PRINTED
01C8  50          PUSH  AX
01C9  31C0        XOR   AX,AX
01CB  50          PUSH  AX
01CC  50          PUSH  AX
01CD  9A5F616709  CALL  0967:615F   ; setVarLong</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 02 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 01 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 01 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 02  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

#### `40 let dividend = (dividend+1) or 1`

OR is just another operator (`evalOrLong`).  Defining label 40 resolves two references at once: the placeholders in line 21 (at 0122) and line 32 (at 01B7).

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>01D2  1E          PUSH  DS
01D3  B85F00      MOV   AX,005F     ; DIVIDEND
01D6  50          PUSH  AX
01D7  BE5F00      MOV   SI,005F     ; DIVIDEND
01DA  AD          LODSW
01DB  92          XCHG  AX,DX
01DC  AD          LODSW
01DD  50          PUSH  AX
01DE  52          PUSH  DX
01DF  B80100      MOV   AX,0001
01E2  99          CWD
01E3  52          PUSH  DX
01E4  50          PUSH  AX
01E5  9A3C5D6709  CALL  0967:5D3C   ; evalAddLong
01EA  B80100      MOV   AX,0001
01ED  99          CWD
01EE  52          PUSH  DX
01EF  50          PUSH  AX
01F0  9A885F6709  CALL  0967:5F88   ; evalOrLong
01F5  9A5F616709  CALL  0967:615F   ; setVarLong</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 02 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 01 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 01 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 02  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

<div class="codegen">
<div><div class="cg-title">Placeholder before</div><pre>0122  9A2B326709  CALL  0967:322B   ; genMore
01B7  9A2B326709  CALL  0967:322B   ; genMore</pre></div>
<div><div class="cg-title">Placeholder after</div><pre>0122  E9AD00      JMP   01D2
0125  6709        DB    67,09       ; unused
01B7  E91800      JMP   01D2
01BA  6709        DB    67,09       ; unused</pre></div>
</div>

#### `41 if dividend >= limit then goto 90`

The placeholder at 021A won't be called until DIVIDEND reaches 1001, so for now, the program simply falls into the cap at 021F.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>01FA  BE5F00      MOV   SI,005F     ; DIVIDEND
01FD  AD          LODSW
01FE  92          XCHG  AX,DX
01FF  AD          LODSW
0200  50          PUSH  AX
0201  52          PUSH  DX
0202  BE0E00      MOV   SI,000E     ; LIMIT
0205  AD          LODSW
0206  92          XCHG  AX,DX
0207  AD          LODSW
0208  50          PUSH  AX
0209  52          PUSH  DX
020A  9A1E606709  CALL  0967:601E   ; evalGELong
020F  58          POP   AX
0210  5A          POP   DX
0211  09D0        OR    AX,DX
0213  7505        JNZ   021A
0215  E90700      JMP   021F
0218  6709        DB    67,09       ; unused
021A  9A2B326709  CALL  0967:322B   ; genMore</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 02 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 01 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 01 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 <span class="cg-hl">03</span>  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

#### `50 if dividend < maxsquared then goto 15`

GOTO 15 is a backward reference, so the THEN block is a JMP to 00C4 (plus the usual NOPs).  DIVIDEND (3) is less than MAXSQUARED (4), so the program loops back to line 15, running only code it already has, until DIVIDEND becomes 5 and the program finally falls into the cap at 0244.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>021F  BE5F00      MOV   SI,005F     ; DIVIDEND
0222  AD          LODSW
0223  92          XCHG  AX,DX
0224  AD          LODSW
0225  50          PUSH  AX
0226  52          PUSH  DX
0227  BE2C00      MOV   SI,002C     ; MAXSQUARED
022A  AD          LODSW
022B  92          XCHG  AX,DX
022C  AD          LODSW
022D  50          PUSH  AX
022E  52          PUSH  DX
022F  9A0F606709  CALL  0967:600F   ; evalLTLong
0234  58          POP   AX
0235  5A          POP   DX
0236  09D0        OR    AX,DX
0238  7505        JNZ   023F
023A  E90700      JMP   0244
023D  6709        DB    67,09       ; unused
023F  E982FE      JMP   00C4
0242  90          NOP
0243  90          NOP</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 02 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 01 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 01 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 03  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

#### `51 let maxdivisor = maxdivisor+1`

DIVIDEND is 5 now, and PRIMES and PRINTED are both 2.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>0244  1E          PUSH  DS
0245  B81D00      MOV   AX,001D     ; MAXDIVISOR
0248  50          PUSH  AX
0249  BE1D00      MOV   SI,001D     ; MAXDIVISOR
024C  AD          LODSW
024D  92          XCHG  AX,DX
024E  AD          LODSW
024F  50          PUSH  AX
0250  52          PUSH  DX
0251  B80100      MOV   AX,0001
0254  99          CWD
0255  52          PUSH  DX
0256  50          PUSH  AX
0257  9A3C5D6709  CALL  0967:5D3C   ; evalAddLong
025C  9A5F616709  CALL  0967:615F   ; setVarLong</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 02 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 <span class="cg-hl">02</span> 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 <span class="cg-hl">02</span> 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 <span class="cg-hl">05</span>  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

#### `52 let maxsquared = maxsquared+advsquared`

Adding one variable to another is just two pushes and a call to `evalAddLong`.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>0261  1E          PUSH  DS
0262  B82C00      MOV   AX,002C     ; MAXSQUARED
0265  50          PUSH  AX
0266  BE2C00      MOV   SI,002C     ; MAXSQUARED
0269  AD          LODSW
026A  92          XCHG  AX,DX
026B  AD          LODSW
026C  50          PUSH  AX
026D  52          PUSH  DX
026E  BE3B00      MOV   SI,003B     ; ADVSQUARED
0271  AD          LODSW
0272  92          XCHG  AX,DX
0273  AD          LODSW
0274  50          PUSH  AX
0275  52          PUSH  DX
0276  9A3C5D6709  CALL  0967:5D3C   ; evalAddLong
027B  9A5F616709  CALL  0967:615F   ; setVarLong</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 <span class="cg-hl">03</span> 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 04 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 02 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 02 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 05  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

#### `53 let advsquared = advsquared+2`

MAXSQUARED is now 9, the next square after 4.  Adding successive odd numbers (ADVSQUARED) to it keeps it a perfect square without any multiplication.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>0280  1E          PUSH  DS
0281  B83B00      MOV   AX,003B     ; ADVSQUARED
0284  50          PUSH  AX
0285  BE3B00      MOV   SI,003B     ; ADVSQUARED
0288  AD          LODSW
0289  92          XCHG  AX,DX
028A  AD          LODSW
028B  50          PUSH  AX
028C  52          PUSH  DX
028D  B80200      MOV   AX,0002
0290  99          CWD
0291  52          PUSH  DX
0292  50          PUSH  AX
0293  9A3C5D6709  CALL  0967:5D3C   ; evalAddLong
0298  9A5F616709  CALL  0967:615F   ; setVarLong</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 03 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 <span class="cg-hl">09</span> 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 05 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 02 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 02 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 05  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

#### `55 goto 15`

A line with nothing but a backward GOTO is just a JMP and two NOPs.  At this point, every line except line 90 has been generated, and the program runs entirely in the code it has, until DIVIDEND passes 1000.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>029D  E924FE      JMP   00C4
02A0  90          NOP
02A1  90          NOP</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 03 00 00  VISOR...
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 09 00 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 <span class="cg-hl">07</span> 00 00 00 46  RED....F
0040  50 52 49 4D 45 53 02 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 02 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 05  IVIDEND.
0060  00 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

#### `90 print:print "TOTAL PRIMES < ";mid$(str$(limit),2);": ";primes`

Line 90 is generated last, when DIVIDEND finally reaches 1001 and line 41 calls `genMore` from its placeholder at 021A.  By then, PRIMES is 168 (A8 00 00 00).

String constants are stored in the code, too: PUSH CS, followed by a CALL over a length-prefixed string, pushes the far address of the string, since a CALL pushes the address of the byte that follows it.  MID$ and STR$ each get 4 bytes for their results, and since STR$ takes a double, LIMIT is converted by FPU_CVT1LD into another 8-byte slot, which ES:DI points to.  MID$'s length is omitted, so the generator pushes -2, which `strMid` takes to mean "the rest of the string."

When line 90 finishes, the program reaches the cap at 0320 one last time.  There are no more lines, so `genMore` replaces the cap with a RETF and returns to it, and the program returns to `genCode`.

<div class="codegen">
<div><div class="cg-title">Code (3DFF)</div><pre>02A2  B000        MOV   AL,00       ; VAR_NONE
02A4  50          PUSH  AX
02A5  9A165A6709  CALL  0967:5A16   ; printArgs

02AA  B000        MOV   AL,00       ; VAR_NONE
02AC  50          PUSH  AX
02AD  0E          PUSH  CS
02AE  E81000      CALL  02C1
02B1  0F544F54    DB    15,"TOTAL PRIMES &lt; "
      414C2050
      52494D45
      53203C20
02C1  B060        MOV   AL,60       ; VAR_STR
02C3  50          PUSH  AX
02C4  B002        MOV   AL,02       ; VAR_SEMI
02C6  50          PUSH  AX
02C7  50          PUSH  AX
02C8  50          PUSH  AX
02C9  50          PUSH  AX
02CA  50          PUSH  AX
02CB  BE0E00      MOV   SI,000E     ; LIMIT
02CE  AD          LODSW
02CF  92          XCHG  AX,DX
02D0  AD          LODSW
02D1  50          PUSH  AX
02D2  52          PUSH  DX
02D3  EB08        JMP   SHORT 02DD
02D5  00000000    DQ    0           ; slot
      00000000
02DD  0E          PUSH  CS
02DE  07          POP   ES
02DF  BFD502      MOV   DI,02D5
02E2  9A4A029B02  CALL  029B:024A   ; FPU_CVT1LD
02E7  9A866A6709  CALL  0967:6A86   ; strStr
02EC  B80200      MOV   AX,0002
02EF  99          CWD
02F0  52          PUSH  DX
02F1  50          PUSH  AX
02F2  B8FEFF      MOV   AX,FFFE     ; -2
02F5  99          CWD
02F6  52          PUSH  DX
02F7  50          PUSH  AX
02F8  9ACE696709  CALL  0967:69CE   ; strMid
02FD  B060        MOV   AL,60       ; VAR_STR
02FF  50          PUSH  AX
0300  B002        MOV   AL,02       ; VAR_SEMI
0302  50          PUSH  AX
0303  0E          PUSH  CS
0304  E80300      CALL  030A
0307  023A20      DB    2,": "
030A  B060        MOV   AL,60       ; VAR_STR
030C  50          PUSH  AX
030D  B002        MOV   AL,02       ; VAR_SEMI
030F  50          PUSH  AX
0310  BE4600      MOV   SI,0046     ; PRIMES
0313  AD          LODSW
0314  92          XCHG  AX,DX
0315  AD          LODSW
0316  50          PUSH  AX
0317  52          PUSH  DX
0318  B040        MOV   AL,40       ; VAR_LONG
031A  50          PUSH  AX
031B  9A165A6709  CALL  0967:5A16   ; printArgs</pre></div>
<div><div class="cg-title">Variables (3CFE)</div><pre>0000  00 00 00 10 6F 00 56 00  ....o.V.
0008  45 4C 49 4D 49 54 E8 03  ELIMIT..
0010  00 00 4A 4D 41 58 44 49  ..JMAXDI
0018  56 49 53 4F 52 <span class="cg-hl">20</span> 00 00  VISOR ..
0020  00 4A 4D 41 58 53 51 55  .JMAXSQU
0028  41 52 45 44 <span class="cg-hl">00</span> <span class="cg-hl">04</span> 00 00  ARED....
0030  4A 41 44 56 53 51 55 41  JADVSQUA
0038  52 45 44 <span class="cg-hl">41</span> 00 00 00 46  REDA...F
0040  50 52 49 4D 45 53 <span class="cg-hl">A8</span> 00  PRIMES..
0048  00 00 47 50 52 49 4E 54  ..GPRINT
0050  45 44 <span class="cg-hl">03</span> 00 00 00 48 44  ED....HD
0058  49 56 49 44 45 4E 44 <span class="cg-hl">E9</span>  IVIDEND.
0060  <span class="cg-hl">03</span> 00 00 47 44 49 56 49  ...GDIVI
0068  53 4F 52 03 00 00 00 00  SOR.....</pre></div>
</div>

<div class="codegen">
<div><div class="cg-title">Placeholder before</div><pre>021A  9A2B326709  CALL  0967:322B   ; genMore</pre></div>
<div><div class="cg-title">Placeholder after</div><pre>021A  E98500      JMP   02A2
021D  6709        DB    67,09       ; unused</pre></div>
</div>

### The Timeline

Here's every call to `genMore`, in order, along with the placeholder it was called from and the lines it generated.  Most calls come from the cap at the end of the code, because the program simply ran off the end of what had been generated; the others come from forward GOTOs that the program reached before their target lines existed.

| Call | From | Placeholder | Lines Generated |
|:----:|:----:|:------------|:----------------|
| 1 | 000C | cap | 10, 11 |
| 2 | 003C | cap | 13 |
| 3 | 0068 | cap | 14 |
| 4 | 00C4 | cap | 15 |
| 5 | 00D4 | cap | 20 |
| 6 | 00F4 | GOTO in line 20 | 21, 22, 30 |
| 7 | 017C | cap | 31 |
| 8 | 0199 | cap | 32 |
| 9 | 01B7 | GOTO in line 32 | 33, 40 |
| 10 | 01FA | cap | 41 |
| 11 | 021F | cap | 50 |
| 12 | 0244 | cap | 51 |
| 13 | 0261 | cap | 52 |
| 14 | 0280 | cap | 53 |
| 15 | 029D | cap | 55 |
| 16 | 021A | GOTO in line 41 | 90 |
| 17 | 0320 | cap | none (RETF) |

### Labels

Every numbered line also adds a label to a table at the end of the code block, which grows down from the end of the block (the word at offset 0008 of the block points to the bottom).  Each entry is 4 bytes: a line number, followed by the offset of its code.  A forward reference adds an entry with the high bit of the offset (LBL_RESOLVE) set, and when the label is finally defined, the placeholder is patched and the reference's line number is replaced with FFFD (CTL_DONE).  Here's the table after the program finished:

<div class="codegen">
<div><div class="cg-title">Labels</div><pre>0FA0  005A  02A2  line 90
0FA4  0037  029D  line 55
0FA8  0035  0280  line 53
0FAC  0034  0261  line 52
0FB0  0033  0244  line 51
0FB4  0032  021F  line 50
0FB8  FFFD  821A  GOTO at 021A (resolved)
0FBC  0029  01FA  line 41
0FC0  0028  01D2  line 40
0FC4  0021  01BC  line 33
0FC8  FFFD  81B7  GOTO at 01B7 (resolved)
0FCC  0020  0199  line 32
0FD0  001F  017C  line 31
0FD4  001E  0149  line 30
0FD8  0016  0127  line 22
0FDC  FFFD  8122  GOTO at 0122 (resolved)
0FE0  0015  00F9  line 21
0FE4  FFFD  80F4  GOTO at 00F4 (resolved)
0FE8  0014  00D4  line 20
0FEC  000F  00C4  line 15
0FF0  000E  0068  line 14
0FF4  000D  003C  line 13
0FF8  000B  000C  line 11
0FFC  000A  000C  line 10</pre></div>
<div><div class="cg-title">Code block (3DFF)</div><pre>0FA0  5A 00 A2 02 37 00 9D 02  Z...7...
0FA8  35 00 80 02 34 00 61 02  5...4.a.
0FB0  33 00 44 02 32 00 1F 02  3.D.2...
0FB8  FD FF 1A 82 29 00 FA 01  ....)...
0FC0  28 00 D2 01 21 00 BC 01  (...!...
0FC8  FD FF B7 81 20 00 99 01  .... ...
0FD0  1F 00 7C 01 1E 00 49 01  ..|...I.
0FD8  16 00 27 01 FD FF 22 81  ..'...".
0FE0  15 00 F9 00 FD FF F4 80  ........
0FE8  14 00 D4 00 0F 00 C4 00  ........
0FF0  0E 00 68 00 0D 00 3C 00  ..h...&lt;.
0FF8  0B 00 0C 00 0A 00 0C 00  ........</pre></div>
</div>

To keep large programs from scanning the entire table for every line, the generator remembers the highest label defined so far and the lowest label that a reference is still waiting for, so it scans only when a new label could be a duplicate or could resolve something.

### The Result

Altogether, the 20 lines of PRIMES.BAS produced 791 bytes of code, including two 8-byte slots, two strings, and a few unused bytes left behind by patched placeholders, plus 111 bytes of variables (including the 8-byte header).

It's not sophisticated code (every operator is a far call, and every value takes a round trip through the stack), but it's compact, and because nothing has to be parsed or looked up while the program runs, it's still about 10 times faster than BASICA, which interprets the program's tokens every time it runs them.

Since the program ran to completion, all of its code was generated, so COMMAND.COM keeps the code when the program ends.  If you type RUN afterward, the same code runs again without generating anything; the variables are simply cleared, since the code refers to them by address.

I captured all of this with the PCjs Debugger, running BASIC-DOS 2.01 on an emulated IBM PC XT, with breakpoints in `genMore` before and after its call to `genCommands`, and dumps of the code block and the variable block at every stop.
