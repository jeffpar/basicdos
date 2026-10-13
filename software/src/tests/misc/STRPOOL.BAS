10 REM STRPOOL.BAS: BASIC-DOS string pool tests (prints "failed" on error)
20 DEFINT A-Z
30 F0 = FRE(0)
40 P$ = "" : I = 0
50 P$ = P$ + CHR$(33 + (I * 7) MOD 90) : I = I + 1 : IF I < 255 THEN GOTO 50
60 S0 = 1 : L0 = 0
70 S1 = 1 : L1 = 0
80 S2 = 1 : L2 = 0
90 S3 = 1 : L3 = 0
100 S4 = 1 : L4 = 0
110 S5 = 1 : L5 = 0
120 S6 = 1 : L6 = 0
130 S7 = 1 : L7 = 0
140 S8 = 1 : L8 = 0
150 S9 = 1 : L9 = 0
160 G$ = "" : GL = 0 : I = 1
170 K = I MOD 10 : S = (I * 37) MOD 200 + 1 : N = (I * 53) MOD 56
180 IF K = 0 THEN V0$ = MID$(P$, S, N) : S0 = S : L0 = N
190 IF K = 1 THEN V1$ = MID$(P$, S, N) : S1 = S : L1 = N
200 IF K = 2 THEN V2$ = MID$(P$, S, N) : S2 = S : L2 = N
210 IF K = 3 THEN V3$ = MID$(P$, S, N) : S3 = S : L3 = N
220 IF K = 4 THEN V4$ = MID$(P$, S, N) : S4 = S : L4 = N
230 IF K = 5 THEN V5$ = MID$(P$, S, N) : S5 = S : L5 = N
240 IF K = 6 THEN V6$ = MID$(P$, S, N) : S6 = S : L6 = N
250 IF K = 7 THEN V7$ = MID$(P$, S, N) : S7 = S : L7 = N
260 IF K = 8 THEN V8$ = MID$(P$, S, N) : S8 = S : L8 = N
270 IF K = 9 THEN V9$ = MID$(P$, S, N) : S9 = S : L9 = N
280 J = (I * 7) MOD 10
290 IF J = 0 AND V0$ <> MID$(P$, S0, L0) THEN PRINT "pool failed at"; I; 0
300 IF J = 1 AND V1$ <> MID$(P$, S1, L1) THEN PRINT "pool failed at"; I; 1
310 IF J = 2 AND V2$ <> MID$(P$, S2, L2) THEN PRINT "pool failed at"; I; 2
320 IF J = 3 AND V3$ <> MID$(P$, S3, L3) THEN PRINT "pool failed at"; I; 3
330 IF J = 4 AND V4$ <> MID$(P$, S4, L4) THEN PRINT "pool failed at"; I; 4
340 IF J = 5 AND V5$ <> MID$(P$, S5, L5) THEN PRINT "pool failed at"; I; 5
350 IF J = 6 AND V6$ <> MID$(P$, S6, L6) THEN PRINT "pool failed at"; I; 6
360 IF J = 7 AND V7$ <> MID$(P$, S7, L7) THEN PRINT "pool failed at"; I; 7
370 IF J = 8 AND V8$ <> MID$(P$, S8, L8) THEN PRINT "pool failed at"; I; 8
380 IF J = 9 AND V9$ <> MID$(P$, S9, L9) THEN PRINT "pool failed at"; I; 9
390 X$ = V1$ + "-" + V2$
400 IF LEFT$(X$, LEN(V1$)) <> V1$ OR RIGHT$(X$, LEN(V2$)) <> V2$ THEN PRINT "temp failed at"; I
410 G$ = G$ + MID$(P$, S, 3) : GL = GL + 3
420 IF GL > 240 THEN G$ = MID$(G$, 100) : GL = GL - 99
430 IF LEN(G$) <> GL THEN PRINT "grow failed at"; I
440 I = I + 1 : IF I <= 1500 THEN GOTO 170
450 IF V0$ <> MID$(P$, S0, L0) THEN PRINT "final check failed"; 0
460 IF V1$ <> MID$(P$, S1, L1) THEN PRINT "final check failed"; 1
470 IF V2$ <> MID$(P$, S2, L2) THEN PRINT "final check failed"; 2
480 IF V3$ <> MID$(P$, S3, L3) THEN PRINT "final check failed"; 3
490 IF V4$ <> MID$(P$, S4, L4) THEN PRINT "final check failed"; 4
500 IF V5$ <> MID$(P$, S5, L5) THEN PRINT "final check failed"; 5
510 IF V6$ <> MID$(P$, S6, L6) THEN PRINT "final check failed"; 6
520 IF V7$ <> MID$(P$, S7, L7) THEN PRINT "final check failed"; 7
530 IF V8$ <> MID$(P$, S8, L8) THEN PRINT "final check failed"; 8
540 IF V9$ <> MID$(P$, S9, L9) THEN PRINT "final check failed"; 9
550 V0$ = "" : V1$ = "" : V2$ = "" : V3$ = "" : V4$ = "" : V5$ = "" : V6$ = "" : V7$ = "" : V8$ = "" : V9$ = ""
560 G$ = "" : X$ = "" : P$ = ""
570 F1 = FRE(0)
580 IF F1 <> F0 THEN PRINT "leak check failed:"; F0 - F1
590 PRINT "STRPOOL done"
