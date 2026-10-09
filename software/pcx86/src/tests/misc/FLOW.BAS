10 REM FLOW.BAS: BASIC-DOS control flow tests (prints "failed" on error)
20 DEFINT A-Z
30 T = 0 : FOR I = 1 TO 10 : T = T + I : NEXT I
40 IF T <> 55 OR I <> 11 THEN PRINT "FOR failed:"; T; I
50 T = 0 : FOR I = 10 TO 1 STEP -3 : T = T + I : NEXT
60 IF T <> 22 OR I <> -2 THEN PRINT "FOR STEP failed:"; T; I
70 T = 0 : FOR I = 5 TO 4 : T = 1 : NEXT
80 IF T <> 0 OR I <> 5 THEN PRINT "FOR skip failed"
90 N = 3 : T = 0 : FOR I = 1 TO N : N = 10 : T = T + 1 : NEXT
100 IF T <> 3 THEN PRINT "FOR limit failed:"; T
110 D# = 0 : FOR X# = 0 TO 1 STEP .25 : D# = D# + X# : NEXT X#
120 IF D# <> 2.5 OR X# <> 1.25 THEN PRINT "FOR double failed"
130 T = 0 : FOR I = 1 TO 3 : FOR J = 1 TO I : T = T + 1 : NEXT J, I
140 IF T <> 6 THEN PRINT "nested FOR failed:"; T
150 T = 0 : FOR I = 1 TO 4 : FOR J = 1 TO 4 : IF J > I THEN GOTO 170
160 T = T + 1
170 NEXT J, I : GOTO 190
180 REM unreachable
190 IF T <> 10 THEN PRINT "GOTO in FOR failed:"; T
200 N = 0 : WHILE N < 5 : N = N + 1 : WEND
210 IF N <> 5 THEN PRINT "WHILE failed"
220 N = 0 : T = 0 : WHILE N < 3 : M = 0 : WHILE M < 2 : M = M + 1 : T = T + 1 : WEND : N = N + 1 : WEND
230 IF T <> 6 THEN PRINT "nested WHILE failed:"; T
240 S$ = "" : WHILE LEN(S$) < 4 : S$ = S$ + "X" : WEND
250 IF S$ <> "XXXX" THEN PRINT "WHILE string failed"
260 N = 0 : WHILE 0 : N = 1 : WEND
270 IF N <> 0 THEN PRINT "WHILE skip failed"
280 R = 0 : GOSUB 3460
290 IF R <> 1 THEN PRINT "GOSUB failed"
300 F = 1 : K = 6 : GOSUB 3470
310 IF F <> 720 THEN PRINT "recursive GOSUB failed:"; F
320 T = 0 : FOR I = 1 TO 5 : ON I GOSUB 3490, 3500 : NEXT
330 IF T <> 11 THEN PRINT "ON GOSUB failed:"; T
340 ON 2 GOTO 3510, 3520
350 PRINT "ON GOTO failed"
360 X = 0 : ON 3 GOTO 3510, 3510 : X = 1
370 IF X <> 1 THEN PRINT "ON range failed"
380 DEF SUMTO(N)
390 S = 0 : FOR Q = 1 TO N : S = S + Q : NEXT
400 RETURN S
410 IF SUMTO(4) <> 10 THEN PRINT "FOR in DEF failed"
420 P = P + 1
430 P = P + 1
440 P = P + 1
450 P = P + 1
460 P = P + 1
470 P = P + 1
480 P = P + 1
490 P = P + 1
500 P = P + 1
510 P = P + 1
520 P = P + 1
530 P = P + 1
540 P = P + 1
550 P = P + 1
560 P = P + 1
570 P = P + 1
580 P = P + 1
590 P = P + 1
600 P = P + 1
610 P = P + 1
620 P = P + 1
630 P = P + 1
640 P = P + 1
650 P = P + 1
660 P = P + 1
670 P = P + 1
680 P = P + 1
690 P = P + 1
700 P = P + 1
710 P = P + 1
720 P = P + 1
730 P = P + 1
740 P = P + 1
750 P = P + 1
760 P = P + 1
770 P = P + 1
780 P = P + 1
790 P = P + 1
800 P = P + 1
810 P = P + 1
820 P = P + 1
830 P = P + 1
840 P = P + 1
850 P = P + 1
860 P = P + 1
870 P = P + 1
880 P = P + 1
890 P = P + 1
900 P = P + 1
910 P = P + 1
920 P = P + 1
930 P = P + 1
940 P = P + 1
950 P = P + 1
960 P = P + 1
970 P = P + 1
980 P = P + 1
990 P = P + 1
1000 P = P + 1
1010 P = P + 1
1020 P = P + 1
1030 P = P + 1
1040 P = P + 1
1050 P = P + 1
1060 P = P + 1
1070 P = P + 1
1080 P = P + 1
1090 P = P + 1
1100 P = P + 1
1110 P = P + 1
1120 P = P + 1
1130 P = P + 1
1140 P = P + 1
1150 P = P + 1
1160 P = P + 1
1170 P = P + 1
1180 P = P + 1
1190 P = P + 1
1200 P = P + 1
1210 P = P + 1
1220 P = P + 1
1230 P = P + 1
1240 P = P + 1
1250 P = P + 1
1260 P = P + 1
1270 P = P + 1
1280 P = P + 1
1290 P = P + 1
1300 P = P + 1
1310 P = P + 1
1320 P = P + 1
1330 P = P + 1
1340 P = P + 1
1350 P = P + 1
1360 P = P + 1
1370 P = P + 1
1380 P = P + 1
1390 P = P + 1
1400 P = P + 1
1410 P = P + 1
1420 P = P + 1
1430 P = P + 1
1440 P = P + 1
1450 P = P + 1
1460 P = P + 1
1470 P = P + 1
1480 P = P + 1
1490 P = P + 1
1500 P = P + 1
1510 P = P + 1
1520 P = P + 1
1530 P = P + 1
1540 P = P + 1
1550 P = P + 1
1560 P = P + 1
1570 P = P + 1
1580 P = P + 1
1590 P = P + 1
1600 P = P + 1
1610 P = P + 1
1620 P = P + 1
1630 P = P + 1
1640 P = P + 1
1650 P = P + 1
1660 P = P + 1
1670 P = P + 1
1680 P = P + 1
1690 P = P + 1
1700 P = P + 1
1710 P = P + 1
1720 P = P + 1
1730 P = P + 1
1740 P = P + 1
1750 P = P + 1
1760 P = P + 1
1770 P = P + 1
1780 P = P + 1
1790 P = P + 1
1800 P = P + 1
1810 P = P + 1
1820 P = P + 1
1830 P = P + 1
1840 P = P + 1
1850 P = P + 1
1860 P = P + 1
1870 P = P + 1
1880 P = P + 1
1890 P = P + 1
1900 P = P + 1
1910 P = P + 1
1920 GOTO 1940
1930 PRINT "far GOTO failed"
1940 P = P + 1
1950 P = P + 1
1960 P = P + 1
1970 P = P + 1
1980 P = P + 1
1990 P = P + 1
2000 P = P + 1
2010 P = P + 1
2020 P = P + 1
2030 P = P + 1
2040 P = P + 1
2050 P = P + 1
2060 P = P + 1
2070 P = P + 1
2080 P = P + 1
2090 P = P + 1
2100 P = P + 1
2110 P = P + 1
2120 P = P + 1
2130 P = P + 1
2140 P = P + 1
2150 P = P + 1
2160 P = P + 1
2170 P = P + 1
2180 P = P + 1
2190 P = P + 1
2200 P = P + 1
2210 P = P + 1
2220 P = P + 1
2230 P = P + 1
2240 P = P + 1
2250 P = P + 1
2260 P = P + 1
2270 P = P + 1
2280 P = P + 1
2290 P = P + 1
2300 P = P + 1
2310 P = P + 1
2320 P = P + 1
2330 P = P + 1
2340 P = P + 1
2350 P = P + 1
2360 P = P + 1
2370 P = P + 1
2380 P = P + 1
2390 P = P + 1
2400 P = P + 1
2410 P = P + 1
2420 P = P + 1
2430 P = P + 1
2440 P = P + 1
2450 P = P + 1
2460 P = P + 1
2470 P = P + 1
2480 P = P + 1
2490 P = P + 1
2500 P = P + 1
2510 P = P + 1
2520 P = P + 1
2530 P = P + 1
2540 P = P + 1
2550 P = P + 1
2560 P = P + 1
2570 P = P + 1
2580 P = P + 1
2590 P = P + 1
2600 P = P + 1
2610 P = P + 1
2620 P = P + 1
2630 P = P + 1
2640 P = P + 1
2650 P = P + 1
2660 P = P + 1
2670 P = P + 1
2680 P = P + 1
2690 P = P + 1
2700 P = P + 1
2710 P = P + 1
2720 P = P + 1
2730 P = P + 1
2740 P = P + 1
2750 P = P + 1
2760 P = P + 1
2770 P = P + 1
2780 P = P + 1
2790 P = P + 1
2800 P = P + 1
2810 P = P + 1
2820 P = P + 1
2830 P = P + 1
2840 P = P + 1
2850 P = P + 1
2860 P = P + 1
2870 P = P + 1
2880 P = P + 1
2890 P = P + 1
2900 P = P + 1
2910 P = P + 1
2920 P = P + 1
2930 P = P + 1
2940 P = P + 1
2950 P = P + 1
2960 P = P + 1
2970 P = P + 1
2980 P = P + 1
2990 P = P + 1
3000 P = P + 1
3010 P = P + 1
3020 P = P + 1
3030 P = P + 1
3040 P = P + 1
3050 P = P + 1
3060 P = P + 1
3070 P = P + 1
3080 P = P + 1
3090 P = P + 1
3100 P = P + 1
3110 P = P + 1
3120 P = P + 1
3130 P = P + 1
3140 P = P + 1
3150 P = P + 1
3160 P = P + 1
3170 P = P + 1
3180 P = P + 1
3190 P = P + 1
3200 P = P + 1
3210 P = P + 1
3220 P = P + 1
3230 P = P + 1
3240 P = P + 1
3250 P = P + 1
3260 P = P + 1
3270 P = P + 1
3280 P = P + 1
3290 P = P + 1
3300 P = P + 1
3310 P = P + 1
3320 P = P + 1
3330 P = P + 1
3340 P = P + 1
3350 P = P + 1
3360 P = P + 1
3370 P = P + 1
3380 P = P + 1
3390 P = P + 1
3400 P = P + 1
3410 P = P + 1
3420 P = P + 1
3430 P = P + 1
3440 IF P <> 300 THEN PRINT "padding failed"
3441 IF SGN(-3) <> -1 OR SGN(0) <> 0 OR SGN(2) <> 1 THEN PRINT "SGN failed"
3442 IF CINT(2.4) <> 2 OR CINT(-2.6) <> -3 THEN PRINT "CINT failed"
3443 X = 5 : Y = 7 : SWAP X, Y : IF X <> 7 OR Y <> 5 THEN PRINT "SWAP failed"
3444 RANDOMIZE 9 : A# = RND : RANDOMIZE 9 : IF RND <> A# THEN PRINT "RANDOMIZE failed"
3445 ON ERROR GOTO 3525 : ERROR 12
3446 IF E <> 3445 THEN PRINT "ERL failed"
3447 ON ERROR GOTO 0
3450 GOTO 3530
3460 R = R + 1 : RETURN
3470 IF K <= 1 THEN RETURN
3480 F = F * K : K = K - 1 : GOSUB 3470 : RETURN
3490 T = T + 1 : RETURN
3500 T = T + 10 : RETURN
3510 PRINT "ON GOTO wrong target" : GOTO 3530
3520 GOTO 360
3525 E = ERL : RESUME 3446
3530 PRINT "FLOW done" : END
