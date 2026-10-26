10 REM PRTUSING.BAS: BASIC-DOS PRINTF USING tests (prints "failed" on error)
20 OPEN "FT3.DAT" FOR OUTPUT AS #1
30 PRINTF #1, USING "%d|%5d|%-5d|%ld|%u"; 42, -7, 3, 123456, 65535
40 PRINTF #1, USING "%s|%-6s|%.2s|%c%c|%%"; "abc", "de", "fgh", 65, "xyz"
50 PRINTF #1, USING "%f|%.2f|%8.3f|%#d"; 2.5, 3.14159, -1.5, 9
60 PRINTF #1, USING "%x|%s|%d"; 255, 12, "str"
70 PRINTF #1, USING "no newline";
80 PRINTF #1, USING "%s"; " then more"
90 PRINTF #1, USING "%d%%"; 50
92 D% = 23896 : T% = 26813
94 PRINTF #1, USING "%.3W %.3F %2D %Y %X|%H:%02N:%02S %G%A"; D%, D%, D%, D%, D%, T%, T%, T%, T%, T%
100 CLOSE #1
110 OPEN "FT3.DAT" FOR INPUT AS #1
120 LINE INPUT #1, L$
130 IF L$ <> "42|   -7|3    |123456|65535" THEN PRINT "numbers failed: "; L$ : FAILS = FAILS + 1
140 LINE INPUT #1, L$
150 IF L$ <> "abc|de    |fg|Ax|%" THEN PRINT "strings failed: "; L$ : FAILS = FAILS + 1
160 LINE INPUT #1, L$
170 IF L$ <> "2.5|3.14|  -1.500| 9" THEN PRINT "doubles failed: "; L$ : FAILS = FAILS + 1
180 LINE INPUT #1, L$
190 IF L$ <> "FF|%s|%d" THEN PRINT "mismatch failed: "; L$ : FAILS = FAILS + 1
200 LINE INPUT #1, L$
210 IF L$ <> "no newline then more" THEN PRINT "separator failed: "; L$ : FAILS = FAILS + 1
220 LINE INPUT #1, L$
230 IF L$ <> "50%" THEN PRINT "percent failed: "; L$ : FAILS = FAILS + 1
232 LINE INPUT #1, L$
234 IF L$ <> "Sat Oct 24 2026 26|13:05:58 1p" THEN PRINT "dates failed: "; L$ : FAILS = FAILS + 1
240 CLOSE
250 DEL FT3.DAT
260 IF FAILS THEN PRINT "PRTUSING failed" ELSE PRINT "PRTUSING passed"
