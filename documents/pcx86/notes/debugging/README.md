## Debugging Notes

### Fresh PSP

From PC DOS 2.00:

>> db 144d:0
&144D:0000  CD 20 00 80 00 9A F0 FF-0D F0 8E 09 32 0B 99 2B  . ..........2..+
&144D:0010  32 0B 56 09 32 0B 4E 0A-01 01 01 00 02 FF FF FF  2.V.2.N.........
&144D:0020  FF FF FF FF FF FF FF FF-FF FF FF FF 17 0B 46 01  ..............F.
&144D:0030  4E 0A 00 00 00 00 00 00-00 00 00 00 00 00 00 00  N...............
&144D:0040  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
&144D:0050  CD 21 CB 00 00 00 00 00-00 00 00 00 00 20 20 20  .!...........   
&144D:0060  20 20 20 20 20 20 20 20-00 00 00 00 00 20 20 20          .....   
&144D:0070  20 20 20 20 20 20 20 20-00 00 00 00 00 00 00 00          ........
&144D:0080  00 0D 67 77 62 00 0D 43-3A 5C 54 4F 4F 4C 53 0D  ..gwb..C:\TOOLS.
&144D:0090  34 4C 49 42 0D 49 4E 43-0D 5C 4D 41 53 4D 34 3B  4LIB.INC.\MASM4;
&144D:00A0  43 3A 5C 54 4F 4F 4C 53-5C 42 49 4E 3B 43 3A 5C  C:\TOOLS\BIN;C:\
&144D:00B0  44 4F 53 0D 00 00 00 00-00 00 00 00 00 00 00 00  DOS.............
&144D:00C0  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
&144D:00D0  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
&144D:00E0  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
&144D:00F0  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................

### SYMDEB.EXE

Needs a machine with at least 64K of RAM.  Allocating only the minimum
of 11h paragraphs causes problems.

### GWB.EXE

running on PC DOS 2.00
*debugger halting on INT 3
stopped (1052900017 cycles, 1595051342186 ms, 1 hz)
AX=5200 BX=010E CX=0000 DX=0000 SP=FFEE BP=0000 SI=0000 DI=0000 
SS=142D DS=142D ES=00E5 PS=F202 V0 D0 I1 T0 S0 Z0 A0 P0 C0 
&142D:0105 CD20             INT      20
>> dw es:bx-2 l1
&00E5:010C  051F                                          ..
>> d dos 51f
dumpMCB(0x051F)
051F:0000: 'M' PID=0x7F75 LEN=0x052D ""
0A4D:0000: 'M' PID=0x0A4E LEN=0x00BD ""
0B0B:0000: 'M' PID=0x0A4E LEN=0x000A ""
0B16:0000: 'M' PID=0x0B22 LEN=0x000A ""
0B21:0000: 'M' PID=0x0B22 LEN=0x090A "pu."
142C:0000: 'Z' PID=0x0000 LEN=0x6BD3 ""
>> g
running
debugger halting on INT 3
stopped (500138196 cycles, 1595051375310 ms, 0 hz)
AX=0000 BX=0000 CX=00FF DX=0B22 SP=0000 BP=0000 SI=C5C0 DI=0100 
SS=0B32 DS=0B22 ES=0B22 PS=F246 V0 D0 I1 T0 S0 Z1 A0 P1 C0 
&0B32:C5C1 8CC9             MOV      CX,CS
>> d dos 51f
dumpMCB(0x051F)
051F:0000: 'M' PID=0x7F75 LEN=0x052D ""
0A4D:0000: 'M' PID=0x0A4E LEN=0x00BD ""
0B0B:0000: 'M' PID=0x0A4E LEN=0x000A ""
0B16:0000: 'M' PID=0x0B22 LEN=0x000A ""
0B21:0000: 'Z' PID=0x0B22 LEN=0x74DE "pu."
>> db ds:0
&0B22:0000  CD 20 00 80 00 9A F0 FF-0D F0 8C 02 4E 0A 99 02  . ..........N...
&0B22:0010  4E 0A E2 04 4E 0A 4E 0A-01 01 01 00 02 FF FF FF  N...N.N.........
&0B22:0020  FF FF FF FF FF FF FF FF-FF FF FF FF 17 0B 46 01  ..............F.
&0B22:0030  4E 0A 00 00 00 00 00 00-00 00 00 00 00 00 00 00  N...............
&0B22:0040  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
&0B22:0050  CD 21 CB 00 00 00 00 00-00 00 00 00 00 20 20 20  .!...........   
&0B22:0060  20 20 20 20 20 20 20 20-00 00 00 00 00 20 20 20          .....   
&0B22:0070  20 20 20 20 20 20 20 20-00 00 00 00 00 00 00 00          ........
>> u f00d:fff0 l1
invalid value: l1
>> u f00d:fff0
IBMBIO.COM+0x0AB7:
&F00D:FFF0 EA080CE500       JMP      &00E5:0C08 (IBMDOS.COM+0x0C08)
&F00D:FFF5 0000             ADD      [BX+SI],AL
&F00D:FFF7 0000             ADD      [BX+SI],AL
&F00D:FFF9 0000             ADD      [BX+SI],AL
&F00D:FFFB 0000             ADD      [BX+SI],AL
&F00D:FFFD 0000             ADD      [BX+SI],AL
&F00D:FFFF 00               ADD      BH,BH
&F00D:0001 FFFF             INVALID 
>> u e5:c08
IBMDOS.COM+0x0C08:
&00E5:0C08 58               POP      AX
&00E5:0C09 58               POP      AX
&00E5:0C0A 2E               CS:     
&00E5:0C0B 8F06E502         POP      WORD [02E5]
&00E5:0C0F 9C               PUSHF   
&00E5:0C10 FA               CLI     
&00E5:0C11 50               PUSH     AX
&00E5:0C12 2E               CS:     
&00E5:0C13 FF36E502         PUSH     WORD [02E5]
