## Debugging Notes

### SYMDEB

Needs a machine with at least 64K of RAM.

Needs DOS functions 29h (parse file name) and 37h (get switchar).

Makes some weird memory accesses around &0507:5D34 (far above 64K).
Before that, loads ES with our DOS segment, using a variable at DS:8E94:

    >> u 5d49
    SYMDEB.EXE+0x5F49:
    &0507:5D49 8E06948E         MOV      ES,[8E94]
    &0507:5D4D 06               PUSH     ES
    &0507:5D4E 51               PUSH     CX
    &0507:5D4F 26               ES:     
    &0507:5D50 8B0E0A00         MOV      CX,[000A]
    &0507:5D54 26               ES:     
    &0507:5D55 8E060C00         MOV      ES,[000C]
    &0507:5D59 E30E             JCXZ     5D69 (SYMDEB.EXE+0x5F69)
    &0507:5D5B 26               ES:     
    &0507:5D5C 39060600         CMP      [0006],AX
    &0507:5D60 742F             JZ       5D91 (SYMDEB.EXE+0x5F91)
    &0507:5D62 26               ES:     
    &0507:5D63 8E060000         MOV      ES,[0000]
    &0507:5D67 E2F2             LOOP     5D5B (SYMDEB.EXE+0x5F5B)
    &0507:5D69 59               POP      CX
    &0507:5D6A 07               POP      ES

