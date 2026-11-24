REM Eratosthenes Sieve Prime Number Program in BASIC
REM From BYTE Magazine, September 1981, p.188
REM
REM See https://archive.org/details/byte-magazine-1981-09/page/n181
REM and https://archive.org/details/byte-magazine-1983-01/page/n291
REM
REM Change from the original source: DEFINT A-Z added to ensure FLAGS is
REM array of integers rather than doubles; the latter would be too large.
REM BASICA and GWBASIC would default to single-precision floats, but
REM BASIC-DOS supports only double-precision floats, so that would not be
REM a fair comparison.
0 DEFINT A-Z
1 SIZE = 8190
2 DIM FLAGS(8191)
3 PRINT "Only 1 iteration"
5 COUNT = 0
6 FOR I = 0 TO SIZE
7 FLAGS(I) = 1
8 NEXT I
9 FOR I = 0 TO SIZE
10 IF FLAGS(I) = 0 THEN 18
11 PRIME = I+I + 3
12 K = I + PRIME
13 IF K > SIZE THEN 17
14 FLAGS(K) = 0
15 K = K + PRIME
16 GOTO 13
17 COUNT = COUNT + 1
18 NEXT I
19 PRINT COUNT," PRIMES"
