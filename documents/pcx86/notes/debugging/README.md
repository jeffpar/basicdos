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

---

>> d dos 3c6
dumpMCB(0x03C6)
03C6:0000: 'M' PID=0x0008 LEN=0x0002 ""
03C9:0000: 'M' PID=0x0008 LEN=0x0002 ""
03CC:0000: 'M' PID=0x03CD LEN=0x00B6 ""
0483:0000: 'M' PID=0x0484 LEN=0x00B6 ""
053A:0000: 'M' PID=0x053B LEN=0x090B ""
>> reset
bw &054B:8E96 hit
stopped (54106 opcodes, -309830456 cycles, 1594950362638 ms, 0 hz)
AX=0000 BX=0030 CX=0E5D DX=0C00 SP=DFF2 BP=0000 SI=0000 DI=2346 
SS=F000 DS=0000 ES=0C00 PS=F046 V0 D0 I0 T0 S0 Z1 A0 P1 C0 
&F000:E1B6 81C20004         ADD      DX,0400
>> g
running
*bw &054B:8E96 hit
stopped (15638721 opcodes, 201244079 cycles, 1594950369740 ms, 0 hz)
AX=009D BX=0201 CX=0003 DX=0073 SP=0AC6 BP=02D0 SI=0366 DI=0E96 
SS=03CD DS=0116 ES=0D4B PS=F207 V0 D0 I1 T0 S0 Z0 A0 P1 C1 
&0116:0216 7301             JNC      0219 (IBMBIO.COM+0x0E83)
>> g
running
bw &054B:8E96 hit
stopped (47588 opcodes, 577014 cycles, 1594950375228 ms, 0 hz)
AX=0E45 BX=0331 CX=0004 DX=08FA SP=8F9E BP=0000 SI=0100 DI=7EC9 
SS=054B DS=054B ES=054B PS=F246 V0 D0 I1 T0 S0 Z1 A0 P1 C0 
&054B:4C85 A3988E           MOV      [8E98],AX
>> d dos 3c6
dumpMCB(0x03C6)
03C6:0000: 'M' PID=0x0008 LEN=0x0002 ""
03C9:0000: 'M' PID=0x0008 LEN=0x0002 ""
03CC:0000: 'M' PID=0x03CD LEN=0x00B6 ""
0483:0000: 'M' PID=0x0484 LEN=0x00B6 ""
053A:0000: 'M' PID=0x053B LEN=0x090B ""
0E46:0000: 'Z' PID=0x0000 LEN=0x01B9 ""
>> dh 1000 1000
1000 instructions earlier:
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32E 5F               POP      DI                       ;history=997
&F000:F32F 5E               POP      SI                       ;history=996
&F000:F330 C3               RET                               ;history=995
&F000:F2B6 03F5             ADD      SI,BP                    ;history=994
&F000:F2B8 03FD             ADD      DI,BP                    ;history=993
&F000:F2BA FECC             DEC      AH                       ;history=992
&F000:F2BC 75F5             JNZ      F2B3 (romBIOS+0x12B3)    ;history=991
&F000:F2B3 E87200           CALL     F328 (romBIOS+0x1328)    ;history=990
&F000:F328 8ACA             MOV      CL,DL                    ;history=989
&F000:F32A 56               PUSH     SI                       ;history=988
&F000:F32B 57               PUSH     DI                       ;history=987
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&0106:0081 9A30050000       CALL     &0000:0530 (IBMDOS.COM+0x;history=971
&0000:0530 EA4B036301       JMP      &0163:034B (IBMDOS.COM+0x;history=970
&0163:034B 2E               CS:     
&0163:0350 F8               CLC                               ;history=968
&0163:0351 CB               RETF                              ;history=967
&0106:0086 9C               PUSHF                             ;history=966
&0106:0087 2E               CS:     
&F000:FEA5 FB               STI                               ;history=964
&F000:FEA6 1E               PUSH     DS                       ;history=963
&F000:FEA7 50               PUSH     AX                       ;history=962
&F000:FEA8 52               PUSH     DX                       ;history=961
&F000:FEA9 E8ADFB           CALL     FA59 (romBIOS+0x1A59)    ;history=960
&F000:FA59 50               PUSH     AX                       ;history=959
&F000:FA5A B84000           MOV      AX,0040                  ;history=958
&F000:FA5D 8ED8             MOV      DS,AX                    ;history=957
&F000:FA5F 58               POP      AX                       ;history=956
&F000:FA60 C3               RET                               ;history=955
&F000:FEAC FF066C00         INC      WORD [006C]              ;history=954
&F000:FEB0 7504             JNZ      FEB6 (romBIOS+0x1EB6)    ;history=953
&F000:FEB6 833E6E0018       CMP      [006E],0018              ;history=952
&F000:FEBB 7515             JNZ      FED2 (romBIOS+0x1ED2)    ;history=951
&F000:FED2 FE0E4000         DEC      BYTE [0040]              ;history=950
&F000:FED6 750B             JNZ      FEE3 (romBIOS+0x1EE3)    ;history=949
&F000:FEE3 CD1C             INT      1C                       ;history=948
&F000:FF4B CF               IRET                              ;history=947
&F000:FEE5 B020             MOV      AL,20                    ;history=946
&F000:FEE7 E620             OUT      20,AL                    ;history=945
&F000:FEE9 5A               POP      DX                       ;history=944
&F000:FEEA 58               POP      AX                       ;history=943
&F000:FEEB 1F               POP      DS                       ;history=942
&F000:FEEC CF               IRET                              ;history=941
&0106:008C 50               PUSH     AX                       ;history=940
&0106:008D 53               PUSH     BX                       ;history=939
&0106:008E 52               PUSH     DX                       ;history=938
&0106:008F 57               PUSH     DI                       ;history=937
&0106:0090 1E               PUSH     DS                       ;history=936
&0106:0091 06               PUSH     ES                       ;history=935
&0106:0092 8CC8             MOV      AX,CS                    ;history=934
&0106:0094 8ED8             MOV      DS,AX                    ;history=933
&0106:0096 BB3400           MOV      BX,0034                  ;history=932
&0106:0099 C43F             LES      DI,[BX]                  ;history=931
&0106:009B FB               STI                               ;history=930
&0106:009C 83FFFF           CMP      DI,FFFF                  ;history=929
&0106:009F 744A             JZ       00EB (IBMBIO.COM+0x0C15) ;history=928
&0106:00EB 07               POP      ES                       ;history=927
&0106:00EC 1F               POP      DS                       ;history=926
&0106:00ED 5F               POP      DI                       ;history=925
&0106:00EE 5A               POP      DX                       ;history=924
&0106:00EF 5B               POP      BX                       ;history=923
&0106:00F0 58               POP      AX                       ;history=922
&0106:00F1 F9               STC                               ;history=921
&0106:00F2 EA35050000       JMP      &0000:0535 (IBMDOS.COM+0x;history=920
&0000:0535 EA52036301       JMP      &0163:0352 (IBMDOS.COM+0x;history=919
&0163:0352 FA               CLI                               ;history=918
&0163:0353 2E               CS:     
&0163:0358 750D             JNZ      0367 (IBMDOS.COM+0x0367) ;history=916
&0163:035A 730B             JNC      0367 (IBMDOS.COM+0x0367) ;history=915
&0163:035C FC               CLD                               ;history=914
&0163:035D 83EC0A           SUB      SP,000A                  ;history=913
&0163:0360 50               PUSH     AX                       ;history=912
&0163:0361 B81618           MOV      AX,1816                  ;history=911
&0163:0364 E94EFF           JMP      02B5 (IBMDOS.COM+0x02B5) ;history=910
&0163:02B5 53               PUSH     BX                       ;history=909
&0163:02B6 51               PUSH     CX                       ;history=908
&0163:02B7 52               PUSH     DX                       ;history=907
&0163:02B8 1E               PUSH     DS                       ;history=906
&0163:02B9 56               PUSH     SI                       ;history=905
&0163:02BA 06               PUSH     ES                       ;history=904
&0163:02BB 57               PUSH     DI                       ;history=903
&0163:02BC 55               PUSH     BP                       ;history=902
&0163:02BD 8BEC             MOV      BP,SP                    ;history=901
&0163:02BF E80000           CALL     02C2 (IBMDOS.COM+0x02C2) ;history=900
&0163:02C2 8CCB             MOV      BX,CS                    ;history=899
&0163:02C4 8EDB             MOV      DS,BX                    ;history=898
&0163:02C6 8EC3             MOV      ES,BX                    ;history=897
&0163:02C8 80FC18           CMP      AH,18                    ;history=896
&0163:02CB 750D             JNZ      02DA (IBMDOS.COM+0x02DA) ;history=895
&0163:02CD 3C25             CMP      AL,25                    ;history=894
&0163:02CF 733C             JNC      030D (IBMDOS.COM+0x030D) ;history=893
&0163:02D1 B452             MOV      AH,52                    ;history=892
&0163:02D3 02E0             ADD      AH,AL                    ;history=891
&0163:02D5 EB28             JMP      02FF (IBMDOS.COM+0x02FF) ;history=890
&0163:02FF 2BDB             SUB      BX,BX                    ;history=889
&0163:0301 8ADC             MOV      BL,AH                    ;history=888
&0163:0303 03DB             ADD      BX,BX                    ;history=887
&0163:0305 FF973801         CALL     WORD [BX+0138]           ;history=886
&0163:2155 FB               STI                               ;history=885
&0163:2156 A10600           MOV      AX,[0006]                ;history=884
&0163:2159 E9F6F7           JMP      1952 (IBMDOS.COM+0x1952) ;history=883
&0163:1952 FB               STI                               ;history=882
&0163:1953 8B1E0600         MOV      BX,[0006]                ;history=881
&0163:1957 85DB             TEST     BX,BX                    ;history=880
&0163:1959 7419             JZ       1974 (IBMDOS.COM+0x1974) ;history=879
&0163:195B 85C0             TEST     AX,AX                    ;history=878
&0163:195D 740C             JZ       196B (IBMDOS.COM+0x196B) ;history=877
&0163:195F 8BD8             MOV      BX,AX                    ;history=876
&0163:1961 9C               PUSHF                             ;history=875
&0163:1962 807F0553         CMP      [BX+05],53               ;history=874
&0163:1966 7402             JZ       196A (IBMDOS.COM+0x196A) ;history=873
&0163:196A 9D               POPF                              ;history=872
&0163:196B 83C328           ADD      BX,0028                  ;history=871
&0163:196E 3B1E2600         CMP      BX,[0026]                ;history=870
&0163:1972 7204             JC       1978 (IBMDOS.COM+0x1978) ;history=869
&0163:1978 3BD8             CMP      BX,AX                    ;history=868
&0163:197A 742B             JZ       19A7 (IBMDOS.COM+0x19A7) ;history=867
&0163:197C F60704           TEST     [BX],04                  ;history=866
&0163:197F 74EA             JZ       196B (IBMDOS.COM+0x196B) ;history=865
&0163:1981 9C               PUSHF                             ;history=864
&0163:1982 807F0553         CMP      [BX+05],53               ;history=863
&0163:1986 7402             JZ       198A (IBMDOS.COM+0x198A) ;history=862
&0163:198A 9D               POPF                              ;history=861
&0163:198B 8B5708           MOV      DX,[BX+08]               ;history=860
&0163:198E 0B570A           OR       DX,[BX+0A]               ;history=859
&0163:1991 75D8             JNZ      196B (IBMDOS.COM+0x196B) ;history=858
&0163:196B 83C328           ADD      BX,0028                  ;history=857
&0163:196E 3B1E2600         CMP      BX,[0026]                ;history=856
&0163:1972 7204             JC       1978 (IBMDOS.COM+0x1978) ;history=855
&0163:1978 3BD8             CMP      BX,AX                    ;history=854
&0163:197A 742B             JZ       19A7 (IBMDOS.COM+0x19A7) ;history=853
&0163:197C F60704           TEST     [BX],04                  ;history=852
&0163:197F 74EA             JZ       196B (IBMDOS.COM+0x196B) ;history=851
&0163:196B 83C328           ADD      BX,0028                  ;history=850
&0163:196E 3B1E2600         CMP      BX,[0026]                ;history=849
&0163:1972 7204             JC       1978 (IBMDOS.COM+0x1978) ;history=848
&0163:1978 3BD8             CMP      BX,AX                    ;history=847
&0163:197A 742B             JZ       19A7 (IBMDOS.COM+0x19A7) ;history=846
&0163:197C F60704           TEST     [BX],04                  ;history=845
&0163:197F 74EA             JZ       196B (IBMDOS.COM+0x196B) ;history=844
&0163:196B 83C328           ADD      BX,0028                  ;history=843
&0163:196E 3B1E2600         CMP      BX,[0026]                ;history=842
&0163:1972 7204             JC       1978 (IBMDOS.COM+0x1978) ;history=841
&0163:1974 8B1E2400         MOV      BX,[0024]                ;history=840
&0163:1978 3BD8             CMP      BX,AX                    ;history=839
&0163:197A 742B             JZ       19A7 (IBMDOS.COM+0x19A7) ;history=838
&0163:19A7 7302             JNC      19AB (IBMDOS.COM+0x19AB) ;history=837
&0163:19AB C3               RET                               ;history=836
&0163:0309 83562000         ADC      [BP+20],0000             ;history=835
&0163:030D 5D               POP      BP                       ;history=834
&0163:030E 9C               PUSHF                             ;history=833
&0163:030F 81FDC202         CMP      BP,02C2                  ;history=832
&0163:0313 7402             JZ       0317 (IBMDOS.COM+0x0317) ;history=831
&0163:0317 9D               POPF                              ;history=830
&0163:0318 5D               POP      BP                       ;history=829
&0163:0319 5F               POP      DI                       ;history=828
&0163:031A 07               POP      ES                       ;history=827
&0163:031B 5E               POP      SI                       ;history=826
&0163:031C 1F               POP      DS                       ;history=825
&0163:031D 5A               POP      DX                       ;history=824
&0163:031E 59               POP      CX                       ;history=823
&0163:031F 5B               POP      BX                       ;history=822
&0163:0320 58               POP      AX                       ;history=821
&0163:0321 83C40A           ADD      SP,000A                  ;history=820
&0163:0324 CF               IRET                              ;history=819
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32E 5F               POP      DI                       ;history=755
&F000:F32F 5E               POP      SI                       ;history=754
&F000:F330 C3               RET                               ;history=753
&F000:F2B6 03F5             ADD      SI,BP                    ;history=752
&F000:F2B8 03FD             ADD      DI,BP                    ;history=751
&F000:F2BA FECC             DEC      AH                       ;history=750
&F000:F2BC 75F5             JNZ      F2B3 (romBIOS+0x12B3)    ;history=749
&F000:F2B3 E87200           CALL     F328 (romBIOS+0x1328)    ;history=748
&F000:F328 8ACA             MOV      CL,DL                    ;history=747
&F000:F32A 56               PUSH     SI                       ;history=746
&F000:F32B 57               PUSH     DI                       ;history=745
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32E 5F               POP      DI                       ;history=666
&F000:F32F 5E               POP      SI                       ;history=665
&F000:F330 C3               RET                               ;history=664
&F000:F2B6 03F5             ADD      SI,BP                    ;history=663
&F000:F2B8 03FD             ADD      DI,BP                    ;history=662
&F000:F2BA FECC             DEC      AH                       ;history=661
&F000:F2BC 75F5             JNZ      F2B3 (romBIOS+0x12B3)    ;history=660
&F000:F2B3 E87200           CALL     F328 (romBIOS+0x1328)    ;history=659
&F000:F328 8ACA             MOV      CL,DL                    ;history=658
&F000:F32A 56               PUSH     SI                       ;history=657
&F000:F32B 57               PUSH     DI                       ;history=656
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32E 5F               POP      DI                       ;history=577
&F000:F32F 5E               POP      SI                       ;history=576
&F000:F330 C3               RET                               ;history=575
&F000:F2B6 03F5             ADD      SI,BP                    ;history=574
&F000:F2B8 03FD             ADD      DI,BP                    ;history=573
&F000:F2BA FECC             DEC      AH                       ;history=572
&F000:F2BC 75F5             JNZ      F2B3 (romBIOS+0x12B3)    ;history=571
&F000:F2B3 E87200           CALL     F328 (romBIOS+0x1328)    ;history=570
&F000:F328 8ACA             MOV      CL,DL                    ;history=569
&F000:F32A 56               PUSH     SI                       ;history=568
&F000:F32B 57               PUSH     DI                       ;history=567
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32C F3               REPZ    
&F000:F32E 5F               POP      DI                       ;history=488
&F000:F32F 5E               POP      SI                       ;history=487
&F000:F330 C3               RET                               ;history=486
&F000:F2B6 03F5             ADD      SI,BP                    ;history=485
&F000:F2B8 03FD             ADD      DI,BP                    ;history=484
&F000:F2BA FECC             DEC      AH                       ;history=483
&F000:F2BC 75F5             JNZ      F2B3 (romBIOS+0x12B3)    ;history=482
&F000:F2BE 58               POP      AX                       ;history=481
&F000:F2BF B020             MOV      AL,20                    ;history=480
&F000:F2C1 E86D00           CALL     F331 (romBIOS+0x1331)    ;history=479
&F000:F331 8ACA             MOV      CL,DL                    ;history=478
&F000:F333 57               PUSH     DI                       ;history=477
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F334 F3               REPZ    
&F000:F336 5F               POP      DI                       ;history=398
&F000:F337 C3               RET                               ;history=397
&F000:F2C4 03FD             ADD      DI,BP                    ;history=396
&F000:F2C6 FECB             DEC      BL                       ;history=395
&F000:F2C8 75F7             JNZ      F2C1 (romBIOS+0x12C1)    ;history=394
&F000:F2CA E88C07           CALL     FA59 (romBIOS+0x1A59)    ;history=393
&F000:FA59 50               PUSH     AX                       ;history=392
&F000:FA5A B84000           MOV      AX,0040                  ;history=391
&F000:FA5D 8ED8             MOV      DS,AX                    ;history=390
&F000:FA5F 58               POP      AX                       ;history=389
&F000:FA60 C3               RET                               ;history=388
&F000:F2CD 803E490007       CMP      [0049],07                ;history=387
&F000:F2D2 7407             JZ       F2DB (romBIOS+0x12DB)    ;history=386
&F000:F2D4 A06500           MOV      AL,[0065]                ;history=385
&F000:F2D7 BAD803           MOV      DX,03D8                  ;history=384
&F000:F2DA EE               OUT      DX,AL                    ;history=383
&F000:F2DB E9E7FE           JMP      F1C5 (romBIOS+0x11C5)    ;history=382
&F000:F1C5 5F               POP      DI                       ;history=381
&F000:F1C6 5E               POP      SI                       ;history=380
&F000:F1C7 5B               POP      BX                       ;history=379
&F000:F1C8 59               POP      CX                       ;history=378
&F000:F1C9 5A               POP      DX                       ;history=377
&F000:F1CA 1F               POP      DS                       ;history=376
&F000:F1CB 07               POP      ES                       ;history=375
&F000:F1CC CF               IRET                              ;history=374
&0098:0507 5D               POP      BP                       ;history=373
&0098:0508 5A               POP      DX                       ;history=372
&0098:0509 59               POP      CX                       ;history=371
&0098:050A 5B               POP      BX                       ;history=370
&0098:050B C3               RET                               ;history=369
&0098:0439 C3               RET                               ;history=368
&0098:056E EB15             JMP      0585 (IBMBIO.COM+0x07BF) ;history=367
&0098:0585 89160800         MOV      [0008],DX                ;history=366
&0098:0589 8CD8             MOV      AX,DS                    ;history=365
&0098:058B 2E               CS:     
&0098:0590 7503             JNZ      0595 (IBMBIO.COM+0x07CF) ;history=363
&0098:0592 E8A5FE           CALL     043A (IBMBIO.COM+0x0674) ;history=362
&0098:043A 8B160800         MOV      DX,[0008]                ;history=361
&0098:043E E85300           CALL     0494 (IBMBIO.COM+0x06CE) ;history=360
&0098:0494 8AC6             MOV      AL,DH                    ;history=359
&0098:0496 2E               CS:     
&0098:049B 03C0             ADD      AX,AX                    ;history=357
&0098:049D 2BDB             SUB      BX,BX                    ;history=356
&0098:049F 8ADA             MOV      BL,DL                    ;history=355
&0098:04A1 03DB             ADD      BX,BX                    ;history=354
&0098:04A3 03D8             ADD      BX,AX                    ;history=353
&0098:04A5 C3               RET                               ;history=352
&0098:0441 031E1000         ADD      BX,[0010]                ;history=351
&0098:0445 D1EB             SHR      BX,1                     ;history=350
&0098:0447 B40E             MOV      AH,0E                    ;history=349
&0098:0449 E89A01           CALL     05E6 (IBMBIO.COM+0x0820) ;history=348
&0098:05E6 8B160E00         MOV      DX,[000E]                ;history=347
&0098:05EA 9C               PUSHF                             ;history=346
&0098:05EB 80FE03           CMP      DH,03                    ;history=345
&0098:05EE 7402             JZ       05F2 (IBMBIO.COM+0x082C) ;history=344
&0098:05F2 9D               POPF                              ;history=343
&0098:05F3 8AC4             MOV      AL,AH                    ;history=342
&0098:05F5 FA               CLI                               ;history=341
&0098:05F6 EE               OUT      DX,AL                    ;history=340
&0098:05F7 42               INC      DX                       ;history=339
&0098:05F8 8AC7             MOV      AL,BH                    ;history=338
&0098:05FA EE               OUT      DX,AL                    ;history=337
&0098:05FB 4A               DEC      DX                       ;history=336
&0098:05FC 8AC4             MOV      AL,AH                    ;history=335
&0098:05FE 40               INC      AX                       ;history=334
&0098:05FF EE               OUT      DX,AL                    ;history=333
&0098:0600 42               INC      DX                       ;history=332
&0098:0601 8AC3             MOV      AL,BL                    ;history=331
&0098:0603 EE               OUT      DX,AL                    ;history=330
&0098:0604 FB               STI                               ;history=329
&0098:0605 4A               DEC      DX                       ;history=328
&0098:0606 C3               RET                               ;history=327
&0098:044C C3               RET                               ;history=326
&0098:0595 07               POP      ES                       ;history=325
&0098:0596 1F               POP      DS                       ;history=324
&0098:0597 5F               POP      DI                       ;history=323
&0098:0598 5A               POP      DX                       ;history=322
&0098:0599 59               POP      CX                       ;history=321
&0098:059A 5B               POP      BX                       ;history=320
&0098:059B 58               POP      AX                       ;history=319
&0098:059C C3               RET                               ;history=318
&0098:014A E2FA             LOOP     0146 (IBMBIO.COM+0x0380) ;history=317
&0098:014C 07               POP      ES                       ;history=316
&0098:014D 26               ES:     
&0098:0153 C3               RET                               ;history=314
&0098:0085 CB               RETF                              ;history=313
&0163:063F 1F               POP      DS                       ;history=312
&0163:0640 5D               POP      BP                       ;history=311
&0163:0641 5F               POP      DI                       ;history=310
&0163:0642 5E               POP      SI                       ;history=309
&0163:0643 59               POP      CX                       ;history=308
&0163:0644 58               POP      AX                       ;history=307
&0163:0645 07               POP      ES                       ;history=306
&0163:0646 8B4603           MOV      AX,[BP+03]               ;history=305
&0163:0649 8B5606           MOV      DX,[BP+06]               ;history=304
&0163:064C 83C41C           ADD      SP,001C                  ;history=303
&0163:064F A90080           TEST     AX,8000                  ;history=302
&0163:0652 7401             JZ       0655 (IBMDOS.COM+0x0655) ;history=301
&0163:0655 5D               POP      BP                       ;history=300
&0163:0656 5B               POP      BX                       ;history=299
&0163:0657 C3               RET                               ;history=298
&0163:0E1B C3               RET                               ;history=297
&0163:0580 EB05             JMP      0587 (IBMDOS.COM+0x0587) ;history=296
&0163:0587 07               POP      ES                       ;history=295
&0163:0588 5F               POP      DI                       ;history=294
&0163:0589 5E               POP      SI                       ;history=293
&0163:058A 5A               POP      DX                       ;history=292
&0163:058B 59               POP      CX                       ;history=291
&0163:058C 5B               POP      BX                       ;history=290
&0163:058D F8               CLC                               ;history=289
&0163:058E C3               RET                               ;history=288
&0163:0309 83562000         ADC      [BP+20],0000             ;history=287
&0163:030D 5D               POP      BP                       ;history=286
&0163:030E 9C               PUSHF                             ;history=285
&0163:030F 81FDC202         CMP      BP,02C2                  ;history=284
&0163:0313 7402             JZ       0317 (IBMDOS.COM+0x0317) ;history=283
&0163:0317 9D               POPF                              ;history=282
&0163:0318 5D               POP      BP                       ;history=281
&0163:0319 5F               POP      DI                       ;history=280
&0163:031A 07               POP      ES                       ;history=279
&0163:031B 5E               POP      SI                       ;history=278
&0163:031C 1F               POP      DS                       ;history=277
&0163:031D 5A               POP      DX                       ;history=276
&0163:031E 59               POP      CX                       ;history=275
&0163:031F 5B               POP      BX                       ;history=274
&0163:0320 58               POP      AX                       ;history=273
&0163:0321 83C40A           ADD      SP,000A                  ;history=272
&0163:0324 CF               IRET                              ;history=271
&054B:0E6C EBF0             JMP      0E5E (SYMDEB.EXE+0x105E) ;history=270
&054B:0E5E 5E               POP      SI                       ;history=269
&054B:0E5F 58               POP      AX                       ;history=268
&054B:0E60 EB01             JMP      0E63 (SYMDEB.EXE+0x1063) ;history=267
&054B:0E63 0E               PUSH     CS                       ;history=266
&054B:0E64 E8FBFF           CALL     0E62 (SYMDEB.EXE+0x1062) ;history=265
&054B:0E62 CF               IRET                              ;history=264
&054B:0E67 C3               RET                               ;history=263
&054B:036C E87105           CALL     08E0 (SYMDEB.EXE+0x0AE0) ;history=262
&054B:08E0 1E               PUSH     DS                       ;history=261
&054B:08E1 0E               PUSH     CS                       ;history=260
&054B:08E2 1F               POP      DS                       ;history=259
&054B:08E3 B82225           MOV      AX,2522                  ;history=258
&054B:08E6 BA8E09           MOV      DX,098E                  ;history=257
&054B:08E9 CD21             INT      21                       ;history=256
&0163:02B0 FC               CLD                               ;history=255
&0163:02B1 83EC0A           SUB      SP,000A                  ;history=254
&0163:02B4 50               PUSH     AX                       ;history=253
&0163:02B5 53               PUSH     BX                       ;history=252
&0163:02B6 51               PUSH     CX                       ;history=251
&0163:02B7 52               PUSH     DX                       ;history=250
&0163:02B8 1E               PUSH     DS                       ;history=249
&0163:02B9 56               PUSH     SI                       ;history=248
&0163:02BA 06               PUSH     ES                       ;history=247
&0163:02BB 57               PUSH     DI                       ;history=246
&0163:02BC 55               PUSH     BP                       ;history=245
&0163:02BD 8BEC             MOV      BP,SP                    ;history=244
&0163:02BF E80000           CALL     02C2 (IBMDOS.COM+0x02C2) ;history=243
&0163:02C2 8CCB             MOV      BX,CS                    ;history=242
&0163:02C4 8EDB             MOV      DS,BX                    ;history=241
&0163:02C6 8EC3             MOV      ES,BX                    ;history=240
&0163:02C8 80FC18           CMP      AH,18                    ;history=239
&0163:02CB 750D             JNZ      02DA (IBMDOS.COM+0x02DA) ;history=238
&0163:02DA FB               STI                               ;history=237
&0163:02DB 816620FEFF       AND      [BP+20],FFFE             ;history=236
&0163:02E0 80FC52           CMP      AH,52                    ;history=235
&0163:02E3 F5               CMC                               ;history=234
&0163:02E4 7223             JC       0309 (IBMDOS.COM+0x0309) ;history=233
&0163:02E6 8B1E0600         MOV      BX,[0006]                ;history=232
&0163:02EA 85DB             TEST     BX,BX                    ;history=231
&0163:02EC 7411             JZ       02FF (IBMDOS.COM+0x02FF) ;history=230
&0163:02EE 9C               PUSHF                             ;history=229
&0163:02EF 807F0553         CMP      [BX+05],53               ;history=228
&0163:02F3 7402             JZ       02F7 (IBMDOS.COM+0x02F7) ;history=227
&0163:02F7 9D               POPF                              ;history=226
&0163:02F8 817F230101       CMP      [BX+23],0101             ;history=225
&0163:02FD 74D8             JZ       02D7 (IBMDOS.COM+0x02D7) ;history=224
&0163:02FF 2BDB             SUB      BX,BX                    ;history=223
&0163:0301 8ADC             MOV      BL,AH                    ;history=222
&0163:0303 03DB             ADD      BX,BX                    ;history=221
&0163:0305 FF973801         CALL     WORD [BX+0138]           ;history=220
&0163:118D E82A01           CALL     12BA (IBMDOS.COM+0x12BA) ;history=219
&0163:12BA B400             MOV      AH,00                    ;history=218
&0163:12BC 03C0             ADD      AX,AX                    ;history=217
&0163:12BE 03C0             ADD      AX,AX                    ;history=216
&0163:12C0 3D8800           CMP      AX,0088                  ;history=215
&0163:12C3 7211             JC       12D6 (IBMDOS.COM+0x12D6) ;history=214
&0163:12C5 3D9400           CMP      AX,0094                  ;history=213
&0163:12C8 F5               CMC                               ;history=212
&0163:12C9 720B             JC       12D6 (IBMDOS.COM+0x12D6) ;history=211
&0163:12CB 2D7800           SUB      AX,0078                  ;history=210
&0163:12CE 03060600         ADD      AX,[0006]                ;history=209
&0163:12D2 7302             JNC      12D6 (IBMDOS.COM+0x12D6) ;history=208
&0163:12D6 C3               RET                               ;history=207
&0163:1190 7304             JNC      1196 (IBMDOS.COM+0x1196) ;history=206
&0163:1196 97               XCHG     AX,DI                    ;history=205
&0163:1197 FA               CLI                               ;history=204
&0163:1198 8B460A           MOV      AX,[BP+0A]               ;history=203
&0163:119B AB               STOSW                             ;history=202
&0163:119C 8B4608           MOV      AX,[BP+08]               ;history=201
&0163:119F AB               STOSW                             ;history=200
&0163:11A0 FB               STI                               ;history=199
&0163:11A1 F8               CLC                               ;history=198
&0163:11A2 C3               RET                               ;history=197
&0163:0309 83562000         ADC      [BP+20],0000             ;history=196
&0163:030D 5D               POP      BP                       ;history=195
&0163:030E 9C               PUSHF                             ;history=194
&0163:030F 81FDC202         CMP      BP,02C2                  ;history=193
&0163:0313 7402             JZ       0317 (IBMDOS.COM+0x0317) ;history=192
&0163:0317 9D               POPF                              ;history=191
&0163:0318 5D               POP      BP                       ;history=190
&0163:0319 5F               POP      DI                       ;history=189
&0163:031A 07               POP      ES                       ;history=188
&0163:031B 5E               POP      SI                       ;history=187
&0163:031C 1F               POP      DS                       ;history=186
&0163:031D 5A               POP      DX                       ;history=185
&0163:031E 59               POP      CX                       ;history=184
&0163:031F 5B               POP      BX                       ;history=183
&0163:0320 58               POP      AX                       ;history=182
&0163:0321 83C40A           ADD      SP,000A                  ;history=181
&0163:0324 CF               IRET                              ;history=180
&054B:08EB 1F               POP      DS                       ;history=179
&054B:08EC C3               RET                               ;history=178
&054B:036F 06               PUSH     ES                       ;history=177
&054B:0370 B82435           MOV      AX,3524                  ;history=176
&054B:0373 CD21             INT      21                       ;history=175
&0163:02B0 FC               CLD                               ;history=174
&0163:02B1 83EC0A           SUB      SP,000A                  ;history=173
&0163:02B4 50               PUSH     AX                       ;history=172
&0163:02B5 53               PUSH     BX                       ;history=171
&0163:02B6 51               PUSH     CX                       ;history=170
&0163:02B7 52               PUSH     DX                       ;history=169
&0163:02B8 1E               PUSH     DS                       ;history=168
&0163:02B9 56               PUSH     SI                       ;history=167
&0163:02BA 06               PUSH     ES                       ;history=166
&0163:02BB 57               PUSH     DI                       ;history=165
&0163:02BC 55               PUSH     BP                       ;history=164
&0163:02BD 8BEC             MOV      BP,SP                    ;history=163
&0163:02BF E80000           CALL     02C2 (IBMDOS.COM+0x02C2) ;history=162
&0163:02C2 8CCB             MOV      BX,CS                    ;history=161
&0163:02C4 8EDB             MOV      DS,BX                    ;history=160
&0163:02C6 8EC3             MOV      ES,BX                    ;history=159
&0163:02C8 80FC18           CMP      AH,18                    ;history=158
&0163:02CB 750D             JNZ      02DA (IBMDOS.COM+0x02DA) ;history=157
&0163:02DA FB               STI                               ;history=156
&0163:02DB 816620FEFF       AND      [BP+20],FFFE             ;history=155
&0163:02E0 80FC52           CMP      AH,52                    ;history=154
&0163:02E3 F5               CMC                               ;history=153
&0163:02E4 7223             JC       0309 (IBMDOS.COM+0x0309) ;history=152
&0163:02E6 8B1E0600         MOV      BX,[0006]                ;history=151
&0163:02EA 85DB             TEST     BX,BX                    ;history=150
&0163:02EC 7411             JZ       02FF (IBMDOS.COM+0x02FF) ;history=149
&0163:02EE 9C               PUSHF                             ;history=148
&0163:02EF 807F0553         CMP      [BX+05],53               ;history=147
&0163:02F3 7402             JZ       02F7 (IBMDOS.COM+0x02F7) ;history=146
&0163:02F7 9D               POPF                              ;history=145
&0163:02F8 817F230101       CMP      [BX+23],0101             ;history=144
&0163:02FD 74D8             JZ       02D7 (IBMDOS.COM+0x02D7) ;history=143
&0163:02FF 2BDB             SUB      BX,BX                    ;history=142
&0163:0301 8ADC             MOV      BL,AH                    ;history=141
&0163:0303 03DB             ADD      BX,BX                    ;history=140
&0163:0305 FF973801         CALL     WORD [BX+0138]           ;history=139
&0163:1266 E85100           CALL     12BA (IBMDOS.COM+0x12BA) ;history=138
&0163:12BA B400             MOV      AH,00                    ;history=137
&0163:12BC 03C0             ADD      AX,AX                    ;history=136
&0163:12BE 03C0             ADD      AX,AX                    ;history=135
&0163:12C0 3D8800           CMP      AX,0088                  ;history=134
&0163:12C3 7211             JC       12D6 (IBMDOS.COM+0x12D6) ;history=133
&0163:12C5 3D9400           CMP      AX,0094                  ;history=132
&0163:12C8 F5               CMC                               ;history=131
&0163:12C9 720B             JC       12D6 (IBMDOS.COM+0x12D6) ;history=130
&0163:12CB 2D7800           SUB      AX,0078                  ;history=129
&0163:12CE 03060600         ADD      AX,[0006]                ;history=128
&0163:12D2 7302             JNC      12D6 (IBMDOS.COM+0x12D6) ;history=127
&0163:12D6 C3               RET                               ;history=126
&0163:1269 7304             JNC      126F (IBMDOS.COM+0x126F) ;history=125
&0163:126F 96               XCHG     AX,SI                    ;history=124
&0163:1270 FA               CLI                               ;history=123
&0163:1271 AD               LODSW                             ;history=122
&0163:1272 89460E           MOV      [BP+0E],AX               ;history=121
&0163:1275 AD               LODSW                             ;history=120
&0163:1276 894604           MOV      [BP+04],AX               ;history=119
&0163:1279 FB               STI                               ;history=118
&0163:127A F8               CLC                               ;history=117
&0163:127B C3               RET                               ;history=116
&0163:0309 83562000         ADC      [BP+20],0000             ;history=115
&0163:030D 5D               POP      BP                       ;history=114
&0163:030E 9C               PUSHF                             ;history=113
&0163:030F 81FDC202         CMP      BP,02C2                  ;history=112
&0163:0313 7402             JZ       0317 (IBMDOS.COM+0x0317) ;history=111
&0163:0317 9D               POPF                              ;history=110
&0163:0318 5D               POP      BP                       ;history=109
&0163:0319 5F               POP      DI                       ;history=108
&0163:031A 07               POP      ES                       ;history=107
&0163:031B 5E               POP      SI                       ;history=106
&0163:031C 1F               POP      DS                       ;history=105
&0163:031D 5A               POP      DX                       ;history=104
&0163:031E 59               POP      CX                       ;history=103
&0163:031F 5B               POP      BX                       ;history=102
&0163:0320 58               POP      AX                       ;history=101
&0163:0321 83C40A           ADD      SP,000A                  ;history=100
&0163:0324 CF               IRET                              ;history=99
&054B:0375 891E7F6D         MOV      [6D7F],BX                ;history=98
&054B:0379 8C06816D         MOV      [6D81],ES                ;history=97
&054B:037D 07               POP      ES                       ;history=96
&054B:037E B82425           MOV      AX,2524                  ;history=95
&054B:0381 BA5609           MOV      DX,0956                  ;history=94
&054B:0384 CD21             INT      21                       ;history=93
&0163:02B0 FC               CLD                               ;history=92
&0163:02B1 83EC0A           SUB      SP,000A                  ;history=91
&0163:02B4 50               PUSH     AX                       ;history=90
&0163:02B5 53               PUSH     BX                       ;history=89
&0163:02B6 51               PUSH     CX                       ;history=88
&0163:02B7 52               PUSH     DX                       ;history=87
&0163:02B8 1E               PUSH     DS                       ;history=86
&0163:02B9 56               PUSH     SI                       ;history=85
&0163:02BA 06               PUSH     ES                       ;history=84
&0163:02BB 57               PUSH     DI                       ;history=83
&0163:02BC 55               PUSH     BP                       ;history=82
&0163:02BD 8BEC             MOV      BP,SP                    ;history=81
&0163:02BF E80000           CALL     02C2 (IBMDOS.COM+0x02C2) ;history=80
&0163:02C2 8CCB             MOV      BX,CS                    ;history=79
&0163:02C4 8EDB             MOV      DS,BX                    ;history=78
&0163:02C6 8EC3             MOV      ES,BX                    ;history=77
&0163:02C8 80FC18           CMP      AH,18                    ;history=76
&0163:02CB 750D             JNZ      02DA (IBMDOS.COM+0x02DA) ;history=75
&0163:02DA FB               STI                               ;history=74
&0163:02DB 816620FEFF       AND      [BP+20],FFFE             ;history=73
&0163:02E0 80FC52           CMP      AH,52                    ;history=72
&0163:02E3 F5               CMC                               ;history=71
&0163:02E4 7223             JC       0309 (IBMDOS.COM+0x0309) ;history=70
&0163:02E6 8B1E0600         MOV      BX,[0006]                ;history=69
&0163:02EA 85DB             TEST     BX,BX                    ;history=68
&0163:02EC 7411             JZ       02FF (IBMDOS.COM+0x02FF) ;history=67
&0163:02EE 9C               PUSHF                             ;history=66
&0163:02EF 807F0553         CMP      [BX+05],53               ;history=65
&0163:02F3 7402             JZ       02F7 (IBMDOS.COM+0x02F7) ;history=64
&0163:02F7 9D               POPF                              ;history=63
&0163:02F8 817F230101       CMP      [BX+23],0101             ;history=62
&0163:02FD 74D8             JZ       02D7 (IBMDOS.COM+0x02D7) ;history=61
&0163:02FF 2BDB             SUB      BX,BX                    ;history=60
&0163:0301 8ADC             MOV      BL,AH                    ;history=59
&0163:0303 03DB             ADD      BX,BX                    ;history=58
&0163:0305 FF973801         CALL     WORD [BX+0138]           ;history=57
&0163:118D E82A01           CALL     12BA (IBMDOS.COM+0x12BA) ;history=56
&0163:12BA B400             MOV      AH,00                    ;history=55
&0163:12BC 03C0             ADD      AX,AX                    ;history=54
&0163:12BE 03C0             ADD      AX,AX                    ;history=53
&0163:12C0 3D8800           CMP      AX,0088                  ;history=52
&0163:12C3 7211             JC       12D6 (IBMDOS.COM+0x12D6) ;history=51
&0163:12C5 3D9400           CMP      AX,0094                  ;history=50
&0163:12C8 F5               CMC                               ;history=49
&0163:12C9 720B             JC       12D6 (IBMDOS.COM+0x12D6) ;history=48
&0163:12CB 2D7800           SUB      AX,0078                  ;history=47
&0163:12CE 03060600         ADD      AX,[0006]                ;history=46
&0163:12D2 7302             JNC      12D6 (IBMDOS.COM+0x12D6) ;history=45
&0163:12D6 C3               RET                               ;history=44
&0163:1190 7304             JNC      1196 (IBMDOS.COM+0x1196) ;history=43
&0163:1196 97               XCHG     AX,DI                    ;history=42
&0163:1197 FA               CLI                               ;history=41
&0163:1198 8B460A           MOV      AX,[BP+0A]               ;history=40
&0163:119B AB               STOSW                             ;history=39
&0163:119C 8B4608           MOV      AX,[BP+08]               ;history=38
&0163:119F AB               STOSW                             ;history=37
&0163:11A0 FB               STI                               ;history=36
&0163:11A1 F8               CLC                               ;history=35
&0163:11A2 C3               RET                               ;history=34
&0163:0309 83562000         ADC      [BP+20],0000             ;history=33
&0163:030D 5D               POP      BP                       ;history=32
&0163:030E 9C               PUSHF                             ;history=31
&0163:030F 81FDC202         CMP      BP,02C2                  ;history=30
&0163:0313 7402             JZ       0317 (IBMDOS.COM+0x0317) ;history=29
&0163:0317 9D               POPF                              ;history=28
&0163:0318 5D               POP      BP                       ;history=27
&0163:0319 5F               POP      DI                       ;history=26
&0163:031A 07               POP      ES                       ;history=25
&0163:031B 5E               POP      SI                       ;history=24
&0163:031C 1F               POP      DS                       ;history=23
&0163:031D 5A               POP      DX                       ;history=22
&0163:031E 59               POP      CX                       ;history=21
&0163:031F 5B               POP      BX                       ;history=20
&0163:0320 58               POP      AX                       ;history=19
&0163:0321 83C40A           ADD      SP,000A                  ;history=18
&0163:0324 CF               IRET                              ;history=17
&054B:0386 E8D848           CALL     4C61 (SYMDEB.EXE+0x4E61) ;history=16
&054B:4C61 8CC8             MOV      AX,CS                    ;history=15
&054B:4C63 BFC17E           MOV      DI,7EC1                  ;history=14
&054B:4C66 FC               CLD                               ;history=13
&054B:4C67 AB               STOSW                             ;history=12
&054B:4C68 AB               STOSW                             ;history=11
&054B:4C69 AB               STOSW                             ;history=10
&054B:4C6A AB               STOSW                             ;history=9
&054B:4C6B BAA08F           MOV      DX,8FA0                  ;history=8
&054B:4C6E B90400           MOV      CX,0004                  ;history=7
&054B:4C71 D3EA             SHR      DX,CL                    ;history=6
&054B:4C73 03C2             ADD      AX,DX                    ;history=5
&054B:4C75 803E7D6D00       CMP      [6D7D],00                ;history=4
&054B:4C7A 7403             JZ       4C7F (SYMDEB.EXE+0x4E7F) ;history=3
&054B:4C7F A3948E           MOV      [8E94],AX                ;history=2
&054B:4C82 A3968E           MOV      [8E96],AX                ;history=1

---

SYMDEB.EXE header:

00000000  4d 5a 9d 00 49 00 04 00  20 00 11 00 ff ff ea 08  |MZ..I... .......|
00000010  00 01 fb 2e 09 01 00 00  1e 00 00 00 01 00 b4 08  |................|
00000020  00 00 e0 58 00 00 71 59  00 00 c0 59 00 00 00 00  |...X..qY...Y....|
00000030  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|

dumpMCB(0x03C6)
03C6:0000: 'M' PID=0x0008 LEN=0x0002 ""
03C9:0000: 'M' PID=0x0008 LEN=0x0002 ""
03CC:0000: 'M' PID=0x03CD LEN=0x00B6 ""
0483:0000: 'M' PID=0x0484 LEN=0x00B6 ""
053A:0000: 'M' PID=0x03CD LEN=0x091A ""
0E55:0000: 'Z' PID=0x0000 LEN=0x01AA ""

SYMDEB.EXE is 37021 (909dh) bytes, 2314 (90Ah) paras.

PSP at 53Bh.  We add 90Ah, plus 10h for the PSP, giving E55h, then we subtract
EXE_PARASHDR (=20h), giving E35h.

After reading header, we read the main EXE (8E9Dh total bytes) starting
at paragraph 54Bh.  1st (8000h byte) chunk bumps next para to D4Bh, and then
the final E9Dh bytes bumps us another EAh paras, for a total of E35h.  Which
aligns with where we loaded the header data.

There are 4 relocation entries, all adjusted by a base segment value of 54Bh.
The adjustments are made at offsets: 08B4, 58E0, 5971, and 59C0.

	mov	es,ax			; ES = PSP segment              53Bh
	sub	dx,ax			; DX = base # paras             DX = E35h - 53Bh = 8FAh
	add	dx,si			; DX = base + minimum           DX = 8FAh + 11h = 90Bh
	mov	bx,dx			; BX = realloc size (in paras)
