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

Here's log of running "SYMDEB E.COM" on PC DOS 2.00 (with an 11-byte E.COM)
with only 96Fh paragraphs available.  The system crashed.

    bp &0000:0000 set
    instruction history buffer allocated
    BusX86: 16Kb VIDEO at 0xB8000
    AX=0000 BX=0000 CX=0000 DX=0000 SP=0000 BP=0000 SI=0000 DI=0000 
    SS=0000 DS=0000 ES=0000 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &FFFF:0000 EA5BE000F0       JMP      &F000:E05B (romBIOS+0x005B)
    running
    *>> d dos 51f
    dumpMCB(0x051F)
    051F:0000: 'M' PID=0x7F75 LEN=0x052D ""
    0A4D:0000: 'M' PID=0x0A4E LEN=0x00BD ""
    0B0B:0000: 'M' PID=0x0A4E LEN=0x000A ""
    0B16:0000: 'M' PID=0x0B22 LEN=0x000A ""
    0B21:0000: 'M' PID=0x0B22 LEN=0x068F "pu."
    11B1:0000: 'M' PID=0x11BD LEN=0x000A ""
    11BC:0000: 'M' PID=0x11BD LEN=0x068F ""
    184C:0000: 'M' PID=0x1858 LEN=0x000A ""
    1857:0000: 'M' PID=0x1858 LEN=0x068F ""
    1EE7:0000: 'M' PID=0x1EF3 LEN=0x000A ""
    1EF2:0000: 'M' PID=0x1EF3 LEN=0x068F ""
    2582:0000: 'M' PID=0x258E LEN=0x000A ""
    258D:0000: 'M' PID=0x258E LEN=0x068F ""
    2C1D:0000: 'M' PID=0x2C29 LEN=0x000A ""
    2C28:0000: 'M' PID=0x2C29 LEN=0x068F ""
    32B8:0000: 'M' PID=0x32C4 LEN=0x000A ""
    32C3:0000: 'M' PID=0x32C4 LEN=0x068F ""
    3953:0000: 'M' PID=0x395F LEN=0x000A ""
    395E:0000: 'M' PID=0x395F LEN=0x068F ""
    3FEE:0000: 'M' PID=0x3FFA LEN=0x000A ""
    3FF9:0000: 'M' PID=0x3FFA LEN=0x068F ""
    4689:0000: 'M' PID=0x4695 LEN=0x000A ""
    4694:0000: 'M' PID=0x4695 LEN=0x068F ""
    4D24:0000: 'M' PID=0x4D30 LEN=0x000A ""
    4D2F:0000: 'M' PID=0x4D30 LEN=0x068F ""
    53BF:0000: 'M' PID=0x53CB LEN=0x000A ""
    53CA:0000: 'M' PID=0x53CB LEN=0x068F ""
    5A5A:0000: 'M' PID=0x5A66 LEN=0x000A ""
    5A65:0000: 'M' PID=0x5A66 LEN=0x068F ""
    60F5:0000: 'M' PID=0x6101 LEN=0x000A ""
    6100:0000: 'M' PID=0x6101 LEN=0x068F ""
    6790:0000: 'M' PID=0x679C LEN=0x000A ""
    679B:0000: 'M' PID=0x679C LEN=0x068F ""
    6E2B:0000: 'M' PID=0x6E37 LEN=0x000A ""
    6E36:0000: 'M' PID=0x6E37 LEN=0x068F ""
    74C6:0000: 'M' PID=0x74D2 LEN=0x000A ""
    74D1:0000: 'M' PID=0x74D2 LEN=0x01BE ""
    7690:0000: 'Z' PID=0x0A4E LEN=0x096F ""
    suspicious opcode: 0x00 0x00
    stopped (44831041 opcodes, 680622685 cycles, 1595611164008 ms, 0 hz)
    AX=F202 BX=435C CX=00FF DX=0080 SP=0178 BP=0000 SI=8F74 DI=0100 
    SS=0A4E DS=7FB2 ES=4D4F PS=F213 V0 D0 I1 T0 S0 Z0 A1 P0 C1 
    &4D4F:435E 0000             ADD      [BX+SI],AL
    >> dh 100 100
    100 instructions earlier:
    &00E5:2C0B 807D0500         CMP      [DI+05],00               ;history=100
    &00E5:2C0F 7417             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=99
    &00E5:2C28 C53D             LDS      DI,[DI]                  ;history=98
    &00E5:2C2A 83FFFF           CMP      DI,FFFF                  ;history=97
    &00E5:2C2D 75CE             JNZ      2BFD (IBMDOS.COM+0x2BFD) ;history=96
    &00E5:2BFD 386504           CMP      [DI+04],AH               ;history=95
    &00E5:2C00 7426             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=94
    &00E5:2C02 3AE0             CMP      AH,AL                    ;history=93
    &00E5:2C04 7405             JZ       2C0B (IBMDOS.COM+0x2C0B) ;history=92
    &00E5:2C0B 807D0500         CMP      [DI+05],00               ;history=91
    &00E5:2C0F 7417             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=90
    &00E5:2C28 C53D             LDS      DI,[DI]                  ;history=89
    &00E5:2C2A 83FFFF           CMP      DI,FFFF                  ;history=88
    &00E5:2C2D 75CE             JNZ      2BFD (IBMDOS.COM+0x2BFD) ;history=87
    &00E5:2BFD 386504           CMP      [DI+04],AH               ;history=86
    &00E5:2C00 7426             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=85
    &00E5:2C02 3AE0             CMP      AH,AL                    ;history=84
    &00E5:2C04 7405             JZ       2C0B (IBMDOS.COM+0x2C0B) ;history=83
    &00E5:2C0B 807D0500         CMP      [DI+05],00               ;history=82
    &00E5:2C0F 7417             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=81
    &00E5:2C28 C53D             LDS      DI,[DI]                  ;history=80
    &00E5:2C2A 83FFFF           CMP      DI,FFFF                  ;history=79
    &00E5:2C2D 75CE             JNZ      2BFD (IBMDOS.COM+0x2BFD) ;history=78
    &00E5:2BFD 386504           CMP      [DI+04],AH               ;history=77
    &00E5:2C00 7426             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=76
    &00E5:2C02 3AE0             CMP      AH,AL                    ;history=75
    &00E5:2C04 7405             JZ       2C0B (IBMDOS.COM+0x2C0B) ;history=74
    &00E5:2C0B 807D0500         CMP      [DI+05],00               ;history=73
    &00E5:2C0F 7417             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=72
    &00E5:2C28 C53D             LDS      DI,[DI]                  ;history=71
    &00E5:2C2A 83FFFF           CMP      DI,FFFF                  ;history=70
    &00E5:2C2D 75CE             JNZ      2BFD (IBMDOS.COM+0x2BFD) ;history=69
    &00E5:2BFD 386504           CMP      [DI+04],AH               ;history=68
    &00E5:2C00 7426             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=67
    &00E5:2C02 3AE0             CMP      AH,AL                    ;history=66
    &00E5:2C04 7405             JZ       2C0B (IBMDOS.COM+0x2C0B) ;history=65
    &00E5:2C0B 807D0500         CMP      [DI+05],00               ;history=64
    &00E5:2C0F 7417             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=63
    &00E5:2C28 C53D             LDS      DI,[DI]                  ;history=62
    &00E5:2C2A 83FFFF           CMP      DI,FFFF                  ;history=61
    &00E5:2C2D 75CE             JNZ      2BFD (IBMDOS.COM+0x2BFD) ;history=60
    &00E5:2BFD 386504           CMP      [DI+04],AH               ;history=59
    &00E5:2C00 7426             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=58
    &00E5:2C02 3AE0             CMP      AH,AL                    ;history=57
    &00E5:2C04 7405             JZ       2C0B (IBMDOS.COM+0x2C0B) ;history=56
    &00E5:2C0B 807D0500         CMP      [DI+05],00               ;history=55
    &00E5:2C0F 7417             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=54
    &00E5:2C28 C53D             LDS      DI,[DI]                  ;history=53
    &00E5:2C2A 83FFFF           CMP      DI,FFFF                  ;history=52
    &00E5:2C2D 75CE             JNZ      2BFD (IBMDOS.COM+0x2BFD) ;history=51
    &00E5:2BFD 386504           CMP      [DI+04],AH               ;history=50
    &00E5:2C00 7426             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=49
    &00E5:2C02 3AE0             CMP      AH,AL                    ;history=48
    &00E5:2C04 7405             JZ       2C0B (IBMDOS.COM+0x2C0B) ;history=47
    &00E5:2C0B 807D0500         CMP      [DI+05],00               ;history=46
    &00E5:2C0F 7417             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=45
    &00E5:2C28 C53D             LDS      DI,[DI]                  ;history=44
    &00E5:2C2A 83FFFF           CMP      DI,FFFF                  ;history=43
    &00E5:2C2D 75CE             JNZ      2BFD (IBMDOS.COM+0x2BFD) ;history=42
    &00E5:2BFD 386504           CMP      [DI+04],AH               ;history=41
    &00E5:2C00 7426             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=40
    &00E5:2C02 3AE0             CMP      AH,AL                    ;history=39
    &00E5:2C04 7405             JZ       2C0B (IBMDOS.COM+0x2C0B) ;history=38
    &00E5:2C0B 807D0500         CMP      [DI+05],00               ;history=37
    &00E5:2C0F 7417             JZ       2C28 (IBMDOS.COM+0x2C28) ;history=36
    &00E5:2C28 C53D             LDS      DI,[DI]                  ;history=35
    &00E5:2C2A 83FFFF           CMP      DI,FFFF                  ;history=34
    &00E5:2C2D 75CE             JNZ      2BFD (IBMDOS.COM+0x2BFD) ;history=33
    &00E5:2C2F 16               PUSH     SS                       ;history=32
    &00E5:2C30 1F               POP      DS                       ;history=31
    &00E5:2C31 C3               RET                               ;history=30
    &00E5:3271 FA               CLI                               ;history=29
    &00E5:3272 C606410100       MOV      [0141],00                ;history=28
    &00E5:3277 C6064301FF       MOV      [0143],FF                ;history=27
    &00E5:327C 8E1EA501         MOV      DS,[01A5]                ;history=26
    &00E5:3280 8E163000         MOV      SS,[0030]                ;history=25
    &00E5:3284 8B262E00         MOV      SP,[002E]                ;history=24
    &00E5:3288 E85FDA           CALL     0CEA (IBMDOS.COM+0x0CEA) ;history=23
    &00E5:0CEA 2E               CS:     
    &00E5:0CEF 58               POP      AX                       ;history=21
    &00E5:0CF0 5B               POP      BX                       ;history=20
    &00E5:0CF1 59               POP      CX                       ;history=19
    &00E5:0CF2 5A               POP      DX                       ;history=18
    &00E5:0CF3 5E               POP      SI                       ;history=17
    &00E5:0CF4 5F               POP      DI                       ;history=16
    &00E5:0CF5 5D               POP      BP                       ;history=15
    &00E5:0CF6 1F               POP      DS                       ;history=14
    &00E5:0CF7 07               POP      ES                       ;history=13
    &00E5:0CF8 2E               CS:     
    &00E5:0CFD C3               RET                               ;history=11
    &00E5:328B 58               POP      AX                       ;history=10
    &00E5:328C 58               POP      AX                       ;history=9
    &00E5:328D 58               POP      AX                       ;history=8
    &00E5:328E B802F2           MOV      AX,F202                  ;history=7
    &00E5:3291 50               PUSH     AX                       ;history=6
    &00E5:3292 2E               CS:     
    &00E5:3297 2E               CS:     
    &00E5:329C FB               STI                               ;history=3
    &00E5:329D CF               IRET                              ;history=2
    &4D4F:435C 0000             ADD      [BX+SI],AL               ;history=1
    >> r
    AX=F202 BX=435C CX=00FF DX=0080 SP=0178 BP=0000 SI=8F74 DI=0100 
    SS=0A4E DS=7FB2 ES=4D4F PS=F213 V0 D0 I1 T0 S0 Z0 A1 P0 C1 
    &4D4F:435E 0000             ADD      [BX+SI],AL
    >> db cs:0
    &4D4F:0000  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0010  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0020  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0030  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0040  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0050  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0060  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0070  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    >> db es:0
    &4D4F:0000  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0010  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0020  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0030  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0040  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0050  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0060  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &4D4F:0070  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    >> r
    AX=F202 BX=435C CX=00FF DX=0080 SP=0178 BP=0000 SI=8F74 DI=0100 
    SS=0A4E DS=7FB2 ES=4D4F PS=F213 V0 D0 I1 T0 S0 Z0 A1 P0 C1 
    &4D4F:435E 0000             ADD      [BX+SI],AL
    BusX86: 16Kb VIDEO at 0xB8000
    AX=0000 BX=0000 CX=0000 DX=0000 SP=0000 BP=0000 SI=0000 DI=0000 
    SS=0000 DS=0000 ES=0000 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &FFFF:0000 EA5BE000F0       JMP      &F000:E05B (romBIOS+0x005B)
    running
    *>> d dos 51f
    dumpMCB(0x051F)
    051F:0000: 'M' PID=0x7F75 LEN=0x052D ""
    0A4D:0000: 'M' PID=0x0A4E LEN=0x00BD ""
    0B0B:0000: 'M' PID=0x0A4E LEN=0x000A ""
    0B16:0000: 'M' PID=0x0B22 LEN=0x000A ""
    0B21:0000: 'M' PID=0x0B22 LEN=0x068F "pu."
    11B1:0000: 'M' PID=0x11BD LEN=0x000A ""
    11BC:0000: 'M' PID=0x11BD LEN=0x068F ""
    184C:0000: 'M' PID=0x1858 LEN=0x000A ""
    1857:0000: 'M' PID=0x1858 LEN=0x068F ""
    1EE7:0000: 'M' PID=0x1EF3 LEN=0x000A ""
    1EF2:0000: 'M' PID=0x1EF3 LEN=0x068F ""
    2582:0000: 'M' PID=0x258E LEN=0x000A ""
    258D:0000: 'M' PID=0x258E LEN=0x068F ""
    2C1D:0000: 'M' PID=0x2C29 LEN=0x000A ""
    2C28:0000: 'M' PID=0x2C29 LEN=0x068F ""
    32B8:0000: 'M' PID=0x32C4 LEN=0x000A ""
    32C3:0000: 'M' PID=0x32C4 LEN=0x068F ""
    3953:0000: 'M' PID=0x395F LEN=0x000A ""
    395E:0000: 'M' PID=0x395F LEN=0x068F ""
    3FEE:0000: 'M' PID=0x3FFA LEN=0x000A ""
    3FF9:0000: 'M' PID=0x3FFA LEN=0x068F ""
    4689:0000: 'M' PID=0x4695 LEN=0x000A ""
    4694:0000: 'M' PID=0x4695 LEN=0x068F ""
    4D24:0000: 'M' PID=0x4D30 LEN=0x000A ""
    4D2F:0000: 'M' PID=0x4D30 LEN=0x068F ""
    53BF:0000: 'M' PID=0x53CB LEN=0x000A ""
    53CA:0000: 'M' PID=0x53CB LEN=0x068F ""
    5A5A:0000: 'M' PID=0x5A66 LEN=0x000A ""
    5A65:0000: 'M' PID=0x5A66 LEN=0x068F ""
    60F5:0000: 'M' PID=0x6101 LEN=0x000A ""
    6100:0000: 'M' PID=0x6101 LEN=0x068F ""
    6790:0000: 'M' PID=0x679C LEN=0x000A ""
    679B:0000: 'M' PID=0x679C LEN=0x068F ""
    6E2B:0000: 'M' PID=0x6E37 LEN=0x000A ""
    6E36:0000: 'M' PID=0x6E37 LEN=0x068F ""
    74C6:0000: 'M' PID=0x74D2 LEN=0x000A ""
    74D1:0000: 'M' PID=0x74D2 LEN=0x01BE ""
    7690:0000: 'Z' PID=0x0A4E LEN=0x096F ""
    >> dw 0:80
    &0000:0080  0BFB  00E5  0180  0A4E  039E  0A4E  0299  0A4E   ......N...N...N.
    &0000:0090  04E2  0A4E  14D4  00E5  1521  00E5  27E7  00E5   ..N.....!....'..
    &0000:00A0  0C07  00E5  0126  0070  0000  0000  0000  0000   ....&.p.........
    &0000:00B0  0000  0000  0000  0000  036D  0A4E  0000  0000   ........m.N.....
    &0000:00C0  08EA  E50C  0000  0000  0000  0000  0000  0000   ................
    &0000:00D0  0000  0000  0000  0000  0000  0000  0000  0000   ................
    &0000:00E0  0000  0000  0000  0000  0000  0000  0000  0000   ................
    &0000:00F0  0000  0000  0000  0000  0000  0000  0000  0000   ................
    >> bp a4e:180
    bp &0A4E:0180 set
    bp &0A4E:0180 hit
    stopped (73119577 opcodes, 1122344125 cycles, 1595611271320 ms, 1 hz)
    AX=4024 BX=0001 CX=0002 DX=29B9 SP=2F4D BP=0000 SI=2B89 DI=29BC 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F003 V0 D0 I0 T0 S0 Z0 A0 P0 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (5915 opcodes, 94047 cycles, 1595611273585 ms, 0 hz)
    AX=2901 BX=29D4 CX=000C DX=2B06 SP=2F5D BP=0000 SI=2B8B DI=2CD9 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (697 opcodes, 5924 cycles, 1595611274970 ms, 0 hz)
    AX=2901 BX=2965 CX=FF06 DX=2B06 SP=2F5D BP=0000 SI=2B92 DI=005C 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F016 V0 D0 I0 T0 S0 Z0 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (564 opcodes, 4917 cycles, 1595611275871 ms, 0 hz)
    AX=2901 BX=290D CX=FF06 DX=2B06 SP=2F5D BP=0000 SI=2B97 DI=006C 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F097 V0 D0 I0 T0 S1 Z0 A1 P1 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (666 opcodes, 7333 cycles, 1595611276532 ms, 0 hz)
    AX=473A BX=290D CX=0000 DX=2B00 SP=2F5B BP=0000 SI=2C0F DI=2C0F 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (273 opcodes, 4355 cycles, 1595611277166 ms, 0 hz)
    AX=1A3F BX=290D CX=0000 DX=2D55 SP=2F5D BP=0000 SI=2C0F DI=2CE5 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (307 opcodes, 4389 cycles, 1595611277859 ms, 0 hz)
    AX=113D BX=290D CX=00FB DX=2CD9 SP=2F5D BP=0000 SI=0028 DI=2C4F 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (2875 opcodes, 32329 cycles, 1595611278575 ms, 0 hz)
    AX=3BFF BX=290D CX=00FB DX=2C0C SP=2F5D BP=0000 SI=0028 DI=2C4F 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (530 opcodes, 6567 cycles, 1595611279165 ms, 0 hz)
    AX=473A BX=2900 CX=00FB DX=0003 SP=2F51 BP=0000 SI=2C0F DI=2C0F 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F006 V0 D0 I0 T0 S0 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (273 opcodes, 4400 cycles, 1595611279796 ms, 0 hz)
    AX=3B00 BX=293B CX=00FB DX=0028 SP=2F5D BP=0000 SI=0037 DI=2C5D 
    SS=7CB0 DS=0B0C ES=7CB0 PS=F006 V0 D0 I0 T0 S0 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (8061 opcodes, 102604 cycles, 1595611280652 ms, 0 hz)
    AX=1100 BX=293B CX=00FB DX=2CD9 SP=2F5D BP=0000 SI=0037 DI=2C5D 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (5953 opcodes, 74536 cycles, 1595611281260 ms, 0 hz)
    AX=3BFF BX=293B CX=00FB DX=2C0C SP=2F5D BP=0000 SI=0037 DI=2C5D 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (530 opcodes, 6567 cycles, 1595611281905 ms, 0 hz)
    AX=473A BX=2900 CX=00FB DX=0003 SP=2F51 BP=0000 SI=2C0F DI=2C0F 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F006 V0 D0 I0 T0 S0 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (273 opcodes, 4400 cycles, 1595611282618 ms, 0 hz)
    AX=3B00 BX=293B CX=00FB DX=0037 SP=2F5D BP=0000 SI=0046 DI=2C5D 
    SS=7CB0 DS=0B0C ES=7CB0 PS=F006 V0 D0 I0 T0 S0 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (8313 opcodes, 104403 cycles, 1595611283199 ms, 0 hz)
    AX=1100 BX=293B CX=00FB DX=2CD9 SP=2F5D BP=0000 SI=0046 DI=2C5D 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (4171 opcodes, 50524 cycles, 1595611283784 ms, 0 hz)
    AX=1200 BX=293B CX=00FB DX=2CD9 SP=2F5D BP=0000 SI=0046 DI=2C5D 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (3471 opcodes, 40020 cycles, 1595611284578 ms, 0 hz)
    AX=3BFF BX=293B CX=00FB DX=2C0C SP=2F5B BP=0000 SI=0046 DI=2C5D 
    SS=7CB0 DS=7CB0 ES=7CB0 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (497 opcodes, 6639 cycles, 1595611285395 ms, 0 hz)
    AX=4900 BX=293B CX=0000 DX=2C0C SP=2F5D BP=0000 SI=2D61 DI=2C69 
    SS=7CB0 DS=7CB0 ES=7691 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (214 opcodes, 4160 cycles, 1595611286935 ms, 0 hz)
    AX=4B00 BX=0B1C CX=0A4E DX=2C4F SP=017A BP=0000 SI=0100 DI=0100 
    SS=0A4E DS=7CB0 ES=0A4E PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (22 opcodes, 357 cycles, 1595611290281 ms, 0 hz)
    AX=484E BX=FFFF CX=0A4E DX=2C4F SP=0162 BP=0000 SI=0100 DI=0100 
    SS=0A4E DS=7CB0 ES=0A4E PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (737 opcodes, 9752 cycles, 1595611294965 ms, 0 hz)
    AX=4808 BX=096F CX=0A4E DX=2C4F SP=0162 BP=0000 SI=0100 DI=0100 
    SS=0A4E DS=7CB0 ES=0A4E PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (738 opcodes, 9713 cycles, 1595611296099 ms, 0 hz)
    AX=4991 BX=7FA7 CX=0A4E DX=2C4F SP=0162 BP=0000 SI=0100 DI=0100 
    SS=0A4E DS=7CB0 ES=7691 PS=F812 V1 D0 I0 T0 S0 Z0 A1 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (2175 opcodes, 26646 cycles, 1595611313987 ms, 0 hz)
    AX=3300 BX=7FA7 CX=0000 DX=8D1E SP=015E BP=0000 SI=054E DI=0100 
    SS=0A4E DS=7FA7 ES=7691 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (103 opcodes, 1662 cycles, 1595611314746 ms, 0 hz)
    AX=3301 BX=7FA7 CX=0000 DX=0000 SP=015E BP=0000 SI=054E DI=0100 
    SS=0A4E DS=7FA7 ES=7691 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (100 opcodes, 1571 cycles, 1595611315445 ms, 0 hz)
    AX=5100 BX=7FA7 CX=0000 DX=0000 SP=015E BP=0000 SI=054E DI=0100 
    SS=0A4E DS=7FA7 ES=7691 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (101 opcodes, 1730 cycles, 1595611316104 ms, 0 hz)
    AX=1900 BX=0168 CX=0000 DX=0000 SP=015E BP=0000 SI=054E DI=0100 
    SS=0A4E DS=7FA7 ES=0A4E PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (96 opcodes, 1538 cycles, 1595611316769 ms, 0 hz)
    AX=0E02 BX=0168 CX=0000 DX=0002 SP=015E BP=0000 SI=054E DI=0100 
    SS=0A4E DS=7FA7 ES=0A4E PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (124 opcodes, 1981 cycles, 1595611317386 ms, 0 hz)
    AX=3D00 BX=0B1C CX=0004 DX=2C4F SP=015E BP=0000 SI=0168 DI=0100 
    SS=0A4E DS=7CB0 ES=0A4E PS=F093 V0 D0 I0 T0 S1 Z0 A1 P0 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (10338 opcodes, 127684 cycles, 1595611318011 ms, 0 hz)
    AX=4400 BX=0005 CX=0004 DX=2C4F SP=015E BP=0000 SI=0168 DI=0100 
    SS=0A4E DS=7CB0 ES=0A4E PS=F092 V0 D0 I0 T0 S1 Z0 A1 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (360 opcodes, 5436 cycles, 1595611318736 ms, 0 hz)
    AX=4800 BX=000A CX=7F04 DX=0042 SP=015A BP=0000 SI=0B1C DI=009E 
    SS=0A4E DS=0A4E ES=0B0C PS=F017 V0 D0 I0 T0 S0 Z0 A1 P1 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (942 opcodes, 12951 cycles, 1595611319310 ms, 0 hz)
    AX=3F91 BX=0005 CX=001E DX=0568 SP=015A BP=0000 SI=009E DI=009E 
    SS=0A4E DS=7FA7 ES=7691 PS=F056 V0 D0 I0 T0 S0 Z1 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (1848 opcodes, 27162 cycles, 1595611319928 ms, 0 hz)
    AX=4800 BX=FFFF CX=0005 DX=0568 SP=015A BP=0000 SI=009E DI=009E 
    SS=0A4E DS=7FA7 ES=7691 PS=F056 V0 D0 I0 T0 S0 Z1 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (795 opcodes, 10693 cycles, 1595611320518 ms, 0 hz)
    AX=4864 BX=0964 CX=0005 DX=0568 SP=015C BP=0000 SI=009E DI=009E 
    SS=0A4E DS=7FA7 ES=7691 PS=F007 V0 D0 I0 T0 S0 Z0 A0 P1 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (771 opcodes, 10230 cycles, 1595611321000 ms, 0 hz)
    AX=4200 BX=0005 CX=0000 DX=0200 SP=015C BP=0000 SI=009E DI=009E 
    SS=0A4E DS=7FA7 ES=7691 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (200 opcodes, 3050 cycles, 1595611321491 ms, 0 hz)
    AX=3F00 BX=0005 CX=9000 DX=0000 SP=0158 BP=0000 SI=009E DI=009E 
    SS=0A4E DS=76AC ES=7691 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (7135 opcodes, 96306 cycles, 1595611322027 ms, 0 hz)
    AX=4200 BX=0005 CX=0000 DX=001E SP=015C BP=0000 SI=009E DI=009E 
    SS=0A4E DS=7FA7 ES=0000 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (194 opcodes, 2956 cycles, 1595611322542 ms, 0 hz)
    AX=3F1E BX=0005 CX=001C DX=0568 SP=015A BP=0000 SI=009E DI=009E 
    SS=0A4E DS=7FA7 ES=0000 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (1529 opcodes, 21862 cycles, 1595611323013 ms, 0 hz)
    AX=3EAC BX=0005 CX=0003 DX=0000 SP=015E BP=0000 SI=76AC DI=0578 
    SS=0A4E DS=76AC ES=7FA7 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (185 opcodes, 2789 cycles, 1595611323474 ms, 0 hz)
    AX=559B BX=0005 CX=0003 DX=769C SP=015C BP=0000 SI=0001 DI=0578 
    SS=0A4E DS=769B ES=7FA7 PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (1364 opcodes, 19437 cycles, 1595611323940 ms, 0 hz)
    AX=1A00 BX=0000 CX=00FF DX=0080 SP=015A BP=0000 SI=0168 DI=0100 
    SS=0A4E DS=769C ES=769C PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (104 opcodes, 1714 cycles, 1595611324463 ms, 0 hz)
    AX=3301 BX=0000 CX=00FF DX=7600 SP=0158 BP=0000 SI=0168 DI=0100 
    SS=0A4E DS=0000 ES=769C PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (382 opcodes, 6164 cycles, 1595611324931 ms, 0 hz)
    AX=30AC BX=0000 CX=0000 DX=769C SP=8F9A BP=0000 SI=0100 DI=0100 
    SS=76AC DS=76AC ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (112 opcodes, 1812 cycles, 1595611325396 ms, 0 hz)
    AX=3501 BX=0000 CX=0000 DX=769C SP=8F9A BP=0000 SI=0100 DI=0100 
    SS=76AC DS=76AC ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (109 opcodes, 1770 cycles, 1595611325900 ms, 0 hz)
    AX=3502 BX=013F CX=0000 DX=769C SP=8F9A BP=0000 SI=0100 DI=0100 
    SS=76AC DS=76AC ES=0070 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (109 opcodes, 1770 cycles, 1595611326425 ms, 0 hz)
    AX=3503 BX=F85F CX=0000 DX=769C SP=8F9A BP=0000 SI=0100 DI=0100 
    SS=76AC DS=76AC ES=F000 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (109 opcodes, 1770 cycles, 1595611326892 ms, 0 hz)
    AX=3509 BX=013F CX=0000 DX=769C SP=8F9A BP=0000 SI=0100 DI=0100 
    SS=76AC DS=76AC ES=0070 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (109 opcodes, 1770 cycles, 1595611327322 ms, 0 hz)
    AX=3510 BX=E987 CX=0000 DX=769C SP=8F9A BP=0000 SI=0100 DI=0100 
    SS=76AC DS=76AC ES=F000 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (111 opcodes, 1770 cycles, 1595611327793 ms, 0 hz)
    AX=51AC BX=F065 CX=0000 DX=769C SP=8F9A BP=0000 SI=0100 DI=0100 
    SS=76AC DS=76AC ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (218 opcodes, 3237 cycles, 1595611328251 ms, 0 hz)
    AX=0900 BX=009C CX=0000 DX=013C SP=8F92 BP=0000 SI=0082 DI=0100 
    SS=76AC DS=76AC ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (70568 opcodes, 964238 cycles, 1595611328773 ms, 0 hz)
    AX=0900 BX=009C CX=0021 DX=01C1 SP=8F92 BP=0000 SI=0082 DI=0100 
    SS=76AC DS=76AC ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (6899 opcodes, 106446 cycles, 1595611330351 ms, 0 hz)
    AX=2522 BX=009C CX=0021 DX=098E SP=8F96 BP=0000 SI=0082 DI=0100 
    SS=76AC DS=76AC ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (106 opcodes, 1656 cycles, 1595611331094 ms, 0 hz)
    AX=3524 BX=009C CX=0021 DX=098E SP=8F98 BP=0000 SI=0082 DI=0100 
    SS=76AC DS=76AC ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (111 opcodes, 1790 cycles, 1595611332036 ms, 0 hz)
    AX=2524 BX=04E2 CX=0021 DX=0956 SP=8F9A BP=0000 SI=0082 DI=0100 
    SS=76AC DS=76AC ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (137 opcodes, 2113 cycles, 1595611332732 ms, 0 hz)
    AX=3700 BX=04E2 CX=0004 DX=08FA SP=8F86 BP=0000 SI=0082 DI=7EC9 
    SS=76AC DS=76AC ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (407 opcodes, 5301 cycles, 1595611334379 ms, 0 hz)
    AX=2523 BX=04E2 CX=0000 DX=0A2B SP=8F9A BP=0000 SI=00D0 DI=7F7D 
    SS=76AC DS=76AC ES=76AC PS=F087 V0 D0 I0 T0 S1 Z0 A0 P1 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (122 opcodes, 1779 cycles, 1595611335177 ms, 0 hz)
    AX=2502 BX=0400 CX=0028 DX=2C1B SP=8F9A BP=0000 SI=00D0 DI=7F7D 
    SS=76AC DS=76AC ES=76AC PS=F086 V0 D0 I0 T0 S1 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (105 opcodes, 1622 cycles, 1595611335833 ms, 0 hz)
    AX=3301 BX=0400 CX=0028 DX=2C01 SP=8F9A BP=0000 SI=00D0 DI=7F7D 
    SS=76AC DS=76AC ES=76AC PS=F086 V0 D0 I0 T0 S1 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (102 opcodes, 1595 cycles, 1595611336469 ms, 0 hz)
    AX=2600 BX=0400 CX=0028 DX=7FA7 SP=8F9A BP=0000 SI=00D0 DI=7F7D 
    SS=76AC DS=76AC ES=76AC PS=F002 V0 D0 I0 T0 S0 Z0 A0 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (381 opcodes, 7236 cycles, 1595611337087 ms, 0 hz)
    AX=4A9C BX=090A CX=0028 DX=7FA7 SP=8F96 BP=0000 SI=00D0 DI=7F7D 
    SS=76AC DS=76AC ES=769C PS=F016 V0 D0 I0 T0 S0 Z0 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (275 opcodes, 4224 cycles, 1595611337652 ms, 0 hz)
    AX=1A00 BX=090A CX=0028 DX=0080 SP=8F9A BP=0000 SI=00D0 DI=7EC9 
    SS=76AC DS=7FA7 ES=7FA7 PS=F016 V0 D0 I0 T0 S0 Z0 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (229 opcodes, 3603 cycles, 1595611338376 ms, 0 hz)
    AX=2901 BX=080A CX=0004 DX=0080 SP=8F9A BP=0000 SI=0081 DI=005C 
    SS=76AC DS=76AC ES=7FA7 PS=F007 V0 D0 I0 T0 S0 Z0 A0 P1 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (635 opcodes, 6505 cycles, 1595611339121 ms, 0 hz)
    AX=3700 BX=080A CX=0004 DX=0080 SP=8F98 BP=0000 SI=0087 DI=005C 
    SS=76AC DS=76AC ES=7FA7 PS=F007 V0 D0 I0 T0 S0 Z0 A0 P1 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (251 opcodes, 3822 cycles, 1595611339886 ms, 0 hz)
    AX=3700 BX=080A CX=0004 DX=002F SP=8F96 BP=0000 SI=0082 DI=370D 
    SS=76AC DS=76AC ES=7FA7 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (342 opcodes, 4571 cycles, 1595611340564 ms, 0 hz)
    AX=2901 BX=080A CX=0004 DX=002F SP=8F98 BP=0000 SI=0087 DI=005C 
    SS=76AC DS=76AC ES=76AC PS=F006 V0 D0 I0 T0 S0 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (368 opcodes, 4637 cycles, 1595611341543 ms, 0 hz)
    AX=3700 BX=080A CX=0004 DX=002F SP=8F96 BP=0000 SI=0087 DI=005C 
    SS=76AC DS=76AC ES=76AC PS=F006 V0 D0 I0 T0 S0 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (240 opcodes, 3680 cycles, 1595611342298 ms, 0 hz)
    AX=2901 BX=080A CX=0004 DX=002F SP=8F98 BP=0000 SI=0087 DI=006C 
    SS=76AC DS=76AC ES=76AC PS=F006 V0 D0 I0 T0 S0 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (423 opcodes, 5569 cycles, 1595611343020 ms, 0 hz)
    AX=3700 BX=080A CX=0004 DX=002F SP=8F86 BP=0000 SI=0087 DI=7F2F 
    SS=76AC DS=76AC ES=76AC PS=F056 V0 D0 I0 T0 S0 Z1 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (464 opcodes, 6335 cycles, 1595611343631 ms, 0 hz)
    AX=3700 BX=080A CX=0004 DX=0100 SP=8F86 BP=0000 SI=0086 DI=7F2F 
    SS=76AC DS=76AC ES=76AC PS=F056 V0 D0 I0 T0 S0 Z1 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (401 opcodes, 5309 cycles, 1595611344311 ms, 0 hz)
    AX=3D02 BX=8092 CX=0000 DX=0082 SP=8F84 BP=0000 SI=0087 DI=7F2F 
    SS=76AC DS=76AC ES=76AC PS=F056 V0 D0 I0 T0 S0 Z1 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (2683 opcodes, 33864 cycles, 1595611345037 ms, 0 hz)
    AX=4202 BX=0005 CX=0000 DX=0000 SP=8F98 BP=0000 SI=0086 DI=7F2F 
    SS=76AC DS=76AC ES=76AC PS=F056 V0 D0 I0 T0 S0 Z1 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (290 opcodes, 4592 cycles, 1595611346345 ms, 0 hz)
    AX=3E0B BX=0005 CX=0000 DX=0000 SP=8F98 BP=0000 SI=0086 DI=7F2F 
    SS=76AC DS=76AC ES=76AC PS=F093 V0 D0 I0 T0 S1 Z0 A1 P0 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (287 opcodes, 4609 cycles, 1595611348567 ms, 0 hz)
    AX=3700 BX=769C CX=0000 DX=0000 SP=8F88 BP=0000 SI=0086 DI=7F2F 
    SS=76AC DS=76AC ES=76AC PS=F056 V0 D0 I0 T0 S0 Z1 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (401 opcodes, 5309 cycles, 1595611349284 ms, 0 hz)
    AX=4B01 BX=8092 CX=0000 DX=0082 SP=8F86 BP=0000 SI=0087 DI=7F2F 
    SS=76AC DS=76AC ES=76AC PS=F056 V0 D0 I0 T0 S0 Z1 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (24 opcodes, 355 cycles, 1595611354959 ms, 0 hz)
    AX=48AC BX=FFFF CX=0000 DX=0082 SP=017A BP=0000 SI=0087 DI=7F2F 
    SS=0A4E DS=76AC ES=76AC PS=F012 V0 D0 I0 T0 S0 Z0 A1 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (881 opcodes, 11947 cycles, 1595611360280 ms, 0 hz)
    AX=4808 BX=0059 CX=0000 DX=0082 SP=017A BP=0000 SI=0087 DI=7F2F 
    SS=0A4E DS=76AC ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (882 opcodes, 11908 cycles, 1595611363843 ms, 0 hz)
    AX=49A7 BX=7FA7 CX=0000 DX=0082 SP=017A BP=0000 SI=0087 DI=7F2F 
    SS=0A4E DS=76AC ES=7FA7 PS=F812 V1 D0 I0 T0 S0 Z0 A1 P0 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (2284 opcodes, 28320 cycles, 1595611369622 ms, 0 hz)
    AX=3D00 BX=7FA7 CX=0000 DX=0939 SP=017A BP=0000 SI=054E DI=7F2F 
    SS=0A4E DS=0A4E ES=7FA7 PS=F083 V0 D0 I0 T0 S1 Z0 A0 P0 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> db ds:dx
    &0A4E:0939  43 3A 5C 43 4F 4D 4D 41-4E 44 2E 43 4F 4D 00 00  C:\COMMAND.COM..
    &0A4E:0949  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &0A4E:0959  00 00 00 00 00 00 00 00-2C 01 B0 7C 03 0A 00 80  ........,..|....
    &0A4E:0969  EE 8B 01 00 03 01 01 01-00 01 00 00 FF FF 00 00  ................
    &0A4E:0979  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &0A4E:0989  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &0A4E:0999  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &0A4E:09A9  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    >> g
    running
    bp &0A4E:0180 hit
    stopped (2048 opcodes, 22894 cycles, 1595611392501 ms, 0 hz)
    AX=4200 BX=0005 CX=0000 DX=3F30 SP=017A BP=0000 SI=054E DI=7F2F 
    SS=0A4E DS=0A4E ES=7FA7 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (278 opcodes, 4387 cycles, 1595611395596 ms, 0 hz)
    AX=3F30 BX=0005 CX=054E DX=0000 SP=017A BP=0000 SI=054E DI=7F2F 
    SS=0A4E DS=7FA7 ES=7FA7 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (6816 opcodes, 96439 cycles, 1595611399631 ms, 0 hz)
    AX=3E4E BX=0005 CX=054E DX=0000 SP=0178 BP=0000 SI=054E DI=7F2F 
    SS=0A4E DS=7FA7 ES=7FA7 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (2317 opcodes, 28844 cycles, 1595611400954 ms, 0 hz)
    AX=3300 BX=0005 CX=0000 DX=8D1E SP=0176 BP=0000 SI=054E DI=7F2F 
    SS=0A4E DS=7FA7 ES=7FA7 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (239 opcodes, 3996 cycles, 1595611402041 ms, 0 hz)
    AX=3301 BX=0005 CX=0000 DX=0000 SP=0176 BP=0000 SI=054E DI=7F2F 
    SS=0A4E DS=7FA7 ES=7FA7 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (212 opcodes, 3362 cycles, 1595611402839 ms, 0 hz)
    AX=5100 BX=0005 CX=0000 DX=0000 SP=0176 BP=0000 SI=054E DI=7F2F 
    SS=0A4E DS=7FA7 ES=7FA7 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (101 opcodes, 1730 cycles, 1595611403611 ms, 0 hz)
    AX=1900 BX=8F74 CX=0000 DX=0000 SP=0176 BP=0000 SI=054E DI=7F2F 
    SS=0A4E DS=7FA7 ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (96 opcodes, 1538 cycles, 1595611404470 ms, 0 hz)
    AX=0E02 BX=8F74 CX=0000 DX=0002 SP=0176 BP=0000 SI=054E DI=7F2F 
    SS=0A4E DS=7FA7 ES=76AC PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (124 opcodes, 1981 cycles, 1595611405308 ms, 0 hz)
    AX=3D00 BX=8092 CX=0004 DX=0082 SP=0176 BP=0000 SI=8F74 DI=7F2F 
    SS=0A4E DS=76AC ES=76AC PS=F097 V0 D0 I0 T0 S1 Z0 A1 P1 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> db ds:dx
    &76AC:0082  45 2E 43 4F 4D 00 3A 5C-54 4F 4F 4C 53 0D 34 4C  E.COM.:\TOOLS.4L
    &76AC:0092  49 42 0D 49 4E 43 0D 5C-4D 41 53 4D 34 3B 43 3A  IB.INC.\MASM4;C:
    &76AC:00A2  5C 54 4F 4F 4C 53 5C 42-49 4E 3B 43 3A 5C 44 4F  \TOOLS\BIN;C:\DO
    &76AC:00B2  53 0D 00 00 00 00 00 00-00 00 00 00 00 00 00 00  S...............
    &76AC:00C2  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &76AC:00D2  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &76AC:00E2  00 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00  ................
    &76AC:00F2  00 00 00 00 00 00 00 00-00 00 00 00 00 00 53 45  ..............SE
    >> g
    running
    bp &0A4E:0180 hit
    stopped (2603 opcodes, 32451 cycles, 1595611410593 ms, 0 hz)
    AX=4400 BX=0005 CX=0004 DX=0082 SP=0176 BP=0000 SI=8F74 DI=7F2F 
    SS=0A4E DS=76AC ES=76AC PS=F096 V0 D0 I0 T0 S1 Z0 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (365 opcodes, 5493 cycles, 1595611411995 ms, 0 hz)
    AX=4800 BX=000A CX=7F04 DX=0042 SP=0172 BP=0000 SI=8092 DI=009E 
    SS=0A4E DS=769C ES=7691 PS=F017 V0 D0 I0 T0 S0 Z0 A1 P1 C1 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (974 opcodes, 13355 cycles, 1595611412925 ms, 0 hz)
    AX=3FA7 BX=0005 CX=001E DX=0568 SP=0172 BP=0000 SI=009E DI=009E 
    SS=0A4E DS=7FA7 ES=7FA7 PS=F056 V0 D0 I0 T0 S0 Z1 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (1329 opcodes, 19457 cycles, 1595611413859 ms, 0 hz)
    AX=480B BX=FFFF CX=001E DX=0568 SP=0176 BP=0000 SI=009E DI=009E 
    SS=0A4E DS=7FA7 ES=7FA7 PS=F056 V0 D0 I0 T0 S0 Z1 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (786 opcodes, 10378 cycles, 1595611414579 ms, 0 hz)
    AX=4808 BX=004E CX=001E DX=0568 SP=0176 BP=0000 SI=009E DI=009E 
    SS=0A4E DS=7FA7 ES=7FA7 PS=F016 V0 D0 I0 T0 S0 Z0 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (797 opcodes, 10452 cycles, 1595611415465 ms, 0 hz)
    AX=4200 BX=0005 CX=0000 DX=0000 SP=0174 BP=0000 SI=009E DI=009E 
    SS=0A4E DS=7FA7 ES=7FA7 PS=F056 V0 D0 I0 T0 S0 Z1 A1 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (191 opcodes, 2915 cycles, 1595611416260 ms, 0 hz)
    AX=3F00 BX=0005 CX=03E0 DX=0000 SP=0174 BP=0000 SI=009E DI=009E 
    SS=0A4E DS=7FC2 ES=7FA7 PS=F006 V0 D0 I0 T0 S0 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (554 opcodes, 9205 cycles, 1595611417025 ms, 0 hz)
    AX=3EB2 BX=0005 CX=03E0 DX=0000 SP=0176 BP=0000 SI=03DF DI=009E 
    SS=0A4E DS=7FB2 ES=7FA7 PS=F006 V0 D0 I0 T0 S0 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (185 opcodes, 2789 cycles, 1595611417816 ms, 0 hz)
    AX=55B1 BX=0005 CX=03E0 DX=7FB2 SP=0174 BP=0000 SI=0001 DI=009E 
    SS=0A4E DS=7FB1 ES=7FA7 PS=F006 V0 D0 I0 T0 S0 Z0 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    bp &0A4E:0180 hit
    stopped (1364 opcodes, 19457 cycles, 1595611418799 ms, 0 hz)
    AX=0000 BX=0000 CX=00FF DX=0080 SP=0172 BP=0000 SI=8F74 DI=0100 
    SS=0A4E DS=7FB2 ES=7FB2 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
    &0A4E:0180 80FC4B           CMP      AH,4B
    >> g
    running
    suspicious opcode: 0x00 0x00
    stopped (401 opcodes, 6271 cycles, 1595611426736 ms, 0 hz)
    AX=F202 BX=435C CX=00FF DX=0080 SP=0178 BP=0000 SI=8F74 DI=0100 
    SS=0A4E DS=7FB2 ES=4D4F PS=F213 V0 D0 I1 T0 S0 Z0 A1 P0 C1 
    &4D4F:435E 0000             ADD      [BX+SI],AL

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
