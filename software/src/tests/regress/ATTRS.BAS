10 REM ATTRS.BAS: file attribute tests (DOS functions 43h and 57h, read-only
20 REM files, and DIR /A and /S), using the DOS statement
30 F$ = "ATTR.TMP" : G$ = "ATTRRO.TMP" : H$ = "ATTRCP.TMP" : FAILS = 0
40 OPEN F$ FOR OUTPUT AS #1 : PRINT #1, "data" : CLOSE #1
50 DOS &H4300, 0, 0, F$
60 IF DOS(2) <> 32 THEN PRINT "archive failed" : FAILS = FAILS + 1
70 DOS &H4301, 0, 33, F$ : DOS &H4300, 0, 0, F$
80 IF DOS(2) <> 33 THEN PRINT "set read-only failed" : FAILS = FAILS + 1
90 E = 0 : ON ERROR GOTO 900 : OPEN F$ FOR APPEND AS #1 : CLOSE #1
100 IF E <> 75 THEN PRINT "read-only open failed" : FAILS = FAILS + 1
110 E = 0 : ON ERROR GOTO 910 : OPEN F$ FOR OUTPUT AS #1 : CLOSE #1
120 IF E <> 75 THEN PRINT "read-only create failed" : FAILS = FAILS + 1
130 ON ERROR GOTO 0
140 OPEN F$ FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
150 IF L$ <> "data" THEN PRINT "read-only input failed" : FAILS = FAILS + 1
151 REM FOR RANDOM opens a read-only file for reading
152 OPEN F$ AS #1 LEN = 4 : FIELD #1, 4 AS R$ : GET #1, 1
154 IF R$ <> "data" THEN PRINT "read-only random failed" : FAILS = FAILS + 1
156 E = 0 : ON ERROR GOTO 950 : PUT #1, 1
158 IF E <> 70 THEN PRINT "read-only PUT failed" : FAILS = FAILS + 1
159 ON ERROR GOTO 0 : CLOSE #1
160 DEL F$
170 IF ERRORLEVEL = 0 THEN PRINT "read-only delete failed" : FAILS = FAILS + 1
180 DOS &H4301, 0, 2, F$ : DIR F$
190 IF ERRORLEVEL = 0 THEN PRINT "hidden DIR failed" : FAILS = FAILS + 1
200 DIR /A F$
210 IF ERRORLEVEL THEN PRINT "DIR /A failed" : FAILS = FAILS + 1
220 DOS &H4301, 0, &H14, F$ : DOS &H4300, 0, 0, F$
230 IF DOS(2) <> 4 THEN PRINT "directory bit failed" : FAILS = FAILS + 1
240 DIR F$
250 IF ERRORLEVEL THEN PRINT "system DIR failed" : FAILS = FAILS + 1
260 REM Set a handle's time (12:34:56) and date (2-3-2001), which closing keeps
270 DOS &H4301, 0, 0, F$ : DOS &H3D02, 0, 0, F$ : H = DOS(0)
280 T = 12 * 2048 + 34 * 32 + 28 : D = 21 * 512 + 2 * 32 + 3
290 DOS &H5701, H, T, D : DOS &H5700, H
300 IF DOS(2) <> T OR DOS(3) <> D THEN PRINT "get time failed" : FAILS = FAILS + 1
310 DOS &H4000, H, 2, "xy" : DOS &H3E00, H
320 D$ = DIR$(F$)
330 IF CVI(MID$(D$, 2)) <> T OR CVI(MID$(D$, 4)) <> D THEN PRINT "set time failed" : FAILS = FAILS + 1
332 REM COPY keeps the date and time
334 COPY F$ H$ : D$ = DIR$(H$) : DEL H$
336 IF CVI(MID$(D$, 2)) <> T OR CVI(MID$(D$, 4)) <> D THEN PRINT "copy time failed" : FAILS = FAILS + 1
340 REM A file created read-only is writable until it's closed
350 DOS &H3C00, 0, 1, G$ : H = DOS(0)
360 DOS &H4000, H, 3, "abc"
370 IF DOS(0) <> 3 THEN PRINT "read-only create write failed" : FAILS = FAILS + 1
380 DOS &H3E00, H : DOS &H4300, 0, 0, G$
390 IF DOS(2) <> 33 THEN PRINT "read-only create attributes failed" : FAILS = FAILS + 1
400 E = 0 : ON ERROR GOTO 920 : DOS &H3D01, 0, 0, G$
410 IF E <> 70 THEN PRINT "read-only DOS open failed" : FAILS = FAILS + 1
420 E = 0 : ON ERROR GOTO 930 : X = DOS(4)
430 IF E <> 5 THEN PRINT "DOS(4) failed" : FAILS = FAILS + 1
440 E = 0 : ON ERROR GOTO 940 : DOS &H4300, 0, 0, "NOSUCH.TMP"
450 IF E <> 53 THEN PRINT "missing file failed" : FAILS = FAILS + 1
460 ON ERROR GOTO 0
470 DOS &H4301, 0, 0, G$ : DEL G$ : DEL F$
480 IF ERRORLEVEL THEN PRINT "cleanup failed" : FAILS = FAILS + 1
490 MD ATTRD : OPEN "ATTRD\ATTRS.TMP" FOR OUTPUT AS #1 : CLOSE #1
500 DIR ATTRS.TMP
510 IF ERRORLEVEL = 0 THEN PRINT "DIR without /S failed" : FAILS = FAILS + 1
520 DIR /S ATTRS.TMP
530 IF ERRORLEVEL THEN PRINT "DIR /S failed" : FAILS = FAILS + 1
540 DEL ATTRD\ATTRS.TMP : RD ATTRD
550 IF FAILS THEN PRINT "ATTRS failed" ELSE PRINT "ATTRS passed"
560 END
900 E = ERR : RESUME 100
910 E = ERR : RESUME 120
920 E = ERR : RESUME 410
930 E = ERR : RESUME 430
940 E = ERR : RESUME 450
950 E = ERR : RESUME 158
