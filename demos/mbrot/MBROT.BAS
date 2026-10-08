10 REM MBROT.BAS: draws the Mandelbrot set in SCREEN 2 (640x200)
20 REM Uses 32-bit integers as fixed-point numbers with 12 fraction bits
30 REM (4096 = 1.0), and draws each row and its mirror image at once
40 REM Optional argument: block size (1 = full detail, 2 = default, 4 = fast)
50 DEFINT A-Z:S=VAL(ARG$(1)):IF S<1 THEN S=2
60 SCREEN 2:MX=32
70 FOR R=0 TO 99 STEP S:CY=(R*2+S-200)*27:YY=CY*CY>>12
80 FOR C=0 TO 639 STEP S:CX=(C*2+S-1)*11-10240:X=0:Y=0:X2=0:Y2=0:N=0
90 REM Skip points inside the main cardioid and the period-2 bulb
100 A=CX-1024:Q=(A*A>>12)+YY:B=CX+4096
110 IF (Q*(Q+A)>>12)<YY\4 OR (B*B>>12)+YY<256 THEN N=MX
120 WHILE N<MX AND X2+Y2<16384
130 Y=(X*Y>>11)+CY:X=X2-Y2+CX:X2=X*X>>12:Y2=Y*Y>>12:N=N+1
140 WEND
150 IF N=MX OR (N>6 AND (N AND 1)) THEN GOSUB 200
160 NEXT
170 IF INKEY$=CHR$(27) THEN END
180 NEXT
190 WHILE INKEY$<>CHR$(27):WEND:END
200 LINE (C,R)-(C+S-1,R+S-1),,BF
210 LINE (C,199-R)-(C+S-1,200-R-S),,BF:RETURN
